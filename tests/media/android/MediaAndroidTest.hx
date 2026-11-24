import haxe.DynamicAccess;
import haxe.crypto.Crc32;
import helder.asset.Asset;
import helder.async.Async;
import helder.media.*;
import helder.media.android.McCodec;
import helder.media.android.McVideo;
import helder.media.ui.VideoTexture;

// helder.media's decoding on Android (CI's android job, android.sh): the
// videos of tests/media/apple/decoded.json through MediaCodec, their
// count, times and planes' CRC-32 against ffmpeg's (read as YUV_420_888);
// the audio tracks, their frames and samples; frames turned to RGB on GLES
// from their AHardwareBuffers (the driver's conversion) against ffmpeg's
// where flat; exact seeks and steps by time and pixels; a clip played
// through AAudio, each frame within a frame of the clock. What the device
// has no decoder for is skipped with a line; H.264 and AAC never.
@:hxmc.unsafe(gc)
class MediaAndroidTest {
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
		Sys.println('MediaAndroidTest: ${ok ? "ok" : "FAIL"}: $what${detail == "" ? "" : " (" + detail + ")"}');
		if (!ok) failed++;
	}

	static function main() {
		helder.os.android.Activity.link();
		var expected:Dynamic = haxe.Json.parse(Asset.embed("tests/media/apple/decoded.json").toString());
		var t0 = haxe.Timer.stamp();
		Async.run(_ -> {
			var videos:DynamicAccess<Dynamic> = expected.video;
			for (f => e in videos) video(f, e);
			var audios:DynamicAccess<Dynamic> = expected.audio;
			for (k => e in audios) audio(k, e);
			var rgbs:DynamicAccess<Dynamic> = expected.rgb;
			try {
				colours(rgbs);
				seeks(videos);
				played();
			} catch (e:Dynamic) {
				check('no error', false, Std.string(e) + haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
			}
		});
		Sys.println('MediaAndroidTest: ${Math.round((haxe.Timer.stamp() - t0) * 10) / 10} s');
		Sys.println('MediaAndroidTest: ${failed == 0 ? "passed" : failed + " failed"}');
	}

	static function source(f:String):ByteSource
		return new MemorySource(files[f]);

	@:coroutine static function open(f:String):Media
		return Media.open(source(f));

	static function crc(f:VideoFrame):Int
		return Crc32.make(f.pixels());

	// (the decoder's frames of f's video, every packet given; null: none
	// here, said; H.264 never skipped)
	@:coroutine static function decodeAll(f:String):Null<Array<VideoFrame>> {
		var m = open(f), t = Lambda.find(m.tracks, t -> t.kind == Video);
		var d = try new McVideo(t) catch (e:MediaError) null, frames = [];
		var why = d == null ? "no decoder" : null, p;
		if (d != null) try {
			while ((p = m.next()) != null) if (p.track == t) d.decode(p, m.read(p), true);
			d.flush();
			var t0 = haxe.Timer.stamp();
			while (d.pending > 0 && haxe.Timer.stamp() - t0 < 3) {
				d.take(frames);
				Async.delay(0.002);
			}
			d.take(frames);
			if (frames.length == 0) why = "no frames";
		} catch (e:MediaError) why = e.message;
		m.close();
		if (why != null && t.codec != H264) {
			Sys.println('MediaAndroidTest: skipped: $f (${t.codec}: $why)');
			for (fr in frames) fr.release();
			if (d != null) d.close();
			return null;
		}
		frames.sort((a, b) -> a.time < b.time ? -1 : 1);
		decoders.push(d);
		return frames;
	}

	static final decoders:Array<McVideo> = [];

	// (f's planes against ffmpeg's: where the system's decoder differs (the
	// emulator's host decoder, c2.goldfish's, makes full range video range),
	// said, and its own software decoder's checked)
	@:coroutine static function video(f:String, e:Dynamic) {
		McVideo.readable = true;
		var r = planes(f, e);
		if (r != null && !r.ok && !StringTools.startsWith(r.name, "c2.android.")) {
			Sys.println('MediaAndroidTest: note: $f: the system\'s ${r.name} differs (${r.detail}): c2.android\'s checked');
			McCodec.software = true;
			r = planes(f, e);
			McCodec.software = false;
		}
		if (r != null) check('$f (${r.name}): ${r.count} frames, each packet\'s time, planes as ffmpeg decodes them', r.ok, r.detail);
	}

	@:coroutine static function planes(f:String, e:Dynamic):Null<{ok:Bool, detail:String, name:String, count:Int}> {
		var frames = decodeAll(f);
		if (frames == null) return null;
		var m = open(f), t = Lambda.find(m.tracks, t -> t.kind == Video), pts = [], p;
		while ((p = m.next()) != null) if (p.track == t) pts.push(p.time);
		m.close();
		pts.sort((a, b) -> a < b ? -1 : 1);
		var crcs:Array<Int> = e.crcs, bad = [];
		for (i in 0...frames.length)
			if (i >= crcs.length || crc(frames[i]) != crcs[i] || frames[i].time != pts[i]) bad.push(i);
		var first = frames[0], name = @:privateAccess decoders[0].codec.name;
		var ok = frames.length == crcs.length && bad.length == 0 && first.width == e.width && first.height == e.height && first.bits == e.bits;
		var detail = '${frames.length} of ${crcs.length}, ${first.width}x${first.height} ${first.bits} bits ${first.matrix}${first.full ? " full" : ""}${bad.length > 0 ? ", differing: " + bad : ""}';
		for (fr in frames) fr.release();
		close();
		return {ok: ok, detail: detail, name: name, count: frames.length};
	}

	static function close() {
		for (d in decoders) d.close();
		decoders.resize(0);
	}

	@:coroutine static function audio(key:String, e:Dynamic) {
		var f = key.split(":")[0], n = Std.parseInt(key.split(":")[1]);
		var m = open(f), t = [for (t in m.tracks) if (t.kind == Audio) t][n];
		var d = try Decoders.audio(t) catch (x:MediaError) {
			if (t.codec == Aac) throw x;
			null;
		}
		if (d == null) {
			Sys.println('MediaAndroidTest: skipped: $key (${t.codec}: no decoder)');
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
		d.flush(buf);
		var t0 = haxe.Timer.stamp();
		while (d.pending > 0 && haxe.Timer.stamp() - t0 < 2) {
			hear(d.decode(null, null, buf));
			if (d.decoded == null) Async.delay(0.002);
		}
		var samples:Array<Float> = e.samples, worst = 0.0;
		var tolerance = switch t.codec {
			case Flac | Alac: 1e-6;
			case Aac: 2e-3;
			case _: 1e-3;
		}
		for (i in 0...samples.length)
			if (i * 97 < left.length) worst = Math.max(worst, Math.abs(left[i * 97] - samples[i]));
		var frames:Int = e.frames, slack = t.codec == Opus ? 960 : 0;
		check('$key ${t.codec}: ${left.length} frames at ${d.rate}, its samples as ffmpeg\'s',
			d.rate == e.rate && Math.abs(left.length - frames) <= slack && worst <= tolerance, 'ffmpeg ${frames}, the largest difference $worst');
		d.close();
		buf.free();
		m.close();
	}

	// frames turned to RGB on GLES (headless: VideoTexture's pass from the
	// AHardwareBuffer's EGLImage, the driver's YUV conversion) against
	// ffmpeg's, upright, where the picture is flat
	@:coroutine static function colours(rgbs:DynamicAccess<Dynamic>) {
		McVideo.readable = false;
		var device = helder.gfx.Device.create(helder.os.Surface.headless(64, 64));
		var vt = new VideoTexture(device);
		for (f => e in rgbs) {
			var r = colour(f, e, device, vt);
			if (r != null && !r.ok && !StringTools.startsWith(r.name, "c2.android.")) {
				Sys.println('MediaAndroidTest: note: $f: the system\'s ${r.name} differs in RGB (${r.detail}): c2.android\'s checked');
				McCodec.software = true;
				r = colour(f, e, device, vt);
				McCodec.software = false;
			}
			// (where the system tags it otherwise than ffmpeg reads it, its
			// driver converts as tagged: said, not failed)
			var reads = f == "apple/h264-full.mp4" ? "709" : f == "apple/hevc10.mp4" ? "2020" : "601";
			if (r != null && !r.ok && r.tagged != reads)
				Sys.println('MediaAndroidTest: note: $f (${r.name}): tagged BT.${r.tagged} by the system (ffmpeg reads BT.$reads), converted so by the driver: ${r.detail}');
			else if (r != null) check('$f (${r.name}): frame ${e.frame} in RGB, ${r.size} upright, as ffmpeg turns it where flat', r.ok, r.detail);
		}
		vt.dispose();
		device.dispose();
	}

	// (#93's GPU tolerance where the driver converts: a mean under 1.5 levels, at most 8)
	@:coroutine static function colour(f:String, e:Dynamic, device:helder.gfx.Device, vt:VideoTexture):Null<{ok:Bool, detail:String, name:String, size:String, tagged:String}> {
		var frames = decodeAll(f);
		if (frames == null) return null;
		var m = open(f), t = Lambda.find(m.tracks, t -> t.kind == Video);
		m.close();
		var frame = frames[(e.frame : Int)], tagged = frame.matrix;
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
		var mean = sum / (pixels.length / 5 * 3), name = @:privateAccess decoders[0].codec.name;
		for (fr in frames) fr.release();
		close();
		return {
			ok: ok && w == e.width && h == e.height && mean < 1.5 && worst <= 8,
			detail: '${Std.int(pixels.length / 5)} pixels, the mean difference ${Math.round(mean * 100) / 100} levels, the largest $worst',
			name: name,
			size: '${w}x$h',
			tagged: tagged
		};
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
		McVideo.readable = true;
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

	// a clip played through AAudio, its clock: each frame shown once, in
	// order, within a frame of the clock; ended at its end (an emulator
	// without audio: the monotonic clock, said)
	@:coroutine static function played() {
		McVideo.readable = false;
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
		Sys.println('MediaAndroidTest: played on ${heard ? "AAudio" : "the monotonic clock (no audio output)"}');
		check("played: each frame once, in order", shows.join(",") == [for (i in 0...10) i / 10].join(","), shows.join(","));
		check("played: each shown within a frame of the clock", late < 0.1 + 0.01, 'at most ${Math.round(late * 1000)} ms after its time');
		check("played: ended, the clock at the end", ended && Math.abs(position - 1) < 0.1, '$position');
		check("played: the audio's 8000 frames decoded", Math.abs(written - 8000) <= 64, '$written');
	}
}
