package helder.media;

import helder.test.Test;

// The playback clock on a clock of the test's own: monotonic, then
// mastered by synthetic audio callbacks (the frames given, the output's
// latency): play, pause, seek, rate, a stalled output, and which of a
// run of frames is due as the callbacks come.
function tests() {
	describe("Playback", () -> {
		var now = 0.0;
		var clock = new Playback(() -> now);
		beforeEach(() -> {
			now = 10;
			clock = new Playback(() -> now);
		});
		test("monotonic: play, pause, seek, rate", () -> {
			equals(clock.time, 0.0);
			clock.play();
			now = 10.5;
			approx(clock.time, 0.5);
			clock.pause();
			now = 12;
			approx(clock.time, 0.5);
			clock.seek(3);
			equals(clock.time, 3.0);
			clock.play();
			clock.speed(2);
			now = 13;
			approx(clock.time, 5);
			approx(clock.wait(6), 0.5);
			throws(() -> clock.speed(0));
		});
		test("audio: the frames heard, latency after the callback that gave them", () -> {
			clock.audio(1000, 0.1);
			clock.play();
			now = 11;
			clock.played(100);
			now = 11.05;
			equals(clock.time, 0.0);
			now = 11.15;
			approx(clock.time, 0.05);
			now = 11.1;
			clock.played(100);
			now = 11.2;
			approx(clock.time, 0.1);
			// (no callback since: never past what the output was given)
			now = 13;
			approx(clock.time, 0.2);
		});
		test("audio: play starts with the next frames given, a seek too", () -> {
			clock.audio(1000, 0);
			now = 11;
			clock.played(500);
			clock.play();
			now = 11.4;
			equals(clock.time, 0.0);
			clock.played(200);
			now = 11.55;
			approx(clock.time, 0.15);
			clock.seek(7);
			now = 11.7;
			equals(clock.time, 7.0);
			clock.played(100);
			now = 11.75;
			approx(clock.time, 7.05);
		});
		test("audio at twice the rate: the media's time twice the frames'", () -> {
			clock.audio(1000, 0);
			clock.speed(2);
			clock.play();
			now = 11;
			clock.played(100);
			now = 11.05;
			approx(clock.time, 0.1);
		});
		test("the frame due as synthetic callbacks come (30 fps, 48 kHz, 512 frames)", () -> {
			var frames = [for (i in 0...60) i / 30];
			clock.audio(48000, 0.02);
			clock.play();
			var shown = [], last = -1;
			for (k in 0...200) {
				now = 10 + k * 512 / 48000;
				clock.played(512);
				var i = clock.due(frames);
				if (i != last) shown.push(i);
				last = i;
			}
			// (every frame once, in order, none skipped at this pace)
			equals(shown.slice(0, 4), [0, 1, 2, 3]);
			equals(shown.length, 60);
			// (time never runs back)
			var t = clock.time;
			now += 0.001;
			assert(clock.time >= t);
		});
		test("an audio callback allocates nothing", () -> {
			clock.audio(48000, 0);
			clock.played(512);
			var before = hxmc.GcStats.bytesAllocated();
			for (_ in 0...100) clock.played(512);
			equals(hxmc.GcStats.bytesAllocated() - before, 0.0);
		});
	});
}
