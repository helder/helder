package helder.css;

import helder.css.CssCalc;
import helder.css.CssTerm;

using Lambda;
using StringTools;

// What is known when computing without layout: the element's font size
// (em; font-size's own em is its parent's), the root's (rem), the line
// heights (lh, rlh: the right one for the property, null for normal), the
// viewport (vw, vh), its color (currentcolor), the first available font's
// metrics (ex, ch, cap, ic) and the root's (rex...), when an engine gives them.
typedef CssComputeContext = {
	?fontSize:Float,
	?parentFontSize:Float,
	?rootFontSize:Float,
	?lineHeight:Float,
	?rootLineHeight:Float,
	?viewport:{width:Float, height:Float},
	?color:String,
	// (the same colour as a value: what a relative colour of currentcolor resolves against)
	?currentColor:helder.css.CssColors.CssColorValue,
	?metrics:CssFontMetrics,
	?rootMetrics:CssFontMetrics
}

// A specified value's terms as computed values (CSS Cascade 4 §4.4):
// absolute lengths in px and relative ones resolved where the context
// knows them, math functions simplified, clamped to their range and
// rounded when integers, keywords that compute to numbers as those
// (positions, font-width, line widths, font-size and font-weight's).
class CssComputed {
	public static function terms(property:String, terms:Array<CssTerm>, ctx:CssComputeContext):Array<CssTerm> {
		var fontSize = property == "font-size" ? ctx.parentFontSize ?? 16 : ctx.fontSize ?? 16;
		var calc:CssCalcContext = {
			fontSize: fontSize,
			rootFontSize: ctx.rootFontSize ?? 16,
			lineHeight: ctx.lineHeight,
			rootLineHeight: ctx.rootLineHeight,
			viewport: ctx.viewport,
			metrics: ctx.metrics,
			rootMetrics: ctx.rootMetrics
		};
		var out = [for (t in terms) term(t, calc)];
		return switch property {
			case "background-position" | "object-position": CssText.unlayers([for (l in CssText.layers(out)) position(l)]);
			// (a logical keyword stays one alone; in a list of layers, browsers make it a percentage)
			case "background-position-x":
				var ls = CssText.layers(out);
				CssText.unlayers([for (l in ls) axis(l, "left", "right", "x-start", "x-end", ls.length == 1)]);
			case "background-position-y":
				var ls = CssText.layers(out);
				CssText.unlayers([for (l in ls) axis(l, "top", "bottom", "y-start", "y-end", ls.length == 1)]);
			case "background-image" | "list-style-image" | "border-image-source" | "content": [for (t in out) resolution(gradient(t))];
			// (horizontal text's shape: circle; filled is the default fill)
			case "text-emphasis-style":
				switch out {
					case [Keyword("filled")] | [Keyword("filled"), Keyword("circle")]: [Keyword("circle")];
					case [Keyword("open")]: [out[0], Keyword("circle")];
					case [Keyword("filled"), shape]: [shape];
					case _: out;
				}
			case "font-width" | "font-stretch": [for (t in out) width(t)];
			case "border-top-width" | "border-right-width" | "border-bottom-width" | "border-left-width" | "border-width" | "outline-width":
				[for (t in out) line(t)];
			case "opacity":
				[for (t in out) switch t {
					case Number(v, _): Number(v < 0 ? 0 : v > 1 ? 1 : v, false);
					case Percentage(p): Number(p < 0 ? 0 : p > 100 ? 1 : p / 100, false);
					case _: t;
				}];
			case "z-index":
				switch out {
					case [Number(v, _)]: [Number(Math.max(-2147483648, Math.min(2147483647, v)), true)];
					case _: out;
				}
			case "font-weight":
				[for (t in out) switch t {
					case Keyword("normal"): Number(400, false);
					case Keyword("bold"): Number(700, false);
					case _: t;
				}];
			case "font-size":
				[for (t in out) switch t {
					case Keyword(k) if (SIZES.exists(k)): Dimension(SIZES[k], "px");
					case Keyword("larger"): Dimension(step(fontSize, 1), "px");
					case Keyword("smaller"): Dimension(step(fontSize, -1), "px");
					case Percentage(p): Dimension(p * fontSize / 100, "px");
					case Calc(n, type, range): term(Calc(n, type, range), calc, fontSize);
					case _: t;
				}];
			// (Contain 2 §3: the sets strict and content name, as those keywords)
			case "contain":
				var words = [for (t in out) switch t {
					case Keyword(k): k;
					case _: "";
				}].join(" ");
				words == "layout style paint" ? [Keyword("content")] : words == "size layout style paint" ? [Keyword("strict")] : out;
			case "line-height":
				[for (t in out) switch t {
					case Percentage(p): Dimension(p * fontSize / 100, "px");
					case _: t;
				}];
			case "align-content" | "align-items" | "align-self" | "justify-content" | "justify-items" | "justify-self":
				// (outside a flex container flex-start is flow-start, Align 3)
				[for (t in out) switch t {
					case Keyword("flex-start"): Keyword("flow-start");
					case Keyword("flex-end"): Keyword("flow-end");
					case _: t;
				}];
			case "font-feature-settings" | "font-variation-settings": features(out);
			case "font-palette": [for (t in out) CssCanonical.paletteMix(t)];
			case "filter" | "backdrop-filter": [for (t in out) filter(t)];
			// (a number of steps at least 1, 2 for jump-none, Easing 1 §2.3)
			case "transition-timing-function":
				[for (t in out) switch t {
					case Func("steps", [Number(n, i), Delim(","), Keyword(p)]): Func("steps", [Number(Math.max(p == "jump-none" ? 2 : 1, n), i), Delim(","), Keyword(p)]);
					case Func("steps", [Number(n, i)]): Func("steps", [Number(Math.max(1, n), i)]);
					case _: t;
				}];
			case "grid-row-start" | "grid-row-end" | "grid-column-start" | "grid-column-end":
				// (span 1 with a name is span and the name)
				switch out {
					case [Keyword("span"), Number(1, _), name = Ident(_)]: [out[0], name];
					case _: out;
				}
			case "text-shadow" | "box-shadow": CssText.unlayers([for (l in CssText.layers(out)) shadow(l, property == "box-shadow")]);
			case "word-spacing": out.length == 1 && out[0].match(Keyword("normal")) ? [Dimension(0, "px")] : out;
			case "letter-spacing": out.length == 1 && out[0].match(Dimension(0, _)) ? [Keyword("normal")] : out;
			case "text-justify": [for (t in out) t.match(Keyword("distribute")) ? Keyword("inter-character") : t];
			case _: out;
		}
	}

	// (Filter Effects 1 §5.1: an amount as a number, 1 when left out, at
	// least 0, at most 1 for the ones that can't go past; blur() 0px;
	// hue-rotate() 0deg; drop-shadow()'s colour first, currentcolor when
	// left out, and its blur 0px)
	static function filter(t:CssTerm):CssTerm
		return switch t {
			case Func("blur", []): Func("blur", [Dimension(0, "px")]);
			case Func("hue-rotate", []) | Func("hue-rotate", [Number(0, _)]): Func("hue-rotate", [Dimension(0, "deg")]);
			case Func("drop-shadow", args):
				var color = args.find(a -> a.match(Color(_))) ?? Color(CssColors.keyword("currentcolor"));
				var lengths = args.filter(a -> !a.match(Color(_)));
				if (lengths.length == 2) lengths.push(Dimension(0, "px"));
				Func("drop-shadow", [color].concat(lengths));
			case Func(f = "brightness" | "contrast" | "grayscale" | "invert" | "opacity" | "saturate" | "sepia", args):
				var v:Null<Float> = switch args {
					case []: 1;
					case [Number(n, _)]: n;
					case [Percentage(p)]: p / 100;
					case _: null;
				}
				if (v == null) return t;
				if (v < 0) v = 0;
				if (v > 1 && f != "brightness" && f != "contrast" && f != "saturate") v = 1;
				Func(f, [Number(v, false)]);
			case _: t;
		}

	static final SIZES = [
		"xx-small" => 9.0, "x-small" => 10.0, "small" => 13.0, "medium" => 16.0, "large" => 18.0, "x-large" => 24.0, "xx-large" => 32.0, "xxx-large" => 48.0
	];

	// (larger and smaller: the parent's size a step along the absolute-size
	// table when it is one of its sizes, Fonts 4 §2.5; else, or past either
	// end, by browsers' ratio of 1.2)
	static function step(parent:Float, by:Int):Float {
		var i = TABLE.findIndex(s -> Math.abs(s - parent) < 1e-6), k = i + by;
		return i >= 0 && k >= 0 && k < TABLE.length ? TABLE[k] : by > 0 ? parent * 1.2 : parent / 1.2;
	}

	static final TABLE = [9.0, 10.0, 13.0, 16.0, 18.0, 24.0, 32.0, 48.0];

	static function term(t:CssTerm, calc:CssCalcContext, ?percent:Float):CssTerm
		return switch t {
			case Dimension(v, u):
				var c = CssCalc.canonical(v, u, calc);
				c == null ? t : Dimension(c.value, c.unit);
			case Calc(n, type, range):
				switch dropZeros(CssCalc.simplify(n, calc, percent)) {
					case Value(v, u):
						// (a NaN computes to 0, Values 4 §10.9)
						if (Math.isNaN(v)) v = 0;
						// (clamped to the grammar's range, an integer rounded)
						if (range != null) {
							var lo = CssCalc.canonical(range.min, range.unit), hi = CssCalc.canonical(range.max, range.unit);
							if (lo != null && v < lo.value) v = lo.value;
							if (hi != null && v > hi.value) v = hi.value;
						}
						if (type == "integer") v = Math.fround(v);
						u == "" ? Number(v, type == "integer") : u == "%" ? Percentage(v) : Dimension(v, u);
					case s: Calc(s, type, range);
				}
			case Func(name, args): Func(name, [for (a in args) term(a, calc, percent)]);
			case Brackets(open, args): Brackets(open, [for (a in args) term(a, calc, percent)]);
			case _: t;
		}

	// (a computed sum's zero dimensions add nothing: calc(50% + 0px) is 50%)
	static function dropZeros(n:CssCalcNode):CssCalcNode
		return switch n {
			case Sum(xs):
				var kept = xs.filter(x -> switch x {
					case Value(0, u): u == "%" || u == "";
					case _: true;
				});
				kept.length == 0 ? xs[0] : kept.length == 1 ? kept[0] : Sum(kept);
			case _: n;
		}

	// a position as two percentages or lengths: left 0%, center 50%, right 10px calc(100% - 10px)
	static function position(l:Array<CssTerm>):Array<CssTerm> {
		var x:Array<CssTerm>, y:Array<CssTerm>;
		inline function vertical(t:CssTerm):Bool
			return t.match(Keyword("top" | "bottom" | "y-start" | "y-end"));
		inline function horizontal(t:CssTerm):Bool
			return t.match(Keyword("left" | "right" | "x-start" | "x-end"));
		switch l.length {
			case 1:
				x = vertical(l[0]) ? [Keyword("center")] : [l[0]];
				y = vertical(l[0]) ? [l[0]] : [Keyword("center")];
			case 2:
				var swap = vertical(l[0]) || horizontal(l[1]);
				x = [swap ? l[1] : l[0]];
				y = [swap ? l[0] : l[1]];
			case 3 | 4:
				// (keywords with offsets: the first pair, then the rest)
				var first = l[1].match(Keyword(_)) ? [l[0]] : [l[0], l[1]];
				var second = l.slice(first.length);
				var swap = vertical(first[0]) || horizontal(second[0]);
				x = swap ? second : first;
				y = swap ? first : second;
			case _: return l;
		}
		var px = side(x, "left", "right", "x-start", "x-end"), py = side(y, "top", "bottom", "y-start", "y-end");
		return px == null || py == null ? l : [px, py];
	}

	// (a logical keyword alone stays one)
	static function axis(l:Array<CssTerm>, start:String, end:String, start2:String, end2:String, alone:Bool):Array<CssTerm> {
		if (alone && l.length == 1 && l[0].match(Keyword("x-start" | "x-end" | "y-start" | "y-end"))) return l;
		var s = side(l, start, end, start2, end2);
		return s == null ? l : [s];
	}

	static function side(part:Array<CssTerm>, start:String, end:String, start2:String, end2:String):Null<CssTerm> {
		var k = switch part[0] {
			case Keyword(w): w;
			case _: null;
		}
		var offset = k == null ? part[0] : part.length > 1 ? part[1] : null;
		if (k == null) return offset;
		if (k == "center") return Percentage(50);
		if (k == start || k == start2) return offset ?? Percentage(0);
		if (k != end && k != end2) return null;
		return switch offset {
			case null: Percentage(100);
			case Percentage(p): Percentage(100 - p);
			case Dimension(v, u): Calc(Sum([Value(100, "%"), Value(-v, u)]), "length-percentage", null);
			case _: null;
		}
	}

	// a gradient's position as percentages, a centre left out; a stop of two positions as two stops (Images 4 §3.4)
	static function gradient(t:CssTerm):CssTerm
		return switch t {
			case Func(name, args) if (name.endsWith("gradient") && args.exists(a -> a.match(Delim(",")))):
				var layers = CssText.layers(args);
				var split = [for (l in layers) switch l {
					case [c = Color(_), a, b] if (!a.match(Keyword(_)) && !b.match(Keyword(_))): [[c, a], [c, b]];
					case _: [l];
				}];
				var flat = [for (s in split) for (l in s) l];
				var out = Func(name, CssText.unlayers(flat));
				name.startsWith("radial") || name.startsWith("repeating-radial") || name.startsWith("conic") || name.startsWith("repeating-conic") ? placed(out) : out;
			case _: placed(t);
		}

	static function placed(t:CssTerm):CssTerm
		return switch t {
			case Func(name = "radial-gradient" | "repeating-radial-gradient" | "conic-gradient" | "repeating-conic-gradient", args):
				var at = -1, comma = -1;
				for (k in 0...args.length) {
					if (comma < 0 && args[k].match(Delim(","))) comma = k;
					if (comma < 0 && args[k].match(Keyword("at"))) at = k;
				}
				if (at < 0 || comma < 0) return t;
				var p = position(args.slice(at + 1, comma));
				var centre = p.length == 2 && p[0].match(Percentage(50)) && p[1].match(Percentage(50));
				var head = centre ? args.slice(0, at) : args.slice(0, at + 1).concat(p);
				Func(name, head.length == 0 ? args.slice(comma + 1) : head.concat(args.slice(comma)));
			case _: t;
		}

	// (image-set()'s resolutions: at least 0)
	static function resolution(t:CssTerm):CssTerm
		return switch t {
			case Func("image-set", args): Func("image-set", [for (a in args) switch a {
					case Dimension(v, u) if (v < 0): Dimension(0, u);
					case _: a;
				}]);
			case _: t;
		}

	// feature settings with a tag given twice: the last, sorted by tag
	static function features(l:Array<CssTerm>):Array<CssTerm> {
		var by = new Map<String, Array<CssTerm>>();
		for (f in CssText.layers(l)) switch f[0] {
			case Str(s): by.set(s, f);
			case _: return l;
		}
		var tags = [for (k in by.keys()) k];
		tags.sort(Reflect.compare);
		return CssText.unlayers([for (k in tags) by[k]]);
	}

	// a shadow's colour (currentcolor) and blur (0px) when left out
	static function shadow(l:Array<CssTerm>, box:Bool):Array<CssTerm> {
		if (l.length == 1 && l[0].match(Keyword("none"))) return l;
		var color = l.filter(t -> t.match(Color(_)));
		var lengths = l.filter(t -> t.match(Dimension(_, _) | Calc(_, _, _)));
		var inset = l.filter(t -> t.match(Keyword("inset")));
		if (lengths.length < 2) return l;
		while (lengths.length < (box ? 4 : 3)) lengths.push(Dimension(0, "px"));
		return (color.length > 0 ? color : [Color(CssColors.keyword("currentcolor"))]).concat(lengths).concat(inset);
	}

	// Fonts 4's font-width keywords as their percentages
	static function width(t:CssTerm):CssTerm
		return switch t {
			case Keyword(k):
				var p = [
					"ultra-condensed" => 50.0, "extra-condensed" => 62.5, "condensed" => 75.0, "semi-condensed" => 87.5, "normal" => 100.0,
					"semi-expanded" => 112.5, "expanded" => 125.0, "extra-expanded" => 150.0, "ultra-expanded" => 200.0
				][k];
				p == null ? t : Percentage(p);
			case _: t;
		}

	// a line width: thin 1px, medium 3px, thick 5px; above 1px down to a whole one, between 0 and 1 up to 1 (as browsers snap them)
	static function line(t:CssTerm):CssTerm
		return switch t {
			case Keyword("thin"): Dimension(1, "px");
			case Keyword("medium"): Dimension(3, "px");
			case Keyword("thick"): Dimension(5, "px");
			case Dimension(v, "px") if (v > 0 && v < 1): Dimension(1, "px");
			case Dimension(v, "px") if (v > 1): Dimension(Math.ffloor(v), "px");
			case _: t;
		}
}
