package helder.text;

import haxe.io.Bytes;
import helder.text.ColorPaint;

// COLR (versions 0 and 1) and CPAL read: a base glyph's paint (ColorPaint),
// version 1's first, else version 0's layers; the palettes, each a colour
// per entry (0xAARRGGBB) with its flags (light, dark). Version 1's variable
// paints are read at their default values (no deltas applied). The font is
// untrusted: a read past a table is an error ("Colr: ..."), a paint graph is
// at most DEPTH deep, a glyph's reference back into a cycle nothing.
class Colr {
	static inline var DEPTH = 64;

	final data:Bytes;
	final colr:Int;
	final end:Int;
	final version:Int;
	final baseList:Int;
	final layerList:Int;
	final clipList:Int;
	// (paints by offset: a table shared in the graph read once)
	final read = new Map<Int, ColorPaint>();
	final glyphs = new Map<Int, Null<ColorPaint>>();

	public final palettes:Array<Array<Int>> = [];
	public final paletteFlags:Array<Int> = [];
	public var entries(default, null) = 0;

	public function new(data:Bytes, colr:Int, colrLength:Int, cpal:Int, cpalLength:Int) {
		this.data = data;
		this.colr = colr;
		end = colr + colrLength;
		if (colr < 0 || colrLength < 14 || end > data.length || end < colr) throw "Colr: COLR past the font";
		version = u16(colr);
		baseList = version >= 1 ? offset32(colr, u32(colr + 14)) : 0;
		layerList = version >= 1 ? offset32(colr, u32(colr + 18)) : 0;
		clipList = version >= 1 ? offset32(colr, u32(colr + 22)) : 0;
		if (cpal != -1) palettesOf(cpal, cpal + cpalLength);
	}

	// a glyph's paint, null when it has none
	public function paint(g:Int):Null<ColorPaint> {
		if (glyphs.exists(g)) return glyphs.get(g);
		var p = try base(g, []) catch (_:String) null;
		glyphs.set(g, p);
		return p;
	}

	// a glyph's clip box (version 1's ClipList: xMin, yMin, xMax, yMax), null: none
	public function clipBox(g:Int):Null<Array<Float>> {
		if (clipList == 0) return null;
		var n = u32(clipList + 1);
		for (i in 0...n) {
			var r = clipList + 5 + 7 * i;
			if (g < u16(r) || g > u16(r + 2)) continue;
			var b = clipList + u24(r + 4);
			return [s16(b + 1), s16(b + 3), s16(b + 5), s16(b + 7)];
		}
		return null;
	}

	function base(g:Int, seen:Array<Int>):Null<ColorPaint> {
		// (a glyph that refers back to one being read: nothing there, as Skia draws a cycle)
		if (seen.contains(g)) return null;
		if (seen.length > DEPTH) throw "Colr: glyphs nested too deep";
		if (baseList != 0) {
			var lo = 0, hi = u32(baseList) - 1;
			while (lo <= hi) {
				var mid = (lo + hi) >> 1, r = baseList + 4 + 6 * mid, id = u16(r);
				if (id < g) lo = mid + 1 else if (id > g) hi = mid - 1 else return paintAt(baseList + u32(r + 2), seen.concat([g]), 0);
			}
		}
		return layers0(g);
	}

	// (version 0: the base glyph's layers, each a glyph in a palette entry's colour)
	function layers0(g:Int):Null<ColorPaint> {
		var n = u16(colr + 2), records = colr + u32(colr + 4), layers = colr + u32(colr + 8), count = u16(colr + 12);
		var lo = 0, hi = n - 1;
		while (lo <= hi) {
			var mid = (lo + hi) >> 1, r = records + 6 * mid, id = u16(r);
			if (id < g) lo = mid + 1 else if (id > g) hi = mid - 1 else {
				var first = u16(r + 2), k = u16(r + 4);
				if (first + k > count) throw "Colr: layers past the table";
				return Layers([for (i in 0...k) Glyph(u16(layers + 4 * (first + i)), Solid(u16(layers + 4 * (first + i) + 2), 1))]);
			}
		}
		return null;
	}

	function paintAt(at:Int, seen:Array<Int>, depth:Int):ColorPaint {
		if (depth > DEPTH) throw "Colr: a paint graph too deep";
		var known = read.get(at);
		if (known != null) return known;
		var p = paintOf(at, seen, depth + 1);
		read.set(at, p);
		return p;
	}

	function child(at:Int, field:Int, seen:Array<Int>, depth:Int):ColorPaint
		return paintAt(at + u24(at + field), seen, depth);

	function paintOf(at:Int, seen:Array<Int>, depth:Int):ColorPaint {
		inline function f2(k:Int)
			return s16(at + k) / 16384;
		return switch u8(at) {
			case 1:
				var n = u8(at + 1), first = u32(at + 2);
				if (layerList == 0 || first + n > u32(layerList)) throw "Colr: layers past the list";
				Layers([for (i in 0...n) paintAt(layerList + u32(layerList + 4 + 4 * (first + i)), seen, depth)]);
			case 2 | 3: Solid(u16(at + 1), f2(3));
			case 4 | 5:
				Linear(line(at + u24(at + 1), u8(at) == 5), s16(at + 4), s16(at + 6), s16(at + 8), s16(at + 10), s16(at + 12), s16(at + 14));
			case 6 | 7:
				Radial(line(at + u24(at + 1), u8(at) == 7), s16(at + 4), s16(at + 6), u16(at + 8), s16(at + 10), s16(at + 12), u16(at + 14));
			case 8 | 9:
				// (its angles biased by a half turn: 360 written as 1.0)
				Sweep(line(at + u24(at + 1), u8(at) == 9), s16(at + 4), s16(at + 6), (f2(8) + 1) * 180, (f2(10) + 1) * 180);
			case 10: Glyph(u16(at + 4), child(at, 1, seen, depth));
			// (another glyph's paint, inside its clip box)
			case 11:
				var g = u16(at + 1), p = base(g, seen) ?? Layers([]), box = clipBox(g);
				box == null ? p : Clip(box[0], box[1], box[2], box[3], p);
			case 12 | 13:
				var m = at + u24(at + 4);
				inline function fixed(k:Int)
					return u32(m + k) / 65536;
				Transform(fixed(0), fixed(4), fixed(8), fixed(12), fixed(16), fixed(20), child(at, 1, seen, depth));
			case 14 | 15: Transform(1, 0, 0, 1, s16(at + 4), s16(at + 6), child(at, 1, seen, depth));
			case 16 | 17: Transform(f2(4), 0, 0, f2(6), 0, 0, child(at, 1, seen, depth));
			case 18 | 19: around(s16(at + 8), s16(at + 10), f2(4), 0, 0, f2(6), child(at, 1, seen, depth));
			case 20 | 21: Transform(f2(4), 0, 0, f2(4), 0, 0, child(at, 1, seen, depth));
			case 22 | 23: around(s16(at + 6), s16(at + 8), f2(4), 0, 0, f2(4), child(at, 1, seen, depth));
			case 24 | 25:
				var a = f2(4) * Math.PI;
				Transform(Math.cos(a), Math.sin(a), -Math.sin(a), Math.cos(a), 0, 0, child(at, 1, seen, depth));
			case 26 | 27:
				var a = f2(4) * Math.PI;
				around(s16(at + 6), s16(at + 8), Math.cos(a), Math.sin(a), -Math.sin(a), Math.cos(a), child(at, 1, seen, depth));
			case 28 | 29: Transform(1, Math.tan(f2(6) * Math.PI), -Math.tan(f2(4) * Math.PI), 1, 0, 0, child(at, 1, seen, depth));
			case 30 | 31:
				around(s16(at + 8), s16(at + 10), 1, Math.tan(f2(6) * Math.PI), -Math.tan(f2(4) * Math.PI), 1, child(at, 1, seen, depth));
			case 32: Composite(u8(at + 4), child(at, 1, seen, depth), child(at, 5, seen, depth));
			case f: throw 'Colr: no paint format $f';
		}
	}

	// (a transform about (cx, cy): moved there, transformed, moved back)
	static function around(cx:Float, cy:Float, xx:Float, yx:Float, xy:Float, yy:Float, p:ColorPaint):ColorPaint
		return Transform(xx, yx, xy, yy, cx - xx * cx - xy * cy, cy - yx * cx - yy * cy, p);

	// a ColorLine (VarColorLine: each stop followed by its variation index)
	function line(at:Int, variable:Bool):ColorLine {
		var n = u16(at + 1), size = variable ? 10 : 6;
		return {extend: u8(at) > 2 ? 0 : u8(at), stops: [for (i in 0...n) {
			var s = at + 3 + size * i;
			{offset: s16(s) / 16384, entry: u16(s + 2), alpha: s16(s + 4) / 16384};
		}]};
	}

	function palettesOf(cpal:Int, cpalEnd:Int) {
		if (cpal < 0 || cpalEnd > data.length || cpal + 12 > cpalEnd) throw "Colr: CPAL past the font";
		var version = get16(cpal), n = get16(cpal + 2), count = get16(cpal + 4), records = get16(cpal + 6), first = cpal + get32(cpal + 8);
		if (cpal + 12 + 2 * count > cpalEnd || first < cpal) throw "Colr: CPAL's palettes past it";
		entries = n;
		var types = version >= 1 && cpal + 16 + 2 * count <= cpalEnd ? get32(cpal + 12 + 2 * count) : 0;
		for (p in 0...count) {
			var start = get16(cpal + 12 + 2 * p);
			if (start + n > records || first + 4 * (start + n) > cpalEnd) throw "Colr: a palette past its records";
			palettes.push([for (i in 0...n) {
				var c = first + 4 * (start + i);
				// (BGRA)
				data.get(c + 3) << 24 | data.get(c + 2) << 16 | data.get(c + 1) << 8 | data.get(c);
			}]);
			paletteFlags.push(types > 0 && cpal + types + 4 * p + 4 <= cpalEnd ? get32(cpal + types + 4 * p) : 0);
		}
	}

	// ---- reads within COLR (else an error)

	inline function need(at:Int, n:Int)
		if (at < colr || at + n > end) throw "Colr: a read past COLR";

	function offset32(from:Int, o:Int):Int
		return o == 0 ? 0 : from + o;

	function u8(at:Int):Int {
		need(at, 1);
		return data.get(at);
	}

	function u16(at:Int):Int {
		need(at, 2);
		return data.get(at) << 8 | data.get(at + 1);
	}

	function s16(at:Int):Int {
		var v = u16(at);
		return v >= 0x8000 ? v - 0x10000 : v;
	}

	function u24(at:Int):Int {
		need(at, 3);
		return data.get(at) << 16 | data.get(at + 1) << 8 | data.get(at + 2);
	}

	function u32(at:Int):Int {
		need(at, 4);
		return data.get(at) << 24 | data.get(at + 1) << 16 | data.get(at + 2) << 8 | data.get(at + 3);
	}

	// (CPAL's, its own bounds checked by palettesOf)
	inline function get16(at:Int):Int
		return data.get(at) << 8 | data.get(at + 1);

	inline function get32(at:Int):Int
		return data.get(at) << 24 | data.get(at + 1) << 16 | data.get(at + 2) << 8 | data.get(at + 3);
}
