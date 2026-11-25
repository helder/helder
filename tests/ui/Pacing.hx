import haxe.Timer;
import helder.os.*;
import helder.ui.*;
import helder.ui.draw.*;

// A layer's transition in a real window while the program is busy
// (AsyncScrollWindow --anim): a box turning, moving and fading over the
// list; the program blocked for 300 ms while it runs: the compositor's
// frames keep coming at the display's pace, from the animation alone (no
// input meanwhile); then a box that never moved, its transition declared
// and the program blocked right after the frame declaring it: animated by
// the compositor from the first vsync the program misses. With --pace s [--work ms]: the frames' pacing over s
// seconds of an animation, the program working ms after each of its
// frames (HELDER_ASYNC_SCROLL=0: the synchronous path's); on a display
// kept awake (caffeinate -d on macOS), its presents waiting for the vsync.
class Pacing {
	public static function run(w:helder.ui.UiWindow, pace:Float, work:Float):Int {
		var spin = new Node();
		spin.style.set({position: Absolute, left: 120, top: 90, width: 90, height: 60, radius: 10, background: 0xFF2A7AE2});
		spin.style.transform = Transform.parse("translate(0px, 0px) rotate(0deg)");
		var length = pace > 0 ? pace + 1 : 1.2;
		spin.style.transition = Transition.parse('transform ${length}s linear, opacity ${length}s linear');
		w.root.append(spin);
		// (one that never moved: no layer of its own until it is declared)
		var tap = new Node();
		tap.style.set({position: Absolute, left: 250, top: 40, width: 60, height: 40, radius: 8, background: 0xFFE2462A});
		tap.style.transform = Transform.parse("translate(0px, 0px)");
		tap.style.transition = Transition.parse("transform 1s linear, opacity 1s linear");
		w.root.append(tap);
		var c = w.compositor, lock = new sys.thread.Mutex(), mine:Array<Float> = [], theirs:Array<Float> = [];
		if (c == null && pace <= 0) {
			Sys.println("Pacing: no compositor here: skipped");
			w.close();
			return 0;
		}
		if (c != null) c.onFrame = t -> {
			lock.acquire();
			mine.push(t);
			lock.release();
		};
		var step = 0, from = 0.0, to = 0.0, failed = 0, tapped = -1;
		// (Wayland's system layers wait for each commit's frame callback, which a
		// headless weston answers every other refresh: 30 frames a second)
		var slow = Sys.getEnv("WAYLAND_DISPLAY") != null && c != null && c.layers != null;
		function check(what:String, ok:Bool, detail:String) {
			if (!ok) failed++;
			Sys.println('Pacing: ${ok ? "ok" : "FAIL"}: $what ($detail)');
		}
		// (the compositor's frames between from and to, their median gap)
		function blocked(what:String) {
			lock.acquire();
			var during = [for (t in mine) if (t > from && t <= to) t];
			lock.release();
			var gaps = [for (i in 1...during.length) during[i] - during[i - 1]];
			gaps.sort(Reflect.compare);
			var median = gaps.length > 0 ? gaps[Std.int(gaps.length / 2)] : 1.0;
			check('the animation\'s frames presented while the program was blocked for 300 ms$what', during.length >= (slow ? 6 : 10), during.length + " frames");
			check('at the display\'s pace$what', gaps.length > 0 && median < (slow ? 0.05 : 0.03), "median gap " + Math.round(median * 10000) / 10 + " ms");
		}
		App.run(() -> {
			step++;
			if (step == 10) {
				spin.style.transform = Transform.parse("translate(140px, 30px) rotate(270deg)");
				spin.style.opacity = 0.3;
			}
			if (pace <= 0 && step == 16) {
				// (the program busy while it runs)
				from = Timer.stamp();
				Sys.sleep(0.3);
				to = Timer.stamp();
			}
			if (pace > 0 && step == 16) from = Timer.stamp();
			// (once the first is over: nothing else moving, the compositor's frames this one's alone)
			if (pace <= 0 && step > 24 && tapped < 0 && !Clock.active && !c.moving() && c.due() < 0) {
				tapped = step;
				tap.style.transform = Transform.parse("translate(-120px, 150px)");
				tap.style.opacity = 0.5;
			}
			if (w.needsFrame()) {
				w.frame();
				w.device.settle();
				lock.acquire();
				theirs.push(Timer.stamp());
				lock.release();
			}
			if (pace <= 0 && step == tapped) {
				// (blocked right after the frame declaring it: that frame hands it over running)
				from = Timer.stamp();
				Sys.sleep(0.3);
				to = Timer.stamp();
			}
			if (pace > 0 && work > 0 && step > 10) {
				var until = Timer.stamp() + work;
				while (Timer.stamp() < until) {}
			}
			if (pace <= 0 && step == 24) blocked("");
			if (pace <= 0 && tapped < 0 && step > 24 && Timer.stamp() - to > 10) {
				check("at rest after the first animation", false, "still moving 10 s on");
				tapped = step - 8;
			}
			if (pace <= 0 && tapped > 0 && step == tapped + 8) {
				blocked(", declared in the frame before");
				w.close();
				Sys.println("Pacing: " + (failed == 0 ? "ok" : '$failed FAILED'));
				Sys.exit(failed == 0 ? 0 : 1);
			}
			if (pace > 0 && from > 0 && Timer.stamp() > from + pace) {
				to = Timer.stamp();
				lock.acquire();
				var all = [for (t in mine.concat(theirs)) if (t > from && t <= to) t];
				lock.release();
				all.sort(Reflect.compare);
				var gaps = [for (i in 1...all.length) all[i] - all[i - 1]];
				var sorted = gaps.copy();
				sorted.sort(Reflect.compare);
				inline function ms(v:Float) return Math.round(v * 10000) / 10;
				var sum = 0.0, late = 0;
				for (g in gaps) {
					sum += g;
					if (g > 0.025) late++;
				}
				Sys.println('Pacing: ${c == null ? "synchronous" : "compositor"}, the program ${work > 0 ? "busy " + Math.round(work * 1000) + " ms a frame" : "idle"}: '
					+ '${all.length} frames in ${ms(to - from)} ms (${Math.round(all.length / (to - from))} a second), gap mean ${ms(sum / gaps.length)} ms, '
					+ 'p50 ${ms(sorted[Std.int(sorted.length / 2)])}, p95 ${ms(sorted[Std.int(sorted.length * 0.95)])}, max ${ms(sorted[sorted.length - 1])}, '
					+ '$late over 25 ms' + (c == null ? "" : ' (${mine.length} of them the compositor\'s)'));
				w.close();
				Sys.exit(0);
			}
		}, e -> w.handle(e));
		return failed;
	}
}
