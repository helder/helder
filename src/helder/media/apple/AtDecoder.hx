package helder.media.apple;

import haxe.io.Bytes;
import helder.media.apple.CoreMedia;
import hxmc.unsafe.*;

// helder.media's AudioDecoder on Apple's systems: an AudioConverter
// (AudioToolbox) from the codec to interleaved floats at the track's rate,
// two channels (a channel map: mono to both, the first two of more), its
// magic cookie the track's config. A packet a call: the converter's input
// callback (on this thread, inside the call) gives it the packet once,
// then says there is no more for now. AAC, MP3, ALAC, FLAC and Opus.
@:hxmc.unsafe(gc)
class AtDecoder implements AudioDecoder {
	// the input's state in native memory (the callback's user data): the
	// packet's address and size, whether it was given, its description
	static inline var DATA = 0;
	static inline var SIZE = 8;
	static inline var GIVEN = 12;
	static inline var CHANNELS = 16;
	static inline var DESC = 24; // AudioStreamPacketDescription: start (8), frames (4), size (4)
	static inline var STATE = 40;
	static inline var MORE = 0x6d6f7265; // 'more': the input's "none for now"

	public final rate:Int;
	public var decoded(default, null):Null<Packet>;

	final converter:Ptr;
	final state:Ptr;
	var input:Ptr = Ptr.nil();
	var inputSize = 0;
	final list:Ptr;
	// (frames asked for a call: a packet's, where the format says; FLAC's
	// decoder gives nothing when asked for more than the packet it has)
	final chunk:Int;

	public static function supports(c:Codec):Bool
		return format(c) != 0;

	static function format(c:Codec):Int
		return switch c {
			case Aac: 0x61616320; // 'aac '
			case Mp3: 0x2e6d7033; // '.mp3'
			case Alac: 0x616c6163;
			case Flac: 0x666c6163;
			case Opus: 0x6f707573;
			case _: 0;
		}

	public function new(track:MediaTrack) {
		var id = format(track.codec);
		if (id == 0) throw new MediaError('no decoder for ${track.codec}');
		rate = track.codec == Opus ? 48000 : track.sampleRate;
		var channels = track.channels > 0 ? track.channels : 2;
		state = LibC.malloc(STATE);
		LibC.memset(state, 0, STATE);
		Mem.setI32(state, CHANNELS, channels);
		list = LibC.malloc(24);
		chunk = frames(track) > 0 ? frames(track) : 8192;
		converter = Arena.scopedValue(a -> {
			var from = a.alloc(40), to = a.alloc(40);
			LibC.memset(from, 0, 40);
			Mem.setF64(from, 0, rate);
			Mem.setI32(from, 8, id);
			Mem.setI32(from, 12, depth(track));
			Mem.setI32(from, 20, frames(track));
			Mem.setI32(from, 28, channels);
			// (to: 32-bit floats, packed, two channels)
			Mem.setF64(to, 0, rate);
			Mem.setI32(to, 8, 0x6c70636d);
			Mem.setI32(to, 12, 1 | 8);
			Mem.setI32(to, 16, 8);
			Mem.setI32(to, 20, 1);
			Mem.setI32(to, 24, 8);
			Mem.setI32(to, 28, 2);
			Mem.setI32(to, 32, 32);
			Mem.setI32(to, 36, 0);
			var out:Ptr<Ptr> = a.alloc(8);
			var st = Converter.AudioConverterNew(from, to, out);
			if (st != 0) throw new MediaError('the system does not decode ${track.codec} (OSStatus $st)');
			var c = out.value;
			var cookie = track.config;
			// (Matroska's FLAC: "fLaC" and its blocks; the decoder takes STREAMINFO's body)
			if (track.codec == Flac && cookie != null && cookie.length >= 42 && cookie.get(0) == 0x66) cookie = cookie.sub(8, 34);
			if (cookie != null && cookie.length > 0)
				Converter.AudioConverterSetProperty(c, 0x646d6763, cookie.length, a.copyBytes(cookie)); // 'dmgc': the magic cookie
			if (channels != 2) {
				// ('chmp': each output channel's input)
				var map:Ptr<Int32> = a.alloc(8);
				Mem.setI32(map, 0, 0);
				Mem.setI32(map, 4, channels == 1 ? 0 : 1);
				Converter.AudioConverterSetProperty(c, 0x63686d70, 8, map);
			}
			c;
		});
	}

	// (a packet's frames, where the format has a fixed number)
	static function frames(t:MediaTrack):Int
		return switch t.codec {
			case Aac: 1024;
			case Mp3: 1152;
			case Opus: 960;
			// (STREAMINFO's largest block; Matroska's after "fLaC" and a block header)
			case Flac if (t.config != null && t.config.length >= 34): be(t.config, t.config.get(0) == 0x66 ? 10 : 2, 2);
			// (the alac box's frame length)
			case Alac if (t.config != null && t.config.length >= 16): be(t.config, 12, 4);
			case _: 0;
		}

	// (FLAC's source depth, the lossless formats' flag: 16, 20, 24 or 32 bits)
	static function depth(t:MediaTrack):Int {
		var c = t.config;
		if (t.codec != Flac || c == null || c.length < 34) return 0;
		var at = c.get(0) == 0x66 ? 8 : 0;
		var bits = ((c.get(at + 12) & 1) << 4 | c.get(at + 13) >> 4) + 1;
		return switch bits {
			case 16: 1;
			case 20: 2;
			case 24: 3;
			case 32: 4;
			case _: 0;
		}
	}

	static function be(b:Bytes, at:Int, n:Int):Int {
		var v = 0;
		for (i in 0...n) v = v << 8 | b.get(at + i);
		return v;
	}

	// the converter's input: the packet, once
	@:hxmc.callback @:hxmc.noGc static function give(converter:Ptr, packets:Ptr, list:Ptr, descs:Ptr, state:Ptr):Int {
		if (Mem.getI32(state, GIVEN) != 0) {
			Mem.setI32(packets, 0, 0);
			return MORE;
		}
		Mem.setI32(state, GIVEN, 1);
		Mem.setI32(packets, 0, 1);
		Mem.setI32(list, 0, 1);
		Mem.setI32(list, 8, Mem.getI32(state, CHANNELS));
		Mem.setI32(list, 12, Mem.getI32(state, SIZE));
		Mem.setPtr(list, 16, Mem.getPtr(state, DATA));
		if (!descs.isNull()) {
			var d = state.add(DESC);
			Mem.setI64(d, 0, 0);
			Mem.setI32(d, 8, 0);
			Mem.setI32(d, 12, Mem.getI32(state, SIZE));
			Mem.setPtr(descs, 0, d);
		}
		return 0;
	}

	public function decode(p:Null<Packet>, bytes:Null<Bytes>, samples:AudioBuffer):Int {
		decoded = p;
		if (p == null || bytes == null) return 0;
		var n = bytes.length;
		if (n > inputSize) {
			if (!input.isNull()) LibC.free(input);
			input = LibC.malloc(inputSize = n * 2);
		}
		LibC.memcpy(input, BytesPtr.of(bytes, 0, n), (n : Int64));
		Mem.setPtr(state, DATA, input);
		Mem.setI32(state, SIZE, n);
		Mem.setI32(state, GIVEN, 0);
		var total = 0;
		// (a packet may give more frames than one call takes: until it is used up)
		while (true) {
			samples.room(total + chunk);
			Mem.setI32(list, 0, 1);
			Mem.setI32(list, 8, 2);
			Mem.setI32(list, 12, chunk * 8);
			Mem.setPtr(list, 16, samples.data.add(total * 8));
			var got = Arena.scopedValue(a -> {
				var count:Ptr<Int32> = a.alloc(4);
				count.value = chunk;
				var st = Converter.AudioConverterFillComplexBuffer(converter, Callback.addr(give), state, count, list, Ptr.nil());
				if (st != 0 && st != MORE) throw new MediaError('a packet the decoder refused (OSStatus $st)');
				count.value;
			});
			total += got;
			if (got < chunk) break;
		}
		return total;
	}

	public function reset()
		Converter.AudioConverterReset(converter);

	public function close() {
		Converter.AudioConverterDispose(converter);
		if (!input.isNull()) LibC.free(input);
		LibC.free(state);
		LibC.free(list);
		input = Ptr.nil();
	}
}
