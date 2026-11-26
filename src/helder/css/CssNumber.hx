package helder.css;

using StringTools;

// Numbers as CSSOM writes them: browsers' six significant digits (printf's
// %.6g: 0.333333, 1e+06), an integer's every digit, infinity and NaN as
// calc() spells them.
class CssNumber {
	public static function format(x:Float, integer = false):String {
		if (Math.isNaN(x)) return "NaN";
		if (x == Math.POSITIVE_INFINITY) return "infinity";
		if (x == Math.NEGATIVE_INFINITY) return "-infinity";
		if (x == 0) return "0";
		var sign = x < 0 ? "-" : "", a = Math.abs(x);
		if (integer && a < 1e15) return sign + digits(Math.fround(a));
		var e = exponent(a);
		var scale = Math.pow(10, 5 - e);
		var r = Math.round(a * scale) / scale;
		if (r == 0) return "0";
		e = exponent(r);
		if (e < -4 || e >= 6) {
			var m = fixed(r / Math.pow(10, e), 5);
			// (rounding the mantissa can make it 10)
			if (m == "10") {
				m = "1";
				e++;
			}
			return sign + m + "e" + (e < 0 ? "-" : "+") + Std.string(e < 0 ? -e : e).lpad("0", 2);
		}
		return sign + fixed(r, 5 - e < 0 ? 0 : 5 - e);
	}

	static function exponent(a:Float):Int {
		var e = Math.floor(Math.log(a) / Math.log(10));
		// (log10 is off by one near powers of ten)
		if (Math.pow(10, e) > a) e--;
		if (Math.pow(10, e + 1) <= a) e++;
		return e;
	}

	// a, below 1e15, with at most `places` decimals, trailing zeros dropped
	static function fixed(a:Float, places:Int):String {
		var whole = Math.ffloor(a);
		var scale = Math.pow(10, places);
		var frac:Float = Math.round((a - whole) * scale);
		if (frac >= scale) {
			whole += 1;
			frac -= scale;
		}
		var s = digits(whole);
		if (frac == 0 || places == 0) return s;
		var f = digits(frac).lpad("0", places);
		var end = f.length;
		while (end > 0 && f.charCodeAt(end - 1) == "0".code) end--;
		return s + "." + f.substr(0, end);
	}

	// (a whole number's digits, without Int's 32-bit range)
	static function digits(a:Float):String {
		if (a < 2147483647) return Std.string(Std.int(a));
		var b = new StringBuf(), out = [];
		var x = a;
		while (x >= 1) {
			var q = Math.ffloor(x / 10);
			out.push(Std.int(x - q * 10));
			x = q;
		}
		out.reverse();
		for (d in out) b.add(d);
		return b.toString();
	}
}
