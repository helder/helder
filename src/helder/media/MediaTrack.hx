package helder.media;

import haxe.io.Bytes;

// A track of a file, what a decoder is configured with.
//
// config is what ffmpeg calls the codec's extradata, as the systems'
// decoders take it: the body of avcC, hvcC, av1C or vpcC; AAC's
// AudioSpecificConfig; Opus's OpusHead (MP4's dOps turned into it, as
// Matroska stores it); FLAC's STREAMINFO (MP4) or the CodecPrivate
// ("fLaC" and its blocks, Matroska); ALAC's alac box, its header
// included; Vorbis's three headers, Xiph-laced (Matroska's CodecPrivate).
// null where the codec needs none (VP8, VP9 in WebM, MP3, PCM).
class MediaTrack {
	// its place in Media.tracks
	public final index:Int;
	// the container's own number (MP4's track ID, Matroska's TrackNumber)
	public final id:Int;
	public final kind:MediaKind;
	public final codec:Codec;
	// the container's name for the codec: "avc1", "mp4a", "V_VP9", "A_PCM/INT/LIT"
	public final tag:String;
	public final config:Null<Bytes>;
	// ticks a second of its packets' pts, dts and duration
	public final timescale:Float;
	// seconds; -1 when the file does not say
	public final duration:Float;
	// video: coded pixels, and the degrees clockwise a frame is turned to show (0, 90, 180, 270)
	public final width:Int;
	public final height:Int;
	public final rotation:Int;
	// audio: frames a second, channels, bits a sample (PCM's; 0 elsewhere)
	public final sampleRate:Int;
	public final channels:Int;
	public final bits:Int;
	// seconds of decoded audio to drop at the start (Matroska's CodecDelay:
	// Opus's pre-skip), and to decode before a seek's target (SeekPreRoll)
	public final delay:Float;
	public final preroll:Float;

	@:allow(helder.media)
	function new(t:TrackInfo) {
		index = t.index;
		id = t.id;
		kind = t.kind;
		codec = t.codec;
		tag = t.tag;
		config = t.config;
		timescale = t.timescale;
		duration = t.duration;
		width = t.width;
		height = t.height;
		rotation = t.rotation;
		sampleRate = t.sampleRate;
		channels = t.channels;
		bits = t.bits;
		delay = t.delay;
		preroll = t.preroll;
	}
}
