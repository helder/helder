package helder.media.apple;

import haxe.io.Bytes;
import helder.media.apple.CoreMedia;
import helder.os.apple.objc.*;
import hxmc.Platform;
import hxmc.unsafe.*;

// helder.media's VideoDecoder on Apple's systems: a VTDecompressionSession
// (the hardware's decoder where VTIsHardwareDecodeSupported, else the
// system's own in software) of a format description made from the
// track's config (avcC, hvcC, vpcC, av1C as sample description atoms; a
// WebM's VP9 a vpcC of its first keyframe's header), decoding
// asynchronously into CVPixelBuffers on IOSurfaces Metal reads (NV12 or
// P010, video or full range). Its output callback runs on VideoToolbox's
// threads, where nothing may collect: it retains the buffer into a ring in
// native memory (single producer at a time, VideoToolbox serialising its
// callbacks), take() reads it on ours. A frame's time goes as the
// callback's refCon: a serial into the times kept here.
@:hxmc.unsafe(gc)
class VtDecoder implements VideoDecoder {
	static inline var SLOTS = 64;
	static inline var WRITTEN = 0;
	static inline var READ = 4;
	static inline var HEADER = 8;
	static inline var SLOT = 16;

	// NV12 and P010, video and full range: 420v 420f x420 xf20
	static final FORMATS = [0x34323076, 0x34323066, 0x78343230, 0x78663230];

	public var pending(get, never):Int;

	final track:MediaTrack;
	final codec:Int;
	final ring:Ptr;
	final times = new haxe.ds.Vector<Float>(256);
	var serial = 0;
	var out = 0;
	var session = Ptr.nil();
	var format = Ptr.nil();

	public static function supports(c:Codec):Bool
		return code(c) != 0;

	static function code(c:Codec):Int
		return switch c {
			case H264: 0x61766331; // avc1
			case Hevc: 0x68766331; // hvc1
			case Vp9: 0x76703039; // vp09
			case Av1: 0x61763031; // av01
			case _: 0;
		}

	// whether the system's hardware decodes it (VP9's and AV1's decoders are only that)
	public static function hardware(c:Codec):Bool {
		var k = code(c);
		if (k == 0) return false;
		register(k);
		return VideoToolbox.VTIsHardwareDecodeSupported(k);
	}

	// (macOS: VP9's and AV1's decoders loaded on request)
	static function register(k:Int) {
		#if (!helder.os || helder.os == "macos")
		if (Platform.apple() == 0 && (k == 0x76703039 || k == 0x61763031)) VideoToolbox.VTRegisterSupplementalVideoDecoderIfAvailable(k);
		#end
	}

	public function new(track:MediaTrack) {
		this.track = track;
		codec = code(track.codec);
		if (codec == 0) throw new MediaError('no decoder for ${track.codec}');
		register(codec);
		ring = LibC.malloc(HEADER + SLOTS * SLOT);
		LibC.memset(ring, 0, HEADER + SLOTS * SLOT);
	}

	function get_pending():Int
		return serial - out - (Atomic.load32(ring.add(WRITTEN)) - Atomic.load32(ring.add(READ)));

	// (made at the first packet: a WebM's VP9 has its configuration in its first keyframe)
	function open(first:Bytes) {
		var config = track.config;
		if (config == null && track.codec == Vp9) config = vpcC(first);
		var pool = Runtime.objc_autoreleasePoolPush();
		var st = Arena.scopedValue(a -> {
			var p:Ptr<Ptr> = a.alloc(8);
			// (H.264's and HEVC's from their parameter sets: CoreMedia reads
			// their colours and range there, which it does not from the atoms)
			var s = sets(config, a, p);
			if (s != 0) {
				var ext = config == null ? Ptr.nil() : dict(["SampleDescriptionExtensionAtoms", dict([atom(track.codec), data(config)])]);
				s = CoreMedia.CMVideoFormatDescriptionCreate(Ptr.nil(), codec, track.width, track.height, ext, p);
			}
			if (s != 0) return s;
			format = p.value;
			// (one format, the stream's depth and range: NV12 or P010; with
			// none the hardware gives its compressed ones, with a list it
			// converts to the first)
			var full = range(config), deep = depth(config) > 8;
			var attrs = dict([
				"PixelFormatType", num(deep ? (full ? 0x78663230 : 0x78343230) : (full ? 0x34323066 : 0x34323076)),
				"IOSurfaceProperties", Msg.id(ObjC.cls("NSDictionary"), ObjC.sel("dictionary")),
				"MetalCompatibility", Msg.idInt(ObjC.cls("NSNumber"), ObjC.sel("numberWithBool:"), 1)
			]);
			var cb:Ptr<Ptr> = a.alloc(16);
			Mem.setPtr(cb, 0, Callback.addr(output));
			Mem.setPtr(cb, 8, ring);
			s = VideoToolbox.VTDecompressionSessionCreate(Ptr.nil(), format, Ptr.nil(), attrs, cb, p);
			if (s == 0) session = p.value;
			s;
		});
		Runtime.objc_autoreleasePoolPop(pool);
		if (st != 0) throw new MediaError('the system does not decode this ${track.codec} (OSStatus $st)');
	}

	// (avcC's or hvcC's parameter sets into a format description: 0, else not made)
	function sets(c:Null<Bytes>, a:Arena, out:Ptr<Ptr>):Int {
		if (c == null || (track.codec != H264 && track.codec != Hevc)) return -1;
		var list:Array<Bytes> = [], length = 4;
		try {
			if (track.codec == H264) {
				length = (c.get(4) & 3) + 1;
				var at = 5;
				for (kind in 0...2) {
					var n = c.get(at++) & (kind == 0 ? 31 : 255);
					for (_ in 0...n) {
						var size = c.get(at) << 8 | c.get(at + 1);
						list.push(c.sub(at + 2, size));
						at += 2 + size;
					}
				}
			} else {
				length = (c.get(21) & 3) + 1;
				var at = 23;
				for (_ in 0...c.get(22)) {
					var n = c.get(at + 1) << 8 | c.get(at + 2);
					at += 3;
					for (_ in 0...n) {
						var size = c.get(at) << 8 | c.get(at + 1);
						list.push(c.sub(at + 2, size));
						at += 2 + size;
					}
				}
			}
		} catch (_:Dynamic) return -1;
		if (list.length == 0) return -1;
		var ptrs:Ptr<Ptr> = a.alloc(8 * list.length), sizes:Ptr<Int64> = a.alloc(8 * list.length);
		for (i in 0...list.length) {
			Mem.setPtr(ptrs, i * 8, a.copyBytes(list[i]));
			Mem.setI64(sizes, i * 8, list[i].length);
		}
		return track.codec == H264 ? CoreMedia.CMVideoFormatDescriptionCreateFromH264ParameterSets(Ptr.nil(), list.length, ptrs, sizes, length, out)
			: CoreMedia.CMVideoFormatDescriptionCreateFromHEVCParameterSets(Ptr.nil(), list.length, ptrs, sizes, length, Ptr.nil(), out);
	}

	// (full range: the format description's, else VP9's vpcC's)
	function range(c:Null<Bytes>):Bool {
		var k = ObjC.str("FullRangeVideo");
		var v = CoreMedia.CMFormatDescriptionGetExtension(format, k);
		ObjC.release(k);
		if (!v.isNull()) return Msg.b(v, ObjC.sel("boolValue"));
		return track.codec == Vp9 && c != null && c.length > 6 && c.get(6) & 1 == 1;
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

	// (VideoToolbox's threads: the buffer retained into the ring; a frame
	// not shown, dropped or failed leaves no slot)
	@:hxmc.callback @:hxmc.noGc static function output(ring:Ptr, refCon:Ptr, status:Int, flags:Int, image:Ptr):Void {
		var w = Atomic.load32(ring.add(WRITTEN));
		var at = ring.add(HEADER + (w & (SLOTS - 1)) * SLOT);
		Mem.setI32(at, 8, refCon.toI64().toInt());
		if (status != 0 || image.isNull() || w - Atomic.load32(ring.add(READ)) >= SLOTS) {
			Mem.setPtr(at, 0, Ptr.nil());
		} else
			Mem.setPtr(at, 0, FastCV.CVPixelBufferRetain(image));
		Atomic.store32(ring.add(WRITTEN), w + 1);
	}

	public function decode(p:Packet, bytes:Bytes, show:Bool) {
		if (session.isNull()) open(bytes);
		var n = bytes.length;
		var sample = Arena.scopedValue(a -> {
			var out:Ptr<Ptr> = a.alloc(8);
			if (CoreMedia.CMBlockBufferCreateWithMemoryBlock(Ptr.nil(), Ptr.nil(), n, Ptr.nil(), Ptr.nil(), 0, n, 1, out) != 0) return Ptr.nil();
			var block = out.value, at:Ptr<Ptr> = a.alloc(8);
			CoreMedia.CMBlockBufferGetDataPointer(block, 0, Ptr.nil(), Ptr.nil(), at);
			LibC.memcpy(at.value, BytesPtr.of(bytes, 0, n), (n : Int64));
			// (CMSampleTimingInfo: duration, pts, dts)
			var timing = a.alloc(72), size:Ptr<Int64> = a.alloc(8);
			var scale = Std.int(track.timescale);
			time(timing, 0, p.duration, scale);
			time(timing, 24, p.pts, scale);
			time(timing, 48, p.dts, scale);
			size.value = n;
			var s = CoreMedia.CMSampleBufferCreateReady(Ptr.nil(), block, format, 1, 1, timing, 1, size, out);
			CF.CFRelease(block);
			s == 0 ? out.value : Ptr.nil();
		});
		if (sample.isNull()) throw new MediaError("a sample buffer could not be made");
		times[serial & 255] = p.time;
		// (asynchronous; not output: kVTDecodeFrame_DoNotOutputFrame)
		var st = VideoToolbox.VTDecompressionSessionDecodeFrame(session, sample, 1 | (show ? 0 : 2), Ptr.ofI64(serial), Ptr.nil());
		CF.CFRelease(sample);
		serial++;
		if (st != 0) {
			// (a frame it refused: none comes for it)
			out++;
		}
	}

	static function time(at:Ptr, off:Int, ticks:Float, scale:Int) {
		Mem.setI64(at, off, (cast haxe.Int64.fromFloat(ticks) : Int64));
		Mem.setI32(at, off + 8, scale);
		Mem.setI32(at, off + 12, 1); // kCMTimeFlags_Valid
		Mem.setI64(at, off + 16, 0);
	}

	public function take(into:Array<VideoFrame>) {
		var r = Atomic.load32(ring.add(READ)), w = Atomic.load32(ring.add(WRITTEN));
		while (r != w) {
			var at = ring.add(HEADER + (r & (SLOTS - 1)) * SLOT);
			var image = Mem.getPtr(at, 0), s = Mem.getI32(at, 8);
			r++;
			out++;
			if (!image.isNull()) into.push(frame(image, times[s & 255]));
		}
		Atomic.store32(ring.add(READ), r);
	}

	function frame(image:Ptr, time:Float):VideoFrame {
		var f = CoreVideo.CVPixelBufferGetPixelFormatType(image);
		var full = f == 0x34323066 || f == 0x78663230, bits = f == 0x78343230 || f == 0x78663230 ? 10 : 8;
		if (!FORMATS.contains(f)) throw new MediaError('a pixel format of the decoder\'s not read here (${StringTools.hex(f, 8)})');
		var m = attachment(image, "CVImageBufferYCbCrMatrix");
		var matrix = m == null ? (track.height > 576 ? "709" : "601") : StringTools.contains(m, "2020") ? "2020" : StringTools.contains(m, "709") ? "709" : "601";
		return new VideoFrame(this, time, CoreVideo.CVPixelBufferGetWidth(image).toInt(), CoreVideo.CVPixelBufferGetHeight(image).toInt(), matrix, full, bits, image);
	}

	static function attachment(b:Ptr, key:String):Null<String> {
		var k = ObjC.str(key);
		var v = CoreVideo.CVBufferCopyAttachment(b, k, Ptr.nil());
		ObjC.release(k);
		if (v.isNull()) return null;
		var s = ObjC.string(v);
		CF.CFRelease(v);
		return s;
	}

	public function flush() {
		if (session.isNull()) return;
		VideoToolbox.VTDecompressionSessionFinishDelayedFrames(session);
		VideoToolbox.VTDecompressionSessionWaitForAsynchronousFrames(session);
	}

	// the frames given decoded (a test's, a thumbnail's)
	public function wait()
		if (!session.isNull()) VideoToolbox.VTDecompressionSessionWaitForAsynchronousFrames(session);

	public function reset() {
		wait();
		var dropped = [];
		take(dropped);
		for (f in dropped) f.release();
	}

	public function release(f:VideoFrame)
		CF.CFRelease(f.image);

	// (its IOSurface's, by id: the texture keeps the surface while it lives)
	public function plane(f:VideoFrame, plane:Int):Null<String> {
		var s = CoreVideo.CVPixelBufferGetIOSurface(f.image);
		if (s.isNull()) return null;
		return 'iosurface:${Surfaces.IOSurfaceGetID(s)}:$plane:${plane == 0 ? "r" : "rg"}${f.bits > 8 ? 16 : 8}';
	}

	public function close() {
		reset();
		if (!session.isNull()) {
			VideoToolbox.VTDecompressionSessionInvalidate(session);
			CF.CFRelease(session);
		}
		if (!format.isNull()) CF.CFRelease(format);
		session = format = Ptr.nil();
	}

	static function atom(c:Codec):String
		return switch c {
			case H264: "avcC";
			case Hevc: "hvcC";
			case Vp9: "vpcC";
			case _: "av1C";
		}

	// (a vpcC of VP9's uncompressed header: its profile, bit depth,
	// subsampling and range; colours unspecified)
	static function vpcC(key:Bytes):Bytes {
		var bit = 0;
		function read(n:Int):Int {
			var v = 0;
			for (_ in 0...n) {
				var b = bit >> 3 < key.length ? (key.get(bit >> 3) >> (7 - (bit & 7))) & 1 : 0;
				v = (v << 1) | b;
				bit++;
			}
			return v;
		}
		read(2);
		var profile = read(1) | (read(1) << 1);
		if (profile == 3) read(1);
		var depth = 8, sub = 1, full = 0;
		if (read(1) == 0 && read(1) == 0) {
			read(2);
			read(24);
			if (profile >= 2) depth = read(1) == 1 ? 12 : 10;
			var space = read(3);
			if (space != 7) {
				full = read(1);
				if (profile == 1 || profile == 3) sub = read(1) == 1 ? (read(1) == 1 ? 1 : 2) : 3;
			} else sub = 3;
		}
		var b = Bytes.alloc(12);
		b.set(0, 1);
		b.set(4, profile);
		b.set(5, 10);
		b.set(6, (depth << 4) | (sub << 1) | full);
		b.set(7, 2);
		b.set(8, 2);
		b.set(9, 2);
		return b;
	}

	static function dict(kv:Array<Dynamic>):Ptr {
		var d = Msg.id(ObjC.cls("NSMutableDictionary"), ObjC.sel("dictionary"));
		var i = 0;
		while (i < kv.length) {
			var k = ObjC.str(kv[i]);
			Msg.vPtrPtr(d, ObjC.sel("setObject:forKey:"), kv[i + 1], k);
			ObjC.release(k);
			i += 2;
		}
		return d;
	}

	static function num(v:Int):Ptr
		return Msg.idInt(ObjC.cls("NSNumber"), ObjC.sel("numberWithUnsignedInt:"), v);

	static function data(b:Bytes):Ptr
		return Arena.scopedValue(a -> Msg.idPtrInt(ObjC.cls("NSData"), ObjC.sel("dataWithBytes:length:"), a.copyBytes(b), b.length));

	public function pixels(f:VideoFrame):Bytes {
		var b = f.image, out = new haxe.io.BytesBuffer();
		CoreVideo.CVPixelBufferLockBaseAddress(b, 1);
		var px = f.bits > 8 ? 2 : 1;
		for (plane in 0...2) {
			var base:Ptr<UInt8> = CoreVideo.CVPixelBufferGetBaseAddressOfPlane(b, plane);
			var row = CoreVideo.CVPixelBufferGetBytesPerRowOfPlane(b, plane).toInt();
			var w = CoreVideo.CVPixelBufferGetWidthOfPlane(b, plane).toInt() * px * (plane == 0 ? 1 : 2);
			var h = CoreVideo.CVPixelBufferGetHeightOfPlane(b, plane).toInt();
			var line = Bytes.alloc(w);
			for (y in 0...h) {
				BytesPtr.copyIn(line, 0, base.add(y * row), w);
				out.add(line);
			}
		}
		CoreVideo.CVPixelBufferUnlockBaseAddress(b, 1);
		return out.getBytes();
	}
}
