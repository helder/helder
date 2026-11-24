import haxe.DynamicAccess;
import haxe.crypto.Crc32;
import helder.async.Async;
import helder.media.*;
import helder.media.apple.VtDecoder;
import helder.media.ui.VideoTexture;
import sys.io.File;

// helder.media's decoding on Apple's systems (the system-images lane on
// macOS): every frame of tests/media's videos and this folder's
// (fixtures.sh) through VideoToolbox, their count, times and planes'
// CRC-32 against ffmpeg's decoding (decoded.json: expect.mjs); every
// audio track through AudioToolbox and helder's Vorbis, its frames and
// samples against ffmpeg's (libopus's for Opus), trimmed as the player
// trims them; exact seeks and frame steps landing on the frame by its
// time and pixels; a clip played through CoreAudio's "file:" output, each
// frame shown within a frame of the clock, the audio's frames in the
// file. AV1 and VP9 where the system decodes them (VP9: the hardware's,
// from 128 pixels; AV1: Apple's M3 and later), skipped elsewhere.
//
//   MediaAppleTest out-dir
@:hxmc.unsafe(gc)
class MediaAppleTest {
	static var failed = 0;
	static var out = "bin/media";

	static function check(what:String, ok:Bool, detail = "") {
		Sys.println('MediaAppleTest: ${ok ? "ok" : "FAIL"}: $what${detail == "" ? "" : " (" + detail + ")"}');
		if (!ok) failed++;
	}

	static function main() {
		if (Sys.args().length > 0) out = Sys.args()[0];
		var expected:Dynamic = haxe.Json.parse(File.getContent("tests/media/apple/decoded.json"));
		var t0 = haxe.Timer.stamp();
		Async.run(_ -> {
			var videos:DynamicAccess<Dynamic> = expected.video;
			for (f => e in videos) video(f, e);
			var audios:DynamicAccess<Dynamic> = expected.audio;
			for (k => e in audios) audio(k, e);
			refused();
			var rgbs:DynamicAccess<Dynamic> = expected.rgb;
			colours(rgbs);
			seeks(videos);
			played();
		});
		Sys.println('MediaAppleTest: ${Math.round((haxe.Timer.stamp() - t0) * 10) / 10} s');
		Sys.exit(failed > 0 ? 1 : 0);
	}

	@:coroutine static function open(f:String):Media
		return Media.open(new FileSource("tests/media/" + f));

	static function crc(f:VideoFrame):Int
		return Crc32.make(f.pixels());

	// (whether the system decodes it: VP9 and AV1 are the hardware's)
	static function decodes(t:MediaTrack):Bool
		return t.codec == H264 || t.codec == Hevc || VtDecoder.hardware(t.codec);

	@:coroutine static function video(f:String, e:Dynamic) {
		var m = open(f), t = Lambda.find(m.tracks, t -> t.kind == Video);
		if (!decodes(t)) {
			Sys.println('MediaAppleTest: skipped: $f (no ${t.codec} decoder here)');
			return;
		}
		var d = new VtDecoder(t), frames = [], pts = [];
		var p;
		while ((p = m.next()) != null)
			if (p.track == t) {
				d.decode(p, m.read(p), true);
				pts.push(p.time);
			}
		d.flush();
		d.take(frames);
		frames.sort((a, b) -> a.time < b.time ? -1 : 1);
		pts.sort((a, b) -> a < b ? -1 : 1);
		var crcs:Array<Int> = e.crcs, bad = [];
		for (i in 0...frames.length)
			if (i >= crcs.length || crc(frames[i]) != crcs[i] || frames[i].time != pts[i]) bad.push(i);
		var first = frames[0];
		check('$f: ${frames.length} frames, each packet\'s time, planes as ffmpeg decodes them',
			frames.length == crcs.length && bad.length == 0 && first.width == e.width && first.height == e.height && first.bits == e.bits,
			'${frames.length} of ${crcs.length}, ${first.width}x${first.height} ${first.bits} bits ${first.matrix}${first.full ? " full" : ""}${bad.length > 0 ? ", differing: " + bad : ""}');
		if (f == "apple/hevc10.mp4") check("hevc10.mp4: P010, BT.2020", first.bits == 10 && first.matrix == "2020" && !first.full);
		if (f == "apple/h264-full.mp4") check("h264-full.mp4: full range, BT.709", first.full && first.matrix == "709");
		for (fr in frames) fr.release();
		d.close();
		m.close();
	}

	@:coroutine static function audio(key:String, e:Dynamic) {
		var f = key.split(":")[0], n = Std.parseInt(key.split(":")[1]);
		var m = open(f), t = [for (t in m.tracks) if (t.kind == Audio) t][n];
		var d = Decoders.audio(t), buf = new AudioBuffer(), left = [];
		var p;
		while ((p = m.next()) != null)
			if (p.track == t) {
				var k = d.decode(p, m.read(p), buf);
				var keep = @:privateAccess Player.keep(p, k, d.rate, 0, @:privateAccess Player.end(t));
				for (i in keep.first...keep.first + keep.count) left.push(buf.get(i * 2));
			}
		var samples:Array<Float> = e.samples, worst = 0.0;
		var tolerance = switch t.codec {
			case Flac | Alac: 1e-6;
			case Aac: 2e-3;
			case _: 1e-3;
		}
		for (i in 0...samples.length)
			if (i * 97 < left.length) worst = Math.max(worst, Math.abs(left[i * 97] - samples[i]));
		// (Opus: libopus's from an Ogg copy ends where its last page says, ours at the track's duration)
		var frames:Int = e.frames, slack = t.codec == Opus ? 960 : 0;
		check('$key ${t.codec}: ${left.length} frames at ${d.rate}, its samples as ffmpeg\'s', d.rate == e.rate && Math.abs(left.length - frames) <= slack
			&& worst <= tolerance, 'ffmpeg ${frames}, the largest difference $worst');
		d.close();
		buf.free();
		m.close();
	}

	// frames turned to RGB on the GPU (Metal, headless: VideoTexture's pass
	// from the IOSurfaces' planes) against ffmpeg's, upright, where the
	// picture is flat (chroma's upsampling and siting differ at edges)
	@:coroutine static function colours(rgbs:DynamicAccess<Dynamic>) {
		var device = helder.gfx.Device.create(helder.os.Surface.headless(64, 64));
		var vt = new VideoTexture(device);
		for (f => e in rgbs) {
			var m = open(f), t = Lambda.find(m.tracks, t -> t.kind == Video);
			var d = new VtDecoder(t), frames = [];
			var p;
			while ((p = m.next()) != null) if (p.track == t) d.decode(p, m.read(p), true);
			d.flush();
			d.take(frames);
			frames.sort((a, b) -> a.time < b.time ? -1 : 1);
			var frame = frames[(e.frame : Int)];
			var ok = vt.prepare(frame, t.rotation);
			// (a frame into the texture, read back)
			device.frameInto(vt.target);
			var w = vt.width, h = vt.height, px = haxe.io.Bytes.alloc(w * h * 4);
			var enc = device.beginFrame();
			if (enc != null) {
				vt.record(enc);
				device.readPixels(px);
				device.endFrame();
			}
			device.frameInto(null);
			var pixels:Array<Int> = e.pixels, sum = 0.0, worst = 0, k = 0;
			while (k < pixels.length) {
				var x = pixels[k], y = pixels[k + 1];
				for (c in 0...3) {
					// (Metal's readPixels swaps a BGRA frame's red and blue: this one is RGBA)
					var dv = Std.int(Math.abs(px.get((y * w + x) * 4 + 2 - c) - pixels[k + 2 + c]));
					sum += dv;
					if (dv > worst) worst = dv;
				}
				k += 5;
			}
			var mean = sum / (pixels.length / 5 * 3);
			if (Sys.getEnv("DUMP") != null) {
				var ppm = new haxe.io.BytesOutput();
				ppm.writeString('P6 $w $h 255\n');
				for (i in 0...w * h) for (c in 0...3) ppm.writeByte(px.get(i * 4 + 2 - c));
				File.saveBytes('$out/' + StringTools.replace(f, "/", "-") + ".ppm", ppm.getBytes());
			}
			check('$f: frame ${e.frame} in RGB, ${w}x$h upright, as ffmpeg turns it where flat (${Std.int(pixels.length / 5)} pixels)', ok && w == e.width && h == e.height && mean < 1 && worst <= 3,
				'the mean difference ${Math.round(mean * 100) / 100} levels, the largest $worst');
			for (fr in frames) fr.release();
			d.close();
			m.close();
		}
		vt.dispose();
		device.dispose();
	}

	// tests/media's VP9 is 4:4:4 (profile 1), which Apple's decoder does not take: an error of helder.media's
	@:coroutine static function refused() {
		var m = open("vp9.mp4"), t = m.tracks[0];
		var e = try {
			var d = new VtDecoder(t), p = m.next();
			d.decode(p, m.read(p), true);
			d.wait();
			d.close();
			"decoded";
		} catch (e:MediaError) "MediaError";
		check("VP9 4:4:4: a MediaError, or decoded", e == "MediaError" || e == "decoded", e);
		m.close();
	}

	// (the player's frame shown once the update finds it, or null after a second)
	@:coroutine static function shown(p:Player, time:Float):Null<VideoFrame> {
		var t0 = haxe.Timer.stamp();
		while (haxe.Timer.stamp() - t0 < 2) {
			var f = p.update();
			if (f != null && Math.abs(f.time - time) < 1e-6) return f;
			Async.delay(0.002);
		}
		return p.shown;
	}

	@:coroutine static function seeks(videos:DynamicAccess<Dynamic>) {
		var p = Player.open(new FileSource("tests/media/h264-aac.mp4"), {silent: true});
		var t0 = haxe.Timer.stamp();
		while (!p.loaded && p.error == null && haxe.Timer.stamp() - t0 < 2) Async.delay(0.002);
		check("the player loaded", p.loaded && p.duration == 1, '${p.error} ${p.duration}');
		var crcs:Array<Int> = videos["h264-aac.mp4"].crcs;
		function at(what:String, f:Null<VideoFrame>, time:Float, i:Int)
			check('h264-aac.mp4: $what: the frame at $time', f != null && f.time == time && crc(f) == crcs[i], f == null ? "none" : '${f.time}');
		at("opened", shown(p, 0), 0, 0);
		p.seek(0.45);
		at("seek(0.45), exact (B-frames, 4 dropped)", shown(p, 0.4), 0.4, 4);
		p.step(1);
		at("step(1)", shown(p, 0.5), 0.5, 5);
		p.step(1);
		at("step(1) again", shown(p, 0.6), 0.6, 6);
		p.step(-1);
		at("step(-1)", shown(p, 0.5), 0.5, 5);
		p.seek(0.99);
		at("seek(0.99): the last", shown(p, 0.9), 0.9, 9);
		p.step(1);
		at("step(1) at the end: stays", shown(p, 0.9), 0.9, 9);
		p.seek(0.75, false);
		at("seek(0.75) to its keyframe", shown(p, 0), 0, 0);
		check("time after it: the keyframe's", p.time == 0, '${p.time}');
		p.close();
		// (an edit list: the frame due at 0 is before the edit, decoded from the keyframe 0.45 s before)
		var p = Player.open(new FileSource("tests/media/editlist.mov"), {silent: true});
		var f = shown(p, -0.05), crcs:Array<Int> = videos["editlist.mov"].crcs;
		check("editlist.mov: at 0 the frame at -0.05 (the edit's)", f != null && f.time == -0.05 && crc(f) == crcs[4], f == null ? "none" : '${f.time}');
		p.seek(0.6);
		f = shown(p, 0.55);
		check("editlist.mov: seek(0.6): 0.55", f != null && f.time == 0.55 && crc(f) == crcs[10], f == null ? "none" : '${f.time}');
		p.close();
	}

	// a clip played through CoreAudio's file output (its clock's pace): each
	// frame shown once, in order, within a frame of the clock (the audio
	// heard); the audio's frames in the file
	@:coroutine static function played() {
		var raw = '$out/played.raw';
		var p = Player.open(new FileSource("tests/media/h264-aac.mp4"), {device: 'file:$raw'});
		var ended = false, shows = [], late = 0.0, t0 = haxe.Timer.stamp();
		p.onEnded = () -> ended = true;
		while (!p.loaded && haxe.Timer.stamp() - t0 < 2) Async.delay(0.002);
		p.play();
		var last:Null<VideoFrame> = null;
		while (!ended && haxe.Timer.stamp() - t0 < 4) {
			var f = p.update();
			if (f != null && f != last) {
				last = f;
				shows.push(f.time);
				var off = p.time - f.time;
				if (off < -1e-6 || off > late) late = Math.max(late, off < 0 ? -off + 1 : off);
			}
			Async.delay(0.002);
		}
		var position = p.time;
		p.close();
		check("played: each frame once, in order", shows.join(",") == [for (i in 0...10) i / 10].join(","), shows.join(","));
		check("played: each shown within a frame of the clock", late < 0.1 + 0.01, 'at most ${Math.round(late * 1000)} ms after its time');
		check("played: ended, the clock at the end", ended && Math.abs(position - 1) < 0.1, '$position');
		// (the frames the decoder gave, between the silence before and after)
		var b = File.getBytes(raw), n = b.length >> 3, first = -1, lastHeard = -1;
		for (i in 0...n)
			if (Math.abs(b.getFloat(i * 8)) > 1e-4) {
				if (first < 0) first = i;
				lastHeard = i;
			}
		var heard = lastHeard - first + 1;
		check("played: the audio's 8000 frames in the output", Math.abs(heard - 8000) <= 64, '$heard: from $first to $lastHeard of $n');
		if (failed == 0) sys.FileSystem.deleteFile(raw);
	}
}
