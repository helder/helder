import haxe.io.Bytes;
import helder.gfx.*;
import helder.os.*;

// tests/3d's scenes timed, whatever back end the build has (the GPU's, or
// the CPU's: -D helder.soft): the first frame (the scene made, drawn and
// read back: shaders compiled, textures uploaded) and the least of RUNS
// frames after it, each drawn and read back, in ms, a line a scene:
//   FrameBench [WxH (256x192)] [scene ...]
class FrameBench {
	static final RUNS = Std.parseInt(Sys.getEnv("FRAMES") ?? "10");

	static function main() {
		var args = Sys.args(), w = 256, h = 192;
		if (args.length > 0 && args[0].indexOf("x") > 0) {
			var s = args.shift().split("x");
			w = Std.parseInt(s[0]);
			h = Std.parseInt(s[1]);
		}
		var names = args.length > 0 ? args : Scenes.NAMES;
		var px = Bytes.alloc(w * h * 4), firsts = 0.0, steadies = 0.0;
		for (name in names) {
			var t0 = haxe.Timer.stamp();
			var device = Device.create(Surface.headless(w, h));
			var draw = Scenes.make(name, device);
			if (!Scenes.ready()) {
				Sys.println('$name: not ready');
				continue;
			}
			function frame() {
				var enc = device.beginFrame();
				draw(enc);
				device.readPixels(px);
				device.endFrame();
			}
			frame();
			var first = haxe.Timer.stamp() - t0, best = 1e9;
			for (_ in 0...RUNS) {
				var t = haxe.Timer.stamp();
				frame();
				best = Math.min(best, haxe.Timer.stamp() - t);
			}
			device.dispose();
			firsts += first;
			steadies += best;
			Sys.println('$name ${w}x$h: ${ms(best)} ms (first ${ms(first)})');
		}
		Sys.println('all ${names.length} ${w}x$h: ${ms(steadies)} ms (first ${ms(firsts)})');
	}

	static function ms(s:Float):Float
		return Math.round(s * 10000) / 10;
}
