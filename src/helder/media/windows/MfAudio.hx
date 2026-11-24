package helder.media.windows;

#if ((!helder.os || helder.os == "windows") && hxmc.target != "wasm32-wasi")
import haxe.io.Bytes;
import helder.media.windows.Mf;
import helder.os.win32.Com;
import hxmc.unsafe.*;

// helder.media's AudioDecoder on Windows: Media Foundation's decoder of the
// codec (MfTransform: AAC, MP3, FLAC and ALAC, Opus where the system has
// one), into floats where it gives them, else 16 bits, the first two
// channels interleaved (mono doubled). Its config is MF_MT_USER_DATA:
// AAC's HEAACWAVEINFO's tail and AudioSpecificConfig, ALAC's cookie,
// FLAC's STREAMINFO, OpusHead (forms tried in turn where the system's
// decoders differ). An output comes after its packet: one a call, its
// packet found by its time (decoded), what came since asked for with no
// packet; the end drained.
@:hxmc.unsafe(gc)
class MfAudio implements AudioDecoder {
	static inline var BASE = 1000.0;

	public final rate:Int;
	public var decoded(default, null):Null<Packet>;
	public var pending(get, never):Int;
	// (tests) the last output's time as the decoder stamped it, seconds (NaN: none)
	public var stamped(default, null) = Math.NaN;

	final track:MediaTrack;
	final mft:MfTransform;
	final given:Array<Packet> = [];
	var channels = 2;
	var floats = true;
	// (the first output since a start or a seek: its excess over its packet dropped)
	var lead = true;

	public static function supports(c:Codec):Bool
		return switch c {
			case Aac | Mp3 | Flac | Alac | Opus: Mf.loaded();
			case _: false;
		}

	static function tag(c:Codec):Int
		return switch c {
			case Aac: 0x1610;
			case Mp3: 0x55;
			case Flac: 0xF1AC;
			case Alac: 0x6C61;
			case _: 0x704F;
		}

	public function new(track:MediaTrack) {
		this.track = track;
		if (!supports(track.codec)) throw new MediaError('no decoder for ${track.codec}');
		rate = track.codec == Opus ? 48000 : track.sampleRate;
		var sub = Mf.subtype(tag(track.codec)), ch = track.channels > 0 ? track.channels : 2;
		var made:Null<MfTransform> = null, tried = "";
		for (data in forms(track)) {
			made = MfTransform.open(MfId.AUDIO_DECODER, MfId.AUDIO, sub, t -> {
				var input = MfTransform.type(i -> {
					MfTransform.guid(i, MfId.MAJOR_TYPE, MfId.AUDIO);
					MfTransform.guid(i, MfId.SUBTYPE, sub);
					MfTransform.int(i, MfId.RATE, rate);
					MfTransform.int(i, MfId.CHANNELS, ch);
					if (track.codec == Aac) {
						MfTransform.int(i, MfId.AAC_PAYLOAD, 0);
						MfTransform.int(i, MfId.BITS, 16);
					}
					if (data != null) MfTransform.blob(i, MfId.USER_DATA, data);
				});
				var hr = IMFTransform.SetInputType(t, 0, input, 0);
				Com.release(input);
				if (hr < 0) MfTransform.note('SetInputType ${MfTransform.hex(hr)} (config ${data == null ? "none" : data.length + " bytes"})');
				hr >= 0 && output(t);
			});
			if (made != null) break;
			tried += (tried == "" ? "" : " | ") + MfTransform.found;
		}
		LibC.free(sub);
		if (made == null) throw new MediaError('the system does not decode this ${track.codec} ($tried)');
		mft = made;
		mft.changed = t -> {
			var ok = output(t);
			if (ok) formats();
			ok;
		};
		formats();
	}

	// (the configs tried, in turn)
	static function forms(t:MediaTrack):Array<Null<Bytes>> {
		var c = t.config;
		if (c == null) return [null];
		return switch t.codec {
			case Aac:
				var b = Bytes.alloc(12 + c.length);
				b.fill(0, 12, 0);
				b.set(2, 0xFE);
				b.blit(12, c, 0, c.length);
				[b];
			case Alac if (c.length >= 36): [c.sub(12, c.length - 12), c];
			case Flac:
				var info = c.length >= 42 && c.get(0) == 0x66 ? c.sub(8, 34) : c.length >= 38 ? c.sub(4, 34) : c;
				var whole = Bytes.alloc(42);
				whole.blit(0, Bytes.ofString("fLaC"), 0, 4);
				whole.set(4, 0x80);
				whole.set(7, 34);
				whole.blit(8, info, 0, Std.int(Math.min(34, info.length)));
				[info, whole, null];
			case Mp3: [null];
			// (OpusHead, its pre-skip 0: the player trims the priming by the
			// packets' times, as elsewhere, not the decoder too)
			case Opus if (c.length >= 12):
				var h = c.sub(0, c.length);
				h.set(10, 0);
				h.set(11, 0);
				[h, c, null];
			case _: [c, null];
		}
	}

	// (floats where it gives them, else 16 bits)
	static function output(t:Ptr):Bool
		return MfTransform.choose(t, o -> MfTransform.subtypeOf(o) == 3)
			|| MfTransform.choose(t, o -> MfTransform.subtypeOf(o) == 1 && MfTransform.read(o, MfId.BITS) == 16);

	// (what it gives: its channels, floats or 16 bits)
	function formats() {
		var t = mft.current();
		if (t.isNull()) return;
		var n = MfTransform.read(t, MfId.CHANNELS);
		if (n > 0) channels = n;
		floats = MfTransform.subtypeOf(t) == 3;
		Com.release(t);
	}

	function get_pending():Int
		return given.length;

	public function decode(p:Null<Packet>, bytes:Null<Bytes>, samples:AudioBuffer):Int {
		if (p != null && bytes != null) {
			given.push(p);
			var d = p.duration > 0 ? p.duration / track.timescale * 1e7 : 0;
			mft.push(bytes, key(p.time), d);
		}
		return out(samples);
	}

	static function key(t:Float):Float
		return Math.round((t + BASE) * 1e7);

	// (the next output into samples: its packet decoded, its frames)
	function out(samples:AudioBuffer):Int {
		decoded = null;
		var s = mft.next();
		if (s.isNull()) return 0;
		var k = Arena.scopedValue(a -> {
			var t:Ptr<Int32> = a.alloc(8);
			if (IMFSample.GetSampleTime(s, t.raw()) < 0) return -1.0;
			t[1] * 4294967296.0 + (t[0] < 0 ? t[0] + 4294967296.0 : t[0]);
		});
		var n = copy(s, samples);
		Com.release(s);
		stamped = k < 0 ? Math.NaN : k / 1e7 - BASE;
		if (given.length == 0) return n;
		var at = 0;
		for (i in 0...given.length) if (Math.abs(key(given[i].time) - k) < 1) {
			at = i;
			break;
		}
		decoded = given[at];
		given.splice(0, at + 1);
		// (a first output longer than its packet starts with the decoder's own
		// lead: Media Foundation's MP3 decoder gives 624 frames for the first
		// 576, 48 of its own before them; the packet's frames are its last)
		var d = Math.round(decoded.duration / track.timescale * rate);
		if (lead && d > 0 && n > d) {
			for (i in 0...d * 2) samples.set(i, samples.get(i + (n - d) * 2));
			n = d;
		}
		lead = false;
		return n;
	}

	// (a sample's PCM into samples as two channels of floats: its frames)
	function copy(s:Ptr, samples:AudioBuffer):Int
		return Arena.scopedValue(a -> {
			var b:Ptr<Ptr> = a.alloc(8), data:Ptr<Ptr> = a.alloc(8), len:Ptr<Int32> = a.alloc(4);
			if (IMFSample.ConvertToContiguousBuffer(s, b) < 0) return 0;
			if (IMFMediaBuffer.Lock(b.value, data, Ptr.nil(), len) < 0) {
				Com.release(b.value);
				return 0;
			}
			var at = data.value, w = floats ? 4 : 2, ch = channels, n = Std.int(len.value / (w * ch));
			samples.room(n);
			var r = ch > 1 ? 1 : 0;
			for (i in 0...n) {
				var o = i * ch * w;
				samples.set(i * 2, floats ? Mem.getF32(at, o) : Mem.getI16(at, o) / 32768);
				samples.set(i * 2 + 1, floats ? Mem.getF32(at, o + r * w) : Mem.getI16(at, o + r * 2) / 32768);
			}
			IMFMediaBuffer.Unlock(b.value);
			Com.release(b.value);
			n;
		});

	// the stream's end: its last outputs (by decode, as they come)
	public function flush(samples:AudioBuffer):Int {
		mft.drain();
		return 0;
	}

	public function reset() {
		lead = true;
		mft.flush();
		given.resize(0);
		decoded = null;
	}

	public function close()
		mft.close();
}
#end
