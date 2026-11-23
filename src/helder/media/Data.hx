package helder.media;

import haxe.io.Bytes;

// Big-endian reads over bytes, each checked against the end: a value past
// it is a MediaError, never a read outside. Numbers past 32 bits are
// Floats (exact to 2^53). EBML's variable-length integers too.
class Data {
	public final bytes:Bytes;
	public var pos:Int;
	public final end:Int;

	public function new(bytes:Bytes, pos = 0, end = -1) {
		this.bytes = bytes;
		this.pos = pos;
		this.end = end < 0 || end > bytes.length ? bytes.length : end;
		if (pos < 0 || pos > this.end) throw new MediaError("truncated");
	}

	public var left(get, never):Int;

	inline function get_left()
		return end - pos;

	inline function need(n:Int)
		if (n < 0 || n > end - pos) throw new MediaError("truncated");

	public function sub(n:Int):Data {
		need(n);
		var d = new Data(bytes, pos, pos + n);
		pos += n;
		return d;
	}

	public function skip(n:Int) {
		need(n);
		pos += n;
	}

	public function u8():Int {
		need(1);
		return bytes.get(pos++);
	}

	public function u16():Int {
		need(2);
		var v = (bytes.get(pos) << 8) | bytes.get(pos + 1);
		pos += 2;
		return v;
	}

	public function u24():Int {
		need(3);
		var v = (bytes.get(pos) << 16) | (bytes.get(pos + 1) << 8) | bytes.get(pos + 2);
		pos += 3;
		return v;
	}

	public function u32():Float {
		need(4);
		var v = bytes.get(pos) * 16777216.0 + ((bytes.get(pos + 1) << 16) | (bytes.get(pos + 2) << 8) | bytes.get(pos + 3));
		pos += 4;
		return v;
	}

	// a count or a size: at most 2^31 - 1
	public function count():Int {
		var v = u32();
		if (v > 0x7fffffff) throw new MediaError("count out of range");
		return Std.int(v);
	}

	public function i32():Int {
		need(4);
		var v = (bytes.get(pos) << 24) | (bytes.get(pos + 1) << 16) | (bytes.get(pos + 2) << 8) | bytes.get(pos + 3);
		pos += 4;
		return v;
	}

	public function i16():Int {
		var v = u16();
		return v >= 0x8000 ? v - 0x10000 : v;
	}

	public function u64():Float
		return u32() * 4294967296.0 + u32();

	public function i64():Float {
		var hi = i32();
		return hi * 4294967296.0 + u32();
	}

	public function f32():Float {
		need(4);
		var v = haxe.io.FPHelper.i32ToFloat(i32());
		return v;
	}

	public function f64():Float {
		var hi = i32(), lo = i32();
		return haxe.io.FPHelper.i64ToDouble(lo, hi);
	}

	public function fourcc():String {
		need(4);
		var s = String.fromCharCode(bytes.get(pos)) + String.fromCharCode(bytes.get(pos + 1)) + String.fromCharCode(bytes.get(pos + 2))
			+ String.fromCharCode(bytes.get(pos + 3));
		pos += 4;
		return s;
	}

	public function take(n:Int):Bytes {
		need(n);
		var b = bytes.sub(pos, n);
		pos += n;
		return b;
	}

	// n bytes as text (EBML's strings: up to the first zero)
	public function text(n:Int):String {
		need(n);
		var e = pos, stop = pos + n;
		while (e < stop && bytes.get(e) != 0) e++;
		var s = bytes.getString(pos, e - pos);
		pos = stop;
		return s;
	}

	// an EBML element ID, its marker bits kept (0x1A45DFA3)
	public function id():Int {
		var first = u8(), len = first >= 0x80 ? 1 : first >= 0x40 ? 2 : first >= 0x20 ? 3 : first >= 0x10 ? 4 : 0;
		if (len == 0) throw new MediaError("bad element ID");
		var v = first;
		for (_ in 1...len) v = (v << 8) | u8();
		return v;
	}

	// an EBML size: -1 for unknown (all its bits set)
	public function vsize():Float {
		var first = u8(), len = 1, mask = 0x80;
		while (len <= 8 && first & mask == 0) {
			len++;
			mask >>= 1;
		}
		if (len > 8) throw new MediaError("bad element size");
		var v:Float = first & (mask - 1), all = v == mask - 1;
		for (_ in 1...len) {
			var b = u8();
			if (b != 0xff) all = false;
			v = v * 256 + b;
		}
		return all ? -1 : v;
	}

	// a lacing size difference: a signed EBML number
	public function vsigned():Float {
		var first = u8(), len = 1, mask = 0x80;
		while (len <= 8 && first & mask == 0) {
			len++;
			mask >>= 1;
		}
		if (len > 8) throw new MediaError("bad lace size");
		var v:Float = first & (mask - 1), bias = 0.5;
		for (_ in 1...len) v = v * 256 + u8();
		for (_ in 0...7 * len) bias *= 2;
		return v - (bias - 1);
	}

	// an EBML unsigned or signed integer, or float, of n bytes
	public function uint(n:Int):Float {
		if (n > 8) throw new MediaError("integer too long");
		var v = 0.0;
		for (_ in 0...n) v = v * 256 + u8();
		return v;
	}

	public function sint(n:Int):Float {
		if (n == 0) return 0;
		var v = uint(n), top = 0.5;
		for (_ in 0...8 * n) top *= 2;
		return v >= top ? v - 2 * top : v;
	}

	public function float(n:Int):Float
		return n == 4 ? f32() : n == 8 ? f64() : n == 0 ? 0 : throw new MediaError("bad float");
}
