package helder.media;

// A track's codec, the same name whichever container it came in.
enum abstract Codec(String) to String {
	var H264 = "h264";
	var Hevc = "hevc";
	var Vp8 = "vp8";
	var Vp9 = "vp9";
	var Av1 = "av1";
	var Aac = "aac";
	var Mp3 = "mp3";
	var Opus = "opus";
	var Vorbis = "vorbis";
	var Flac = "flac";
	var Alac = "alac";
	var Pcm = "pcm";
	// another (MediaTrack.tag names it): no decoder will take it
	var Other = "other";
}
