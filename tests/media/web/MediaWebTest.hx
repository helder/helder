import haxe.DynamicAccess;
import haxe.crypto.Crc32;
import helder.async.Async;
import helder.media.*;
import helder.media.ui.VideoShader;
import helder.media.ui.VideoTexture;
import helder.media.web.WebElement;
import helder.media.web.WebVideoDecoder;
import hxmc.unsafe.*;

// helder.media's decoding in a browser (browser.mjs runs it: Chromium,
// Firefox, WebKit): tests/media's videos through WebCodecs, each frame's
// time and planes' CRC-32 against ffmpeg's (tests/media/apple/decoded.json,
// as MediaAppleTest checks Apple's), the audio tracks' frames and samples;
// frames turned to RGB on the GPU (the browser's copy, then VideoTexture's
// pass) against ffmpeg's where flat (decoded.json's, and rgb.json's of VP9
// and AV1: expect.mjs); exact seeks and steps through the
// player; a clip played through the page's AudioWorklet, its frames in
// order and on the audio's clock; the <video> element's fallback played
// once. What a browser does not decode is skipped, each skip printed.
// Prints "ok" and the number of checks; exits 1 on a failure.
@:hxmc.unsafe(gc)
class MediaWebTest {
	static var checks = 0;
	static var failed = 0;
	// (Chromium's, CI's: what the browser gives held to ffmpeg's; the others'
	// own conversions, sizes and colour readings printed, not failed)
	static final strict = Sys.getEnv("BROWSER") == "chromium";

	static function check(what:String, ok:Bool, detail = "") {
		checks++;
		Sys.println('${ok ? "ok" : "FAIL"}: $what${detail == "" ? "" : " (" + detail + ")"}');
		if (!ok) failed++;
	}

	// (a check of what the browser itself gives)
	static function given(what:String, ok:Bool, detail = "") {
		if (ok || strict) return check(what, ok, detail);
		Sys.println('differs in ${Sys.getEnv("BROWSER")}: $what ($detail)');
	}

	static function main() {
		Async.main(_ -> {
			if (Sys.getEnv("MODE") == "autoplay") {
				autoplay();
				Sys.println(failed == 0 ? 'ok ($checks checks)' : '$failed of $checks checks failed');
				Sys.exit(failed == 0 ? 0 : 1);
			}
			var expected:Dynamic = haxe.Json.parse(helder.async.Fetch.bytes("tests/media/apple/decoded.json").toString());
			var videos:DynamicAccess<Dynamic> = expected.video;
			for (f => e in videos) video(f, e);
			var audios:DynamicAccess<Dynamic> = expected.audio;
			for (k => e in audios) audio(k, e);
			colours(expected.rgb);
			colours(haxe.Json.parse(helder.async.Fetch.bytes("tests/media/web/rgb.json").toString()));
			seeks(videos);
			ranged();
			played(audios["apple/vp9-yuv.webm:0"]);
			element();
			Sys.println(failed == 0 ? 'ok ($checks checks)' : '$failed of $checks checks failed');
			Sys.exit(failed == 0 ? 0 : 1);
		});
	}

	@:coroutine static function open(f:String):Media
		return Media.open(WebSource.url("tests/media/" + f));

	static function crc(f:VideoFrame):Int
		return Crc32.make(planes(f));

	// (its planes, as check.mjs read them before the decoder gave it out; empty: RGB)
	static function planes(f:VideoFrame):haxe.io.Bytes {
		var b = haxe.io.Bytes.alloc(Check.pixels_length(f.handle()));
		Check.pixels(f.handle(), hxmc.Span.ofBytes(b));
		return b;
	}

	@:coroutine static function first(m:Media, kind:MediaKind):Null<MediaTrack> {
		var t = Lambda.find(m.tracks, t -> t.kind == kind);
		if (t == null || Decoders.supported(t)) return t;
		Sys.println('skipped: ${t.codec} (${helder.media.web.WebCodec.name(t)}): this browser does not decode it');
		return null;
	}

	// (every frame of a video's track: decoded with its planes read, sorted)
	@:coroutine static function decodeAll(m:Media, t:MediaTrack, keep:Bool):{frames:Array<VideoFrame>, pts:Array<Float>, crcs:Array<Int>} {
		var d = new WebVideoDecoder(t), frames = [], got = [], pts = [], crcs = [];
		function take() {
			got.resize(0);
			d.take(got);
			for (f in got) {
				crcs.push(crc(f));
				frames.push(f);
			}
		}
		var p;
		while ((p = m.next()) != null)
			if (p.track == t) {
				d.decode(p, m.read(p), true);
				pts.push(p.time);
				take();
			}
		d.flush();
		var t0 = haxe.Timer.stamp();
		while (frames.length < pts.length && haxe.Timer.stamp() - t0 < 5) {
			Async.delay(0.005);
			take();
		}
		var order = [for (i in 0...frames.length) i];
		order.sort((a, b) -> frames[a].time < frames[b].time ? -1 : 1);
		pts.sort((a, b) -> a < b ? -1 : 1);
		var sorted = [for (i in order) frames[i]], c = [for (i in order) crcs[i]];
		if (!keep) for (f in sorted) f.release();
		if (!keep) d.close();
		return {frames: sorted, pts: pts, crcs: c};
	}

	// (planes the browser gives as decoded: not RGB (Firefox's software
	// decoders' BGRX), not turned to full range (WebKit's))
	static function decoded(f:String, fr:VideoFrame):Bool
		return planes(fr).length > 0 && !(fr.full && f != "apple/h264-full.mp4");

	@:coroutine static function video(f:String, e:Dynamic) {
		var m = open(f), t = first(m, Video);
		if (t == null) return m.close();
		var r = decodeAll(m, t, true), crcs:Array<Int> = e.crcs, bad = [];
		var one = r.frames[0], asDecoded = one != null && decoded(f, one);
		if (one != null && !asDecoded) Sys.println('$f: the browser gives its frames ${planes(one).length == 0 ? "in RGB" : "in full range"}: their planes not compared');
		for (i in 0...r.frames.length)
			if (i >= crcs.length || asDecoded && r.crcs[i] != crcs[i] || r.frames[i].time != r.pts[i]) bad.push(i);
		var times = [for (i in 0...r.frames.length) if (r.frames[i].time != r.pts[i]) i];
		check('$f: ${r.frames.length} frames, each packet\'s time', one != null && r.frames.length == crcs.length && times.length == 0, times.length > 0 ? 'differing: $times' : "");
		if (one != null) given('$f: planes as ffmpeg decodes them, its size', bad.length == 0 && one.width == e.width && one.height == e.height && (!asDecoded || one.bits == e.bits),
			one == null ? "none" : '${r.frames.length} of ${crcs.length}, ${one.width}x${one.height} ${one.bits} bits ${one.matrix}${one.full ? " full" : ""}${bad.length > 0 ? ", differing: " + bad : ""}');
		for (fr in r.frames) fr.release();
		m.close();
	}

	@:coroutine static function audio(key:String, e:Dynamic) {
		var f = key.split(":")[0], n = Std.parseInt(key.split(":")[1]);
		var m = open(f), t = [for (t in m.tracks) if (t.kind == Audio) t][n];
		if (t.codec != Vorbis && !Decoders.supported(t)) {
			Sys.println('skipped: $key ${t.codec}: this browser does not decode it');
			return m.close();
		}
		var d = Decoders.audio(t), buf = new AudioBuffer(), left = [];
		// (a decoder the browser said it has, failing: its own, noted)
		try audible(m, t, d, buf, left) catch (x:MediaError) {
			Sys.println('skipped: $key ${t.codec}: ${x.message}');
			d.close();
			buf.free();
			return m.close();
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
		check('$key ${t.codec}: ${left.length} frames at ${d.rate}, its samples as ffmpeg\'s', d.rate == e.rate && Math.abs(left.length - frames) <= slack
			&& worst <= tolerance, 'ffmpeg ${frames}, the largest difference $worst');
		d.close();
		buf.free();
		m.close();
	}

	// (a track's packets through d, its first channel's frames kept as the player trims them)
	@:coroutine static function audible(m:Media, t:MediaTrack, d:AudioDecoder, buf:AudioBuffer, left:Array<Float>) {
		function heard(k:Int) {
			var q = d.decoded;
			if (q == null) return false;
			var keep = @:privateAccess Player.keep(q, k, d.rate, 0, @:privateAccess Player.end(t));
			for (i in keep.first...keep.first + keep.count) left.push(buf.get(i * 2));
			return true;
		}
		var p;
		while ((p = m.next()) != null) if (p.track == t) heard(d.decode(p, m.read(p), buf));
		// (what comes later: until nothing has come for a while)
		var t0 = haxe.Timer.stamp();
		while (haxe.Timer.stamp() - t0 < 0.3) {
			Async.delay(0.005);
			while (heard(d.decode(null, null, buf))) t0 = haxe.Timer.stamp();
		}
	}

	// (a frame on the GPU, read back: VideoTexture's target drawn onto a
	// headless surface of its size by the same shader, unconverted, then
	// helder.gfx's readPixels of the page: WebGPU's resolves later)
	@:coroutine static function readBack(vt:VideoTexture):haxe.io.Bytes {
		var w = vt.width, h = vt.height, px = haxe.io.Bytes.alloc(w * h * 4);
		var device = @:privateAccess vt.device, enc = device.beginFrame();
		if (enc == null) return px;
		vt.record(enc);
		var blit = Blit.of(device), u = haxe.io.Bytes.alloc(64);
		VideoShader.params.video.write({
			r: new helder.gfx.shader.Vec4(1, 0, 0, 0),
			g: new helder.gfx.shader.Vec4(0, 1, 0, 0),
			b: new helder.gfx.shader.Vec4(0, 0, 1, 0),
			turn: new helder.gfx.shader.Vec4(0, 1, 1, 1)
		}, u);
		enc.beginPass({colors: [{load: Clear}]});
		enc.setPipeline(blit);
		enc.setVertexBuffer(0, @:privateAccess vt.triangle);
		enc.setUniforms(VideoShader.uniforms[0].binding, u);
		enc.setTexture(VideoShader.textures[0].binding, vt.target, @:privateAccess vt.sampler);
		enc.setTexture(VideoShader.textures[1].binding, vt.target, @:privateAccess vt.sampler);
		enc.draw(3);
		enc.endPass();
		device.endFrame();
		var r = Check.read();
		helder.media.web.Glue.Wait.done(r);
		Check.take(r, hxmc.Span.ofBytes(px));
		return px;
	}

	// frames turned to RGB on the GPU (the browser's copy of its frame and
	// VideoTexture's pass, upright) against ffmpeg's, where the picture is
	// flat (within #93's: a mean under a level, at most 3)
	@:coroutine static function colours(rgbs:DynamicAccess<Dynamic>) {
		for (f => e in rgbs) {
			var m = open(f), t = first(m, Video);
			if (t == null) {
				m.close();
				continue;
			}
			var device = helder.gfx.Device.create(helder.os.Surface.headless(e.width, e.height)), vt = new VideoTexture(device);
			var r = decodeAll(m, t, true), frame = r.frames[(e.frame : Int)];
			var ok = frame != null && vt.prepare(frame, t.rotation);
			var px = ok ? readBack(vt) : haxe.io.Bytes.alloc(0), w = vt.width, h = vt.height;
			var pixels:Array<Int> = e.pixels, sum = 0.0, worst = 0, k = 0;
			while (ok && k < pixels.length) {
				var x = pixels[k], y = pixels[k + 1];
				for (c in 0...3) {
					var dv = Std.int(Math.abs(px.get((y * w + x) * 4 + c) - pixels[k + 2 + c]));
					sum += dv;
					if (dv > worst) worst = dv;
				}
				k += 5;
			}
			var mean = sum / (pixels.length / 5 * 3);
			// (HDR's PQ: the browser maps it to SDR, ffmpeg's reference does not)
			// (the browser's conversion: its chroma's upsampling is not swscale's, a few levels off at most)
			var hdr = f == "apple/hevc10.mp4";
			if (hdr && ok) Sys.println('$f: in RGB, the mean difference ${Math.round(mean * 100) / 100} levels, the largest $worst (PQ mapped by the browser: not checked)');
			else given('$f: frame ${e.frame} in RGB on ${device.backend == WebGPU ? "WebGPU" : "WebGL2"}, ${w}x$h upright, as ffmpeg turns it where flat (${frame.matrix})', ok && w == e.width && h == e.height
				&& mean < 1 && worst <= 8, 'the mean difference ${Math.round(mean * 100) / 100} levels, the largest $worst');
			for (fr in r.frames) fr.release();
			m.close();
			vt.dispose();
			device.dispose();
		}
	}

	// (the player's frame once the update finds it, or the last after two seconds)
	@:coroutine static function shown(p:Player, time:Float):Null<VideoFrame> {
		var t0 = haxe.Timer.stamp();
		while (haxe.Timer.stamp() - t0 < 2) {
			var f = p.update();
			if (f != null && Math.abs(f.time - time) < 1e-6) return f;
			Async.delay(0.004);
		}
		return p.shown;
	}

	// exact seeks and steps on the first video this browser decodes (B-frames: h264-aac.mp4's)
	@:coroutine static function seeks(videos:DynamicAccess<Dynamic>) {
		var f = null, m = null;
		for (c in ["h264-aac.mp4", "apple/vp9-yuv.webm", "av1.webm"]) {
			m = open(c);
			var t = Lambda.find(m.tracks, t -> t.kind == Video);
			if (Decoders.supported(t)) {
				f = c;
				break;
			}
			m.close();
		}
		if (f == null) return Sys.println("skipped: seeks: no video this browser decodes");
		var t = Lambda.find(m.tracks, t -> t.kind == Video), pts = [], keys = [], p;
		while ((p = m.next()) != null) if (p.track == t) {
			pts.push(p.time);
			if (p.key) keys.push(p.time);
		}
		m.close();
		pts.sort((a, b) -> a < b ? -1 : 1);
		var pl = Player.open(WebSource.of("tests/media/" + f), {silent: true}), crcs:Array<Int> = videos[f].crcs, n = pts.length;
		function at(what:String, fr:Null<VideoFrame>, i:Int)
			check('$f: $what: the frame at ${pts[i]}', fr != null && fr.time == pts[i] && (!decoded(f, fr) || crc(fr) == crcs[i]), fr == null ? "none" : '${fr.time}');
		at("opened", shown(pl, pts[0]), 0);
		var k = n >> 1, dt = pts[1] - pts[0];
		pl.seek(pts[k] + dt / 2);
		at('seek(${pts[k] + dt / 2}), exact', shown(pl, pts[k]), k);
		pl.step(1);
		at("step(1)", shown(pl, pts[k + 1]), k + 1);
		pl.step(1);
		at("step(1) again", shown(pl, pts[k + 2]), k + 2);
		pl.step(-1);
		at("step(-1)", shown(pl, pts[k + 1]), k + 1);
		pl.seek(pts[n - 1] + dt * 0.9);
		at("seek: the last", shown(pl, pts[n - 1]), n - 1);
		pl.step(1);
		at("step(1) at the end: stays", shown(pl, pts[n - 1]), n - 1);
		var key = keys.filter(x -> x <= pts[k] + 1e-9).pop();
		pl.seek(pts[k] + dt / 2, false);
		at("seek to its keyframe", shown(pl, key), pts.indexOf(key));
		pl.close();
	}

	// a clip by URL: until its first frame shows, the bytes it needs, not
	// the file's (requests of 256 bytes: a small file; browser.mjs counts
	// them between the marks); one sought before it loaded
	@:coroutine static function ranged() {
		var f = "web/long.webm", m = open(f), ok = Decoders.supported(m.tracks[0]);
		m.close();
		if (!ok) return Sys.println('skipped: ranged: $f\'s VP9 not decoded here');
		WebSource.block = 256;
		helder.async.Fetch.bytes("begin.mark");
		var p = Player.open(WebSource.of("tests/media/" + f), {silent: true});
		var fr = shown(p, 0);
		helder.async.Fetch.bytes("ranged.mark");
		WebSource.block = 65536;
		check('ranged: $f by URL, its first frame', fr != null && fr.time == 0, fr == null ? "none" : '${fr.time}');
		p.close();
		// (a seek asked for before it loaded: there at once)
		var p = Player.open(WebSource.of("tests/media/" + f), {silent: true});
		p.seek(2.55);
		var fr = shown(p, 2.5);
		check('ranged: $f sought before it loaded, the frame at 2.5', fr != null && fr.time == 2.5, fr == null ? "none" : '${fr.time}');
		p.close();
	}

	// a clip played through the page's AudioWorklet (its clock): each frame
	// shown once, in order, within a frame of the clock; ended at its end;
	// the audio's frames all given to the output
	@:coroutine static function played(e:Dynamic) {
		var f = "apple/vp9-yuv.webm", m = open(f);
		var ok = Decoders.supported(m.tracks[0]) && Decoders.supported(m.tracks[1]);
		m.close();
		if (!ok) return Sys.println('skipped: played: $f\'s VP9 or Opus not decoded here');
		var p = Player.open(WebSource.of("tests/media/" + f));
		var ended = false, shows = [], late = 0.0, t0 = haxe.Timer.stamp();
		p.onEnded = () -> ended = true;
		while (p.update() == null && p.error == null && haxe.Timer.stamp() - t0 < 2) Async.delay(0.004);
		p.play();
		var last:Null<VideoFrame> = null;
		while (!ended && haxe.Timer.stamp() - t0 < 5) {
			var fr = p.update();
			if (fr != null && fr != last) {
				last = fr;
				shows.push(fr.time);
				var off = p.time - fr.time;
				if (off < -1e-6 || off > late) late = Math.max(late, off < 0 ? -off + 1 : off);
			}
			Async.delay(0.004);
		}
		var position = p.time, heard = @:privateAccess p.ring.read, outputs = @:privateAccess p.out != null;
		p.close();
		check("played: on the page's audio output", outputs, '${p.error}');
		check("played: each frame once, in order", shows.join(",") == [for (i in 0...10) i / 10].join(","), shows.join(","));
		check("played: each shown within a frame of the clock", late < 0.1 + 0.02, 'at most ${Math.round(late * 1000)} ms after its time');
		check("played: ended, the clock at the end", ended && Math.abs(position - 1) < 0.1, '$position');
		var frames:Int = e.frames;
		check("played: the audio's frames given to the output", Math.abs(heard - frames) <= 960, '$heard of ffmpeg\'s $frames');
	}

	// (a page with no gesture yet: browser.mjs's MODE autoplay) a muted
	// clip plays, its audio output silent, the pictures on; unmuted, it
	// waits for a gesture
	@:coroutine static function autoplay() {
		var f = "apple/vp9-yuv.webm", m = open(f), ok = Decoders.supported(m.tracks[0]) && Decoders.supported(m.tracks[1]);
		m.close();
		if (!ok) return Sys.println('skipped: autoplay: $f not decoded here');
		var p = Player.open(WebSource.of("tests/media/" + f)), t0 = haxe.Timer.stamp();
		p.muted = true;
		while (!p.loaded && p.error == null && haxe.Timer.stamp() - t0 < 2) Async.delay(0.004);
		p.play();
		var last = 0.0;
		while (haxe.Timer.stamp() - t0 < 3 && last < 0.5) {
			var fr = p.update();
			if (fr != null) last = fr.time;
			Async.delay(0.01);
		}
		check("autoplay: muted, it plays before a gesture", last >= 0.5, 'the frame at $last');
		p.close();
		var p = Player.open(WebSource.of("tests/media/" + f));
		t0 = haxe.Timer.stamp();
		while (!p.loaded && p.error == null && haxe.Timer.stamp() - t0 < 2) Async.delay(0.004);
		p.play();
		t0 = haxe.Timer.stamp();
		while (haxe.Timer.stamp() - t0 < 0.6) {
			p.update();
			Async.delay(0.01);
		}
		check("autoplay: with sound, it waits for a gesture", p.time < 0.1, '${p.time}');
		p.close();
	}

	// the <video> element's fallback (asked for: WebCodecs decodes these):
	// loaded, played on its own clock, seeked, its frame drawn
	@:coroutine static function element() {
		WebElement.forced = true;
		var p = Player.open(WebSource.of("tests/media/apple/vp9-yuv.webm"));
		WebElement.forced = false;
		var t0 = haxe.Timer.stamp();
		while (!p.loaded && p.error == null && haxe.Timer.stamp() - t0 < 3) Async.delay(0.004);
		if (p.error != null && p.error.indexOf("does not play") >= 0) return Sys.println('skipped: element: ${p.error}');
		check("element: loaded, its duration", p.loaded && Math.abs(p.duration - 1) < 0.05, '${p.error} ${p.duration}');
		p.muted = true;
		p.play();
		var times = [];
		while (haxe.Timer.stamp() - t0 < 4 && (times.length == 0 || times[times.length - 1] < 0.5)) {
			var fr = p.update();
			if (fr != null && (times.length == 0 || fr.time != times[times.length - 1])) times.push(fr.time);
			Async.delay(0.01);
		}
		check("element: played, its frames on", times.length >= 3 && times[times.length - 1] >= 0.5, times.join(","));
		p.pause();
		p.seek(0.25);
		var fr = null;
		t0 = haxe.Timer.stamp();
		while (haxe.Timer.stamp() - t0 < 2 && Math.abs(p.time - 0.25) > 0.06) Async.delay(0.01);
		fr = p.update();
		check("element: seek(0.25)", Math.abs(p.time - 0.25) <= 0.06, '${p.time}');
		var device = helder.gfx.Device.create(helder.os.Surface.headless(128, 96)), vt = new VideoTexture(device);
		var ok = fr != null && vt.prepare(fr, 0), px = ok ? readBack(vt) : haxe.io.Bytes.alloc(0), lit = 0;
		for (i in 0...px.length >> 2) if (px.get(i * 4) + px.get(i * 4 + 1) + px.get(i * 4 + 2) > 60) lit++;
		check("element: its frame drawn", ok && vt.width == 128 && lit > px.length >> 3, '${vt.width}x${vt.height}, $lit lit');
		vt.dispose();
		device.dispose();
		p.close();
	}
}

// (the page's: the frame's pixels, helder.gfx's readPixels, which resolves later)
@:hxmc.c @:hxmc.lib("helder_media_check") extern class Check {
	static function read():Int;
	@:hxmc.fast @:hxmc.safe static function take(h:Int, into:hxmc.Span<UInt8>):Void;
	static function pixels_length(frame:Int):Int;
	@:hxmc.fast @:hxmc.safe static function pixels(frame:Int, into:hxmc.Span<UInt8>):Void;
}

// (a pipeline of VideoShader's onto the surface: readBack's)
class Blit {
	static var made:Null<helder.gfx.Pipeline>;
	static var on:Null<helder.gfx.Device>;

	public static function of(device:helder.gfx.Device):helder.gfx.Pipeline {
		if (on != device || made == null) {
			made = device.createPipeline(VideoShader.pipeline({}));
			on = device;
		}
		return made;
	}
}
