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
	final svg:Null<String->Null<helder.canvas.Svg>>;
	final glyphs = new Glyphs();
	// (the states pushed now, innermost last)
	final stack:Array<Int> = [];
	// each glyph's origin on a quarter pixel across and a whole one down, as
	// Skia quantizes subpixel-positioned text (Chromium's), collapsed borders
	// on whole pixels; off for a PDF, whose text and borders keep layout's
	// places (a tie rounds up, float noise aside)
	public var snap = true;
	// a list marker's disc, circle or square drawn as Chromium's shape; off:
	// as its text, the counter style's symbol and suffix (print's, as WeasyPrint's)
	public var shapes = true;
	// the canvas's background: the area it covers (null: the painter's
	// whole) and the box it is positioned in (null: the root's fragment);
	// a page's: its page area, the root's box over all the pages
	public var canvasArea:Null<Array<Float>> = null;
	// whether the root's background is the canvas's (CSS 2.1 §14.2); off: a
	// box of its own (a page's margin box)
	public var propagate = true;
	public var canvasBox:Null<Array<Float>> = null;
	// what is seen (x0, y0, x1, y1 in the painter's units; null: the
	// painter's whole): what is outside it is skipped, as outside the
	// painter (a window's view of a long document)
	public var area:Null<Array<Float>> = null;
	// the glyph runs placed, kept by the fragments' run each was placed from
	// (a view's, for the painters that keep what they are given: UiPainter); null: none kept
	public var placedRuns:Null<PlacedRuns> = null;
	// scroll containers' offsets (x, y) by their element: what they hold
	// moved back by them (PaintOrder.scroller); null: none scrolled
	public var scrolls:Null<haxe.ds.ObjectMap<{}, Array<Float>>> = null;
	// (each state's offset from its scrollers, x and y: culling where things are drawn)
	final shifts:Array<Float> = [];

	public function new(fragments:Fragments, order:PaintOrder, image:String->Null<Bitmap>, ?svg:String->Null<helder.canvas.Svg>) {
		f = fragments;
		this.order = order;
		this.image = image;
		this.svg = svg;
	}

	public function paint(p:Painter) {
		if (propagate) canvas(p);
		// (what is outside the painter is skipped, but under a transform, or with a shadow or an outline that may reach in;
		// a run of steps whose bounds miss it at once)
		var cull = p.matrix.isIdentity();
		var a = area;
		var ax0 = (a == null ? 0 : a[0]) - MARGIN, ay0 = (a == null ? 0 : a[1]) - MARGIN;
		var ax1 = (a == null ? p.width : a[2]) + MARGIN, ay1 = (a == null ? p.height : a[3]) + MARGIN;
		var shifted = scrolls != null && shift();
		// (into a display list: each flat context's calls a span, copied from the paint before where it is the same)
		var list = spans == null || PaintSpans.off ? null : listOf(p);
		if (list != null) {
			var sum = 0.0;
			if (shifted) for (v in shifts) sum = sum * 31 + v;
			spans.begin(order, list, area, sum);
			starts.resize(order.count);
			for (k in 0...order.count) starts[k] = -1;
			var r = order.contexts;
			while (r-- > 0) if (order.contextFlat(r) && order.contextEnd(r) > order.contextStart(r)) starts[order.contextStart(r)] = r;
			open.resize(0);
		} else if (spans != null) spans.none();
		// (runs of steps whose bounds miss what is seen passed over at once: chunks; with spans, a flat context
		// moved by its scrolls (a list's rows out of view))
		var runs = cull && list == null ? order.chunks() : null;
		var k = 0;
		while (k < order.count) {
			if (list != null) {
				// (the spans ending here kept; one starting here copied, else begun)
				while (open.length > 0 && open[open.length - 1] <= k) close();
				var r = starts[k];
				if (r >= 0 && cull) {
					var st = order.stateOf[k];
					if (order.contextMisses(r, shifted ? shifts[2 * st] : 0, shifted ? shifts[2 * st + 1] : 0, ax0, ay0, ax1, ay1)) {
						culled();
						k = order.contextEnd(r);
						continue;
					}
				}
				if (r >= 0) {
					enter(p, order.stateOf[k]);
					var q = spans.before(order, r);
					if (q >= 0 && spans.copy(r, q)) {
						k = order.contextEnd(r);
						continue;
					}
					spans.mark();
					open.push(r);
					open.push(list.markInts());
					open.push(list.markFloats());
					open.push(list.markResources());
					open.push(1);
					open.push(order.contextEnd(r));
				}
			}
			if (runs != null && k % PaintOrder.CHUNK == 0) {
				var r = Std.int(k / PaintOrder.CHUNK) * 4;
				if (runs[r] > ax1 || runs[r + 1] > ay1 || runs[r + 2] < ax0 || runs[r + 3] < ay0) {
					k += PaintOrder.CHUNK;
					continue;
				}
			}
			var id = order.fragments[k], x = order.xs[k], y = order.ys[k];
			k++;
			if (shifted) {
				var st = order.stateOf[k - 1];
				x -= shifts[2 * st];
				y -= shifts[2 * st + 1];
			}
			if (cull && !order.transformed[order.stateOf[k - 1]] && (y > ay1 || x > ax1 || y + f.height(id) < ay0 || x + f.width(id) < ax0)) {
				var st = f.box(id).style, r = st.reach;
				if (r != r) r = st.reach = reach(st);
				if (r == 0 || y - r > ay1 || x - r > ax1 || y + f.height(id) + r < ay0 || x + f.width(id) + r < ax0) {
					if (list != null) culled();
					continue;
				}
			}
			if (shifted) {
				x = order.xs[k - 1];
				y = order.ys[k - 1];
			}
			enter(p, order.stateOf[k - 1]);
			var b = f.box(id), s = b.style;
			switch order.steps[k - 1] {
				case PaintOrder.BACKGROUND:
					if (!s.visible) continue;
					if (f.kind(id) == Fragments.SPAN) span(p, id, x, y) else box(p, id, b, x, y);
				case PaintOrder.TEXT:
					if (s.visible) text(p, id, b, x, y);
				case PaintOrder.BORDERS:
					if (s.visible) collapsed(p, id, b, x, y);
				case PaintOrder.REPLACED:
					if (s.visible && (b.image != null || b.svg != null)) replaced(p, id, b, x, y);
				case PaintOrder.OUTLINE:
					if (s.visible && !(b.kind == Container && (s.part == BoxStyle.COLUMN || s.part == BoxStyle.COLUMN_GROUP))) {
						var w = f.width(id), h = f.height(id);
						Borders.outline(p, s, x, y, w, h);
					}
			}
		}
		if (list != null) while (open.length > 0) close();
		if (spans != null) spans.fresh = false;
		enter(p, 0);
	}

	static inline var MARGIN = 64;

	// the spans of what it paints into a display list, kept for the next paint (null: none)
	public var spans:Null<PaintSpans> = null;
	// (each step's flat context starting there, -1 none; the spans open: record, ints, floats, resources, whether
	// no step was culled, end)
	final starts:Array<Int> = [];
	final open:Array<Int> = [];

	// (the innermost open span kept)
	function close() {
		var n = open.length;
		spans.keep(open[n - 6], open[n - 5], open[n - 4], open[n - 3], open[n - 2] == 1);
		open.resize(n - 6);
	}

	// (a step culled: the spans open hold less than their steps)
	inline function culled() {
		var k = open.length - 2;
		while (k >= 0) {
			open[k] = 0;
			k -= 6;
		}
	}

	// (the display list a painter records into: helder.ui's)
	static function listOf(p:Painter):Null<helder.ui.draw.DisplayList> {
		if (!Std.isOfType(p, UiPainter)) return null;
		var c = @:privateAccess (cast p : UiPainter).canvas;
		return Std.isOfType(c, helder.ui.draw.DisplayList) ? cast c : null;
	}

	// (each state's offset from the scrollers around it; false: none scrolled)
	function shift():Bool {
		var any = false, n = order.parents.length;
		shifts.resize(2 * n);
		shifts[0] = shifts[1] = 0;
		for (s in 1...n) {
			var p = order.parents[s], dx = shifts[2 * p], dy = shifts[2 * p + 1];
			if (order.scroller[s]) {
				var o = scrolls.get(Box.scrollKey(f.box(order.layerFragment[s])));
				if (o != null) {
					dx += o[0];
					dy += o[1];
					any = true;
				}
			}
			shifts[2 * s] = dx;
			shifts[2 * s + 1] = dy;
		}
		return any;
	}

	// (how far past its border box a box paints: its shadows' and its outline's reach)
	@:allow(helder.ui.box.PaintOrder, helder.ui.box.Fragments) static function reach(s:BoxStyle):Float {
		var r = 0.0;
		var st = s.outlineStyle;
		if (st != "none" && st != "") r = s.outlineWidth + Math.abs(s.outlineOffset);
		var list = s.shadows;
		if (list != null) for (one in list) {
			var sum = 0.0;
			for (v in one.lengths) sum += Math.abs(v);
			r = Math.max(r, sum * 2);
		}
		return r;
	}

	// (the painter's state made the step's: layers and clips left and entered)
	final path:Array<Int> = [];

	function enter(p:Painter, st:Int) {
		var path = path;
		path.resize(0);
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
					if (order.scroller[s] && scrolls != null) {
						var o = scrolls.get(Box.scrollKey(f.box(order.layerFragment[s])));
						if (o != null) p.translate(-o[0], -o[1]);
					}
			}
		}
	}

	function box(p:Painter, id:Int, b:Box, x:Float, y:Float) {
		if (b.kind == TableWrapper) return;
		var s = b.style, w = f.width(id), h = f.height(id);
		// (an empty cell's, under empty-cells: hide in the separated borders model: nothing, §17.6.1.1)
		if (b.flags & (Box.EMPTY | Box.COLLAPSED) == Box.EMPTY && s.rare.emptyCells == "hide") return;
		var part = s.part;
		Borders.shadows(p, s, x, y, w, h, false);
		var cells = part == BoxStyle.ROW || part == BoxStyle.ROW_GROUP || part == BoxStyle.COLUMN || part == BoxStyle.COLUMN_GROUP ? gridCells(id, b, x, y, w, h) : null;
		if (cells != null) {
			p.save();
			p.clip(cells);
		}
		// (a block's fragment in a fragmentainer: its start or end in another, box-decoration-break: slice)
		var noTop = f.start(id) == Box.NO_START, noBottom = f.end(id) == Box.NO_END;
		if (b != order.canvas || !propagate) Backgrounds.paint(p, s, x, y, w, h, image, null, false, false, noTop, noBottom, svg);
		if (cells != null) p.restore();
		Borders.shadows(p, s, x, y, w, h, true);
		// (rows, columns and their groups have no borders of their own but collapsed; collapsed ones are the table's)
		if (b.flags & Box.COLLAPSED == 0 && (part == 0 || part == BoxStyle.CELL || part == BoxStyle.CAPTION))
			Borders.paint(p, s, x, y, w, h, false, false, noTop, noBottom);
	}

	// (a row's, column's or group's background shows in its cells, not in the spacing between them, §17.5.1:
	// the grid's cells under its rectangle; null where there is no spacing)
	function gridCells(id:Int, b:Box, x:Float, y:Float, w:Float, h:Float):Null<Path> {
		var t = b.parent;
		while (t != null && !(t.kind == Container && t.style.inner == BoxStyle.TABLE)) t = t.parent;
		// (the table's fragment around this one: its grid)
		var k = id;
		while (k >= 0 && f.box(k) != t) k = f.parent(k);
		var g = t == null ? null : TableGrid.of(t.table, k);
		if (g == null || g.spacing == 0 || g.fragment < 0) return null;
		var o = f.absolute(g.fragment);
		var path = new Path();
		for (r in 0...g.rows) for (c in 0...g.columns) {
			if (g.hides(r)) continue;
			var cx = o.x + g.x[c], cy = o.y + g.y[r];
			if (cx + g.widths[c] <= x || cx >= x + w || cy + g.heights[r] <= y || cy >= y + h) continue;
			path.rect(Math.round(cx), Math.round(cy), Math.round(cx + g.widths[c]) - Math.round(cx), Math.round(cy + g.heights[r]) - Math.round(cy));
		}
		return path;
	}

	// (a table's collapsed borders, §17.6.2: each line's segments, a horizontal one over the vertical
	// lines' half widths at its ends; double, dotted and the rest drawn solid)
	function collapsed(p:Painter, id:Int, b:Box, x:Float, y:Float) {
		var g = TableGrid.of(b.table, id);
		if (g == null || !g.collapse) return;
		var rows = g.rows, cols = g.columns;
		inline function colLeft(c:Int):Float
			return c < cols ? g.x[c] : g.x[cols - 1] + g.widths[cols - 1];
		inline function rowTop(r:Int):Float
			return r < rows ? g.y[r] : g.y[rows - 1] + g.heights[rows - 1];
		inline function px(v:Float):Float
			return snap ? Math.round(v) : v;
		var path = new Path();
		// (in a fragmentainer: the lines of the rows here, a horizontal one beside one of them)
		for (r in 0...rows) for (c in 0...cols + 1) {
			if (g.hides(r)) continue;
			var k = g.v(r, c), w = g.vPainted(k);
			if (w <= 0) continue;
			var lx = px(x + colLeft(c) - g.half(w, false)), ty = px(y + rowTop(r)), by = px(y + rowTop(r + 1));
			fillRect(p, path, lx, ty, w, by - ty, g.vColor[k]);
		}
		for (r in 0...rows + 1) for (c in 0...cols) {
			if (g.shown != null && (r == 0 || g.hides(r - 1)) && (r == rows || g.hides(r))) continue;
			var k = g.h(r, c), w = g.hPainted(k);
			if (w <= 0) continue;
			var left = 0.0, right = 0.0;
			for (rr in [r - 1, r]) if (rr >= 0 && rr < rows) {
				left = Math.max(left, g.half(g.vPainted(g.v(rr, c)), false));
				right = Math.max(right, g.half(g.vPainted(g.v(rr, c + 1)), true));
			}
			var lx = px(x + colLeft(c) - left), rx = px(x + colLeft(c + 1) + right);
			var ty = px(y + rowTop(r) - g.half(w, false));
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
			Backgrounds.paint(p, b.style, at[0], at[1], at[2], at[3], image, canvasArea ?? [0.0, 0.0, p.width * 1.0, p.height * 1.0], false, false, false, false, svg);
			return;
		}
	}

	function span(p:Painter, id:Int, x:Float, y:Float) {
		var b = f.box(id), s = b.style, w = f.width(id), h = f.height(id);
		var noLeft = f.start(id) == Box.NO_START, noRight = f.end(id) == Box.NO_END;
		Backgrounds.paint(p, s, x, y, w, h, image, null, noLeft, noRight, false, false, svg);
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
		// (an SVG as its paths, on whole pixels as an image is: an image's in black, its own document's colour; an inline one's paint is the cascade's)
		if (b.svg != null) {
			var own = b.flags & Box.INLINE_SVG != 0;
			b.svg.paint(p, x0, y0, Math.round(dx + dw) - x0, Math.round(dy + dh) - y0, own ? b.style.text.colour : 0xFF000000);
			return;
		}
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
		if (!shapes || !b.markerPseudo() || marker == null || !marker.markerPseudo() || run.text == null) return false;
		var symbol = marker.markerSymbol();
		if (symbol == null || StringTools.trim(run.shown()) != symbol) return false;
		if (color >>> 24 == 0) return true;
		var a = Math.round(FontMatch.ascent(run.face, run.size)), offset = Std.int(a * 2 / 3), size = Std.int((offset + 1) / 2);
		// (outside: from the line's start, its marker span's end: whatever its text's trailing space)
		var span = f.parent(id);
		var hasSpan = span >= 0 && f.kind(span) == Fragments.SPAN;
		var start = hasSpan ? x - f.x(id) : x, width = f.width(hasSpan ? span : id);
		var line = hasSpan ? f.parent(span) : -1;
		var rtl = line >= 0 ? f.box(line).style.rtl : marker.style.rtl;
		var px = marker.flags & Box.OUTSIDE == 0 ? x : rtl ? start + offset + 7 - size : start + width - offset - 7;
		var x0 = Math.round(px), y0 = Math.round(baseline) - a + Std.int(3 * (a - offset) / 2);
		var path = new Path();
		switch symbol {
			case "\u25AA":
				path.rect(x0, y0, size, size);
				p.fill(path, Paint.solid(color));
			case "\u25E6":
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
		var run = f.glyphs(id);
		if (run == null) return;
		var s = b.style;
		var baseline = y + f.baseline(id);
		var color = s.text.colour;
		if (symbol(p, id, b, run, x, baseline, color)) return;
		var decorations = decorating(b);
		// (underlines and overlines under the text, line-throughs over it)
		for (d in decorations) decorate(p, d, run, x, baseline, f.width(id), false);
		// (a painter that draws the run where it is placed: nothing copied here)
		if (color >>> 24 != 0 && Std.isOfType(p, RunText) && (cast p : RunText).runText(run, x, baseline, snap, Paint.solid(color))) {} else if (color >>> 24 != 0) {
			// (placed before at the same place: the same, a window's repaint allocating none)
			var placed = placedRuns != null && placedRuns.runs[r] != null && placedRuns.xs[r] == x && placedRuns.ys[r] == baseline && placedRuns.snapped[r] == snap ? placedRuns.runs[r] : null;
			if (placed != null) placedRuns.touch(r);
			if (placed == null) {
				placed = new ShapedRun(run.face, run.size);
				placed.text = run.text;
				placed.skew = run.skew;
				placed.bold = run.bold;
				placed.palette = run.palette;
				for (k in 0...run.count) {
					var gx = x + run.x(k), gy = baseline + run.y(k);
					placed.push(run.id(k), snap ? Math.floor(gx * 4 + 0.5 + 1e-3) / 4 : gx, snap ? Math.round(gy) : gy, run.start(k), run.end(k));
				}
				if (placedRuns != null) placedRuns.keep(r, placed, x, baseline, snap);
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
		var out = NONE;
		var a = b.kind == Text ? b.parent : b;
		while (a != null) {
			if (a.style.decorates()) {
				if (out == NONE) out = [];
				out.push(a.style);
			}
			if (a.kind == InlineBlock || a.kind == Container || a.style.floating || a.style.absolute) break;
			a = a.parent;
		}
		return out;
	}

	static final NONE:Array<BoxStyle> = [];
	static final LINES = ["underline", "overline", "line-through"];

	function decorate(p:Painter, d:BoxStyle, run:ShapedRun, x:Float, baseline:Float, width:Float, over:Bool) {
		var t = d.text, color = t.decorationColour;
		if (color >>> 24 == 0 || width <= 0) return;
		var u = FontMatch.underline(run.face, run.size), strike = FontMatch.strikeout(run.face, run.size);
		// (auto: a tenth of the font size, as Chromium's; from-font: the font's own)
		var auto = run.size / 10;
		var given = d.rare.fromFont ? (over ? strike.thickness : u.thickness) : t.decorationThickness == t.decorationThickness ? t.decorationThickness : auto;
		var thickness = Math.max(1, Math.floor(given));
		var style = switch t.decorationStyle {
			case Double: "double";
			case Dotted: "dotted";
			case Dashed: "dashed";
			case Wavy: "wavy";
			case _: "solid";
		}
		for (line in LINES) {
			if (t.decoration & (line == "underline" ? helder.ui.flow.InlineValues.InlineDecoration.Underline : line == "overline" ? helder.ui.flow.InlineValues.InlineDecoration.Overline : helder.ui.flow.InlineValues.InlineDecoration.LineThrough) == 0) continue;
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

// (BoxPainter.placedRuns: by the fragments' run index, its run placed, where
// and whether snapped; kept while placed in this paint or the last: next)
class PlacedRuns {
	public final runs:Array<Null<ShapedRun>> = [];
	public final xs:Array<Float> = [];
	public final ys:Array<Float> = [];
	public final snapped:Array<Bool> = [];
	final stamps:Array<Int> = [];
	var kept:Array<Int> = [];
	var stamp = 1;

	public function new() {}

	public function keep(r:Int, run:ShapedRun, x:Float, y:Float, snap:Bool) {
		runs[r] = run;
		xs[r] = x;
		ys[r] = y;
		snapped[r] = snap;
		touch(r);
	}

	// (r placed again in this paint)
	public function touch(r:Int) {
		if (stamps[r] == stamp) return;
		stamps[r] = stamp;
		kept.push(r);
	}

	// a paint begins: the runs neither it nor the last placed let go
	public function next() {
		stamp++;
		var still = [];
		for (r in kept) if (stamps[r] >= stamp - 1) still.push(r) else runs[r] = null;
		kept = still;
	}

	public function clear() {
		runs.resize(0);
		xs.resize(0);
		ys.resize(0);
		snapped.resize(0);
		stamps.resize(0);
		kept = [];
	}
}
