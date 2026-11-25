package helder.gfx.soft;

import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

// A compute stage's storage on the CPU (helder.gfx.shader.Soft's compute
// form): a storage buffer's binding (its bytes' address, then their
// count, Abi.STORAGE's slots) read and written by element (std430: the
// element's stride, a field's offset), each lane its own index, an index
// past the buffer read as 0 and written nowhere (as GPUs' robust access);
// atomics lane by lane in order (a dispatch runs on one thread: the same
// order on every machine); a storage texture's texel (a SoftTexture) set.
@:hxmc.unsafe(gc)
class Buffers {
	public static inline var DATA = 0;
	public static inline var BYTES = 8;
	public static inline var SIZE = 16;

	// (the byte of element i's field at off, or -1 past the buffer)
	static inline function at(b:Ptr, i:Int, stride:Int, off:Int):Int {
		var o = i * stride + off;
		return b.isNull() || i < 0 || o + 4 > Mem.getI32(b, BYTES) ? -1 : o;
	}

	public static inline function f32At(b:Ptr, i:Int, stride:Int, off:Int):Float {
		var o = at(b, i, stride, off);
		return o < 0 ? 0.0 : (Mem.getF32(Mem.getPtr(b, DATA), o) : Float);
	}

	public static inline function i32At(b:Ptr, i:Int, stride:Int, off:Int):Int {
		var o = at(b, i, stride, off);
		return o < 0 ? 0 : Mem.getI32(Mem.getPtr(b, DATA), o);
	}

	public static function f32(b:Ptr, i:LaneInt, stride:Int, off:Int):Lane
		return Lane.make(f32At(b, i.get(0), stride, off), f32At(b, i.get(1), stride, off), f32At(b, i.get(2), stride, off), f32At(b, i.get(3), stride, off));

	public static function i32(b:Ptr, i:LaneInt, stride:Int, off:Int):LaneInt
		return LaneInt.make(i32At(b, i.get(0), stride, off), i32At(b, i.get(1), stride, off), i32At(b, i.get(2), stride, off), i32At(b, i.get(3), stride, off));

	// (hxmc.simd's lanes read by constants: each lane written in turn)
	public static function setF32(b:Ptr, i:LaneInt, stride:Int, off:Int, v:Lane, m:LaneBool) {
		inline function one(l:Int) {
			var o = m.get(l) ? at(b, i.get(l), stride, off) : -1;
			if (o >= 0) Mem.setF32(Mem.getPtr(b, DATA), o, v.get(l));
		}
		one(0);
		one(1);
		one(2);
		one(3);
	}

	public static function setI32(b:Ptr, i:LaneInt, stride:Int, off:Int, v:LaneInt, m:LaneBool) {
		inline function one(l:Int) {
			var o = m.get(l) ? at(b, i.get(l), stride, off) : -1;
			if (o >= 0) Mem.setI32(Mem.getPtr(b, DATA), o, v.get(l));
		}
		one(0);
		one(1);
		one(2);
		one(3);
	}

	// atomicAdd (op 0), atomicMin (1), atomicMax (2) of an Int element: each lane's value before
	public static function atomic(b:Ptr, i:LaneInt, v:LaneInt, m:LaneBool, op:Int):LaneInt {
		inline function one(l:Int):Int {
			var o = m.get(l) ? at(b, i.get(l), 4, 0) : -1, d = o < 0 ? Ptr.nil() : Mem.getPtr(b, DATA);
			var was = o < 0 ? 0 : Mem.getI32(d, o), x = v.get(l);
			if (o >= 0) Mem.setI32(d, o, op == 0 ? was + x : op == 1 ? (x < was ? x : was) : (x > was ? x : was));
			return was;
		}
		// (in lane order: the arguments' order)
		var r0 = one(0), r1 = one(1), r2 = one(2), r3 = one(3);
		return LaneInt.make(r0, r1, r2, r3);
	}

	// texel x, y of a storage texture (a SoftTexture's level 0) set to each lane's colour, in its format
	public static function store(t:Ptr, x:LaneInt, y:LaneInt, c:Lane4, m:LaneBool) {
		if (t.isNull()) return;
		var w = Mem.getI32(t, SoftTexture.WIDTH), h = Mem.getI32(t, SoftTexture.HEIGHT), kind = Mem.getI32(t, SoftTexture.KIND);
		var half = Mem.getI32(t, SoftTexture.FORMAT) == (cast TextureFormat.RGBA16F : Int), base = SoftTexture.at(t, 0, 0);
		inline function one(l:Int) {
			var px = x.get(l), py = y.get(l);
			if (m.get(l) && px >= 0 && py >= 0 && px < w && py < h) texel(base, kind, half, py * w + px, c.x.get(l), c.y.get(l), c.z.get(l), c.w.get(l));
		}
		one(0);
		one(1);
		one(2);
		one(3);
	}

	// (texel i of a storage texture's level, in its kind: unorm clamped and rounded, half floats rounded)
	static function texel(base:Ptr, kind:Int, half:Bool, i:Int, r:Float, g:Float, b:Float, a:Float) {
		if (kind == SoftTexture.U8) {
			inline function q(v:Float):Int
				return Std.int((v < 0 ? 0 : v > 1 ? 1 : v) * 255 + 0.5);
			Mem.setI32(base, 4 * i, q(r) | (q(g) << 8) | (q(b) << 16) | (q(a) << 24));
		} else if (kind == SoftTexture.F4) {
			inline function f(v:Float):Float
				return half ? Formats.roundHalf(v) : v;
			Mem.setF32(base, 16 * i, f(r));
			Mem.setF32(base, 16 * i + 4, f(g));
			Mem.setF32(base, 16 * i + 8, f(b));
			Mem.setF32(base, 16 * i + 12, f(a));
		} else
			Mem.setF32(base, 4 * i, r);
	}
}
