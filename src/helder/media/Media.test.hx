package helder.media;

import haxe.crypto.Crc32;
import haxe.io.Bytes;
import helder.test.Test;

// The files of tests/media (fixtures.sh: ffmpeg's, some Matroska laced or
// made live by lace.mjs) against what ffprobe reads in them
// (expected.json: expect.mjs): each track's codec, sizes, rate, channels,
// rotation, timescale and config bytes; each packet's times, duration,
// size, keyframe flag and the CRC-32 of its bytes, in decode order. Exact
// seeks with B-frames and an edit list. Every file cut short and with
// bytes changed: a MediaError or packets, never another error or a hang.
// Natively and as wasm32-wasi.
function tests() {
	var expected:haxe.DynamicAccess<Dynamic> = haxe.Json.parse(sys.io.File.getContent("tests/media/expected.json"));
	describe("Media", () -> {
		for (name in expected.keys())
			test('$name as ffprobe reads it', async(() -> check(name, expected[name])));
		test("from memory, as from the file", async(() -> {
			var m = Media.open(new MemorySource(sys.io.File.getBytes("tests/media/vp9-opus.webm")));
			equals([for (t in m.tracks) t.codec], [Vp9, Opus]);
			equals(count(m), 61);
		}));
		test("the SPS's colours: HEVC Main 10's BT.2020, H.264's BT.709 full range", async(() -> {
			function said(c:Null<{matrix:String, full:Bool}>)
				return c == null ? "none" : c.matrix + (c.full ? " full" : "");
			var m = Media.open(new MemorySource(sys.io.File.getBytes("tests/media/apple/hevc10.mp4")));
			equals(said(CodecConfig.colours(Lambda.find(m.tracks, t -> t.kind == Video))), "2020");
			m.close();
			var m = Media.open(new MemorySource(sys.io.File.getBytes("tests/media/apple/h264-full.mp4")));
			equals(said(CodecConfig.colours(Lambda.find(m.tracks, t -> t.kind == Video))), "709 full");
			m.close();
		}));
		test("H.264's B-frames (ctts): from the keyframe, 4 dropped to 0.4 s", async(() -> {
			var m = open("h264-aac.mp4");
			var s = m.seek(0.45);
			equals([s[0].packet.pts, s[0].drop, s[0].time], [0.0, 4, 0.4]);
			// (audio: the packet that holds the time)
			equals([s[1].packet.pts, s[1].drop], [3072.0, 0]);
			// (next goes on from the keyframe and the audio's packet)
			var p = m.next();
			equals([p.track.index, p.pts], [0, 0.0]);
		}));
		test("an edit list: times from its media time, the frame before it due at 0", async(() -> {
			var m = open("editlist.mov");
			var s = m.seek(0);
			equals([s[0].packet.pts, s[0].drop, s[0].time], [-4608.0, 4, -0.05]);
			s = m.seek(0.6);
			equals([s[0].packet.pts, s[0].drop, s[0].time], [5632.0, 0, 0.55]);
			s = m.seek(0.75);
			equals([s[0].packet.pts, s[0].drop, s[0].time], [5632.0, 2, 0.75]);
			// (the AAC frame holding 0: priming before it)
			equals(s[1].packet.pts, 5616.0);
			equals(m.seek(0)[1].packet.pts, -528.0);
		}));
		test("fragments: a keyframe each, frames to drop after it", async(() -> {
			var m = open("fragmented.mp4");
			var s = m.seek(1.0);
			equals([s[0].packet.pts, s[0].drop, s[0].time], [10240.0, 0, 1.0]);
			s = m.seek(0.85);
			equals([s[0].packet.pts, s[0].drop, s[0].time], [6144.0, 2, 0.8]);
			// (sidx: the fragments' places, the first moof's first)
			var mp4 = cast(m.demuxer, Mp4);
			equals(mp4.segments[0], {track: 1, time: 0.2, offset: 1370.0, size: 2555.0});
		}));
		test("WebM: from a Cue's cluster, and without Cues (live) the same", async(() -> {
			for (f in ["vp9-opus.webm", "live.webm"]) {
				var m = open(f);
				var s = m.seek(0.75);
				equals([s[0].packet.pts, s[0].drop, s[0].time], [500.0, 2, 0.7]);
				equals([s[1].packet.pts, s[1].drop], [734.0, 0]);
				var p = m.next();
				equals(p.pts, 500.0);
				// (back to the start, and to the end)
				equals(m.seek(0)[0].packet.pts, 0.0);
				equals(m.seek(5)[0].time, 0.9);
			}
		}));
		test("laced frames: each its own time and bytes", async(() -> {
			var m = open("laced.mkv");
			var s = m.seek(0.4);
			equals([s[1].packet.pts, s[1].packet.size], [384.0, 512]);
			equals(s[0].packet.pts, 400.0);
		}));
		test("frame stepping: back one frame from each", async(() -> {
			var m = open("h264-aac.mp4");
			var times = [];
			var t = 0.9;
			while (t >= 0) {
				var s = m.seek(t)[0];
				times.push(Math.round(s.time * 10));
				t = s.time - 1e-9;
			}
			equals(times, [9, 8, 7, 6, 5, 4, 3, 2, 1, 0]);
		}));
		test("not a media file, or cut in its header", async(() -> {
			equals(outcome(Bytes.ofString("neither MP4 nor Matroska")), "error");
			equals(outcome(sys.io.File.getBytes("tests/media/h264-aac.mp4").sub(0, 30)), "error");
		}));
	});
	describe("malformed", () -> {
		var files = [for (f in expected.keys()) f];
		files.sort(Reflect.compare);
		test("every file cut short and with bytes changed: a MediaError or packets", async(() -> {
			var seed = 7, outcomes = new Map<String, Int>(), t0 = haxe.Timer.stamp();
			function random(n:Int):Int {
				seed = (seed * 1103515245 + 12345) & 0x7fffffff;
				return seed % n;
			}
			for (f in files) {
				var whole = sys.io.File.getBytes('tests/media/$f');
				for (k in 1...12) {
					var o = outcome(whole.sub(0, Std.int(whole.length * k / 12)));
					outcomes[o] = (outcomes[o] ?? 0) + 1;
				}
				for (_ in 0...60) {
					var b = whole.sub(0, whole.length);
					for (_ in 0...1 + random(4)) {
						// (mostly in the headers, where the sizes and counts are)
						var at = random(10) < 7 ? random(b.length < 4096 ? b.length : 4096) : random(b.length);
						b.set(at, random(3) == 0 ? 0xff : random(256));
					}
					var o = outcome(b);
					outcomes[o] = (outcomes[o] ?? 0) + 1;
				}
			}
			assert(outcomes["error"] > 0 && outcomes["read"] > 0, '$outcomes');
			assert(haxe.Timer.stamp() - t0 < 30, "fuzz took too long");
		})).timeout(60);
	});
}

@:coroutine private function open(name:String):Media
	return Media.open(new FileSource('tests/media/$name'));

// a file opened, all its packets read and a seek: "read", or "error" for a MediaError
@:coroutine private function outcome(b:Bytes):String {
	var r = attempt(b);
	if (r != "read" && r != "error") fail(r);
	return r;
}

// (a memory source never suspends: an error is thrown, not resumed with,
// so catching it here is safe, helder.async's README, "Not yet")
@:coroutine private function attempt(b:Bytes):String {
	try {
		var m = Media.open(new MemorySource(b));
		var p;
		while ((p = m.next()) != null) m.read(p);
		m.seek(0.5);
		m.seek(0);
		return "read";
	} catch (e:MediaError) {
		return "error";
	}
}

@:coroutine private function count(m:Media):Int {
	var n = 0;
	while (m.next() != null) n++;
	return n;
}

@:coroutine private function check(name:String, e:Dynamic) {
	var m = open(name);
	var streams:Array<Dynamic> = e.streams, packets:Array<Array<Dynamic>> = e.packets;
	equals(m.tracks.length, streams.length);
	for (i in 0...streams.length) {
		var s = streams[i], t = m.tracks[i];
		var codec:String = s.codec;
		equals((t.codec : String), codec.indexOf("pcm_") == 0 ? "pcm" : codec, '$name track $i codec');
		equals(t.kind, s.type, '$name track $i kind');
		equals([t.width, t.height, t.sampleRate, t.channels], [s.width, s.height, s.rate, s.channels], '$name track $i');
		equals(t.rotation, (360 - Std.int(s.rotation)) % 360, '$name track $i rotation');
		equals(t.timescale, Std.parseFloat((s.timeBase : String).split("/")[1]), '$name track $i timescale');
		if (s.extradata != "") equals(t.config?.toHex(), s.extradata, '$name track $i config');
		if (s.duration != null) approx(t.duration, s.duration, 1e-3, '$name track $i duration');
	}
	// (QuickTime's edit list starts the video mid-frame: ffmpeg moves its
	// first whole frame to 0, half a frame later than the edit says)
	var moved = name == "editlist.mov" ? [512.0, 0.0] : [0.0, 0.0];
	var mkv = !StringTools.endsWith(name, ".mp4") && !StringTools.endsWith(name, ".mov");
	var got:Array<Array<Array<Dynamic>>> = [for (_ in streams) []], want:Array<Array<Array<Dynamic>>> = [for (_ in streams) []];
	for (p in packets) {
		var s:Int = p[0];
		want[s].push([p[1] + moved[s], mkv ? p[1] + moved[s] : p[2] + moved[s], p[3], p[4], p[6], p[7]]);
	}
	// (ffmpeg's MP3 parser gives the last frame its whole 1152 samples; stts says 337)
	if (name == "audio.mp4") want[3][want[3].length - 1][2] = 337;
	var p;
	while ((p = m.next()) != null) {
		var b = m.read(p);
		var crc = StringTools.hex(Crc32.make(b), 8).toLowerCase();
		got[p.track.index].push(([p.pts, p.dts, p.duration, p.size, p.key ? 1 : 0, crc] : Array<Dynamic>));
	}
	for (i in 0...streams.length) equals(got[i], want[i], '$name track $i packets');
}
