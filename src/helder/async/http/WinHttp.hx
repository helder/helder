package helder.async.http;

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
class WinHttp {
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
	static inline var FAILED = 0x01000000;

	@:coroutine public static function request(url:String, options:Null<RequestOptions>):Reply {
		var u = Client.Url.parse(url);
		if (session.isNull()) {
			// (WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY, Windows 8.1; else the default's; WINHTTP_FLAG_ASYNC)
			session = Arena.scopedValue(a -> WinHttpApi.WinHttpOpen(a.wstring("helder"), 4, Ptr.nil(), Ptr.nil(), 0x10000000));
			if (session.isNull()) session = Arena.scopedValue(a -> WinHttpApi.WinHttpOpen(a.wstring("helder"), 0, Ptr.nil(), Ptr.nil(), 0x10000000));
			if (session.isNull()) throw new Exception('$url: WinHTTP did not open');
		}
		var method = options?.method ?? "GET";
		var conn = Arena.scopedValue(a -> WinHttpApi.WinHttpConnect(session, a.wstring(u.host), u.port, 0));
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
}
#end
