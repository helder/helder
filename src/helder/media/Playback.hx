package helder.media;

import haxe.atomic.AtomicInt;

// The clock a player keeps: where in the media it is (time, seconds),
// playing or paused, its rate, seeks. Its master is the audio output once
// one is attached (audio(...)): the frames its callback gave
// (played(frames), on the audio thread) less what the system holds
// (latency), so pictures follow the sound heard; else a monotonic clock.
// The video side asks which of its decoded frames is due (due).
//
//   var clock = new Playback();
//   var out = Audio.open({}, (buffer, frames) -> {
//     fill(buffer, frames);            // the media's samples from clock's time on
//     clock.played(frames);
//   });
//   clock.audio(out.sampleRate, out.latency);
//   clock.play();
//   var i = clock.due(frameTimes);    // each frame: the latest decoded one due now
class Playback {
	public var playing(default, null) = false;
	public var rate(default, null) = 1.0;

	final now:() -> Float;
	// (the media's time at the anchor, the base clock's time there)
	var anchor = 0.0;
	var since = 0.0;
	// (the latest time told: it never goes back while playing, audio's callbacks jittering)
	var told = Math.NEGATIVE_INFINITY;
	// (the audio master: frames a second, the output's latency; what the
	// audio thread publishes, a sequence lock around fed, before and stamp)
	var sampleRate = 0;
	var latency = 0.0;
	final version = new AtomicInt(0);
	var fed = 0.0;
	var before = 0.0;
	var stamp = -1.0;

	// now: seconds of a monotonic clock (haxe.Timer.stamp; a test's own)
	public function new(?now:() -> Float)
		this.now = now ?? haxe.Timer.stamp;

	// the media's time now, seconds
	public var time(get, never):Float;

	function get_time():Float {
		if (!playing) return anchor;
		var t = anchor + (base() - since) * rate;
		// (audio: the time a play or seek started until the output plays it)
		if (t < anchor) t = anchor;
		if (t < told) t = told;
		return told = t;
	}

	public function play() {
		if (playing) return;
		told = Math.NEGATIVE_INFINITY;
		since = start();
		playing = true;
	}

	public function pause() {
		if (!playing) return;
		anchor = time;
		told = Math.NEGATIVE_INFINITY;
		playing = false;
	}

	public function seek(time:Float) {
		told = Math.NEGATIVE_INFINITY;
		anchor = time;
		since = start();
	}

	public function speed(rate:Float) {
		if (rate <= 0) throw new MediaError("rate must be positive");
		told = Math.NEGATIVE_INFINITY;
		anchor = time;
		since = start();
		this.rate = rate;
	}

	// the audio output this clock follows from now on (0: none, the monotonic clock again)
	public function audio(sampleRate:Int, latency:Float) {
		told = Math.NEGATIVE_INFINITY;
		anchor = time;
		this.sampleRate = sampleRate;
		this.latency = latency;
		since = start();
	}

	// the audio callback gave the output frames more (on the audio thread)
	public function played(frames:Int) {
		version.add(1);
		before = fed;
		fed += frames;
		stamp = now();
		version.add(1);
	}

	// the index of the frame to show: the last of times (seconds, ascending)
	// at or before the time; -1 when none is due yet
	public function due(times:Array<Float>):Int {
		var t = time, i = -1;
		for (k in 0...times.length) if (times[k] <= t) i = k else break;
		return i;
	}

	// seconds until a frame at that media time is due (0: now or past)
	public function wait(at:Float):Float {
		if (!playing) return Math.POSITIVE_INFINITY;
		var d = (at - time) / rate;
		return d > 0 ? d : 0;
	}

	// (the base clock where what follows starts: with audio, the time the
	// next frame the callback gives is heard; else now)
	function start():Float {
		if (sampleRate <= 0) return now();
		var s = sample();
		return s.fed / sampleRate;
	}

	// (the base clock: the audio heard, seconds of frames given; between
	// callbacks it runs on the monotonic clock, never past what was given)
	function base():Float {
		if (sampleRate <= 0) return now();
		var s = sample();
		if (s.stamp < 0) return 0;
		var heard = s.before / sampleRate + (now() - s.stamp - latency);
		var top = s.fed / sampleRate;
		return heard > top ? top : heard;
	}

	function sample():{fed:Float, before:Float, stamp:Float} {
		while (true) {
			var v = version.load();
			if (v & 1 == 1) continue;
			var f = fed, b = before, s = stamp;
			if (version.load() == v) return {fed: f, before: b, stamp: s};
		}
	}
}
