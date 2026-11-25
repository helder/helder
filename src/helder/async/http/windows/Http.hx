package helder.async.http.windows;

import helder.async.http.Client;
#if (target.name == "hxmc" && (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64"))
import haxe.Exception;
import haxe.io.Bytes;
import helder.async.*;
import helder.async.http.Client.Reply;
import helder.async.http.Client.RequestOptions;
import hxmc.unsafe.*;

// Client.request on Windows: WinHTTP (the system's TLS, Schannel, its
// certificate store and proxies, HTTP/2), asynchronous: its callbacks come on
// the system's threads, without the GC, and only note each step's end (an
// event, a number, an error) in a context of malloc'ed memory; the
// coroutine here polls it on the loop's turns (held: at most every 10 ms on
// Windows) and takes the next step: send, receive the response, its status
// and headers, then the body as it comes.
@:hxmc.unsafe(gc)
class Http {
	static var session = Ptr.nil();

	// (the context: the last step's end, its number, its error)
	static inline var EVENT = 0;
	static inline var INFO = 4;
	static inline var ERROR = 8;
	static inline var SIZE = 16;

	// (WINHTTP_CALLBACK_STATUS_*)
	static inline var SENT = 0x00400000;
	static inline var HEADERS = 0x00020000;
	static inline var DATA = 0x00040000;
	static inline var READ = 0x00080000;
	static inline var FAILED = 0x00200000;

	@:coroutine public static function request(url:String, options:Null<RequestOptions>):Reply {
		var u = Client.Url.parse(url);
		var method = options?.method ?? "GET";
		var conn = Arena.scopedValue(a -> WinHttpApi.WinHttpConnect(open(url), a.wstring(u.host), u.port, 0));
		if (conn.isNull()) throw new Exception('$url: WinHTTP did not connect');
		// (WINHTTP_FLAG_SECURE)
		var req = Arena.scopedValue(a -> WinHttpApi.WinHttpOpenRequest(conn, a.wstring(method), a.wstring(u.path), Ptr.nil(), Ptr.nil(), Ptr.nil(), u.secure ? 0x00800000 : 0));
		if (req.isNull()) {
			WinHttpApi.WinHttpCloseHandle(conn);
			throw new Exception('$url: WinHTTP did not open the request');
		}
		var ctx = LibC.malloc(SIZE);
		LibC.memset(ctx, 0, SIZE);
		// (the completions only: no handle's closing after the context is gone)
		WinHttpApi.WinHttpSetStatusCallback(req, Callback.addr(callback), SENT | HEADERS | DATA | READ | FAILED, 0);
		var headers = new StringBuf();
		var given = options?.headers ?? new Map();
		for (k => v in given)
			headers.add('$k: $v\r\n');
		if (options?.contentType != null && !given.exists("content-type")) headers.add('content-type: ${options.contentType}\r\n');
		var body = options?.body ?? (options?.text != null ? Bytes.ofString(options.text) : Bytes.alloc(0));
		// (the body WinHTTP's until the request ends: malloc'ed)
		var data = body.length > 0 ? LibC.malloc(body.length) : Ptr.nil();
		if (body.length > 0) LibC.memcpy(data, BytesPtr.of(body, 0, body.length), body.length);
		var chunks = new haxe.io.BytesBuffer(), status = 0, map = new Map<String, String>();
		inline function close() {
			WinHttpApi.WinHttpSetStatusCallback(req, Ptr.nil(), 0, 0);
			WinHttpApi.WinHttpCloseHandle(req);
			WinHttpApi.WinHttpCloseHandle(conn);
			if (!data.isNull()) LibC.free(data);
			LibC.free(ctx);
		}
		try {
			var h = headers.toString();
			var sent = Arena.scopedValue(a -> WinHttpApi.WinHttpSendRequest(req, h == "" ? Ptr.nil() : a.wstring(h), -1, data, body.length, body.length, ctx));
			if (!sent) throw new Exception('$url: WinHTTP did not send (${Win32.GetLastError()})');
			await(ctx, SENT, url);
			if (!WinHttpApi.WinHttpReceiveResponse(req, Ptr.nil())) throw new Exception('$url: WinHTTP did not receive (${Win32.GetLastError()})');
			await(ctx, HEADERS, url);
			status = statusOf(req);
			map = headersOf(req);
			while (true) {
				if (!WinHttpApi.WinHttpQueryDataAvailable(req, Ptr.nil())) throw new Exception('$url: WinHTTP did not read (${Win32.GetLastError()})');
				await(ctx, DATA, url);
				var n = Mem.getI32(ctx, INFO);
				if (n <= 0) break;
				var buf = LibC.malloc(n);
				if (!WinHttpApi.WinHttpReadData(req, buf, n, Ptr.nil())) {
					LibC.free(buf);
					throw new Exception('$url: WinHTTP did not read (${Win32.GetLastError()})');
				}
				await(ctx, READ, url);
				var got = Mem.getI32(ctx, INFO), b = Bytes.alloc(got);
				if (got > 0) BytesPtr.copyIn(b, 0, buf, got);
				LibC.free(buf);
				chunks.add(b);
				if (got == 0) break;
			}
		} catch (e:Exception) {
			close();
			throw e;
		}
		close();
		return new Reply(status, map, chunks.getBytes());
	}

	static function open(url:String):Ptr {
		if (!session.isNull()) return session;
		// (WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY, Windows 8.1; else the default's; WINHTTP_FLAG_ASYNC)
		session = Arena.scopedValue(a -> WinHttpApi.WinHttpOpen(a.wstring("helder"), 4, Ptr.nil(), Ptr.nil(), 0x10000000));
		if (session.isNull()) session = Arena.scopedValue(a -> WinHttpApi.WinHttpOpen(a.wstring("helder"), 0, Ptr.nil(), Ptr.nil(), 0x10000000));
		if (session.isNull()) throw new Exception('$url: WinHTTP did not open');
		return session;
	}

	// (the step's end, polled on the loop's turns: its event taken; a failure thrown)
	@:coroutine static function await(ctx:Ptr, event:Int, url:String) {
		var loop = Loop.current();
		loop.hold();
		var e = Async.suspendCancellable(cont -> {
			var done = false;
			loop.check(() -> {
				if (done) return true;
				var got = Atomic.load32(ctx.add(EVENT));
				if (got == 0) return false;
				Atomic.store32(ctx.add(EVENT), 0);
				done = true;
				cont.resume(got, null);
				return true;
			});
			return _ -> done = true;
		});
		loop.release();
		if (e == FAILED) throw new Exception('$url: WinHTTP failed (${Mem.getI32(ctx, ERROR)})');
		if (e != event) throw new Exception('$url: WinHTTP said $e, not $event');
	}

	// (WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER)
	static function statusOf(req:Ptr):Int {
		var v = LibC.malloc(8);
		Mem.setI32(v, 0, 0);
		Mem.setI32(v, 4, 4);
		WinHttpApi.WinHttpQueryHeaders(req, 19 | 0x20000000, Ptr.nil(), v, v.add(4), Ptr.nil());
		var s = Mem.getI32(v, 0);
		LibC.free(v);
		return s;
	}

	// (WINHTTP_QUERY_RAW_HEADERS_CRLF: its length asked first; the status line skipped)
	static function headersOf(req:Ptr):Map<String, String> {
		var map = new Map<String, String>(), len = LibC.malloc(4);
		Mem.setI32(len, 0, 0);
		WinHttpApi.WinHttpQueryHeaders(req, 22, Ptr.nil(), Ptr.nil(), len, Ptr.nil());
		var n = Mem.getI32(len, 0);
		if (n > 0) {
			var buf:Ptr<UInt16> = LibC.malloc(n + 2);
			if (WinHttpApi.WinHttpQueryHeaders(req, 22, Ptr.nil(), buf, len, Ptr.nil())) {
				var text = new StringBuf(), chars = Std.int(Mem.getI32(len, 0) / 2);
				for (i in 0...chars)
					text.addChar(buf[i]);
				var lines = text.toString().split("\r\n");
				for (i in 1...lines.length) {
					var colon = lines[i].indexOf(":");
					if (colon > 0) map.set(StringTools.trim(lines[i].substr(0, colon)).toLowerCase(), StringTools.trim(lines[i].substr(colon + 1)));
				}
			}
			LibC.free(buf);
		}
		LibC.free(len);
		return map;
	}

	// (the system's threads, no GC: the step's end noted, the event last)
	@:hxmc.callback @:hxmc.noGc static function callback(handle:Ptr, ctx:Ptr, status:Int, info:Ptr, infoLength:Int):Void {
		if (ctx.isNull()) return;
		if (status == DATA) Mem.setI32(ctx, INFO, Mem.getI32(info, 0));
		else if (status == READ) Mem.setI32(ctx, INFO, infoLength);
		// (WINHTTP_ASYNC_RESULT: its dwError after the DWORD_PTR)
		else if (status == FAILED) Mem.setI32(ctx, ERROR, Mem.getI32(info, 8));
		Atomic.store32(ctx.add(EVENT), status);
	}
}

// WebSocket.open on Windows: WinHTTP's (the upgrade a request with
// WINHTTP_OPTION_UPGRADE_TO_WEB_SOCKET, then its WebSocket calls: framing,
// pings and the close handshake are its own). Completions are noted as the
// request's are, in a slot of the context each for receive, send and
// shutdown, so a send runs while a receive waits; the context and the
// receive buffer, which WinHTTP may still write, are freed once the
// handle's closing has come.
@:hxmc.unsafe(gc)
@:access(helder.async.http.windows.Http)
class WinWebSocket {
	// (the context: the upgrade request's steps, then a slot for each operation)
	static inline var RECEIVE = 16;
	static inline var SEND = 32;
	static inline var SHUTDOWN = 48;
	static inline var CLOSING = 64;
	static inline var SIZE = 80;
	// (within a slot, beside Http's EVENT, INFO and ERROR)
	static inline var TYPE = 12;
	static inline var BUFFER = 65536;

	// (WINHTTP_CALLBACK_STATUS_*)
	static inline var READ = 0x00080000;
	static inline var WRITE = 0x00100000;
	static inline var FAILED = 0x00200000;
	static inline var DOWN = 0x04000000;
	static inline var CLOSED = 0x00000800;

	public var closed(default, null) = false;
	final conn:Ptr;
	final ws:Ptr;
	final ctx:Ptr;
	final buf:Ptr;
	// (the last send's bytes, WinHTTP's until it completes)
	var sent = Ptr.nil();
	var reading = false;
	var freed = false;
	final lock = new Lock();

	function new(conn, ws, ctx) {
		this.conn = conn;
		this.ws = ws;
		this.ctx = ctx;
		buf = LibC.malloc(BUFFER);
	}

	@:coroutine public static function open(url:String):WinWebSocket {
		var u = Client.Url.parse(url);
		var conn = Arena.scopedValue(a -> WinHttpApi.WinHttpConnect(Http.open(url), a.wstring(u.host), u.port, 0));
		if (conn.isNull()) throw new Exception('$url: WinHTTP did not connect');
		var req = Arena.scopedValue(a -> WinHttpApi.WinHttpOpenRequest(conn, a.wstring("GET"), a.wstring(u.path), Ptr.nil(), Ptr.nil(), Ptr.nil(), u.secure ? 0x00800000 : 0));
		if (req.isNull()) {
			WinHttpApi.WinHttpCloseHandle(conn);
			throw new Exception('$url: WinHTTP did not open the request');
		}
		var ctx = LibC.malloc(SIZE);
		LibC.memset(ctx, 0, SIZE);
		WinHttpApi.WinHttpSetStatusCallback(req, Callback.addr(Http.callback), Http.SENT | Http.HEADERS | FAILED, 0);
		var ws = Ptr.nil();
		try {
			if (!WinHttpApi.WinHttpSetOption(req, 114, Ptr.nil(), 0)) throw new Exception('$url: WinHTTP has no WebSockets (${Win32.GetLastError()})');
			if (!WinHttpApi.WinHttpSendRequest(req, Ptr.nil(), 0, Ptr.nil(), 0, 0, ctx)) throw new Exception('$url: WinHTTP did not send (${Win32.GetLastError()})');
			Http.await(ctx, Http.SENT, url);
			if (!WinHttpApi.WinHttpReceiveResponse(req, Ptr.nil())) throw new Exception('$url: WinHTTP did not receive (${Win32.GetLastError()})');
			Http.await(ctx, Http.HEADERS, url);
			var status = Http.statusOf(req);
			if (status != 101) throw new Exception('WebSocket to $url: $status');
			ws = WinHttpApi.WinHttpWebSocketCompleteUpgrade(req, ctx);
			if (ws.isNull()) throw new Exception('$url: WinHTTP did not upgrade (${Win32.GetLastError()})');
		} catch (e:Exception) {
			WinHttpApi.WinHttpSetStatusCallback(req, Ptr.nil(), 0, 0);
			WinHttpApi.WinHttpCloseHandle(req);
			WinHttpApi.WinHttpCloseHandle(conn);
			LibC.free(ctx);
			throw e;
		}
		WinHttpApi.WinHttpSetStatusCallback(req, Ptr.nil(), 0, 0);
		WinHttpApi.WinHttpCloseHandle(req);
		WinHttpApi.WinHttpSetStatusCallback(ws, Callback.addr(callback), READ | WRITE | FAILED | DOWN | CLOSED, 0);
		return new WinWebSocket(conn, ws, ctx);
	}

	// the next message; null once closed
	@:coroutine public function receive():Null<String> {
		var parts:Null<haxe.io.BytesBuffer> = null;
		while (!closed) {
			// (a receive left waiting by a cancel is still WinHTTP's: its end taken here)
			if (!reading) {
				if (WinHttpApi.WinHttpWebSocketReceive(ws, buf, BUFFER, Ptr.nil(), Ptr.nil()) != 0) break;
				reading = true;
			}
			var e = wait(RECEIVE);
			reading = false;
			if (closed || e != READ) break;
			// (WINHTTP_WEB_SOCKET_BUFFER_TYPE: 4 a close; 0, 2 a message's end, 1, 3 a fragment)
			var type = Mem.getI32(ctx, RECEIVE + TYPE);
			if (type == 4) break;
			var n = Mem.getI32(ctx, RECEIVE + Http.INFO), b = Bytes.alloc(n);
			if (n > 0) BytesPtr.copyIn(b, 0, buf, n);
			if ((type == 0 || type == 2) && parts == null) return b.toString();
			parts ??= new haxe.io.BytesBuffer();
			parts.add(b);
			if (type == 0 || type == 2) return parts.getBytes().toString();
		}
		close();
		return null;
	}

	@:coroutine public function send(text:String):Void {
		lock.acquire();
		try {
			if (closed) throw new Exception("WebSocket closed");
			var b = Bytes.ofString(text);
			if (!sent.isNull()) LibC.free(sent);
			sent = LibC.malloc(b.length + 1);
			if (b.length > 0) LibC.memcpy(sent, BytesPtr.of(b, 0, b.length), b.length);
			// (WINHTTP_WEB_SOCKET_UTF8_MESSAGE_BUFFER_TYPE)
			var r = WinHttpApi.WinHttpWebSocketSend(ws, 2, sent, b.length);
			if (r != 0) throw new Exception('WebSocket: WinHTTP did not send ($r)');
			var e = wait(SEND);
			if (closed) throw new Exception("WebSocket closed");
			if (e != WRITE) throw new Exception('WebSocket: WinHTTP failed (${Mem.getI32(ctx, SEND + Http.ERROR)})');
		} catch (e:Exception) {
			lock.release();
			throw e;
		}
		lock.release();
	}

	// a close sent, the handle closed (the other side's answer not waited for)
	@:coroutine public function close(code = 1000):Void {
		if (closed) return;
		closed = true;
		// (ERROR_IO_PENDING: the close frame's sending completes later)
		var r = WinHttpApi.WinHttpWebSocketShutdown(ws, code, Ptr.nil(), 0);
		// (a cancel here still closes the handle)
		if (r == 0 || r == 997) try wait(SHUTDOWN) catch (_:Exception) {}
		WinHttpApi.WinHttpCloseHandle(ws);
		WinHttpApi.WinHttpCloseHandle(conn);
		var loop = Loop.current(), sent = sent;
		loop.hold();
		loop.check(() -> {
			if (Atomic.load32(ctx.add(CLOSING)) == 0) return false;
			freed = true;
			LibC.free(buf);
			if (!sent.isNull()) LibC.free(sent);
			LibC.free(ctx);
			loop.release();
			return true;
		});
	}

	// (an operation's end in its slot, as Http.await's; 0 once the context is
	// freed: a wait from before the close, checked before the free, after it ends)
	@:coroutine function wait(at:Int):Int {
		var loop = Loop.current();
		loop.hold();
		var e = Async.suspendCancellable(cont -> {
			var done = false;
			loop.check(() -> {
				if (done) return true;
				var got = freed ? 0 : Atomic.load32(ctx.add(at));
				if (got == 0 && !freed) return false;
				if (got != 0) Atomic.store32(ctx.add(at), 0);
				done = true;
				cont.resume(got, null);
				return true;
			});
			return _ -> done = true;
		});
		loop.release();
		return e;
	}

	// (the system's threads, no GC: a slot by the operation; WINHTTP_WEB_SOCKET_STATUS's
	// count and type, or WINHTTP_WEB_SOCKET_ASYNC_RESULT's error and operation)
	@:hxmc.callback @:hxmc.noGc static function callback(handle:Ptr, ctx:Ptr, status:Int, info:Ptr, infoLength:Int):Void {
		if (ctx.isNull()) return;
		var at = 0;
		if (status == READ) at = RECEIVE;
		else if (status == WRITE) at = SEND;
		else if (status == DOWN) at = SHUTDOWN;
		else if (status == CLOSED) at = CLOSING;
		else if (status == FAILED) {
			var op = Mem.getI32(info, 16);
			at = op == 0 ? SEND : op == 1 ? RECEIVE : SHUTDOWN;
			Mem.setI32(ctx, at + Http.ERROR, Mem.getI32(info, 8));
		} else return;
		if (status == READ || status == WRITE) {
			Mem.setI32(ctx, at + Http.INFO, Mem.getI32(info, 0));
			Mem.setI32(ctx, at + TYPE, Mem.getI32(info, 4));
		}
		Atomic.store32(ctx.add(at), status);
	}
}

@:hxmc.c @:hxmc.lib("winhttp") private extern class WinHttpApi {
	static function WinHttpOpen(agent:Ptr, access:Int, proxy:Ptr, bypass:Ptr, flags:Int):Ptr;
	static function WinHttpConnect(session:Ptr, host:Ptr, port:Int, reserved:Int):Ptr;
	static function WinHttpOpenRequest(conn:Ptr, verb:Ptr, path:Ptr, version:Ptr, referrer:Ptr, accept:Ptr, flags:Int):Ptr;
	static function WinHttpSetStatusCallback(h:Ptr, cb:Ptr, flags:Int, reserved:Int64):Ptr;
	static function WinHttpSendRequest(req:Ptr, headers:Ptr, headersLength:Int, optional:Ptr, optionalLength:Int, total:Int, ctx:Ptr):Bool;
	static function WinHttpReceiveResponse(req:Ptr, reserved:Ptr):Bool;
	static function WinHttpQueryHeaders(req:Ptr, info:Int, name:Ptr, buf:Ptr, len:Ptr, index:Ptr):Bool;
	static function WinHttpQueryDataAvailable(req:Ptr, n:Ptr):Bool;
	static function WinHttpReadData(req:Ptr, buf:Ptr, n:Int, read:Ptr):Bool;
	static function WinHttpCloseHandle(h:Ptr):Bool;
	static function WinHttpSetOption(h:Ptr, option:Int, buf:Ptr, len:Int):Bool;
	static function WinHttpWebSocketCompleteUpgrade(req:Ptr, ctx:Ptr):Ptr;
	static function WinHttpWebSocketSend(ws:Ptr, type:Int, buf:Ptr, len:Int):Int;
	static function WinHttpWebSocketReceive(ws:Ptr, buf:Ptr, len:Int, read:Ptr, type:Ptr):Int;
	static function WinHttpWebSocketShutdown(ws:Ptr, status:Int, reason:Ptr, len:Int):Int;
}
#end
