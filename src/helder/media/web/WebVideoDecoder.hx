package helder.media.web;

#if (hxmc.target == "wasm32-wasi")
import haxe.io.Bytes;
import hxmc.unsafe.*;

// A track decoded by the browser's WebCodecs VideoDecoder (imports.mjs):
// packets in as EncodedVideoChunks, timed in microseconds; a frame out is
// the page's VideoFrame, its handle the VideoFrame's image (never in the
// module's memory: VideoTexture copies it into a texture on the GPU), shown
// as soon as it is let go (the decoder's pool is small). Frames before an
// exact seek's target are given back as they come. Configured at the
// first packet, a keyframe: a WebM's VP9 has its profile there, VP9's and
// AV1's colours may be only there.
@:hxmc.unsafe(gc)
class WebVideoDecoder implements VideoDecoder {
	// (a test's: each frame's planes read too, for pixels())
	public static var copy = false;

	public var pending(get, never):Int;

	final track:MediaTrack;
	final copies = copy;
	var h = 0;
	// (the packets' times by their microseconds: a frame's exact time)
	final micros:Array<Float> = [];
	final times:Array<Float> = [];

	public function new(track:MediaTrack)
		this.track = track;

	function open(first:Null<Bytes>) {
		var name = WebCodec.name(track, first);
		if (name == null) throw new MediaError('no decoder for ${track.codec}');
		var d = WebCodec.description(track) ?? Bytes.alloc(0);
		var w = track.width, ht = track.height, c = copies ? 1 : 0, space = WebCodec.untagged(track, first);
		h = Glue.decoder(0, name, w, ht, c, space, hxmc.Span.ofBytes(d));
		if (Glue.failed(h) == 1) throw new MediaError('the browser does not decode $name');
	}

	function get_pending():Int
		return h == 0 ? 0 : Glue.pending(h);

	public function decode(p:Packet, bytes:Bytes, show:Bool) {
		if (h == 0) open(bytes);
		var us = Math.ffloor(p.time * 1e6 + 0.5);
		if (show) {
			micros.push(us);
			times.push(p.time);
		}
		var key = p.key ? 1 : 0, d = Math.ffloor(p.duration / p.track.timescale * 1e6 + 0.5), s = show ? 1 : 0;
		if (Glue.decode(h, key, us, d, s, hxmc.Span.ofBytes(bytes)) == 0)
			throw new MediaError('the browser could not decode this ${track.codec}');
	}

	public function take(into:Array<VideoFrame>) {
		// (a failure: the next decode's error, the player's loop catching it)
		if (h == 0 || Glue.failed(h) == 1) return;
		var f;
		while ((f = Glue.frame(h)) != 0) {
			var us = Glue.info(f, 0), time = us / 1e6;
			for (i in 0...micros.length)
				if (micros[i] == us) {
					time = times[i];
					micros.splice(i, 1);
					times.splice(i, 1);
					break;
				}
			into.push(made(this, f, time));
		}
	}

	// (a frame of the page's: its handle the image)
	public static function made(owner:VideoDecoder, f:Int, time:Float):VideoFrame {
		var m = Glue.info(f, 3);
		return @:privateAccess new VideoFrame(owner, time, Std.int(Glue.info(f, 1)), Std.int(Glue.info(f, 2)), m == 709 ? "709" : m == 2020 ? "2020" : "601",
			Glue.info(f, 4) == 1, Std.int(Glue.info(f, 5)), Ptr.ofI64(f));
	}

	public function flush()
		if (h != 0) Glue.flush(h);

	public function reset() {
		micros.resize(0);
		times.resize(0);
		if (h != 0) Glue.reset(h);
	}

	public function release(f:VideoFrame)
		Glue.release(f.handle());

	// (none: the browser's frame is drawn by VideoTexture's copy)
	public function plane(f:VideoFrame, plane:Int):Null<String>
		return null;

	public function pixels(f:VideoFrame):Bytes {
		var i = f.handle(), b = Bytes.alloc(Glue.pixels_length(i));
		Glue.pixels(i, hxmc.Span.ofBytes(b));
		return b;
	}

	public function close() {
		if (h != 0) Glue.close(h);
		h = 0;
	}
}
#end
