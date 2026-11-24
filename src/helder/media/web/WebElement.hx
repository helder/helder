package helder.media.web;

#if (hxmc.target == "wasm32-wasi")
import haxe.io.Bytes;
import hxmc.unsafe.*;

// The fallback where WebCodecs does not decode a file (older Safari's
// audio, some Firefox and HEVC cases): the page's <video> element playing
// the WebSource's URL or Blob itself, its decoding, sound and clock the
// browser's; its frame drawn as a decoder's is (VideoTexture: the element
// copied on the GPU). Weaker: a seek lands where the browser puts it, a
// step is a seek by a frame's duration, no frames decoded ahead. Muted until
// a gesture allows sound. The main thread only: a worker has no elements.
@:hxmc.unsafe(gc)
class WebElement implements VideoDecoder {
	public var pending(get, never):Int;
	// seconds: the frame shown's time, the browser's duration; a frame's (the file's first)
	public var time(get, never):Float;
	public var duration(get, never):Float;
	public var ended(get, never):Bool;
	public var frame = 1 / 30;
	// (a test's: the element even where WebCodecs decodes the file)
	public static var forced = false;

	final h:Int;
	var presented = -1.0;
	var shown:Null<VideoFrame>;

	function new(h)
		this.h = h;

	// (null: no element here, or not a WebSource)
	public static function open(source:ByteSource):Null<WebElement> {
		var w = Std.downcast(source, helder.media.WebSource);
		if (w == null) return null;
		var h = Glue.element(@:privateAccess w.h);
		return h == 0 ? null : new WebElement(h);
	}

	@:coroutine public function ready():Bool
		return Glue.Wait.done(h);

	function get_pending():Int
		return 0;

	function get_time():Float
		return Glue.element_get(h, 0);

	function get_duration():Float
		return Glue.element_get(h, 4);

	function get_ended():Bool
		return Glue.element_get(h, 2) == 1;

	public function play()
		Glue.element_set(h, 0, 1);

	public function pause()
		Glue.element_set(h, 0, 0);

	public function seek(t:Float)
		Glue.element_set(h, 1, t);

	public function rate(r:Float)
		Glue.element_set(h, 4, r);

	// its volume (0: muted) and looping
	public function sound(volume:Float, loop:Bool) {
		Glue.element_set(h, 3, volume == 0 ? 1 : 0);
		if (volume > 0) Glue.element_set(h, 2, volume);
		Glue.element_set(h, 5, loop ? 1 : 0);
	}

	// the frame it shows: one each frame the browser presented
	public function current():VideoFrame {
		var n = Glue.element_get(h, 1);
		if (shown == null || n != presented) {
			presented = n;
			shown = WebVideoDecoder.made(this, h, time);
		}
		return shown;
	}

	public function decode(p:Packet, bytes:Bytes, show:Bool) {}

	public function take(into:Array<VideoFrame>) {}

	public function flush() {}

	public function reset() {}

	// (the element's frame is the element: nothing to give back)
	public function release(f:VideoFrame) {}

	public function plane(f:VideoFrame, plane:Int):Null<String>
		return null;

	public function pixels(f:VideoFrame):Bytes
		return Bytes.alloc(0);

	public function close()
		Glue.element_close(h);
}
#end
