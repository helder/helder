package helder.css;

// CssPacked's encoding, written (CssSheetData at build time).
@:allow(helder.css)
class CssPackedWriter {
	final out = new StringBuf();
	final pool = new Map<String, Int>();
	var pooled = 0;

	public function new() {}

	public function toString():String
		return out.toString();

	public function uint(n:Int) {
		// (unsigned: a negative n is a zigzagged int's top half)
		while (n < 0 || n >= 63) {
			out.addChar(64 + (n & 63));
			n >>>= 6;
		}
		out.addChar(1 + n);
	}

	public function int(n:Int)
		uint((n << 1) ^ (n >> 31));

	public function bool(b:Bool)
		uint(b ? 1 : 0);

	public function str(s:String) {
		var k = pool.get(s);
		if (k != null) return uint(k + 1);
		uint(0);
		var ascii = true;
		for (i in 0...s.length) {
			var c = StringTools.fastCodeAt(s, i);
			if (c < 1 || c > 127) ascii = false;
		}
		uint(ascii ? s.length << 1 : (s.length << 1) | 1);
		if (ascii) out.add(s) else for (i in 0...s.length) uint(StringTools.fastCodeAt(s, i));
		pool.set(s, pooled++);
	}

	public function nstr(s:Null<String>) {
		bool(s != null);
		if (s != null) str(s);
	}

	public function float(f:Float) {
		if (Math.isFinite(f) && f == Math.ffloor(f) && Math.abs(f) < 1e9 && !(f == 0 && 1 / f < 0)) {
			uint(0);
			int(Std.int(f));
		} else {
			uint(1);
			str(Math.isNaN(f) ? "NaN" : f == Math.POSITIVE_INFINITY ? "Infinity" : f == Math.NEGATIVE_INFINITY ? "-Infinity" : Std.string(f));
		}
	}

	public function list<T>(xs:Array<T>, f:T->Void) {
		uint(xs.length);
		for (x in xs) f(x);
	}

	public function nlist<T>(xs:Null<Array<T>>, f:T->Void) {
		bool(xs != null);
		if (xs != null) list(xs, f);
	}
}
