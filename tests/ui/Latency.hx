import haxe.Timer;
import helder.os.*;
import helder.ui.*;
import helder.ui.draw.*;

// The time from a scroll's input to the present of the first frame that
// shows it (AsyncScrollWindow --latency n [--work ms]): a wheel's event put
// where the system's come in every 250 ms (Inject), the frames' presents
// and offsets recorded (the program's after settle, the compositor's after
// its present), with the program working ms after each of its frames.
// Run it with HELDER_ASYNC_SCROLL=0 for the synchronous path; on a display
// kept awake (caffeinate -d on macOS), its presents waiting for the vsync.
class Latency {
	public static function run(w:UiWindow, list:Node, n:Int, work:Float) {
		if (!Inject.supported) {
			Sys.println("Latency: no input to inject here");
			w.close();
			return;
		}
		var lock = new sys.thread.Mutex(), sent:Array<Float> = [], before:Array<Float> = [], presents:Array<Float> = [], offsets:Array<Float> = [];
		var c = w.compositor;
		if (c != null) c.onFrame = t -> {
			var o = c.offsets(list);
			lock.acquire();
			presents.push(t);
			offsets.push(o == null ? -1 : o.y);
			lock.release();
		};
		var started = false, inject:Null<Inject> = null, step = 0;
		App.run(() -> {
			step++;
			if (step == 20 && !started) {
				started = true;
				inject = Inject.start(w.window, n * 250, 0.25, t -> {
					lock.acquire();
					sent.push(t);
					lock.release();
				});
			}
			if (!w.needsFrame() && c != null) c.rest();
			if (w.needsFrame()) {
				w.frame();
				w.device.settle();
				lock.acquire();
				presents.push(Timer.stamp());
				offsets.push(list.scrollY);
				lock.release();
			}
			if (work > 0) {
				var until = Timer.stamp() + work;
				while (Timer.stamp() < until) {}
			}
			if (inject != null && inject.sent >= n && Timer.stamp() > sent[sent.length - 1] + 0.3) {
				inject.join();
				lock.acquire();
				// (each event's first present past it with the offset past the one shown when it was sent)
				var order = [for (i in 0...presents.length) i];
				order.sort((a, b) -> Reflect.compare(presents[a], presents[b]));
				var lat = [];
				// (the first ten: the window settling)
				for (s in sent.slice(10)) {
					var shown = -1.0;
					for (i in order) if (presents[i] <= s) shown = Math.max(shown, offsets[i]);
					for (i in order)
						if (presents[i] > s && offsets[i] > shown) {
							lat.push(presents[i] - s);
							break;
						}
				}
				lock.release();
				if (Sys.getEnv("LATENCY_ALL") != null) Sys.println([for (v in lat) Math.round(v * 1000)]);
				lat.sort(Reflect.compare);
				inline function ms(v:Float) return Math.round(v * 10000) / 10;
				var sum = 0.0;
				for (v in lat) sum += v;
				Sys.println('Latency: ${c == null ? "synchronous" : "compositor"}, the program ${work > 0 ? "busy " + Math.round(work * 1000) + " ms a frame" : "idle"}: input to present mean ${ms(sum / lat.length)} ms, p50 ${ms(lat[Std.int(lat.length / 2)])}, p95 ${ms(lat[Std.int(lat.length * 0.95)])} (${lat.length} of ${sent.length - 10})');
				w.close();
				Sys.exit(0);
			}
		}, e -> w.handle(e));
	}
}
