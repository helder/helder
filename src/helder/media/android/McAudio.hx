package helder.media.android;

import haxe.io.Bytes;
import helder.media.android.MediaNdk;
import hxmc.unsafe.*;

// helder.media's AudioDecoder on Android: an AMediaCodec (McCodec) of the
// track into PCM buffers (floats asked for, 16 bits where the codec gives
// those), its first two channels interleaved (mono doubled). csd-0 is
// AAC's AudioSpecificConfig, OpusHead (csd-1 and csd-2 its pre-skip and
// preroll in nanoseconds) or FLAC's "fLaC" and STREAMINFO. The codec's
// outputs come later than their packets: one an output, the packet found
// by its time (decoded), what came since asked for with no packet.
@:hxmc.unsafe(gc)
class McAudio implements AudioDecoder {
	static inline var BASE = 1e9;

	public final rate:Int;
	public var decoded(default, null):Null<Packet>;
	public var pending(get, never):Int;

	final codec:McCodec;
	// (given, no output yet: in order)
	final given:Array<Packet> = [];
	var channels:Int;
	var floats = false;

	public static function supports(c:Codec):Bool
		return switch c {
			case Aac | Mp3 | Opus | Flac: MediaNdk.loaded();
			case _: false;
		}

	public function new(track:MediaTrack) {
		if (!supports(track.codec)) throw new MediaError('no decoder for ${track.codec}');
		rate = track.codec == Opus ? 48000 : track.sampleRate;
		channels = track.channels > 0 ? track.channels : 2;
		var c = track.config;
		codec = McCodec.open(track, f -> {
			McCodec.int(f, "sample-rate", rate);
			McCodec.int(f, "channel-count", channels);
			// (ENCODING_PCM_FLOAT)
			McCodec.int(f, "pcm-encoding", 4);
			switch track.codec {
				case Aac if (c != null):
					McCodec.buffer(f, "csd-0", c);
				case Opus if (c != null && c.length >= 12):
					McCodec.buffer(f, "csd-0", c);
					McCodec.buffer(f, "csd-1", ns((c.get(10) | c.get(11) << 8) * 1e9 / 48000));
					McCodec.buffer(f, "csd-2", ns(Math.max(track.preroll, 0.08) * 1e9));
				case Flac if (c != null):
					McCodec.buffer(f, "csd-0", flac(c));
				case _:
			}
		}, Ptr.nil(), 0);
	}

	// (a 64-bit little-endian count)
	static function ns(v:Float):Bytes {
		var b = Bytes.alloc(8);
		b.setInt64(0, haxe.Int64.fromFloat(Math.round(v)));
		return b;
	}

	// (MP4's STREAMINFO made a stream's header; Matroska's is one)
	static function flac(c:Bytes):Bytes {
		if (c.length >= 4 && c.getString(0, 4) == "fLaC") return c;
		var b = Bytes.alloc(8 + c.length);
		b.blit(0, Bytes.ofString("fLaC"), 0, 4);
		b.set(4, 0x80);
		b.set(5, c.length >> 16 & 0xFF);
		b.set(6, c.length >> 8 & 0xFF);
		b.set(7, c.length & 0xFF);
		b.blit(8, c, 0, c.length);
		return b;
	}

	function get_pending():Int
		return given.length;

	public function decode(p:Null<Packet>, bytes:Null<Bytes>, samples:AudioBuffer):Int {
		if (p != null && bytes != null) {
			given.push(p);
			codec.push(bytes, key(p), p.key);
		}
		// (a few packets in flight at most: software decoders take a
		// millisecond, so waiting for one keeps the player from reading on)
		return out(samples, given.length > 3 ? 20000 : 0);
	}

	static function key(p:Packet):Float
		return BASE + Math.round(p.time * 1e6);

	// (the next output into samples: its packet decoded, its frames)
	function out(samples:AudioBuffer, wait:Int):Int {
		decoded = null;
		codec.feed();
		while (true) {
			var idx = codec.next(wait);
			if (idx == MediaNdk.FORMAT_CHANGED) {
				var n = codec.output("channel-count");
				if (n > 0) channels = n;
				// (no key: 16 bits, the codec's default)
				floats = codec.output("pcm-encoding") == 4;
				continue;
			}
			if (idx < 0) return 0;
			var size = codec.size, ending = codec.ending, k = codec.time;
			var n = size <= 0 ? 0 : copy(idx, size, samples);
			MediaNdk.AMediaCodec_releaseOutputBuffer(codec.codec, idx, false);
			if (ending) {
				// (the end's buffer: the last packet's frames, where it has any)
				decoded = n > 0 && given.length > 0 ? given[0] : null;
				given.resize(0);
				return n;
			}
			if (given.length == 0) continue;
			// (its packet: the one of its time, else the next in order)
			var at = 0;
			for (i in 0...given.length) if (Math.abs(key(given[i]) - k) < 0.5) {
				at = i;
				break;
			}
			decoded = given[at];
			given.splice(0, at + 1);
			return n;
		}
	}

	// (an output's PCM into samples as two channels of floats: its frames)
	function copy(idx:Int, size:Int, samples:AudioBuffer):Int {
		var off = Mem.getI32(codec.info, 0);
		var base = Arena.scopedValue(a -> {
			var s:Ptr<Int64> = a.alloc(8);
			MediaNdk.AMediaCodec_getOutputBuffer(codec.codec, idx, s);
		});
		if (base.isNull()) return 0;
		var at = base.add(off), w = floats ? 4 : 2, ch = channels, n = Std.int(size / (w * ch));
		samples.room(n);
		var r = ch > 1 ? 1 : 0;
		for (i in 0...n) {
			var o = i * ch * w;
			samples.set(i * 2, floats ? Mem.getF32(at, o) : Mem.getI16(at, o) / 32768);
			samples.set(i * 2 + 1, floats ? Mem.getF32(at, o + r * w) : Mem.getI16(at, o + r * 2) / 32768);
		}
		return n;
	}

	// the stream's end: its last outputs (by decode, as they come) once the codec has the end
	public function flush(samples:AudioBuffer):Int {
		codec.push(null, 0, false);
		decoded = null;
		return 0;
	}

	public function reset() {
		codec.flush();
		given.resize(0);
		decoded = null;
	}

	public function close()
		codec.close();
}
