package helder.async.http;

#if (target.name == "hxmc" && (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64"))
import haxe.Exception;
import haxe.io.Bytes;
import helder.async.*;
import helder.async.http.Client.Reply;
import helder.async.http.Client.RequestOptions;
import helder.os.android.Jni;
import hxmc.unsafe.*;

// Client.request on Android: java.net.HttpURLConnection (the system's TLS
// and certificates, the app's network security config: its cleartext rules
// and pins, the system's proxy). Its calls block, and Android allows no
// network on the main thread: each request runs on a thread of its own,
// attached to the VM for it (its own JNIEnv), and its reply is posted to the
// loop that asked. An error status is a reply (its error stream the body);
// a failure (no network, a refused certificate) the Java exception's text.
@:hxmc.unsafe(gc)
class AndroidHttp {
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
	static function fetch(url:String, method:String, headers:String, body:Null<Bytes>):Reply {
		var vm = Mem.getPtr(helder.os.android.Activity.activity, 8), out:Ptr<Ptr> = LibC.malloc(8);
		var attached = JavaVm.GetEnv(vm, out, 0x10006) != 0;
		if (attached && JavaVm.AttachCurrentThread(vm, out, Ptr.nil()) != 0) {
			LibC.free(out);
			throw new Exception("no VM for the request's thread");
		}
		var env = out.value;
		LibC.free(out);
		var args:Ptr = LibC.malloc(64);
		try {
			var r = calls(env, args, url, method, headers, body);
			LibC.free(args);
			if (attached) JavaVm.DetachCurrentThread(vm);
			return r;
		} catch (e:Exception) {
			LibC.free(args);
			if (attached) JavaVm.DetachCurrentThread(vm);
			throw e;
		}
	}

	static function calls(env:Ptr, args:Ptr, url:String, verb:String, headers:String, body:Null<Bytes>):Reply {
		JniEnv.PushLocalFrame(env, 64);
		try {
			function cls(name:String):Ptr
				return Arena.scopedValue(a -> JniEnv.FindClass(env, a.cstring(name)));
			function method(c:Ptr, name:String, sig:String):Ptr
				return Arena.scopedValue(a -> JniEnv.GetMethodID(env, c, a.cstring(name), a.cstring(sig)));
			function str(s:String):Ptr {
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
			function set(a:Int64, b:Int64 = 0):Ptr {
				Mem.setI64(args, 0, a);
				Mem.setI64(args, 8, b);
				return args;
			}
			function check() {
				if (JniEnv.ExceptionCheck(env) == 0) return;
				var t = JniEnv.ExceptionOccurred(env);
				JniEnv.ExceptionClear(env);
				var text = t.isNull() ? "failed" : jstring(env, JniEnv.CallObjectMethodA(env, t, method(cls("java/lang/Throwable"), "toString", "()Ljava/lang/String;"), args));
				throw new Exception(text);
			}
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
				if (!k.isNull()) map.set(jstring(env, k).toLowerCase(), jstring(env, v));
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
			throw e;
		}
	}

	// (a java.lang.String's text, by its UTF-16 units)
	static function jstring(env:Ptr, s:Ptr):String {
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
