package helder.media.linux;

#if ((!helder.os || helder.os == "linux") && hxmc.target != "wasm32-wasi")
import hxmc.unsafe.*;

// FFmpeg's libavcodec and libavutil, the system's (sonames 58 to 61: FFmpeg
// 4 to 7), loaded at run time (helder.os.Dl: nothing bundled; a program
// starts without them). Structs are read only where their layout is the
// same in all four (AVFrame's planes, size, format and pts; AVPacket's pts,
// data and flags; AVCodecParameters' type, id and extradata;
// AVDRMFrameDescriptor); what moves between them goes through accessors
// (AVOptions, avcodec_parameters_to_context, formats by name), but for
// hw_device_ctx, which has none (Av.device: its offset in each). Errors are
// negative AVERRORs.
@:build(helder.os.Dl.build())
@:hxmc.unsafe(gc)
class Avcodec {
	static function avcodec_version():Int;
	static function avcodec_find_decoder_by_name(name:Ptr):Ptr;
	static function avcodec_alloc_context3(codec:Ptr):Ptr;
	static function avcodec_free_context(ctx:Ptr<Ptr>):Void;
	static function avcodec_parameters_alloc():Ptr;
	static function avcodec_parameters_free(par:Ptr<Ptr>):Void;
	static function avcodec_parameters_to_context(ctx:Ptr, par:Ptr):Int;
	static function avcodec_open2(ctx:Ptr, codec:Ptr, options:Ptr):Int;
	static function avcodec_send_packet(ctx:Ptr, pkt:Ptr):Int;
	static function avcodec_receive_frame(ctx:Ptr, frame:Ptr):Int;
	static function avcodec_flush_buffers(ctx:Ptr):Void;
	static function av_packet_alloc():Ptr;
	static function av_packet_free(pkt:Ptr<Ptr>):Void;
	static function av_new_packet(pkt:Ptr, size:Int):Int;
	static function av_packet_unref(pkt:Ptr):Void;
}

@:build(helder.os.Dl.build())
@:hxmc.unsafe(gc)
class Avutil {
	static function av_log_set_level(level:Int):Void;
	static function av_malloc(size:Int64):Ptr;
	static function av_frame_alloc():Ptr;
	static function av_frame_free(frame:Ptr<Ptr>):Void;
	static function av_frame_unref(frame:Ptr):Void;
	static function av_frame_ref(dst:Ptr, src:Ptr):Int;
	static function av_opt_set_int(obj:Ptr, name:Ptr, v:Int64, flags:Int):Int;
	static function av_opt_set(obj:Ptr, name:Ptr, v:Ptr, flags:Int):Int;
	static function av_opt_get_int(obj:Ptr, name:Ptr, flags:Int, out:Ptr<Int64>):Int;
	static function av_get_pix_fmt_name(fmt:Int):CString;
	static function av_get_sample_fmt_name(fmt:Int):CString;
	static function av_get_pix_fmt(name:Ptr):Int;
	static function av_strerror(err:Int, buf:Ptr, size:Int64):Int;
	static function av_hwdevice_find_type_by_name(name:Ptr):Int;
	static function av_hwdevice_ctx_create(out:Ptr<Ptr>, type:Int, device:Ptr, options:Ptr, flags:Int):Int;
	static function av_buffer_ref(buf:Ptr):Ptr;
	static function av_buffer_unref(buf:Ptr<Ptr>):Void;
	static function av_hwframe_transfer_data(dst:Ptr, src:Ptr, flags:Int):Int;
	static function av_hwframe_map(dst:Ptr, src:Ptr, flags:Int):Int;
}

// (libavutil 57 and later: a decoder's channels as an AVChannelLayout,
// FFmpeg 7's only way; 4's is the "ac" option)
@:build(helder.os.Dl.build())
@:hxmc.unsafe(gc)
class AvLayout {
	static function av_opt_get_chlayout(obj:Ptr, name:Ptr, flags:Int, layout:Ptr):Int;
	static function av_channel_layout_uninit(layout:Ptr):Void;
}

@:hxmc.unsafe(gc)
class Av {
	// (AV_OPT_SEARCH_CHILDREN: a decoder's private options too)
	public static inline var CHILDREN = 1;
	public static inline var EAGAIN = -11;

	static var tried = false;
	static var why:Null<String>;
	// libavcodec's major version (58 to 61; 0: none)
	public static var major(default, null) = 0;
	static var layouts = false;

	// whether the system has libavcodec (once; why not: missing())
	public static function loaded():Bool {
		if (!tried) {
			tried = true;
			why = "no libavcodec.so.58 to 61";
			for (v in [61, 60, 59, 58]) {
				if (Avutil.load('libavutil.so.${v - 2}') != null) continue;
				var e = Avcodec.load('libavcodec.so.$v');
				if (e != null) continue;
				if (Avcodec.avcodec_version() >> 16 != v) continue;
				major = v;
				why = null;
				layouts = AvLayout.load('libavutil.so.${v - 2}') == null;
				// (AV_LOG_ERROR: its warnings are not ours to print)
				Avutil.av_log_set_level(16);
				break;
			}
		}
		return why == null;
	}

	// what is missing, said (null: nothing)
	public static function missing():Null<String> {
		loaded();
		return why == null ? null : 'helder.media: $why (FFmpeg\'s libavcodec, the system\'s package: libavcodec60 or libavcodec61, ffmpeg-libs, ffmpeg)';
	}

	// (AVCodecContext.hw_device_ctx: no accessor sets it; its offset in each
	// major version, from their headers, 64-bit)
	public static function device():Int
		return switch major {
			case 58: 1032;
			case 59: 872;
			case 60: 864;
			case 61: 560;
			case _: -1;
		}

	public static function error(e:Int):String
		return Arena.scopedValue(a -> {
			var b = a.alloc(128);
			Avutil.av_strerror(e, b, 128) < 0 ? 'error $e' : (cast b : CString).toString();
		});

	// a decoder by the first of its names this libavcodec has, opened on the
	// config (extradata) with options (and a hardware device: VAAPI's);
	// throws a MediaError where none opens
	public static function open(names:Array<String>, audio:Bool, config:Null<haxe.io.Bytes>, options:Map<String, Int>, hw:Ptr):{ctx:Ptr, name:String} {
		var tried = [];
		for (name in names) {
			var codec = Arena.scopedValue(a -> Avcodec.avcodec_find_decoder_by_name(a.cstring(name)));
			if (codec.isNull()) continue;
			var ctx = Avcodec.avcodec_alloc_context3(codec);
			if (ctx.isNull()) continue;
			var r = Arena.scopedValue(a -> {
				// (AVCodecParameters: codec_type, codec_id, extradata (padded), its size; the codec's type and id)
				var par = Avcodec.avcodec_parameters_alloc(), out:Ptr<Ptr> = a.alloc(8);
				Mem.setI32(par, 0, Mem.getI32(codec, 16));
				Mem.setI32(par, 4, Mem.getI32(codec, 20));
				if (config != null && config.length > 0) {
					var d = Avutil.av_malloc(config.length + 64);
					LibC.memset(d, 0, config.length + 64);
					LibC.memcpy(d, BytesPtr.of(config, 0, config.length), config.length);
					Mem.setPtr(par, 16, d);
					Mem.setI32(par, 24, config.length);
				}
				var r = Avcodec.avcodec_parameters_to_context(ctx, par);
				out.value = par;
				Avcodec.avcodec_parameters_free(out);
				if (r < 0) return r;
				for (k => v in options) Avutil.av_opt_set_int(ctx, a.cstring(k), v, CHILDREN);
				if (!hw.isNull()) Mem.setPtr(ctx, device(), Avutil.av_buffer_ref(hw));
				if (audio) Avutil.av_opt_set(ctx, a.cstring("request_sample_fmt"), a.cstring("flt"), CHILDREN);
				Avcodec.avcodec_open2(ctx, codec, Ptr.nil());
			});
			if (r >= 0) return {ctx: ctx, name: name};
			tried.push('$name: ${error(r)}');
			free(ctx);
		}
		throw new MediaError(tried.length == 0 ? 'libavcodec has no ${names.join(" or ")} decoder' : 'libavcodec opens no decoder (${tried.join("; ")})');
	}

	public static function free(ctx:Ptr)
		Arena.scoped(a -> {
			var p:Ptr<Ptr> = a.alloc(8);
			p.value = ctx;
			Avcodec.avcodec_free_context(p);
		});

	public static function freeFrame(f:Ptr)
		Arena.scoped(a -> {
			var p:Ptr<Ptr> = a.alloc(8);
			p.value = f;
			Avutil.av_frame_free(p);
		});

	public static function freePacket(pkt:Ptr)
		Arena.scoped(a -> {
			var p:Ptr<Ptr> = a.alloc(8);
			p.value = pkt;
			Avcodec.av_packet_free(p);
		});

	// an int option of the decoder's (its context's; null: none)
	public static function get(ctx:Ptr, name:String):Null<Int>
		return Arena.scopedValue(a -> {
			var v:Ptr<Int64> = a.alloc(8);
			Avutil.av_opt_get_int(ctx, a.cstring(name), CHILDREN, v) < 0 ? null : v.value.toInt();
		});

	// the decoder's channels: its layout's (FFmpeg 5 and later), else "ac" (4's)
	public static function channels(ctx:Ptr):Int {
		if (layouts) {
			var n = Arena.scopedValue(a -> {
				// (AVChannelLayout: order, nb_channels, the mask or map, opaque)
				var l = a.alloc(24);
				LibC.memset(l, 0, 24);
				if (AvLayout.av_opt_get_chlayout(ctx, a.cstring("ch_layout"), CHILDREN, l) < 0) return 0;
				var n = Mem.getI32(l, 4);
				AvLayout.av_channel_layout_uninit(l);
				n;
			});
			if (n > 0) return n;
		}
		return get(ctx, "ac") ?? 0;
	}

	// a packet of bytes, its pts (and flags: 1 a keyframe); nil where none was made
	public static function packet(pkt:Ptr, bytes:haxe.io.Bytes, pts:Int, key:Bool):Bool {
		if (Avcodec.av_new_packet(pkt, bytes.length) < 0) return false;
		LibC.memcpy(Mem.getPtr(pkt, 24), BytesPtr.of(bytes, 0, bytes.length), bytes.length);
		Mem.setI64(pkt, 8, pts);
		Mem.setI32(pkt, 40, key ? 1 : 0);
		return true;
	}

	// (AVFrame's: the planes, their pitches, extended_data, the size, samples, format and pts)
	public static inline function data(f:Ptr, i:Int):Ptr
		return Mem.getPtr(f, i * 8);

	public static inline function pitch(f:Ptr, i:Int):Int
		return Mem.getI32(f, 64 + i * 4);

	public static inline function plane(f:Ptr, i:Int):Ptr
		return Mem.getPtr(Mem.getPtr(f, 96), i * 8);

	public static inline function width(f:Ptr):Int
		return Mem.getI32(f, 104);

	public static inline function height(f:Ptr):Int
		return Mem.getI32(f, 108);

	public static inline function samples(f:Ptr):Int
		return Mem.getI32(f, 112);

	public static inline function format(f:Ptr):Int
		return Mem.getI32(f, 116);

	public static inline function pts(f:Ptr):Int
		return Mem.getI64(f, 136).toInt();

	public static function pixels(f:Ptr):String {
		var s = Avutil.av_get_pix_fmt_name(format(f));
		return s.isNull() ? "" : s.toString();
	}

	public static function sampleFormat(f:Ptr):String {
		var s = Avutil.av_get_sample_fmt_name(format(f));
		return s.isNull() ? "" : s.toString();
	}
}
#end
