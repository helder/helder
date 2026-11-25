import haxe.Timer;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.parallel.Items;
import helder.parallel.On;
import helder.parallel.Parallel;
import hxmc.unsafe.LibC;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;
import ParallelShaders;

// helder.parallel's bench (`bun run test bench parallel`; docs/design/parallel.md,
// "Measured"): one particle step over N particles, as
//
//   today    ParallelShaders.Integrate's main over an Array<Particle> (the
//            CPU fallback examples/fountain has), then store()d into bytes
//   hand     the prototype's lanes, written by hand (ParallelKernels.lanes):
//            what the generated form is measured against
//   scalar   each(n, ..., Scalar), the generated scalar form
//   simd     each(n, ..., Simd): 4 particles a turn, one thread
//   jobs     each(n, ..., Jobs): simd's chunks on helder.jobs' threads
//   auto     each(n, ...): the form Auto picks
//
// Each the least of its runs (a run: enough steps for 2 ms), in µs a step.
// First the forms are checked against each other after 64 steps of 1003
// particles: simd, jobs, auto and hand the same bits, scalar and today within
// 1e-4. PARALLEL_N="1000 5000" and PARALLEL_FORMS="simd,jobs" narrow a run.
@:hxmc.unsafe(gc)
class ParallelBench {
	static inline var DT = 1 / 120;
	static inline var GRAVITY = 9.8;
	static inline var DRAG = 0.999;
	static inline var BOUNCE = 0.8;
	static final SIZES = [1000, 3000, 10000, 30000, 100000, 300000, 1000000];
	static final FORMS = ["today", "hand", "scalar", "simd", "jobs", "auto"];

	static var failures = 0;

	static function main() {
		Sys.println('parallel: ${hxmc.Platform.os() == 2 ? "windows" : hxmc.Platform.os() == 1 ? "macos" : hxmc.Platform.os() == 3 ? "wasm32" : "linux"}, ${helder.jobs.Spread.threads() + 1} threads');
		check(1003, 64);
		var given = Sys.getEnv("PARALLEL_N"), only = Sys.getEnv("PARALLEL_FORMS");
		var sizes = given == null ? SIZES : [for (x in given.split(" ")) if (x != "") Std.parseInt(x)];
		var names = only == null ? FORMS : FORMS.filter(x -> only.split(",").contains(x));
		var rows:Array<Array<String>> = [];
		for (n in sizes) {
			var row = [Std.string(n)];
			for (name in names) {
				var us = measure(name, n);
				Sys.println('parallel $n $name ${round(us)}');
				row.push(round(us));
			}
			rows.push(row);
		}
		Sys.println("");
		Sys.println("| N | " + names.join(" | ") + " |");
		Sys.println("|" + [for (_ in 0...names.length + 1) "---:"].join("|") + "|");
		for (r in rows)
			Sys.println("| " + r.join(" | ") + " |");
		Sys.exit(failures == 0 ? 0 : 1);
	}

	static function round(us:Float):String
		return us >= 100 ? Std.string(Math.round(us)) : Std.string(Math.round(us * 10) / 10);

	// ---- the particles: the same start for every form

	static function initial(n:Int):Items<Particle> {
		var ps = new Items<Particle>(n), seed = 12345;
		inline function next():Float {
			seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
			return seed / 0x7FFFFFFF;
		}
		for (i in 0...n)
			ps[i] = {pos: vec4(next() * 10 - 5, next() * 4, next() * 10 - 5, i), vel: vec4(next() * 2 - 1, next() * 6 - 1, next() * 2 - 1, 0)};
		return ps;
	}

	// the step, a body (the design's particles step, its age left out)
	static function step(ps:Items<Particle>, on:On) {
		var g = GRAVITY, dt = DT, drag = DRAG, bounce = BOUNCE;
		each(ps.length, i -> {
			var q = ps[i];
			var vel = q.vel.xyz * drag - vec3(0, g * dt, 0);
			var pos = q.pos.xyz + vel * dt;
			if (pos.y < 0) {
				pos = vec3(pos.x, -pos.y, pos.z);
				vel = vec3(vel.x, -vel.y * bounce, vel.z);
			}
			ps[i] = {pos: vec4(pos, q.pos.w), vel: vec4(vel, q.vel.w)};
		}, on);
	}

	// ---- a run of one form: steps steps

	static final id = ComputeInput.at(0, 0, 0, 64, 1, 1);
	static var list:Array<Particle> = [];
	static var params:{step:ParticleStep, particles:RWStorage<Particle>} = null;
	static var bytes:haxe.io.Bytes = null;

	static function steps(name:String, ps:Items<Particle>, steps:Int) {
		var n = ps.length;
		switch name {
			case "today":
				for (_ in 0...steps) {
					for (i in 0...n) {
						id.x = i;
						Integrate.main(id, params);
					}
					Integrate.params.particles.store(list, bytes);
				}
			case "hand":
				var d = Mem.getPtr(ps.data().binding(), 0);
				for (_ in 0...steps)
					ParallelKernels.lanes(d, 0, n, DT, GRAVITY, DRAG, BOUNCE);
			case "scalar":
				for (_ in 0...steps)
					step(ps, Scalar);
			case "simd":
				for (_ in 0...steps)
					step(ps, Simd);
			case "jobs":
				for (_ in 0...steps)
					step(ps, Jobs);
			case _:
				for (_ in 0...steps)
					step(ps, Auto);
		}
	}

	static function prepare(name:String, ps:Items<Particle>) {
		if (name != "today") return;
		list = [for (i in 0...ps.length) ps[i]];
		bytes = haxe.io.Bytes.alloc(ps.length * Integrate.params.particles.stride);
		params = {step: {dt: DT, gravity: GRAVITY, drag: DRAG, bounce: BOUNCE, count: ps.length}, particles: list};
	}

	// (the particles as floats: today's from its list)
	static function floats(name:String, ps:Items<Particle>):Array<Float>
		return name == "today" ? [for (q in list) for (v in [q.pos, q.vel]) for (x in [v.x, v.y, v.z, v.w]) x] : [
			for (i in 0...ps.length) for (v in [ps[i].pos, ps[i].vel]) for (x in [v.x, v.y, v.z, v.w]) x
		];

	// ---- the forms checked against simd

	static function check(n:Int, count:Int) {
		var ref = initial(n);
		steps("simd", ref, count);
		var want = floats("simd", ref);
		for (name in ["jobs", "auto", "hand", "scalar", "today"]) {
			var ps = initial(n);
			prepare(name, ps);
			steps(name, ps, count);
			compare(name, floats(name, ps), want, name == "scalar" || name == "today" ? 1e-4 : 0);
			ps.dispose();
		}
		ref.dispose();
	}

	static function compare(name:String, got:Array<Float>, want:Array<Float>, tolerance:Float) {
		var worst = 0.0, at = -1;
		for (i in 0...want.length) {
			var e = Math.abs(got[i] - want[i]) / Math.max(1, Math.abs(want[i]));
			if (!(e <= worst)) {
				worst = e;
				at = i;
			}
		}
		var ok = worst <= tolerance;
		if (!ok) failures++;
		Sys.println('parallel: check $name: ' + (ok ? "ok" : "FAIL") + (worst == 0 ? " (the same bits)" : ' (at most $worst apart, at float $at)'));
	}

	// ---- timing

	static function measure(name:String, n:Int):Float {
		var ps = initial(n);
		prepare(name, ps);
		// (enough steps for 2 ms or more a run, after one to warm up)
		var t0 = Timer.stamp();
		steps(name, ps, 1);
		var one = Timer.stamp() - t0;
		var k = Std.int(Math.max(1, Math.min(10000, 0.002 / Math.max(one, 1e-7))));
		var runs = one > 0.05 ? 3 : 10, best = 1e30;
		for (_ in 0...runs) {
			var t = Timer.stamp();
			steps(name, ps, k);
			best = Math.min(best, (Timer.stamp() - t) / k * 1e6);
		}
		ps.dispose();
		list = [];
		params = null;
		return best;
	}
}
