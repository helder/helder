package helder.ui.box;

import helder.canvas.Filter.Blur;
import helder.canvas.Paint;
import helder.canvas.Painter;
import helder.canvas.Path;
import helder.canvas.Stroke;
import helder.css.CssTerm;

// Borders (Backgrounds 3 §4: each side's width, style and colour, the
// corners split on their diagonals, border-radius's curves), outlines
// (UI 4 §3) and box shadows (§7), painted on a Painter. Rectangles are
// snapped to whole pixels first, as browsers paint them.
class Borders {
	// The corner radii of a border box w by h: top-left, top-right,
	// bottom-right, bottom-left, x and y each; scaled down where they
	// would overlap (§5.5). Null: square corners.
	public static function radii(s:BoxStyle, w:Float, h:Float):Null<Array<Float>> {
		var r = [];
		var any = false;
		for (c in CORNERS) switch s.terms('border-$c-radius') {
			case [a, b]:
				r.push(Transforms.length(a, w));
				r.push(Transforms.length(b, h));
			case [a]:
				r.push(Transforms.length(a, w));
				r.push(Transforms.length(a, h));
			case _:
				r.push(0);
				r.push(0);
		}
		for (v in r) if (v > 0) any = true;
		if (!any) return null;
		var f = 1.0;
		inline function fit(sum:Float, side:Float)
			if (sum > side && sum > 0) f = Math.min(f, side / sum);
		fit(r[0] + r[2], w);
		fit(r[6] + r[4], w);
		fit(r[1] + r[7], h);
		fit(r[3] + r[5], h);
		return f < 1 ? [for (v in r) v * f] : r;
	}

	static final CORNERS = ["top-left", "top-right", "bottom-right", "bottom-left"];

	// (radii shrunk by insets: top, right, bottom, left)
	public static function inset(r:Null<Array<Float>>, t:Float, right:Float, b:Float, l:Float):Null<Array<Float>> {
		if (r == null) return null;
		inline function p(v:Float):Float
			return v < 0 ? 0 : v;
		return [p(r[0] - l), p(r[1] - t), p(r[2] - right), p(r[3] - t), p(r[4] - right), p(r[5] - b), p(r[6] - l), p(r[7] - b)];
	}

	public static function rect(path:Path, x:Float, y:Float, w:Float, h:Float, r:Null<Array<Float>>) {
		if (w <= 0 || h <= 0) return;
		if (r == null) path.rect(x, y, w, h) else path.roundRectXY(x, y, w, h, r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7]);
	}

	// Chromium's Color::Dark(), what inset, outset, groove and ridge shade with
	public static function dark(c:Int):Int {
		var a = c >>> 24, r = (c >> 16) & 255, g = (c >> 8) & 255, b = c & 255;
		if (r == 0 && g == 0 && b == 0) return (a << 24) | 0x545454;
		var v = Math.max(r, Math.max(g, b)) / 255;
		var m = Math.max(0, (v - 0.33) / v);
		inline function ch(x:Int):Int
			return Std.int(x / 255 * m * 255.99);
		return (a << 24) | (ch(r) << 16) | (ch(g) << 8) | ch(b);
	}

	static final SIDES = ["top", "right", "bottom", "left"];

	// The box's borders around (x, y, w, h); left and right left out where an inline box is split.
	public static function paint(p:Painter, s:BoxStyle, x:Float, y:Float, w:Float, h:Float, noLeft = false, noRight = false) {
		var m = s.model();
		var widths = [m.border[0], noRight ? 0 : m.border[1], m.border[2], noLeft ? 0 : m.border[3]];
		if (widths[0] + widths[1] + widths[2] + widths[3] == 0) return;
		var styles = [for (k in 0...4) s.keyword('border-${SIDES[k]}-style')];
		var colors = [for (k in 0...4) s.color('border-${SIDES[k]}-color')];
		var x0 = Math.round(x), y0 = Math.round(y), x1 = Math.round(x + w), y1 = Math.round(y + h);
		draw(p, x0, y0, x1 - x0, y1 - y0, widths, styles, colors, radii(s, x1 - x0, y1 - y0));
	}

	public static function draw(p:Painter, x:Float, y:Float, w:Float, h:Float, widths:Array<Float>, styles:Array<String>, colors:Array<Int>,
			r:Null<Array<Float>>) {
		var t = widths[0], rt = widths[1], b = widths[2], l = widths[3];
		var visible = [for (k in 0...4) widths[k] > 0 && styles[k] != "none" && styles[k] != "hidden" && colors[k] >>> 24 != 0];
		var same = true;
		for (k in 1...4) if (styles[k] != styles[0] || colors[k] != colors[0] || !visible[k]) same = false;
		var ring = new Path();
		rect(ring, x, y, w, h, r);
		rect(ring, x + l, y + t, w - l - rt, h - t - b, inset(r, t, rt, b, l));
		if (same && visible[0] && styles[0] == "solid") {
			p.fill(ring, Paint.solid(colors[0]), true);
			return;
		}
		// (each side's wedge: from its outer corners to the inner ones)
		var ix0 = x + l, iy0 = y + t, ix1 = x + w - rt, iy1 = y + h - b;
		var wedges = [
			[x, y, x + w, y, ix1, iy0, ix0, iy0],
			[x + w, y, x + w, y + h, ix1, iy1, ix1, iy0],
			[x + w, y + h, x, y + h, ix0, iy1, ix1, iy1],
			[x, y + h, x, y, ix0, iy0, ix0, iy1]
		];
		var clipped = r != null;
		if (clipped) {
			p.save();
			p.clip(ring, true);
		}
		for (k in 0...4) {
			if (!visible[k]) continue;
			var wedge = new Path();
			var q = wedges[k];
			wedge.moveTo(q[0], q[1]);
			wedge.lineTo(q[2], q[3]);
			wedge.lineTo(q[4], q[5]);
			wedge.lineTo(q[6], q[7]);
			wedge.close();
			var c = colors[k], st = styles[k];
			var topLeft = k == 0 || k == 3;
			switch st {
				case "solid":
					p.fill(wedge, Paint.solid(c));
				case "inset" | "outset":
					p.fill(wedge, Paint.solid((st == "inset") == topLeft ? dark(c) : c));
				case "double" if (widths[k] >= 3):
					p.save();
					p.clip(wedge);
					var third = [for (v in widths) Math.floor((v + 1) / 3)];
					var outer = new Path();
					rect(outer, x, y, w, h, r);
					rect(outer, x + third[3], y + third[0], w - third[3] - third[1], h - third[0] - third[2], inset(r, third[0], third[1], third[2], third[3]));
					p.fill(outer, Paint.solid(c), true);
					var inner = new Path();
					var ox = [for (k in 0...4) widths[k] - third[k]];
					rect(inner, x + ox[3], y + ox[0], w - ox[3] - ox[1], h - ox[0] - ox[2], inset(r, ox[0], ox[1], ox[2], ox[3]));
					rect(inner, x + l, y + t, w - l - rt, h - t - b, inset(r, t, rt, b, l));
					p.fill(inner, Paint.solid(c), true);
					p.restore();
				case "groove" | "ridge":
					p.save();
					p.clip(wedge);
					var half = [for (v in widths) Math.floor(v / 2)];
					var outerDark = (st == "groove") == topLeft;
					var outer = new Path();
					rect(outer, x, y, w, h, r);
					rect(outer, x + half[3], y + half[0], w - half[3] - half[1], h - half[0] - half[2], inset(r, half[0], half[1], half[2], half[3]));
					p.fill(outer, Paint.solid(outerDark ? dark(c) : c), true);
					var inner = new Path();
					rect(inner, x + half[3], y + half[0], w - half[3] - half[1], h - half[0] - half[2], inset(r, half[0], half[1], half[2], half[3]));
					rect(inner, x + l, y + t, w - l - rt, h - t - b, inset(r, t, rt, b, l));
					p.fill(inner, Paint.solid(outerDark ? c : dark(c)), true);
					p.restore();
				case "dotted" | "dashed":
					p.save();
					p.clip(wedge);
					var bw = widths[k];
					var line = new Path();
					switch k {
						case 0: line.moveTo(x, y + t / 2); line.lineTo(x + w, y + t / 2);
						case 1: line.moveTo(x + w - rt / 2, y); line.lineTo(x + w - rt / 2, y + h);
						case 2: line.moveTo(x + w, y + h - b / 2); line.lineTo(x, y + h - b / 2);
						case _: line.moveTo(x + l / 2, y + h); line.lineTo(x + l / 2, y);
					}
					var stroke = new Stroke(bw);
					var length = k == 0 || k == 2 ? w : h;
					if (st == "dotted") {
						var n = Math.max(1, Math.round(length / (2 * bw)));
						var gap = length / n;
						if (bw >= 3) {
							stroke.cap = helder.canvas.Stroke.Cap.round;
							stroke.dash = new helder.canvas.Stroke.Dash([0, gap], -gap / 4 + bw / 2 - gap / 4);
						} else
							stroke.dash = new helder.canvas.Stroke.Dash([gap / 2, gap / 2]);
					} else {
						var dash = 3 * bw;
						var n = Math.max(1, Math.round((length + dash) / (2 * dash)));
						var period = (length + dash) / n;
						stroke.dash = new helder.canvas.Stroke.Dash([dash, period - dash]);
					}
					p.stroke(line, stroke, Paint.solid(c));
					p.restore();
				case _:
					p.fill(wedge, Paint.solid(c));
			}
		}
		if (clipped) p.restore();
	}

	// The outline outside the border box (x, y, w, h), its offset apart.
	public static function outline(p:Painter, s:BoxStyle, x:Float, y:Float, w:Float, h:Float) {
		var st = s.keyword("outline-style");
		if (st == "none" || st == "") return;
		var ow = s.px("outline-width");
		if (ow <= 0) return;
		var off = s.px("outline-offset");
		var c = switch s.terms("outline-color") {
			case [Keyword("auto" | "invert")]: s.color("color");
			case _: s.color("outline-color");
		}
		if (st == "auto") st = "solid";
		var x0 = Math.round(x) - off - ow, y0 = Math.round(y) - off - ow;
		var x1 = Math.round(x + w) + off + ow, y1 = Math.round(y + h) + off + ow;
		var r = radii(s, Math.round(x + w) - Math.round(x), Math.round(y + h) - Math.round(y));
		if (r != null) r = [for (v in r) v > 0 ? v + off + ow : 0];
		draw(p, x0, y0, x1 - x0, y1 - y0, [ow, ow, ow, ow], [st, st, st, st], [c, c, c, c], r);
	}

	// (a blurred shape in an image of its own size, the blur's reach around it, drawn
	// at its place: a layer of the whole painter blurred for each shadow costs the page)
	static function blurred(p:Painter, x:Float, y:Float, w:Float, h:Float, r:Null<Array<Float>>, blur:Float, color:Int) {
		var pad = Math.ceil(blur * 1.5) + 2;
		var iw = Math.ceil(w) + 2 * pad, ih = Math.ceil(h) + 2 * pad;
		if (iw <= 0 || ih <= 0 || iw * ih > 4096 * 4096) return;
		var off = p.offscreen(iw, ih);
		off.saveLayer(1, null, null, new Blur(blur / 2));
		var shape = new Path();
		rect(shape, pad, pad, w, h, r);
		off.fill(shape, Paint.solid(color));
		off.restore();
		p.drawImage(off.snapshot(), 0, 0, iw, ih, Math.floor(x) - pad, Math.floor(y) - pad, iw, ih, PLAIN, false);
	}

	static final PLAIN = new Paint();

	// Box shadows (§7.1): outer ones outside the border box (under the background), or inset ones inside
	// the padding box (over it); the first on top.
	public static function shadows(p:Painter, s:BoxStyle, x:Float, y:Float, w:Float, h:Float, insets:Bool) {
		var terms = s.terms("box-shadow");
		if (terms.length == 0 || terms[0].match(Keyword("none"))) return;
		var list:Array<Array<CssTerm>> = [[]];
		for (t in terms) if (t.match(Delim(","))) list.push([]) else list[list.length - 1].push(t);
		var x0 = Math.round(x), y0 = Math.round(y), bw = Math.round(x + w) - x0, bh = Math.round(y + h) - y0;
		var r = radii(s, bw, bh);
		var m = s.model();
		var k = list.length;
		while (k-- > 0) {
			var color = s.color("color"), inner = false, lengths = [];
			for (t in list[k]) switch t {
				case Color(c): color = BoxStyle.argb(c, s.color("color"));
				case Keyword("inset"): inner = true;
				case Dimension(v, _): lengths.push(v);
				case _:
			}
			while (lengths.length < 4) lengths.push(0);
			var ox = lengths[0], oy = lengths[1], blur = lengths[2], spread = lengths[3];
			if (color >>> 24 == 0 || inner != insets) continue;
			p.save();
			var big = new Path();
			if (!inner) {
				big.rect(x0 - 10000, y0 - 10000, bw + 20000, bh + 20000);
				rect(big, x0, y0, bw, bh, r);
				p.clip(big, true);
				var shape = new Path();
				var sr = r == null ? null : [for (v in r) v > 0 ? Math.max(0, v + spread) : 0];
				var sx = x0 + ox - spread, sy = y0 + oy - spread, sw = bw + 2 * spread, sh = bh + 2 * spread;
				if (blur > 0) blurred(p, sx, sy, sw, sh, sr, blur, color) else {
					rect(shape, sx, sy, sw, sh, sr);
					p.fill(shape, Paint.solid(color));
				}
			} else {
				var px = x0 + m.border[3], py = y0 + m.border[0], pw = bw - m.border[1] - m.border[3], ph = bh - m.border[0] - m.border[2];
				var pr = inset(r, m.border[0], m.border[1], m.border[2], m.border[3]);
				var clip = new Path();
				rect(clip, px, py, pw, ph, pr);
				p.clip(clip);
				var ir = pr == null ? null : [for (v in pr) v > 0 ? Math.max(0, v - spread) : 0];
				// (the shadow is the padding box less the hole: drawn in an image of its size, blurred there)
				var pad = blur > 0 ? Math.ceil(blur * 1.5) + 2 : 0;
				var iw = Math.ceil(pw) + 2 * pad, ih = Math.ceil(ph) + 2 * pad;
				if (iw > 0 && ih > 0 && iw * ih <= 4096 * 4096) {
					var to:Painter = blur > 0 ? p.offscreen(iw, ih) : p;
					var dx = blur > 0 ? pad - px : 0.0, dy = blur > 0 ? pad - py : 0.0;
					if (blur > 0) to.saveLayer(1, null, null, new Blur(blur / 2));
					var shape = new Path();
					shape.rect(px - pad + dx, py - pad + dy, iw, ih);
					rect(shape, px + ox + spread + dx, py + oy + spread + dy, pw - 2 * spread, ph - 2 * spread, ir);
					to.fill(shape, Paint.solid(color), true);
					if (blur > 0) {
						to.restore();
						p.drawImage(to.snapshot(), 0, 0, iw, ih, px - pad, py - pad, iw, ih, PLAIN, false);
					}
				}
			}
			p.restore();
		}
	}
}
