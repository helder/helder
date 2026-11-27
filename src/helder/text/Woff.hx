package helder.text;

import haxe.io.Bytes;
import helder.compress.Brotli;
import helder.image.Inflate;

// WOFF 1.0 and WOFF2 fonts, as the sfnt they wrap (FontFile reads that;
// FontFile.parse and faceCount unwrap them by their signature). WOFF's
// tables are zlib's, WOFF2's one Brotli stream, its glyf and loca (and
// hmtx, when so transformed) rebuilt from their transformed form: points
// from triplets, bounding boxes computed where none is given, loca from
// the glyphs' sizes. A WOFF2 collection is a .ttc. Untrusted input: every
// offset and count is checked, and the sfnt is at most MAX bytes; a damaged
// file throws "Woff: ...".
class Woff {
	public static inline var MAX = 64 << 20;

	public static function is(data:Bytes):Bool
		return data.length >= 4 && (data.getString(0, 4) == "wOFF" || data.getString(0, 4) == "wOF2");

	// the sfnt (or .ttc) of a WOFF or WOFF2 file
	public static function sfnt(data:Bytes):Bytes {
		if (!is(data)) throw "Woff: not a WOFF file";
		var c = cache;
		if (c != null && c.data == data) return c.sfnt;
		var s = data.getString(0, 4) == "wOF2" ? woff2(data) : woff1(data);
		cache = {data: data, sfnt: s};
		return s;
	}

	// (the last one: faceCount then parse unwrap the same bytes once)
	static var cache:Null<{data:Bytes, sfnt:Bytes}> = null;

	// --- WOFF 1.0

	static function woff1(data:Bytes):Bytes {
		var r = new Reader(data, 0, data.length);
		r.skip(4);
		var flavor = r.u32();
		r.skip(4);
		var n = r.u16();
		var tables = [];
		r.at = 44;
		for (_ in 0...n) {
			var tag = r.tag(), offset = r.u32(), stored = r.u32(), length = r.u32();
			r.skip(4);
			if (offset < 0 || stored < 0 || length < 0 || offset + stored > data.length || offset + stored < 0) throw "Woff: a table past the file";
			if (stored > length) throw "Woff: a table larger stored than whole";
			if (length > MAX) throw "Woff: a table too large";
			var t = stored == length ? data.sub(offset, length) : try Inflate.exact(data.sub(offset, stored), length, true) catch (e:String) throw 'Woff: $e';
			tables.push({tag: tag, data: t});
		}
		return build([{flavor: flavor, tables: tables}]);
	}

	// --- WOFF2

	static final TAGS = ["cmap", "head", "hhea", "hmtx", "maxp", "name", "OS/2", "post", "cvt ", "fpgm", "glyf", "loca", "prep", "CFF ", "VORG", "EBDT",
		"EBLC", "gasp", "hdmx", "kern", "LTSH", "PCLT", "VDMX", "vhea", "vmtx", "BASE", "GDEF", "GPOS", "GSUB", "EBSC", "JSTF", "MATH", "CBDT", "CBLC", "COLR",
		"CPAL", "SVG ", "sbix", "acnt", "avar", "bdat", "bloc", "bsln", "cvar", "fdsc", "feat", "fmtx", "fvar", "gvar", "hsty", "just", "lcar", "mort", "morx",
		"opbd", "prop", "trak", "Zapf", "Silf", "Glat", "Gloc", "Feat", "Sill"];

	static function woff2(data:Bytes):Bytes {
		var r = new Reader(data, 0, data.length);
		r.skip(4);
		var flavor = r.u32();
		r.skip(4);
		var n = r.u16();
		r.skip(6);
		var compressed = r.u32();
		r.at = 48;
		// (each entry: its tag, transform, where in the stream and how long there, whole)
		var entries = [], total = 0;
		for (_ in 0...n) {
			var flags = r.u8(), t = flags & 63, version = flags >> 6;
			var tag = t == 63 ? r.tag() : TAGS[t];
			var length = r.base128(), stored = length;
			var glyfOrLoca = tag == "glyf" || tag == "loca";
			var transformed = glyfOrLoca ? version == 0 : version != 0;
			if (transformed) {
				if (!glyfOrLoca && !(tag == "hmtx" && version == 1)) throw 'Woff: no transform $version of $tag';
				stored = r.base128();
				if (tag == "loca" && stored != 0) throw "Woff: a transformed loca is not empty";
			} else if (glyfOrLoca && version != 3) throw 'Woff: no transform $version of $tag';
			if (length > MAX || stored > MAX) throw "Woff: a table too large";
			entries.push({tag: tag, transformed: transformed, at: total, stored: stored, length: length});
			total += stored;
			if (total > MAX) throw "Woff: tables too large";
		}
		// (a collection's fonts: each a flavor and its tables' entries)
		var fonts:Array<{flavor:Int, tables:Array<Int>}> = [];
		if (flavor == 0x74746366) {
			r.skip(4);
			for (_ in 0...r.u255()) {
				var count = r.u255(), f = r.u32();
				var tables = [for (_ in 0...count) r.u255()];
				for (i in tables) if (i >= n) throw "Woff: a collection's table is none";
				fonts.push({flavor: f, tables: tables});
			}
			if (fonts.length == 0) throw "Woff: a collection of no fonts";
		} else fonts.push({flavor: flavor, tables: [for (i in 0...n) i]});
		if (r.at + compressed > data.length) throw "Woff: the tables past the file";
		var stream = Brotli.exact(data, r.at, compressed, total);
		// (each entry's table rebuilt once: a collection's fonts share them)
		var made = new Map<Int, Bytes>(), xMins = new Map<Int, Array<Int>>();
		function raw(i:Int):Bytes {
			var e = entries[i];
			return stream.sub(e.at, e.stored);
		}
		function part(i:Null<Int>):Null<Bytes>
			return i == null ? null : raw(i);
		var out = [];
		for (f in fonts) {
			var byTag = new Map<String, Int>();
			for (i in f.tables) byTag.set(entries[i].tag, i);
			var glyf = byTag.get("glyf"), loca = byTag.get("loca");
			if ((glyf != null) != (loca != null)) throw "Woff: glyf without loca";
			if (glyf != null && entries[glyf].transformed != entries[loca].transformed) throw "Woff: glyf and loca transformed apart";
			if (glyf != null && entries[glyf].transformed && !made.exists(glyf)) {
				var g = Glyf.rebuild(raw(glyf));
				if (g.loca.length != entries[loca].length) throw "Woff: loca's length is not its glyphs'";
				made.set(glyf, g.glyf);
				made.set(loca, g.loca);
				xMins.set(glyf, g.xMins);
			}
			var tables = [];
			for (i in f.tables) {
				var e = entries[i], t = made.get(i);
				if (t == null) {
					t = e.tag == "hmtx" && e.transformed ? hmtx(raw(i), part(byTag.get("hhea")), part(byTag.get("maxp")), glyf == null ? null : xMins.get(glyf)) : raw(i);
					made.set(i, t);
				}
				tables.push({tag: e.tag, data: t});
			}
			out.push({flavor: f.flavor, tables: tables});
		}
		return build(out, flavor == 0x74746366);
	}

	// a transformed hmtx: the left side bearings left out are the glyphs' xMin
	static function hmtx(t:Bytes, hh:Null<Bytes>, mp:Null<Bytes>, x:Null<Array<Int>>):Bytes {
		if (x == null) throw "Woff: a transformed hmtx without transformed glyphs";
		if (hh == null || mp == null || hh.length < 36 || mp.length < 6) throw "Woff: a transformed hmtx without hhea and maxp";
		var metrics = hh.get(34) << 8 | hh.get(35), glyphs = mp.get(4) << 8 | mp.get(5);
		if (metrics == 0 || metrics > glyphs || glyphs > x.length) throw "Woff: hmtx's counts are not the glyphs'";
		var r = new Reader(t, 0, t.length), flags = r.u8();
		var out = Bytes.alloc(4 * metrics + 2 * (glyphs - metrics));
		var advances = [for (_ in 0...metrics) r.u16()];
		for (i in 0...metrics) {
			out.set(4 * i, advances[i] >> 8);
			out.set(4 * i + 1, advances[i]);
		}
		for (i in 0...glyphs) {
			var lsb = (i < metrics ? flags & 1 != 0 : flags & 2 != 0) ? x[i] : r.u16();
			var p = i < metrics ? 4 * i + 2 : 4 * metrics + 2 * (i - metrics);
			out.set(p, lsb >> 8);
			out.set(p + 1, lsb);
		}
		return out;
	}

	// an sfnt (collection: a .ttc) of these fonts' tables, each table's data
	// once, records sorted by tag
	static function build(fonts:Array<{flavor:Int, tables:Array<{tag:String, data:Bytes}>}>, collection = false):Bytes {
		var at = collection ? 12 + 4 * fonts.length : 0;
		for (f in fonts) at += 12 + 16 * f.tables.length;
		var where = new Map<String, Int>(), datas:Array<Bytes> = [], size = at;
		inline function pad(n:Int)
			return (n + 3) & ~3;
		var offsets = [];
		for (f in fonts) for (t in f.tables) {
			var k = key(t.data, datas);
			if (k < 0) {
				datas.push(t.data);
				offsets.push(size);
				size += pad(t.data.length);
				if (size > MAX) throw "Woff: the font is too large";
			}
		}
		var out = Bytes.alloc(size);
		var w = 0;
		inline function u16(v:Int) {
			out.set(w++, v >> 8);
			out.set(w++, v);
		}
		inline function u32(v:Int) {
			u16(v >>> 16);
			u16(v & 0xffff);
		}
		if (collection) {
			u32(0x74746366);
			u32(0x00010000);
			u32(fonts.length);
			var o = 12 + 4 * fonts.length;
			for (f in fonts) {
				u32(o);
				o += 12 + 16 * f.tables.length;
			}
		}
		for (f in fonts) {
			var tables = f.tables.copy();
			tables.sort((a, b) -> a.tag < b.tag ? -1 : a.tag > b.tag ? 1 : 0);
			var n = tables.length, p = 1, e = 0;
			while (p * 2 <= n) {
				p *= 2;
				e++;
			}
			u32(f.flavor);
			u16(n);
			u16(p * 16);
			u16(e);
			u16(n * 16 - p * 16);
			for (t in tables) {
				for (i in 0...4) out.set(w++, t.tag.charCodeAt(i));
				u32(checksum(t.data));
				u32(offsets[key(t.data, datas)]);
				u32(t.data.length);
			}
		}
		for (i in 0...datas.length) out.blit(offsets[i], datas[i], 0, datas[i].length);
		return out;
	}

	static function key(b:Bytes, datas:Array<Bytes>):Int {
		for (i in 0...datas.length) if (datas[i] == b) return i;
		return -1;
	}

	static function checksum(b:Bytes):Int {
		var s = 0, i = 0, n = b.length;
		while (i + 3 < n) {
			s += b.get(i) << 24 | b.get(i + 1) << 16 | b.get(i + 2) << 8 | b.get(i + 3);
			i += 4;
		}
		var k = 24;
		while (i < n) {
			s += b.get(i++) << k;
			k -= 8;
		}
		return s;
	}
}

// WOFF2's transformed glyf: its streams read into glyf and loca again
private class Glyf {
	public final glyf:Bytes;
	public final loca:Bytes;
	public final xMins:Array<Int>;

	function new(glyf, loca, xMins) {
		this.glyf = glyf;
		this.loca = loca;
		this.xMins = xMins;
	}

	public static function rebuild(t:Bytes):Glyf {
		var h = new Reader(t, 0, t.length);
		h.skip(2);
		var options = h.u16(), glyphs = h.u16(), long = h.u16() != 0;
		var sizes = [for (_ in 0...7) h.u32()];
		var at = h.at;
		function stream(i:Int):Reader {
			var start = at;
			for (k in 0...i) start += sizes[k];
			if (sizes[i] < 0 || start + sizes[i] > t.length || start < 0) throw "Woff: a glyf stream past the table";
			return new Reader(t, start, start + sizes[i]);
		}
		var contours = stream(0), points = stream(1), flags = stream(2), coords = stream(3), composites = stream(4), boxes = stream(5),
			instructions = stream(6);
		var end = at;
		for (s in sizes) end += s;
		var overlap = options & 1 != 0 ? new Reader(t, end, end + ((glyphs + 7) >> 3)) : null;
		if (overlap != null && end + ((glyphs + 7) >> 3) > t.length) throw "Woff: the overlap bitmap past the table";
		var boxBits = (glyphs + 31) >> 5 << 2;
		var boxMap = boxes.at;
		boxes.skip(boxBits);
		var out = new Writer(t.length * 2), loca = Bytes.alloc((glyphs + 1) * (long ? 4 : 2)), xMins = [];
		var xs:Array<Int> = [], ys:Array<Int> = [], on:Array<Bool> = [], ends:Array<Int> = [];
		for (g in 0...glyphs) {
			var start = out.length;
			var n = contours.s16(), hasBox = t.get(boxMap + (g >> 3)) & (0x80 >> (g & 7)) != 0;
			if (n == 0) {
				if (hasBox) throw "Woff: an empty glyph with a bounding box";
				xMins.push(0);
			} else if (n == -1) {
				if (!hasBox) throw "Woff: a composite glyph without its bounding box";
				out.u16(0xffff);
				var x0 = boxes.s16();
				xMins.push(x0);
				out.u16(x0);
				for (_ in 0...3) out.u16(boxes.s16());
				// (its components: flags, glyph, arguments and transform, until the last)
				var instructed = false, more = true, from = composites.at;
				while (more) {
					var f = composites.u16();
					composites.skip(2 + (f & 1 != 0 ? 4 : 2) + (f & 8 != 0 ? 2 : f & 0x40 != 0 ? 4 : f & 0x80 != 0 ? 8 : 0));
					more = f & 0x20 != 0;
					if (f & 0x100 != 0) instructed = true;
				}
				out.bytes(t, from, composites.at - from);
				if (instructed) {
					var k = coords.u255();
					out.u16(k);
					out.bytes(t, instructions.take(k), k);
				}
			} else if (n > 0) {
				ends.resize(0);
				var total = 0;
				for (_ in 0...n) {
					total += points.u255();
					if (total > 0xffff) throw "Woff: a glyph of too many points";
					ends.push(total - 1);
				}
				xs.resize(0);
				ys.resize(0);
				on.resize(0);
				var x = 0, y = 0;
				for (_ in 0...total) {
					var f = flags.u8();
					on.push(f & 0x80 == 0);
					f &= 0x7f;
					var dx = 0, dy = 0;
					if (f < 10) dy = sign(f, ((f & 14) << 7) + coords.u8()) else if (f < 20) dx = sign(f, (((f - 10) & 14) << 7) + coords.u8()) else if (f < 84) {
						var b0 = f - 20, b1 = coords.u8();
						dx = sign(f, 1 + (b0 & 0x30) + (b1 >> 4));
						dy = sign(f >> 1, 1 + ((b0 & 0x0c) << 2) + (b1 & 0x0f));
					} else if (f < 120) {
						var b0 = f - 84;
						dx = sign(f, 1 + (Std.int(b0 / 12) << 8) + coords.u8());
						dy = sign(f >> 1, 1 + (((b0 % 12) >> 2) << 8) + coords.u8());
					} else if (f < 124) {
						var b1 = coords.u8(), b2 = coords.u8();
						dx = sign(f, (b1 << 4) + (b2 >> 4));
						dy = sign(f >> 1, ((b2 & 0x0f) << 8) + coords.u8());
					} else {
						dx = sign(f, coords.u16());
						dy = sign(f >> 1, coords.u16());
					}
					x += dx;
					y += dy;
					xs.push(x);
					ys.push(y);
				}
				var k = coords.u255();
				var x0 = 0, y0 = 0, x1 = 0, y1 = 0;
				if (hasBox) {
					x0 = boxes.s16();
					y0 = boxes.s16();
					x1 = boxes.s16();
					y1 = boxes.s16();
				} else if (total > 0) {
					x0 = x1 = xs[0];
					y0 = y1 = ys[0];
					for (i in 1...total) {
						if (xs[i] < x0) x0 = xs[i] else if (xs[i] > x1) x1 = xs[i];
						if (ys[i] < y0) y0 = ys[i] else if (ys[i] > y1) y1 = ys[i];
					}
				}
				xMins.push(x0);
				out.u16(n);
				out.u16(x0);
				out.u16(y0);
				out.u16(x1);
				out.u16(y1);
				for (e in ends) out.u16(e);
				out.u16(k);
				out.bytes(t, instructions.take(k), k);
				simple(out, xs, ys, on, overlap != null && t.get(overlap.at + (g >> 3)) & (0x80 >> (g & 7)) != 0);
			} else throw "Woff: a glyph's contour count is not one";
			while (out.length & 3 != 0) out.u8(0);
			if (out.length > Woff.MAX) throw "Woff: glyf too large";
			if (long) {
				loca.set(4 * g, start >>> 24);
				loca.set(4 * g + 1, start >> 16);
				loca.set(4 * g + 2, start >> 8);
				loca.set(4 * g + 3, start);
			} else {
				if (start >> 1 > 0xffff) throw "Woff: glyf too large for short loca";
				loca.set(2 * g, start >> 9);
				loca.set(2 * g + 1, start >> 1);
			}
		}
		var size = out.length;
		if (long) {
			loca.set(4 * glyphs, size >>> 24);
			loca.set(4 * glyphs + 1, size >> 16);
			loca.set(4 * glyphs + 2, size >> 8);
			loca.set(4 * glyphs + 3, size);
		} else {
			if (size >> 1 > 0xffff) throw "Woff: glyf too large for short loca";
			loca.set(2 * glyphs, size >> 9);
			loca.set(2 * glyphs + 1, size >> 1);
		}
		return new Glyf(out.done(), loca, xMins);
	}

	static inline function sign(f:Int, v:Int):Int
		return f & 1 != 0 ? v : -v;

	// a simple glyph's flags and coordinates, TrueType's packing (repeats, short and same)
	static function simple(out:Writer, xs:Array<Int>, ys:Array<Int>, on:Array<Bool>, overlap:Bool) {
		var n = xs.length, fl = [], px = 0, py = 0;
		for (i in 0...n) {
			var dx = xs[i] - px, dy = ys[i] - py, f = on[i] ? 1 : 0;
			if (dx == 0) f |= 0x10 else if (dx > -256 && dx < 256) f |= 0x02 | (dx > 0 ? 0x10 : 0);
			if (dy == 0) f |= 0x20 else if (dy > -256 && dy < 256) f |= 0x04 | (dy > 0 ? 0x20 : 0);
			if (i == 0 && overlap) f |= 0x40;
			fl.push(f);
			px = xs[i];
			py = ys[i];
		}
		var i = 0;
		while (i < n) {
			var f = fl[i], r = 0;
			while (i + r + 1 < n && fl[i + r + 1] == f && r < 255) r++;
			if (r > 0) {
				out.u8(f | 0x08);
				out.u8(r);
			} else out.u8(f);
			i += r + 1;
		}
		px = 0;
		for (i in 0...n) {
			var d = xs[i] - px;
			px = xs[i];
			if (fl[i] & 0x02 != 0) out.u8(d < 0 ? -d : d) else if (fl[i] & 0x10 == 0) out.u16(d);
		}
		py = 0;
		for (i in 0...n) {
			var d = ys[i] - py;
			py = ys[i];
			if (fl[i] & 0x04 != 0) out.u8(d < 0 ? -d : d) else if (fl[i] & 0x20 == 0) out.u16(d);
		}
	}
}

// (big-endian reads within [at, end): past it, "Woff: the file is cut")
private class Reader {
	final b:Bytes;
	public var at:Int;
	final end:Int;

	public function new(b, at, end) {
		this.b = b;
		this.at = at;
		this.end = end;
	}

	inline function need(n:Int)
		if (at + n > end || n < 0) throw "Woff: the file is cut";

	public function skip(n:Int) {
		need(n);
		at += n;
	}

	public function u8():Int {
		need(1);
		return b.get(at++);
	}

	public function u16():Int {
		need(2);
		var v = b.get(at) << 8 | b.get(at + 1);
		at += 2;
		return v;
	}

	public function s16():Int {
		var v = u16();
		return v >= 0x8000 ? v - 0x10000 : v;
	}

	// (past 2^31: refused, a length or an offset no file has)
	public function u32():Int {
		need(4);
		var v = b.get(at) << 24 | b.get(at + 1) << 16 | b.get(at + 2) << 8 | b.get(at + 3);
		at += 4;
		return v;
	}

	public function tag():String {
		need(4);
		at += 4;
		return b.getString(at - 4, 4);
	}

	// UIntBase128: up to five bytes, no leading zero, within 32 bits (here 31)
	public function base128():Int {
		var v = 0;
		for (i in 0...5) {
			var c = u8();
			if (i == 0 && c == 0x80) throw "Woff: a number with a leading zero";
			if (v & 0x7e000000 != 0) throw "Woff: a number too large";
			v = v << 7 | (c & 0x7f);
			if (c & 0x80 == 0) return v;
		}
		throw "Woff: a number too long";
	}

	// 255UInt16
	public function u255():Int {
		var c = u8();
		return switch c {
			case 253: u16();
			case 255: u8() + 253;
			case 254: u8() + 506;
			case _: c;
		}
	}

	// (n bytes: where they start)
	public function take(n:Int):Int {
		need(n);
		at += n;
		return at - n;
	}
}

// (a growing big-endian output)
private class Writer {
	var b:Bytes;

	public var length(default, null) = 0;

	public function new(size:Int)
		b = Bytes.alloc(size < 64 ? 64 : size);

	inline function room(n:Int)
		if (length + n > b.length) {
			var c = Bytes.alloc(Std.int(Math.max(b.length * 2, length + n)));
			c.blit(0, b, 0, length);
			b = c;
		}

	public function u8(v:Int) {
		room(1);
		b.set(length++, v);
	}

	public function u16(v:Int) {
		room(2);
		b.set(length++, v >> 8);
		b.set(length++, v);
	}

	public function bytes(from:Bytes, at:Int, n:Int) {
		room(n);
		b.blit(length, from, at, n);
		length += n;
	}

	public function done():Bytes
		return b.sub(0, length);
}
