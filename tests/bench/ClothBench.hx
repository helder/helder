import Cloth;
import haxe.Timer;
import helder.gfx.shader.ShaderMath.*;
import helder.parallel.On;
import helder.parallel.Parallel;

// examples/cloth's step (`bun run test bench cloth`): one Integrate and 16
// Jacobi iterations over a sheet of N points, µs a step, the least of its
// runs (a run: enough steps for 2 ms), as scalar, simd, jobs and gpu (the
// points staying there; one read back after a run, the wait for it).
// CLOTH_SIDES="32 64" narrows a run.
class ClothBench {
	static final SIDES = [32, 64, 128, 256, 512];
	static final FORMS = [Scalar, Simd, Jobs, Gpu];

	static function main() {
		var device = try helder.gfx.Device.create(helder.os.Surface.headless(64, 64)) catch (_:Dynamic) null;
		if (device != null && device.has(Compute)) Parallel.device = device;
		var forms = FORMS.filter(f -> f != Gpu || Parallel.device != null);
		Sys.println('cloth: ${helder.jobs.Spread.threads() + 1} threads, gpu ' + (Parallel.device == null ? "none" : Std.string(device.backend)));
		var given = Sys.getEnv("CLOTH_SIDES");
		var sides = given == null ? SIDES : [for (x in given.split(" ")) if (x != "") Std.parseInt(x)];
		var rows = [];
		for (side in sides) {
			var row = [Std.string(side * side)];
			for (f in forms) {
				var us = f == Scalar && side > 128 ? -1 : measure(side, f);
				Sys.println('cloth ${side * side} ${f.toString()} ${round(us)}');
				row.push(us < 0 ? "" : round(us));
			}
			rows.push(row);
		}
		Sys.println("");
		Sys.println("| points | " + [for (f in forms) f.toString()].join(" | ") + " |");
		Sys.println("|" + [for (_ in 0...forms.length + 1) "---:"].join("|") + "|");
		for (r in rows)
			Sys.println("| " + r.join(" | ") + " |");
	}

	static function steps(c:Cloth, k:Int) {
		for (_ in 0...k)
			c.step();
		// (the GPU's steps waited for)
		if (c.on == Gpu) c.points[0];
	}

	static function measure(side:Int, on:On):Float {
		var c = new Cloth(side, side, 2.0 / side, 1, 8);
		c.wind = vec4(0.5, 0, 1, 0);
		c.on = on;
		var t0 = Timer.stamp();
		steps(c, 1);
		var one = Timer.stamp() - t0;
		var k = Std.int(Math.max(1, Math.min(1000, 0.002 / Math.max(one, 1e-7))));
		var best = 1e30;
		for (_ in 0...(one > 0.05 ? 3 : 8)) {
			var t = Timer.stamp();
			steps(c, k);
			best = Math.min(best, (Timer.stamp() - t) / k * 1e6);
		}
		c.dispose();
		return best;
	}

	static function round(us:Float):String
		return us >= 100 ? Std.string(Math.round(us)) : Std.string(Math.round(us * 10) / 10);
}
