package helder.gfx.soft;

import hxmc.simd.F32x4;
import hxmc.unsafe.Ptr;

// Four consecutive elements' Vec4 (at the same offset in each, stride bytes
// apart) as lanes and back: four 128-bit loads transposed (8 shuffles), the
// range form's contiguous reads and writes (helder.gfx.shader.Soft.rowsRead,
// helder.parallel's kernels), no bounds check (the caller's range holds
// them)
@:hxmc.unsafe(gc)
class Rows {
	public static inline function vec4(d:Ptr, o:Int, stride:Int):Lane4 {
		var r0 = F32x4.loadPtr(d, o), r1 = F32x4.loadPtr(d, o + stride), r2 = F32x4.loadPtr(d, o + 2 * stride), r3 = F32x4.loadPtr(d, o + 3 * stride);
		var a0 = r0.shuffle(r1, 0, 4, 1, 5), a1 = r2.shuffle(r3, 0, 4, 1, 5), a2 = r0.shuffle(r1, 2, 6, 3, 7), a3 = r2.shuffle(r3, 2, 6, 3, 7);
		return new Lane4(Lane.ofF32(a0.shuffle(a1, 0, 1, 4, 5)), Lane.ofF32(a0.shuffle(a1, 2, 3, 6, 7)), Lane.ofF32(a2.shuffle(a3, 0, 1, 4, 5)),
			Lane.ofF32(a2.shuffle(a3, 2, 3, 6, 7)));
	}

	public static inline function setVec4(d:Ptr, o:Int, stride:Int, v:Lane4) {
		var x = v.x.f32(), y = v.y.f32(), z = v.z.f32(), w = v.w.f32();
		var a0 = x.shuffle(y, 0, 4, 1, 5), a1 = z.shuffle(w, 0, 4, 1, 5), a2 = x.shuffle(y, 2, 6, 3, 7), a3 = z.shuffle(w, 2, 6, 3, 7);
		a0.shuffle(a1, 0, 1, 4, 5).storePtr(d, o);
		a0.shuffle(a1, 2, 3, 6, 7).storePtr(d, o + stride);
		a2.shuffle(a3, 0, 1, 4, 5).storePtr(d, o + 2 * stride);
		a2.shuffle(a3, 2, 3, 6, 7).storePtr(d, o + 3 * stride);
	}

	// a Float field of each element, lane by lane
	public static inline function f32(d:Ptr, o:Int, stride:Int):Lane
		return Lane.make(hxmc.unsafe.Mem.getF32(d, o), hxmc.unsafe.Mem.getF32(d, o + stride), hxmc.unsafe.Mem.getF32(d, o + 2 * stride),
			hxmc.unsafe.Mem.getF32(d, o + 3 * stride));

	public static inline function setF32(d:Ptr, o:Int, stride:Int, v:Lane) {
		hxmc.unsafe.Mem.setF32(d, o, v.get(0));
		hxmc.unsafe.Mem.setF32(d, o + stride, v.get(1));
		hxmc.unsafe.Mem.setF32(d, o + 2 * stride, v.get(2));
		hxmc.unsafe.Mem.setF32(d, o + 3 * stride, v.get(3));
	}

	public static inline function i32(d:Ptr, o:Int, stride:Int):LaneInt
		return LaneInt.make(hxmc.unsafe.Mem.getI32(d, o), hxmc.unsafe.Mem.getI32(d, o + stride), hxmc.unsafe.Mem.getI32(d, o + 2 * stride),
			hxmc.unsafe.Mem.getI32(d, o + 3 * stride));

	public static inline function setI32(d:Ptr, o:Int, stride:Int, v:LaneInt) {
		hxmc.unsafe.Mem.setI32(d, o, v.get(0));
		hxmc.unsafe.Mem.setI32(d, o + stride, v.get(1));
		hxmc.unsafe.Mem.setI32(d, o + 2 * stride, v.get(2));
		hxmc.unsafe.Mem.setI32(d, o + 3 * stride, v.get(3));
	}
}
