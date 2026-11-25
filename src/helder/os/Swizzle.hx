package helder.os;

import hxmc.simd.I32x4;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

// RGBA8 pixels as BGRA8 (X11's, Wayland's and Windows' 32-bit pixels:
// little-endian 0xAARRGGBB), four at a time
@:hxmc.unsafe(gc)
class Swizzle {
	public static function bgra(dst:Ptr, src:Ptr, n:Int) {
		var ga = I32x4.splat(0xFF00FF00), b = I32x4.splat(0xFF), i = 0;
		while (i + 4 <= n) {
			var v = I32x4.loadPtr(src, 4 * i);
			((v & ga) | ((v & b) << 16) | ((v >>> 16) & b)).storePtr(dst, 4 * i);
			i += 4;
		}
		while (i < n) {
			var v = Mem.getI32(src, 4 * i);
			Mem.setI32(dst, 4 * i, (v & 0xFF00FF00) | ((v & 0xFF) << 16) | ((v >>> 16) & 0xFF));
			i++;
		}
	}
}
