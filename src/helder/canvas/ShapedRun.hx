package helder.canvas;

import haxe.io.Bytes;
import helder.text.FontFile;

// Glyphs of one face at one size as a GlyphText painter takes them: each
// glyph's id, its pen in the painter's units (y down, on its baseline) and
// the characters of text it shows (UTF-16 units from start to end; a
// ligature's several, a cluster's glyphs after its first none of their own
// but the same range), in the order drawn (visual: right to left text
// reversed), read by index (id(i), x(i), ...). A glyph is drawn as face.outline through
// [size / unitsPerEm * scaleX, 0, skew * size / unitsPerEm * scaleX, -size / unitsPerEm, x, y],
// skew 0.25 an oblique's. Its columns are packed (20 bytes a glyph; a y
// only where one is not 0): a long document's lines hold millions.
class ShapedRun {
	public var face:FontFile;
	public var size = 0.0;
	public var scaleX = 1.0;
	public var skew = 0.0;
	// synthesized bold: the outlines also stroked this wide, in pixels (0: none)
	public var bold = 0.0;
	// a colour font's palette, its entries' colours (font-palette: null, the font's first)
	public var palette:Null<Array<Int>> = null;
	public var text = "";
	public var count(default, null) = 0;
	// (per glyph: its id, start and end (3 Int32), its x (a Float64); its y apart, while one isn't 0)
	var ints:Bytes;
	var xs:Bytes;
	var ys:Null<Bytes> = null;

	static final EMPTY = Bytes.alloc(0);

	public function new(face:FontFile, size:Float) {
		this.face = face;
		this.size = size;
		ints = EMPTY;
		xs = EMPTY;
	}

	public inline function id(i:Int):Int
		return ints.getInt32(12 * i);

	public inline function start(i:Int):Int
		return ints.getInt32(12 * i + 4);

	public inline function end(i:Int):Int
		return ints.getInt32(12 * i + 8);

	public inline function x(i:Int):Float
		return xs.getDouble(8 * i);

	public inline function y(i:Int):Float
		return ys == null ? 0 : ys.getDouble(8 * i);

	public function clear()
		count = 0;

	// (room for n glyphs at once: grown a glyph at a time, each push copies)
	public function reserve(n:Int) {
		if (xs.length >= 8 * n) return;
		ints = grown(ints, 12 * n);
		xs = grown(xs, 8 * n);
		if (ys != null) ys = grown(ys, 8 * n);
	}

	static function grown(b:Bytes, n:Int):Bytes {
		var c = Bytes.alloc(n);
		c.blit(0, b, 0, b.length < n ? b.length : n);
		return c;
	}

	public function push(id:Int, x:Float, y:Float, start:Int, end:Int) {
		if (8 * (count + 1) > xs.length) reserve(count < 4 ? 8 : 2 * count);
		var k = count++;
		ints.setInt32(12 * k, id);
		ints.setInt32(12 * k + 4, start);
		ints.setInt32(12 * k + 8, end);
		xs.setDouble(8 * k, x);
		if (y != 0 && ys == null) {
			ys = Bytes.alloc(xs.length);
			ys.fill(0, ys.length, 0);
		}
		if (ys != null) ys.setDouble(8 * k, y);
	}

	// the characters its glyphs show: its text from the first of them to the last
	public function shown():String {
		if (count == 0) return "";
		var lo = start(0), hi = end(0);
		for (i in 1...count) {
			if (start(i) < lo) lo = start(i);
			if (end(i) > hi) hi = end(i);
		}
		return text.substring(lo, hi);
	}

	// a copy of its own (a recording outlives the caller's buffers)
	public function copy():ShapedRun {
		var r = new ShapedRun(face, size);
		r.scaleX = scaleX;
		r.skew = skew;
		r.bold = bold;
		r.palette = palette;
		r.text = text;
		r.reserve(count);
		for (i in 0...count)
			r.push(id(i), x(i), y(i), start(i), end(i));
		return r;
	}
}
