package helder.async.http.android;

#if (target.name == "hxmc" && (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64"))
import haxe.Exception;
import haxe.io.Bytes;
import helder.async.*;
import helder.async.http.Client.Reply;
import helder.async.http.Client.RequestOptions;
import helder.os.android.Jni;
import hxmc.unsafe.*;
import helder.async.Errors;

// Client.request on Android: java.net.HttpURLConnection (the system's TLS
// and certificates, the app's network security config: its cleartext rules
// and pins, the system's proxy). Its calls block, and Android allows no
// network on the main thread: each request runs on a thread of its own,
// attached to the VM for it (its own JNIEnv), and its reply is posted to the
// loop that asked. An error status is a reply (its error stream the body);
// a failure (no network, a refused certificate) the Java exception's text.
@:hxmc.unsafe(gc)
class Http {
	@:coroutine public static function request(url:String, options:Null<RequestOptions>):Reply {
		var headers = new StringBuf();
		var given = options?.headers ?? new Map();
		for (k => v in given)
			headers.add('$k\n$v\n');
		if (options?.contentType != null && !given.exists("content-type")) headers.add('content-type\n${options.contentType}\n');
		var body = options?.body ?? (options?.text != null ? Bytes.ofString(options.text) : null);
		var method = options?.method ?? "GET", head = headers.toString();
		var loop = Loop.current();
		var out:{reply:Null<Reply>, error:Null<String>} = Async.suspendCancellable(cont -> {
			var done = false;
			loop.hold();
			sys.thread.Thread.create(() -> {
				var r:{reply:Null<Reply>, error:Null<String>} = try {reply: fetch(url, method, head, body), error: null} catch (e:Exception) {reply: null, error: e.message};
				loop.post(() -> {
					loop.release();
					if (done) return;
					done = true;
					cont.resume(r, null);
				});
			});
			return _ -> done = true;
		});
		if (out.error != null) throw new Exception('$url: ${out.error}');
		return out.reply;
	}

	// (the request's thread: attached to the VM, the calls made, detached)
	static function fetch(url:String, method:String, headers:String, body:Null<Bytes>):Reply
		return Java.attached(env -> {
			var args:Ptr = LibC.malloc(64);
			try {
				var r = calls(env, args, url, method, headers, body);
				LibC.free(args);
				r;
			} catch (e:Exception) {
				LibC.free(args);
				throw Errors.kept(e);
			}
		});

	static function calls(env:Ptr, args:Ptr, url:String, verb:String, headers:String, body:Null<Bytes>):Reply {
		JniEnv.PushLocalFrame(env, 64);
		try {
			function cls(name:String):Ptr
				return Java.cls(env, name);
			function method(c:Ptr, name:String, sig:String):Ptr
				return Java.method(env, c, name, sig);
			function str(s:String):Ptr
				return Java.str(env, s);
			function set(a:Int64, b:Int64 = 0):Ptr {
				Mem.setI64(args, 0, a);
				Mem.setI64(args, 8, b);
				return args;
			}
			function check()
				Java.check(env);
			var urlCls = cls("java/net/URL"), connCls = cls("java/net/HttpURLConnection");
			var u = JniEnv.NewObjectA(env, urlCls, method(urlCls, "<init>", "(Ljava/lang/String;)V"), set(str(url).toI64()));
			check();
			var conn = JniEnv.CallObjectMethodA(env, u, method(urlCls, "openConnection", "()Ljava/net/URLConnection;"), args);
			check();
			JniEnv.CallVoidMethodA(env, conn, method(connCls, "setRequestMethod", "(Ljava/lang/String;)V"), set(str(verb).toI64()));
			check();
			JniEnv.CallVoidMethodA(env, conn, method(connCls, "setConnectTimeout", "(I)V"), set(30000));
			JniEnv.CallVoidMethodA(env, conn, method(connCls, "setReadTimeout", "(I)V"), set(30000));
			var lines = headers.split("\n"), property = method(connCls, "setRequestProperty", "(Ljava/lang/String;Ljava/lang/String;)V");
			var i = 0;
			while (i + 1 < lines.length) {
				JniEnv.CallVoidMethodA(env, conn, property, set(str(lines[i]).toI64(), str(lines[i + 1]).toI64()));
				check();
				i += 2;
			}
			if (body != null && body.length > 0) {
				JniEnv.CallVoidMethodA(env, conn, method(connCls, "setDoOutput", "(Z)V"), set(1));
				JniEnv.CallVoidMethodA(env, conn, method(connCls, "setFixedLengthStreamingMode", "(I)V"), set(body.length));
				var os = JniEnv.CallObjectMethodA(env, conn, method(connCls, "getOutputStream", "()Ljava/io/OutputStream;"), args);
				check();
				var arr = JniEnv.NewByteArray(env, body.length), p = LibC.malloc(body.length);
				LibC.memcpy(p, BytesPtr.of(body, 0, body.length), body.length);
				JniEnv.SetByteArrayRegion(env, arr, 0, body.length, p);
				LibC.free(p);
				var osCls = cls("java/io/OutputStream");
				JniEnv.CallVoidMethodA(env, os, method(osCls, "write", "([B)V"), set(arr.toI64()));
				check();
				JniEnv.CallVoidMethodA(env, os, method(osCls, "close", "()V"), args);
				check();
			}
			var status = JniEnv.CallIntMethodA(env, conn, method(connCls, "getResponseCode", "()I"), args);
			check();
			// (the headers: index 0 the status line, its key null)
			var map = new Map<String, String>(), keyAt = method(connCls, "getHeaderFieldKey", "(I)Ljava/lang/String;"),
				fieldAt = method(connCls, "getHeaderField", "(I)Ljava/lang/String;");
			var n = 0;
			while (n < 200) {
				var v = JniEnv.CallObjectMethodA(env, conn, fieldAt, set(n));
				check();
				if (v.isNull()) break;
				var k = JniEnv.CallObjectMethodA(env, conn, keyAt, set(n));
				if (!k.isNull()) map.set(Java.text(env, k).toLowerCase(), Java.text(env, v));
				JniEnv.DeleteLocalRef(env, v);
				if (!k.isNull()) JniEnv.DeleteLocalRef(env, k);
				n++;
			}
			// (the body: the error stream for an error status, which may be none)
			var stream = JniEnv.CallObjectMethodA(env, conn, method(connCls, status >= 400 ? "getErrorStream" : "getInputStream", "()Ljava/io/InputStream;"), args);
			if (JniEnv.ExceptionCheck(env) != 0) {
				JniEnv.ExceptionClear(env);
				stream = Ptr.nil();
			}
			var all = new haxe.io.BytesBuffer();
			if (!stream.isNull()) {
				var isCls = cls("java/io/InputStream"), read = method(isCls, "read", "([B)I");
				var buf = JniEnv.NewByteArray(env, 16384), tmp = LibC.malloc(16384);
				while (true) {
					var got = JniEnv.CallIntMethodA(env, stream, read, set(buf.toI64()));
					check();
					if (got <= 0) break;
					JniEnv.GetByteArrayRegion(env, buf, 0, got, tmp);
					var b = Bytes.alloc(got);
					BytesPtr.copyIn(b, 0, tmp, got);
					all.add(b);
				}
				LibC.free(tmp);
				JniEnv.CallVoidMethodA(env, stream, method(isCls, "close", "()V"), args);
				JniEnv.ExceptionClear(env);
			}
			JniEnv.CallVoidMethodA(env, conn, method(connCls, "disconnect", "()V"), args);
			JniEnv.ExceptionClear(env);
			JniEnv.PopLocalFrame(env, Ptr.nil());
			return new Reply(status, map, all.getBytes());
		} catch (e:Exception) {
			JniEnv.PopLocalFrame(env, Ptr.nil());
			throw Errors.kept(e);
		}
	}}

// WebSocket.open's connection on Android: a java.net.Socket, with an
// SSLSocket of SSLSocketFactory.getDefault() on it for wss (the system's TLS
// and certificates; the name checked by HttpsURLConnection's verifier,
// which an SSLSocket does not do itself), as a Source and a Sink that
// WebSocket frames over. Android allows no network on the main thread: the
// socket has two threads attached to the VM. The reader reads a chunk ahead,
// posts it to the loop and waits until it is taken (a cancelled read loses
// nothing); the writer runs the connect, each write and the close in turn.
@:hxmc.unsafe(gc)
class AndroidSocket implements helder.async.Stream.Source implements helder.async.Stream.Sink {
	final writer = new Worker();
	// (a read asked of the reader's thread: 1, or 0 to end it)
	final credits = new sys.thread.Deque<Int>();
	final loop = Loop.current();
	// (global references, the threads'; deleted by the last to end)
	var socket = Ptr.nil();
	var input = Ptr.nil();
	var output = Ptr.nil();
	var left = 2;
	final lock = new sys.thread.Mutex();
	// (the reader's last chunk, empty at the end, or its failure; a read waiting for it)
	var chunk:Null<Bytes> = null;
	var failure:Null<String> = null;
	var waiting:Null<() -> Void> = null;
	var closed = false;

	function new() {
		writer.start(end);
		loop.hold();
		sys.thread.Thread.create(() -> Java.attached(env -> {
			while (credits.pop(true) > 0) {
				var r:{chunk:Null<Bytes>, error:Null<String>} = try {chunk: receive(env), error: null} catch (e:Exception) {chunk: null, error: e.message};
				loop.post(() -> {
					chunk = r.chunk;
					failure = r.error;
					if (waiting != null) waiting();
				});
				if (r.chunk == null || r.chunk.length == 0) break;
			}
			end(env);
			loop.post(loop.release);
			null;
		}));
	}

	@:coroutine public static function connect(host:String, port:Int, secure:Bool):AndroidSocket {
		var s = new AndroidSocket();
		try {
			s.writer.run(env -> s.open(env, host, port, secure));
		} catch (e:Exception) {
			s.close();
			throw new Exception('$host:$port: ${e.message}');
		}
		s.credits.add(1);
		return s;
	}

	@:coroutine public function read(b:Bytes, pos:Int, len:Int):Int {
		if (chunk == null && failure == null && !closed) Async.suspendCancellable(cont -> {
			waiting = () -> {
				waiting = null;
				cont.resume(null, null);
			};
			return _ -> waiting = null;
		});
		var got = chunk;
		if (got == null || got.length == 0) {
			if (failure != null && !closed) throw new Exception(failure);
			return 0;
		}
		var n = got.length < len ? got.length : len;
		b.blit(pos, got, 0, n);
		if (n < got.length) chunk = got.sub(n, got.length - n) else {
			chunk = null;
			credits.add(1);
		}
		return n;
	}

	@:coroutine public function write(b:Bytes, pos:Int, len:Int):Void {
		if (closed) throw new Exception("closed");
		var data = b.sub(pos, len);
		writer.run(env -> send(env, data));
	}

	// (the socket closed on the writer's thread: a read waiting on the reader's ends)
	public function close() {
		if (closed) return;
		closed = true;
		writer.add(env -> {
			if (!socket.isNull()) {
				JniEnv.CallVoidMethodA(env, socket, Java.method(env, Java.cls(env, "java/net/Socket"), "close", "()V"), Ptr.nil());
				JniEnv.ExceptionClear(env);
			}
		});
		writer.stop();
		credits.add(0);
		if (waiting != null) waiting();
	}

	function end(env:Ptr) {
		lock.acquire();
		var last = --left == 0;
		lock.release();
		if (!last) return;
		for (r in [socket, input, output])
			if (!r.isNull()) JniEnv.DeleteGlobalRef(env, r);
	}

	function open(env:Ptr, host:String, port:Int, secure:Bool):Null<Bytes> {
		JniEnv.PushLocalFrame(env, 32);
		var args:Ptr = LibC.malloc(32);
		try {
			function set(a:Int64, b:Int64 = 0, c:Int64 = 0, d:Int64 = 0):Ptr {
				Mem.setI64(args, 0, a);
				Mem.setI64(args, 8, b);
				Mem.setI64(args, 16, c);
				Mem.setI64(args, 24, d);
				return args;
			}
			var socketCls = Java.cls(env, "java/net/Socket"), addrCls = Java.cls(env, "java/net/InetSocketAddress");
			var s = JniEnv.NewObjectA(env, socketCls, Java.method(env, socketCls, "<init>", "()V"), args);
			Java.check(env);
			var addr = JniEnv.NewObjectA(env, addrCls, Java.method(env, addrCls, "<init>", "(Ljava/lang/String;I)V"), set(Java.str(env, host).toI64(), port));
			Java.check(env);
			JniEnv.CallVoidMethodA(env, s, Java.method(env, socketCls, "connect", "(Ljava/net/SocketAddress;I)V"), set(addr.toI64(), 30000));
			Java.check(env);
			JniEnv.CallVoidMethodA(env, s, Java.method(env, socketCls, "setTcpNoDelay", "(Z)V"), set(1));
			if (secure) {
				var plain = s;
				function fail(e:Exception) {
					JniEnv.ExceptionClear(env);
					JniEnv.CallVoidMethodA(env, plain, Java.method(env, socketCls, "close", "()V"), args);
					JniEnv.ExceptionClear(env);
					throw e;
				}
				try {
					var factoryCls = Java.cls(env, "javax/net/ssl/SSLSocketFactory"), sslCls = Java.cls(env, "javax/net/ssl/SSLSocket");
					var factory = JniEnv.CallStaticObjectMethodA(env, factoryCls, Java.staticMethod(env, factoryCls, "getDefault", "()Ljavax/net/SocketFactory;"), args);
					Java.check(env);
					s = JniEnv.CallObjectMethodA(env, factory, Java.method(env, factoryCls, "createSocket", "(Ljava/net/Socket;Ljava/lang/String;IZ)Ljava/net/Socket;"),
						set(plain.toI64(), Java.str(env, host).toI64(), port, 1));
					Java.check(env);
					JniEnv.CallVoidMethodA(env, s, Java.method(env, sslCls, "startHandshake", "()V"), args);
					Java.check(env);
					var session = JniEnv.CallObjectMethodA(env, s, Java.method(env, sslCls, "getSession", "()Ljavax/net/ssl/SSLSession;"), args);
					var httpsCls = Java.cls(env, "javax/net/ssl/HttpsURLConnection"), verifierCls = Java.cls(env, "javax/net/ssl/HostnameVerifier");
					var verifier = JniEnv.CallStaticObjectMethodA(env, httpsCls, Java.staticMethod(env, httpsCls, "getDefaultHostnameVerifier", "()Ljavax/net/ssl/HostnameVerifier;"), args);
					Java.check(env);
					var ok = JniEnv.CallBooleanMethodA(env, verifier, Java.method(env, verifierCls, "verify", "(Ljava/lang/String;Ljavax/net/ssl/SSLSession;)Z"),
						set(Java.str(env, host).toI64(), session.toI64()));
					Java.check(env);
					if (ok == 0) throw new Exception('the certificate is not for $host');
				} catch (e:Exception) fail(e);
			}
			var input = JniEnv.CallObjectMethodA(env, s, Java.method(env, socketCls, "getInputStream", "()Ljava/io/InputStream;"), args);
			Java.check(env);
			var output = JniEnv.CallObjectMethodA(env, s, Java.method(env, socketCls, "getOutputStream", "()Ljava/io/OutputStream;"), args);
			Java.check(env);
			socket = JniEnv.NewGlobalRef(env, s);
			this.input = JniEnv.NewGlobalRef(env, input);
			this.output = JniEnv.NewGlobalRef(env, output);
		} catch (e:Exception) {
			LibC.free(args);
			JniEnv.PopLocalFrame(env, Ptr.nil());
			throw Errors.kept(e);
		}
		LibC.free(args);
		JniEnv.PopLocalFrame(env, Ptr.nil());
		return null;
	}

	// (the reader's thread: what one read gives, empty at the end)
	function receive(env:Ptr):Bytes {
		if (input.isNull()) return Bytes.alloc(0);
		JniEnv.PushLocalFrame(env, 8);
		var args:Ptr = LibC.malloc(8), arr = JniEnv.NewByteArray(env, 16384);
		Mem.setI64(args, 0, arr.toI64());
		var got = JniEnv.CallIntMethodA(env, input, Java.method(env, Java.cls(env, "java/io/InputStream"), "read", "([B)I"), args);
		LibC.free(args);
		try Java.check(env) catch (e:Exception) {
			JniEnv.PopLocalFrame(env, Ptr.nil());
			throw Errors.kept(e);
		}
		var b = Bytes.alloc(got > 0 ? got : 0);
		if (got > 0) {
			var tmp = LibC.malloc(got);
			JniEnv.GetByteArrayRegion(env, arr, 0, got, tmp);
			BytesPtr.copyIn(b, 0, tmp, got);
			LibC.free(tmp);
		}
		JniEnv.PopLocalFrame(env, Ptr.nil());
		return b;
	}

	// (the writer's thread: the bytes written, flushed)
	function send(env:Ptr, data:Bytes):Null<Bytes> {
		if (output.isNull()) throw new Exception("not connected");
		JniEnv.PushLocalFrame(env, 8);
		var args:Ptr = LibC.malloc(8), arr = JniEnv.NewByteArray(env, data.length);
		if (data.length > 0) {
			var tmp = LibC.malloc(data.length);
			LibC.memcpy(tmp, BytesPtr.of(data, 0, data.length), data.length);
			JniEnv.SetByteArrayRegion(env, arr, 0, data.length, tmp);
			LibC.free(tmp);
		}
		Mem.setI64(args, 0, arr.toI64());
		var osCls = Java.cls(env, "java/io/OutputStream");
		JniEnv.CallVoidMethodA(env, output, Java.method(env, osCls, "write", "([B)V"), args);
		if (JniEnv.ExceptionCheck(env) == 0) JniEnv.CallVoidMethodA(env, output, Java.method(env, osCls, "flush", "()V"), args);
		LibC.free(args);
		try Java.check(env) catch (e:Exception) {
			JniEnv.PopLocalFrame(env, Ptr.nil());
			throw Errors.kept(e);
		}
		JniEnv.PopLocalFrame(env, Ptr.nil());
		return null;
	}
}

// (a thread attached to the VM for its life, running what is added in turn;
// run: a call there, its result posted to the loop)
@:hxmc.unsafe(gc)
private class Worker {
	final jobs = new sys.thread.Deque<Null<Ptr->Void>>();

	public function new() {}

	public function start(end:Ptr->Void)
		sys.thread.Thread.create(() -> Java.attached(env -> {
			var job;
			while ((job = jobs.pop(true)) != null)
				job(env);
			end(env);
			null;
		}));

	public function add(job:Ptr->Void)
		jobs.add(job);

	public function stop()
		jobs.add(null);

	@:coroutine public function run(f:Ptr->Null<Bytes>):Null<Bytes> {
		var loop = Loop.current();
		var out:{value:Null<Bytes>, error:Null<String>} = Async.suspendCancellable(cont -> {
			var done = false;
			loop.hold();
			jobs.add(env -> {
				var r:{value:Null<Bytes>, error:Null<String>} = try {value: f(env), error: null} catch (e:Exception) {value: null, error: e.message};
				loop.post(() -> {
					loop.release();
					if (done) return;
					done = true;
					cont.resume(r, null);
				});
			});
			return _ -> done = true;
		});
		if (out.error != null) throw new Exception(out.error);
		return out.value;
	}
}

// (JNI's calls on an env of this thread's)
@:hxmc.unsafe(gc)
private class Java {
	// (f on this thread attached to the VM: detached after, if it was not before)
	public static function attached<T>(f:Ptr->T):T {
		var vm = Mem.getPtr(helder.os.android.Activity.activity, 8), out:Ptr<Ptr> = LibC.malloc(8);
		var attach = JavaVm.GetEnv(vm, out, 0x10006) != 0;
		if (attach && JavaVm.AttachCurrentThread(vm, out, Ptr.nil()) != 0) {
			LibC.free(out);
			throw new Exception("no VM for this thread");
		}
		var env = out.value;
		LibC.free(out);
		try {
			var r = f(env);
			if (attach) JavaVm.DetachCurrentThread(vm);
			return r;
		} catch (e:Exception) {
			if (attach) JavaVm.DetachCurrentThread(vm);
			throw Errors.kept(e);
		}
	}

	public static function cls(env:Ptr, name:String):Ptr
		return Arena.scopedValue(a -> JniEnv.FindClass(env, a.cstring(name)));

	public static function method(env:Ptr, c:Ptr, name:String, sig:String):Ptr
		return Arena.scopedValue(a -> JniEnv.GetMethodID(env, c, a.cstring(name), a.cstring(sig)));

	public static function staticMethod(env:Ptr, c:Ptr, name:String, sig:String):Ptr
		return Arena.scopedValue(a -> JniEnv.GetStaticMethodID(env, c, a.cstring(name), a.cstring(sig)));

	public static function str(env:Ptr, s:String):Ptr {
		// (UTF-16: a code point past the BMP as its surrogates)
		var units = [];
		for (c in new haxe.iterators.StringIteratorUnicode(s))
			if (c < 0x10000) units.push(c) else {
				units.push(0xD800 + ((c - 0x10000) >> 10));
				units.push(0xDC00 + ((c - 0x10000) & 0x3FF));
			}
		var p:Ptr<UInt16> = LibC.malloc(2 * units.length + 2);
		for (i in 0...units.length)
			p[i] = units[i];
		var j = JniEnv.NewString(env, p, units.length);
		LibC.free(p);
		return j;
	}

	// (a Java exception thrown after a call: its text)
	public static function check(env:Ptr) {
		if (JniEnv.ExceptionCheck(env) == 0) return;
		var t = JniEnv.ExceptionOccurred(env);
		JniEnv.ExceptionClear(env);
		var text = t.isNull() ? "failed" : Java.text(env, JniEnv.CallObjectMethodA(env, t, method(env, cls(env, "java/lang/Throwable"), "toString", "()Ljava/lang/String;"), Ptr.nil()));
		throw new Exception(text);
	}

	// (a java.lang.String's text, by its UTF-16 units)
	public static function text(env:Ptr, s:Ptr):String {
		if (s.isNull()) return "";
		var n = JniEnv.GetStringLength(env, s);
		var p:Ptr<UInt16> = LibC.malloc(2 * n + 2);
		JniEnv.GetStringRegion(env, s, 0, n, p);
		var b = new StringBuf(), i = 0;
		while (i < n) {
			var c:Int = p[i++];
			if (c >= 0xD800 && c < 0xDC00 && i < n) c = 0x10000 + ((c - 0xD800) << 10) + ((p[i++] : Int) - 0xDC00);
			b.addChar(c);
		}
		LibC.free(p);
		return b.toString();
	}
}
#end
