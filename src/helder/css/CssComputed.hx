package helder.css;

import helder.css.CssCalc;
import helder.css.CssTerm;

// What is known when computing without layout: the element's font size
// (em; font-size's own em is its parent's), the root's (rem), the
// viewport (vw, vh), its color (currentcolor).
typedef CssComputeContext = {
	?fontSize:Float,
	?parentFontSize:Float,
	?rootFontSize:Float,
	?viewport:{width:Float, height:Float},
	?color:String
}

// A specified value's terms as computed values (CSS Cascade 4 §4.4):
// absolute lengths in px and relative ones resolved where the context
// knows them, math functions simplified, clamped to their range and
// rounded when integers, keywords that compute to numbers as those
// (positions, font-width, line widths, font-size and font-weight's).
class CssComputed {
	public static function terms(property:String, terms:Array<CssTerm>, ctx:CssComputeContext):Array<CssTerm> {
		var fontSize = property == "font-size" ? ctx.parentFontSize ?? 16 : ctx.fontSize ?? 16;
		var calc:CssCalcContext = {fontSize: fontSize, rootFontSize: ctx.rootFontSize ?? 16, viewport: ctx.viewport};
		var out = [for (t in terms) term(t, calc)];
		return switch property {
			case "background-position" | "object-position": CssText.unlayers([for (l in CssText.layers(out)) position(l)]);
			case "background-position-x": CssText.unlayers([for (l in CssText.layers(out)) axis(l, "left", "right", "x-start", "x-end")]);
			case "background-position-y": CssText.unlayers([for (l in CssText.layers(out)) axis(l, "top", "bottom", "y-start", "y-end")]);
			case "background-image" | "list-style-image" | "border-image-source" | "content": [for (t in out) gradient(t)];
			case "font-width" | "font-stretch": [for (t in out) width(t)];
			case "border-top-width" | "border-right-width" | "border-bottom-width" | "border-left-width" | "border-width" | "outline-width":
				[for (t in out) line(t)];
			case "opacity":
				[for (t in out) switch t {
					case Number(v, _): Number(v < 0 ? 0 : v > 1 ? 1 : v, false);
					case Percentage(p): Number(p < 0 ? 0 : p > 100 ? 1 : p / 100, false);
					case _: t;
				}];
			case "font-weight":
				[for (t in out) switch t {
					case Keyword("normal"): Number(400, false);
					case Keyword("bold"): Number(700, false);
					case _: t;
				}];
			case "font-size":
				[for (t in out) switch t {
					case Keyword(k) if (SIZES.exists(k)): Dimension(SIZES[k], "px");
					case Percentage(p): Dimension(p * fontSize / 100, "px");
					case Calc(n, type, range): term(Calc(n, type, range), {fontSize: fontSize, rootFontSize: calc.rootFontSize, viewport: calc.viewport}, fontSize);
					case _: t;
				}];
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

	static final SIZES = [
		"xx-small" => 9.0, "x-small" => 10.0, "small" => 13.0, "medium" => 16.0, "large" => 18.0, "x-large" => 24.0, "xx-large" => 32.0, "xxx-large" => 48.0
	];

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
	static function axis(l:Array<CssTerm>, start:String, end:String, start2:String, end2:String):Array<CssTerm> {
		if (l.length == 1 && l[0].match(Keyword(_)) && (l[0].match(Keyword("x-start" | "x-end" | "y-start" | "y-end")))) return l;
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

	// a gradient's position as percentages, a centre left out
	static function gradient(t:CssTerm):CssTerm
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
