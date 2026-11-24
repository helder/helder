package helder.gfx.soft;

import hxmc.unsafe.LibC;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

// The conversions of the formats: half floats (IEEE 754 binary16, rounded
// to nearest even as GPUs store them) and sRGB (its exact curve; the
// 256 decoded values in a table outside the collector's heap, which tiles
// read while a collection may run)
@:hxmc.unsafe(gc)
class Formats {
	public static function half(h:Int):Float {
		var s = (h >> 15) & 1 == 0 ? 1.0 : -1.0, e = (h >> 10) & 31, m = h & 1023;
		if (e == 0) return s * m * 5.9604644775390625e-8;
		if (e == 31) return m == 0 ? s * Math.POSITIVE_INFINITY : Math.NaN;
		return s * (1 + m / 1024) * Math.pow(2, e - 15);
	}

	// f's half float bits (rounded to nearest even; overflow to infinity)
	public static function toHalf(f:Float):Int {
		var bits = Mem.f32Bits(f);
		var s = (bits >>> 16) & 0x8000, e = (bits >>> 23) & 255, m = bits & 0x7FFFFF;
		if (e == 255) return s | 0x7C00 | (m != 0 ? 0x200 : 0);
		var he = e - 127 + 15;
		if (he >= 31) return s | 0x7C00;
		if (he <= 0) {
			if (he < -10) return s;
			m |= 0x800000;
			var shift = 14 - he, half = m >>> shift, rest = m & ((1 << shift) - 1), mid = 1 << (shift - 1);
			if (rest > mid || (rest == mid && half & 1 != 0)) half++;
			return s | half;
		}
		var half = (he << 10) | (m >>> 13), rest = m & 0x1FFF;
		if (rest > 0x1000 || (rest == 0x1000 && half & 1 != 0)) half++;
		return s | half;
	}

	// f as a half float stores it
	public static inline function roundHalf(f:Float):Float
		return half(toHalf(f));

	public static function decode(c:Float):Float
		return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);

	public static function encode(l:Float):Float
		return l <= 0.0031308 ? l * 12.92 : 1.055 * Math.pow(l, 1 / 2.4) - 0.055;

	// (the 256 sRGB values decoded, as float32s; then the 255 midpoints
	// between them in linear values: a value's code is how many it passes)
	static var table = Ptr.nil();

	public static function srgb():Ptr {
		if (!table.isNull()) return table;
		var t:Ptr = LibC.malloc(4 * 512);
		for (i in 0...256)
			Mem.setF32(t, 4 * i, decode(i / 255));
		for (i in 0...255)
			Mem.setF32(t, 1024 + 4 * i, decode((i + 0.5) / 255));
		Mem.setF32(t, 1024 + 4 * 255, 2);
		return table = t;
	}

	// a linear value's sRGB code (0..255), its nearest: the midpoints it passes
	public static inline function srgbCode(t:Ptr, l:Float):Int {
		var lo = 0, n = 256;
		while (n > 1) {
			var h = n >> 1;
			if ((Mem.getF32(t, 1024 + 4 * (lo + h - 1)) : Float) <= l) lo += h;
			n -= h;
		}
		return lo;
	}
}
