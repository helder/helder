package helder.ui.draw;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// UiShader's shapes: the functions its fragments call, apart from it so
// that the CPU's canvas (soft.SoftCanvas) computes the same coverage from
// the same code, linking none of the shader's.

class UiShapes {
	// the signed distance from p (relative to the centre) to a rectangle
	// with rounded corners, each corner's radius its own (y down)
	public static function box(p:Vec2, half:Vec2, r:Vec4):Float {
		var rc = p.x > 0 ? (p.y > 0 ? r.z : r.y) : (p.y > 0 ? r.w : r.x);
		var rr = min(rc, min(half.x, half.y));
		var q = abs(p) - half + vec2(rr, rr);
		// (off a corner's arc the nearer side's distance itself, not through
		// length, which a GPU may round (Metal's): a side on whole pixels covers
		// them wholly, the same for any clip the side is of)
		return (q.x > 0 && q.y > 0 ? length(q) : max(q.x, q.y)) - rr;
	}

	// the same for a rectangle whose corners are quarter ellipses (rad: the
	// corner's radii across and down), to the first order in the corners
	public static function ellipseBox(p:Vec2, half:Vec2, rad:Vec2):Float {
		var rx = min(rad.x, half.x), ry = min(rad.y, half.y);
		var q = abs(p) - half + vec2(rx, ry);
		if (q.x > 0 && q.y > 0 && rx > 0 && ry > 0) {
			var k = length(q / vec2(rx, ry));
			return (k - 1) * k / length(q / vec2(rx * rx, ry * ry));
		}
		var e = abs(p) - half;
		return length(max(e, vec2(0, 0))) + min(max(e.x, e.y), 0);
	}

	// a dashed (style 1) or dotted (2) border's coverage at p (from the
	// centre), w the sides' widths, r the corners' radii: the side it is on the
	// one its distance to over that side's width is least (the corners split
	// on their diagonals); along its straight part (between its corners'
	// radii, where they are wider than it), an odd number of dashes and gaps
	// as long as each other, about three widths, the first and last at its
	// ends, a rounded corner's arc solid between them; or dots as wide as the
	// side, one at each end and spaced about a width apart, along a rounded
	// corner's arc too; anti-aliased over a pixel
	public static function dashes(p:Vec2, half:Vec2, w:Vec4, r:Vec4, style:Float):Float {
		var dt = (p.y + half.y) / max(w.x, 0.001), dr = (half.x - p.x) / max(w.y, 0.001);
		var db = (half.y - p.y) / max(w.z, 0.001), dl = (p.x + half.x) / max(w.w, 0.001);
		var across = min(dt, db) < min(dl, dr);
		var top = dt < db, left = dl < dr;
		var t = across ? p.x + half.x : p.y + half.y;
		var len = across ? 2 * half.x : 2 * half.y;
		var width = across ? (top ? w.x : w.z) : (left ? w.w : w.y);
		var depth = across ? (top ? p.y + half.y : half.y - p.y) : (left ? p.x + half.x : half.x - p.x);
		// (the radii at its start and end: top left to right, bottom left to right, left and right top to bottom)
		var rs = across ? (top ? r.x : r.w) : (left ? r.x : r.y);
		var re = across ? (top ? r.y : r.z) : (left ? r.w : r.z);
		rs = rs > width ? rs : 0.0;
		re = re > width ? re : 0.0;
		// (the corner it is in, mirrored to the top left's: its radius, its sides' widths)
		var q = vec2(-abs(p.x), -abs(p.y));
		var rc = p.x > 0 ? (p.y > 0 ? r.z : r.y) : (p.y > 0 ? r.w : r.x);
		var wh = p.y > 0 ? w.z : w.x, wv = p.x > 0 ? w.y : w.w;
		var cornered = rc > max(wh, wv) && q.x < rc - half.x && q.y < rc - half.y;
		if (style > 1.5) {
			if (cornered) {
				// (dots spaced along the arc, from the side's last to the other's first)
				var wc = (wh + wv) * 0.5, c = vec2(rc - half.x, rc - half.y), rr = rc - wc * 0.5;
				var n = max(1, floor(1.5707963 * rr / (2 * wc) + 0.5)), da = 1.5707963 / n;
				var a = clamp(atan2(c.y - q.y, c.x - q.x), 0, 1.5707963);
				var at = floor(a / da + 0.5) * da;
				var dot = c - vec2(cos(at), sin(at)) * rr;
				return clamp(wc * 0.5 - length(q - dot) + 0.5, 0, 1);
			}
			var a0 = max(rs, width * 0.5), a1 = max(re, width * 0.5);
			var span = max(len - a0 - a1, 0.001);
			var gaps = max(1, floor(span / (2 * width) + 0.5));
			var step = span / gaps;
			var u = t - a0;
			var along = u - floor(u / step + 0.5) * step;
			return clamp(width * 0.5 - length(vec2(along, depth - width * 0.5)) + 0.5, 0, 1);
		}
		if (cornered || t < rs || t > len - re) return 1.0;
		var straight = max(len - rs - re, 0.001);
		var k = max(1, floor((straight / (3 * max(width, 1)) - 1) * 0.5 + 0.5) * 2 + 1);
		var seg = straight / k;
		var v = t - rs;
		var g = v - floor(v / (2 * seg)) * 2 * seg;
		var d = g < seg ? min(g, seg - g) : -min(g - seg, 2 * seg - g);
		// (its first and last dash solid to its ends, where a corner goes on)
		if (v < seg) d = seg - v;
		if (v > straight - seg) d = v - (straight - seg);
		return clamp(0.5 + d, 0, 1);
	}

	// erf, approximated (Abramowitz and Stegun 7.1.27), on two values
	public static function erf2(x:Vec2):Vec2 {
		var s = sign(x), a = abs(x);
		var r = vec2(1, 1) + (vec2(0.278393, 0.278393) + (vec2(0.230389, 0.230389) + a * a * 0.078108) * a) * a;
		r = r * r;
		return s - s / (r * r);
	}

	// a row of the blurred rectangle: its coverage at x, y blurred along x
	// (the row's half width narrowed by the corner)
	public static function blurRow(x:Float, y:Float, sigma:Float, corner:Float, half:Vec2):Float {
		var delta = min(half.y - corner - abs(y), 0);
		var curved = half.x - corner + sqrt(max(0, corner * corner - delta * delta));
		var integral = vec2(0.5, 0.5) + erf2((vec2(x, x) + vec2(-curved, curved)) * (0.70710678 / sigma)) * 0.5;
		return integral.y - integral.x;
	}

	public static function gauss(y:Float, sigma:Float):Float
		return exp(-(y * y) / (2 * sigma * sigma)) / (2.5066283 * sigma);

	// a rectangle with rounded corners blurred by a Gaussian at p (from its
	// centre): rows blurred exactly, summed over the column at four points
	public static function blurred(p:Vec2, half:Vec2, r:Vec4, sigma:Float):Float {
		var rc = p.x > 0 ? (p.y > 0 ? r.z : r.y) : (p.y > 0 ? r.w : r.x);
		var corner = min(rc, min(half.x, half.y));
		var low = p.y - half.y, high = p.y + half.y;
		var y0 = clamp(-3 * sigma, low, high), y1 = clamp(3 * sigma, low, high);
		var dy = (y1 - y0) / 4;
		var y = y0 + dy * 0.5;
		var a = blurRow(p.x, p.y - y, sigma, corner, half) * gauss(y, sigma);
		a += blurRow(p.x, p.y - (y + dy), sigma, corner, half) * gauss(y + dy, sigma);
		a += blurRow(p.x, p.y - (y + 2 * dy), sigma, corner, half) * gauss(y + 2 * dy, sigma);
		a += blurRow(p.x, p.y - (y + 3 * dy), sigma, corner, half) * gauss(y + 3 * dy, sigma);
		return a * dy;
	}

	// (where p is in a turned quad (its corners a, b, c in target pixels),
	// from its centre in its own pixels: from the pixel's centre, not
	// interpolated, so the same in any target, a texture's or a frame's (GL
	// draws them each way up))
	public static function turned(p:Vec2, a:Vec2, b:Vec2, c:Vec2, ext:Vec2):Vec2 {
		var e1 = b - a, e2 = c - a, d = p - a;
		var det = e1.x * e2.y - e1.y * e2.x;
		var u = (d.x * e2.y - d.y * e2.x) / det, v = (e1.x * d.y - e1.y * d.x) / det;
		return vec2((u * 2 - 1) * ext.x, (v * 2 - 1) * ext.y);
	}
}
