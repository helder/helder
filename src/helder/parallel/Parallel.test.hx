package helder.parallel;

import helder.math.Mat4;
import helder.gfx.shader.ShaderMath.*;
import helder.math.Vec2;
import helder.math.Vec4;
import helder.parallel.Parallel;
import helder.test.Gen;
import helder.test.Test;

// helder.parallel's forms against each other (`bun run helder test
// src/helder/parallel`, natively and as wasm32-wasi): random counts, data
// and forms, Simd and Jobs the same bits whatever the threads, Scalar (in
// doubles) within float32's rounding, the reductions the same bits on any
// number of threads. The compile-time rules' rejections are the parallel
// lane's (tests/parallel/reject).
function tests() {
	describe("Items", () -> {
		test("zeros, set and read, bounds checked", () -> {
			var a = new Items<Float>(5);
			equals([for (i in 0...5) a[i]], [0.0, 0, 0, 0, 0]);
			a[2] = 1.5;
			equals(a[2], 1.5);
			equals(a.length, 5);
			throws(() -> a[5]);
			throws(() -> a[-1] = 1);
			a.dispose();
			equals(a.disposed, true);
			throws(() -> a[0]);
		});
		test("float32, as the GPU's storage", () -> {
			var a = new Items<Float>(1);
			a[0] = 0.1;
			equals(a[0], (haxe.io.FPHelper.i32ToFloat(haxe.io.FPHelper.floatToI32(0.1))));
		});
		test("structs, vectors and matrices at their std430 offsets", () -> {
			var ps = new Items<Particle>(3);
			ps[1] = {pos: vec4(1, 2, 3, 4), vel: vec4(5, 6, 7, 8)};
			var q = ps[1];
			equals([q.pos.x, q.pos.w, q.vel.x, q.vel.w], [1.0, 4, 5, 8]);
			var ms = new Items<Mat4>(2);
			ms[1] = mat4(2);
			equals(ms[1].c2.z, 2.0);
			var v = Items.of([vec2(1, 2), vec2(3, 4)]);
			equals(v[1].y, 4.0);
			var back = [];
			v.copyTo(back);
			equals(back.length, 2);
		});
	});

	describe("each", () -> {
		test("the forms against each other", () -> property(cases(), c -> {
			var a = data(c.n, c.seed), k = 0.37 + c.seed % 7;
			function run(on:On):Items<Float> {
				var out = new Items<Float>(c.n + 3);
				each(c.n, i -> out[i] = a[i] * k + Math.sin(a[i]) - Std.int(a[i]) % 3, on);
				return out;
			}
			var scalar = run(On.Scalar), simd = run(On.Simd), jobs = run(On.Jobs), picked = run(c.on);
			same(simd, jobs, "jobs");
			near(simd, scalar, "scalar");
			near(picked, scalar, "picked");
			// (the items past n untouched)
			for (x in [simd, jobs, scalar])
				equals([x[c.n], x[c.n + 1], x[c.n + 2]], [0.0, 0, 0]);
		}));
		test("ifs and loops on lanes, gathers, Ints", () -> property(cases(), c -> {
			var a = data(c.n, c.seed), n = c.n, flag = c.seed % 2 == 0;
			function run(on:On) {
				var out = new Items<Float>(n), ints = new Items<Int>(n);
				each(n, i -> {
					var s = 0.0;
					var j = 0;
					while (j < (i & 3)) {
						s += a[(i * 7 + j) % n];
						j++;
					}
					if (a[i] > 0 && flag) s = -s else if (a[i] < -50) s *= 2;
					out[i] = s;
					ints[i] = (i * 31) ^ Std.int(a[i]);
				}, on);
				return {out: out, ints: ints};
			}
			var simd = run(On.Simd), jobs = run(On.Jobs), scalar = run(On.Scalar);
			same(simd.out, jobs.out, "jobs");
			near(simd.out, scalar.out, "scalar");
			equals(list(simd.ints), list(scalar.ints));
			equals(list(jobs.ints), list(scalar.ints));
		}));
		test("struct items: a particle step", () -> property(cases(), c -> {
			function run(on:On) {
				var ps = particles(c.n, c.seed);
				var g = 9.8, dt = 1 / 120, drag = 0.999, bounce = 0.8;
				for (_ in 0...8)
					each(ps.length, i -> {
						var q = ps[i];
						var vel = q.vel.xyz * drag - vec3(0, g * dt, 0);
						var pos = q.pos.xyz + vel * dt;
						if (pos.y < 0) {
							pos = vec3(pos.x, -pos.y, pos.z);
							vel = vec3(vel.x, -vel.y * bounce, vel.z);
						}
						ps[i] = {pos: vec4(pos, q.pos.w + dt), vel: vec4(vel, q.vel.w)};
					}, on);
				return ps;
			}
			var simd = run(On.Simd), jobs = run(On.Jobs), scalar = run(On.Scalar);
			equals(flat(simd), flat(jobs));
			nearList(flat(simd), flat(scalar), "scalar");
		}));
		test("captured vectors, matrices and Bools", () -> {
			var a = data(37, 3), out = new Items<Vec4>(37), m = mat4(2), v = vec4(1, 2, 3, 4), on = true;
			each(37, i -> out[i] = on ? m * (v * a[i]) : v);
			equals(out[5].y, f32(2 * (2 * a[5])));
		});
		test("map: out[i], each i of its length", () -> property(cases(), c -> {
			var a = data(c.n, c.seed);
			var x = new Items<Float>(c.n), y = new Items<Float>(c.n);
			map(x, i -> a[i] * 2 + 1, c.on);
			map(y, i -> {
				if (a[i] > 0) return a[i];
				return -a[i];
			}, c.on);
			for (i in 0...c.n) {
				equals(x[i], f32(a[i] * 2 + 1));
				equals(y[i], Math.abs(a[i]));
			}
		}));
		test("an Items shorter than n, one disposed, a written one passed twice: thrown", () -> {
			var a = new Items<Float>(4), b = new Items<Float>(4);
			throws(() -> each(5, i -> a[i] = 1));
			b.dispose();
			throws(() -> each(4, i -> b[i] = 1));
			var c = a;
			throws(() -> each(4, i -> a[i] = c[i] + 1));
		});
		test("On.Gpu: not yet", () -> {
			var a = new Items<Float>(4);
			throws(() -> each(4, i -> a[i] = 1, Gpu));
		});
	});

	describe("reductions", () -> {
		test("sum, min, max: the forms, any threads, the same", () -> property(cases(), c -> {
			var a = data(c.n, c.seed), ints = new Items<Int>(c.n);
			for (i in 0...c.n)
				ints[i] = Std.int(a[i] * 1000);
			var s = sum(c.n, i -> a[i] * a[i], Simd);
			var si = sum(c.n, i -> ints[i] * 3, Simd);
			var lo = min(c.n, i -> a[i], Simd), hi = max(c.n, i -> a[i], Simd);
			var saved = helder.jobs.Jobs.workers;
			for (w in [0, 1, 2, 3, 5, 11]) {
				helder.jobs.Jobs.workers = w;
				equals(sum(c.n, i -> a[i] * a[i], Jobs), s);
				equals(sum(c.n, i -> ints[i] * 3, Jobs), si);
				equals(min(c.n, i -> a[i], Jobs), lo);
				equals(max(c.n, i -> a[i], Jobs), hi);
			}
			helder.jobs.Jobs.workers = saved;
			equals(sum(c.n, i -> ints[i] * 3, Scalar), si);
			equals(min(c.n, i -> a[i], Scalar), lo);
			equals(max(c.n, i -> a[i], Scalar), hi);
			var exact = 0.0;
			for (i in 0...c.n)
				exact += a[i] * a[i];
			assert(Math.abs(sum(c.n, i -> a[i] * a[i], Scalar) - s) <= 1e-5 * Math.max(1, exact), 'sum: ${sum(c.n, i -> a[i] * a[i], Scalar)} and $s');
		}));
		test("none: the identity", () -> {
			var a = new Items<Float>(0);
			equals(sum(0, i -> a[i]), 0.0);
			equals(min(0, i -> a[i]), Math.POSITIVE_INFINITY);
			equals(max(0, i -> a[i]), Math.NEGATIVE_INFINITY);
		});
		test("reduce: a vector's bounds, combined in order", () -> property(cases(), c -> {
			var a = data(c.n, c.seed);
			function bounds(on:On):Vec2
				return reduce(c.n, vec2(1e30, -1e30), i -> vec2(a[i], a[i]), (x, y) -> vec2(Math.min(x.x, y.x), Math.max(x.y, y.y)), on);
			var simd = bounds(On.Simd), jobs = bounds(On.Jobs), scalar = bounds(On.Scalar);
			equals([simd.x, simd.y], [jobs.x, jobs.y]);
			equals([simd.x, simd.y], [scalar.x, scalar.y]);
			if (c.n > 0) equals(simd.x, min(c.n, i -> a[i]));
		}));
	});

	describe("kernel", () -> {
		test("a named body of its own parameters", () -> property(cases(), c -> {
			var a = data(c.n, c.seed);
			function run(on:On) {
				var out = new Items<Float>(c.n);
				Scale.run(c.n, {from: a, to: out, by: 3, add: 0.5}, on);
				return out;
			}
			same(run(On.Simd), run(On.Jobs), "jobs");
			near(run(On.Simd), run(On.Scalar), "scalar");
		}));
		test("a written Items passed twice: thrown", () -> {
			var a = new Items<Float>(8);
			throws(() -> Scale.run(8, {from: a, to: a, by: 1, add: 0}));
		});
	});

	describe("Auto", () -> {
		test("picks Simd or Jobs, the same bits either way", () -> {
			var a = data(20000, 1), out = new Items<Float>(20000);
			var want = new Items<Float>(20000);
			each(20000, i -> want[i] = a[i] * 2 + Math.sqrt(Math.abs(a[i])), Simd);
			for (_ in 0...40) {
				each(20000, i -> out[i] = a[i] * 2 + Math.sqrt(Math.abs(a[i])));
				same(out, want, "auto");
			}
		});
	});
}

final Scale = kernel(function(i:Int, p:{from:Items<Float>, to:Items<Float>, by:Float, add:Float}) {
	p.to[i] = p.from[i] * p.by + p.add + p.from.length;
});

@:structInit @:publicFields class Particle {
	var pos:Vec4;
	var vel:Vec4;
}

private typedef Case = {n:Int, seed:Int, on:On}

private function cases():Gen<Case>
	return c -> {n: c.draw(oneOf([int(0, 9), int(0, 300), int(1000, 5000)])), seed: c.draw(int(0, 100000)), on: c.draw(pick([On.Auto, On.Scalar, On.Simd, On.Jobs]))};

// (n floats in -100...100 of a seed)
private function data(n:Int, seed:Int):Items<Float> {
	var a = new Items<Float>(n), s = seed * 7919 + 1;
	for (i in 0...n) {
		s = (s * 1103515245 + 12345) & 0x7FFFFFFF;
		a[i] = s / 0x7FFFFFFF * 200 - 100;
	}
	return a;
}

private function particles(n:Int, seed:Int):Items<Particle> {
	var a = data(n * 6, seed), ps = new Items<Particle>(n);
	for (i in 0...n)
		ps[i] = {pos: vec4(a[6 * i] / 10, a[6 * i + 1] / 25 + 4, a[6 * i + 2] / 10, i), vel: vec4(a[6 * i + 3] / 50, a[6 * i + 4] / 20, a[6 * i + 5] / 50, 0)};
	return ps;
}

private function f32(x:Float):Float
	return haxe.io.FPHelper.i32ToFloat(haxe.io.FPHelper.floatToI32(x));

private function list(a:Items<Int>):Array<Int>
	return [for (i in 0...a.length) a[i]];

private function flat(ps:Items<Particle>):Array<Float>
	return [for (i in 0...ps.length) for (v in [ps[i].pos, ps[i].vel]) for (x in [v.x, v.y, v.z, v.w]) x];

private function same(a:Items<Float>, b:Items<Float>, what:String, ?pos:haxe.PosInfos) {
	for (i in 0...a.length)
		if (a[i] != b[i] && !(Math.isNaN(a[i]) && Math.isNaN(b[i]))) {
			fail('$what: item $i: ${a[i]} and ${b[i]}', pos);
			return;
		}
}

private function near(a:Items<Float>, b:Items<Float>, what:String, ?pos:haxe.PosInfos)
	nearList([for (i in 0...a.length) a[i]], [for (i in 0...b.length) b[i]], what, pos);

private function nearList(a:Array<Float>, b:Array<Float>, what:String, ?pos:haxe.PosInfos) {
	for (i in 0...a.length)
		if (!(Math.abs(a[i] - b[i]) <= 2e-5 * Math.max(1, Math.abs(b[i])))) {
			fail('$what: item $i: ${a[i]} and ${b[i]}', pos);
			return;
		}
}
