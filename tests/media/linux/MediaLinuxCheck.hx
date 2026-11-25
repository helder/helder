import haxe.DynamicAccess;
import haxe.crypto.Crc32;
import helder.asset.Asset;
import helder.async.Async;
import helder.media.*;
import helder.media.linux.Av;
import helder.media.linux.AvVideo;
import helder.media.ui.VideoTexture;
import sys.io.File;

// helder.media's decoding on Linux (the system-images lane on a Linux host,
// CI's gfx job: libavcodec installed, no VAAPI driver): the videos of
// tests/media/apple/decoded.json through libavcodec in software, their
// count, times and planes' CRC-32 against ffmpeg's; the audio tracks,
// their frames (Opus's and Vorbis's totals exact) and samples; frames
// turned to RGB by helder's pass on GL (Mesa's llvmpipe) against ffmpeg's
// where flat; exact seeks and steps by time and pixels; a clip played
// through ALSA's file output at the clock's pace, each frame within a frame
// of it, its audio's frames in the file. Then VAAPI's: where a driver
// decodes (a device of libavutil's), the videos again on it, copied out
// and as DMA-BUFs drawn; without one, skipped with a line. What
// libavcodec has no decoder for is skipped with a line; H.264 and AAC never.
//   MediaLinuxCheck [dir]
@:hxmc.unsafe(gc)
class MediaLinuxCheck {
	static var failed = 0;
	static var out = "bin/media";

	static final files:Map<String, haxe.io.Bytes> = [
		"h264-aac.mp4" => Asset.embed("tests/media/h264-aac.mp4"),
		"hevc.mp4" => Asset.embed("tests/media/hevc.mp4"),
		"editlist.mov" => Asset.embed("tests/media/editlist.mov"),
		"rotated.mp4" => Asset.embed("tests/media/rotated.mp4"),
		"fragmented.mp4" => Asset.embed("tests/media/fragmented.mp4"),
		"av1.webm" => Asset.embed("tests/media/av1.webm"),
		"av1.mp4" => Asset.embed("tests/media/av1.mp4"),
		"apple/vp9-yuv.webm" => Asset.embed("tests/media/apple/vp9-yuv.webm"),
		"apple/hevc10.mp4" => Asset.embed("tests/media/apple/hevc10.mp4"),
		"apple/h264-full.mp4" => Asset.embed("tests/media/apple/h264-full.mp4"),
		"apple/quads.mp4" => Asset.embed("tests/media/apple/quads.mp4"),
		"apple/chirp.mp4" => Asset.embed("tests/media/apple/chirp.mp4"),
		"apple/chirp.mkv" => Asset.embed("tests/media/apple/chirp.mkv")
	];

	static function check(what:String, ok:Bool, detail = "") {
		Sys.println('MediaLinuxCheck: ${ok ? "ok" : "FAIL"}: $what${detail == "" ? "" : " (" + detail + ")"}');
		if (!ok) failed++;
	}

	static function say(s:String)
		Sys.println('MediaLinuxCheck: $s');

	static function main() {
		if (Sys.args().length > 0) out = Sys.args()[0];
		sys.FileSystem.createDirectory(out);
		var expected:Dynamic = haxe.Json.parse(Asset.embed("tests/media/apple/decoded.json").toString());
		var t0 = haxe.Timer.stamp();
		if (!Av.loaded()) {
			check("libavcodec loaded", false, Av.missing());
			Sys.exit(1);
		}
		say('libavcodec ${Av.major}');
		var device = helder.gfx.Device.create(helder.os.Surface.headless(64, 64));
		Async.run(_ -> {
			try {
				var videos:DynamicAccess<Dynamic> = expected.video, rgbs:DynamicAccess<Dynamic> = expected.rgb;
				say("videos");
				AvVideo.software = true;
				for (f => e in videos) video(f, e);
				say("audio");
				var audios:DynamicAccess<Dynamic> = expected.audio;
				for (k => e in audios) audio(k, e);
				say("colours");
				colours(rgbs, device);
				say("seeks");
				seeks(videos);
				say("played");
				played();
				AvVideo.software = false;
				say("VAAPI");
				if (AvVideo.device().isNull()) say('VAAPI: skipped (${AvVideo.vaWhy})') else {
					for (f => e in videos) video(f, e, true);
					colours(rgbs, device, true);
				}
			} catch (e:Dynamic) {
				check('no error', false, Std.string(e) + haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
			}
		});
		device.dispose();
		say('${Math.round((haxe.Timer.stamp() - t0) * 10) / 10} s');
		say(failed == 0 ? "passed" : '$failed failed');
		Sys.exit(failed == 0 ? 0 : 1);
	}

	static function source(f:String):ByteSource
		return new MemorySource(files[f]);

	@:coroutine static function open(f:String):Media
		return Media.open(source(f));

	static function crc(f:VideoFrame):Int
		return Crc32.make(f.pixels());

	static final decoders:Array<AvVideo> = [];

	static function close() {
		for (d in decoders) d.close();
		decoders.resize(0);
	}

	// (the decoder's frames of f's video, every packet given; null: none
	// here, said; H.264 never skipped; gpu: VAAPI's, said where it was not)
	@:coroutine static function decodeAll(f:String, gpu = false):Null<Array<VideoFrame>> {
		var m = open(f), t = Lambda.find(m.tracks, t -> t.kind == Video);
		var why:Null<String> = null, d:Null<AvVideo> = null, frames = [], p;
		try {
			d = new AvVideo(t);
			while ((p = m.next()) != null) if (p.track == t) d.decode(p, m.read(p), true);
			d.flush();
			d.take(frames);
			if (frames.length == 0) why = "no frames";
			if (gpu && why == null && !d.hardware) why = 'VAAPI not taken (${d.why})';
		} catch (e:MediaError) why = e.message;
		m.close();
		if (why != null) {
			for (fr in frames) fr.release();
			if (d != null) d.close();
			if (t.codec == H264 && !gpu) check('$f: decoded', false, why);
			else say('skipped: $f${gpu ? " on VAAPI" : ""} (${t.codec}: $why)');
			return null;
		}
		frames.sort((a, b) -> a.time < b.time ? -1 : 1);
		decoders.push(d);
		return frames;
	}

	@:coroutine static function video(f:String, e:Dynamic, gpu = false) {
		var frames = decodeAll(f, gpu);
		if (frames == null) return;
		var m = open(f), t = Lambda.find(m.tracks, t -> t.kind == Video), pts = [], p;
		while ((p = m.next()) != null) if (p.track == t) pts.push(p.time);
		m.close();
		pts.sort((a, b) -> a < b ? -1 : 1);
		var crcs:Array<Int> = e.crcs, bad = [];
		for (i in 0...frames.length)
			if (i >= crcs.length || crc(frames[i]) != crcs[i] || frames[i].time != pts[i]) bad.push(i);
		var first = frames[0], how = '${decoders[0].name}${gpu ? " on VAAPI" : ""}';
		var ok = frames.length == crcs.length && bad.length == 0 && first.width == e.width && first.height == e.height && first.bits == e.bits;
		var times = [for (fr in frames) fr.time].join(",");
		check('$f ($how): ${frames.length} frames, each packet\'s time, planes as ffmpeg decodes them', ok,
			'${frames.length} of ${crcs.length}, ${first.width}x${first.height} ${first.bits} bits ${first.matrix}${first.full ? " full" : ""}${bad.length > 0 ? ", differing: " + bad + ", times " + times : ""}');
		for (fr in frames) fr.release();
		close();
	}

	@:coroutine static function audio(key:String, e:Dynamic) {
		var f = key.split(":")[0], n = Std.parseInt(key.split(":")[1]);
		var m = open(f), t = [for (t in m.tracks) if (t.kind == Audio) t][n];
		var d = try Decoders.audio(t) catch (x:MediaError) {
			if (t.codec == Aac) check('$key: decoded', false, x.message);
			else say('skipped: $key (${t.codec}: ${x.message})');
			m.close();
			return;
		}
		if (d == null) {
			check('$key ${t.codec}: a decoder', t.codec != Aac);
			say('skipped: $key (${t.codec}: no decoder)');
			m.close();
			return;
		}
		var buf = new AudioBuffer(), left = [];
		function hear(k:Int) {
			var q = d.decoded;
			if (q == null) return;
			var keep = @:privateAccess Player.keep(q, k, d.rate, 0, @:privateAccess Player.end(t));
			for (i in keep.first...keep.first + keep.count) left.push(buf.get(i * 2));
		}
		var p;
		while ((p = m.next()) != null)
			if (p.track == t) hear(d.decode(p, m.read(p), buf));
		// (the drained frames, after the last packet's: to the track's end, as the player's tail keeps them)
		var k = d.flush(buf), end = @:privateAccess Player.end(t);
		if (end > 0) k = Std.int(Math.max(0, Math.min(k, Math.round(end * d.rate) - left.length)));
		for (i in 0...k) left.push(buf.get(i * 2));
		var samples:Array<Float> = e.samples, worst = 0.0;
		var tolerance = switch t.codec {
			case Flac | Alac: 1e-6;
			case Aac: 2e-3;
			case _: 1e-3;
		}
		for (i in 0...samples.length)
			if (i * 97 < left.length) worst = Math.max(worst, Math.abs(left[i * 97] - samples[i]));
		var frames:Int = e.frames, name = Std.downcast(d, helder.media.linux.AvAudio)?.name;
		var ok = d.rate == e.rate && left.length == frames && worst <= tolerance;
		check('$key ${t.codec} ($name): ${left.length} frames at ${d.rate}, its samples as ffmpeg\'s', ok, 'ffmpeg ${frames}, the largest difference $worst');
		d.close();
		buf.free();
		m.close();
	}

	// frames turned to RGB by helder's pass on GL (headless: the planes
	// opened from the decoder's memory, or VAAPI's DMA-BUFs, VideoShader's
	// conversion), upright where the pass turns them, against ffmpeg's where
	// the picture is flat: a mean under 1 level, at most 8
	@:coroutine static function colours(rgbs:DynamicAccess<Dynamic>, device:helder.gfx.Device, gpu = false) {
		var vt = new VideoTexture(device);
		for (f => e in rgbs) {
			var frames = decodeAll(f, gpu);
			if (frames == null) continue;
			var m = open(f), t = Lambda.find(m.tracks, t -> t.kind == Video);
			m.close();
			var frame = frames[(e.frame : Int)], handle = frame.plane(0) ?? "none";
			var ok = vt.prepare(frame, t.rotation);
			device.frameInto(vt.target);
			var w = vt.width, h = vt.height, px = haxe.io.Bytes.alloc(w * h * 4);
			var enc = device.beginFrame();
			if (enc != null) {
				vt.record(enc);
				device.readPixels(px);
				device.endFrame();
			}
			device.frameInto(null);
			var r = compare(e, px, w), how = gpu ? 'VAAPI, ${handle.split(":")[0]}${AvVideo.copies ? " (copied: no DMA-BUF import)" : ""}' : "software";
			check('$f ($how): frame ${e.frame} in RGB on ${device.backend}, ${w}x$h upright, as ffmpeg turns it where flat', ok && w == e.width && h == e.height
				&& r.mean < 1 && r.worst <= 8, '${frame.matrix}${frame.full ? " full" : ""} ${frame.bits} bits, ${r.detail}');
			for (fr in frames) fr.release();
			close();
		}
		vt.dispose();
	}

	static function compare(e:Dynamic, px:haxe.io.Bytes, w:Int):{mean:Float, worst:Int, detail:String} {
		var pixels:Array<Int> = e.pixels, sum = 0.0, worst = 0, k = 0;
		while (k < pixels.length) {
			var x = pixels[k], y = pixels[k + 1];
			for (c in 0...3) {
				var dv = Std.int(Math.abs(px.get((y * w + x) * 4 + c) - pixels[k + 2 + c]));
				sum += dv;
				if (dv > worst) worst = dv;
			}
			k += 5;
		}
		var mean = sum / (pixels.length / 5 * 3);
		return {mean: mean, worst: worst, detail: '${Std.int(pixels.length / 5)} pixels, the mean difference ${Math.round(mean * 100) / 100} levels, the largest $worst'};
	}

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
		var p = Player.open(source("h264-aac.mp4"), {silent: true});
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
		p.close();
		var p = Player.open(source("editlist.mov"), {silent: true});
		var f = shown(p, -0.05), crcs:Array<Int> = videos["editlist.mov"].crcs;
		check("editlist.mov: at 0 the frame at -0.05 (the edit's)", f != null && f.time == -0.05 && crc(f) == crcs[4], f == null ? "none" : '${f.time}');
		p.seek(0.6);
		f = shown(p, 0.55);
		check("editlist.mov: seek(0.6): 0.55", f != null && f.time == 0.55 && crc(f) == crcs[10], f == null ? "none" : '${f.time}');
		p.close();
	}

	// a clip played through ALSA's file output (paced at the clock: the audio
	// heard is the clock): each frame shown once, in order, within a frame of
	// the clock; ended at its end; the audio's frames in the file
	@:coroutine static function played() {
		var raw = '$out/played.raw';
		var p = Player.open(new FileSource("tests/media/h264-aac.mp4"), {device: 'file:$raw'});
		var ended = false, shows = [], late = 0.0, t0 = haxe.Timer.stamp();
		p.onEnded = () -> ended = true;
		while (!p.loaded && p.error == null && haxe.Timer.stamp() - t0 < 2) Async.delay(0.002);
		var heard = @:privateAccess p.out != null;
		check("played: through ALSA's file output", heard, p.error ?? "");
		p.play();
		var last:Null<VideoFrame> = null;
		while (!ended && haxe.Timer.stamp() - t0 < 5) {
			var f = p.update();
			if (f != null && f != last) {
				last = f;
				shows.push(f.time);
				var off = p.time - f.time;
				if (off < -1e-6 || off > late) late = Math.max(late, off < 0 ? -off + 1 : off);
			}
			Async.delay(0.002);
		}
		if (p.error != null) check("played: no error", false, p.error);
		var position = p.time;
		p.close();
		check("played: each frame once, in order", shows.join(",") == [for (i in 0...10) i / 10].join(","), shows.join(","));
		check("played: each shown within a frame of the clock", late < 0.1 + 0.01, 'at most ${Math.round(late * 1000)} ms after its time');
		check("played: ended, the clock at the end", ended && Math.abs(position - 1) < 0.1, '$position');
		if (!heard) return;
		// (the frames the decoder gave, between the silence before and after)
		var b = File.getBytes(raw), n = b.length >> 3, first = -1, lastHeard = -1;
		for (i in 0...n)
			if (Math.abs(b.getFloat(i * 8)) > 1e-4) {
				if (first < 0) first = i;
				lastHeard = i;
			}
		var count = lastHeard - first + 1;
		check("played: the audio's 8000 frames in the output", Math.abs(count - 8000) <= 64, '$count: from $first to $lastHeard of $n');
		if (failed == 0) sys.FileSystem.deleteFile(raw);
	}
}
