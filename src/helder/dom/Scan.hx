package helder.dom;

#if !(eval || interp)
import hxmc.rt.StrView;
import hxmc.simd.U16x8;
import hxmc.simd.U8x16;
#end

// The tokenizer's text runs: the next unit that ends one (a, b, NUL or CR),
// 16 units at a time (8 in a string of two bytes a unit). A kernel
// (@:hxmc.kernel): it reads the string through StrView's spans, each access
// checked, and touches no GC object; Eval scans a unit at a time.
@:noCompletion class Scan {
	// the first index in s[from, to) holding a, b, 0 or 13 (to: none)
	public static function stop(s:String, from:Int, to:Int, a:Int, b:Int):Int {
		#if (eval || interp)
		var i = from;
		while (i < to) {
			var c = StringTools.fastCodeAt(s, i);
			if (c == a || c == b || c == 0 || c == 13) return i;
			i++;
		}
		return to;
		#else
		return find(s, from, to, a, b);
		#end
	}

	#if !(eval || interp)
	@:hxmc.kernel static function find(s:String, from:Int, to:Int, a:Int, b:Int):Int {
		var i = from;
		if (StrView.isOne(s)) {
			var u = StrView.units1(s);
			var va = U8x16.splat(a), vb = U8x16.splat(b), vz = U8x16.zero(), vr = U8x16.splat(13);
			while (i + 16 <= to) {
				var v = U8x16.loadSpan(u, i);
				var m = (v.eq(va) | v.eq(vb) | v.eq(vz) | v.eq(vr)).bitmask();
				if (m != 0) return i + low(m);
				i += 16;
			}
			while (i < to) {
				var c:Int = u[i];
				if (c == a || c == b || c == 0 || c == 13) return i;
				i++;
			}
			return to;
		}
		var w = StrView.units2(s);
		var bytes = w.reinterpret();
		var va = U16x8.splat(a), vb = U16x8.splat(b), vz = U16x8.zero(), vr = U16x8.splat(13);
		while (i + 8 <= to) {
			var v = U16x8.loadSpan(bytes, 2 * i);
			var m = (v.eq(va) | v.eq(vb) | v.eq(vz) | v.eq(vr)).asI8x16().bitmask();
			if (m != 0) return i + (low(m) >> 1);
			i += 8;
		}
		while (i < to) {
			var c:Int = w[i];
			if (c == a || c == b || c == 0 || c == 13) return i;
			i++;
		}
		return to;
	}

	// the lowest set bit's index
	static inline function low(m:Int):Int {
		var k = 0;
		while (m & 1 == 0) {
			m >>>= 1;
			k++;
		}
		return k;
	}
	#end
}
