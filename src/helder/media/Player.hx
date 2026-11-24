package helder.media;

import helder.async.Async;
import helder.os.audio.Audio;
import hxmc.unsafe.*;

typedef PlayerOptions = {
	// the audio output (helder.os.audio.AudioConfig's device: "file:PATH" in tests)
	@:optional var device:String;
	// no audio output: the pictures on the monotonic clock (thumbnails, a muted preview)
	@:optional var silent:Bool;
}

// A video or audio file played: its first video and audio tracks decoded
// by the system's decoders (Decoders) a little ahead of the clock
// (Playback) on a task of the loop, the audio into an output of its own
// (helder.os.audio.Audio, at the decoder's rate: the system resamples),
// which is the clock; the picture due now is update()'s. The controls
// are the app's: play, pause, seek, step, rate, volume, muted, loop.
//
//   var p = Player.open(new FileSource("clip.mp4"));
//   p.onLoaded = () -> p.play();
//   // each frame: var f = p.update(); draw f (helder.media.ui.VideoTexture)
@:hxmc.unsafe(gc)
class Player {
	// (the frames decoded ahead, the seconds of audio)
	static inline var AHEAD = 8;
	static inline var AUDIO_AHEAD = 0.5;
	// (frames behind the last decoded that may still come before it: B-frames)
	static inline var REORDER = 3;
	// (frames given a decoder before it gave one, at most)
	static inline var HELD = 24;
	static inline var EPS = 1e-6;

	public var media(default, null):Null<Media>;
	public var video(default, null):Null<MediaTrack>;
	public var audio(default, null):Null<MediaTrack>;
	// seconds (0 until loaded)
	public var duration(default, null) = 0.0;
	public var loaded(default, null) = false;
	public var error(default, null):Null<String>;
	public var ended(default, null) = false;
	public var playing(get, never):Bool;
	public var time(get, never):Float;
	// the frame shown at the last update (null: none yet)
	public var shown(default, null):Null<VideoFrame>;
	public var rate(default, set) = 1.0;
	public var volume = 1.0;
	public var muted(default, set) = false;
	public var loop = false;
	public var onLoaded:Null<Void->Void>;
	public var onEnded:Null<Void->Void>;
	public var onError:Null<String->Void>;
	// a frame came in (decoded, or due): what shows it draws again
	public var onFrame:Null<Void->Void>;

	final clock = new Playback();
	final options:PlayerOptions;
	final source:ByteSource;
	var vdec:Null<VideoDecoder>;
	var adec:Null<AudioDecoder>;
	var out:Null<Audio>;
	var ring:Null<AudioRing>;
	final pcm = new AudioBuffer();
	// (decoded, in presentation order)
	final frames:Array<VideoFrame> = [];
	final fresh:Array<VideoFrame> = [];
	// (frames shown before, let go a few updates later: the GPU may still read them)
	final retired:Array<VideoFrame> = [];
	final retiredAt:Array<Int> = [];
	var updates = 0;
	// (a seek asked for, done by the pump: its time and exactness; -1e300 none)
	var asked = -1e300;
	var exact = true;
	var stepping = 0;
	// (after a seek: the first frame shown, the first audio heard)
	var target = 0.0;
	var audioFrom = 0.0;
	// (the media time of the ring's first frame since a seek)
	var ringTime = 0.0;
	var eof = false;
	var flushed = false;
	// (the audio shorter than the video: once it is over, silence and the clock going on)
	var pads = false;
	var closed = false;
	// (the audio thread's: whether it gives the ring's frames, and their gain)
	var sounding = false;
	var gain = 1.0;
	// (a play whose output gives nothing yet: when, and the ring's frames read then)
	var playAt = -1.0;
	var readAt = 0;
	#if (hxmc.target == "wasm32-wasi")
	// (the browser's <video>, where WebCodecs does not decode the file)
	var element:Null<helder.media.web.WebElement>;
	#end

	public static function open(source:ByteSource, ?options:PlayerOptions):Player
		return new Player(source, options ?? {});

	function new(source:ByteSource, options:PlayerOptions) {
		this.source = source;
		this.options = options;
		Async.launch(_ -> run());
	}

	function get_playing():Bool
		return clock.playing;

	function get_time():Float {
		#if (hxmc.target == "wasm32-wasi")
		if (element != null) return element.time;
		#end
		return clock.time;
	}

	// (unmuted after playing on without its output: the output again, from where it is)
	function set_muted(m:Bool):Bool {
		muted = m;
		if (!m && out == null && adec != null && options.silent != true && loaded && !closed) {
			out = output(adec.rate);
			if (out != null) seek(time);
		}
		return m;
	}

	public function play() {
		if (playing || closed) return;
		if (ended) {
			ended = false;
			seek(0);
		}
		resync();
		clock.play();
		sounding = true;
		#if (hxmc.target == "wasm32-wasi")
		if (element != null) element.play();
		#end
		if (out != null) out.start();
		playAt = haxe.Timer.stamp();
		readAt = ring == null ? 0 : ring.read;
	}

	public function pause() {
		if (!playing) return;
		clock.pause();
		sounding = false;
		#if (hxmc.target == "wasm32-wasi")
		if (element != null) element.pause();
		#end
	}

	// to time (seconds): exact, the frame due then (decoded from the
	// keyframe before it, the frames between not shown); else the keyframe
	// before it, sooner
	public function seek(time:Float, exact = true) {
		if (closed) return;
		asked = Math.max(0, Math.min(time, duration > 0 ? duration : time));
		this.exact = exact;
		ended = false;
		stepping = 0;
		clock.seek(asked);
		#if (hxmc.target == "wasm32-wasi")
		if (element != null) {
			element.seek(asked);
			asked = -1e300;
		}
		#end
	}

	// a frame on (1) or back (-1), paused
	public function step(n:Int) {
		pause();
		if (shown == null || n == 0) return;
		#if (hxmc.target == "wasm32-wasi")
		// (the element's: a seek by the frame's duration)
		if (element != null) {
			seek(shown.time + n * element.frame + element.frame * 0.25);
			return;
		}
		#end
		if (n < 0) seek(shown.time - 1e-9) else stepping = n;
	}

	function set_rate(r:Float):Float {
		if (r <= 0 || r == rate) return rate;
		rate = r;
		clock.speed(r);
		#if (hxmc.target == "wasm32-wasi")
		if (element != null) element.rate(r);
		#end
		// (the output at the decoder's rate times it: faster, higher; the ring goes on)
		if (out != null && adec != null) {
			out.close();
			out = output(adec.rate);
			if (out != null) {
				resync();
				if (playing) out.start();
			}
		}
		return r;
	}

	// (the clock at the ring's next frame: the output's queue, dropped or
	// heard while paused, no longer counts)
	function resync() {
		var r = ring;
		if (r != null && adec != null && !closed && asked < -1e299) clock.seek(ringTime + r.read / adec.rate);
	}

	// the frame to show now: the latest due of those decoded (a frame:
	// update keeps it, its caller must not release it)
	public function update():Null<VideoFrame> {
		updates++;
		while (retired.length > 0 && updates - retiredAt[0] > 3) {
			retired.shift().release();
			retiredAt.shift();
		}
		#if (hxmc.target == "wasm32-wasi")
		if (element != null) return shownOf(element);
		#end
		// (playing, muted, its output giving nothing: a page before its first
		// gesture, whose audio waits for one; the pictures go on, on the
		// monotonic clock, the output opened again when unmuted)
		if (playing && muted && out != null && ring != null && ring.read == readAt && playAt > 0 && haxe.Timer.stamp() - playAt > 0.3) {
			out.close();
			out = null;
			clock.audio(0, 0);
		}
		collect();
		if (stepping > 0) return shown;
		var settled = drained() ? frames.length : frames.length - REORDER;
		var due = -1, t = clock.time;
		for (i in 0...settled) if (frames[i].time <= t) due = i else break;
		if (due >= 0) {
			retire(shown);
			shown = frames[due];
			for (i in 0...due) frames[i].release();
			frames.splice(0, due + 1);
		}
		// (the end once heard: the clock at the audio's last frame, or the
		// video's end where it is longer; the output's queue played out)
		// (all the audio decoded: whether it ends before the video)
		var a = adec, r = ring, v = video;
		if (eof && flushed && a != null && a.pending == 0 && r != null && v != null)
			pads = ringTime + r.written / a.rate < (v.duration > 0 ? v.duration : duration) - 1e-3;
		if (playing && eof && flushed && frames.length == 0 && (vdec == null || vdec.pending == 0) && (adec == null || adec.pending == 0)
			&& (ring == null || ring.available() == 0)) {
			var end = ring != null && adec != null ? ringTime + ring.written / adec.rate : 0.0;
			if (video != null) end = Math.max(end, Math.max(duration, last));
			if (t >= end - 1e-3) finish();
		}
		return shown;
	}

	var last = 0.0;

	#if (hxmc.target == "wasm32-wasi")
	// (the element's frame, its controls kept to the player's)
	function shownOf(e:helder.media.web.WebElement):Null<VideoFrame> {
		e.sound(muted ? 0 : volume, loop);
		var f = e.current();
		if (f != shown) {
			shown = f;
			if (onFrame != null) onFrame();
		}
		if (playing && e.ended) finish();
		return shown;
	}
	#end

	function retire(f:Null<VideoFrame>) {
		if (f == null) return;
		retired.push(f);
		retiredAt.push(updates);
	}

	function finish() {
		if (loop) {
			seek(0);
			return;
		}
		clock.pause();
		sounding = false;
		ended = true;
		if (onEnded != null) onEnded();
	}

	// (the decoder's frames in order; before a seek's target dropped)
	function collect() {
		var d = vdec;
		if (d == null) return;
		fresh.resize(0);
		d.take(fresh);
		for (f in fresh) {
			if (f.time < target - EPS || asked > -1e299) {
				f.release();
				continue;
			}
			var i = frames.length;
			while (i > 0 && frames[i - 1].time > f.time) i--;
			frames.insert(i, f);
			if (f.time > last) last = f.time;
		}
		if (fresh.length > 0 && onFrame != null) onFrame();
	}

	// (the loop: a seek asked for, a step, a packet where a decoder wants
	// one; all else plain functions: a coroutine's state machine grows with
	// what it holds across its suspensions)
	@:coroutine function run() {
		try {
			var m = Media.open(source);
			var v = Lambda.find(m.tracks, t -> t.kind == Video), a = Lambda.find(m.tracks, t -> t.kind == Audio);
			// (the browser's answer awaited: isConfigSupported; elsewhere the decoders tell)
			#if (hxmc.target == "wasm32-wasi")
			if (v != null && !Decoders.supported(v)) v = null;
			if (a != null && !Decoders.supported(a)) a = null;
			var all = Lambda.find(m.tracks, t -> t.kind == Video);
			if (all != null && (v == null || helder.media.web.WebElement.forced) && fallback(m, all)) return;
			#end
			opened(m, v, a);
			var first = true;
			while (!closed) {
				if (first || asked > -1e299) {
					// (a seek asked for before it loaded: there at once)
					var t = asked > -1e299 ? asked : 0.0, x = first || exact;
					asked = -1e300;
					reset();
					var pre = seeked(m.seek(t), t, x);
					if (pre < 1e299) @:privateAccess m.seekTrack(audio.index, pre);
					if (first) {
						first = false;
						loaded = true;
						if (onLoaded != null) onLoaded();
					}
					continue;
				}
				if (stepping > 0 && stepped()) continue;
				if (!wants()) {
					Async.delay(playing || stepping > 0 ? 0.004 : 0.02);
					continue;
				}
				var p = m.next();
				if (p == null) eof = true else if (p.track == video || p.track == audio) feed(p, m.read(p));
			}
		} catch (e:Dynamic) {
			if (closed) return;
			error = Std.string(e is haxe.Exception ? (e : haxe.Exception).message : e);
			if (onError != null) onError(error);
		}
	}

	#if (hxmc.target == "wasm32-wasi")
	// (what WebCodecs does not decode played by the page's <video>: false
	// where there is none, a worker's)
	@:coroutine function fallback(m:Media, v:MediaTrack):Bool {
		var e = helder.media.web.WebElement.open(source);
		if (e == null) return false;
		element = e;
		if (!e.ready()) throw new MediaError("the browser does not play this file");
		if (closed) return true;
		media = m;
		video = v;
		var s = Lambda.find(m.seek(0), s -> s.track == v);
		e.frame = s != null && s.packet != null && s.packet.duration > 0 ? s.packet.duration / v.timescale : 1 / 30;
		duration = m.duration > 0 ? m.duration : e.duration;
		e.rate(rate);
		loaded = true;
		if (onLoaded != null) onLoaded();
		return true;
	}
	#end

	// (its tracks: the first video and audio, where the system decodes them; their decoders, the output)
	function opened(m:Media, v:Null<MediaTrack>, a:Null<MediaTrack>) {
		media = m;
		video = v;
		audio = a;
		if (video != null) {
			vdec = Decoders.video(video);
			if (vdec == null) video = null;
		}
		if (audio != null) {
			adec = try Decoders.audio(audio) catch (e:MediaError) null;
			if (adec == null) audio = null;
		}
		if (video == null && audio == null) throw new MediaError("nothing this system decodes");
		duration = m.duration > 0 ? m.duration : Math.max(video != null ? video.duration : 0, audio != null ? audio.duration : 0);
		if (adec != null) {
			// (two seconds, and room for a packet's 16384 frames over the
			// first that decodes asks for: a low rate's, 8 kHz's, too)
			ring = new AudioRing(Std.int(Math.max(adec.rate * 2, 65536)));
			out = options.silent == true ? null : output(adec.rate);
		}
	}

	function output(rate:Int):Null<Audio> {
		var o = try Audio.open({sampleRate: Std.int(rate * this.rate), channels: 2, frames: 512, device: options.device, session: "playback"}, fill)
		catch (_:Dynamic) null;
		if (o == null) {
			// (no output: the pictures on the monotonic clock, the audio dropped)
			clock.audio(0, 0);
			return null;
		}
		clock.audio(o.sampleRate, o.latency);
		return o;
	}

	// (the audio thread)
	function fill(buffer:Ptr<Float32>, n:Int) {
		var r = ring;
		if (!sounding || r == null) return;
		var g = muted ? 0.0 : volume;
		var k = r.take(buffer, n, g);
		// (the audio over and the video on: silence, the clock going on with it)
		if (k < n && pads) {
			for (i in k * 2...n * 2) Mem.setF32(buffer, i * 4, 0);
			k = n;
		}
		if (k > 0) clock.played(k);
	}

	// (before a seek: the output stopped while the ring is emptied, what was decoded dropped)
	function reset() {
		if (out != null) out.stop();
		for (f in frames) f.release();
		frames.resize(0);
		if (vdec != null) {
			vdec.reset();
			fresh.resize(0);
		}
		if (adec != null) adec.reset();
		if (ring != null) ring.clear();
		eof = false;
		flushed = false;
		pads = false;
	}

	// (the media seeked to time: the frame to show first, the audio to hear
	// first; the clock there, the output started again. The audio track's
	// seek a little before (returned; 1e300 none): a lossy codec's first
	// frames overlap the packet before theirs, Opus's SeekPreRoll, decoded,
	// not heard)
	function seeked(seeks:Array<Seek>, time:Float, exact:Bool):Float {
		target = time;
		for (s in seeks)
			if (s.track == video && s.packet != null) target = exact ? s.time : s.packet.time;
		audioFrom = exact || video == null ? time : target;
		ringTime = audioFrom;
		clock.seek(exact ? time : target);
		if (out != null && sounding) out.start();
		if (audio == null) return 1e300;
		var lossless = audio.codec == Flac || audio.codec == Alac || audio.codec == Pcm;
		var pre = Math.max(audio.preroll, lossless ? 0 : 0.1);
		return pre > 0 ? audioFrom - pre : 1e300;
	}

	// (stepping on: the next frame after the one shown, once it is decoded;
	// false: none yet)
	function stepped():Bool {
		collect();
		var settled = drained() ? frames.length : frames.length - REORDER;
		var after = shown == null ? -1e300 : shown.time, i = 0;
		while (i < settled && frames[i].time <= after + EPS) i++;
		if (i >= settled) {
			if (!drained()) return false;
			stepping = 0;
			return true;
		}
		retire(shown);
		shown = frames[i];
		for (k in 0...i) frames[k].release();
		frames.splice(0, i + 1);
		clock.seek(shown.time);
		stepping--;
		if (onFrame != null) onFrame();
		return true;
	}

	// (every frame decoded and out: the stream's end, its decoder flushed and given all)
	function drained():Bool
		return eof && flushed && (vdec == null || vdec.pending == 0);

	// (an audio decoder that failed (WebKit's Opus, said to decode): the
	// video goes on without it, on the monotonic clock)
	function deaf(e:MediaError) {
		if (video == null) throw e;
		if (out != null) out.close();
		out = null;
		if (adec != null) adec.close();
		adec = null;
		audio = null;
		if (ring != null) ring.clear();
		clock.audio(0, 0);
	}

	// (whether a decoder wants a packet; at the end the video's held frames put out)
	function wants():Bool {
		collect();
		var v = vdec, a = adec, r = ring;
		// (what a decoder that decodes later gave since)
		if (a != null && r != null) try while (r.room() > 16384) {
			var n = a.decode(null, null, pcm);
			if (a.decoded == null) break;
			hear(a, r, n);
		} catch (e:MediaError) {
			deaf(e);
			a = null;
		}
		if (eof) {
			if (!flushed) {
				if (v != null) v.flush();
				if (a != null && r != null) tail(a, r, a.flush(pcm));
				flushed = true;
			}
			return false;
		}
		// (a decoder that holds frames back, WebKit's and Firefox's: fed on until one settles)
		var wantV = v != null && (frames.length + v.pending < AHEAD || stepping > 0 || frames.length <= REORDER && v.pending < HELD);
		var wantA = a != null && r != null && r.room() > 16384 && (r.available() / a.rate < AUDIO_AHEAD || !playing && v == null);
		return wantV || wantA;
	}

	// (a packet to its decoder: a frame before the target decoded, not shown;
	// audio's frames from the time heard first into the ring)
	function feed(p:Packet, bytes:haxe.io.Bytes) {
		var v = vdec, a = adec, r = ring;
		if (p.track == video && v != null) v.decode(p, bytes, p.time >= target - EPS);
		else if (p.track == audio && a != null && r != null) try hear(a, r, a.decode(p, bytes, pcm)) catch (e:MediaError) deaf(e);
	}

	// (a packet's n decoded frames into the ring from the time heard first:
	// the decoder's `decoded`, a packet before p where it decodes later)
	function hear(a:AudioDecoder, r:AudioRing, n:Int) {
		var q = a.decoded;
		if (q == null) return;
		var k = keep(q, n, a.rate, audioFrom, end(audio));
		// (the ring's first frame: its time)
		if (k.count > 0 && r.written == 0) ringTime = k.time;
		r.write(pcm, k.first, k.count);
	}

	// (the stream's end: the n frames a decoder held after the last packet's, up to the track's end)
	function tail(a:AudioDecoder, r:AudioRing, n:Int) {
		var e = end(audio);
		if (e > 0) n = Std.int(Math.max(0, Math.min(n, Math.round((e - ringTime) * a.rate) - r.written)));
		r.write(pcm, 0, n);
	}

	// what of a packet's n decoded frames plays: from the time `from`, to
	// the track's end (its duration, 0: none). The first frame's time is
	// the packet's pts, but a packet that decoded to fewer frames than it
	// lasts lost them at its start (Apple's Opus decoder's first, 120 of
	// 960), so its end is where they meet
	static function keep(p:Packet, n:Int, rate:Int, from:Float, end:Float):{first:Int, count:Int, time:Float} {
		var d = p.duration / p.track.timescale, at = p.time, delay = p.track.delay;
		// (Matroska's times are whole milliseconds: the first packet's -7 ms is CodecDelay's -6.5)
		if (delay > 0 && at < -delay && at > -delay - 1e-3) at = -delay;
		var t0 = n > 0 && d > 0 && n < Math.round(d * rate) ? at + d - n / rate : at;
		var first = 0, count = n;
		while (first < n && t0 + first / rate < from - EPS) first++;
		count = n - first;
		if (end > 0) while (count > 0 && t0 + (first + count - 1) / rate >= end - EPS) count--;
		return {first: first, count: count, time: t0 + first / rate};
	}

	// a track's end: its duration, less Matroska's CodecDelay, which the
	// pts are and its duration is not; 0, none
	static function end(t:MediaTrack):Float
		return t.duration > 0 ? t.duration - t.delay : 0;

	public function close() {
		if (closed) return;
		closed = true;
		#if (hxmc.target == "wasm32-wasi")
		if (element != null) element.close();
		#end
		if (out != null) out.close();
		if (shown != null) shown.release();
		for (f in retired) f.release();
		retired.resize(0);
		for (f in frames) f.release();
		frames.resize(0);
		if (vdec != null) vdec.close();
		if (adec != null) adec.close();
		if (media != null) media.close() else source.close();
		if (ring != null) ring.free();
		pcm.free();
	}
}
