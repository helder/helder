package helder.scene.render;

import helder.math.Vec4;
import helder.parallel.On;
import helder.test.Test;

// helder.scene's simulated particles stepped on the CPU's forms (no
// device: the step is helder.parallel's each over the ring; drawing is the
// 3d lanes'): births taken into the ring in order, falls, a floor's bounce,
// a sphere's push, deaths, and Simd and Jobs the same bits.
function tests() {
	describe("Particles", () -> {
		test("born at the next step, falling, bounced off the floor", () -> {
			var ps = new Particles(16, 4);
			ps.floor = 0;
			ps.bounce = 0.5;
			ps.emit(0, 1, 0, 1, 0, 0, 1, 1, 1, 1, 0.1, 0.1, 10);
			equals(ps.pending, 1);
			ps.step(0.1);
			equals(ps.pending, 0);
			var q = ps.items[0];
			assert(q.start.y < 1 && q.start.x > 0, 'moved: ${q.start.x}, ${q.start.y}');
			for (_ in 0...20)
				ps.step(0.05);
			q = ps.items[0];
			assert(q.start.y >= 0, 'above the floor: ${q.start.y}');
			ps.dispose();
		});
		test("pushed out of a sphere, dead after its life, the ring's oldest written over", () -> {
			var ps = new Particles(4, 4);
			ps.gravity = new helder.math.Vec3(0, 0, 0);
			ps.spheres[0] = new Vec4(0, 0, 0, 1);
			ps.emit(0.5, 0, 0, -1, 0, 0, 1, 1, 1, 1, 0.1, 0.1, 0.5);
			ps.step(0.1);
			var q = ps.items[0];
			assert(Math.abs(Math.sqrt(q.start.x * q.start.x + q.start.y * q.start.y + q.start.z * q.start.z) - 1) < 1e-5, 'on the sphere: ${q.start.x}');
			assert(q.velocity.x >= 0, 'its fall into it bounced: ${q.velocity.x}');
			for (_ in 0...10)
				ps.step(0.1);
			var x = ps.items[0].start.x;
			ps.step(0.1);
			equals(ps.items[0].start.x, x);
			for (k in 0...6)
				ps.emit(k, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0.1, 0.1, 5);
			equals(ps.dropped, 2);
			ps.step(0.1);
			equals([for (k in 0...4) ps.items[k].start.x], [3.0, 0, 1, 2]);
			ps.dispose();
		});
		test("Simd and Jobs: the same bits", () -> {
			function run(on:On) {
				var ps = new Particles(5000, 1000);
				ps.on = on;
				ps.floor = 0;
				ps.drag = 0.3;
				ps.spheres[0] = new Vec4(0, 1, 0, 0.75);
				for (s in 0...30) {
					for (k in 0...200)
						ps.emit(Math.sin(k) * 0.5, 2, Math.cos(k) * 0.5, Math.sin(k * 3), 1 + (k % 7) * 0.3, Math.cos(k * 5), 1, 1, 1, 1, 0.05, 0.01, 3);
					ps.step(1 / 60);
				}
				var out = [for (k in 0...ps.capacity) for (v in [ps.items[k].start, ps.items[k].velocity]) for (x in [v.x, v.y, v.z]) x];
				ps.dispose();
				return out;
			}
			var simd = run(Simd), jobs = run(Jobs);
			equals(jobs, simd);
		});
	});
}
