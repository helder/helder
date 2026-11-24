package helder.gfx.soft;

import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

// A uniform block's arrays read by an index (std140: 16 bytes a Vec4, 64 a
// Mat4), held in the array as a GPU's robust access does
@:hxmc.unsafe(gc)
class Uniforms {
	public static inline function index(i:Int, n:Int):Int
		return i < 0 ? 0 : i >= n ? n - 1 : i;

	// each lane's element of a Vec4 array at off
	public static function vec4s(p:Ptr, off:Int, i:LaneInt, n:Int):Lane4 {
		var a = off + 16 * index(i.get(0), n), b = off + 16 * index(i.get(1), n), c = off + 16 * index(i.get(2), n), d = off + 16 * index(i.get(3), n);
		inline function lane(k:Int):Lane
			return Lane.make(Mem.getF32(p, a + k), Mem.getF32(p, b + k), Mem.getF32(p, c + k), Mem.getF32(p, d + k));
		return new Lane4(lane(0), lane(4), lane(8), lane(12));
	}

	public static function mats(p:Ptr, off:Int, i:LaneInt, n:Int):LaneMat {
		var at = off + 0, k = LaneInt.make(index(i.get(0), n) * 4, index(i.get(1), n) * 4, index(i.get(2), n) * 4, index(i.get(3), n) * 4);
		return new LaneMat(vec4s(p, at, k, 4 * n), vec4s(p, at, k + LaneInt.splat(1), 4 * n), vec4s(p, at, k + LaneInt.splat(2), 4 * n),
			vec4s(p, at, k + LaneInt.splat(3), 4 * n));
	}
}
