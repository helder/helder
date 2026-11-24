package helder.media.web;

#if (hxmc.target == "wasm32-wasi")
import haxe.io.Bytes;

// A track decoded by the browser's WebCodecs AudioDecoder (imports.mjs):
// packets in as EncodedAudioChunks, timed in microseconds; each AudioData
// that comes is copied into samples as interleaved stereo floats at a later
// decode, its packet the next given (`decoded`): in order, one for one, as
// the browsers decode (by its own time it is not: Chromium times them anew
// from 0, a priming packet's at -1024 frames given 0's)
@:hxmc.unsafe(gc)
class WebAudioDecoder implements AudioDecoder {
	public final rate:Int;
	public var decoded(default, null):Null<Packet>;

	final track:MediaTrack;
	final h:Int;
	final sent:Array<Packet> = [];

	public function new(track:MediaTrack) {
		this.track = track;
		var name = WebCodec.name(track);
		if (name == null) throw new MediaError('no decoder for ${track.codec}');
		var d = WebCodec.description(track) ?? Bytes.alloc(0);
		// (Opus decodes at 48 kHz, whatever rate the file names: its input's)
		rate = track.codec == Opus ? 48000 : track.sampleRate;
		var r = rate, c = track.channels;
		h = Glue.decoder(1, name, r, c, 0, 0, hxmc.Span.ofBytes(d));
		if (Glue.failed(h) == 1) throw new MediaError('the browser does not decode $name');
	}

	public function decode(p:Null<Packet>, bytes:Null<Bytes>, samples:AudioBuffer):Int {
		decoded = null;
		if (p != null && bytes != null) {
			sent.push(p);
			var t = us(p.time), d = us(p.duration / p.track.timescale);
			Glue.decode(h, 1, t, d, 1, hxmc.Span.ofBytes(bytes));
		}
		if (Glue.failed(h) == 1) throw new MediaError('the browser could not decode this ${track.codec}');
		var n = Glue.audio_frames(h);
		if (n < 0) return 0;
		decoded = sent.shift();
		samples.room(n);
		Glue.audio_take(h, samples.data);
		return n;
	}

	static function us(t:Float):Float
		return Math.ffloor(t * 1e6 + 0.5);

	public function reset() {
		sent.resize(0);
		Glue.reset(h);
	}

	public function close()
		Glue.close(h);
}
#end
