import hxmc.simd.F32x4;
import hxmc.simd.I32x4;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

// The CPU forms of ParallelShaders.Integrate, written by hand as the kernel
// compiler (docs/design/parallel.md, "One body, four forms") would emit
// them from the same body, over the GPU's own std430 bytes (a particle: 32
// bytes, pos then vel, each four float32s):
//
//   scalar   one particle a turn, Haxe's Floats (doubles), stored as float32
//   lanes    4 particles a turn, a lane each (the general form: any body):
//            4 rows loaded, transposed into x, y, z, w lanes, the body run
//            on lanes, its if a select, transposed back and stored
//   vec      one particle a turn, its Vec4 one register (the form for a
//            body all of whose values are Vec4s: not general)
//   chunk    a range of lanes on helder.jobs.Spread's threads: a GC-free
//            callback of a context (the buffer, the count, the uniforms)
//
// lanes and vec round every operation to float32, as the GPU does (no
// fused multiply-adds); scalar rounds only where it stores.
@:hxmc.unsafe(gc)
class ParallelKernels {
	public static inline var STRIDE = 32;

	// (a run's context: what chunk reads)
	public static inline var C_DATA = 0;
	public static inline var C_COUNT = 8;
	public static inline var C_CHUNK = 12;
	public static inline var C_DT = 16;
	public static inline var C_GRAVITY = 24;
	public static inline var C_DRAG = 32;
	public static inline var C_BOUNCE = 40;
	public static inline var C_SIZE = 48;

	public static function scalar(d:Ptr, from:Int, to:Int, dt:Float, g:Float, drag:Float, bounce:Float) {
		var gdt = g * dt;
		for (i in from...to) {
			var o = i * STRIDE;
			var vx = Mem.getF32(d, o + 16) * drag, vy = Mem.getF32(d, o + 20) * drag - gdt, vz = Mem.getF32(d, o + 24) * drag;
			var px = Mem.getF32(d, o) + vx * dt, py = Mem.getF32(d, o + 4) + vy * dt, pz = Mem.getF32(d, o + 8) + vz * dt;
			if (py < 0) {
				py = -py;
				vy = -vy * bounce;
			}
			Mem.setF32(d, o, px);
			Mem.setF32(d, o + 4, py);
			Mem.setF32(d, o + 8, pz);
			Mem.setF32(d, o + 16, vx);
			Mem.setF32(d, o + 20, vy);
			Mem.setF32(d, o + 24, vz);
		}
	}

	public static function lanes(d:Ptr, from:Int, to:Int, dt:Float, g:Float, drag:Float, bounce:Float) {
		// (the uniforms: splatted once, as float32s; g * dt rounded as the GPU's)
		var dtv = F32x4.splat(dt), dragv = F32x4.splat(drag), gdt = F32x4.splat(g) * dtv, nb = F32x4.splat(-bounce), zero = F32x4.zero();
		var i = from;
		while (i + 4 <= to) {
			var o = i * STRIDE;
			var p0 = F32x4.loadPtr(d, o), v0 = F32x4.loadPtr(d, o + 16), p1 = F32x4.loadPtr(d, o + 32), v1 = F32x4.loadPtr(d, o + 48);
			var p2 = F32x4.loadPtr(d, o + 64), v2 = F32x4.loadPtr(d, o + 80), p3 = F32x4.loadPtr(d, o + 96), v3 = F32x4.loadPtr(d, o + 112);
			// (rows to lanes)
			var a0 = p0.shuffle(p1, 0, 4, 1, 5), a1 = p2.shuffle(p3, 0, 4, 1, 5), a2 = p0.shuffle(p1, 2, 6, 3, 7), a3 = p2.shuffle(p3, 2, 6, 3, 7);
			var px = a0.shuffle(a1, 0, 1, 4, 5), py = a0.shuffle(a1, 2, 3, 6, 7), pz = a2.shuffle(a3, 0, 1, 4, 5), pw = a2.shuffle(a3, 2, 3, 6, 7);
			var b0 = v0.shuffle(v1, 0, 4, 1, 5), b1 = v2.shuffle(v3, 0, 4, 1, 5), b2 = v0.shuffle(v1, 2, 6, 3, 7), b3 = v2.shuffle(v3, 2, 6, 3, 7);
			var vx = b0.shuffle(b1, 0, 1, 4, 5), vy = b0.shuffle(b1, 2, 3, 6, 7), vz = b2.shuffle(b3, 0, 1, 4, 5), vw = b2.shuffle(b3, 2, 3, 6, 7);
			// (the body)
			vx = vx * dragv;
			vy = vy * dragv - gdt;
			vz = vz * dragv;
			px = px + vx * dtv;
			py = py + vy * dtv;
			pz = pz + vz * dtv;
			var below = py.lt(zero);
			py = F32x4.select(below, -py, py);
			vy = F32x4.select(below, vy * nb, vy);
			// (lanes to rows)
			a0 = px.shuffle(py, 0, 4, 1, 5);
			a1 = pz.shuffle(pw, 0, 4, 1, 5);
			a2 = px.shuffle(py, 2, 6, 3, 7);
			a3 = pz.shuffle(pw, 2, 6, 3, 7);
			a0.shuffle(a1, 0, 1, 4, 5).storePtr(d, o);
			a0.shuffle(a1, 2, 3, 6, 7).storePtr(d, o + 32);
			a2.shuffle(a3, 0, 1, 4, 5).storePtr(d, o + 64);
			a2.shuffle(a3, 2, 3, 6, 7).storePtr(d, o + 96);
			b0 = vx.shuffle(vy, 0, 4, 1, 5);
			b1 = vz.shuffle(vw, 0, 4, 1, 5);
			b2 = vx.shuffle(vy, 2, 6, 3, 7);
			b3 = vz.shuffle(vw, 2, 6, 3, 7);
			b0.shuffle(b1, 0, 1, 4, 5).storePtr(d, o + 16);
			b0.shuffle(b1, 2, 3, 6, 7).storePtr(d, o + 48);
			b2.shuffle(b3, 0, 1, 4, 5).storePtr(d, o + 80);
			b2.shuffle(b3, 2, 3, 6, 7).storePtr(d, o + 112);
			i += 4;
		}
		// (the last few: one lane each, as the masked last group would)
		if (i < to) vec(d, i, to, dt, g, drag, bounce);
	}

	public static function vec(d:Ptr, from:Int, to:Int, dt:Float, g:Float, drag:Float, bounce:Float) {
		var dtv = F32x4.make(dt, dt, dt, 0), dragv = F32x4.make(drag, drag, drag, 1), gdt = F32x4.make(0, g, 0, 0) * F32x4.splat(dt);
		var nb = F32x4.make(1, -bounce, 1, 1), zero = F32x4.zero(), y = I32x4.make(0, -1, 0, 0), xyz = I32x4.make(-1, -1, -1, 0);
		for (i in from...to) {
			var o = i * STRIDE;
			var pos = F32x4.loadPtr(d, o), vel = F32x4.loadPtr(d, o + 16);
			vel = F32x4.select(xyz, vel * dragv - gdt, vel);
			pos = F32x4.select(xyz, pos + vel * dtv, pos);
			var below = pos.lt(zero) & y;
			pos = F32x4.select(below, -pos, pos);
			vel = F32x4.select(below, vel * nb, vel);
			pos.storePtr(d, o);
			vel.storePtr(d, o + 16);
		}
	}

	// chunk k of a run (Parallel.run's callback): its lanes
	@:hxmc.callback @:hxmc.unsafe public static function chunk(ctx:Ptr, k:Int):Int {
		var n = Mem.getI32(ctx, C_COUNT), c = Mem.getI32(ctx, C_CHUNK);
		var from = k * c, to = from + c;
		if (to > n) to = n;
		if (from < to) lanes(Mem.getPtr(ctx, C_DATA), from, to, Mem.getF64(ctx, C_DT), Mem.getF64(ctx, C_GRAVITY), Mem.getF64(ctx, C_DRAG), Mem.getF64(ctx, C_BOUNCE));
		return 0;
	}

	static var chunkAddr = Ptr.nil();

	public static function chunkAddress():Ptr {
		if (chunkAddr.isNull()) chunkAddr = hxmc.unsafe.Callback.addr(ParallelKernels.chunk);
		return chunkAddr;
	}
}
