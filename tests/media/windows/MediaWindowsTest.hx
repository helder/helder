import haxe.DynamicAccess;
import haxe.crypto.Crc32;
import helder.asset.Asset;
import helder.async.Async;
import helder.media.*;
import helder.media.ui.VideoTexture;
import helder.media.windows.MfTransform;
import helder.media.windows.MfVideo;

// helder.media's decoding on Windows (the system-images lane on a Windows
// host, CI's desktop-windows job): the videos of tests/media/apple/
// decoded.json through Media Foundation, their count, times and planes'
// CRC-32 against ffmpeg's; the audio tracks, their frames and samples;
// frames turned to RGB by helder's pass on Direct3D 11 (WARP on CI's
// runner) and by the system layer's conversion (WinLayer's, on the CPU)
// against ffmpeg's where flat; exact seeks and steps by time and pixels; a
// clip played on WASAPI's clock (the monotonic clock where the machine has
// no output, said), each frame within a frame of it. What the system has
// no decoder for (HEVC, VP9 and AV1 are Store extensions) is skipped with
// a line; H.264 and AAC never.
@:hxmc.unsafe(gc)
class MediaWindowsTest {
	static var failed = 0;

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
		Sys.println('MediaWindowsTest: ${ok ? "ok" : "FAIL"}: $what${detail == "" ? "" : " (" + detail + ")"}');
		if (!ok) failed++;
	}

	static function say(s:String)
		Sys.println('MediaWindowsTest: $s');

	static function main() {
		VorbisDecoder.link();
		var expected:Dynamic = haxe.Json.parse(Asset.embed("tests/media/apple/decoded.json").toString());
		var t0 = haxe.Timer.stamp();
		say('Media Foundation: ${helder.media.windows.Mf.loaded()}');
		// (the device first: where it is a GPU's, the decoders decode on it, DXVA)
		var device = helder.gfx.Device.create(helder.os.Surface.headless(64, 64));
		say('a hardware device for DXVA: ${!helder.gfx.d3d11.D3D11Backend.decoding.isNull()}');
		Async.run(_ -> {
			try {
				var videos:DynamicAccess<Dynamic> = expected.video;
				say("videos");
				for (f => e in videos) {
					MfVideo.software = true;
					video(f, e);
					MfVideo.software = false;
					if (!helder.gfx.d3d11.D3D11Backend.decoding.isNull()) video(f, e, true);
				}
				say("audio");
				var audios:DynamicAccess<Dynamic> = expected.audio;
				for (k => e in audios) audio(k, e);
				var rgbs:DynamicAccess<Dynamic> = expected.rgb;
				// (each part said first: a crash's place in the log)
				say("colours");
				colours(rgbs, device);
				say("seeks");
				seeks(videos);
				say("played");
				played();
			} catch (e:Dynamic) {
				check('no error', false, Std.string(e) + haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
			}
		});
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

	static final decoders:Array<MfVideo> = [];

	static function close() {
		for (d in decoders) d.close();
		decoders.resize(0);
	}

	// (the decoder's frames of f's video, every packet given; null: none
	// here, said; H.264 never skipped)
	@:coroutine static function decodeAll(f:String):Null<Array<VideoFrame>> {
		var m = open(f), t = Lambda.find(m.tracks, t -> t.kind == Video);
		var why:Null<String> = null, d:Null<MfVideo> = null, frames = [], p;
		try {
			d = new MfVideo(t);
			while ((p = m.next()) != null) if (p.track == t) d.decode(p, m.read(p), true);
			d.flush();
			d.take(frames);
			if (frames.length == 0) why = "no frames";
		} catch (e:MediaError) why = e.message;
		m.close();
		if (why != null) {
			for (fr in frames) fr.release();
			if (d != null) d.close();
			if (t.codec == H264) check('$f: decoded', false, '$why; ${MfTransform.found}');
			else say('skipped: $f (${t.codec}: $why; ${MfTransform.found})');
			return null;
		}
		frames.sort((a, b) -> a.time < b.time ? -1 : 1);
		decoders.push(d);
		return frames;
	}

	// (gpu: the GPU's decoder, said where the system's would not take it)
	@:coroutine static function video(f:String, e:Dynamic, gpu = false) {
		var frames = decodeAll(f);
		if (frames == null) return;
		if (gpu && !decoders[0].hardware) {
			say('$f: DXVA not taken (${decoders[0].why})');
			for (fr in frames) fr.release();
			close();
			return;
		}
		var m = open(f), t = Lambda.find(m.tracks, t -> t.kind == Video), pts = [], p;
		while ((p = m.next()) != null) if (p.track == t) pts.push(p.time);
		m.close();
		pts.sort((a, b) -> a < b ? -1 : 1);
		var crcs:Array<Int> = e.crcs, bad = [];
		for (i in 0...frames.length)
			if (i >= crcs.length || crc(frames[i]) != crcs[i] || frames[i].time != pts[i]) bad.push(i);
		var first = frames[0], how = decoders[0].hardware ? "DXVA" : "software";
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
			if (t.codec == Aac) check('$key: decoded', false, '${x.message}; ${MfTransform.found}');
			null;
		}
		if (d == null) {
			if (t.codec != Aac) say('skipped: $key (${t.codec}: no decoder; ${MfTransform.found})');
			m.close();
			return;
		}
		var buf = new AudioBuffer(), left = [], outs = [];
		function hear(k:Int) {
			var q = d.decoded;
			var mf = Std.downcast(d, helder.media.windows.MfAudio);
			if (k > 0 || q != null) outs.push('${q == null ? "-" : Std.string(q.pts) + "+" + q.duration} n=$k${mf == null ? "" : " at " + Math.round(mf.stamped * t.timescale)}');
			if (q == null) return;
			var keep = @:privateAccess Player.keep(q, k, d.rate, 0, @:privateAccess Player.end(t));
			for (i in keep.first...keep.first + keep.count) left.push(buf.get(i * 2));
		}
		var p;
		try {
			while ((p = m.next()) != null)
				if (p.track == t) hear(d.decode(p, m.read(p), buf));
			d.flush(buf);
			var guard = 0;
			while (d.pending > 0 && guard++ < 1000) {
				hear(d.decode(null, null, buf));
				if (d.decoded == null) break;
			}
		} catch (x:MediaError) {
			check('$key ${t.codec}: decoded', false, x.message);
			d.close();
			buf.free();
			m.close();
			return;
		}
		var samples:Array<Float> = e.samples, worst = 0.0;
		var tolerance = switch t.codec {
			case Flac | Alac: 1e-6;
			case Aac: 2e-3;
			case _: 1e-3;
		}
		for (i in 0...samples.length)
			if (i * 97 < left.length) worst = Math.max(worst, Math.abs(left[i * 97] - samples[i]));
		// (MP4's Opus: ffmpeg reads its pre-skip in the track's timescale, its
		// count off by that; Matroska's within a millisecond (its times whole
		// ones: the first packet's -7 is CodecDelay's -6.5); else exact)
		var frames:Int = e.frames, slack = t.codec != Opus ? 0 : f.indexOf(".mp4") > 0 ? 960 : 48;
		var ok = d.rate == e.rate && Math.abs(left.length - frames) <= slack && worst <= tolerance;
		check('$key ${t.codec}: ${left.length} frames at ${d.rate}, its samples as ffmpeg\'s', ok, 'ffmpeg ${frames}, the largest difference $worst');
		if (!ok) {
			// (what the decoder gave: each output's packet (pts+duration, the
			// track's ticks), frames, the decoder's own time; and the shift of
			// ours that fits ffmpeg's best)
			var n = outs.length;
			say('$key: outputs ${n}: ${outs.slice(0, 4).join(", ")} ... ${outs.slice(Std.int(Math.max(4, n - 3))).join(", ")}');
			var best = 0, bestErr = 1e9;
			for (s in -1600...1601) {
				var w = 0.0, used = 0;
				for (i in 0...samples.length) {
					var j = i * 97 + s;
					if (j < 0 || j >= left.length) continue;
					used++;
					w = Math.max(w, Math.abs(left[j] - samples[i]));
				}
				if (used > samples.length / 2 && w < bestErr) {
					bestErr = w;
					best = s;
				}
			}
			say('$key: ours fit ffmpeg\'s best shifted by $best frames (the largest difference then $bestErr)');
		}
		d.close();
		buf.free();
		m.close();
	}

	// frames turned to RGB by helder's pass on Direct3D 11 (headless: the
	// planes opened from the decoder's memory, VideoShader's conversion) and
	// by WinLayer's on the CPU, upright where the pass turns them, against
	// ffmpeg's where the picture is flat: a mean under 1 level, at most 8
	@:coroutine static function colours(rgbs:DynamicAccess<Dynamic>, device:helder.gfx.Device) {
		var vt = new VideoTexture(device);
		for (f => e in rgbs) {
			var frames = decodeAll(f);
			if (frames == null) continue;
			var m = open(f), t = Lambda.find(m.tracks, t -> t.kind == Video);
			m.close();
			var frame = frames[(e.frame : Int)];
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
			var r = compare(e, px, w), how = decoders[0].hardware ? "DXVA" : "software";
			check('$f ($how): frame ${e.frame} in RGB on ${device.backend}, ${w}x$h upright, as ffmpeg turns it where flat', ok && w == e.width && h == e.height
				&& r.mean < 1 && r.worst <= 8, r.detail);
			// (the system layer's conversion, on the CPU: the picture as decoded, not turned)
			if (t.rotation == 0) {
				var cw = frame.width, out:hxmc.unsafe.Ptr<hxmc.unsafe.UInt8> = hxmc.unsafe.LibC.malloc(cw * frame.height * 4);
				@:privateAccess helder.media.ui.WinLayer.convert(frame, frame.pixels(), out);
				var rgba = haxe.io.Bytes.alloc(cw * frame.height * 4);
				hxmc.unsafe.BytesPtr.copyIn(rgba, 0, out, rgba.length);
				hxmc.unsafe.LibC.free(out);
				var l = compare(e, rgba, cw);
				check('$f: frame ${e.frame} in RGB as the system layer is given it, as ffmpeg turns it where flat', l.mean < 1 && l.worst <= 8, l.detail);
			}
			for (fr in frames) fr.release();
			close();
		}
		vt.dispose();
		device.dispose();
		say('the device let go: no decoder on it after (${helder.gfx.d3d11.D3D11Backend.decoding.isNull()})');
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

	// a clip played through WASAPI, its clock: each frame shown once, in
	// order, within a frame of the clock; ended at its end; the audio's
	// frames into the output (where the machine has one: CI's runner has
	// none, the monotonic clock then, said)
	@:coroutine static function played() {
		var p = Player.open(source("h264-aac.mp4"));
		var ended = false, shows = [], late = 0.0, t0 = haxe.Timer.stamp();
		p.onEnded = () -> ended = true;
		while (!p.loaded && haxe.Timer.stamp() - t0 < 2) Async.delay(0.002);
		var heard = @:privateAccess p.out != null;
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
		var position = p.time, ring = @:privateAccess p.ring, written = ring == null ? 0 : ring.written;
		p.close();
		say('played on ${heard ? "WASAPI" : "the monotonic clock (no audio output)"}');
		check("played: each frame once, in order", shows.join(",") == [for (i in 0...10) i / 10].join(","), shows.join(","));
		check("played: each shown within a frame of the clock", late < 0.1 + 0.01, 'at most ${Math.round(late * 1000)} ms after its time');
		check("played: ended, the clock at the end", ended && Math.abs(position - 1) < 0.1, '$position');
		if (heard) check("played: the audio's 8000 frames decoded", Math.abs(written - 8000) <= 64, '$written');
		else say('played: the audio\'s frames not checked (no output: $written in the ring)');
	}
}
