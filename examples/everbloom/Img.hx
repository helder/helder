import helder.async.Async;
import helder.async.http.Client;
import helder.image.Image;
import helder.image.ImageJobs;
import helder.view.graph.Graph.*;
import helder.view.graph.Signal;

// The API's images, by URL and width (the spec's ?width=N or &width=N):
// fetched (six at a time), decoded, kept while they are among the last
// ones asked for (LIMIT); a signal each, null until it lands (the node
// shows the surface colour meanwhile) or when it failed.
class Img {
	static inline var LIMIT = 90;
	static inline var PARALLEL = 6;

	static final cache = new Map<String, Signal<Null<Image>>>();
	static final order:Array<String> = [];
	static final waiting:Array<String> = [];
	static var running = 0;
	static final none:Signal<Null<Image>> = signal(null);

	public static function sized(url:String, width:Int):String
		return url + (url.indexOf("?") >= 0 ? "&" : "?") + "width=" + width;

	public static function of(url:Null<String>, width:Int):Signal<Null<Image>> {
		if (url == null) return none;
		var key = sized(url, width);
		var s = cache.get(key);
		if (s != null) {
			// (asked again: the most recent)
			order.remove(key);
			order.push(key);
			return s;
		}
		s = signal(null);
		cache.set(key, s);
		order.push(key);
		while (order.length > LIMIT) {
			var old = order.shift();
			cache.remove(old);
			waiting.remove(old);
		}
		waiting.push(key);
		pump();
		return s;
	}

	static function pump() {
		while (running < PARALLEL && waiting.length > 0) {
			var key = waiting.pop();
			running++;
			Async.launch(@:coroutine function(_) {
				var r = Client.request(key);
				if (r.status < 200 || r.status >= 300) return null;
				return ImageJobs.decode(r.body);
			}).onCompletion((image, e) -> {
				running--;
				var s = cache.get(key);
				if (s != null && image != null) s(image);
				pump();
			});
		}
	}
}
