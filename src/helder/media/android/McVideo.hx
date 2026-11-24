package helder.media.android;

import haxe.io.Bytes;
import helder.media.android.MediaNdk;
import hxmc.unsafe.*;

// helder.media's VideoDecoder on Android: an AMediaCodec (McCodec) of the
// track, its csd-0 and csd-1 from avcC's or hvcC's parameter sets (start
// codes before each), av1C's whole; VP9 needs none. It decodes onto an
// AImageReader's surface: its frames AImages on AHardwareBuffers sampled by
// GLES through an EGLImage (plane: "ahb:", no copy; their YUV the driver's
// to convert, as the codec tagged them), or, with a system layer, onto that
// layer's surface (output: the frames buffers of the codec's, rendered as
// they fall due). Times go in as microseconds (offset: never below 0),
// each output found by its time; one is rendered to the reader at a time
// (its queue keeps the last one queued), so that after a seek at most one
// of before it comes, dropped unless it is the same frame again.
@:hxmc.unsafe(gc)
class McVideo implements VideoDecoder {
	// (tests: the frames' planes readable by the CPU, pixels; else the GPU's alone)
	public static var readable = false;
	// (the images out at once: what the player holds, ahead and retired)
	static inline var IMAGES = 20;
	static inline var BASE = 1e9;

	public var pending(get, never):Int;

	final track:MediaTrack;
	var codec:Null<McCodec>;
	var reader = Ptr.nil();
	var window = Ptr.nil();
	// (the layer's surface the codec renders onto; nil: the reader's)
	var layer = Ptr.nil();
	// (given, not out: their keys, times, whether shown; rendered to the reader, not taken)
	final keys:Array<Float> = [];
	final times:Array<Float> = [];
	final shows:Array<Bool> = [];
	final rendered:Array<Float> = [];
	final renderedTimes:Array<Float> = [];
	// (the codec's buffers out for a layer: their index and time)
	final held:Array<{idx:Int, time:Float}> = [];
	var matrix = "601";
	var full = false;
	var bits = 8;

	public static function supports(c:Codec):Bool
		return switch c {
			case H264 | Hevc | Vp9 | Av1: MediaNdk.loaded();
			case _: false;
		}

	public function new(track:MediaTrack) {
		this.track = track;
		if (!supports(track.codec)) throw new MediaError('no decoder for ${track.codec}');
	}

	function get_pending():Int
		return keys.length + rendered.length + (codec == null ? 0 : codec.waiting);

	function open() {
		var w = track.width, h = track.height, c = track.config;
		bits = depth(c);
		var st = Arena.scopedValue(a -> {
			var out:Ptr<Ptr> = a.alloc(8);
			// (AIMAGE_FORMAT_PRIVATE, the codec's own layout; where read
			// YUV_420_888, YCBCR_P010 at 10 bits; GPU_SAMPLED_IMAGE, CPU_READ_OFTEN)
			var format = !readable ? 0x22 : bits > 8 ? 0x36 : 0x23;
			var s = MediaNdk.AImageReader_newWithUsage(w, h, format, readable ? 0x103 : 0x100, IMAGES, out);
			if (s != 0) return s;
			reader = out.value;
			s = MediaNdk.AImageReader_getWindow(reader, out);
			if (s == 0) window = out.value;
			s;
		});
		if (st != 0) throw new MediaError('no images for the decoder (media_status_t $st)');
		var sets = parameterSets(c);
		codec = McCodec.open(track, f -> {
			McCodec.int(f, "width", w);
			McCodec.int(f, "height", h);
			if (sets != null) {
				McCodec.buffer(f, "csd-0", sets[0]);
				if (sets[1].length > 0) McCodec.buffer(f, "csd-1", sets[1]);
			} else if (track.codec == Av1 && c != null)
				McCodec.buffer(f, "csd-0", c);
		}, layer.isNull() ? window : layer, lengths(c));
	}

	// (bits a sample: hvcC's, vpcC's, av1C's; H.264 High 10's)
	function depth(c:Null<Bytes>):Int {
		if (c == null) return 8;
		return switch track.codec {
			case Hevc if (c.length > 17): (c.get(17) & 7) + 8;
			case Vp9 if (c.length > 6): c.get(6) >> 4;
			case Av1 if (c.length > 2): c.get(2) & 0x40 != 0 ? 10 : 8;
			case H264 if (c.length > 1): c.get(1) == 110 ? 10 : 8;
			case _: 8;
		}
	}

	// (avcC's NAL length size, hvcC's; 0: none, the packets as they are)
	function lengths(c:Null<Bytes>):Int
		return c == null ? 0 : switch track.codec {
			case H264 if (c.length > 4): (c.get(4) & 3) + 1;
			case Hevc if (c.length > 21): (c.get(21) & 3) + 1;
			case _: 0;
		}

	// (avcC's SPS and PPS, hvcC's VPS, SPS and PPS all in the first: each after a start code)
	function parameterSets(c:Null<Bytes>):Null<Array<Bytes>> {
		if (c == null || (track.codec != H264 && track.codec != Hevc)) return null;
		var lists = [new haxe.io.BytesBuffer(), new haxe.io.BytesBuffer()];
		function add(to:haxe.io.BytesBuffer, at:Int, size:Int) {
			for (b in [0, 0, 0, 1]) to.addByte(b);
			to.addBytes(c, at, size);
		}
		try {
			if (track.codec == H264) {
				var at = 5;
				for (kind in 0...2) {
					var n = c.get(at++) & (kind == 0 ? 31 : 255);
					for (_ in 0...n) {
						var size = c.get(at) << 8 | c.get(at + 1);
						add(lists[kind], at + 2, size);
						at += 2 + size;
					}
				}
			} else {
				var at = 23;
				for (_ in 0...c.get(22)) {
					var n = c.get(at + 1) << 8 | c.get(at + 2);
					at += 3;
					for (_ in 0...n) {
						var size = c.get(at) << 8 | c.get(at + 1);
						add(lists[0], at + 2, size);
						at += 2 + size;
					}
				}
			}
		} catch (_:Dynamic) return null;
		return [lists[0].getBytes(), lists[1].getBytes()];
	}

	public function decode(p:Packet, bytes:Bytes, show:Bool) {
		if (codec == null) open();
		var k = BASE + Math.round(p.time * 1e6);
		keys.push(k);
		times.push(p.time);
		shows.push(show);
		codec.push(bytes, k, p.key);
		pump();
	}

	// (inputs given as buffers free, outputs released: rendered where shown)
	function pump() {
		var c = codec;
		if (c == null) return;
		c.feed();
		// (one rendered at a time: the reader's queue keeps the last one queued, dropping those before it)
		while (rendered.length == 0) {
			var idx = c.next();
			if (idx == MediaNdk.FORMAT_CHANGED) {
				colours(c);
				continue;
			}
			if (idx < 0) break;
			var at = find(c.time);
			if (c.ending && c.size == 0 || at < 0) {
				MediaNdk.AMediaCodec_releaseOutputBuffer(c.codec, idx, false);
				if (c.ending) ended();
				continue;
			}
			var k = keys[at], t = times[at], show = shows[at];
			keys.splice(at, 1);
			times.splice(at, 1);
			shows.splice(at, 1);
			if (show && !layer.isNull()) held.push({idx: idx, time: t});
			else {
				MediaNdk.AMediaCodec_releaseOutputBuffer(c.codec, idx, show);
				if (show) {
					rendered.push(k);
					renderedTimes.push(t);
				}
			}
			if (c.ending) ended();
		}
		c.feed();
	}

	// (the end's output: what it never gave no longer waited for)
	function ended() {
		keys.resize(0);
		times.resize(0);
		shows.resize(0);
	}

	// (the entry an output's time is; else the earliest: a codec that times
	// its outputs anew gives them in presentation order)
	function find(k:Float):Int {
		if (keys.length == 0) return -1;
		var best = 0;
		for (i in 0...keys.length) {
			if (Math.abs(keys[i] - k) < 0.5) return i;
			if (keys[i] < keys[best]) best = i;
		}
		return best;
	}

	// (the output's colours as the system tagged its buffers, which the
	// driver converts by: its dataspace's standard and range, else
	// color-standard's and color-range's; unnamed, BT.601's video range, as
	// ffmpeg reads them. An H.264 of BT.709's matrix but no primaries is
	// BT.601's to Android)
	function colours(c:McCodec) {
		var d = c.output("android._dataspace"), s = c.output("color-standard"), r = c.output("color-range");
		if (d > 0) {
			s = switch d >> 16 & 63 {
				case 1: 1;
				case 6 | 7: 6;
				case _: 4;
			}
			r = d >> 27 & 7;
		}
		matrix = s == 1 ? "709" : s == 6 ? "2020" : "601";
		full = r == 1;
	}

	public function take(into:Array<VideoFrame>) {
		pump();
		for (h in held) into.push(new VideoFrame(this, h.time, track.width, track.height, matrix, full, bits, Ptr.ofI64(h.idx * 2 + 1)));
		held.resize(0);
		if (reader.isNull()) return;
		while (true) {
			var image = Arena.scopedValue(a -> {
				var out:Ptr<Ptr> = a.alloc(8);
				MediaNdk.AImageReader_acquireNextImage(reader, out) == 0 ? out.value : Ptr.nil();
			});
			if (image.isNull()) return;
			var ns = Arena.scopedValue(a -> {
				var out:Ptr<Int64> = a.alloc(8);
				MediaNdk.AImage_getTimestamp(image, out);
				var lo = Mem.getI32(out, 0), hi = Mem.getI32(out, 4);
				hi * 4294967296.0 + (lo < 0 ? lo + 4294967296.0 : lo);
			});
			var k = Math.round(ns / 1000), at = -1;
			for (i in 0...rendered.length) if (Math.abs(rendered[i] - k) < 0.5) at = i;
			// (one of before a seek: dropped)
			if (at < 0) {
				MediaNdk.AImage_delete(image);
				continue;
			}
			var t = renderedTimes[at];
			rendered.splice(at, 1);
			renderedTimes.splice(at, 1);
			var size = crop(image);
			into.push(new VideoFrame(this, t, size[0], size[1], matrix, full, bits, image));
			pump();
		}
	}

	// (its picture's size: the image's crop)
	static function crop(image:Ptr):Array<Int>
		return Arena.scopedValue(a -> {
			var r:Ptr<Int32> = a.alloc(16);
			MediaNdk.AImage_getCropRect(image, r);
			[r[2] - r[0], r[3] - r[1]];
		});

	public function flush() {
		if (codec == null) return;
		codec.push(null, 0, false);
		pump();
	}

	public function reset() {
		if (codec != null) codec.flush();
		for (h in held) if (codec != null) MediaNdk.AMediaCodec_releaseOutputBuffer(codec.codec, h.idx, false);
		held.resize(0);
		ended();
		rendered.resize(0);
		renderedTimes.resize(0);
		// (what the reader already has: of before the seek)
		var dropped = [];
		take(dropped);
		for (f in dropped) f.release();
	}

	// whether f is a buffer of the codec's for a layer (else an AImage)
	public static inline function buffered(f:VideoFrame):Bool
		return f.image.toI64().toInt() & 1 == 1;

	public function release(f:VideoFrame) {
		if (buffered(f)) {
			if (codec != null) MediaNdk.AMediaCodec_releaseOutputBuffer(codec.codec, f.image.toI64().toInt() >> 1, false);
		} else
			MediaNdk.AImage_delete(f.image);
	}

	// f onto the layer's surface at ns (System.nanoTime's clock), let go
	public function render(f:VideoFrame, ns:Float) {
		if (!buffered(f) || codec == null) return;
		MediaNdk.AMediaCodec_releaseOutputBufferAtTime(codec.codec, f.image.toI64().toInt() >> 1, (cast haxe.Int64.fromFloat(ns) : Int64));
		@:privateAccess f.image = Ptr.nil();
	}

	// the frames from now onto a layer's surface (an ANativeWindow), or the
	// reader's again (nil)
	public function output(surface:Ptr) {
		layer = surface;
		if (codec != null) MediaNdk.AMediaCodec_setOutputSurface(codec.codec, surface.isNull() ? window : surface);
	}

	// (its AHardwareBuffer by address and its size: GLBackend's openShared
	// imports it as an EGLImage; the picture is its crop, from the top left)
	public function plane(f:VideoFrame, plane:Int):Null<String> {
		if (buffered(f) || f.image.isNull()) return null;
		var b = Arena.scopedValue(a -> {
			var out:Ptr<Ptr> = a.alloc(8);
			MediaNdk.AImage_getHardwareBuffer(f.image, out) == 0 ? out.value : Ptr.nil();
		});
		if (b.isNull()) return null;
		var d = LibC.malloc(48);
		Hb.AHardwareBuffer_describe(b, d);
		var w = Mem.getI32(d, 0), h = Mem.getI32(d, 4);
		LibC.free(d);
		var v:haxe.Int64 = cast b.toI64();
		return 'ahb:${StringTools.hex(v.high, 8)}${StringTools.hex(v.low, 8)}:$w:$h';
	}

	// (the planes as YUV_420_888 or P010 has them: luma, then Cb and Cr
	// interleaved, rows packed; P010 16 bits a sample)
	public function pixels(f:VideoFrame):Bytes {
		if (buffered(f) || f.image.isNull()) return Bytes.alloc(0);
		var w = f.width, h = f.height, cw = (w + 1) >> 1, ch = (h + 1) >> 1;
		var bs = f.bits > 8 ? 2 : 1, out = Bytes.alloc((w * h + cw * ch * 2) * bs);
		Arena.scoped(a -> {
			var data:Ptr<Ptr> = a.alloc(8), len:Ptr<Int32> = a.alloc(4), row:Ptr<Int32> = a.alloc(4), px:Ptr<Int32> = a.alloc(4), r:Ptr<Int32> = a.alloc(16);
			MediaNdk.AImage_getCropRect(f.image, r);
			for (plane in 0...3) {
				if (MediaNdk.AImage_getPlaneData(f.image, plane, data, len) != 0) return;
				MediaNdk.AImage_getPlaneRowStride(f.image, plane, row);
				MediaNdk.AImage_getPlanePixelStride(f.image, plane, px);
				var base:Ptr<UInt8> = data.value, pw = plane == 0 ? w : cw, ph = plane == 0 ? h : ch;
				var x0 = plane == 0 ? r[0] : r[0] >> 1, y0 = plane == 0 ? r[1] : r[1] >> 1;
				for (y in 0...ph) for (x in 0...pw) for (b in 0...bs) {
					var v = Mem.getU8(base, (y0 + y) * row.value + (x0 + x) * px.value + b);
					if (plane == 0) out.set((y * w + x) * bs + b, v) else out.set((w * h + (y * cw + x) * 2 + plane - 1) * bs + b, v);
				}
			}
		});
		return out;
	}

	public function close() {
		reset();
		if (codec != null) codec.close();
		codec = null;
		if (!reader.isNull()) MediaNdk.AImageReader_delete(reader);
		reader = window = Ptr.nil();
	}
}
