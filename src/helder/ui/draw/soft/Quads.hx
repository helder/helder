package helder.ui.draw.soft;

import haxe.io.Bytes;
import helder.canvas.Bitmap;
import helder.gfx.shader.ShaderMath.*;
import helder.gfx.shader.Vec2;
import helder.gfx.shader.Vec4;
import hxmc.simd.F32x4;
import hxmc.simd.I32x4;
import helder.ui.draw.UiShapes;

// UiShader's quads on the CPU: a quad's fields set as the Renderer sets an
// instance's (in target pixels), draw() shades each pixel it may touch by
// the fragment's own math (UiShapes: the same box, ellipse, dash and blur
// functions) and composites it over the target (premultiplied, source
// over, in the target's 8-bit values as a GPU blends into RGBA8). Only the
// pixels near an edge are shaded: a run of pixels a rectangle covers
// whole, inside a clip that covers them whole, is its colour.
@:hxmc.unsafe(gc)
class Quads {
	// the target and where its pixels start in the frame's (a group's buffer: its origin)
	public var target:Bitmap;
	public var ox = 0;
	public var oy = 0;
	// what was drawn into it, in the frame's pixels (x0, y0, x1, y1: a group's, composited alone)
	public var drawnX0 = 0;
	public var drawnY0 = 0;
	public var drawnX1 = 0;
	public var drawnY1 = 0;

	// the quad: its mode (0 a rectangle, 1 a glyph, 2 an image, 3 a shadow, 4 an inset shadow)
	public var mode = 0;
	// (its centre's place, unturned: whole part and fraction; turned: its corners a, b, c)
	public var flat = true;
	public var cx = 0.0;
	public var cy = 0.0;
	public var fx = 0.0;
	public var fy = 0.0;
	public var ax = 0.0;
	public var ay = 0.0;
	public var bx = 0.0;
	public var by = 0.0;
	public var lx = 0.0;
	public var ly = 0.0;
	// (the quad's corners' bounds in target pixels)
	public var x0 = 0.0;
	public var y0 = 0.0;
	public var x1 = 0.0;
	public var y1 = 0.0;
	// its half size, and the corners' place from its centre (with the margin)
	public var hx = 0.0;
	public var hy = 0.0;
	public var ex = 0.0;
	public var ey = 0.0;
	// texture coordinates at the grown corners
	public var u0 = 0.0;
	public var v0 = 0.0;
	public var u1 = 0.0;
	public var v1 = 0.0;
	// the fill and border colours (premultiplied, 0..1)
	public var fr = 0.0;
	public var fg = 0.0;
	public var fb = 0.0;
	public var fa = 0.0;
	public var br = 0.0;
	public var bg = 0.0;
	public var bb = 0.0;
	public var ba = 0.0;
	public var r0 = 0.0;
	public var r1 = 0.0;
	public var r2 = 0.0;
	public var r3 = 0.0;
	public var w0 = 0.0;
	public var w1 = 0.0;
	public var w2 = 0.0;
	public var w3 = 0.0;
	public var blur = 0.0;
	// (mode 0: the border's style; mode 1: read filtered)
	public var style = 0.0;
	// (a glyph's blend: 1 + its contrast, 0 none; its gamma's ratios)
	public var contrast = 0.0;
	public var g0 = 0.0;
	public var g1 = 0.0;
	public var g2 = 0.0;
	public var g3 = 0.0;
	// the clip in target pixels, its corners' radii
	public var cx0 = 0.0;
	public var cy0 = 0.0;
	public var cx1 = 0.0;
	public var cy1 = 0.0;
	public var cr0 = 0.0;
	public var cr1 = 0.0;
	public var cr2 = 0.0;
	public var cr3 = 0.0;
	// the texture read: the glyph atlas's coverage (R8) or an image's premultiplied RGBA
	public var tex:Null<Bytes> = null;
	public var texW = 1;
	public var texH = 1;

	// (the pixel shaded: premultiplied, 0..1)
	var sr = 0.0;
	var sg = 0.0;
	var sb = 0.0;
	var sa = 0.0;

	public function new(target:Bitmap)
		this.target = target;

	// shades and composites every pixel the quad and the clip both reach
	public function draw() {
		var t = target, tw = t.width, th = t.height;
		// (the pixels whose centres the quad covers, as a GPU rasterizes it:
		// left and top edges in, right and bottom out; a turned one's tested each)
		var px0 = Std.int(Math.max(Math.max(Math.ceil(x0 - 0.5), Math.floor(cx0)), ox));
		var py0 = Std.int(Math.max(Math.max(Math.ceil(y0 - 0.5), Math.floor(cy0)), oy));
		var px1 = Std.int(Math.min(Math.min(Math.ceil(x1 - 0.5), Math.ceil(cx1)), ox + tw));
		var py1 = Std.int(Math.min(Math.min(Math.ceil(y1 - 0.5), Math.ceil(cy1)), oy + th));
		if (px1 <= px0 || py1 <= py0) return;
		unblur();
		if (px0 < drawnX0) drawnX0 = px0;
		if (py0 < drawnY0) drawnY0 = py0;
		if (px1 > drawnX1) drawnX1 = px1;
		if (py1 > drawnY1) drawnY1 = py1;
		// (the clip's inside, covered whole: a pixel away from its edges and corners)
		var ck = Math.max(Math.max(cr0, cr1), Math.max(cr2, cr3)) + 1;
		var ix0 = cx0 + ck, iy0 = cy0 + ck, ix1 = cx1 - ck, iy1 = cy1 - ck;
		// (the shape's: an unturned rectangle's or image's away from its corners and border)
		var sk = Math.max(Math.max(r0, r1), Math.max(r2, r3)) + Math.max(Math.max(w0, w1), Math.max(w2, w3)) + 1;
		// (a rectangle's inside: its fill, nothing where it has none)
		var solid = flat && (mode == 0 || mode == 2), filling = mode == 0;
		var opaque = filling && fa >= 1;
		// (an opaque fill's pixel as one little-endian word: RGBA)
		var word = q(fr) | q(fg) << 8 | q(fb) << 16 | 0xFF << 24;
		var px = t.pixels;
		// (an unturned rectangle, solid border, or shadow: shaded four pixels at a time)
		var wide = flat && (mode == 0 && style < 0.5 || mode == 3 || mode == 4);
		for (y in py0...py1) {
			var pcy = y + 0.5, row = (y - oy) * tw - ox;
			// (this row's span covered whole: inside the shape and the clip)
			var a = px1, b = px1;
			if (solid && pcy > iy0 && pcy < iy1) {
				var ly = pcy - cy - fy;
				if (Math.abs(ly) <= hy - sk) {
					a = Std.int(Math.max(Math.ceil(Math.max(cx + fx - (hx - sk), ix0) - 0.5), px0));
					b = Std.int(Math.min(Math.floor(Math.min(cx + fx + (hx - sk), ix1) - 0.5) + 1, px1));
					if (b <= a) a = b = px1;
				}
			}
			var x = px0;
			if (wide) {
				// (four pixels at a time, but for the span covered whole)
				if (a > px0) row4(px, row, px0, a, pcy, iy0, iy1, ix0, ix1);
				if (b < px1) row4(px, row, b, px1, pcy, iy0, iy1, ix0, ix1);
				if (a < b) x = a else continue;
			}
			while (x < px1) {
				if (x == a) {
					if (filling) {
						// (the fill alone: no edge, border or clip reaches it)
						if (fa <= 0) {} else if (opaque) for (k in a...b)
							px.setInt32((row + k) * 4, word) else for (k in a...b) {
							sr = fr;
							sg = fg;
							sb = fb;
							sa = fa;
							over(px, (row + k) * 4);
						}
					} else for (k in a...b) {
						image(k + 0.5, pcy, 1);
						if (sa > 0) over(px, (row + k) * 4);
					}
					// (four lanes: the rest done)
					if (wide) break;
					x = b;
					continue;
				}
				var pcx = x + 0.5;
				if (!flat && !inside(pcx, pcy)) {
					x++;
					continue;
				}
				var clipped = pcx > ix0 && pcx < ix1 && pcy > iy0 && pcy < iy1 ? 1.0 : clip(pcx, pcy);
				if (clipped > 0) {
					shade(pcx, pcy, clipped);
					if (sa > 0 || sr > 0 || sg > 0 || sb > 0) over(px, (row + x) * 4);
				}
				x++;
			}
		}
	}

	// (pixels x0 to x1 of a row (its centre's y: cy), as shade, in four lanes)
	function row4(px:Bytes, row:Int, x0:Int, x1:Int, y:Float, iy0:Float, iy1:Float, ix0:Float, ix1:Float) {
		var zero = F32x4.zero(), one = F32x4.splat(1), half = F32x4.splat(0.5);
		var ly = y - cy - fy, steps = F32x4.make(0.5, 1.5, 2.5, 3.5), clipRow = y > iy0 && y < iy1;
		var x = x0;
		while (x < x1) {
			var pcx = F32x4.splat(x) + steps;
			var lanes = x1 - x;
			var live = lanes >= 4 ? I32x4.splat(-1) : F32x4.make(0, 1, 2, 3).lt(F32x4.splat(lanes));
			// (the clip's coverage)
			var c = one;
			if (!clipRow || x + 0.5 <= ix0 || x + 3.5 >= ix1) {
				var hw = (cx1 - cx0) * 0.5, hh = (cy1 - cy0) * 0.5;
				var qx = pcx - F32x4.splat(cx0 + hw), qy = y - cy0 - hh;
				c = (half - box4(qx, qy, hw, hh, cr0, cr1, cr2, cr3)).clamp(zero, one);
			}
			c = F32x4.select(live, c, zero);
			var lx = pcx - F32x4.splat(cx + fx);
			var r:F32x4, g:F32x4, b:F32x4, a:F32x4;
			if (mode == 0) {
				var edge = (half - box4(lx, ly, hx, hy, r0, r1, r2, r3)).clamp(zero, one) * c;
				var inBorder = zero;
				if (w0 + w1 + w2 + w3 > 0) {
					var ihx = Math.max(hx - (w3 + w1) * 0.5, 0), ihy = Math.max(hy - (w0 + w2) * 0.5, 0);
					var ipx = lx - F32x4.splat((w3 - w1) * 0.5), ipy = ly - (w0 - w2) * 0.5;
					var right = ipx.gt(zero);
					var rc = F32x4.select(right, F32x4.splat(ipy > 0 ? r2 : r1), F32x4.splat(ipy > 0 ? r3 : r0));
					var rx = (rc - F32x4.select(right, F32x4.splat(w1), F32x4.splat(w3))).max(zero);
					var ry = (rc - F32x4.splat(ipy > 0 ? w2 : w0)).max(zero);
					inBorder = (half + ellipse4(ipx, ipy, ihx, ihy, rx, ry)).clamp(zero, one);
				}
				var f = one - inBorder;
				r = (F32x4.splat(fr) * f + F32x4.splat(br) * inBorder) * edge;
				g = (F32x4.splat(fg) * f + F32x4.splat(bg) * inBorder) * edge;
				b = (F32x4.splat(fb) * f + F32x4.splat(bb) * inBorder) * edge;
				a = (F32x4.splat(fa) * f + F32x4.splat(ba) * inBorder) * edge;
			} else {
				var k:F32x4;
				if (mode == 3) {
					var under = zero;
					if (w3 > 0) {
						var chx = Math.max(hx - w2, 0), chy = Math.max(hy - w2, 0);
						under = (half - box4(lx + F32x4.splat(w0), ly + w1, chx, chy, Math.max(r0 - w2, 0), Math.max(r1 - w2, 0), Math.max(r2 - w2, 0),
							Math.max(r3 - w2, 0))).clamp(zero, one);
					}
					// (under the box that casts it whole: nothing)
					if (under.ge(one).all()) {
						x += 4;
						continue;
					}
					var cover = blur > 0.01 ? blur4(lx, ly, hx, hy) : (half - box4(lx, ly, hx, hy, r0, r1, r2, r3)).clamp(zero, one);
					k = cover * (one - under) * c;
				} else {
					var ihx = Math.max(hx - w2, 0), ihy = Math.max(hy - w2, 0);
					var qx = lx - F32x4.splat(w0), qy = ly - w1;
					var lit = blur > 0.01 ? blurIn4(qx, qy, ihx, ihy) : (half - box4(qx, qy, ihx, ihy, Math.max(r0 - w2, 0), Math.max(r1 - w2, 0),
						Math.max(r2 - w2, 0), Math.max(r3 - w2, 0))).clamp(zero, one);
					k = (one - lit) * (half - box4(lx, ly, hx, hy, r0, r1, r2, r3)).clamp(zero, one) * c;
				}
				r = F32x4.splat(fr) * k;
				g = F32x4.splat(fg) * k;
				b = F32x4.splat(fb) * k;
				a = F32x4.splat(fa) * k;
			}
			// (each lane blended: hxmc.simd's lanes read by constants)
			inline function lane(i:Int, ar:Float, ag:Float, ab:Float, aa:Float)
				if (i < lanes && (aa > 0 || ar > 0 || ag > 0 || ab > 0)) {
					sr = ar;
					sg = ag;
					sb = ab;
					sa = aa;
					over(px, (row + x + i) * 4);
				}
			lane(0, r.get(0), g.get(0), b.get(0), a.get(0));
			lane(1, r.get(1), g.get(1), b.get(1), a.get(1));
			lane(2, r.get(2), g.get(2), b.get(2), a.get(2));
			lane(3, r.get(3), g.get(3), b.get(3), a.get(3));
			x += 4;
		}
	}

	// (UiShapes.box of four points along a row (x, y), the corners' radii by side)
	static inline function box4(x:F32x4, y:Float, hx:Float, hy:Float, r0:Float, r1:Float, r2:Float, r3:Float):F32x4 {
		var zero = F32x4.zero();
		var right = x.gt(zero);
		var rc = F32x4.select(right, F32x4.splat(y > 0 ? r2 : r1), F32x4.splat(y > 0 ? r3 : r0));
		var rr = rc.min(F32x4.splat(Math.min(hx, hy)));
		var qx = x.abs() - F32x4.splat(hx) + rr, qy = F32x4.splat(Math.abs(y) - hy) + rr;
		var round = qx.gt(zero) & qy.gt(zero);
		return F32x4.select(round, (qx * qx + qy * qy).sqrt(), qx.max(qy)) - rr;
	}

	// (UiShapes.ellipseBox of four points along a row, each corner's radii rx, ry)
	static inline function ellipse4(x:F32x4, y:Float, hx:Float, hy:Float, rx:F32x4, ry:F32x4):F32x4 {
		var zero = F32x4.zero(), one = F32x4.splat(1);
		rx = rx.min(F32x4.splat(hx));
		ry = ry.min(F32x4.splat(hy));
		var ax = x.abs(), ay = F32x4.splat(Math.abs(y));
		var qx = ax - F32x4.splat(hx) + rx, qy = ay - F32x4.splat(hy) + ry;
		var curved = qx.gt(zero) & qy.gt(zero) & rx.gt(zero) & ry.gt(zero);
		var sx = F32x4.select(curved, rx, one), sy = F32x4.select(curved, ry, one);
		var ux = qx / sx, uy = qy / sy, vx = ux / sx, vy = uy / sy;
		var k = (ux * ux + uy * uy).sqrt();
		var arc = (k - one) * k / F32x4.select(curved, (vx * vx + vy * vy).sqrt(), one);
		var ex = ax - F32x4.splat(hx), ey = ay - F32x4.splat(hy);
		var mx = ex.max(zero), my = ey.max(zero);
		var side = (mx * mx + my * my).sqrt() + ex.max(ey).min(zero);
		return F32x4.select(curved, arc, side);
	}

	// (blurred's rows for four points of a row: an outer shadow's, an inset one's inner box)
	inline function blur4(x:F32x4, y:Float, hx:Float, hy:Float):F32x4 {
		blurred(0, y, hx, hy, vec4(r0, r1, r2, r3));
		return blurRow4(x);
	}

	inline function blurIn4(x:F32x4, y:Float, hx:Float, hy:Float):F32x4 {
		blurred(0, y, hx, hy, vec4(Math.max(r0 - w2, 0), Math.max(r1 - w2, 0), Math.max(r2 - w2, 0), Math.max(r3 - w2, 0)));
		return blurRow4(x);
	}

	// (the kept rows' widths and weights, by each lane's side)
	function blurRow4(x:F32x4):F32x4 {
		var right = x.gt(F32x4.zero()), k = F32x4.splat(0.70710678 / blur), sum = F32x4.zero(), half = F32x4.splat(0.5);
		var n = straight[0] && straight[1] ? 1 : 4;
		for (i in 0...n) {
			var w = F32x4.select(right, F32x4.splat(widths[4 + i]), F32x4.splat(widths[i]));
			var wt = n == 1 ? F32x4.select(right, F32x4.splat(weights[4] + weights[5] + weights[6] + weights[7]),
				F32x4.splat(weights[0] + weights[1] + weights[2] + weights[3])) : F32x4.select(right, F32x4.splat(weights[4 + i]), F32x4.splat(weights[i]));
			sum = sum + (erf4((x + w) * k) - erf4((x - w) * k)) * half * wt;
		}
		return sum;
	}

	static inline function erf4(x:F32x4):F32x4 {
		var zero = F32x4.zero(), one = F32x4.splat(1);
		var s = F32x4.select(x.gt(zero), one, F32x4.select(x.lt(zero), -one, zero)), a = x.abs();
		var r = one + (F32x4.splat(0.278393) + (F32x4.splat(0.230389) + a * a * F32x4.splat(0.078108)) * a) * a;
		r = r * r;
		return s - s / (r * r);
	}

	// a group's pixels (b, its top left at gx, gy in the frame's) over the
	// target at alpha, what it drew alone (x0, y0, x1, y1), clipped: UiShader's
	// image quad read at its texels' centres, each texel as it is
	public function group(b:Bitmap, gx:Int, gy:Int, alpha:Float, x0:Int, y0:Int, x1:Int, y1:Int) {
		var t = target, tw = t.width;
		var px0 = Std.int(Math.max(Math.max(x0, Math.floor(cx0)), ox)), py0 = Std.int(Math.max(Math.max(y0, Math.floor(cy0)), oy));
		var px1 = Std.int(Math.min(Math.min(x1, Math.ceil(cx1)), ox + tw)), py1 = Std.int(Math.min(Math.min(y1, Math.ceil(cy1)), oy + t.height));
		if (px1 <= px0 || py1 <= py0 || alpha <= 0) return;
		if (px0 < drawnX0) drawnX0 = px0;
		if (py0 < drawnY0) drawnY0 = py0;
		if (px1 > drawnX1) drawnX1 = px1;
		if (py1 > drawnY1) drawnY1 = py1;
		var ck = Math.max(Math.max(cr0, cr1), Math.max(cr2, cr3)) + 1;
		var ix0 = cx0 + ck, iy0 = cy0 + ck, ix1 = cx1 - ck, iy1 = cy1 - ck;
		var px = t.pixels, src = b.pixels, k = alpha / 255;
		for (y in py0...py1) {
			var pcy = y + 0.5, row = (y - oy) * tw - ox, srow = (y - gy) * b.width - gx;
			for (x in px0...px1) {
				var s = (srow + x) * 4, a = src.get(s + 3);
				if (a == 0 && src.get(s) == 0 && src.get(s + 1) == 0 && src.get(s + 2) == 0) continue;
				var pcx = x + 0.5;
				var c = k * (pcx > ix0 && pcx < ix1 && pcy > iy0 && pcy < iy1 ? 1.0 : clip(pcx, pcy));
				if (c <= 0) continue;
				sr = src.get(s) * c;
				sg = src.get(s + 1) * c;
				sb = src.get(s + 2) * c;
				sa = a * c;
				over(px, (row + x) * 4);
			}
		}
	}

	// (the source over the pixel at o, both premultiplied, rounded to 8 bits)
	inline function over(px:Bytes, o:Int) {
		var k = 1 - sa;
		px.set(o, q(sr + px.get(o) / 255 * k));
		px.set(o + 1, q(sg + px.get(o + 1) / 255 * k));
		px.set(o + 2, q(sb + px.get(o + 2) / 255 * k));
		px.set(o + 3, q(sa + px.get(o + 3) / 255 * k));
	}

	static inline function q(v:Float):Int {
		var i = Std.int(v * 255 + 0.5);
		return i < 0 ? 0 : i > 255 ? 255 : i;
	}

	// (a turned quad's: the pixel's centre within its corners a, b, c)
	inline function inside(x:Float, y:Float):Bool {
		var e1x = bx - ax, e1y = by - ay, e2x = lx - ax, e2y = ly - ay, dx = x - ax, dy = y - ay;
		var det = e1x * e2y - e1y * e2x;
		var u = (dx * e2y - dy * e2x) / det, v = (e1x * dy - e1y * dx) / det;
		return u >= 0 && u < 1 && v >= 0 && v < 1;
	}

	inline function clip(x:Float, y:Float):Float {
		var hw = (cx1 - cx0) * 0.5, hh = (cy1 - cy0) * 0.5;
		return clamp(0.5 - UiShapes.box(vec2(x - cx0 - hw, y - cy0 - hh), vec2(hw, hh), vec4(cr0, cr1, cr2, cr3)), 0, 1);
	}

	// (the pixel's place from the quad's centre: an unturned one's from its
	// centre's whole part, then its fraction, as UiShader has it)
	inline function local(x:Float, y:Float):Vec2
		return flat ? vec2(x - cx - fx, y - cy - fy) : UiShapes.turned(vec2(x, y), vec2(ax, ay), vec2(bx, by), vec2(lx, ly), vec2(ex, ey));

	// UiShader's fragment at the pixel's centre x, y, times the clip's coverage
	function shade(x:Float, y:Float, clipped:Float) {
		var p = local(x, y), half = vec2(hx, hy), radii = vec4(r0, r1, r2, r3);
		if (mode == 4) {
			var inner = max(half - vec2(w2, w2), vec2(0, 0));
			var ir = max(radii - vec4(w2, w2, w2, w2), vec4(0, 0, 0, 0));
			var q = p - vec2(w0, w1);
			var lit = blur > 0.01 ? (flat ? blurred(q.x, q.y, inner.x, inner.y, ir) : UiShapes.blurred(q, inner, ir, blur)) : clamp(0.5
				- UiShapes.box(q, inner, ir), 0, 1);
			return paint(fr, fg, fb, fa, (1 - lit) * clamp(0.5 - UiShapes.box(p, half, radii), 0, 1) * clipped);
		}
		if (mode == 3) {
			var caster = max(half - vec2(w2, w2), vec2(0, 0));
			var cr = max(radii - vec4(w2, w2, w2, w2), vec4(0, 0, 0, 0));
			var under = w3 > 0 ? clamp(0.5 - UiShapes.box(p + vec2(w0, w1), caster, cr), 0, 1) : 0.0;
			if (under >= 1) return paint(0, 0, 0, 0, 0);
			var a = blur > 0.01 ? (flat ? blurred(p.x, p.y, hx, hy, radii) : UiShapes.blurred(p, half, radii, blur)) : clamp(0.5
				- UiShapes.box(p, half, radii), 0, 1);
			return paint(fr, fg, fb, fa, a * (1 - under) * clipped);
		}
		if (mode == 2) return image(x, y, clipped);
		if (mode == 1) return glyph(p, clipped);
		var d = UiShapes.box(p, half, radii);
		var edge = clamp(0.5 - d, 0, 1);
		if (edge <= 0) return paint(0, 0, 0, 0, 0);
		var inBorder = 0.0;
		if (w0 + w1 + w2 + w3 > 0) {
			var inHalf = max(half - vec2((w3 + w1) * 0.5, (w0 + w2) * 0.5), vec2(0, 0));
			var inP = p - vec2((w3 - w1) * 0.5, (w0 - w2) * 0.5);
			var rc = inP.x > 0 ? (inP.y > 0 ? r2 : r1) : (inP.y > 0 ? r3 : r0);
			var rad = vec2(Math.max(rc - (inP.x > 0 ? w1 : w3), 0), Math.max(rc - (inP.y > 0 ? w2 : w0), 0));
			inBorder = clamp(0.5 + UiShapes.ellipseBox(inP, inHalf, rad), 0, 1);
			if (style > 0.5 && inBorder > 0) inBorder = inBorder * UiShapes.dashes(p, half, vec4(w0, w1, w2, w3), radii, style);
		}
		var k = edge * clipped, f = 1 - inBorder;
		sr = (fr * f + br * inBorder) * k;
		sg = (fg * f + bg * inBorder) * k;
		sb = (fb * f + bb * inBorder) * k;
		sa = (fa * f + ba * inBorder) * k;
	}

	// (UiShapes.blurred at x, y, its terms that hold along a row kept: each
	// of the column's four rows' weight and half width, left and right of
	// the centre; where the four are one width (along a side), one row's)
	final weights = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
	final widths = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
	final straight = [false, false];
	var blurY = Math.NaN;
	var blurHx = 0.0;
	var blurHy = 0.0;

	// (a new quad: the rows kept are not its)
	inline function unblur()
		blurY = Math.NaN;

	function blurred(x:Float, y:Float, hx:Float, hy:Float, r:Vec4):Float {
		var sigma = blur;
		if (y != blurY || hx != blurHx || hy != blurHy) {
			blurY = y;
			blurHx = hx;
			blurHy = hy;
			var low = y - hy, high = y + hy;
			var y0 = clamp(-3 * sigma, low, high), y1 = clamp(3 * sigma, low, high);
			var dy = (y1 - y0) / 4;
			for (side in 0...2) {
				var rc = side == 1 ? (y > 0 ? r.z : r.y) : (y > 0 ? r.w : r.x);
				var corner = Math.min(rc, Math.min(hx, hy)), first = 0.0;
				straight[side] = true;
				for (i in 0...4) {
					var yi = y0 + dy * 0.5 + i * dy;
					var delta = Math.min(hy - corner - Math.abs(y - yi), 0);
					var w = hx - corner + Math.sqrt(Math.max(0, corner * corner - delta * delta));
					weights[side * 4 + i] = UiShapes.gauss(yi, sigma) * dy;
					widths[side * 4 + i] = w;
					if (i == 0) first = w else if (w != first) straight[side] = false;
				}
			}
		}
		var side = x > 0 ? 1 : 0, k = 0.70710678 / sigma, o = side * 4;
		inline function row(w:Float):Float
			return (erf((x + w) * k) - erf((x - w) * k)) * 0.5;
		if (straight[side]) return row(widths[o]) * (weights[o] + weights[o + 1] + weights[o + 2] + weights[o + 3]);
		return row(widths[o]) * weights[o] + row(widths[o + 1]) * weights[o + 1] + row(widths[o + 2]) * weights[o + 2] + row(widths[o + 3]) * weights[o + 3];
	}

	// (UiShapes.erf2's approximation, of one value)
	static inline function erf(x:Float):Float {
		var s = x > 0 ? 1.0 : x < 0 ? -1.0 : 0.0, a = Math.abs(x);
		var r = 1 + (0.278393 + (0.230389 + a * a * 0.078108) * a) * a;
		r = r * r;
		return s - s / (r * r);
	}

	inline function paint(r:Float, g:Float, b:Float, a:Float, k:Float) {
		sr = r * k;
		sg = g * k;
		sb = b * k;
		sa = a * k;
	}

	// (mode 2: the image's texels (premultiplied) read filtered, clamped to
	// their centres, times the colour's alpha, its corners rounded)
	function image(x:Float, y:Float, clipped:Float) {
		var p = local(x, y);
		var cover = r0 + r1 + r2 + r3 == 0 && Math.abs(p.x) <= hx - 0.5 && Math.abs(p.y) <= hy - 0.5 ? 1.0 : clamp(0.5
			- UiShapes.box(p, vec2(hx, hy), vec4(r0, r1, r2, r3)), 0, 1);
		var k = fa * cover * clipped;
		if (k <= 0 || tex == null) return paint(0, 0, 0, 0, 0);
		var u = u0 + (u1 - u0) * ((p.x + ex) / (ex * 2)), v = v0 + (v1 - v0) * ((p.y + ey) / (ey * 2));
		var t = tex, w = texW, h = texH;
		// (a linear filter's texels and weights; clamped to the edge's)
		var sx = u * w - 0.5, sy = v * h - 0.5;
		var ix = Math.floor(sx), iy = Math.floor(sy), ax = sx - ix, ay = sy - iy;
		var xa = ix < 0 ? 0 : ix >= w ? w - 1 : ix, xb = ix + 1 < 0 ? 0 : ix + 1 >= w ? w - 1 : ix + 1;
		var ya = iy < 0 ? 0 : iy >= h ? h - 1 : iy, yb = iy + 1 < 0 ? 0 : iy + 1 >= h ? h - 1 : iy + 1;
		var a = (ya * w + xa) * 4, b = (ya * w + xb) * 4, c = (yb * w + xa) * 4, d = (yb * w + xb) * 4;
		var wa = (1 - ax) * (1 - ay), wb = ax * (1 - ay), wc = (1 - ax) * ay, wd = ax * ay;
		var s = k / 255;
		sr = (t.get(a) * wa + t.get(b) * wb + t.get(c) * wc + t.get(d) * wd) * s;
		sg = (t.get(a + 1) * wa + t.get(b + 1) * wb + t.get(c + 1) * wc + t.get(d + 1) * wd) * s;
		sb = (t.get(a + 2) * wa + t.get(b + 2) * wb + t.get(c + 2) * wc + t.get(d + 2) * wd) * s;
		sa = (t.get(a + 3) * wa + t.get(b + 3) * wb + t.get(c + 3) * wc + t.get(d + 3) * wd) * s;
	}

	// (mode 1: the atlas's coverage at its texels' centres, or filtered, the
	// platform's blend applied, of the colour)
	function glyph(p:Vec2, clipped:Float) {
		var t = tex, w = texW, h = texH;
		var u = u0 + (u1 - u0) * ((p.x + ex) / (ex * 2)), v = v0 + (v1 - v0) * ((p.y + ey) / (ey * 2));
		var a = 0.0;
		if (style > 0.5) {
			var sx = u * w - 0.5, sy = v * h - 0.5;
			var ix = Math.floor(sx), iy = Math.floor(sy), fx = sx - ix, fy = sy - iy;
			inline function at(i:Int, j:Int):Float
				return t.get((j < 0 ? 0 : j >= h ? h - 1 : j) * w + (i < 0 ? 0 : i >= w ? w - 1 : i)) / 255;
			a = (at(ix, iy) * (1 - fx) + at(ix + 1, iy) * fx) * (1 - fy) + (at(ix, iy + 1) * (1 - fx) + at(ix + 1, iy + 1) * fx) * fy;
		} else {
			var i = Math.floor(u * w), j = Math.floor(v * h);
			if (i < 0 || j < 0 || i >= w || j >= h) return paint(0, 0, 0, 0, 0);
			a = t.get(j * w + i) / 255;
		}
		if (contrast > 0.5 && fa > 0) {
			var r = fr / fa, g = fg / fa, b = fb / fa;
			var k = (contrast - 1) * clamp(3 - 4 * (r * 0.30 + g * 0.59 + b * 0.11), 0, 1);
			var f = r * 0.25 + g * 0.5 + b * 0.25;
			a = a * (k + 1) / (a * k + 1);
			a = a + a * (1 - a) * ((g0 * f + g1) * a + (g2 * f + g3));
		}
		paint(fr, fg, fb, fa, a * clipped);
	}
}
