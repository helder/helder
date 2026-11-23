import haxe.Timer;
import helder.gfx.*;
import helder.os.*;

// examples/orbits in a window, its frames timed: on the render thread
// (Device's thread option; HELDER_RENDER_THREAD=0: synchronous), settled
// before the next events as helder.ui's loop does; with --work ms, that
// much of the program's own work after each frame. Prints the frame time and
// the time from a frame's start to its present returning (not a lane: the
// render thread's numbers, gfx/README.md):
//   haxe -cp src -cp examples/orbits -cp tests/3d -main OrbitsTime --custom-target hxmc=bin/OrbitsTime
//   OrbitsTime [frames] [--work ms]
class OrbitsTime {
	static function main() {
		var a = Sys.args(), k = a.indexOf("--work");
		var n = a.length > 0 && k != 0 ? Std.parseInt(a[0]) ?? 300 : 300, work = k >= 0 ? Std.parseFloat(a[k + 1]) / 1000 : 0.0;
		var window = new Window("OrbitsTime", 640, 480);
		var device = Device.create(window.surface, {thread: true});
		var orbits = new Orbits(device);
		var starts:Array<Float> = [], presents:Array<Float> = [];
		@:privateAccess device.replay.onEndFrame = () -> presents.push(Timer.stamp());
		App.run(() -> {
			var t0 = Timer.stamp();
			orbits.at(starts.length / 60);
			var enc = device.beginFrame();
			if (enc == null) return;
			orbits.draw(enc);
			device.endFrame();
			starts.push(t0);
			var until = Timer.stamp() + work;
			while (Timer.stamp() < until) {}
			device.settle();
			if (starts.length == n) {
				var gaps = [for (i in 1...n) starts[i] - starts[i - 1]], latency = [for (i in 0...n) presents[i] - starts[i]];
				Sys.println('OrbitsTime: ${device.threaded ? "render thread" : "synchronous"}: frame ${stats(gaps)}, start to present ${stats(latency)}');
				device.dispose();
				Sys.exit(0);
			}
		}, e -> {});
	}

	static function stats(a:Array<Float>):String {
		var s = a.slice(Std.int(a.length / 10));
		s.sort(Reflect.compare);
		var sum = 0.0;
		for (v in s)
			sum += v;
		inline function ms(v:Float) return Math.round(v * 10000) / 10;
		return 'mean ${ms(sum / s.length)} ms, p50 ${ms(s[Std.int(s.length / 2)])}, p95 ${ms(s[Std.int(s.length * 0.95)])}';
	}
}
