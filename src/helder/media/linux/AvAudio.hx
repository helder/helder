package helder.media.linux;

#if ((!helder.os || helder.os == "linux") && hxmc.target != "wasm32-wasi")
import haxe.io.Bytes;
import helder.media.linux.Av;
import hxmc.unsafe.*;

// helder.media's AudioDecoder on Linux: libavcodec's decoder of the codec
// (AAC, MP3, Opus (libopus's where it has it), Vorbis, FLAC, ALAC), floats
// asked for, whatever it gives turned into two channels of floats (mono
// doubled), a packet's frames as it is sent; the end drained. OpusHead goes
// in with its pre-skip 0: the player trims the priming by the packets'
// times, as on the other systems.
@:hxmc.unsafe(gc)
class AvAudio implements AudioDecoder {
	public final rate:Int;
	public var decoded(default, null):Null<Packet>;
	public var pending(get, never):Int;
	// (tests) libavcodec's decoder
	public final name:String;

	final track:MediaTrack;
	final ctx:Ptr;
	final pkt:Ptr;
	final frame:Ptr;
	var drained = false;

	public static function supports(c:Codec):Bool
		return switch c {
			case Aac | Mp3 | Opus | Vorbis | Flac | Alac: Av.loaded();
			case _: false;
		}

	static function names(c:Codec):Array<String>
		return switch c {
			case Aac: ["aac"];
			case Mp3: ["mp3float", "mp3"];
			case Opus: ["libopus", "opus"];
			case Vorbis: ["vorbis", "libvorbis"];
			case Flac: ["flac"];
			case _: ["alac"];
		}

	// (the config as libavcodec takes it: OpusHead without its pre-skip,
	// FLAC's STREAMINFO alone, ALAC's box whole)
	static function config(t:MediaTrack):Null<Bytes> {
		var c = t.config;
		if (c == null) return null;
		return switch t.codec {
			case Opus if (c.length >= 12):
				var h = c.sub(0, c.length);
				h.set(10, 0);
				h.set(11, 0);
				h;
			case Flac: c.length >= 42 && c.get(0) == 0x66 ? c.sub(8, 34) : c.length >= 38 ? c.sub(4, 34) : c;
			case _: c;
		}
	}

	public function new(track:MediaTrack) {
		this.track = track;
		if (!supports(track.codec)) throw new MediaError(Av.missing() ?? 'no decoder for ${track.codec}');
		var o = Av.open(names(track.codec), true, config(track), [], Ptr.nil());
		ctx = o.ctx;
		name = o.name;
		pkt = Avcodec.av_packet_alloc();
		frame = Avutil.av_frame_alloc();
		var r = Av.get(ctx, "ar") ?? 0;
		rate = track.codec == Opus ? 48000 : r > 0 ? r : track.sampleRate;
	}

	function get_pending():Int
		return 0;

	public function decode(p:Null<Packet>, bytes:Null<Bytes>, samples:AudioBuffer):Int {
		decoded = p;
		if (p == null || bytes == null) return 0;
		if (drained) {
			Avcodec.avcodec_flush_buffers(ctx);
			drained = false;
		}
		if (!Av.packet(pkt, bytes, 0, p.key)) return 0;
		var r = Avcodec.avcodec_send_packet(ctx, pkt);
		Avcodec.av_packet_unref(pkt);
		// (a packet it cannot read: its frames lost, the stream going on, as ffmpeg's)
		if (r < 0 && r != Av.EAGAIN) return 0;
		return take(samples);
	}

	// (what it has out, appended into samples: the frames)
	function take(samples:AudioBuffer):Int {
		var n = 0;
		while (Avcodec.avcodec_receive_frame(ctx, frame) >= 0) {
			n += copy(samples, n);
			Avutil.av_frame_unref(frame);
		}
		return n;
	}

	// (frame's samples into samples from frame `at`, two channels of floats)
	function copy(samples:AudioBuffer, at:Int):Int {
		var n = Av.samples(frame), ch = Av.channels(ctx), fmt = Av.sampleFormat(frame);
		if (ch <= 0) ch = track.channels > 0 ? track.channels : 1;
		if (n <= 0) return 0;
		samples.room(at + n);
		var planar = StringTools.endsWith(fmt, "p"), kind = planar ? fmt.substr(0, fmt.length - 1) : fmt;
		var size = switch kind {
			case "u8": 1;
			case "s16": 2;
			case "dbl" | "s64": 8;
			case _: 4;
		}
		var left = Av.plane(frame, 0), right = planar && ch > 1 ? Av.plane(frame, 1) : left;
		var step = planar ? size : size * ch, r = planar || ch == 1 ? 0 : size;
		inline function read(p:Ptr, o:Int):Float
			return switch kind {
				case "flt": Mem.getF32(p, o);
				case "s16": Mem.getI16(p, o) / 32768;
				case "s32": Mem.getI32(p, o) / 2147483648.0;
				case "dbl": Mem.getF64(p, o);
				case "u8": (Mem.getU8(p, o) - 128) / 128;
				case _: 0.0;
			}
		for (i in 0...n) {
			samples.set((at + i) * 2, read(left, i * step));
			samples.set((at + i) * 2 + 1, read(right, i * step + r));
		}
		return n;
	}

	// the stream's end: what it holds, after the last packet's frames
	public function flush(samples:AudioBuffer):Int {
		if (drained) return 0;
		drained = true;
		if (Avcodec.avcodec_send_packet(ctx, Ptr.nil()) < 0) return 0;
		return take(samples);
	}

	public function reset() {
		Avcodec.avcodec_flush_buffers(ctx);
		drained = false;
		decoded = null;
	}

	public function close() {
		Av.freeFrame(frame);
		Av.freePacket(pkt);
		Av.free(ctx);
	}
}
#end
