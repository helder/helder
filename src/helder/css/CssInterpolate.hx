package helder.css;

import helder.css.CssCalc;
import helder.css.CssColors;
import helder.css.CssProperty;
import helder.css.CssTerm;

using Lambda;

// Computed values interpolated (Web Animations 1 §5, CSS Values 4 §3,
// each property's animation type): p of the way from a to b, p below 0
// or above 1 extrapolating. Lengths, percentages and their mixes (a calc()
// of both), numbers (integers rounded), colours (sRGB for legacy ones,
// Oklab else, premultiplied), the same keywords, functions of the same
// name, lists by layer (repeatable ones repeated to a common length),
// shadows (the shorter list padded with transparent ones), filters (none
// as each function's identity), 2D transforms (function by function where
// they match, the rest as decomposed matrices, CssTransforms), translate,
// scale and rotate (none as their identities), ratios (by their logs),
// visibility (visible between visible and hidden). Null when the values
// don't interpolate: the property is discrete, or they're of different
// kinds. The result is written back through the property's grammar, so it
// is clamped to its range and an integer's rounded.
class CssInterpolate {
	// Values computed with currentcolor resolved (CssTransition does it).
	public static function values(p:CssProperty, a:Array<CssTerm>, b:Array<CssTerm>, t:Float):Null<Array<CssTerm>> {
		var name = CssProperties.name(p);
		return switch CssProperties.animation(p) {
			case 0 | 2: null;
			case 3: finish(name, list(a, b, t, true));
			case _: finish(name, special(name, a, b, t));
		}
	}

	// (the properties whose types say more than by computed value)
	static function special(name:String, a:Array<CssTerm>, b:Array<CssTerm>, t:Float):Null<Array<CssTerm>>
		return switch name {
			case "visibility": visibility(a, b, t);
			case "transform": CssTransforms.interpolate(a, b, t);
			case "translate": individual(a, b, t, [Dimension(0, "px"), Dimension(0, "px"), Dimension(0, "px")], false);
			case "scale": individual(a, b, t, [Number(1, false), Number(1, false), Number(1, false)], true);
			case "rotate": rotate(a, b, t);
			case "box-shadow" | "text-shadow": shadows(a, b, t, name == "box-shadow");
			case "filter" | "backdrop-filter": filters(a, b, t);
			case "aspect-ratio": ratio(a, b, t);
			case "font-style": terms(oblique(a), oblique(b), t);
			case "background-position" | "object-position" | "transform-origin" | "background-size": list(a, b, t, true);
			// (one value of a pair is both)
			case "border-top-left-radius" | "border-top-right-radius" | "border-bottom-right-radius" | "border-bottom-left-radius" | "border-spacing":
				var r = a.length == b.length ? terms(a, b, t) : terms(a.length == 1 ? [a[0], a[0]] : a, b.length == 1 ? [b[0], b[0]] : b, t);
				r != null && r.length == 2 && CssText.term(r[0]) == CssText.term(r[1]) ? [r[0]] : r;
			case "letter-spacing" | "word-spacing": spacing(a, b, t);
			case _: list(a, b, t, false);
		}

	// (a comma-separated list: layer by layer; repeated to their lengths' least common multiple when repeatable)
	static function list(a:Array<CssTerm>, b:Array<CssTerm>, t:Float, repeat:Bool):Null<Array<CssTerm>> {
		var la = CssText.layers(a), lb = CssText.layers(b);
		if (la.length == 1 && lb.length == 1) return terms(a, b, t);
		var n = la.length;
		if (la.length != lb.length) {
			if (!repeat) return null;
			n = lcm(la.length, lb.length);
		}
		var out = [];
		for (k in 0...n) {
			var l = terms(la[k % la.length], lb[k % lb.length], t);
			if (l == null) return null;
			out.push(l);
		}
		return CssText.unlayers(out);
	}

	static function lcm(a:Int, b:Int):Int {
		var x = a, y = b;
		while (y != 0) {
			var r = x % y;
			x = y;
			y = r;
		}
		return Std.int(a / x) * b;
	}

	// Terms of the same shape, pair by pair.
	public static function terms(a:Array<CssTerm>, b:Array<CssTerm>, t:Float):Null<Array<CssTerm>> {
		if (a.length != b.length) return null;
		var out = [];
		for (k in 0...a.length) {
			var x = term(a[k], b[k], t);
			if (x == null) return null;
			out.push(x);
		}
		return out;
	}

	public static function term(x:CssTerm, y:CssTerm, t:Float):Null<CssTerm>
		return switch [x, y] {
			case [Number(u, _), Number(v, _)]: Number(lerp(u, v, t), false);
			case [Dimension(u, a), Dimension(v, b)] if (a == b): Dimension(lerp(u, v, t), a);
			case [Percentage(u), Percentage(v)]: Percentage(lerp(u, v, t));
			case [Dimension(_, _) | Percentage(_) | Calc(_, _, _), Dimension(_, _) | Percentage(_) | Calc(_, _, _)]: mix(x, y, t);
			case [Keyword(a), Keyword(b)] if (a == b): x;
			case [Ident(a), Ident(b)] if (a == b): x;
			case [Str(a), Str(b)] if (a == b): x;
			case [Delim(a), Delim(b)] if (a == b): x;
			case [Url(a, _), Url(b, _)] if (a == b): x;
			case [Raw(a), Raw(b)] if (a == b): x;
			case [Color(c), Color(d)]: color(c, d, t);
			// (a repeat()'s count is its tracks' shape: the same, or not interpolable)
			case [Func(f, a), Func(g, b)] if (f == g && (f != "repeat" || a.length > 0 && b.length > 0 && CssText.term(a[0]) == CssText.term(b[0]))):
				var args = terms(a, b, t);
				args == null ? null : Func(f, args);
			case [Brackets(o, a), Brackets(p, b)] if (o == p):
				var args = terms(a, b, t);
				args == null ? null : Brackets(o, args);
			case _: null;
		}

	static inline function lerp(a:Float, b:Float, t:Float):Float
		return a + (b - a) * t;

	// (a length and a percentage: calc() of both weighed)
	static function mix(x:CssTerm, y:CssTerm, t:Float):Null<CssTerm> {
		var a = node(x), b = node(y);
		if (a == null || b == null) return null;
		var sum = CssCalc.simplify(Sum([Product([a, Value(1 - t, "")]), Product([b, Value(t, "")])]));
		return switch sum {
			case Value(v, "%"): Percentage(v);
			case Value(v, u): Dimension(v, u);
			case n: Calc(n, "length-percentage", null);
		}
	}

	static function node(t:CssTerm):Null<CssCalcNode>
		return switch t {
			case Dimension(v, u): Value(v, u);
			case Percentage(v): Value(v, "%");
			case Calc(n, _, _): n;
			case _: null;
		}

	// A discrete property's value p of the way (transition-behavior:
	// allow-discrete's): the start's below halfway, the end's after; display
	// stays what isn't none (Transitions 2 §3.3).
	public static function discrete(p:CssProperty, a:Array<CssTerm>, b:Array<CssTerm>, t:Float):Array<CssTerm> {
		if (p == Display) {
			if (word(a) == "none" && word(b) != "none") return b;
			if (word(b) == "none" && word(a) != "none") return t >= 1 ? b : a;
		}
		return t < 0.5 ? a : b;
	}

	// ---- colours

	// (Color 4 §12: legacy colours in sRGB, others in Oklab; premultiplied; a missing component the other's)
	static function color(c:CssColorValue, d:CssColorValue, t:Float):Null<CssTerm> {
		c = system(c);
		d = system(d);
		if (c.c.length < 3 || d.c.length < 3) return null;
		var legacy = LEGACY.contains(c.space) && LEGACY.contains(d.space);
		var a = legacy ? [for (x in CssColors.srgb(c)) x] : oklab(c), b = legacy ? [for (x in CssColors.srgb(d)) x] : oklab(d);
		for (k in 0...3) {
			if (Math.isNaN(a[k])) a[k] = b[k];
			if (Math.isNaN(b[k])) b[k] = a[k];
		}
		var alphaA = Math.isNaN(c.alpha) ? d.alpha : c.alpha, alphaB = Math.isNaN(d.alpha) ? c.alpha : d.alpha;
		var alpha = lerp(alphaA, alphaB, t);
		var clamped = alpha < 0 ? 0.0 : alpha > 1 ? 1.0 : alpha;
		// (premultiplied, then divided by the alpha as clamped)
		var out = [for (k in 0...3) clamped == 0 ? lerp(a[k], b[k], t) : lerp(a[k] * alphaA, b[k] * alphaB, t) / clamped];
		return Color({space: legacy ? "rgb" : "oklab", c: out, alpha: clamped});
	}

	static final LEGACY = ["rgb", "hsl", "hwb"];

	// (a system colour as a light page's: what browsers give)
	static function system(c:CssColorValue):CssColorValue {
		if (c.c.length >= 3 || c.keyword == null) return c;
		var rgb = SYSTEM.get(c.keyword);
		return rgb == null ? c : {space: "rgb", c: rgb, alpha: c.alpha};
	}

	static final SYSTEM:Map<String, Array<Float>> = [
		"canvastext" => [0, 0, 0], "canvas" => [255, 255, 255], "linktext" => [0, 0, 238], "visitedtext" => [85, 26, 139],
		"activetext" => [255, 0, 0], "buttonface" => [240, 240, 240], "buttontext" => [0, 0, 0], "buttonborder" => [118, 118, 118],
		"field" => [255, 255, 255], "fieldtext" => [0, 0, 0], "graytext" => [109, 109, 109], "highlight" => [0, 120, 215],
		"highlighttext" => [255, 255, 255], "mark" => [255, 255, 0], "marktext" => [0, 0, 0], "selecteditem" => [0, 120, 215],
		"selecteditemtext" => [255, 255, 255], "accentcolor" => [0, 120, 215], "accentcolortext" => [255, 255, 255]
	];

	// (a colour in Oklab: L 0 to 1, a and b)
	static function oklab(c:CssColorValue):Array<Float> {
		if (c.space == "oklab") return c.c.copy();
		if (c.space == "oklch") {
			var h = c.c[2] * Math.PI / 180;
			return [c.c[0], c.c[1] * Math.cos(h), c.c[1] * Math.sin(h)];
		}
		var s = @:privateAccess CssRgba.srgb(c);
		var lin = [for (x in s) {
			var a = Math.abs(x);
			(x < 0 ? -1 : 1) * (a <= 0.04045 ? a / 12.92 : Math.pow((a + 0.055) / 1.055, 2.4));
		}];
		var l = 0.4122214708 * lin[0] + 0.5363325363 * lin[1] + 0.0514459929 * lin[2];
		var m = 0.2119034982 * lin[0] + 0.6806995451 * lin[1] + 0.1073969566 * lin[2];
		var q = 0.0883024619 * lin[0] + 0.2817188376 * lin[1] + 0.6299787005 * lin[2];
		var l_ = cbrt(l), m_ = cbrt(m), q_ = cbrt(q);
		return [
			0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * q_,
			1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * q_,
			0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * q_
		];
	}

	static inline function cbrt(x:Float):Float
		return x < 0 ? -Math.pow(-x, 1 / 3) : Math.pow(x, 1 / 3);

	// ---- the special ones

	// (Web Animations 1 §5.3: visible for p between 0 and 1 when either end is)
	static function visibility(a:Array<CssTerm>, b:Array<CssTerm>, t:Float):Null<Array<CssTerm>> {
		var x = word(a), y = word(b);
		if (x == y) return a;
		if (x != "visible" && y != "visible") return null;
		return t <= 0 ? a : t >= 1 ? b : [Keyword("visible")];
	}

	static function word(t:Array<CssTerm>):Null<String>
		return t.length == 1 ? switch t[0] {
			case Keyword(k): k;
			case _: null;
		} : null;

	// (translate's and scale's components, a missing one its identity, scale's
	// y its x; none as the identity)
	static function individual(a:Array<CssTerm>, b:Array<CssTerm>, t:Float, identity:Array<CssTerm>, scale:Bool):Null<Array<CssTerm>> {
		if (word(a) == "none" && word(b) == "none") return a;
		function full(v:Array<CssTerm>):Array<CssTerm> {
			if (word(v) == "none") return identity.copy();
			var out = v.copy();
			if (scale && out.length == 1) out.push(out[0]);
			while (out.length < 3) out.push(identity[out.length]);
			return out;
		}
		return terms(full(a), full(b), t);
	}

	// (an angle about the same axis, or z's, as none is; other axes are 3D's)
	static function rotate(a:Array<CssTerm>, b:Array<CssTerm>, t:Float):Null<Array<CssTerm>> {
		if (word(a) == "none" && word(b) == "none") return a;
		function axis(v:Array<CssTerm>):Null<{axis:String, angle:CssTerm}>
			return switch v {
				case [Keyword("none")]: {axis: "z", angle: Dimension(0, "deg")};
				case [angle]: {axis: "z", angle: angle};
				case [Keyword(k), angle]: {axis: k, angle: angle};
				case [Number(0, _), Number(0, _), Number(z, _), angle] if (z > 0): {axis: "z", angle: angle};
				case _: null;
			}
		var x = axis(a), y = axis(b);
		if (x == null || y == null) return null;
		if (x.axis != y.axis && !(word(a) == "none" || word(b) == "none")) return null;
		var k = word(a) == "none" ? y.axis : x.axis;
		var angle = term(x.angle, y.angle, t);
		if (angle == null) return null;
		return k == "z" ? [angle] : [Keyword(k), angle];
	}

	// (each shadow its colour, offsets, blur and spread, inset; the shorter list padded with transparent ones)
	static function shadows(a:Array<CssTerm>, b:Array<CssTerm>, t:Float, box:Bool):Null<Array<CssTerm>> {
		var la = word(a) == "none" ? [] : [for (l in CssText.layers(a)) shadow(l, box)];
		var lb = word(b) == "none" ? [] : [for (l in CssText.layers(b)) shadow(l, box)];
		if (la.length == 0 && lb.length == 0) return a;
		if (la.contains(null) || lb.contains(null)) return null;
		var out = [];
		for (k in 0...Std.int(Math.max(la.length, lb.length))) {
			var x = la[k] ?? blank(lb[k]), y = lb[k] ?? blank(la[k]);
			if (x.inset != y.inset) return null;
			var parts = terms(x.parts, y.parts, t);
			if (parts == null) return null;
			if (x.inset) parts.push(Keyword("inset"));
			out.push(parts);
		}
		return CssText.unlayers(out);
	}

	static function shadow(l:Array<CssTerm>, box:Bool):Null<{parts:Array<CssTerm>, inset:Bool}> {
		var color:CssTerm = Color(CssColors.keyword("transparent")), lengths = [], inset = false;
		for (x in l) switch x {
			case Color(_): color = x;
			case Keyword("inset"): inset = true;
			case Dimension(_, _) | Calc(_, _, _): lengths.push(x);
			case _: return null;
		}
		while (lengths.length < (box ? 4 : 3)) lengths.push(Dimension(0, "px"));
		return {parts: [color].concat(lengths), inset: inset};
	}

	static function blank(s:{parts:Array<CssTerm>, inset:Bool}):{parts:Array<CssTerm>, inset:Bool}
		return {parts: [Color(CssColors.keyword("transparent"))].concat([for (_ in 1...s.parts.length) Dimension(0, "px")]), inset: s.inset};

	// (Filter Effects 1 §14: function by function; none, or a missing tail, as each function's identity)
	static function filters(a:Array<CssTerm>, b:Array<CssTerm>, t:Float):Null<Array<CssTerm>> {
		if (word(a) == "none" && word(b) == "none") return a;
		var fa = word(a) == "none" ? [] : a, fb = word(b) == "none" ? [] : b;
		var out = [];
		for (k in 0...Std.int(Math.max(fa.length, fb.length))) {
			var x = k < fa.length ? fa[k] : identity(fb[k]), y = k < fb.length ? fb[k] : identity(fa[k]);
			if (x == null || y == null) return null;
			var r = switch [x, y] {
				case [Func("drop-shadow", p), Func("drop-shadow", q)]:
					var s = shadows(p, q, t, false);
					s == null ? null : Func("drop-shadow", s);
				case _: term(x, y, t);
			}
			if (r == null) return null;
			out.push(positive(r));
		}
		return out;
	}

	// (a filter's amounts and blurs, past 0 as extrapolated, at 0; hue-rotate's angle and drop-shadow's offsets anything)
	static function positive(f:CssTerm):CssTerm
		return switch f {
			case Func("hue-rotate", _): f;
			case Func("drop-shadow", args):
				var n = 0;
				Func("drop-shadow", [for (x in args) switch x {
					case Dimension(v, u) if (++n == 3 && v < 0): Dimension(0, u);
					case _: x;
				}]);
			case Func(name, [Number(v, _)]) if (v < 0): Func(name, [Number(0, false)]);
			case Func(name, [Dimension(v, u)]) if (v < 0): Func(name, [Dimension(0, u)]);
			case Func(name, [Percentage(v)]) if (v < 0): Func(name, [Percentage(0)]);
			case _: f;
		}

	// (Text 4: normal is 0, and 0 computes to normal)
	static function spacing(a:Array<CssTerm>, b:Array<CssTerm>, t:Float):Null<Array<CssTerm>> {
		inline function zero(v:Array<CssTerm>):Array<CssTerm>
			return word(v) == "normal" ? [Dimension(0, "px")] : v;
		var r = terms(zero(a), zero(b), t);
		return r != null && r.length == 1 && r[0].match(Dimension(0, _)) && (word(a) == "normal" || word(b) == "normal") ? [Keyword("normal")] : r;
	}

	static function identity(f:CssTerm):Null<CssTerm>
		return switch f {
			case Func("blur", _): Func("blur", [Dimension(0, "px")]);
			case Func("hue-rotate", _): Func("hue-rotate", [Dimension(0, "deg")]);
			case Func(n = "brightness" | "contrast" | "opacity" | "saturate", _): Func(n, [Number(1, false)]);
			case Func(n = "grayscale" | "invert" | "sepia", _): Func(n, [Number(0, false)]);
			case Func("drop-shadow", _): Func("drop-shadow", [Color(CssColors.keyword("transparent")), Dimension(0, "px"), Dimension(0, "px"), Dimension(0, "px")]);
			case _: null;
		}

	// (Values 4 §7.5: a ratio by its log; auto stays only where both have it)
	static function ratio(a:Array<CssTerm>, b:Array<CssTerm>, t:Float):Null<Array<CssTerm>> {
		function read(v:Array<CssTerm>):Null<{auto:Bool, r:Float}> {
			var auto = false, nums = [];
			for (x in v) switch x {
				case Keyword("auto"): auto = true;
				case Number(n, _): nums.push(n);
				case Delim("/"):
				case _: return null;
			}
			if (nums.length == 0) return {auto: auto, r: Math.NaN};
			var r = nums.length == 2 ? nums[0] / nums[1] : nums[0];
			return {auto: auto, r: r};
		}
		var x = read(a), y = read(b);
		if (x == null || y == null || x.auto != y.auto || Math.isNaN(x.r) || Math.isNaN(y.r) || x.r <= 0 || y.r <= 0 || !Math.isFinite(x.r)
			|| !Math.isFinite(y.r))
			return null;
		var r = Math.exp(lerp(Math.log(x.r), Math.log(y.r), t));
		var out:Array<CssTerm> = [Number(r, false), Delim("/"), Number(1, false)];
		return x.auto ? [Keyword("auto")].concat(out) : out;
	}

	// (Fonts 4: normal as oblique 0deg)
	static function oblique(v:Array<CssTerm>):Array<CssTerm>
		return switch v {
			case [Keyword("normal")]: [Keyword("oblique"), Dimension(0, "deg")];
			case [Keyword("oblique")]: [Keyword("oblique"), Dimension(14, "deg")];
			case _: v;
		}

	// ---- the result, through the grammar

	// (written and read back as the property: computed, clamped to its
	// ranges; out of them, each number as a calc(), which the grammar takes
	// and clamps, an integer's rounded)
	static function finish(name:String, terms:Null<Array<CssTerm>>):Null<Array<CssTerm>> {
		if (terms == null) return null;
		var read = parse(name, CssText.join(terms, CssText.term));
		if (read == null) read = parse(name, CssText.join(terms, calcs));
		return read ?? terms;
	}

	static function parse(name:String, text:String):Null<Array<CssTerm>>
		return switch CssValues.read(name, Css.values(text)) {
			case Terms(t): CssComputed.terms(name, CssCanonical.terms(name, CssShorthands.plain(t)), {fontSize: 16, parentFontSize: 16, rootFontSize: 16});
			case _: null;
		}

	static function calcs(t:CssTerm):String
		return switch t {
			case Number(_, _) | Dimension(_, _) | Percentage(_): 'calc(${CssText.term(t)})';
			case Func(f, args): '$f(${CssText.join(args, calcs)})';
			case _: CssText.term(t);
		}
}
