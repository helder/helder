package helder.async.http.apple;

#if (target.name == "hxmc" && (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64"))
// (Apple's targets only: a block is linked where it is compiled, a constant branch or not)
import haxe.Exception;
import haxe.io.Bytes;
import helder.async.*;
import helder.async.http.Client.Reply;
import helder.async.http.Client.RequestOptions;
import hxmc.objc.Id;
import hxmc.objc.Strings;
import hxmc.unsafe.*;

// Client.request's https on macOS and iOS: Foundation's NSURLSession (its
// shared session: the system's TLS, HTTP/2, proxies, its cache by the
// responses' headers, App Transport Security's rules), nothing linked that
// the system does not have. The completion handler is a block of a Haxe
// function (hxmc's: the session's queue's thread attached), which posts the
// reply to the loop of the request (held meanwhile: Loop.hold); a request
// cancelled is the task cancelled.
@:hxmc.unsafe(gc)
class Http {
	@:coroutine public static function request(url:String, options:Null<RequestOptions>):Reply {
		var target = NSURL.URLWithString(ns(url));
		if (target == null) throw new Exception('not a url: $url');
		var req = NSMutableURLRequest.requestWithURL(target);
		req.setHTTPMethod(ns(options?.method ?? "GET"));
		var body = options?.body ?? (options?.text != null ? Bytes.ofString(options.text) : null);
		if (body != null && body.length > 0) req.setHTTPBody(Arena.scopedValue(a -> NSData.dataWithBytes(a.copyBytes(body), body.length)));
		var given = options?.headers ?? new Map();
		for (k => v in given)
			req.setValue(ns(v), ns(k));
		if (options?.contentType != null && !given.exists("content-type")) req.setValue(ns(options.contentType), ns("content-type"));
		var loop = Loop.current();
		var out:{reply:Null<Reply>, error:Null<String>} = Async.suspendCancellable(cont -> {
			var done = false;
			loop.hold();
			var task = NSURLSession.sharedSession().dataTaskWithRequest(req, (data, response, error) -> {
				// (the session's thread: what is read of the reply, read here; the rest on the loop)
				var reply = error == null ? replyOf(data, response) : null;
				var message = error == null ? null : str(error.localizedDescription()) ?? "request failed";
				loop.post(() -> {
					loop.release();
					if (done) return;
					done = true;
					cont.resume({reply: reply, error: message}, null);
				});
			});
			task.resume();
			return _ -> if (!done) {
				done = true;
				task.cancel();
			};
		});
		if (out.error != null) throw new Exception('$url: ${out.error}');
		return out.reply;
	}

	static function replyOf(data:Null<NSData>, response:Null<NSURLResponse>):Reply {
		var headers = new Map<String, String>();
		var status = 200;
		var http:Null<NSHTTPURLResponse> = response != null && Std.isOfType(response, NSHTTPURLResponse) ? cast response : null;
		if (http != null) {
			status = http.statusCode().toInt();
			var all = http.allHeaderFields(), keys = all.allKeys();
			for (i in 0...keys.count().toInt()) {
				var k:NSString = cast keys.objectAtIndex(i);
				var v:NSString = cast all.objectForKey(k);
				var name = str(k), value = str(v);
				if (name != null && value != null) headers.set(name.toLowerCase(), value);
			}
		}
		var n = data == null ? 0 : data.length().toInt();
		var b = Bytes.alloc(n);
		if (n > 0) BytesPtr.copyIn(b, 0, data.bytes(), n);
		return new Reply(status, headers, b);
	}

	@:allow(helder.async.http) static inline function ns(s:String):NSString
		return cast Strings.toNSString(s);

	@:allow(helder.async.http) static inline function str(s:Null<NSString>):Null<String>
		return s == null ? null : Strings.ofNSString(cast s);
}

// WebSocket.open's ws and wss on macOS and iOS: NSURLSession's
// NSURLSessionWebSocketTask (the system's TLS, proxies and App Transport
// Security's rules, as Http's requests). A ping after it opens tells
// whether it did (open throws when not); each message received, sent and
// the close are completion handlers posted to the loop, as Http's.
// Binary messages come as their bytes' string, as helder's own WebSocket's.
@:hxmc.unsafe(gc)
class AppleWebSocket {
	final task:NSURLSessionWebSocketTask;
	public var closed(default, null) = false;

	function new(task)
		this.task = task;

	@:coroutine public static function open(url:String):AppleWebSocket {
		var target = NSURL.URLWithString(Http.ns(url));
		if (target == null) throw new Exception('not a url: $url');
		var ws = new AppleWebSocket(NSURLSession.sharedSession().webSocketTaskWithURL(target));
		ws.task.resume();
		var error = ws.await((done:Null<String>->Void) -> ws.task.sendPingWithPongReceiveHandler(e -> done(e == null ? null : Http.str(e.localizedDescription()) ?? "failed")));
		if (error != null) {
			ws.task.cancel();
			throw new Exception('WebSocket to $url: $error');
		}
		return ws;
	}

	// (a call whose completion handler gives a result: awaited on the loop)
	@:coroutine function await<T>(start:(T->Void)->Void):T {
		var loop = Loop.current();
		return Async.suspendCancellable(cont -> {
			var done = false;
			loop.hold();
			start(r -> loop.post(() -> {
				loop.release();
				if (done) return;
				done = true;
				cont.resume(r, null);
			}));
			return _ -> if (!done) {
				done = true;
				task.cancel();
			};
		});
	}

	// the next message; null once closed
	@:coroutine public function receive():Null<String> {
		if (closed) return null;
		var got:{text:Null<String>, error:Bool} = await((done:{text:Null<String>, error:Bool}->Void) -> task.receiveMessageWithCompletionHandler((m, e) -> {
			if (e != null || m == null) return done({text: null, error: true});
			if (m.type() == 1) return done({text: Http.str(m.string()) ?? "", error: false});
			var d = m.data(), n = d == null ? 0 : d.length().toInt(), b = Bytes.alloc(n);
			if (n > 0) BytesPtr.copyIn(b, 0, d.bytes(), n);
			done({text: b.toString(), error: false});
		}));
		if (got.error) {
			closed = true;
			return null;
		}
		return got.text;
	}

	@:coroutine public function send(text:String):Void {
		if (closed) throw new Exception("WebSocket closed");
		var m = NSURLSessionWebSocketMessage.alloc().initWithString(Http.ns(text));
		var error = await((done:Null<String>->Void) -> task.sendMessage(m, e -> done(e == null ? null : Http.str(e.localizedDescription()) ?? "failed")));
		if (error != null) throw new Exception('WebSocket: $error');
	}

	@:coroutine public function ping():Void {
		var error = await((done:Null<String>->Void) -> task.sendPingWithPongReceiveHandler(e -> done(e == null ? null : "failed")));
		if (error != null) throw new Exception('WebSocket: $error');
	}

	public function close(code = 1000):Void {
		if (closed) return;
		closed = true;
		task.cancelWithCloseCode(code, null);
	}
}

@:hxmc.objc @:hxmc.framework("Foundation") private extern class NSObject implements Id {}

@:hxmc.objc @:hxmc.framework("Foundation") private extern class NSString extends NSObject {}

@:hxmc.objc @:hxmc.framework("Foundation") private extern class NSURL extends NSObject {
	static function URLWithString(s:NSString):Null<NSURL>;
}

@:hxmc.objc @:hxmc.framework("Foundation") private extern class NSData extends NSObject {
	static function dataWithBytes(bytes:Ptr, length:Int64):NSData;
	function bytes():Ptr;
	function length():Int64;
}

@:hxmc.objc @:hxmc.framework("Foundation") private extern class NSArray extends NSObject {
	function count():Int64;
	function objectAtIndex(i:Int64):Id;
}

@:hxmc.objc @:hxmc.framework("Foundation") private extern class NSDictionary extends NSObject {
	function allKeys():NSArray;
	function objectForKey(k:Id):Null<Id>;
}

@:hxmc.objc @:hxmc.framework("Foundation") private extern class NSError extends NSObject {
	function localizedDescription():NSString;
}

@:hxmc.objc @:hxmc.framework("Foundation") private extern class NSURLRequest extends NSObject {}

@:hxmc.objc @:hxmc.framework("Foundation") private extern class NSMutableURLRequest extends NSURLRequest {
	static function requestWithURL(url:NSURL):NSMutableURLRequest;
	function setHTTPMethod(m:NSString):Void;
	function setHTTPBody(d:NSData):Void;
	function setValue(v:NSString, forHTTPHeaderField:NSString):Void;
}

@:hxmc.objc @:hxmc.framework("Foundation") private extern class NSURLResponse extends NSObject {}

@:hxmc.objc @:hxmc.framework("Foundation") private extern class NSHTTPURLResponse extends NSURLResponse {
	function statusCode():Int64;
	function allHeaderFields():NSDictionary;
}

@:hxmc.objc @:hxmc.framework("Foundation") private extern class NSURLSessionDataTask extends NSObject {
	function resume():Void;
	function cancel():Void;
}

@:hxmc.objc @:hxmc.framework("Foundation") private extern class NSURLSession extends NSObject {
	static function sharedSession():NSURLSession;
	function dataTaskWithRequest(r:NSURLRequest, completionHandler:(Null<NSData>, Null<NSURLResponse>, Null<NSError>) -> Void):NSURLSessionDataTask;
	function webSocketTaskWithURL(url:NSURL):NSURLSessionWebSocketTask;
}

@:hxmc.objc @:hxmc.framework("Foundation") private extern class NSURLSessionWebSocketMessage extends NSObject {
	static function alloc():NSURLSessionWebSocketMessage;
	function initWithString(s:NSString):NSURLSessionWebSocketMessage;
	// (NSURLSessionWebSocketMessageTypeData 0, String 1)
	function type():Int64;
	function string():Null<NSString>;
	function data():Null<NSData>;
}

@:hxmc.objc @:hxmc.framework("Foundation") private extern class NSURLSessionWebSocketTask extends NSObject {
	function resume():Void;
	function cancel():Void;
	function sendMessage(m:NSURLSessionWebSocketMessage, completionHandler:Null<NSError>->Void):Void;
	function receiveMessageWithCompletionHandler(h:(Null<NSURLSessionWebSocketMessage>, Null<NSError>) -> Void):Void;
	function sendPingWithPongReceiveHandler(h:Null<NSError>->Void):Void;
	function cancelWithCloseCode(code:Int64, reason:Null<NSData>):Void;
}
#end
