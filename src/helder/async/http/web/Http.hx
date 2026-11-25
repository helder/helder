package helder.async.http.web;

#if (hxmc.target == "wasm32-wasi")
import haxe.Exception;
import haxe.io.Bytes;
import helder.async.*;
import helder.async.http.Client.Reply;
import helder.async.http.Client.RequestOptions;

// Client.request and WebSocket.open in the browser (no sockets there): the
// page's fetch and WebSocket (src/helder/async/imports.mjs), their state
// polled on the loop's turns (a turn comes when it changes, as Fetch's).
// Their TLS, proxies, cookies and CORS are the browser's.
class Http {
	@:coroutine public static function request(url:String, options:Null<RequestOptions>):Reply {
		var headers = new StringBuf();
		var given = options?.headers ?? new Map();
		for (k => v in given)
			headers.add('$k: $v\n');
		if (options?.contentType != null && !given.exists("content-type")) headers.add('content-type: ${options.contentType}\n');
		var body = options?.body ?? (options?.text != null ? Bytes.ofString(options.text) : Bytes.alloc(0));
		var h = Web.http_start(url, options?.method ?? "GET", headers.toString(), hxmc.Span.ofBytes(body));
		var ok = until(() -> Web.fetch_state(h) != 0, () -> Web.fetch_free(h));
		if (Web.fetch_state(h) != 1 || !ok) {
			Web.fetch_free(h);
			throw new Exception('$url: the request failed');
		}
		var head = Bytes.alloc(Web.http_headers_length(h));
		Web.http_headers(h, hxmc.Span.ofBytes(head));
		var map = new Map<String, String>();
		for (line in head.toString().split("\n")) {
			var colon = line.indexOf(":");
			if (colon > 0) map.set(StringTools.trim(line.substr(0, colon)).toLowerCase(), StringTools.trim(line.substr(colon + 1)));
		}
		var status = Web.http_status(h);
		var b = Bytes.alloc(Web.fetch_length(h));
		Web.fetch_take(h, hxmc.Span.ofBytes(b));
		return new Reply(status, map, b);
	}

	// (waits for ready on the loop's turns: whether it came; cancelled: cancel())
	@:coroutine public static function until(ready:() -> Bool, cancel:() -> Void):Bool {
		if (ready()) return true;
		return Async.suspendCancellable(cont -> {
			var done = false;
			Async.loopOf(cont.context).check(() -> {
				if (done) return true;
				if (!ready()) return false;
				done = true;
				cont.resume(true, null);
				return true;
			});
			return _ -> if (!done) {
				done = true;
				cancel();
			};
		});
	}
}

// the page's WebSocket (WebSocket.open's in the browser)
class WebWebSocket {
	final h:Int;
	public var closed(default, null) = false;

	function new(h)
		this.h = h;

	@:coroutine public static function open(url:String):WebWebSocket {
		var h = Web.ws_open(url);
		Http.until(() -> Web.ws_state(h) != 0, () -> Web.ws_close(h, 1000));
		if (Web.ws_state(h) != 1) {
			Web.ws_close(h, 1000);
			throw new Exception('WebSocket to $url failed');
		}
		return new WebWebSocket(h);
	}

	// the next message; null once closed
	@:coroutine public function receive():Null<String> {
		if (closed) return null;
		Http.until(() -> Web.ws_next(h) >= 0 || Web.ws_state(h) != 1, () -> {});
		var n = Web.ws_next(h);
		if (n < 0) {
			close();
			return null;
		}
		var b = Bytes.alloc(n);
		Web.ws_take(h, hxmc.Span.ofBytes(b));
		return b.toString();
	}

	public function send(text:String) {
		if (closed || Web.ws_state(h) != 1) throw new Exception("WebSocket closed");
		Web.ws_send(h, text);
	}

	public function close(code = 1000) {
		if (closed) return;
		closed = true;
		Web.ws_close(h, code);
	}
}
#end
