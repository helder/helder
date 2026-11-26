import helder.gfx.Device;
import helder.math.Mat4;
import helder.gfx.shader.ShaderMath.*;
import helder.math.Vec4;
import helder.os.Surface;
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
// fused multiply-adds, its own sin), and Auto's residency rule: a body
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
}
