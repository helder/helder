package helder.ui.draw.soft;

import helder.gfx.shader.ShaderMath.*;
import helder.math.Vec2;
import helder.math.Vec4;
import helder.ui.draw.UiShapes;
import hxmc.simd.F32x4;
import hxmc.simd.I32x4;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

// One of Quads' draws as recorded, outside the collector's heap, and its
// painting into a band of the frame's rows (paint: rows b0 to b1), so that
// bands are painted on any thread (Bands, over helder.jobs.Spread), each
// its records in order: kind 0 a quad (Quads' fields, its pixels px0, py0
// to px1, py1 found when recorded), 1 a group's buffer (tex, texW wide, its
// top left at cx, cy) composited at fa, 2 a rectangle set to word. The
// target is texels of RGBA8 (premultiplied), tw by th, its top left at ox,
// oy in the frame's pixels. Quads' own code, its fields these.
@:build(helder.ui.draw.soft.QuadBuild.build())
@:hxmc.unsafe(gc)
abstract QuadRecord(Ptr) {
	public inline function new(p:Ptr)
		this = p;

	public inline function ptr():Ptr
		return this;

	var flat(get, never):Bool;

	inline function get_flat():Bool
		return isFlat != 0;

	public function paint(b0:Int, b1:Int) {
		var y0 = py0 > b0 ? py0 : b0, y1 = py1 < b1 ? py1 : b1;
		if (y1 <= y0) return;
		switch kind {
			case 0: draw(y0, y1, px0, px1, tw);
			case 1: group(y0, y1, px0, px1, tw);
			case _:
				for (y in y0...y1) {
					var row = target.add(4 * ((y - oy) * tw - ox));
					for (x in px0...px1)
						Mem.setI32(row, 4 * x, word);
				}
		}
	}

	// (Quads.draw's pixels, rows py0 to py1)
	function draw(py0:Int, py1:Int, px0:Int, px1:Int, tw:Int) {
		blurY = Math.NaN;
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
		var px = target;
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
							Mem.setI32(px, (row + k) * 4, word) else for (k in a...b) {
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
	function row4(px:Ptr, row:Int, x0:Int, x1:Int, y:Float, iy0:Float, iy1:Float, ix0:Float, ix1:Float) {
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
		var n = straight(0) && straight(1) ? 1 : 4;
		for (i in 0...n) {
			var w = F32x4.select(right, F32x4.splat(widths(4 + i)), F32x4.splat(widths(i)));
			var wt = n == 1 ? F32x4.select(right, F32x4.splat(weights(4) + weights(5) + weights(6) + weights(7)),
				F32x4.splat(weights(0) + weights(1) + weights(2) + weights(3))) : F32x4.select(right, F32x4.splat(weights(4 + i)), F32x4.splat(weights(i)));
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

	// (Quads.group's composite, rows py0 to py1: the buffer at tex, texW wide, its top left at cx, cy, at fa)
	function group(py0:Int, py1:Int, px0:Int, px1:Int, tw:Int) {
		var gx = Std.int(cx), gy = Std.int(cy), bw = texW;
		var ck = Math.max(Math.max(cr0, cr1), Math.max(cr2, cr3)) + 1;
		var ix0 = cx0 + ck, iy0 = cy0 + ck, ix1 = cx1 - ck, iy1 = cy1 - ck;
		var px = target, src = tex, k = fa / 255;
		for (y in py0...py1) {
			var pcy = y + 0.5, row = (y - oy) * tw - ox, srow = (y - gy) * bw - gx;
			for (x in px0...px1) {
				var s = (srow + x) * 4, a = Mem.getU8(src, s + 3);
				if (a == 0 && Mem.getU8(src, s) == 0 && Mem.getU8(src, s + 1) == 0 && Mem.getU8(src, s + 2) == 0) continue;
				var pcx = x + 0.5;
				var c = k * (pcx > ix0 && pcx < ix1 && pcy > iy0 && pcy < iy1 ? 1.0 : clip(pcx, pcy));
				if (c <= 0) continue;
				sr = Mem.getU8(src, s) * c;
				sg = Mem.getU8(src, s + 1) * c;
				sb = Mem.getU8(src, s + 2) * c;
				sa = a * c;
				over(px, (row + x) * 4);
			}
		}
	}

	// (the source over the pixel at o, both premultiplied, rounded to 8 bits)
	inline function over(px:Ptr, o:Int) {
		var k = 1 - sa;
		Mem.setI8(px, o, q(sr + Mem.getU8(px, o) / 255 * k));
		Mem.setI8(px, o + 1, q(sg + Mem.getU8(px, o + 1) / 255 * k));
		Mem.setI8(px, o + 2, q(sb + Mem.getU8(px, o + 2) / 255 * k));
		Mem.setI8(px, o + 3, q(sa + Mem.getU8(px, o + 3) / 255 * k));
	}

	public static inline function q(v:Float):Int {
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
			return paintOf(fr, fg, fb, fa, (1 - lit) * clamp(0.5 - UiShapes.box(p, half, radii), 0, 1) * clipped);
		}
		if (mode == 3) {
			var caster = max(half - vec2(w2, w2), vec2(0, 0));
			var cr = max(radii - vec4(w2, w2, w2, w2), vec4(0, 0, 0, 0));
			var under = w3 > 0 ? clamp(0.5 - UiShapes.box(p + vec2(w0, w1), caster, cr), 0, 1) : 0.0;
			if (under >= 1) return paintOf(0, 0, 0, 0, 0);
			var a = blur > 0.01 ? (flat ? blurred(p.x, p.y, hx, hy, radii) : UiShapes.blurred(p, half, radii, blur)) : clamp(0.5
				- UiShapes.box(p, half, radii), 0, 1);
			return paintOf(fr, fg, fb, fa, a * (1 - under) * clipped);
		}
		if (mode == 2) return image(x, y, clipped);
		if (mode == 1) return glyph(p, clipped);
		var d = UiShapes.box(p, half, radii);
		var edge = clamp(0.5 - d, 0, 1);
		if (edge <= 0) return paintOf(0, 0, 0, 0, 0);
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
	inline function weights(i:Int):Float
		return Mem.getF64(this, ROWS_AT + 8 * i);

	inline function widths(i:Int):Float
		return Mem.getF64(this, ROWS_AT + 64 + 8 * i);

	inline function straight(side:Int):Bool
		return Mem.getF64(this, ROWS_AT + 128 + 8 * side) != 0;

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
				var corner = Math.min(rc, Math.min(hx, hy)), first = 0.0, same = true;
				for (i in 0...4) {
					var yi = y0 + dy * 0.5 + i * dy;
					var delta = Math.min(hy - corner - Math.abs(y - yi), 0);
					var w = hx - corner + Math.sqrt(Math.max(0, corner * corner - delta * delta));
					Mem.setF64(this, ROWS_AT + 8 * (side * 4 + i), UiShapes.gauss(yi, sigma) * dy);
					Mem.setF64(this, ROWS_AT + 64 + 8 * (side * 4 + i), w);
					if (i == 0) first = w else if (w != first) same = false;
				}
				Mem.setF64(this, ROWS_AT + 128 + 8 * side, same ? 1 : 0);
			}
		}
		var side = x > 0 ? 1 : 0, k = 0.70710678 / sigma, o = side * 4;
		inline function row(w:Float):Float
			return (erf((x + w) * k) - erf((x - w) * k)) * 0.5;
		if (straight(side)) return row(widths(o)) * (weights(o) + weights(o + 1) + weights(o + 2) + weights(o + 3));
		return row(widths(o)) * weights(o) + row(widths(o + 1)) * weights(o + 1) + row(widths(o + 2)) * weights(o + 2) + row(widths(o + 3)) * weights(o + 3);
	}

	// (UiShapes.erf2's approximation, of one value)
	static inline function erf(x:Float):Float {
		var s = x > 0 ? 1.0 : x < 0 ? -1.0 : 0.0, a = Math.abs(x);
		var r = 1 + (0.278393 + (0.230389 + a * a * 0.078108) * a) * a;
		r = r * r;
		return s - s / (r * r);
	}

	inline function paintOf(r:Float, g:Float, b:Float, a:Float, k:Float) {
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
		if (k <= 0 || tex.isNull()) return paintOf(0, 0, 0, 0, 0);
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
		inline function at(i:Int):Int
			return Mem.getU8(t, i);
		sr = (at(a) * wa + at(b) * wb + at(c) * wc + at(d) * wd) * s;
		sg = (at(a + 1) * wa + at(b + 1) * wb + at(c + 1) * wc + at(d + 1) * wd) * s;
		sb = (at(a + 2) * wa + at(b + 2) * wb + at(c + 2) * wc + at(d + 2) * wd) * s;
		sa = (at(a + 3) * wa + at(b + 3) * wb + at(c + 3) * wc + at(d + 3) * wd) * s;
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
				return Mem.getU8(t, (j < 0 ? 0 : j >= h ? h - 1 : j) * w + (i < 0 ? 0 : i >= w ? w - 1 : i)) / 255;
			a = (at(ix, iy) * (1 - fx) + at(ix + 1, iy) * fx) * (1 - fy) + (at(ix, iy + 1) * (1 - fx) + at(ix + 1, iy + 1) * fx) * fy;
		} else {
			var i = Math.floor(u * w), j = Math.floor(v * h);
			if (i < 0 || j < 0 || i >= w || j >= h) return paintOf(0, 0, 0, 0, 0);
			a = Mem.getU8(t, j * w + i) / 255;
		}
		if (contrast > 0.5 && fa > 0) {
			var r = fr / fa, g = fg / fa, b = fb / fa;
			var k = (contrast - 1) * clamp(3 - 4 * (r * 0.30 + g * 0.59 + b * 0.11), 0, 1);
			var f = r * 0.25 + g * 0.5 + b * 0.25;
			a = a * (k + 1) / (a * k + 1);
			a = a + a * (1 - a) * ((g0 * f + g1) * a + (g2 * f + g3));
		}
		paintOf(fr, fg, fb, fa, a * clipped);
	}
}
