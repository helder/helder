package helder.media.web;

import helder.media.*;
import helder.test.Test;

// The codec strings WebCodecs is configured with, read from tests/media's
// configs (ffprobe's profiles and levels), and the streams that name no
// colours (read as BT.601: H.264's SPS, VP9's vpcC or keyframe, AV1's
// sequence header)
function tests() {
	describe("WebCodec", () -> {
		test("names", async(() -> {
			equals(names("h264-aac.mp4"), ["avc1.64000a", "mp4a.40.2"]);
			equals(names("hevc.mp4"), ["hvc1.1.6.L30.90"]);
			equals(names("apple/hevc10.mp4"), ["hvc1.2.4.L30.90"]);
			equals(names("vp9.mp4"), ["vp09.01.10.08"]);
			equals(names("vp9-opus.webm"), ["vp09.01.10.08", "opus"]);
			equals(names("av1.mp4"), ["av01.0.00M.08"]);
			equals(names("apple/chirp.mp4"), ["mp4a.40.2", "mp3", "flac", null, "opus"]);
			equals(names("laced.mkv"), ["vorbis", "pcm-s16"]);
		}));
		test("FLAC's STREAMINFO made a stream header", async(() -> {
			var m = open("apple/chirp.mp4"), d = WebCodec.description(m.tracks[2]);
			equals(d.getString(0, 4), "fLaC");
			equals([d.length, d.get(4), d.get(7)], [42, 0x80, 34]);
		}));
		test("colours not named: BT.601 (1 video range, 2 full; 0 named)", async(() -> {
			equals([for (f in ["h264-aac.mp4", "apple/h264-full.mp4", "vp9.mp4", "apple/vp9-yuv.webm", "av1.webm", "av1.mp4", "hevc.mp4"]) untagged(f)], [1, 0, 0, 1, 1, 1, 0]);
		}));
	});
}

@:coroutine private function open(f:String):Media
	return Media.open(new FileSource("tests/media/" + f));

@:coroutine private function names(f:String):Array<Null<String>> {
	var m = open(f), n = [for (t in m.tracks) WebCodec.name(t, first(m, t))];
	m.close();
	return n;
}

@:coroutine private function untagged(f:String):Int {
	var m = open(f), t = m.tracks[0];
	return WebCodec.untagged(t, first(m, t));
}

// (a track's first packet's bytes)
@:coroutine private function first(m:Media, t:MediaTrack):haxe.io.Bytes {
	m.seek(0);
	var p = m.next();
	while (p != null && p.track != t) p = m.next();
	return p == null ? null : m.read(p);
}
