package helder.media;

#if (hxmc.target == "wasm32-wasi")
import haxe.io.Bytes;
import helder.async.Async;
import hxmc.unsafe.*;

// A ByteSource in the browser (src/helder/media/imports.mjs): a URL read
// by fetch's Range requests, a part at a time, never the whole file (a
// server that ignores Range sends it whole once: kept as a Blob); a Blob
// the page gave (a file picked or dropped: its slices); a file of the
// origin's private file system (OPFS). helder.run's apps have no network:
// their URLs are their bundled assets, their Blobs the user's files.
//
//   var media = Media.open(WebSource.url("clips/intro.webm"));
//   var mine = Media.open(WebSource.blob("drop/1"));   // host.blob("drop/1", file), the page's
class WebSource implements ByteSource {
	public var size(get, never):Float;

	final h:Int;

	function new(h)
		this.h = h;

	@:coroutine public static function url(url:String):WebSource
		return opened(WebMedia.url(url), url);

	@:coroutine public static function blob(name:String):WebSource
		return opened(WebMedia.blob(name), name);

	@:coroutine public static function opfs(path:String):WebSource
		return opened(WebMedia.opfs(path), path);

	@:coroutine static function opened(h:Int, what:String):WebSource {
		if (!done(h)) {
			WebMedia.free(h);
			throw new MediaError('cannot open $what');
		}
		return new WebSource(h);
	}

	function get_size():Float
		return WebMedia.size(h);

	@:coroutine public function read(offset:Float, b:Bytes, pos:Int, len:Int):Int {
		if (offset < 0 || pos < 0 || len < 0 || pos + len > b.length) throw new MediaError("read out of range");
		if (len == 0) return 0;
		var r = WebMedia.read(h, offset, len);
		if (!done(r)) {
			WebMedia.free(r);
			throw new MediaError("read failed");
		}
		var n = WebMedia.length(r);
		if (n > len) n = len;
		WebMedia.take(r, hxmc.Span.ofBytes(b, pos, n));
		return n;
	}

	// (a handle's state awaited: true once done, false if it failed; a
	// cancelled coroutine frees it)
	@:coroutine static function done(h:Int):Bool {
		// (a Blob's source is ready at once: no event would wake the loop)
		var now = WebMedia.state(h);
		if (now != 0) return now == 1;
		return Async.suspendCancellable(cont -> {
			var over = false;
			Async.loopOf(cont.context).check(() -> {
				if (over) return true;
				var s = WebMedia.state(h);
				if (s == 0) return false;
				over = true;
				cont.resume(s == 1, null);
				return true;
			});
			return _ -> if (!over) {
				over = true;
				WebMedia.free(h);
			};
		});
	}

	public function close()
		WebMedia.free(h);
}

// The page's side: imports of the module "helder_media" (imports.mjs). A
// source or a read is a handle: its state (0 waiting, 1 done, -1 failed;
// a turn of the loop comes when it changes), a source's size (-1: not
// known), a read's bytes' length and the bytes into a span (the read freed).
@:hxmc.c @:hxmc.lib("helder_media") private extern class WebMedia {
	@:hxmc.safe static function url(url:String):Int;
	@:hxmc.safe static function blob(name:String):Int;
	@:hxmc.safe static function opfs(path:String):Int;
	static function state(h:Int):Int;
	static function size(h:Int):Float;
	static function read(h:Int, offset:Float, n:Int):Int;
	static function length(h:Int):Int;
	@:hxmc.fast @:hxmc.safe static function take(h:Int, buf:hxmc.Span<UInt8>):Void;
	static function free(h:Int):Void;
}
#end
