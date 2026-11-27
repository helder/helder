package helder.ui.box;

import helder.ui.box.Len.Lens;

import helder.canvas.Bitmap;
import helder.canvas.GlyphText;
import helder.canvas.Glyphs;
import helder.canvas.Paint;
import helder.canvas.Painter;
import helder.canvas.Path;
import helder.canvas.ShapedRun;
import helder.css.CssTerm;

// Fragments painted on a helder.canvas Painter, in PaintOrder's order:
// backgrounds, shadows and borders of boxes and inline boxes, text and
// its decorations (Text Decoration 3: drawn by every decorating box
// around the text, in its own colour), replaced images, outlines; inside
// the opacity layers, transforms and overflow clips their states say.
class BoxPainter {
	final f:Fragments;
	final order:PaintOrder;
	final image:String->Null<Bitmap>;
	final glyphs = new Glyphs();
	// (the states pushed now, innermost last)
	final stack:Array<Int> = [];
	// each glyph's origin on a quarter pixel across and a whole one down, as
	// Skia quantizes subpixel-positioned text (Chromium's); off for a PDF,
	// whose text keeps layout's places (a tie rounds up, float noise aside)
	public var snap = true;
	// the canvas's background: the area it covers (null: the painter's
	// whole) and the box it is positioned in (null: the root's fragment);
	// a page's: its page area, the root's box over all the pages
	public var canvasArea:Null<Array<Float>> = null;
	// whether the root's background is the canvas's (CSS 2.1 §14.2); off: a
	// box of its own (a page's margin box)
	public var propagate = true;
	public var canvasBox:Null<Array<Float>> = null;

	public function new(fragments:Fragments, order:PaintOrder, image:String->Null<Bitmap>) {
		f = fragments;
		this.order = order;
		this.image = image;
	}

	public function paint(p:Painter) {
		if (propagate) canvas(p);
		// (what is outside the painter is skipped, but under a transform, or with a shadow or an outline that may reach in)
		var cull = p.matrix.isIdentity();
		var pw = p.width + MARGIN, ph = p.height + MARGIN;
		for (k in 0...order.count) {
			var id = order.fragments[k], x = order.xs[k], y = order.ys[k];
			if (cull && !order.transformed[order.stateOf[k]] && (y > ph || x > pw || y + f.height(id) < -MARGIN || x + f.width(id) < -MARGIN)) {
				var r = reach(f.box(id).style);
				if (r == 0 || y - r > ph || x - r > pw || y + f.height(id) + r < -MARGIN || x + f.width(id) + r < -MARGIN) continue;
			}
			enter(p, order.stateOf[k]);
			var b = f.box(id), s = b.style;
			switch order.steps[k] {
				case PaintOrder.BACKGROUND:
					if (!s.visible) continue;
					if (f.kind(id) == Fragments.SPAN) span(p, id, x, y) else box(p, id, b, x, y);
				case PaintOrder.TEXT:
					if (s.visible) text(p, id, b, x, y);
				case PaintOrder.BORDERS:
					if (s.visible) collapsed(p, id, b, x, y);
				case PaintOrder.REPLACED:
					if (s.visible && b.image != null) replaced(p, id, b, x, y);
				case PaintOrder.OUTLINE:
					if (s.visible) {
						var w = f.width(id), h = f.height(id);
						Borders.outline(p, s, x, y, w, h);
					}
			}
		}
		enter(p, 0);
	}

	static inline var MARGIN = 64;

	// (how far past its border box a box paints: its shadows' and its outline's reach)
	static function reach(s:BoxStyle):Float {
		var r = 0.0;
		if (s.keyword("outline-style") != "none") r = s.px("outline-width") + Math.abs(s.px("outline-offset"));
		var t = s.terms("box-shadow");
		if (t.length > 1) {
			var sum = 0.0;
			for (x in t) switch x {
				case Dimension(v, _): sum += Math.abs(v);
				case Delim(","):
					r = Math.max(r, sum * 2);
					sum = 0;
				case _:
			}
			r = Math.max(r, sum * 2);
		}
		return r;
	}

	// (the painter's state made the step's: layers and clips left and entered)
	function enter(p:Painter, st:Int) {
		var path = [];
		var s = st;
		while (s != 0) {
			path.push(s);
			s = order.parents[s];
		}
		path.reverse();
		var common = 0;
		while (common < stack.length && common < path.length && stack[common] == path[common]) common++;
		while (stack.length > common) {
			stack.pop();
			p.restore();
		}
		for (k in common...path.length) {
			var s = path[k];
			stack.push(s);
			switch order.kinds[s] {
				case PaintOrder.LAYER:
					var m = order.matrices[s];
					if (order.alphas[s] < 1) p.saveLayer(order.alphas[s]) else p.save();
					if (m != null) p.transform(m.a, m.b, m.c, m.d, m.e, m.f);
				case _:
					p.save();
					var r = order.rects[s];
					var clip = new Path();
					clip.rect(Math.round(r[0]), Math.round(r[1]), Math.round(r[0] + r[2]) - Math.round(r[0]), Math.round(r[1] + r[3]) - Math.round(r[1]));
					p.clip(clip);
			}
		}
	}

	function box(p:Painter, id:Int, b:Box, x:Float, y:Float) {
		if (b.kind == TableWrapper) return;
		var s = b.style, w = f.width(id), h = f.height(id);
		// (an empty cell's, under empty-cells: hide in the separated borders model: nothing, §17.6.1.1)
		if (b.flags & (Box.EMPTY | Box.COLLAPSED) == Box.EMPTY && s.keyword("empty-cells") == "hide") return;
		var part = s.part;
		Borders.shadows(p, s, x, y, w, h, false);
		var cells = part == BoxStyle.ROW || part == BoxStyle.ROW_GROUP || part == BoxStyle.COLUMN || part == BoxStyle.COLUMN_GROUP ? gridCells(b, x, y, w, h) : null;
		if (cells != null) {
			p.save();
			p.clip(cells);
		}
		// (a block's fragment in a fragmentainer: its start or end in another, box-decoration-break: slice)
		var noTop = f.start(id) == Box.NO_START, noBottom = f.end(id) == Box.NO_END;
		if (b != order.canvas || !propagate) Backgrounds.paint(p, s, x, y, w, h, image, null, false, false, noTop, noBottom);
		if (cells != null) p.restore();
		Borders.shadows(p, s, x, y, w, h, true);
		// (rows, columns and their groups have no borders of their own but collapsed; collapsed ones are the table's)
		if (b.flags & Box.COLLAPSED == 0 && (part == 0 || part == BoxStyle.CELL || part == BoxStyle.CAPTION))
			Borders.paint(p, s, x, y, w, h, false, false, noTop, noBottom);
	}

	// (a row's, column's or group's background shows in its cells, not in the spacing between them, §17.5.1:
	// the grid's cells under its rectangle; null where there is no spacing)
	function gridCells(b:Box, x:Float, y:Float, w:Float, h:Float):Null<Path> {
		var t = b.parent;
		while (t != null && !(t.kind == Container && t.style.inner == BoxStyle.TABLE)) t = t.parent;
		var g = t == null ? null : t.table;
		if (g == null || g.spacing == 0 || g.fragment < 0) return null;
		var o = f.absolute(g.fragment);
		var path = new Path();
		for (r in 0...g.rows) for (c in 0...g.columns) {
			var cx = o.x + g.x[c], cy = o.y + g.y[r];
			if (cx + g.widths[c] <= x || cx >= x + w || cy + g.heights[r] <= y || cy >= y + h) continue;
			path.rect(Math.round(cx), Math.round(cy), Math.round(cx + g.widths[c]) - Math.round(cx), Math.round(cy + g.heights[r]) - Math.round(cy));
		}
		return path;
	}

	// (a table's collapsed borders, §17.6.2: each line's segments, a horizontal one over the vertical
	// lines' half widths at its ends; double, dotted and the rest drawn solid)
	function collapsed(p:Painter, id:Int, b:Box, x:Float, y:Float) {
		var g = b.table;
		if (g == null || !g.collapse) return;
		var rows = g.rows, cols = g.columns;
		inline function colLeft(c:Int):Float
			return c < cols ? g.x[c] : g.x[cols - 1] + g.widths[cols - 1];
		inline function rowTop(r:Int):Float
			return r < rows ? g.y[r] : g.y[rows - 1] + g.heights[rows - 1];
		var path = new Path();
		for (r in 0...rows) for (c in 0...cols + 1) {
			var k = g.v(r, c), w = g.vPainted(k);
			if (w <= 0) continue;
			var lx = Math.round(x + colLeft(c) - Math.floor(w / 2)), ty = Math.round(y + rowTop(r)), by = Math.round(y + rowTop(r + 1));
			fillRect(p, path, lx, ty, w, by - ty, g.vColor[k]);
		}
		for (r in 0...rows + 1) for (c in 0...cols) {
			var k = g.h(r, c), w = g.hPainted(k);
			if (w <= 0) continue;
			var left = 0.0, right = 0.0;
			for (rr in [r - 1, r]) if (rr >= 0 && rr < rows) {
				left = Math.max(left, Math.floor(g.vPainted(g.v(rr, c)) / 2));
				right = Math.max(right, Math.ceil(g.vPainted(g.v(rr, c + 1)) / 2));
			}
			var lx = Math.round(x + colLeft(c) - left), rx = Math.round(x + colLeft(c + 1) + right);
			var ty = Math.round(y + rowTop(r) - Math.floor(w / 2));
			fillRect(p, path, lx, ty, rx - lx, w, g.hColor[k]);
		}
	}

	static function fillRect(p:Painter, path:Path, x:Float, y:Float, w:Float, h:Float, color:Int) {
		if (w <= 0 || h <= 0 || color >>> 24 == 0) return;
		path.clear();
		path.rect(x, y, w, h);
		p.fill(path, Paint.solid(color));
	}

	// (the canvas's background, the root's or body's, CSS 2.1 §14.2: under everything, over the whole canvas)
	function canvas(p:Painter) {
		var b = order.canvas;
		if (b == null || !b.style.visible) return;
		for (k in 0...order.count) if (f.box(order.fragments[k]) == b && order.steps[k] == PaintOrder.BACKGROUND) {
			var id = order.fragments[k];
			var at = canvasBox ?? [order.xs[k], order.ys[k], f.width(id), f.height(id)];
			Backgrounds.paint(p, b.style, at[0], at[1], at[2], at[3], image, canvasArea ?? [0.0, 0.0, p.width * 1.0, p.height * 1.0]);
			return;
		}
	}

	function span(p:Painter, id:Int, x:Float, y:Float) {
		var b = f.box(id), s = b.style, w = f.width(id), h = f.height(id);
		var noLeft = f.start(id) == Box.NO_START, noRight = f.end(id) == Box.NO_END;
		Backgrounds.paint(p, s, x, y, w, h, image, null, noLeft, noRight);
		Borders.paint(p, s, x, y, w, h, noLeft, noRight);
	}

	function replaced(p:Painter, id:Int, b:Box, x:Float, y:Float) {
		var s = b.style.model(), img = b.image;
		var cw = f.width(id);
		var pl = Lens.resolve(s.padding[3], cw, 0), pt = Lens.resolve(s.padding[0], cw, 0);
		var pr = Lens.resolve(s.padding[1], cw, 0), pb = Lens.resolve(s.padding[2], cw, 0);
		var dx = x + s.border[3] + pl, dy = y + s.border[0] + pt;
		var dw = f.width(id) - s.border[1] - s.border[3] - pl - pr, dh = f.height(id) - s.border[0] - s.border[2] - pt - pb;
		if (dw <= 0 || dh <= 0) return;
		var x0 = Math.round(dx), y0 = Math.round(dy);
		p.drawImage(img, 0, 0, img.width, img.height, x0, y0, Math.round(dx + dw) - x0, Math.round(dy + dh) - y0, PLAIN, true);
	}

	static final PLAIN = new Paint();

	// (a list marker's disc, circle or square: laid out as its text, drawn as
	// Chromium draws it, a shape of the font's ascent a: two thirds of it
	// halved, three halves of the rest below the text's top; at the text's
	// start inside its item, two thirds of a and 7 before the line outside)
	function symbol(p:Painter, id:Int, b:Box, run:ShapedRun, x:Float, baseline:Float, color:Int):Bool {
		// (the text's box: the marker's, or its text's)
		var marker = b.kind == Text ? b.parent : b;
		if (b.pseudo != "marker" || marker == null || marker.pseudo != "marker" || run.text == null) return false;
		var type = marker.style.keyword("list-style-type");
		var symbol = switch type {
			case "disc": "\u2022";
			case "circle": "\u25E6";
			case "square": "\u25AA";
			case _: return false;
		}
		if (StringTools.trim(run.text) != symbol) return false;
		if (color >>> 24 == 0) return true;
		var a = Math.round(FontMatch.ascent(run.face, run.size)), offset = Std.int(a * 2 / 3), size = Std.int((offset + 1) / 2);
		// (outside: from the line's start, its marker span's end: whatever its text's trailing space)
		var span = f.parent(id);
		var start = span >= 0 && f.kind(span) == Fragments.SPAN ? x - f.x(id) + f.width(span) : x + f.width(id);
		var x0 = Math.round(marker.flags & Box.OUTSIDE != 0 ? start - offset - 7 : x), y0 = Math.round(baseline) - a + Std.int(3 * (a - offset) / 2);
		var path = new Path();
		switch type {
			case "square":
				path.rect(x0, y0, size, size);
				p.fill(path, Paint.solid(color));
			case "circle":
				path.ellipse(x0 + size / 2, y0 + size / 2, size / 2 - 0.5, size / 2 - 0.5, 0, 0, 2 * Math.PI);
				p.stroke(path, new helder.canvas.Stroke(), Paint.solid(color));
			case _:
				path.ellipse(x0 + size / 2, y0 + size / 2, size / 2, size / 2, 0, 0, 2 * Math.PI);
				p.fill(path, Paint.solid(color));
		}
		return true;
	}

	function text(p:Painter, id:Int, b:Box, x:Float, y:Float) {
		var r = f.run(id);
		if (r < 0) return;
		var run = f.runs[r];
		var s = b.style;
		var baseline = y + f.baseline(id);
		var color = s.color("color");
		if (symbol(p, id, b, run, x, baseline, color)) return;
		var decorations = decorating(b);
		// (underlines and overlines under the text, line-throughs over it)
		for (d in decorations) decorate(p, d, run, x, baseline, f.width(id), false);
		if (color >>> 24 != 0) {
			var placed = new ShapedRun(run.face, run.size);
			placed.text = run.text;
			placed.skew = run.skew;
			placed.bold = run.bold;
			placed.palette = run.palette;
			for (k in 0...run.count) {
				var gx = x + run.xs[k], gy = baseline + run.ys[k];
				placed.push(run.ids[k], snap ? Math.floor(gx * 4 + 0.5 + 1e-3) / 4 : gx, snap ? Math.round(gy) : gy, run.starts[k], run.ends[k]);
			}
			var paint = Paint.solid(color);
			// (synthesized bold: outlines filled and stroked, not text a painter keeps)
			// (colour glyphs drawn as their paints; a painter that keeps text, a PDF, draws them itself)
			if (placed.bold > 0) {
				glyphs.path.clear();
				glyphs.addRun(placed);
				if (!glyphs.path.isEmpty()) {
					p.fill(glyphs.path, paint);
					p.stroke(glyphs.path, new helder.canvas.Stroke(placed.bold), paint);
				}
			} else if (!Std.isOfType(p, GlyphText) || !(cast p : GlyphText).glyphText(placed, paint)) helder.canvas.ColorGlyphs.run(p, glyphs, placed, paint);
		}
		for (d in decorations) decorate(p, d, run, x, baseline, f.width(id), true);
	}

	// (the decorating boxes around a text: its ancestors up to the first that
	// stops propagation, an atomic inline, a float or absolutely positioned box)
	static function decorating(b:Box):Array<BoxStyle> {
		var out = [];
		var a = b.kind == Text ? b.parent : b;
		while (a != null) {
			var lines = a.style.terms("text-decoration-line");
			if (lines.length > 0 && !lines[0].match(Keyword("none"))) out.push(a.style);
			if (a.kind == InlineBlock || a.kind == Container || a.style.floating || a.style.absolute) break;
			a = a.parent;
		}
		return out;
	}

	function decorate(p:Painter, d:BoxStyle, run:ShapedRun, x:Float, baseline:Float, width:Float, over:Bool) {
		var color = switch d.terms("text-decoration-color") {
			case [Color(c)]: BoxStyle.argb(c, d.color("color"));
			case _: d.color("color");
		}
		if (color >>> 24 == 0 || width <= 0) return;
		var u = FontMatch.underline(run.face, run.size), strike = FontMatch.strikeout(run.face, run.size);
		// (auto: a tenth of the font size, as Chromium's; from-font: the font's own)
		var auto = run.size / 10;
		var given = switch d.terms("text-decoration-thickness") {
			case [Dimension(v, _)]: v;
			case [Percentage(v)]: v * run.size / 100;
			case [Keyword("from-font")]: over ? strike.thickness : u.thickness;
			case _: auto;
		}
		var thickness = Math.max(1, Math.floor(given));
		var style = d.keyword("text-decoration-style");
		for (t in d.terms("text-decoration-line")) {
			var line = switch t {
				case Keyword(k): k;
				case _: continue;
			}
			if ((line == "line-through") != over) continue;
			var top = switch line {
				case "underline": baseline + Math.max(1, Math.round(u.offset - given / 2));
				case "overline": baseline - FontMatch.ascent(run.face, run.size);
				// (Chromium's: the font's strikeout position the stroke's bottom, auto's thickness above it)
				case "line-through": baseline - Math.round(strike.offset + auto);
				case _: continue;
			}
			var path = new Path();
			var x0 = Math.round(x), x1 = Math.round(x + width), y0 = Math.round(top);
			switch style {
				case "double":
					path.rect(x0, y0, x1 - x0, thickness);
					path.rect(x0, y0 + 2 * thickness, x1 - x0, thickness);
				case "dotted" | "dashed":
					var dash = style == "dotted" ? thickness : 3 * thickness;
					var xx:Float = x0;
					while (xx < x1) {
						path.rect(xx, y0, Math.min(dash, x1 - xx), thickness);
						xx += 2 * dash;
					}
				case _:
					path.rect(x0, y0, x1 - x0, thickness);
			}
			p.fill(path, Paint.solid(color));
		}
	}
}
