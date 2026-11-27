package helder.ui.box;

import helder.ui.box.Len.Lens;

import helder.canvas.Bitmap;
import helder.canvas.Canvas;
import helder.canvas.Gradient;
import helder.canvas.Paint;
import helder.canvas.Painter;
import helder.canvas.Path;
import helder.canvas.Pattern;
import helder.css.CssTerm;

// Backgrounds (Backgrounds 3 §3): the colour under the bottom layer's
// clip, then each layer from the last: its image (a url()'s bitmap, or a
// linear or radial gradient, repeating or not, Images 3) sized, placed
// and tiled in its origin box, clipped to its clip box, rounded corners
// included.
class Backgrounds {
	// The background of a box at (x, y, w, h) (its border box); area: where it is painted
	// instead of its clip box (the canvas's), positioned from the box all the same.
	public static function paint(p:Painter, s:BoxStyle, x:Float, y:Float, w:Float, h:Float, image:String->Null<Bitmap>, ?area:Array<Float>,
			noLeft = false, noRight = false, noTop = false, noBottom = false, ?svg:String->Null<helder.canvas.Svg>) {
		var color = s.backgroundColor, parts = s.background;
		if (color >>> 24 == 0 && parts == null) return;
		// (a colour alone, the common case: its clip box filled, nothing else made)
		if (parts == null && area == null) {
			var x0 = Math.round(x), y0 = Math.round(y), bw = Math.round(x + w) - x0, bh = Math.round(y + h) - y0;
			var r = Borders.radii(s, bw, bh), path = new Path();
			switch s.backgroundClip {
				case "padding-box" | "content-box":
					var m = s.model(), content = s.backgroundClip == "content-box";
					var bl = noLeft ? 0 : m.border[3], br = noRight ? 0 : m.border[1], bt = noTop ? 0 : m.border[0], bb = noBottom ? 0 : m.border[2];
					if (content) {
						bl += noLeft ? 0 : Lens.resolve(m.padding[3], w, 0);
						br += noRight ? 0 : Lens.resolve(m.padding[1], w, 0);
						bt += noTop ? 0 : Lens.resolve(m.padding[0], w, 0);
						bb += noBottom ? 0 : Lens.resolve(m.padding[2], w, 0);
					}
					Borders.rect(path, x0 + bl, y0 + bt, bw - bl - br, bh - bt - bb, Borders.inset(r, bt, br, bb, bl));
				case _:
					Borders.rect(path, x0, y0, bw, bh, r);
			}
			p.fill(path, Paint.solid(color));
			return;
		}
		var images = parts == null ? NONE : parts.images;
		var none = parts == null;
		var x0 = Math.round(x), y0 = Math.round(y), bw = Math.round(x + w) - x0, bh = Math.round(y + h) - y0;
		var m = s.model();
		var r = Borders.radii(s, bw, bh);
		var bl = noLeft ? 0 : m.border[3], br = noRight ? 0 : m.border[1];
		var pl = noLeft ? 0 : Lens.resolve(m.padding[3], w, 0), pr = noRight ? 0 : Lens.resolve(m.padding[1], w, 0);
		var pt = noTop ? 0 : Lens.resolve(m.padding[0], w, 0), pb = noBottom ? 0 : Lens.resolve(m.padding[2], w, 0);
		var bt = noTop ? 0 : m.border[0], bb = noBottom ? 0 : m.border[2];
		function box(which:String):{x:Float, y:Float, w:Float, h:Float, r:Null<Array<Float>>}
			return switch which {
				case "padding-box": {
						x: x0 + bl,
						y: y0 + bt,
						w: bw - bl - br,
						h: bh - bt - bb,
						r: Borders.inset(r, bt, br, bb, bl)
					};
				case "content-box": {
						x: x0 + bl + pl,
						y: y0 + bt + pt,
						w: bw - bl - br - pl - pr,
						h: bh - bt - bb - pt - pb,
						r: Borders.inset(r, bt + pt, br + pr, bb + pb, bl + pl)
					};
				case _: {x: x0, y: y0, w: bw, h: bh, r: r};
			}
		var clips = parts == null ? [[Keyword(s.backgroundClip)]] : parts.clips;
		var origins = parts == null ? NONE : parts.origins;
		var sizes = parts == null ? NONE : parts.sizes;
		var repeats = parts == null ? NONE : parts.repeats;
		var xs = parts == null ? NONE : parts.xs, ys = parts == null ? NONE : parts.ys;
		var attachments = parts == null ? NONE : parts.attachments;
		inline function at<T>(list:Array<Array<T>>, k:Int):Array<T>
			return list[k % list.length];
		inline function word(t:Array<CssTerm>, fallback:String):String
			return switch t {
				case [Keyword(k)]: k;
				case _: fallback;
			}
		function clipPath(c:{x:Float, y:Float, w:Float, h:Float, r:Null<Array<Float>>}):Path {
			var path = new Path();
			if (area != null) path.rect(area[0], area[1], area[2], area[3]) else Borders.rect(path, c.x, c.y, c.w, c.h, c.r);
			return path;
		}
		var last = images.length - 1;
		if (color >>> 24 != 0) p.fill(clipPath(box(word(at(clips, last), "border-box"))), Paint.solid(color));
		if (none) return;
		var k = images.length;
		while (k-- > 0) {
			var img = images[k];
			if (img.length != 1) continue;
			var bitmap:Null<Bitmap> = null, gradient:Null<CssTerm> = null, vector:Null<helder.canvas.Svg> = null;
			switch img[0] {
				case Url(url, _):
					bitmap = image(url);
					if (bitmap == null && svg != null) vector = svg(url);
					if (vector == null && (bitmap == null || bitmap.width == 0 || bitmap.height == 0)) continue;
				case Func(_, _): gradient = img[0];
				case _: continue;
			}
			var c = box(word(at(clips, k), "border-box"));
			var o = box(word(at(origins, k), "padding-box"));
			if (word(at(attachments, k), "scroll") == "fixed") o = {x: 0, y: 0, w: p.width, h: p.height, r: null};
			if (o.w <= 0 || o.h <= 0) continue;
			var iw = bitmap == null ? Math.NaN : bitmap.width * 1.0, ih = bitmap == null ? Math.NaN : bitmap.height * 1.0, ratio = iw / ih;
			if (vector != null) {
				iw = vector.naturalWidth;
				ih = vector.naturalHeight;
				ratio = vector.ratio;
			}
			var tile = size(at(sizes, k), o.w, o.h, iw, ih, ratio);
			var rep = at(repeats, k);
			var rx = word([rep[0]], "repeat"), ry = rep.length > 1 ? word([rep[1]], "repeat") : rx;
			if (rx == "repeat-x") {
				rx = "repeat";
				ry = "no-repeat";
			} else if (rx == "repeat-y") {
				rx = "no-repeat";
				ry = "repeat";
			}
			if (rx == "round") tile.w = o.w / Math.max(1, Math.round(o.w / tile.w));
			if (ry == "round") tile.h = o.h / Math.max(1, Math.round(o.h / tile.h));
			if (rx == "round" && ry != "round" && !Math.isNaN(ratio) && sizeAuto(at(sizes, k), 1)) tile.h = tile.w / ratio;
			if (tile.w <= 0 || tile.h <= 0) continue;
			var px = o.x + Lens.resolve(BoxStyle.toLen(at(xs, k)), o.w - tile.w, 0);
			var py = o.y + Lens.resolve(BoxStyle.toLen(at(ys, k)), o.h - tile.h, 0);
			var gapX = 0.0, gapY = 0.0;
			if (rx == "space") {
				var n = Math.floor(o.w / tile.w);
				if (n >= 2) {
					gapX = (o.w - n * tile.w) / (n - 1);
					px = o.x;
				} else
					rx = "no-repeat";
			}
			if (ry == "space") {
				var n = Math.floor(o.h / tile.h);
				if (n >= 2) {
					gapY = (o.h - n * tile.h) / (n - 1);
					py = o.y;
				} else
					ry = "no-repeat";
			}
			p.save();
			p.clip(clipPath(c));
			var cx0 = area != null ? area[0] : c.x, cy0 = area != null ? area[1] : c.y;
			var cx1 = area != null ? area[0] + area[2] : c.x + c.w, cy1 = area != null ? area[1] + area[3] : c.y + c.h;
			if (vector != null) {
				// (an SVG's tiles each its paths: vectors in a PDF)
				var stepX = tile.w + gapX, stepY = tile.h + gapY;
				var sx = rx == "no-repeat" ? px : px - Math.ceil((px - cx0) / stepX) * stepX;
				var ty = ry == "no-repeat" ? py : py - Math.ceil((py - cy0) / stepY) * stepY;
				while (ty < cy1) {
					var tx = sx;
					while (tx < cx1) {
						vector.paint(p, tx, ty, tile.w, tile.h, 0xFF000000);
						if (rx == "no-repeat") break;
						tx += stepX;
					}
					if (ry == "no-repeat") break;
					ty += stepY;
				}
			} else if (gradient != null && rx == "no-repeat" && ry == "no-repeat") {
				var shader = Gradients.shader(gradient, px, py, tile.w, tile.h);
				if (shader != null) {
					var path = new Path();
					path.rect(px, py, tile.w, tile.h);
					p.fill(path, Paint.shaded(shader));
				}
			} else if (gapX == 0 && gapY == 0) {
				if (gradient != null) bitmap = Gradients.tile(gradient, tile.w, tile.h);
				if (bitmap != null) {
					var pattern = new Pattern(bitmap, rx != "no-repeat", ry != "no-repeat", gradient == null);
					pattern.matrix.translate(px, py).scale(tile.w / bitmap.width, tile.h / bitmap.height);
					var path = new Path();
					var fx0 = rx == "no-repeat" ? Math.max(cx0, px) : cx0, fx1 = rx == "no-repeat" ? Math.min(cx1, px + tile.w) : cx1;
					var fy0 = ry == "no-repeat" ? Math.max(cy0, py) : cy0, fy1 = ry == "no-repeat" ? Math.min(cy1, py + tile.h) : cy1;
					if (fx1 > fx0 && fy1 > fy0) {
						path.rect(fx0, fy0, fx1 - fx0, fy1 - fy0);
						p.fill(path, Paint.shaded(pattern));
					}
				}
			} else {
				if (gradient != null) bitmap = Gradients.tile(gradient, tile.w, tile.h);
				if (bitmap != null) {
					var stepX = tile.w + gapX, stepY = tile.h + gapY;
					var sx = rx == "no-repeat" ? px : px - Math.ceil((px - cx0) / stepX) * stepX;
					var sy = ry == "no-repeat" ? py : py - Math.ceil((py - cy0) / stepY) * stepY;
					var ty = sy;
					while (ty < cy1) {
						var tx = sx;
						while (tx < cx1) {
							p.drawImage(bitmap, 0, 0, bitmap.width, bitmap.height, tx, ty, tile.w, tile.h, PLAIN, gradient == null);
							if (rx == "no-repeat") break;
							tx += stepX;
						}
						if (ry == "no-repeat") break;
						ty += stepY;
					}
				}
			}
			p.restore();
		}
	}

	static final PLAIN = new Paint();

	// (a comma-separated list's parts)
	static final NONE:Array<Array<CssTerm>> = [[Keyword("none")]];

	public static function split(terms:Array<CssTerm>):Array<Array<CssTerm>> {
		var out:Array<Array<CssTerm>> = [[]];
		for (t in terms) if (t.match(Delim(","))) out.push([]) else out[out.length - 1].push(t);
		return out;
	}

	static function sizeAuto(t:Array<CssTerm>, axis:Int):Bool
		return t.length <= axis || t[axis].match(Keyword("auto"));

	// (a layer's size, §3.9, by Images 3 §5.2's default sizing: auto from the
	// image's natural width, height and ratio, whichever it has (an SVG may
	// have a ratio alone); a gradient's, with none, is the area's)
	static function size(t:Array<CssTerm>, aw:Float, ah:Float, iw:Float, ih:Float, ratio:Float):{w:Float, h:Float} {
		var r = Math.isNaN(ratio) || ratio <= 0 || !Math.isFinite(ratio) ? Math.NaN : ratio;
		switch t {
			case [Keyword("contain")] | [Keyword("cover")]:
				if (Math.isNaN(r)) return {w: aw, h: ah};
				var wide = aw / ah > r;
				return t[0].match(Keyword("contain")) == wide ? {w: ah * r, h: ah} : {w: aw, h: aw / r};
			case _:
		}
		var w = t.length > 0 && !t[0].match(Keyword("auto")) ? Transforms.length(t[0], aw) : Math.NaN;
		var h = t.length > 1 && !t[1].match(Keyword("auto")) ? Transforms.length(t[1], ah) : Math.NaN;
		if (Math.isNaN(w) && Math.isNaN(h)) {
			if (!Math.isNaN(iw) && !Math.isNaN(ih)) return {w: iw, h: ih};
			if (!Math.isNaN(r)) {
				if (!Math.isNaN(iw)) return {w: iw, h: iw / r};
				if (!Math.isNaN(ih)) return {w: ih * r, h: ih};
				// (a ratio alone: contained in the area)
				return aw / ah > r ? {w: ah * r, h: ah} : {w: aw, h: aw / r};
			}
			return {w: Math.isNaN(iw) ? aw : iw, h: Math.isNaN(ih) ? ah : ih};
		}
		if (Math.isNaN(w)) w = !Math.isNaN(r) ? h * r : Math.isNaN(iw) ? aw : iw;
		if (Math.isNaN(h)) h = !Math.isNaN(r) ? w / r : Math.isNaN(ih) ? ah : ih;
		return {w: w, h: h};
	}
}

// CSS gradients (Images 3 §3) as helder.canvas's shaders: linear (an
// angle or a side or corner), radial (circle or ellipse, an extent
// keyword or lengths, a position), repeating ones; stops placed as §3.5
// says, interpolated premultiplied.
class Gradients {
	public static function shader(t:CssTerm, x:Float, y:Float, w:Float, h:Float):Null<Gradient> {
		var name, args;
		switch t {
			case Func(n, a):
				name = n;
				args = a;
			case _:
				return null;
		}
		var parts = Backgrounds.split(args);
		var repeating = StringTools.startsWith(name, "repeating-");
		var kind = repeating ? name.substr(10) : name;
		var head = parts[0];
		var hasHead = head.length > 0 && !head[0].match(Color(_));
		var stops = hasHead ? parts.slice(1) : parts;
		var g:Gradient;
		var length:Float;
		switch kind {
			case "linear-gradient":
				var angle = Math.PI;
				if (hasHead) switch head {
					case [Keyword("to"), Keyword(a)]:
						angle = switch a {
							case "top": 0;
							case "right": Math.PI / 2;
							case "left": Math.PI * 1.5;
							case _: Math.PI;
						}
					case [Keyword("to"), Keyword(a), Keyword(b)]:
						var sx = a == "right" || b == "right" ? 1 : -1, sy = a == "bottom" || b == "bottom" ? 1 : -1;
						angle = Math.atan2(sx * h, -sy * w);
					case [a]: angle = Transforms.angle(a);
					case _:
				}
				var dx = Math.sin(angle), dy = -Math.cos(angle);
				length = Math.abs(w * dx) + Math.abs(h * dy);
				var cx = x + w / 2, cy = y + h / 2;
				var places = positions(stops, length);
				var first = repeating ? places[0] : 0.0, last = repeating ? places[places.length - 1] : length;
				if (last - first <= 0) {
					last = first + 1e-3;
				}
				var sx = cx - dx * length / 2, sy = cy - dy * length / 2;
				g = new LinearGradient(sx + dx * first, sy + dy * first, sx + dx * last, sy + dy * last);
				add(g, stops, places, first, last);
			case "radial-gradient":
				var circle = false, extent = "farthest-corner", cx = w / 2, cy = h / 2;
				var rx = Math.NaN, ry = Math.NaN;
				if (hasHead) {
					var k = 0;
					var lengths = [];
					while (k < head.length) {
						switch head[k] {
							case Keyword("circle"): circle = true;
							case Keyword("ellipse"):
							case Keyword("at"):
								var pos = head.slice(k + 1);
								cx = pos.length > 0 ? place(pos[0], w) : cx;
								cy = pos.length > 1 ? place(pos[1], h) : cy;
								k = head.length;
								continue;
							case Keyword(e): extent = e;
							case v: lengths.push(v);
						}
						k++;
					}
					if (lengths.length == 1) {
						rx = ry = Transforms.length(lengths[0], w);
						circle = true;
					} else if (lengths.length == 2) {
						rx = Transforms.length(lengths[0], w);
						ry = Transforms.length(lengths[1], h);
					}
				}
				if (Math.isNaN(rx)) {
					var l = cx, r = w - cx, t = cy, b = h - cy;
					var sideX = extent.indexOf("closest") >= 0 ? Math.min(Math.abs(l), Math.abs(r)) : Math.max(Math.abs(l), Math.abs(r));
					var sideY = extent.indexOf("closest") >= 0 ? Math.min(Math.abs(t), Math.abs(b)) : Math.max(Math.abs(t), Math.abs(b));
					if (circle) {
						var v = extent.indexOf("side") >= 0 ? (extent.indexOf("closest") >= 0 ? Math.min(sideX, sideY) : Math.max(sideX, sideY)) : Math.sqrt(sideX * sideX + sideY * sideY);
						rx = ry = v;
					} else if (extent.indexOf("side") >= 0) {
						rx = sideX;
						ry = sideY;
					} else {
						rx = sideX * 1.4142135623730951;
						ry = sideY * 1.4142135623730951;
					}
				}
				if (rx <= 0 || ry <= 0) return null;
				length = rx;
				var places = positions(stops, length);
				var first = repeating ? places[0] : 0.0, last = repeating ? places[places.length - 1] : length;
				if (last - first <= 0) last = first + 1e-3;
				var rg = new RadialGradient(0, 0, first, 0, 0, last);
				rg.matrix.translate(x + cx, y + cy).scale(1, ry / rx);
				g = rg;
				add(g, stops, places, first, last);
			case _:
				return null;
		}
		if (repeating) g.spread = Gradient.REPEAT;
		return g;
	}

	static function place(t:CssTerm, size:Float):Float
		return switch t {
			case Keyword("left" | "top"): 0;
			case Keyword("right" | "bottom"): size;
			case Keyword("center"): size / 2;
			case _: Transforms.length(t, size);
		}

	// (each stop's colour and place along the line, §3.5.1: the first at 0, the last at the end, the rest spread; none before an earlier)
	static function positions(stops:Array<Array<CssTerm>>, length:Float):Array<Float> {
		var at:Array<Float> = [];
		for (s in stops) {
			if (s.length == 0 || !s[0].match(Color(_))) continue;
			if (s.length > 1) at.push(Transforms.length(s[1], length)) else at.push(Math.NaN);
			if (s.length > 2) at.push(Transforms.length(s[2], length));
		}
		if (at.length == 0) return [0];
		if (Math.isNaN(at[0])) at[0] = 0;
		if (Math.isNaN(at[at.length - 1])) at[at.length - 1] = length;
		var max = at[0];
		for (k in 1...at.length) if (!Math.isNaN(at[k])) {
			if (at[k] < max) at[k] = max;
			max = at[k];
		}
		var k = 1;
		while (k < at.length) {
			if (Math.isNaN(at[k])) {
				var e = k;
				while (Math.isNaN(at[e])) e++;
				var a = at[k - 1], b = at[e];
				for (j in k...e) at[j] = a + (b - a) * (j - k + 1) / (e - k + 1);
				k = e;
			}
			k++;
		}
		return at;
	}

	static function add(g:Gradient, stops:Array<Array<CssTerm>>, places:Array<Float>, first:Float, last:Float) {
		g.premultiplied = true;
		var k = 0;
		for (s in stops) {
			var c = switch s[0] {
				case Color(c): BoxStyle.argb(c, 0xFF000000);
				case _: continue;
			}
			var n = s.length > 2 ? 2 : 1;
			for (_ in 0...n) {
				g.addStop((places[k] - first) / (last - first), c);
				k++;
			}
		}
	}

	// (a gradient drawn into a bitmap of one tile, to repeat; the last few
	// kept by their computed value and size, which a repaint draws again)
	public static function tile(t:CssTerm, w:Float, h:Float):Null<Bitmap> {
		var tw = Math.ceil(w), th = Math.ceil(h);
		if (tw <= 0 || th <= 0 || tw * th > 4096 * 4096) return null;
		for (k in tiles) if (k.term == t && k.w == tw && k.h == th) return k.bitmap;
		var b = drawTile(t, tw, th);
		if (b == null) return null;
		if (tiles.length >= 16) tiles.shift();
		tiles.push({term: t, w: tw, h: th, bitmap: b});
		return b;
	}

	static final tiles:Array<{term:CssTerm, w:Int, h:Int, bitmap:Bitmap}> = [];

	static function drawTile(t:CssTerm, tw:Int, th:Int):Null<Bitmap> {
		var c = new Canvas(tw, th);
		var g = shader(t, 0, 0, tw, th);
		if (g == null) return null;
		var path = new Path();
		path.rect(0, 0, tw, th);
		c.fill(path, Paint.shaded(g));
		return c.snapshot();
	}
}
