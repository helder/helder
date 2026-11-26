package helder.css;

import helder.css.CssCalc;
import helder.css.CssToken;

using StringTools;

// A colour of CSS Color 4 as written: its space and components (NaN for
// none). "rgb" is the legacy sRGB forms' (hex, names, rgb(), rgba()) in 0
// to 255; "hsl" and "hwb" keep their own (hue in degrees, the others 0 to
// 100) until serialized; "lab", "lch", "oklab", "oklch" and color()'s
// spaces their numbers. keyword: a named, system colour, transparent or
// currentcolor as written (its components resolved for a named one).
// parts: the three components and the alpha as written, when one is a
// math function (kept as specified, resolved when computed).
typedef CssColorValue = {space:String, c:Array<Float>, alpha:Float, ?keyword:String, ?parts:Array<CssColorPart>}

// kind: 0 a number, 1 a percentage, 2 an angle (in deg), 3 none; expr: the math function's tree
typedef CssColorPart = {v:Float, kind:Int, ?expr:CssCalcNode}

class CssColors {
	public static final SPACES = ["srgb", "srgb-linear", "display-p3", "display-p3-linear", "a98-rgb", "prophoto-rgb", "rec2020", "xyz", "xyz-d50", "xyz-d65"];
	static final FUNCTIONS = ["rgb", "rgba", "hsl", "hsla", "hwb", "lab", "lch", "oklab", "oklch", "color"];
	static final SYSTEM = [
		"accentcolor", "accentcolortext", "activetext", "buttonborder", "buttonface", "buttontext", "canvas", "canvastext", "field", "fieldtext", "graytext",
		"highlight", "highlighttext", "linktext", "mark", "marktext", "selecteditem", "selecteditemtext", "visitedtext", "activeborder", "activecaption",
		"appworkspace", "background", "buttonhighlight", "buttonshadow", "captiontext", "inactiveborder", "inactivecaption", "inactivecaptiontext",
		"infobackground", "infotext", "menu", "menutext", "scrollbar", "threeddarkshadow", "threedface", "threedhighlight", "threedlightshadow",
		"threedshadow", "window", "windowframe", "windowtext"
	];

	// Whether parse reads this value: a hash, a keyword, or one of Color 4's
	// functions without `from` (color-mix(), relative colours and the rest
	// are left to the grammar).
	public static function handles(v:CssValue):Bool
		return switch v {
			case Token(t): switch t.kind {
					case Hash(_, _) | Ident(_): true;
					case _: false;
				}
			case Function(name, values, _, _): FUNCTIONS.contains(Css.lower(name)) && !relative(values);
			case _: false;
		}

	static function relative(values:Array<CssValue>):Bool {
		for (v in values) switch v {
			case Token(t): switch t.kind {
					case Whitespace:
					case Ident(w): return Css.lower(w) == "from";
					case _: return false;
				}
			case _: return false;
		}
		return false;
	}

	public static function parse(v:CssValue):Null<CssColorValue> {
		return switch v {
			case Token(t): switch t.kind {
					case Hash(h, _): hex(h);
					case Ident(w): keyword(w);
					case _: null;
				}
			case Function(name, values, _, _): try function_(Css.lower(name), values) catch (e:Bad) null;
			case _: null;
		}
	}

	public static function keyword(w:String):Null<CssColorValue> {
		var l = Css.lower(w);
		if (l == "transparent") return {space: "rgb", c: [0, 0, 0], alpha: 0, keyword: l};
		if (l == "currentcolor" || 	SYSTEM.contains(l)) return {space: "rgb", c: [], alpha: 1, keyword: l};
		var n = names().get(l);
		return n == null ? null : {space: "rgb", c: [(n >> 16) & 255, (n >> 8) & 255, n & 255].map(x -> (x:Float)), alpha: 1, keyword: l};
	}

	static function hex(h:String):Null<CssColorValue> {
		var n = h.length;
		if (n != 3 && n != 4 && n != 6 && n != 8) return null;
		var d = [];
		for (k in 0...n) {
			var x = digit(h.fastCodeAt(k));
			if (x < 0) return null;
			d.push(x);
		}
		var c:Array<Float> = n <= 4 ? [for (k in 0...n) d[k] * 17.0] : [for (k in 0...(n >> 1)) d[2 * k] * 16.0 + d[2 * k + 1]];
		return {space: "rgb", c: c.slice(0, 3), alpha: c.length == 4 ? c[3] / 255 : 1};
	}

	static function digit(c:Int):Int
		return c >= "0".code && c <= "9".code ? c - "0".code : c >= "a".code && c <= "f".code ? c - "a".code + 10 : c >= "A".code && c <= "F".code ? c - "A".code + 10 : -1;

	// ---- functions

	static inline var NUMBER = 0;
	static inline var PERCENT = 1;
	static inline var ANGLE = 2;
	static inline var NONE = 3;

	static function function_(name:String, values:Array<CssValue>):CssColorValue {
		var items = [for (v in values) if (!isSpace(v)) v];
		if (Lambda.exists(items, isComma)) return legacy(name, items);
		var space = switch name {
			case "rgba": "rgb";
			case "hsla": "hsl";
			case "color":
				if (items.length == 0) throw new Bad();
				switch items.shift() {
					case Token(t): switch t.kind {
							case Ident(w) if (SPACES.contains(Css.lower(w))): Css.lower(w) == "xyz" ? "xyz-d65" : Css.lower(w);
							case _: throw new Bad();
						}
					case _: throw new Bad();
				}
			case n: n;
		}
		var alpha:Null<CssColorPart> = null;
		var slash = -1;
		for (k in 0...items.length) if (isDelim(items[k], "/")) slash = k;
		if (slash >= 0) {
			if (slash != items.length - 2) throw new Bad();
			alpha = component(items[slash + 1]);
			items = items.slice(0, slash);
		}
		if (items.length != 3) throw new Bad();
		var parts = [for (v in items) component(v)];
		// (an angle only as a hue, which is no percentage)
		var hue = space == "hsl" || space == "hwb" ? 0 : space == "lch" || space == "oklch" ? 2 : -1;
		for (k in 0...3) if (parts[k].kind == ANGLE && k != hue || k == hue && parts[k].kind == PERCENT) throw new Bad();
		if (alpha != null && alpha.kind == ANGLE) throw new Bad();
		return make(space, parts.concat([alpha ?? {v: 1, kind: NUMBER}]));
	}

	// rgb(1, 2, 3), rgba(), hsl(), hsla() with commas: no none, rgb()'s all numbers or all percentages
	static function legacy(name:String, items:Array<CssValue>):CssColorValue {
		var parts = [];
		for (k in 0...items.length) {
			if (k % 2 == 1) {
				if (!isComma(items[k])) throw new Bad();
			} else if (isComma(items[k])) throw new Bad();
			else parts.push(component(items[k]));
		}
		if (items.length % 2 == 0 || parts.length < 3 || parts.length > 4) throw new Bad();
		for (p in parts) if (p.kind == NONE) throw new Bad();
		if (parts.length == 3) parts.push({v: 1, kind: NUMBER});
		return switch name {
			case "rgb" | "rgba":
				var kind = parts[0].kind;
				if (kind == ANGLE || parts[3].kind == ANGLE) throw new Bad();
				for (k in 1...3) if (parts[k].kind != kind) throw new Bad();
				make("rgb", parts);
			case "hsl" | "hsla":
				if (parts[0].kind == PERCENT || parts[1].kind != PERCENT || parts[2].kind != PERCENT || parts[3].kind == ANGLE) throw new Bad();
				make("hsl", parts);
			case _: throw new Bad();
		}
	}

	// (a colour of its parts; parts kept when one is a math function)
	static function make(space:String, parts:Array<CssColorPart>):CssColorValue {
		var r = channels(space, parts);
		var c:CssColorValue = {space: space, c: r.c, alpha: r.alpha};
		if (Lambda.exists(parts, p -> p.expr != null)) c.parts = parts;
		return c;
	}

	// The components in the space's own numbers: percentages scaled,
	// lightness clamped, chroma at least 0, a polar hue in [0, 360), the
	// alpha in [0, 1]. A math function not resolved yet is NaN here.
	static function channels(space:String, parts:Array<CssColorPart>):{c:Array<Float>, alpha:Float} {
		// (none is NaN; a math function's NaN is 0)
		inline function at(k:Int, scale:Float):Float {
			var p = parts[k];
			var v = p.kind == NONE || unresolved(p) ? Math.NaN : Math.isNaN(p.v) ? 0 : p.v;
			return p.kind == PERCENT ? v * scale : v;
		}
		var c = switch space {
			case "rgb": [for (k in 0...3) at(k, 2.55)];
			case "hsl": [finiteHue(at(0, 1)), clampNaN(at(1, 1), 0, Math.POSITIVE_INFINITY), at(2, 1)];
			case "hwb": [finiteHue(at(0, 1)), at(1, 1), at(2, 1)];
			case "lab": [clampNaN(at(0, 1), 0, 100), at(1, 1.25), at(2, 1.25)];
			case "lch": [clampNaN(at(0, 1), 0, 100), clampNaN(at(1, 1.5), 0, Math.POSITIVE_INFINITY), turn(at(2, 1))];
			case "oklab": [clampNaN(at(0, 0.01), 0, 1), at(1, 0.004), at(2, 0.004)];
			case "oklch": [clampNaN(at(0, 0.01), 0, 1), clampNaN(at(1, 0.004), 0, Math.POSITIVE_INFINITY), turn(at(2, 1))];
			case _: [for (k in 0...3) at(k, 0.01)];
		}
		var a = parts[3];
		var alpha = unresolved(a) || a.kind == NONE ? Math.NaN : Math.isNaN(a.v) ? 0 : clamp(a.kind == PERCENT ? a.v / 100 : a.v, 0, 1);
		return {c: c, alpha: alpha};
	}

	static function percentType(s:CssCalcNode):Bool {
		var t = CssCalc.type(s, -1);
		return t != null && CssCalc.isBase(t, 6);
	}

	static function unresolved(p:CssColorPart):Bool
		return p.expr != null && !p.expr.match(Value(_, _));

	static function component(v:CssValue):CssColorPart {
		switch v {
			case Token(t):
				switch t.kind {
					case Number(n, _, _): return {v: n, kind: NUMBER};
					case Percentage(n, _, _): return {v: n, kind: PERCENT};
					case Dimension(n, _, _, unit):
						var c = CssCalc.canonical(n, Css.lower(unit));
						if (c == null || c.unit != "deg") throw new Bad();
						return {v: c.value, kind: ANGLE};
					case Ident(w) if (Css.lower(w) == "none"): return {v: Math.NaN, kind: NONE};
					case _:
				}
			case Function(_, _, _, _):
				var n = CssCalc.parse(v);
				if (n == null) throw new Bad();
				var s = CssCalc.simplify(n);
				// (a percentage inside only where the component is one: not sign(50%) in a hue)
				var hasPercent = CssCalc.hasPercent(n);
				return switch s {
					case _ if (hasPercent && !percentType(s)): throw new Bad();
					case Value(x, ""): {v: x, kind: NUMBER, expr: s};
					case Value(x, "%"): {v: x, kind: PERCENT, expr: s};
					case Value(x, "deg"): {v: x, kind: ANGLE, expr: s};
					case Value(_, _): throw new Bad();
					case _:
						// (one to resolve when computed: sign(1em - 10px))
						var type = CssCalc.type(s, -1);
						if (type == null) throw new Bad();
						var kind = CssCalc.isNumber(type) ? NUMBER : CssCalc.isBase(type, 6) ? PERCENT : CssCalc.isBase(type, 1) ? ANGLE : throw new Bad();
						{v: 0, kind: kind, expr: s};
				}
			case _:
		}
		throw new Bad();
	}

	// (a hue of a legacy form: NaN of a math function and the infinities as 0)
	static function finiteHue(h:Float):Float
		return Math.isNaN(h) || Math.isFinite(h) ? h : 0;

	// (a hue in [0, 360), the infinities as 0)
	static function turn(h:Float):Float {
		if (Math.isNaN(h)) return h;
		if (!Math.isFinite(h)) return 0;
		var r = h % 360;
		return r < 0 ? r + 360 : r;
	}

	static inline function clamp(x:Float, lo:Float, hi:Float):Float
		return x < lo ? lo : x > hi ? hi : x;

	static function clampNaN(x:Float, lo:Float, hi:Float):Float
		return Math.isNaN(x) ? x : clamp(x, lo, hi);

	static function isSpace(v:CssValue):Bool
		return switch v {
			case Token(t): t.kind.match(Whitespace);
			case _: false;
		}

	static function isComma(v:CssValue):Bool
		return switch v {
			case Token(t): t.kind.match(Comma);
			case _: false;
		}

	static function isDelim(v:CssValue, d:String):Bool
		return switch v {
			case Token(t): switch t.kind {
					case Delim(x): x == d;
					case _: false;
				}
			case _: false;
		}

	// ---- serialization (Color 4 §15)

	// As a specified value: a keyword as one; the legacy forms (hsl() and
	// hwb() too) as rgb() or rgba(), unless a component is none (then in
	// their own function; rgb()'s as color(srgb)) or a math function to
	// resolve later (in the modern syntax, it kept); the others in their
	// function, a math function as calc() of its value.
	public static function specified(c:CssColorValue):String {
		if (c.keyword != null) return c.keyword;
		if (c.parts != null && Lambda.exists(c.parts, unresolved)) return modern(c);
		return written(c, true);
	}

	// As a computed value: keywords resolved (currentcolor to `current`,
	// when known), math functions too (in the default context; null when
	// they can't be).
	public static function computed(c:CssColorValue, ?current:String, ?ctx:CssCalcContext):Null<String> {
		if (c.keyword == "currentcolor") return current ?? "currentcolor";
		// (the light scheme's Canvas and CanvasText, as browsers have them; the other system colours as written)
		if (c.keyword == "canvastext") return "rgb(0, 0, 0)";
		if (c.keyword == "canvas") return "rgb(255, 255, 255)";
		if (c.keyword != null && c.c.length == 0) return c.keyword;
		if (c.parts != null && Lambda.exists(c.parts, unresolved)) {
			var parts = [for (p in c.parts) if (!unresolved(p)) p else switch CssCalc.simplify(p.expr, ctx) {
				case Value(x, _): ({v: x, kind: p.kind, expr: Value(x, "")} : CssColorPart);
				case _: return null;
			}];
			var r = channels(c.space, parts);
			return written({space: c.space, c: r.c, alpha: r.alpha}, false);
		}
		return written({space: c.space, c: c.c, alpha: c.alpha}, false);
	}

	// (specified: math functions as calc() of their values in the modern spaces)
	static function written(c:CssColorValue, specified:Bool):String {
		var none = Lambda.exists(c.c, Math.isNaN) || Math.isNaN(c.alpha);
		var exprs = specified && c.parts != null && !["rgb", "hsl", "hwb"].contains(c.space);
		inline function comp(k:Int):String
			return exprs && c.parts[k].expr != null ? CssCalc.serialize(c.parts[k].expr) : num(c.c[k]);
		inline function alpha():String
			return exprs && c.parts[3].expr != null ? ' / ${CssCalc.serialize(c.parts[3].expr)}' : alphaText(c.alpha);
		return switch c.space {
			case "rgb" | "hsl" | "hwb" if (!none): rgbText(srgb(c), c.alpha);
			case "rgb": 'color(srgb ${[for (x in c.c) num(x / 255)].join(" ")}${alphaText(c.alpha)})';
			case "hsl": 'hsl(${num(c.c[0])} ${pct(c.c[1])} ${pct(c.c[2])}${alphaText(c.alpha)})';
			case "hwb": 'hwb(${num(c.c[0])} ${pct(c.c[1])} ${pct(c.c[2])}${alphaText(c.alpha)})';
			case "lab" | "lch" | "oklab" | "oklch": '${c.space}(${comp(0)} ${comp(1)} ${comp(2)}${alpha()})';
			case _: 'color(${c.space} ${comp(0)} ${comp(1)} ${comp(2)}${alpha()})';
		}
	}

	// (a colour with a math function to resolve: modern syntax, the other components as numbers)
	static function modern(c:CssColorValue):String {
		var legacyRgb = c.space == "rgb";
		var parts = [for (k in 0...4) {
			var p = c.parts[k];
			if (unresolved(p)) CssCalc.serialize(p.expr) else if (k == 3) CssNumber.format(c.alpha) else if (legacyRgb) CssNumber.format(clamp(c.c[k], 0, 255)) else num(c.c[k]);
		}];
		var name = switch c.space {
			case "rgb" | "hsl" | "hwb" | "lab" | "lch" | "oklab" | "oklch": c.space;
			case s: 'color($s';
		}
		var alpha = unresolved(c.parts[3]) || c.alpha < 1 ? ' / ${parts[3]}' : "";
		return name.startsWith("color(") ? '$name ${parts.slice(0, 3).join(" ")}$alpha)' : '$name(${parts.slice(0, 3).join(" ")}$alpha)';
	}

	static function num(x:Float):String
		return Math.isNaN(x) ? "none" : !Math.isFinite(x) ? 'calc(${CssNumber.format(x)})' : CssNumber.format(x);

	static function pct(x:Float):String
		return Math.isNaN(x) ? "none" : CssNumber.format(x) + "%";

	static function alphaText(a:Float):String
		return Math.isNaN(a) ? " / none" : a >= 1 ? "" : ' / ${CssNumber.format(a)}';

	static function rgbText(c:Array<Float>, alpha:Float):String {
		// (a hair over, for 127.5 computed as 127.49999)
		var rgb = [for (x in c) Std.string(Math.round(clamp(Math.isNaN(x) ? 0 : x, 0, 255) + 1e-9))].join(", ");
		return alpha >= 1 ? 'rgb($rgb)' : 'rgba($rgb, ${CssNumber.format(clamp(alpha, 0, 1))})';
	}

	// A legacy form's sRGB, 0 to 255: hsl() and hwb() converted (Color 4 §7.1, §8.1).
	public static function srgb(c:CssColorValue):Array<Float> {
		return switch c.space {
			case "hsl": [for (x in hsl(c.c[0], c.c[1] / 100, c.c[2] / 100)) x * 255];
			case "hwb":
				var w = c.c[1] / 100, b = c.c[2] / 100;
				if (w + b >= 1) {
					var g = w / (w + b) * 255;
					[g, g, g];
				} else [for (x in hsl(c.c[0], 1, 0.5)) (x * (1 - w - b) + w) * 255];
			case _: c.c;
		}
	}

	static function hsl(h:Float, s:Float, l:Float):Array<Float> {
		h = h % 360;
		if (h < 0) h += 360;
		if (s < 0) s = 0;
		function f(n:Float):Float {
			var k = (n + h / 30) % 12;
			var a = s * Math.min(l, 1 - l);
			return l - a * Math.max(-1, Math.min(Math.min(k - 3, 9 - k), 1));
		}
		return [f(0), f(8), f(4)];
	}

	static var table:Null<Map<String, Int>>;

	static function names():Map<String, Int> {
		if (table != null) return table;
		var t = new Map<String, Int>();
		for (pair in NAMED.split(" ")) {
			var kv = pair.split(":");
			t.set(kv[0], Std.parseInt("0x" + kv[1]));
		}
		return table = t;
	}

	// (CSS Color 4's 148 named colours, as helder.gfx.CssColor has them)
	static final NAMED = "aliceblue:f0f8ff antiquewhite:faebd7 aqua:00ffff aquamarine:7fffd4 azure:f0ffff beige:f5f5dc bisque:ffe4c4 black:000000 blanchedalmond:ffebcd blue:0000ff blueviolet:8a2be2 brown:a52a2a burlywood:deb887 cadetblue:5f9ea0 chartreuse:7fff00 chocolate:d2691e coral:ff7f50 cornflowerblue:6495ed cornsilk:fff8dc crimson:dc143c cyan:00ffff darkblue:00008b darkcyan:008b8b darkgoldenrod:b8860b darkgray:a9a9a9 darkgreen:006400 darkgrey:a9a9a9 darkkhaki:bdb76b darkmagenta:8b008b darkolivegreen:556b2f darkorange:ff8c00 darkorchid:9932cc darkred:8b0000 darksalmon:e9967a darkseagreen:8fbc8f darkslateblue:483d8b darkslategray:2f4f4f darkslategrey:2f4f4f darkturquoise:00ced1 darkviolet:9400d3 deeppink:ff1493 deepskyblue:00bfff dimgray:696969 dimgrey:696969 dodgerblue:1e90ff firebrick:b22222 floralwhite:fffaf0 forestgreen:228b22 fuchsia:ff00ff gainsboro:dcdcdc ghostwhite:f8f8ff gold:ffd700 goldenrod:daa520 gray:808080 green:008000 greenyellow:adff2f grey:808080 honeydew:f0fff0 hotpink:ff69b4 indianred:cd5c5c indigo:4b0082 ivory:fffff0 khaki:f0e68c lavender:e6e6fa lavenderblush:fff0f5 lawngreen:7cfc00 lemonchiffon:fffacd lightblue:add8e6 lightcoral:f08080 lightcyan:e0ffff lightgoldenrodyellow:fafad2 lightgray:d3d3d3 lightgreen:90ee90 lightgrey:d3d3d3 lightpink:ffb6c1 lightsalmon:ffa07a lightseagreen:20b2aa lightskyblue:87cefa lightslategray:778899 lightslategrey:778899 lightsteelblue:b0c4de lightyellow:ffffe0 lime:00ff00 limegreen:32cd32 linen:faf0e6 magenta:ff00ff maroon:800000 mediumaquamarine:66cdaa mediumblue:0000cd mediumorchid:ba55d3 mediumpurple:9370db mediumseagreen:3cb371 mediumslateblue:7b68ee mediumspringgreen:00fa9a mediumturquoise:48d1cc mediumvioletred:c71585 midnightblue:191970 mintcream:f5fffa mistyrose:ffe4e1 moccasin:ffe4b5 navajowhite:ffdead navy:000080 oldlace:fdf5e6 olive:808000 olivedrab:6b8e23 orange:ffa500 orangered:ff4500 orchid:da70d6 palegoldenrod:eee8aa palegreen:98fb98 paleturquoise:afeeee palevioletred:db7093 papayawhip:ffefd5 peachpuff:ffdab9 peru:cd853f pink:ffc0cb plum:dda0dd powderblue:b0e0e6 purple:800080 rebeccapurple:663399 red:ff0000 rosybrown:bc8f8f royalblue:4169e1 saddlebrown:8b4513 salmon:fa8072 sandybrown:f4a460 seagreen:2e8b57 seashell:fff5ee sienna:a0522d silver:c0c0c0 skyblue:87ceeb slateblue:6a5acd slategray:708090 slategrey:708090 snow:fffafa springgreen:00ff7f steelblue:4682b4 tan:d2b48c teal:008080 thistle:d8bfd8 tomato:ff6347 turquoise:40e0d0 violet:ee82ee wheat:f5deb3 white:ffffff whitesmoke:f5f5f5 yellow:ffff00 yellowgreen:9acd32";
}

private class Bad extends haxe.Exception {
	public function new()
		super("not a colour");
}
