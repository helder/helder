import Cloth;
import helder.gfx.Device;
import helder.gfx.shader.ShaderMath.*;
import helder.os.Surface;
import helder.parallel.On;
import helder.parallel.Parallel;

// examples/cloth's simulation (gfx-compute; gfx-soft: the CPU back end):
// Simd and Jobs the same bits, Scalar near them, the pins kept, the cloth
// stretched little; and the GPU against Simd one step at a time from the
// same state (a step's difference bounded, never compounded: after many
// steps two float32 runs of a chaotic cloth part by more than any bound
// says). Exit code 3: no device with compute (the CPU's checks run first).
class ClothCheck {
	static var failures = 0;

	static function main() {
		cpu();
		var device = try Device.create(Surface.headless(64, 64)) catch (_:Dynamic) null;
		if (device == null || !device.has(Compute)) {
			Sys.println('ClothCheck: no device with compute stages');
			Sys.println(failures == 0 ? "ClothCheck: ok" : 'ClothCheck: $failures failed');
			Sys.exit(failures == 0 ? 3 : 1);
		}
		Parallel.device = device;
		gpu();
		Sys.println(failures == 0 ? "ClothCheck: ok" : 'ClothCheck: $failures failed');
		device.dispose();
		Sys.exit(failures == 0 ? 0 : 1);
	}

	static function check(what:String, ok:Bool, ?detail:String) {
		if (!ok) failures++;
		Sys.println('ClothCheck: $what: ' + (ok ? "ok" : "FAIL" + (detail == null ? "" : ' ($detail)')));
	}

	static function sheet(on:On):Cloth {
		var c = new Cloth(37, 29, 0.05, 1, 6);
		c.wind = vec4(0.8, 0, 1.5, 0);
		c.on = on;
		return c;
	}

	// the largest difference of two cloths' places
	static function apart(a:Cloth, b:Cloth):Float {
		var worst = 0.0;
		for (i in 0...a.points.length) {
			var p = a.points[i].pos, q = b.points[i].pos;
			worst = Math.max(worst, Math.max(Math.abs(p.x - q.x), Math.max(Math.abs(p.y - q.y), Math.abs(p.z - q.z))));
		}
		return worst;
	}

	static function cpu() {
		var simd = sheet(Simd), jobs = sheet(Jobs), scalar = sheet(Scalar);
		var pinned = simd.points[6].pos;
		for (_ in 0...60) {
			simd.step();
			jobs.step();
		}
		check("simd and jobs: the same bits", apart(simd, jobs) == 0);
		// (Scalar in doubles: a step from the same state)
		for (i in 0...simd.points.length)
			scalar.points[i] = simd.points[i];
		var next = sheet(Simd);
		for (i in 0...simd.points.length)
			next.points[i] = simd.points[i];
		scalar.step();
		next.step();
		var d = apart(scalar, next);
		check("scalar: a step within 1e-5", d <= 1e-5, '$d');
		var p = simd.points[6].pos;
		check("the pins kept", p.x == pinned.x && p.y == pinned.y && p.z == pinned.z);
		for (_ in 0...240)
			simd.step();
		var worst = 0.0;
		for (r in 0...simd.height)
			for (c in 0...simd.width - 1) {
				var a = simd.points[r * simd.width + c].pos.xyz, b = simd.points[r * simd.width + c + 1].pos.xyz;
				worst = Math.max(worst, Math.abs(distance(a, b) - simd.spacing) / simd.spacing);
			}
		check("300 steps: stretched 25% at most (Jacobi's 16 iterations)", worst <= 0.25, '$worst');
		var low = 1e30;
		for (i in 0...simd.points.length)
			low = Math.min(low, simd.points[i].pos.y);
		check("it fell", low < 0.5, '$low');
		for (c in [simd, jobs, scalar, next])
			c.dispose();
	}

	// one step on the GPU and on the CPU from the same state, along a CPU run
	static function gpu() {
		var run = sheet(Simd), g = sheet(Gpu), c = sheet(Simd);
		var worst = 0.0;
		for (k in 0...200) {
			if (k % 20 == 0) {
				for (i in 0...run.points.length) {
					g.points[i] = run.points[i];
					c.points[i] = run.points[i];
				}
				g.step();
				c.step();
				worst = Math.max(worst, apart(g, c));
			}
			run.step();
		}
		check("gpu: a step within 1e-4 of simd's (10 states)", worst <= 1e-4, '$worst');
		// (Auto, once drawn: the steps on the GPU)
		var drawn = sheet(Auto);
		drawn.buffer(Parallel.device);
		drawn.step();
		check("Auto, drawn: on the GPU", drawn.points.data().byGpu);
		for (x in [run, g, c, drawn])
			x.dispose();
	}
}
