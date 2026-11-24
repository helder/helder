package helder.media.web;

#if (hxmc.target == "wasm32-wasi")
import helder.async.Async;
import hxmc.unsafe.*;

// The page's side of WebCodecs and the <video> element: imports of the
// module "helder_media" (src/helder/media/imports.mjs), by handle
@:hxmc.c @:hxmc.lib("helder_media") extern class Glue {
	// (spans last, the other arguments plain: a span is never a temporary)
	// kind 0: video (a, b: its coded size), 1: audio (its rate, channels);
	// space: colours the stream does not name (WebCodec.untagged)
	@:hxmc.fast @:hxmc.safe static function supported(kind:Int, codec:String, a:Int, b:Int, config:hxmc.Span<UInt8>):Int;
	@:hxmc.fast @:hxmc.safe static function decoder(kind:Int, codec:String, a:Int, b:Int, copy:Int, space:Int, config:hxmc.Span<UInt8>):Int;
	@:hxmc.fast @:hxmc.safe static function decode(h:Int, key:Int, time:Float, duration:Float, show:Int, bytes:hxmc.Span<UInt8>):Int;
	static function state(h:Int):Int;
	static function free(h:Int):Void;
	static function failed(h:Int):Int;
	static function pending(h:Int):Int;
	static function flush(h:Int):Void;
	static function reset(h:Int):Void;
	static function close(h:Int):Void;
	static function frame(h:Int):Int;
	static function info(h:Int, what:Int):Float;
	static function pixels_length(h:Int):Int;
	@:hxmc.fast @:hxmc.safe static function pixels(h:Int, into:hxmc.Span<UInt8>):Void;
	static function release(h:Int):Void;
	static function audio_frames(h:Int):Int;
	static function audio_take(h:Int, into:Ptr<Float32>):Void;
	static function element(source:Int):Int;
	static function element_get(h:Int, what:Int):Float;
	static function element_set(h:Int, what:Int, v:Float):Void;
	static function element_close(h:Int):Void;
}

class Wait {
	// (a handle's state awaited: true once done, false if it failed)
	@:coroutine public static function done(h:Int):Bool {
		var now = Glue.state(h);
		if (now != 0) return now == 1;
		return Async.suspendCancellable(cont -> {
			var over = false;
			Async.loopOf(cont.context).check(() -> {
				if (over) return true;
				var s = Glue.state(h);
				if (s == 0) return false;
				over = true;
				cont.resume(s == 1, null);
				return true;
			});
			return _ -> over = true;
		});
	}
}
#end
