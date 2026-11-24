package helder.media;

import haxe.io.Bytes;
import helder.os.audio.Vorbis;

// Vorbis by helder's own decoder (helder.os.audio.Vorbis: its headers
// from the track's config), on every system
@:hxmc.unsafe(gc)
class VorbisDecoder implements AudioDecoder {
	public final rate:Int;
	public var decoded(default, null):Null<Packet>;

	var vorbis:Vorbis;
	final config:Bytes;

	public function new(track:MediaTrack) {
		if (track.config == null) throw new MediaError("Vorbis without its headers");
		config = track.config;
		vorbis = open(config);
		rate = vorbis.rate;
	}

	static function open(config:Bytes):Vorbis
		return try Vorbis.headers(config) catch (e:String) throw new MediaError(e);

	public function decode(p:Null<Packet>, bytes:Null<Bytes>, samples:AudioBuffer):Int {
		decoded = p;
		if (p == null || bytes == null) return 0;
		var v = vorbis, n = v.feed(bytes);
		samples.room(n);
		var l = v.out[0], r = v.out[v.channels > 1 ? 1 : 0];
		for (i in 0...n) {
			samples.set(i * 2, l[i]);
			samples.set(i * 2 + 1, r[i]);
		}
		return n;
	}

	// (a seek: the overlap of the packets before forgotten)
	public function reset()
		vorbis = open(config);

	public function close() {}
}
