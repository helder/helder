import helder.gfx.Device;
import helder.math.Mat4;
import helder.math.Vec2;
import helder.math.Vec3;
import helder.gfx.shader.ShaderMath.*;
import helder.math.Vec4;
import helder.os.Surface;
import helder.parallel.GpuRunner;
import helder.parallel.Items;
import helder.parallel.ItemsData;
import helder.parallel.On;
import helder.parallel.Parallel;

@:structInit @:publicFields class GpuParticle {
	var pos:Vec4;
	var vel:Vec4;
}

// helder.parallel's Gpu form against its Simd form on a headless device
// (the gfx-compute lane: D3D11, GL on Mesa; gfx-soft: the CPU back end,
// whose buffers are the Items' own memory), within the GPU's rounding (its
// fused multiply-adds, its own sin; a reduction's tree its own order), and
// Auto's residency rule: a body
// whose Items a dispatch wrote last, or the GPU draws, runs there. Exit
// code 3: no device with compute (skipped).
class GpuCheck {
	static var failures = 0;

	static function main() {
		var device = try Device.create(Surface.headless(64, 64)) catch (e:Dynamic) null;
		if (device == null || !device.has(Compute)) {
			Sys.println('GpuCheck: no device with compute stages' + (device == null ? "" : ' (${device.backend})'));
			Sys.exit(3);
		}
		Parallel.device = device;
		Sys.println('GpuCheck: ${device.backend}');
		floats();
		particles();
		captures();
		residency(device);
		kernels();
		large();
		reductions("");
		// (the subgroups made of workgroup memory, as D3D11 has them)
		if (device.has(Subgroups)) {
			GpuRunner.emulate = true;
			reductions(" (emulated)");
			GpuRunner.emulate = false;
		}
		randomReductions();
		reductionResidency();
		largeReduction();
		writeAfterRead();
		sceneParticles();
		Sys.println(failures == 0 ? "GpuCheck: ok" : 'GpuCheck: $failures failed');
		device.dispose();
		Sys.exit(failures == 0 ? 0 : 1);
	}

	static function check(what:String, ok:Bool, ?detail:String) {
		if (!ok) failures++;
		Sys.println('GpuCheck: $what: ' + (ok ? "ok" : "FAIL" + (detail == null ? "" : ' ($detail)')));
	}

	static function data(n:Int, seed:Int):Items<Float> {
		var a = new Items<Float>(n), s = seed * 7919 + 1;
		for (i in 0...n) {
			s = (s * 1103515245 + 12345) & 0x7FFFFFFF;
			a[i] = s / 0x7FFFFFFF * 200 - 100;
		}
		return a;
	}

	static function near(what:String, a:Items<Float>, b:Items<Float>, tolerance = 1e-5) {
		var worst = 0.0, at = -1;
		for (i in 0...a.length) {
			var e = Math.abs(a[i] - b[i]) / Math.max(1, Math.abs(b[i]));
			if (!(e <= worst)) {
				worst = e;
				at = i;
			}
		}
		check(what, worst <= tolerance, 'item $at: ${at < 0 ? 0 : a[at]} and ${at < 0 ? 0 : b[at]}');
	}

	// a body of Floats, Ints and a loop, its lanes' tail
	static function floats() {
		for (n in [1, 7, 64, 1003, 30001]) {
			var a = data(n, n);
			function run(on:On) {
				var out = new Items<Float>(n), ints = new Items<Int>(n);
				each(n, i -> {
					var s = 0.0;
					for (k in 0...3)
						s += a[(i + k) % n] * k;
					// (GLSL's % of a negative Int is undefined: of positive ones here)
					out[i] = Math.sqrt(Math.abs(a[i])) + s * 0.25 - Std.int(Math.abs(a[i])) % 7;
					ints[i] = (i * 31) ^ Std.int(a[i]);
				}, on);
				return {out: out, ints: ints};
			}
			var g = run(Gpu), c = run(Simd);
			near('floats $n', g.out, c.out);
			var same = true;
			for (i in 0...n)
				if (g.ints[i] != c.ints[i]) same = false;
			check('ints $n', same);
		}
	}

	static function step(ps:Items<GpuParticle>, on:On) {
		var g = 9.8, dt = 1 / 120, drag = 0.999, bounce = 0.8;
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
	}

	static function start(n:Int):Items<GpuParticle> {
		var a = data(n * 6, 3), ps = new Items<GpuParticle>(n);
		for (i in 0...n)
			ps[i] = {pos: vec4(a[6 * i] / 10, a[6 * i + 1] / 25 + 4, a[6 * i + 2] / 10, i), vel: vec4(a[6 * i + 3] / 50, a[6 * i + 4] / 20, a[6 * i + 5] / 50, 0)};
		return ps;
	}

	// 64 steps of a particle system, resident on the GPU between them
	static function particles() {
		var g = start(10007), c = start(10007);
		for (_ in 0...64) {
			step(g, Gpu);
			step(c, Simd);
		}
		var worst = 0.0;
		for (i in 0...g.length)
			for (pair in [[g[i].pos, c[i].pos], [g[i].vel, c[i].vel]])
				worst = Math.max(worst, Math.max(Math.max(Math.abs(pair[0].x - pair[1].x), Math.abs(pair[0].y - pair[1].y)), Math.abs(pair[0].z - pair[1].z)));
		check("particles, 64 steps", worst <= 1e-3, 'at most $worst apart');
	}

	// captured vectors, matrices, Bools and Ints in the uniform block
	static function captures() {
		var n = 100, out = new Items<Vec4>(n), simd = new Items<Vec4>(n), a = data(n, 9);
		var m = mat4(2), v = vec4(1, 2, 3, 4), flag = true, k = 3;
		each(n, i -> out[i] = flag ? m * (v * a[i]) + vec4(k) : v, Gpu);
		each(n, i -> simd[i] = flag ? m * (v * a[i]) + vec4(k) : v, Simd);
		var ok = true;
		for (i in 0...n)
			if (Math.abs(out[i].y - simd[i].y) > 1e-4 || Math.abs(out[i].w - simd[i].w) > 1e-4) ok = false;
		check("captures", ok, '${out[5].y} and ${simd[5].y}');
	}

	// Auto: on the GPU where a dispatch wrote last or the GPU draws, back on the CPU after a CPU write
	static function residency(device:Device) {
		var a = new Items<Float>(1000);
		each(1000, i -> a[i] = i, Gpu);
		check("after a dispatch: the GPU's alone", a.data().state == ItemsData.GPU);
		each(1000, i -> a[i] += 1);
		check("Auto stays there", a.data().state == ItemsData.GPU);
		check("read back on the CPU", a[999] == 1000 && a.data().state & ItemsData.CPU != 0);
		a[0] = 5;
		each(1000, i -> a[i] += 1);
		check("a CPU write: back on the CPU", a.data().state & ItemsData.CPU != 0 && a[0] == 6 && a[1] == 3);
		var drawn = new Items<Float>(64);
		var buffer = drawn.buffer(device);
		each(64, i -> drawn[i] = 2 * i);
		check("drawn: on the GPU", drawn.data().state == ItemsData.GPU && drawn[10] == 20);
		drawn.dispose();
		a.dispose();
	}

	static final Scale = kernel(function(i:Int, p:{from:Items<Float>, to:Items<Float>, by:Float}) {
		p.to[i] = p.from[i] * p.by + p.from.length;
	});

	static function kernels() {
		var a = data(5000, 4), g = new Items<Float>(5000), c = new Items<Float>(5000);
		Scale.run(5000, {from: a, to: g, by: 1.5}, Gpu);
		Scale.run(5000, {from: a, to: c, by: 1.5}, Simd);
		near("a kernel", g, c);
	}

	// a CPU write right after a dispatch that reads the Items: the dispatch
	// sees the values from before it (on Metal and the CPU back end the bytes
	// are the buffer's own: the write waits for the dispatch)
	static function writeAfterRead() {
		var n = 1 << 20, a = new Items<Float>(n), b = new Items<Float>(n);
		for (i in 0...n)
			a[i] = 1;
		each(n, i -> b[i] = a[i] * 2, Gpu);
		for (i in 0...n)
			a[i] = 5;
		var ok = true;
		for (i in 0...n)
			if (b[i] != 2) ok = false;
		check("a CPU write after a dispatch that reads it: not seen by the dispatch", ok, 'b[0] ${b[0]}, b[${n - 1}] ${b[n - 1]}');
		a.dispose();
		b.dispose();
	}

	// helder.scene's simulated particles (Particles: births, a floor, a
	// sphere) on the GPU against the CPU's lanes in lockstep: each step from
	// the same particles (the GPU's copied into the CPU's), so that the
	// bound is a step's. Over many steps the two would part: a particle
	// within rounding of the floor or the sphere takes the other branch of
	// its collision on a GPU whose sqrt and fused multiply-adds are its own
	// (Metal compiles with fast math), and the difference compounds. A step
	// moves every particle within 1e-4 of the lanes but one in 1000 at most,
	// which flipped a collision, and that one within a step's travel
	static function sceneParticles() {
		function system(on:On) {
			var ps = new helder.scene.render.Particles(4096, 512);
			ps.on = on;
			ps.floor = 0;
			ps.drag = 0.2;
			ps.spheres[0] = vec4(0, 1, 0, 0.6);
			return ps;
		}
		var g = system(Gpu), c = system(Simd);
		var worst = 0.0, flipped = 0, travel = 0.0, steps = 40;
		for (s in 0...steps) {
			for (ps in [g, c])
				for (k in 0...100)
					ps.emit(Math.sin(k) * 0.4, 2, Math.cos(k) * 0.4, Math.sin(k * 3), 1 + (k % 5) * 0.4, Math.cos(k * 7), 1, 1, 1, 1, 0.05, 0.01, 4);
			g.step(1 / 60);
			c.step(1 / 60);
			for (k in 0...g.capacity) {
				var a = g.items[k].start, b = c.items[k].start;
				var d = Math.max(Math.abs(a.x - b.x), Math.max(Math.abs(a.y - b.y), Math.abs(a.z - b.z)));
				if (d > 1e-4) {
					flipped++;
					travel = Math.max(travel, d);
				} else
					worst = Math.max(worst, d);
				// (the next step from the GPU's particles)
				c.items[k] = g.items[k];
			}
		}
		var ok = flipped * 1000 <= g.capacity * steps && travel <= 0.25;
		check("helder.scene's Particles, 40 steps in lockstep", ok, 'at most $worst apart; $flipped of ${g.capacity * steps} past 1e-4, at most $travel');
		g.dispose();
		c.dispose();
	}

	// past a row of 65535 workgroups: the index's y
	static function large() {
		var n = 65535 * 64 + 1000, a = new Items<Int>(n);
		each(n, i -> a[i] = i * 3, Gpu);
		var ok = true;
		for (i in [0, 1, 65535 * 64 - 1, 65535 * 64, n - 1])
			if (a[i] != i * 3) ok = false;
		check('$n items', ok);
		a.dispose();
	}

	// (within float32's rounding of a sum of values as large as scale)
	static function close(what:String, g:Float, c:Float, scale:Float) {
		var ok = Math.abs(g - c) <= 1e-5 * Math.max(1, scale) || g == c;
		check(what, ok, '$g and $c');
	}

	// sum, min, max and reduce of Floats, Ints and vectors: the Gpu form against Simd, past a workgroup's tails
	static function reductions(form:String) {
		for (n in [1, 3, 255, 256, 257, 1003, 65536 + 7, 300001]) {
			var a = data(n, n + 1), ints = new Items<Int>(n);
			for (i in 0...n)
				ints[i] = Std.int(a[i] * 1000);
			var scale = 0.0;
			for (i in 0...n)
				scale += a[i] * a[i];
			close('sum $n$form', sum(n, i -> a[i] * a[i], Gpu), sum(n, i -> a[i] * a[i], Simd), scale);
			check('sum of Ints $n$form', sum(n, i -> ints[i] * 3, Gpu) == sum(n, i -> ints[i] * 3, Simd));
			check('min $n$form', min(n, i -> a[i], Gpu) == min(n, i -> a[i], Simd));
			check('max $n$form', max(n, i -> a[i], Gpu) == max(n, i -> a[i], Simd));
			check('min of Ints $n$form', min(n, i -> ints[i], Gpu) == min(n, i -> ints[i], Simd));
			check('max of Ints $n$form', max(n, i -> ints[i] - i, Gpu) == max(n, i -> ints[i] - i, Simd));
			var g2 = sum(n, i -> vec2(a[i], 1), Gpu), c2 = sum(n, i -> vec2(a[i], 1), Simd);
			close('sum of Vec2 $n$form', g2.x, c2.x, 100 * n);
			check('sum of Vec2 $n$form: the count', g2.y == n);
			var g3 = sum(n, i -> vec3(1, a[i], -a[i]), Gpu), c3 = sum(n, i -> vec3(1, a[i], -a[i]), Simd);
			close('sum of Vec3 $n$form', g3.y + g3.x * 1000, c3.y + c3.x * 1000, 1000 * n);
			check('sum of Vec3 $n$form: negated', g3.z == -g3.y);
			var g4 = sum(n, i -> vec4(a[i] * a[i]), Gpu);
			close('sum of Vec4 $n$form', g4.w, sum(n, i -> a[i] * a[i], Simd), scale);
			function bounds(on:On):Vec2
				return reduce(n, vec2(1e30, -1e30), i -> {
					if (a[i] > 99) return vec2(a[i] - 1, a[i] - 1);
					return vec2(a[i], a[i]);
				}, (x, y) -> vec2(Math.min(x.x, y.x), Math.max(x.y, y.y)), on);
			var gb = bounds(Gpu), cb = bounds(Simd);
			check('reduce $n$form', gb.x == cb.x && gb.y == cb.y, '${gb.x}, ${gb.y} and ${cb.x}, ${cb.y}');
			function loopy(on:On):Int
				return reduce(n, 0, i -> {
					var c = 0;
					for (j in 0...4) {
						if (ints[(i + j) % n] > 50000) return j + 10;
						c += j;
					}
					return c;
				}, (x, y) -> x + y, on);
			var gl = loopy(Gpu), cl = loopy(Simd);
			check('reduce, a return in a loop $n$form', gl == cl, '$gl and $cl');
			a.dispose();
			ints.dispose();
		}
	}

	// random counts, data and bodies' constants: Gpu against Simd
	static function randomReductions() {
		var s = 12345, bad = 0;
		inline function next(m:Int):Int {
			s = (s * 1103515245 + 12345) & 0x7FFFFFFF;
			return s % m;
		}
		for (c in 0...60) {
			var n = switch next(3) {
				case 0: next(10);
				case 1: next(2000);
				case _: next(200000);
			}
			var a = data(n, next(100000)), k = next(7) - 3.5;
			var g = sum(n, i -> a[i] * k + 1, Gpu), want = sum(n, i -> a[i] * k + 1, Simd);
			if (!(Math.abs(g - want) <= 1e-5 * Math.max(1, 100 * Math.abs(k) * n))) {
				bad++;
				Sys.println('GpuCheck: random sum $n: $g and $want');
			}
			if (min(n, i -> a[i] * k, Gpu) != min(n, i -> a[i] * k, Simd) || max(n, i -> a[i] * k, Gpu) != max(n, i -> a[i] * k, Simd)) {
				bad++;
				Sys.println('GpuCheck: random min, max $n');
			}
			if (n == 0 && (min(n, i -> a[i], Gpu) != Math.POSITIVE_INFINITY || sum(n, i -> a[i], Gpu) != 0)) bad++;
			a.dispose();
		}
		check("60 random reductions", bad == 0);
	}

	// Auto: a reduction of Items a dispatch wrote last, on the GPU; of the CPU's, on the CPU
	static function reductionResidency() {
		var n = 5000, a = new Items<Float>(n);
		each(n, i -> a[i] = i % 100, Gpu);
		var s = sum(n, i -> a[i]);
		check("Auto: a sum of the GPU's values there", a.data().state == ItemsData.GPU && s == 49.5 * n, '$s');
		a[0] = 1;
		var t = sum(n, i -> a[i]);
		check("Auto: of the CPU's, there", a.data().state & ItemsData.CPU != 0 && t == 49.5 * n + 1, '$t');
		a.dispose();
	}

	// past a row of 65535 workgroups of 256: the partials' index's y
	static function largeReduction() {
		var n = 65535 * 256 + 300, a = new Items<Int>(n);
		each(n, i -> a[i] = i % 3 == 0 ? 2 : 1, Gpu);
		var want = 0;
		for (i in 0...n)
			want += i % 3 == 0 ? 2 : 1;
		var got = sum(n, i -> a[i], Gpu);
		check('a sum of $n items', got == want, '$got and $want');
		check('their max', max(n, i -> a[i] + (i == n - 1 ? 5 : 0), Gpu) == max(n, i -> a[i] + (i == n - 1 ? 5 : 0), Simd));
		a.dispose();
	}
}
