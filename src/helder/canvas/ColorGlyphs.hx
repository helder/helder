package helder.canvas;

import haxe.ds.Vector;
import helder.canvas.Blend.Blender;
import helder.canvas.Gradient;
import helder.text.ColorPaint;
import helder.text.FontFile;

// Colour glyphs drawn on any Painter (the CPU canvas, the GPU's, a PDF's
// Recorder): COLR's paint graph (helder.text.ColorPaint) as what painters
// have (fills, clips to a glyph's outline, transforms, layers with blend
// modes, linear, radial and conic gradients), and CBDT's or sbix's bitmaps
// as images. A sweep gradient is a conic one whose stops are its colour
// line sampled at each of its breaks over the turn (its extend, angles past
// 0 to 360, an end before its start). Colours are the palette's (font-palette:
// the run's; else the font's first) or the text's (entry 0xFFFF).
class ColorGlyphs {
	// whether glyph g is drawn in colour at size
	public static function has(face:FontFile, g:Int, size:Float):Bool
		return face.hasColor && (face.colorPaint(g) != null || face.colorBitmap(g, size) != null);

	// a run's glyphs: plain ones filled as one path, colour ones each drawn
	public static function run(p:Painter, glyphs:Glyphs, r:ShapedRun, paint:Paint) {
		var face = r.face, colour = face.hasColor;
		glyphs.path.clear();
		var plain = new ShapedRun(face, r.size);
		plain.scaleX = r.scaleX;
		plain.skew = r.skew;
		for (i in 0...r.count)
			if (!colour || !draw(p, face, r.ids[i], r.size, r.xs[i], r.ys[i], r.scaleX, r.skew, r.palette, paint.color, paint.alpha))
				plain.push(r.ids[i], r.xs[i], r.ys[i], r.starts[i], r.ends[i]);
		glyphs.addRun(plain);
		if (!glyphs.path.isEmpty()) p.fill(glyphs.path, paint);
	}

	// glyph g of face at (x, y) on the baseline, size pixels, as a run places
	// it (scaleX, skew); false: it has no colour (draw its outline)
	public static function draw(p:Painter, face:FontFile, g:Int, size:Float, x:Float, y:Float, scaleX:Float, skew:Float, palette:Null<Array<Int>>,
			foreground:Int, alpha:Float):Bool {
		var graph = face.colorPaint(g);
		if (graph != null) {
			var c = face.colr, s = size / face.unitsPerEm;
			var box = c.clipBox(g) ?? bounds(face, g);
			var d = new Drawing(p, face, palette ?? (c.palettes.length > 0 ? c.palettes[0] : []), foreground, box);
			p.save();
			if (alpha < 1) p.saveLayer(alpha);
			p.transform(s * scaleX, 0, skew * s * scaleX, -s, x, y);
			p.clip(rect(box[0], box[1], box[2], box[3]));
			try d.paint(graph, new Matrix()) catch (_:String) {}
			p.restore();
			if (alpha < 1) p.restore();
			return true;
		}
		var bm = face.colorBitmap(g, size);
		if (bm == null) return false;
		var b = bitmap(face, g, bm.png, bm.ppem);
		if (b == null) return false;
		var k = size / bm.ppem, pt = new Paint();
		pt.alpha = alpha;
		p.drawImage(b, 0, 0, b.width, b.height, x + bm.left * k * scaleX, y - bm.top * k, b.width * k * scaleX, b.height * k, pt);
		return true;
	}

	// (a glyph without a clip box: its layers' outlines' box, else the em)
	static function bounds(face:FontFile, g:Int):Array<Float> {
		var b = new Bounds();
		function walk(p:ColorPaint, depth:Int)
			if (depth < 32) switch p {
				case Layers(ps): for (x in ps) walk(x, depth + 1);
				case Glyph(id, _): face.outline(id, b);
				case Transform(_, _, _, _, _, _, x) | Clip(_, _, _, _, x): walk(x, depth + 1);
				case Composite(_, s, d):
					walk(s, depth + 1);
					walk(d, depth + 1);
				case _:
			}
		walk(face.colorPaint(g), 0);
		// (transformed layers reach past their outlines: a margin of an em)
		var u = face.unitsPerEm;
		return b.x0 > b.x1 ? [0, face.descender, u, face.ascender] : [b.x0 - u, b.y0 - u, b.x1 + u, b.y1 + u];
	}

	static function rect(x0:Float, y0:Float, x1:Float, y1:Float):Path {
		var r = new Path();
		r.moveTo(x0, y0);
		r.lineTo(x1, y0);
		r.lineTo(x1, y1);
		r.lineTo(x0, y1);
		r.close();
		return r;
	}

	// (bitmaps decoded once a face's glyph and strike)
	static final bitmaps = new Map<String, Null<Bitmap>>();

	static function bitmap(face:FontFile, g:Int, png:haxe.io.Bytes, ppem:Int):Null<Bitmap> {
		var key = face.id + ":" + g + ":" + ppem;
		if (bitmaps.exists(key)) return bitmaps.get(key);
		var d = try helder.image.PngDecoder.decode(png) catch (_:Dynamic) null;
		var b = d == null ? null : Bitmap.fromStraight(d.width, d.height, d.rgba);
		bitmaps.set(key, b);
		return b;
	}

	public static function blend(mode:Int):Null<Blender>
		return switch mode {
			case 0: Blend.clear;
			case 1: Blend.copy;
			case 2: Blend.destination;
			case 3: null;
			case 4: Blend.destinationOver;
			case 5: Blend.sourceIn;
			case 6: Blend.destinationIn;
			case 7: Blend.sourceOut;
			case 8: Blend.destinationOut;
			case 9: Blend.sourceAtop;
			case 10: Blend.destinationAtop;
			case 11: Blend.xor;
			case 12: Blend.lighter;
			case 13: Blend.screen;
			case 14: Blend.overlay;
			case 15: Blend.darken;
			case 16: Blend.lighten;
			case 17: Blend.colorDodge;
			case 18: Blend.colorBurn;
			case 19: Blend.hardLight;
			case 20: Blend.softLight;
			case 21: Blend.difference;
			case 22: Blend.exclusion;
			case 23: Blend.multiply;
			case 24: Blend.hue;
			case 25: Blend.saturation;
			case 26: Blend.color;
			case 27: Blend.luminosity;
			case _: null;
		}
}

// (one glyph's graph drawn: its palette, the text's colour, its box in glyph space)
private class Drawing {
	final p:Painter;
	final face:FontFile;
	final palette:Array<Int>;
	final foreground:Int;
	final box:Array<Float>;
	// (a graph drawn at most this many nodes: a font's shared subgraphs can multiply)
	var budget = 20000;

	public function new(p, face, palette, foreground, box) {
		this.p = p;
		this.face = face;
		this.palette = palette;
		this.foreground = foreground;
		this.box = box;
	}

	// (rel: glyph space from the current one)
	public function paint(g:ColorPaint, rel:Matrix) {
		if (--budget < 0) throw "ColorGlyphs: a graph too large";
		switch g {
			case Layers(ps):
				for (x in ps) paint(x, rel);
			case Glyph(id, child):
				var path = outline(id);
				var fill = fillOf(child);
				if (fill != null) p.fill(path, fill) else {
					p.save();
					p.clip(path);
					paint(child, rel);
					p.restore();
				}
			case Transform(xx, yx, xy, yy, dx, dy, child):
				p.save();
				p.transform(xx, yx, xy, yy, dx, dy);
				var m = new Matrix();
				m.copyFrom(rel);
				m.multiply(matrix(xx, yx, xy, yy, dx, dy));
				paint(child, m);
				p.restore();
			case Clip(x0, y0, x1, y1, child):
				p.save();
				var r = new Path();
				r.moveTo(x0, y0);
				r.lineTo(x1, y0);
				r.lineTo(x1, y1);
				r.lineTo(x0, y1);
				r.close();
				p.clip(r);
				paint(child, rel);
				p.restore();
			case Composite(mode, source, backdrop):
				p.saveLayer();
				paint(backdrop, rel);
				p.saveLayer(1, ColorGlyphs.blend(mode));
				paint(source, rel);
				p.restore();
				p.restore();
			case _:
				var fill = fillOf(g);
				if (fill != null) p.fill(cover(rel), fill);
		}
	}

	static function matrix(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float):Matrix {
		var m = new Matrix();
		m.a = a;
		m.b = b;
		m.c = c;
		m.d = d;
		m.e = e;
		m.f = f;
		return m;
	}

	// (the glyph's box in the current space: what a paint outside any glyph fills)
	function cover(rel:Matrix):Path {
		var inv = new Matrix();
		if (!rel.invertInto(inv)) return new Path();
		var x0 = Math.POSITIVE_INFINITY, y0 = Math.POSITIVE_INFINITY, x1 = Math.NEGATIVE_INFINITY, y1 = Math.NEGATIVE_INFINITY;
		for (k in 0...4) {
			var x = box[k & 1 == 0 ? 0 : 2], y = box[k < 2 ? 1 : 3];
			var u = inv.mapX(x, y), v = inv.mapY(x, y);
			x0 = Math.min(x0, u);
			y0 = Math.min(y0, v);
			x1 = Math.max(x1, u);
			y1 = Math.max(y1, v);
		}
		var r = new Path();
		r.moveTo(x0, y0);
		r.lineTo(x1, y0);
		r.lineTo(x1, y1);
		r.lineTo(x0, y1);
		r.close();
		return r;
	}

	function outline(id:Int):Path {
		var g = new Glyphs();
		face.outline(id, g, [1, 0, 0, 1, 0, 0]);
		return g.path;
	}

	function color(entry:Int, alpha:Float):Int {
		var c = entry == ColorPaints.FOREGROUND || entry >= palette.length ? foreground : palette[entry];
		var a = Math.round(((c >>> 24) & 255) * (alpha < 0 ? 0 : alpha > 1 ? 1 : alpha));
		return a << 24 | (c & 0xFFFFFF);
	}

	// (a paint as a fill: a colour or a gradient; null: one that is not)
	function fillOf(g:ColorPaint):Null<Paint>
		return switch g {
			case Solid(entry, alpha): Paint.solid(color(entry, alpha));
			case Linear(line, x0, y0, x1, y1, x2, y2):
				// (along p0 to p1 projected on the normal of p0 to p2)
				var nx = y2 - y0, ny = -(x2 - x0), nn = nx * nx + ny * ny;
				if (nn == 0 || (x0 == x1 && y0 == y1)) return null;
				var t = ((x1 - x0) * nx + (y1 - y0) * ny) / nn, x3 = x0 + nx * t, y3 = y0 + ny * t;
				var n = normalized(line);
				var lg = new LinearGradient(x0 + (x3 - x0) * n.lo, y0 + (y3 - y0) * n.lo, x0 + (x3 - x0) * n.hi, y0 + (y3 - y0) * n.hi);
				shaded(lg, line, n);
			case Radial(line, x0, y0, r0, x1, y1, r1):
				var n = normalized(line);
				inline function at(a:Float, b:Float, k:Float)
					return a + (b - a) * k;
				var rg = new RadialGradient(at(x0, x1, n.lo), at(y0, y1, n.lo), Math.max(0, at(r0, r1, n.lo)), at(x0, x1, n.hi), at(y0, y1, n.hi),
					Math.max(0, at(r0, r1, n.hi)));
				shaded(rg, line, n);
			case Sweep(line, x, y, start, end):
				sweep(line, x, y, start, end);
			case _: null;
		}

	// (a colour line's stops past 0 to 1: the geometry stretched to them, the offsets made 0 to 1)
	static function normalized(line:ColorLine):{lo:Float, hi:Float} {
		var lo = Math.POSITIVE_INFINITY, hi = Math.NEGATIVE_INFINITY;
		for (s in line.stops) {
			lo = Math.min(lo, s.offset);
			hi = Math.max(hi, s.offset);
		}
		if (line.stops.length == 0 || hi <= lo) return {lo: 0, hi: 1};
		return {lo: lo, hi: hi};
	}

	function stops(line:ColorLine):Array<{offset:Float, color:Int}> {
		var s = [for (x in line.stops) {offset: x.offset, color: color(x.entry, x.alpha)}];
		haxe.ds.ArraySort.sort(s, (a, b) -> a.offset < b.offset ? -1 : a.offset > b.offset ? 1 : 0);
		return s;
	}

	function shaded(g:Gradient, line:ColorLine, n:{lo:Float, hi:Float}):Paint {
		g.premultiplied = true;
		g.spread = line.extend == ColorPaints.REPEAT ? Gradient.REPEAT : line.extend == ColorPaints.REFLECT ? Gradient.REFLECT : Gradient.PAD;
		var span = n.hi - n.lo;
		for (s in stops(line)) g.addStop(span == 0 ? 0 : (s.offset - n.lo) / span, s.color);
		return Paint.shaded(g);
	}

	// (the sweep's colour at each break over a turn, angle / 360 a conic
	// gradient's stop. Degenerate, its angles or its stops coinciding: padded,
	// the first colour before and the last after; repeated or reflected,
	// nothing, as Skia draws them)
	function sweep(line:ColorLine, x:Float, y:Float, start:Float, end:Float):Null<Paint> {
		var st = stops(line);
		if (st.length == 0) return null;
		var lo = st[0].offset, hi = st[st.length - 1].offset;
		if ((start == end || hi == lo) && line.extend != ColorPaints.PAD) return null;
		if (start == end) {
			var a = start - 360 * Math.floor(start / 360), cg = new ConicGradient(0, x, y);
			cg.premultiplied = true;
			cg.addStop(0, st[0].color);
			cg.addStop(a / 360, st[0].color);
			cg.addStop(a / 360, st[st.length - 1].color);
			cg.addStop(1, st[st.length - 1].color);
			return Paint.shaded(cg);
		}
		// (t at an angle; the angle of a t)
		inline function tOf(a:Float)
			return (a - start) / (end - start);
		inline function angleOf(t:Float)
			return start + t * (end - start);
		var t0 = tOf(0), t1 = tOf(360), tMin = Math.min(t0, t1), tMax = Math.max(t0, t1);
		var breaks = [0.0, 360.0];
		var period = hi - lo;
		if (line.extend == ColorPaints.PAD || period <= 0) {
			for (s in st) if (s.offset > tMin && s.offset < tMax) breaks.push(angleOf(s.offset));
		} else {
			// (each stop again a period on, reflected every other one)
			var k0 = Math.floor((tMin - lo) / period) - 1, k1 = Math.ceil((tMax - lo) / period) + 1;
			if (k1 - k0 > 4096) return null;
			for (k in Std.int(k0)...Std.int(k1) + 1)
				for (s in st) {
					var o = line.extend == ColorPaints.REFLECT && k % 2 != 0 ? lo + (k + 1) * period - (s.offset - lo) : s.offset + k * period;
					if (o > tMin && o < tMax) breaks.push(angleOf(o));
				}
		}
		breaks.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		var cg = new ConicGradient(0, x, y);
		cg.premultiplied = true;
		for (k in 0...breaks.length) {
			// (both sides of a hard stop, its colour just before and just after; the turn's ends one side)
			// (a hair either side: a repeat's seam is the last colour before it, the first after)
			var a = breaks[k], t = tOf(a), e = 1e-9 * (end > start ? 1 : -1);
			var before = at(st, wrap(t - e, lo, hi, line.extend), -1), after = at(st, wrap(t + e, lo, hi, line.extend), 1);
			if (k > 0) cg.addStop(a / 360, before);
			if (k < breaks.length - 1 && (k == 0 || after != before)) cg.addStop(a / 360, after);
		}
		return Paint.shaded(cg);
	}

	static function wrap(t:Float, lo:Float, hi:Float, extend:Int):Float {
		var p = hi - lo;
		if (extend == ColorPaints.PAD || p <= 0) return t;
		var u = (t - lo) / p;
		if (extend == ColorPaints.REPEAT) return lo + (u - Math.floor(u)) * p;
		var m = u - 2 * Math.floor(u / 2);
		return lo + (m <= 1 ? m : 2 - m) * p;
	}

	// (the colour line's colour at t, from before it (side -1) or after it (1) where two stops meet)
	static function at(st:Array<{offset:Float, color:Int}>, t:Float, side:Int):Int {
		var n = st.length;
		if (t <= st[0].offset && (side < 0 || t < st[0].offset)) return st[0].color;
		if (t >= st[n - 1].offset && (side > 0 || t > st[n - 1].offset)) return st[n - 1].color;
		for (i in 1...n) {
			var a = st[i - 1], b = st[i];
			if (t > b.offset || side > 0 && t == b.offset && i < n - 1) continue;
			if (b.offset == a.offset) return side < 0 ? a.color : b.color;
			return mix(a.color, b.color, (t - a.offset) / (b.offset - a.offset));
		}
		return st[n - 1].color;
	}

	// (premultiplied, as the gradients interpolate)
	static function mix(c0:Int, c1:Int, k:Float):Int {
		var a0 = ((c0 >>> 24) & 255) / 255, a1 = ((c1 >>> 24) & 255) / 255, a = a0 + (a1 - a0) * k;
		if (a <= 0) return 0;
		inline function ch(s:Int)
			return Math.round((((c0 >> s) & 255) * a0 + ((((c1 >> s) & 255) * a1) - ((c0 >> s) & 255) * a0) * k) / a);
		return Math.round(a * 255) << 24 | ch(16) << 16 | ch(8) << 8 | ch(0);
	}
}

// (an outline's box)
private class Bounds implements helder.text.Outline {
	public var x0 = Math.POSITIVE_INFINITY;
	public var y0 = Math.POSITIVE_INFINITY;
	public var x1 = Math.NEGATIVE_INFINITY;
	public var y1 = Math.NEGATIVE_INFINITY;

	public function new() {}

	inline function add(x:Float, y:Float) {
		if (x < x0) x0 = x;
		if (x > x1) x1 = x;
		if (y < y0) y0 = y;
		if (y > y1) y1 = y;
	}

	public function moveTo(x:Float, y:Float)
		add(x, y);

	public function lineTo(x:Float, y:Float)
		add(x, y);

	public function quadTo(cx:Float, cy:Float, x:Float, y:Float) {
		add(cx, cy);
		add(x, y);
	}

	public function cubicTo(c1x:Float, c1y:Float, c2x:Float, c2y:Float, x:Float, y:Float) {
		add(c1x, c1y);
		add(c2x, c2y);
		add(x, y);
	}

	public function close() {}
}
