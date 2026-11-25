package helder.ui.draw;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;

// A frame's numbers as column streams (FrameWriter, FrameReader): each
// value in the stream of its kind, so that alike values sit together and
// deflate finds them. Ints: unsigned varints (LEB128), a signed one zigzagged.
// Floats: lossless; on a 1/64 grid (helder's boxes, mostly), a zigzagged
// varint of the step from the slot's last value (the same field of the
// last op that has it: a run of equal widths costs a byte each), else the
// value itself, raw, in a stream of its own.
class FrameStreams {
	public static inline var GRID = 64.0;
	// (quantized steps past this: raw, a varint's Float stays exact below 2^53)
	static inline var MAX = 4503599627370496.0;

	public final ops = new BytesBuffer();
	public final ints = new BytesBuffer();
	public final floats = new BytesBuffer();
	public final raws = new BytesBuffer();
	final last = new Map<Int, Float>();

	public function new() {}

	public inline function op(code:Int)
		ops.addByte(code);

	public function uint(v:Float)
		varint(ints, v);

	public inline function int(v:Int)
		uint(zigzag(v));

	public inline function bool(b:Bool)
		ints.addByte(b ? 1 : 0);

	// a colour: ARGB, unsigned
	public inline function color(c:Int)
		uint(c < 0 ? c + 4294967296.0 : c);

	public function string(s:String) {
		var b = Bytes.ofString(s);
		uint(b.length);
		ints.add(b);
	}

	// a float in a slot (its kind of field: the last value's step)
	public function float(slot:Int, v:Float) {
		var q = v * GRID;
		if (Math.isFinite(q) && q == Math.ffloor(q) && Math.abs(q) < MAX) {
			var p = last.get(slot) ?? 0.0;
			var d = q - p;
			if (Math.abs(d) < MAX) {
				last.set(slot, q);
				varint(floats, zigzag(d) * 2);
				return;
			}
		}
		varint(floats, 1);
		raws.addDouble(v);
	}

	// the streams, each its length first
	public function bytes():Bytes {
		var out = new BytesBuffer();
		for (b in [ops, ints, floats, raws]) {
			var s = b.getBytes();
			varint(out, s.length);
			out.add(s);
		}
		return out.getBytes();
	}

	static inline function zigzag(v:Float):Float
		return v >= 0 ? v * 2 : -v * 2 - 1;

	public static function varint(b:BytesBuffer, v:Float) {
		while (v >= 128) {
			var low = v - Math.ffloor(v / 128) * 128;
			b.addByte(Std.int(low) | 128);
			v = Math.ffloor(v / 128);
		}
		b.addByte(Std.int(v));
	}
}

// (its streams read back, in the order they were written)
class FrameInput {
	public final ops:Bytes;
	final ints:Bytes;
	final floats:Bytes;
	final raws:Bytes;
	public var at = 0;
	var ia = 0;
	var fa = 0;
	var ra = 0;
	final last = new Map<Int, Float>();

	public function new(b:Bytes) {
		var p = 0;
		function next():Bytes {
			var n = 0.0, k = 1.0;
			while (true) {
				var c = b.get(p++);
				n += (c & 127) * k;
				k *= 128;
				if (c < 128) break;
			}
			var s = b.sub(p, Std.int(n));
			p += Std.int(n);
			return s;
		}
		ops = next();
		ints = next();
		floats = next();
		raws = next();
	}

	public inline function done():Bool
		return at >= ops.length;

	public inline function op():Int
		return ops.get(at++);

	public function uint():Float {
		var r = readVarint(ints, ia);
		ia = r.at;
		return r.v;
	}

	public function int():Int {
		var z = uint();
		return Std.int(z % 2 == 0 ? z / 2 : -(z + 1) / 2);
	}

	public inline function bool():Bool
		return ints.get(ia++) == 1;

	public function color():Int {
		var v = uint();
		return v >= 2147483648.0 ? Std.int(v - 4294967296.0) : Std.int(v);
	}

	public function string():String {
		var n = Std.int(uint());
		var s = ints.getString(ia, n);
		ia += n;
		return s;
	}

	// (n bytes as they were added to the ints)
	public function raw(n:Int):Bytes {
		var s = ints.sub(ia, n);
		ia += n;
		return s;
	}

	public function float(slot:Int):Float {
		var r = readVarint(floats, fa);
		fa = r.at;
		if (r.v % 2 == 1) {
			var v = raws.getDouble(ra);
			ra += 8;
			return v;
		}
		var z = r.v / 2;
		var d = z % 2 == 0 ? z / 2 : -(z + 1) / 2;
		var q = (last.get(slot) ?? 0.0) + d;
		last.set(slot, q);
		return q / FrameStreams.GRID;
	}

	static function readVarint(b:Bytes, at:Int):{v:Float, at:Int} {
		var n = 0.0, k = 1.0;
		while (true) {
			var c = b.get(at++);
			n += (c & 127) * k;
			k *= 128;
			if (c < 128) break;
		}
		return {v: n, at: at};
	}
}
