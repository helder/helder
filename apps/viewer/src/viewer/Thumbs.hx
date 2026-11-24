package viewer;

import helder.async.Async;
import helder.image.Image;
import helder.media.*;

// A video's thumbnails for the scrub bar: the keyframe before a time,
// decoded from a reading of the file of its own (the player's goes on),
// turned to RGB on the CPU at WIDTH pixels across (every few pixels'
// sample: a thumbnail's), kept by the keyframe's time.
class Thumbs {
	public static inline var WIDTH = 160;

	final open:Void->ByteSource;
	final cache = new Map<String, Image>();
	var media:Null<Media>;
	var decoder:Null<VideoDecoder>;
	var track:Null<MediaTrack>;
	var busy = false;
	var closed = false;

	// open: a reading of the file of its own (its Files')
	public function new(open:Void->ByteSource)
		this.open = open;

	// the thumbnail at t, done(image) once there (at once when kept; null: none)
	public function at(t:Float, done:Null<Image>->Void) {
		if (busy || closed) return;
		busy = true;
		Async.launch(_ -> {
			var img = try find(t) catch (_:Dynamic) null;
			busy = false;
			if (!closed) done(img);
		});
	}

	@:coroutine function find(t:Float):Null<Image> {
		if (media == null) ready(Media.open(open()));
		var m = media;
		if (m == null || decoder == null) return null;
		var key = keyOf(m.seek(t));
		if (key == null || cache.exists(key)) return key == null ? null : cache.get(key);
		var p = m.next();
		while (p != null && p.track != track) p = m.next();
		return p == null ? null : decoded(key, p, m.read(p));
	}

	function ready(m:Media) {
		media = m;
		track = Lambda.find(m.tracks, t -> t.kind == Video);
		if (track != null) decoder = Decoders.video(track);
	}

	// (the keyframe the seek lands on: its time, the cache's key)
	function keyOf(seeks:Array<Seek>):Null<String> {
		var s = Lambda.find(seeks, s -> s.track == track);
		return s == null || s.packet == null ? null : Std.string(s.packet.time);
	}

	function decoded(key:String, p:Packet, bytes:haxe.io.Bytes):Null<Image> {
		var img = frameImage(decoder, p, bytes, track.rotation, 0);
		if (img != null) cache.set(key, img);
		return img;
	}

	// The folder thumbnail, on the calling job's thread: the same keyframe
	// seek and decode as the scrub bar, with a reader of its own.
	@:allow(viewer.Thumbnails) static function poster(path:String, side:Int):Null<Image> {
		var source = new FileSource(path);
		var sample = try Async.run(_ -> posterPacket(source)) catch (_:Dynamic) null;
		source.close();
		if (sample == null) return null;
		var d = Decoders.video(sample.packet.track);
		if (d == null) return null;
		try {
			var img = frameImage(d, sample.packet, sample.bytes, sample.packet.track.rotation, side);
			d.close();
			return img;
		} catch (e:Dynamic) {
			d.close();
			throw e;
		}
	}

	@:coroutine static function posterPacket(source:FileSource):Null<{packet:Packet, bytes:haxe.io.Bytes}> {
		var m = Media.open(source);
		var track = Lambda.find(m.tracks, t -> t.kind == Video);
		if (track == null) return null;
		var seeks = m.seek(Math.min(2, Math.max(0, m.duration * 0.1)));
		var s = Lambda.find(seeks, s -> s.track == track);
		return s == null || s.packet == null ? null : {packet: s.packet, bytes: m.read(s.packet)};
	}

	static function frameImage(d:VideoDecoder, p:Packet, bytes:haxe.io.Bytes, rotation:Int, side:Int):Null<Image> {
		var frames = [];
		d.decode(p, bytes, true);
		d.flush();
		d.take(frames);
		if (frames.length == 0) return null;
		try {
			var img = image(frames[0], rotation, side);
			for (f in frames) f.release();
			return img;
		} catch (e:Dynamic) {
			for (f in frames) f.release();
			throw e;
		}
	}

	// (the frame's planes to RGBA: its matrix, range and depth; turned upright)
	static function image(f:VideoFrame, rotation:Int, side:Int):Image {
		var px = f.pixels(), w = f.width, h = f.height, deep = f.bits > 8;
		// (side > 0: every few pixels' sample still at least side on the long side, for a Resize after)
		var step = side > 0 ? Std.int(Math.max(1, Math.max(w, h) / side)) : Math.ceil(w / WIDTH);
		var tw = Std.int(w / step), th = Std.int(h / step);
		var m = helder.media.ui.VideoTexture.matrix(f);
		var cw = (w + 1) >> 1, chroma = w * h * (deep ? 2 : 1);
		inline function sample(at:Int):Float
			return deep ? (px.get(at) | px.get(at + 1) << 8) / 65535 : px.get(at) / 255;
		var turned = rotation == 90 || rotation == 270, ow = turned ? th : tw, oh = turned ? tw : th;
		var out = haxe.io.Bytes.alloc(ow * oh * 4);
		for (y in 0...th) {
			helder.image.GcPoint.poll();
			for (x in 0...tw) {
				var sx = x * step, sy = y * step, k = deep ? 2 : 1;
				var yy = sample((sy * w + sx) * k), c = chroma + ((sy >> 1) * cw + (sx >> 1)) * 2 * k;
				var cb = sample(c), cr = sample(c + k);
				var ox = x, oy = y;
				switch rotation {
					case 90:
						ox = th - 1 - y;
						oy = x;
					case 180:
						ox = tw - 1 - x;
						oy = th - 1 - y;
					case 270:
						ox = y;
						oy = tw - 1 - x;
					case _:
				}
				var o = (oy * ow + ox) * 4;
				for (i in 0...3) {
					var r = m[i];
					out.set(o + i, Std.int(Math.max(0, Math.min(255, (r.x * yy + r.y * cb + r.z * cr + r.w) * 255 + 0.5))));
				}
				out.set(o + 3, 255);
			}
		}
		return new Image(ow, oh, out);
	}

	public function close() {
		closed = true;
		if (decoder != null) decoder.close();
		if (media != null) media.close();
		decoder = null;
		media = null;
	}
}
