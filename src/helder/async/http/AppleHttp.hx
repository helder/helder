package helder.async.http;

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
class AppleHttp {
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

	static inline function ns(s:String):NSString
		return cast Strings.toNSString(s);

	static inline function str(s:Null<NSString>):Null<String>
		return s == null ? null : Strings.ofNSString(cast s);
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
}
#end
