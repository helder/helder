package helder.async;

#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
import haxe.Exception;
import haxe.io.Bytes;
import hxmc.NativeSsl;
import hxmc.unsafe.*;
import hxmc.I64;
import helder.async.Stream.Source;
import helder.async.Stream.Sink;

// TLS on a Socket by mbedtls (hxmc's runtime has it, on every native
// target): where the platform has no TLS of its own to use (Linux), and for
// a test's server. mbedtls reads and writes two buffers of its own (malloc'ed:
// its callbacks run without the GC) instead of the socket, answering "want
// read" or "want write" when they run dry or fill; the coroutines here move
// the bytes between them and the socket, so the handshake, reads and writes
// suspend on the loop as a Socket's do and never block its thread. A
// client checks the server's certificate against the system's roots (or
// the CA given) and its name; a server presents its certificate and key.
//
//   var tls = TlsSocket.client(Socket.connect("example.com", 443), "example.com");
//   tls.writeString("GET / HTTP/1.1\r\nhost: example.com\r\nconnection: close\r\n\r\n");
//   var page = new Reader(tls).readAll();
@:hxmc.unsafe(gc)
class TlsSocket implements Source implements Sink {
	// (mbedtls 2.28's)
	static inline var WANT_READ = -0x6900;
	static inline var WANT_WRITE = -0x6880;
	static inline var CLOSE_NOTIFY = -0x7880;
	// (a record is at most 16 KiB and some; a buffer holds two)
	static inline var CAP = 36 * 1024;
	// (the context's layout: the incoming buffer, its length and read position; the outgoing, its length)
	static inline var IN = 0;
	static inline var IN_LEN = 8;
	static inline var IN_POS = 12;
	static inline var OUT = 16;
	static inline var OUT_LEN = 24;
	static inline var SIZE = 32;

	public final socket:Socket;
	// (mbedtls's contexts, hxmc's handles: they free themselves when collected)
	final conf:Dynamic;
	final ssl:Dynamic;
	final ctx:Ptr;
	final chunk = Bytes.alloc(CAP);
	var eof = false;
	var closed = false;

	function new(socket:Socket, conf:Dynamic) {
		this.socket = socket;
		this.conf = conf;
		ctx = LibC.malloc(SIZE);
		Mem.setPtr(ctx, IN, LibC.malloc(CAP));
		Mem.setPtr(ctx, OUT, LibC.malloc(CAP));
		Mem.setI32(ctx, IN_LEN, 0);
		Mem.setI32(ctx, IN_POS, 0);
		Mem.setI32(ctx, OUT_LEN, 0);
		ssl = NativeSsl.sslInit();
		check(NativeSsl.sslSetup(ssl, conf));
		Tls.mbedtls_ssl_set_bio(raw(ssl), ctx, Callback.addr(bioWrite), Callback.addr(bioRead), Ptr.nil());
	}

	// a client's TLS on s: its handshake done, the server's certificate checked for host (ca: the roots trusted, else the system's)
	@:coroutine public static function client(s:Socket, host:String, ?ca:sys.ssl.Certificate):TlsSocket {
		var conf = config(false);
		NativeSsl.confCaChain(conf, @:privateAccess (ca ?? sys.ssl.Certificate.loadDefaults()).native);
		NativeSsl.confAuthmode(conf, 2); // MBEDTLS_SSL_VERIFY_REQUIRED
		var t = new TlsSocket(s, conf);
		check(NativeSsl.sslSetHostname(t.ssl, host));
		t.handshake();
		return t;
	}

	// a server's TLS on an accepted s, presenting cert and key
	@:coroutine public static function server(s:Socket, cert:sys.ssl.Certificate, key:sys.ssl.Key):TlsSocket {
		var conf = config(true);
		check(Tls.mbedtls_ssl_conf_own_cert(raw(conf), raw(@:privateAccess cert.native), raw(@:privateAccess key.native)));
		var t = new TlsSocket(s, conf);
		// (the certificate and key kept alive with the configuration)
		t.keep = [cert, key];
		t.handshake();
		return t;
	}

	var keep:Array<Dynamic> = [];

	static function config(server:Bool):Dynamic {
		var conf = NativeSsl.configInit();
		check(NativeSsl.configDefaults(conf, server ? 1 : 0, 0, 0));
		NativeSsl.confRng(conf, sys.ssl.Mbedtls.getDefaultCtrDrbg());
		return conf;
	}

	static inline function raw(o:Dynamic):Ptr
		return Mem.getPtr(Mem.addr(o), 0);

	static function check(code:Int) {
		if (code != 0) throw new Exception("TLS: " + NativeSsl.strerror(code));
	}

	@:coroutine function handshake() {
		while (true) {
			var r = Tls.mbedtls_ssl_handshake(raw(ssl));
			flush();
			if (r == 0) return;
			if (r == WANT_READ) {
				if (!fill()) throw new Exception("TLS: the connection closed in the handshake");
			} else if (r != WANT_WRITE) check(r);
		}
	}

	// up to len bytes into b at pos (0: the end of the stream)
	@:coroutine public function read(b:Bytes, pos:Int, len:Int):Int {
		if (len <= 0) return 0;
		while (true) {
			var n = len < CAP ? len : CAP;
			var p = LibC.malloc(n);
			var r = Tls.mbedtls_ssl_read(raw(ssl), p, n);
			if (r > 0) BytesPtr.copyIn(b, pos, p, r);
			LibC.free(p);
			flush();
			if (r > 0) return r;
			if (r == 0 || r == CLOSE_NOTIFY) return 0;
			if (r == WANT_READ) {
				if (!fill()) return 0;
			} else if (r != WANT_WRITE) check(r);
		}
	}

	@:coroutine public function write(b:Bytes, pos:Int, len:Int):Void {
		while (len > 0) {
			var n = len < CAP ? len : CAP;
			var p = LibC.malloc(n);
			LibC.memcpy(p, BytesPtr.of(b, pos, n), n);
			var r = Tls.mbedtls_ssl_write(raw(ssl), p, n);
			LibC.free(p);
			flush();
			if (r > 0) {
				pos += r;
				len -= r;
			} else if (r == WANT_READ) {
				if (!fill()) throw new Exception("TLS: the connection closed");
			} else if (r != WANT_WRITE) check(r);
		}
	}

	@:coroutine public function writeString(s:String):Void {
		var b = Bytes.ofString(s);
		write(b, 0, b.length);
	}

	// mbedtls's output written to the socket
	@:coroutine function flush() {
		var n = Mem.getI32(ctx, OUT_LEN);
		if (n == 0) return;
		BytesPtr.copyIn(chunk, 0, Mem.getPtr(ctx, OUT), n);
		Mem.setI32(ctx, OUT_LEN, 0);
		socket.write(chunk, 0, n);
	}

	// the socket's bytes into mbedtls's input: whether any came (false: the end)
	@:coroutine function fill():Bool {
		if (eof) return false;
		var inp = Mem.getPtr(ctx, IN), len = Mem.getI32(ctx, IN_LEN), at = Mem.getI32(ctx, IN_POS);
		// (what is read moved to the front)
		if (at > 0) {
			LibC.memmove(inp, inp.add(at), len - at);
			len -= at;
			Mem.setI32(ctx, IN_LEN, len);
			Mem.setI32(ctx, IN_POS, 0);
		}
		var n = socket.read(chunk, 0, CAP - len);
		if (n <= 0) {
			eof = true;
			return false;
		}
		LibC.memcpy(Mem.getPtr(ctx, IN).add(Mem.getI32(ctx, IN_LEN)), BytesPtr.of(chunk, 0, n), n);
		Mem.setI32(ctx, IN_LEN, Mem.getI32(ctx, IN_LEN) + n);
		return true;
	}

	// mbedtls's callbacks (no GC: inside its calls): the buffers, "want" when one is dry or full
	@:hxmc.callback @:hxmc.unsafe static function bioRead(c:Ptr, buf:Ptr, len:I64):Int {
		var at = Mem.getI32(c, IN_POS), have = Mem.getI32(c, IN_LEN) - at;
		if (have <= 0) return WANT_READ;
		var n = len.toInt() < have ? len.toInt() : have;
		LibC.memcpy(buf, Mem.getPtr(c, IN).add(at), n);
		Mem.setI32(c, IN_POS, at + n);
		return n;
	}

	@:hxmc.callback @:hxmc.unsafe static function bioWrite(c:Ptr, buf:Ptr, len:I64):Int {
		var used = Mem.getI32(c, OUT_LEN), room = CAP - used;
		if (room <= 0) return WANT_WRITE;
		var n = len.toInt() < room ? len.toInt() : room;
		LibC.memcpy(Mem.getPtr(c, OUT).add(used), buf, n);
		Mem.setI32(c, OUT_LEN, used + n);
		return n;
	}

	// the close told to the peer (close_notify), then abort
	@:coroutine public function close() {
		if (closed) return;
		try {
			Tls.mbedtls_ssl_close_notify(raw(ssl));
			flush();
		} catch (_) {}
		abort();
	}

	// the socket closed and the buffers freed, the peer told nothing
	public function abort() {
		if (closed) return;
		closed = true;
		socket.close();
		LibC.free(Mem.getPtr(ctx, IN));
		LibC.free(Mem.getPtr(ctx, OUT));
		LibC.free(ctx);
	}
}

// (the mbedtls calls hxmc's runtime has and its sys.ssl does not make: the BIO a context's, a server's certificate)
@:hxmc.c @:hxmc.fast private extern class Tls {
	static function mbedtls_ssl_set_bio(ssl:Ptr, ctx:Ptr, send:Ptr, recv:Ptr, recvTimeout:Ptr):Void;
	static function mbedtls_ssl_conf_own_cert(conf:Ptr, cert:Ptr, key:Ptr):Int;
	static function mbedtls_ssl_handshake(ssl:Ptr):Int;
	static function mbedtls_ssl_read(ssl:Ptr, buf:Ptr, len:I64):Int;
	static function mbedtls_ssl_write(ssl:Ptr, buf:Ptr, len:I64):Int;
	static function mbedtls_ssl_close_notify(ssl:Ptr):Int;
}
#end
