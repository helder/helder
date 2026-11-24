package helder.media.linux;

#if ((!helder.os || helder.os == "linux") && hxmc.target != "wasm32-wasi")
import haxe.io.Bytes;
import helder.media.linux.Av;
import hxmc.unsafe.*;

// helder.media's VideoDecoder on Linux: libavcodec's decoder of the codec
// (H.264, HEVC, VP9; AV1 by libdav1d), on the GPU through VAAPI where a
// driver decodes it (libavcodec's hwaccel on a VAAPI device of libavutil's,
// libva loaded by it: the driver's surfaces its frames), else in software.
// A VAAPI frame is mapped as DMA-BUFs (plane "dmabuf:", one a plane:
// GLBackend imports them, no copy), its surface held while the frame is,
// at most HELD of them (the pool has EXTRA beyond the decoder's own); past
// that, or where the GL device cannot import them (copies), it is copied
// out (av_hwframe_transfer_data) and its surface let go at once: a pool
// whose surfaces the frames hold leaves the decoder none, #104's hang on
// Windows. A software frame is copied out at once into NV12 or P010 of ours
// (plane "mem:", uploaded as the texture is made). Each packet's pts is a
// serial of ours, its frame found by it.
@:hxmc.unsafe(gc)
class AvVideo implements VideoDecoder {
	// (tests) software decoding, VAAPI never asked
	public static var software = false;
	// VAAPI's frames copied out: the GL device imports no DMA-BUF (set by
	// VideoTexture where one was refused)
	public static var copies = false;
	static inline var EXTRA = 16;
	static inline var HELD = 10;
	// (a frame's record: our planes, their pitch and rows; VAAPI's frame and its DRM mapping; a serial)
	static inline var RECORD = 48;
	static var serials = 0;
	static var vaapi = Ptr.nil();
	static var vaTried = false;
	@:noCompletion public static var vaWhy(default, null) = "";

	public var pending(get, never):Int;
	// decoding on the GPU (VAAPI); why not (tests)
	public var hardware(default, null) = false;
	@:noCompletion public var why(default, null) = "";
	// (tests) libavcodec's decoder
	public var name(default, null) = "";

	final track:MediaTrack;
	var ctx = Ptr.nil();
	final pkt:Ptr;
	final frame:Ptr;
	final keys:Array<Int> = [];
	final times:Array<Float> = [];
	final shows:Array<Bool> = [];
	final ready:Array<VideoFrame> = [];
	var next = 0;
	var drained = false;
	var held = 0;
	var colours = false;
	var gpu = false;
	var matrix = "601";
	var full = false;

	public static function supports(c:Codec):Bool
		return switch c {
			case H264 | Hevc | Vp9 | Av1: Av.loaded();
			case _: false;
		}

	// (libavcodec's own AV1 decoder decodes with a hwaccel only)
	static function names(c:Codec, gpu:Bool):Array<String>
		return switch c {
			case H264: ["h264"];
			case Hevc: ["hevc"];
			case Vp9: ["vp9", "libvpx-vp9"];
			case _: gpu ? ["av1", "libdav1d", "libaom-av1"] : ["libdav1d", "libaom-av1", "av1"];
		}

	// a VAAPI device of libavutil's, once (nil: no driver here: vaWhy)
	public static function device():Ptr {
		if (vaTried || !Av.loaded()) return vaapi;
		vaTried = true;
		vaWhy = Arena.scopedValue(a -> {
			var type = Avutil.av_hwdevice_find_type_by_name(a.cstring("vaapi"));
			if (type <= 0) return "libavutil has no VAAPI";
			if (Av.device() < 0) return 'no hw_device_ctx known in libavcodec ${Av.major}';
			var out:Ptr<Ptr> = a.alloc(8);
			out.value = Ptr.nil();
			// (its default: X11's display, else /dev/dri/renderD128; LIBVA_DRIVER_NAME the driver)
			var r = Avutil.av_hwdevice_ctx_create(out, type, Ptr.nil(), Ptr.nil(), 0);
			if (r < 0) return 'no VAAPI device (${Av.error(r)})';
			vaapi = out.value;
			"";
		});
		return vaapi;
	}

	public function new(track:MediaTrack) {
		this.track = track;
		if (!supports(track.codec)) throw new MediaError(Av.missing() ?? 'no decoder for ${track.codec}');
		pkt = Avcodec.av_packet_alloc();
		frame = Avutil.av_frame_alloc();
	}

	function get_pending():Int
		return keys.length;

	// (VAAPI's decoder where there is a device, else software; its config
	// the extradata: avcC's and hvcC's lengths and sets are libavcodec's to read)
	function open() {
		var va = software ? Ptr.nil() : device(), config = track.codec == Vp9 ? null : track.config;
		why = software ? "asked for software" : va.isNull() ? vaWhy : "";
		var o = va.isNull() ? null : try Av.open(names(track.codec, true), false, config, ["threads" => 1, "extra_hw_frames" => EXTRA], va) catch (e:MediaError) {
			why = e.message;
			null;
		}
		gpu = o != null;
		if (o == null) o = Av.open(names(track.codec, false), false, config, ["threads" => 0], Ptr.nil());
		ctx = o.ctx;
		name = o.name;
	}

	public function decode(p:Packet, bytes:Bytes, show:Bool) {
		if (ctx.isNull()) open();
		if (drained) {
			Avcodec.avcodec_flush_buffers(ctx);
			drained = false;
		}
		var pts = next++;
		if (!Av.packet(pkt, bytes, pts, p.key)) return;
		keys.push(pts);
		times.push(p.time);
		shows.push(show);
		var r = Avcodec.avcodec_send_packet(ctx, pkt);
		// (full: what it has out taken, then the packet again)
		if (r == Av.EAGAIN) {
			pump();
			r = Avcodec.avcodec_send_packet(ctx, pkt);
		}
		Avcodec.av_packet_unref(pkt);
		if (r < 0 && r != Av.EAGAIN) {
			var at = keys.indexOf(pts);
			keys.splice(at, 1);
			times.splice(at, 1);
			shows.splice(at, 1);
		}
		pump();
	}

	// (what it has out: frames where shown, the others let go)
	function pump() {
		while (Avcodec.avcodec_receive_frame(ctx, frame) >= 0) {
			var at = keys.indexOf(Av.pts(frame));
			if (at < 0 && keys.length > 0) at = 0;
			if (at < 0) {
				Avutil.av_frame_unref(frame);
				continue;
			}
			var t = times[at], show = shows[at];
			keys.splice(at, 1);
			times.splice(at, 1);
			shows.splice(at, 1);
			var f = show ? made(t) : null;
			Avutil.av_frame_unref(frame);
			if (f != null) ready.push(f);
		}
	}

	// (the colours its context names, else the stream's SPS, else BT.601's video range)
	function named(fmt:String) {
		if (colours) return;
		colours = true;
		var m = Av.get(ctx, "colorspace") ?? 2, r = Av.get(ctx, "color_range") ?? 0, sps = CodecConfig.colours(track);
		matrix = m == 1 ? "709" : m == 9 || m == 10 ? "2020" : m == 2 && sps != null ? sps.matrix : "601";
		full = r == 2 || StringTools.startsWith(fmt, "yuvj") || r == 0 && sps != null && sps.full;
	}

	// (the frame received made ours: VAAPI's held and mapped, else copied out; null: a format not read)
	function made(t:Float):Null<VideoFrame> {
		var fmt = Av.pixels(frame), w = Av.width(frame), h = Av.height(frame);
		var r:Ptr = LibC.malloc(RECORD);
		LibC.memset(r, 0, RECORD);
		Mem.setI32(r, 32, ++serials);
		var ok = if (fmt == "vaapi") {
			hardware = true;
			var kept = !copies && held < HELD ? keep(r) : false;
			kept || copyOut(r, frame, w, h);
		} else {
			// (a profile the driver does not decode: libavcodec's software decoding instead)
			if (gpu && why == "") why = 'the driver does not decode this $fmt ${track.codec}';
			copy(r, frame, fmt, w, h);
		}
		if (!ok) {
			free(r);
			return null;
		}
		named(fmt);
		return new VideoFrame(this, t, w, h, matrix, full, Mem.getI32(r, 36), r);
	}

	// (VAAPI's frame held in r, mapped as DRM PRIME: its DMA-BUFs)
	function keep(r:Ptr):Bool {
		var own = Avutil.av_frame_alloc(), map = Avutil.av_frame_alloc();
		Avutil.av_frame_ref(own, frame);
		Mem.setI32(map, 116, Arena.scopedValue(a -> Avutil.av_get_pix_fmt(a.cstring("drm_prime"))));
		// (AV_HWFRAME_MAP_READ)
		if (Avutil.av_hwframe_map(map, own, 1) < 0) {
			Av.freeFrame(map);
			Av.freeFrame(own);
			return false;
		}
		Mem.setPtr(r, 16, own);
		Mem.setPtr(r, 24, map);
		Mem.setI32(r, 36, deep() ? 10 : 8);
		held++;
		return true;
	}

	// (the stream's depth, where a VAAPI frame does not say it)
	function deep():Bool
		return CodecConfig.depth(track) > 8;

	// (a VAAPI frame's planes copied into r: NV12 or P010)
	function copyOut(r:Ptr, hw:Ptr, w:Int, h:Int):Bool {
		var sw = Avutil.av_frame_alloc();
		var ok = Avutil.av_hwframe_transfer_data(sw, hw, 0) >= 0 && copy(r, sw, Av.pixels(sw), w, h);
		Av.freeFrame(sw);
		return ok;
	}

	// (a software frame's planes into memory of r's: luma, then Cb and Cr
	// interleaved, one pitch; P010's 10 bits at the top of 16)
	function copy(r:Ptr, f:Ptr, fmt:String, w:Int, h:Int):Bool {
		var deep = fmt == "yuv420p10le" || fmt == "p010le", semi = fmt == "nv12" || fmt == "p010le";
		if (!deep && !semi && fmt != "yuv420p" && fmt != "yuvj420p") return false;
		var bs = deep ? 2 : 1, cw = (w + 1) >> 1, ch = (h + 1) >> 1, pitch = cw * 2 * bs;
		var at:Ptr = LibC.malloc(pitch * (h + ch));
		Mem.setPtr(r, 0, at);
		Mem.setI32(r, 8, pitch);
		Mem.setI32(r, 12, h);
		Mem.setI32(r, 36, deep ? 10 : 8);
		var y = Av.data(f, 0), yp = Av.pitch(f, 0), shift = deep && !semi ? 6 : 0;
		for (row in 0...h) {
			var src = y.add(row * yp), dst = at.add(row * pitch);
			if (shift == 0) LibC.memcpy(dst, src, w * bs) else for (i in 0...w) Mem.setI16(dst, i * 2, Mem.getU16(src, i * 2) << 6);
		}
		var uv = at.add(pitch * h);
		if (semi) {
			for (row in 0...ch) LibC.memcpy(uv.add(row * pitch), Av.data(f, 1).add(row * Av.pitch(f, 1)), cw * 2 * bs);
			return true;
		}
		var u = Av.data(f, 1), v = Av.data(f, 2), up = Av.pitch(f, 1), vp = Av.pitch(f, 2);
		for (row in 0...ch) {
			var cu = u.add(row * up), cv = v.add(row * vp), dst = uv.add(row * pitch);
			if (deep) for (i in 0...cw) {
				Mem.setI16(dst, i * 4, Mem.getU16(cu, i * 2) << 6);
				Mem.setI16(dst, i * 4 + 2, Mem.getU16(cv, i * 2) << 6);
			} else for (i in 0...cw) {
				Mem.setI8(dst, i * 2, Mem.getU8(cu, i));
				Mem.setI8(dst, i * 2 + 1, Mem.getU8(cv, i));
			}
		}
		return true;
	}

	// (r's VAAPI frame made memory of ours, its surface let go)
	function own(f:VideoFrame):Bool {
		var r = f.image;
		if (r.isNull()) return false;
		if (!Mem.getPtr(r, 0).isNull()) return true;
		var hw = Mem.getPtr(r, 16);
		if (hw.isNull()) return false;
		var ok = copyOut(r, hw, f.width, f.height);
		unhold(r);
		return ok;
	}

	function unhold(r:Ptr) {
		var map = Mem.getPtr(r, 24), hw = Mem.getPtr(r, 16);
		if (!map.isNull()) Av.freeFrame(map);
		if (!hw.isNull()) {
			Av.freeFrame(hw);
			held--;
		}
		Mem.setPtr(r, 16, Ptr.nil());
		Mem.setPtr(r, 24, Ptr.nil());
	}

	function free(r:Ptr) {
		unhold(r);
		var at = Mem.getPtr(r, 0);
		if (!at.isNull()) LibC.free(at);
		LibC.free(r);
	}

	public function take(into:Array<VideoFrame>) {
		if (!ctx.isNull()) pump();
		for (f in ready) into.push(f);
		ready.resize(0);
	}

	public function flush() {
		if (ctx.isNull() || drained) return;
		drained = true;
		Avcodec.avcodec_send_packet(ctx, Ptr.nil());
		pump();
		// (drained: what never came will not)
		keys.resize(0);
		times.resize(0);
		shows.resize(0);
	}

	public function reset() {
		if (!ctx.isNull()) Avcodec.avcodec_flush_buffers(ctx);
		drained = false;
		keys.resize(0);
		times.resize(0);
		shows.resize(0);
		for (f in ready) f.release();
		ready.resize(0);
	}

	public function release(f:VideoFrame)
		free(f.image);

	// (GLBackend.openShared's: a VAAPI frame's plane as a DMA-BUF of this
	// process's (pid 0), its DRM format the plane's (R8, GR88; R16, GR1616);
	// else our memory, uploaded as it is opened; each frame its own handle)
	public function plane(f:VideoFrame, plane:Int):Null<String> {
		var r = f.image;
		if (r.isNull()) return null;
		var deep = f.bits > 8, map = Mem.getPtr(r, 24), serial = Mem.getI32(r, 32);
		if (!map.isNull() && !copies) {
			var d = Av.data(map, 0), layers = Mem.getI32(d, 104);
			var layer = d.add(112 + (layers > 1 ? plane : 0) * 104), p = layer.add(8 + (layers > 1 ? 0 : plane) * 24);
			var object = d.add(8 + Mem.getI32(p, 0) * 24);
			var fourcc = plane == 0 ? (deep ? 0x20363152 : 0x20203852) : deep ? 0x32335247 : 0x38385247;
			return 'dmabuf:0:${Mem.getI32(object, 0)}:$fourcc:${Mem.getI32(p, 16)}:${Mem.getI32(p, 8)}:${Mem.getI32(object, 20)}:${Mem.getI32(object, 16)}:$serial';
		}
		if (!own(f)) return null;
		var format = plane == 0 ? (deep ? "r16" : "r8") : deep ? "rg16" : "rg8", at = Mem.getPtr(r, 0), pitch = Mem.getI32(r, 8);
		return 'mem:${hex(at.add(plane == 0 ? 0 : pitch * Mem.getI32(r, 12)))}:$pitch:$format:$serial';
	}

	static function hex(p:Ptr):String {
		var v:haxe.Int64 = cast p.toI64();
		return StringTools.hex(v.high, 8) + StringTools.hex(v.low, 8);
	}

	// (luma, then Cb and Cr interleaved, rows packed; P010 16 bits a sample)
	public function pixels(f:VideoFrame):Bytes {
		if (!own(f)) return Bytes.alloc(0);
		var r = f.image, at = Mem.getPtr(r, 0), pitch = Mem.getI32(r, 8);
		var w = f.width, h = f.height, cw = (w + 1) >> 1, ch = (h + 1) >> 1;
		var bs = f.bits > 8 ? 2 : 1, out = Bytes.alloc((w * h + cw * ch * 2) * bs);
		var luma = w * bs, chroma = cw * 2 * bs, uv = at.add(pitch * h);
		for (y in 0...h)
			BytesPtr.copyIn(out, y * luma, at.add(y * pitch), luma);
		for (y in 0...ch)
			BytesPtr.copyIn(out, w * h * bs + y * chroma, uv.add(y * pitch), chroma);
		return out;
	}

	public function close() {
		reset();
		if (!ctx.isNull()) Av.free(ctx);
		ctx = Ptr.nil();
		Av.freeFrame(frame);
		Av.freePacket(pkt);
	}
}
#end
