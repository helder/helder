import haxe.Timer;
using StringTools;
import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.*;
import helder.jobs.Jobs;
import helder.jobs.Parallel;
import helder.os.Surface;
import hxmc.unsafe.LibC;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;
import ParallelShaders;

// The Parallel prototype's bench (docs/design/parallel.md; `bun run test
// bench parallel`): one particle step (ParallelShaders.Integrate) over N
// particles, as
//
//   today    Integrate.main over an Array<Particle> (the CPU fallback
//            examples/fountain has), then store()d into the GPU's bytes
//   scalar   ParallelKernels.scalar over the bytes
//   vec      ParallelKernels.vec (a Vec4 a register)
//   lanes    ParallelKernels.lanes (4 particles a turn: the general form)
//   jobs     lanes in chunks on helder.jobs.Parallel's threads and this one
//   gpu      compute(): the step dispatched, then 32 bytes read back (the
//            wait for it); gpu x10: ten dispatches a frame, a tenth of it;
//            sync: an empty frame and the same read (the floor under gpu);
//            +read: the whole buffer read back after it; +write+read: the
//            CPU's bytes uploaded first too
//
// Each the least of its runs (a run: enough steps for a few milliseconds),
// in µs a step. First the forms are checked against each other after 64
// steps of 1003 particles (vec and lanes bit for bit; scalar, which rounds
// only where it stores, and the GPU, within 1e-4).
//
//   ParallelBench [cpu]     (cpu: no GPU device)
@:hxmc.unsafe(gc)
class ParallelBench {
	static inline var DT = 1 / 120;
	static inline var GRAVITY = 9.8;
	static inline var DRAG = 0.999;
	static inline var BOUNCE = 0.8;
	static final SIZES = [1000, 3000, 10000, 30000, 100000, 300000, 1000000];

	static var failures = 0;

	static function main() {
		var cpuOnly = Sys.args().contains("cpu");
		var threads = Parallel.threads();
		Sys.println('parallel: ${hxmc.Platform.os() == 2 ? "windows" : hxmc.Platform.os() == 1 ? "macos" : hxmc.Platform.os() == 3 ? "wasm32" : "linux"}, ${threads + 1} threads (Parallel.threads() + this one)');
		var device:Null<Device> = null;
		if (!cpuOnly) {
			device = try Device.create(Surface.headless(64, 64)) catch (e:Dynamic) {
				Sys.println('parallel: no GPU device ($e)');
				null;
			}
			if (device != null && !device.has(Compute)) {
				Sys.println('parallel: ${device.backend}: no compute');
				device = null;
			}
			if (device != null) Sys.println('parallel: gpu: ${device.backend}');
		}
		check(device, 1003, 64);
		var rows:Array<Array<String>> = [];
		var names = ["today", "scalar", "vec", "lanes", "jobs"];
		if (device != null) names = names.concat(["gpu", "gpu x10", "sync", "gpu +read", "gpu +write+read"]);
		// (PARALLEL_N="1000 5000": these sizes; PARALLEL_FORMS="lanes,gpu": these forms)
		var given = Sys.getEnv("PARALLEL_N"), only = Sys.getEnv("PARALLEL_FORMS");
		var sizes = given == null ? SIZES : [for (x in given.split(" ")) if (x != "") Std.parseInt(x)];
		if (only != null) names = names.filter(x -> only.split(",").contains(x));
		for (n in sizes) {
			var row = [Std.string(n)];
			for (name in names) {
				var us = measure(name, n, device);
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
		if (device != null) device.dispose();
		Sys.exit(failures == 0 ? 0 : 1);
	}

	static function round(us:Float):String
		return us >= 100 ? Std.string(Math.round(us)) : Std.string(Math.round(us * 10) / 10);

	// ---- the particles: the same start for every form

	static function initial(n:Int):Bytes {
		var b = Bytes.alloc(n * ParallelKernels.STRIDE), seed = 12345;
		inline function next():Float {
			seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
			return seed / 0x7FFFFFFF;
		}
		for (i in 0...n) {
			var o = i * ParallelKernels.STRIDE;
			b.setFloat(o, next() * 10 - 5);
			b.setFloat(o + 4, next() * 4);
			b.setFloat(o + 8, next() * 10 - 5);
			b.setFloat(o + 12, i);
			b.setFloat(o + 16, next() * 2 - 1);
			b.setFloat(o + 20, next() * 6 - 1);
			b.setFloat(o + 24, next() * 2 - 1);
			b.setFloat(o + 28, 0);
		}
		return b;
	}

	static function toPtr(b:Bytes):Ptr {
		var p = LibC.malloc(b.length);
		var i = 0;
		while (i < b.length) {
			Mem.setI32(p, i, b.getInt32(i));
			i += 4;
		}
		return p;
	}

	static function fromPtr(p:Ptr, n:Int):Bytes {
		var b = Bytes.alloc(n);
		var i = 0;
		while (i < n) {
			b.setInt32(i, Mem.getI32(p, i));
			i += 4;
		}
		return b;
	}

	// ---- a run of one form: steps steps

	static var ctx = Ptr.nil();
	static var list:Array<Particle> = [];
	static final id = ComputeInput.at(0, 0, 0, 64, 1, 1);
	static final cpuStep:ParticleStep = {dt: DT, gravity: GRAVITY, drag: DRAG, bounce: BOUNCE, count: 0};
	static var params:{step:ParticleStep, particles:RWStorage<Particle>} = null;

	static function steps(name:String, n:Int, d:Ptr, bytes:Bytes, steps:Int) {
		switch name {
			case "today":
				for (_ in 0...steps) {
					for (i in 0...n) {
						id.x = i;
						Integrate.main(id, params);
					}
					Integrate.params.particles.store(list, bytes);
				}
			case "scalar":
				for (_ in 0...steps)
					ParallelKernels.scalar(d, 0, n, DT, GRAVITY, DRAG, BOUNCE);
			case "vec":
				for (_ in 0...steps)
					ParallelKernels.vec(d, 0, n, DT, GRAVITY, DRAG, BOUNCE);
			case "lanes":
				for (_ in 0...steps)
					ParallelKernels.lanes(d, 0, n, DT, GRAVITY, DRAG, BOUNCE);
			case "jobs":
				// (4 chunks a thread, each a multiple of 4 particles)
				var pieces = (Parallel.threads() + 1) * 4;
				var chunk = ((Std.int((n + pieces - 1) / pieces) + 3) >> 2) << 2;
				if (ctx.isNull()) ctx = LibC.malloc(ParallelKernels.C_SIZE);
				Mem.setPtr(ctx, ParallelKernels.C_DATA, d);
				Mem.setI32(ctx, ParallelKernels.C_COUNT, n);
				Mem.setI32(ctx, ParallelKernels.C_CHUNK, chunk);
				Mem.setF64(ctx, ParallelKernels.C_DT, DT);
				Mem.setF64(ctx, ParallelKernels.C_GRAVITY, GRAVITY);
				Mem.setF64(ctx, ParallelKernels.C_DRAG, DRAG);
				Mem.setF64(ctx, ParallelKernels.C_BOUNCE, BOUNCE);
				var count = Std.int((n + chunk - 1) / chunk);
				for (_ in 0...steps)
					Parallel.run(ParallelKernels.chunkAddress(), ctx, count);
			case _:
				throw name;
		}
	}

	static function prepare(name:String, n:Int, bytes:Bytes) {
		if (name != "today") return;
		list = [for (i in 0...n) Integrate.params.particles.load(bytes, i)];
		cpuStep.count = n;
		params = {step: cpuStep, particles: list};
	}

	// ---- the forms checked against lanes

	static function check(device:Null<Device>, n:Int, count:Int) {
		var start = initial(n);
		var ref = toPtr(start);
		steps("lanes", n, ref, null, count);
		var want = fromPtr(ref, start.length);
		LibC.free(ref);
		for (name in ["scalar", "vec", "jobs", "today"]) {
			var b = Bytes.alloc(start.length);
			b.blit(0, start, 0, start.length);
			var d = toPtr(b);
			prepare(name, n, b);
			steps(name, n, d, b, count);
			var got = name == "today" ? b : fromPtr(d, b.length);
			LibC.free(d);
			compare(name, got, want, name == "vec" || name == "jobs" ? 0 : 1e-4);
		}
		if (device != null) {
			var g = new Gpu(device, start);
			for (_ in 0...count)
				g.steps(1);
			var got = Bytes.alloc(start.length);
			device.readBuffer(g.buffer, 0, got);
			compare("gpu", got, want, 1e-4);
			g.dispose();
		}
	}

	static function compare(name:String, got:Bytes, want:Bytes, tolerance:Float) {
		var worst = 0.0, at = -1;
		var i = 0;
		while (i < want.length) {
			var a = got.getFloat(i), b = want.getFloat(i);
			var e = Math.abs(a - b) / Math.max(1, Math.abs(b));
			if (!(e <= worst)) {
				worst = e;
				at = i;
			}
			i += 4;
		}
		var ok = worst <= tolerance;
		if (!ok) failures++;
		Sys.println('parallel: check $name: ' + (ok ? "ok" : "FAIL") + (worst == 0 ? " (the same bits)" : ' (at most $worst apart, at byte $at)'));
	}

	// ---- timing

	static function measure(name:String, n:Int, device:Null<Device>):Float {
		var start = initial(n);
		var best = 1e30;
		if (name.startsWith("gpu") || name == "sync") {
			var g = new Gpu(device, start);
			var small = Bytes.alloc(32), all = Bytes.alloc(start.length);
			function once():Float {
				var t0 = Timer.stamp();
				switch name {
					case "gpu":
						g.steps(1);
						device.readBuffer(g.buffer, 0, small);
					case "gpu x10":
						g.steps(10);
						device.readBuffer(g.buffer, 0, small);
					case "sync":
						g.steps(0);
						device.readBuffer(g.buffer, 0, small);
					case "gpu +read":
						g.steps(1);
						device.readBuffer(g.buffer, 0, all);
					case _:
						device.writeBuffer(g.buffer, 0, all);
						g.steps(1);
						device.readBuffer(g.buffer, 0, all);
				}
				var t = (Timer.stamp() - t0) * 1e6;
				if (Sys.getEnv("PARALLEL_VERBOSE") != null) Sys.println('parallel:   $name $n: ' + round(t));
				return name == "gpu x10" ? t / 10 : t;
			}
			for (_ in 0...3)
				once();
			var runs = n >= 1000000 ? 15 : 40;
			for (_ in 0...runs)
				best = Math.min(best, once());
			g.dispose();
			return best;
		}
		var d = toPtr(start);
		prepare(name, n, start);
		// (enough steps for 2 ms or more a run, after one to warm up)
		var t0 = Timer.stamp();
		steps(name, n, d, start, 1);
		var one = Timer.stamp() - t0;
		var k = Std.int(Math.max(1, Math.min(10000, 0.002 / Math.max(one, 1e-7))));
		var runs = one > 0.05 ? 3 : 10;
		for (_ in 0...runs) {
			var t = Timer.stamp();
			steps(name, n, d, start, k);
			best = Math.min(best, (Timer.stamp() - t) / k * 1e6);
		}
		LibC.free(d);
		list = [];
		params = null;
		return best;
	}
}

// the step on the GPU: the particles' buffer, the pipeline, the uniform block
private class Gpu {
	public final buffer:Buffer;

	final device:Device;
	final pipeline:ComputePipeline;
	final block:Bytes;
	final n:Int;

	public function new(device:Device, start:Bytes) {
		this.device = device;
		n = Std.int(start.length / Integrate.params.particles.stride);
		buffer = device.createBuffer({size: start.length, usage: Storage, data: start});
		pipeline = device.createComputePipeline(Integrate.pipeline());
		block = Bytes.alloc(Integrate.params.step.block.size);
		Integrate.params.step.write({dt: 1 / 120, gravity: 9.8, drag: 0.999, bounce: 0.8, count: n}, block);
	}

	// k dispatches in a frame (none: the frame alone)
	public function steps(k:Int) {
		var enc = device.beginFrame();
		if (k > 0) {
			enc.beginCompute();
			enc.setComputePipeline(pipeline);
			for (_ in 0...k) {
				enc.setUniforms(Integrate.params.step.block.binding, block);
				enc.setStorage(Integrate.params.particles.binding, buffer);
				enc.dispatch(Integrate.groups(n));
			}
			enc.endCompute();
		}
		device.endFrame();
	}

	public function dispose()
		device.destroyBuffer(buffer);
}
