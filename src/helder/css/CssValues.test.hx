package helder.css;

import helder.css.CssData;
import helder.css.CssGrammar;
import helder.test.Choices;
import helder.test.Gen;
import helder.test.Test;

// helder.css's values (WPT's cases are the css lane's): examples of the
// matcher, the canonical forms, math functions, colours and computed
// values; then a property over every property's grammar: a value drawn
// from the grammar's tree parses, and its serialization parses back to a
// value that serializes the same.
function tests() {
	describe("CssValues", () -> {
		test("matches and serializes", () -> {
			equals(text("margin", "1px 1PX 1px"), "1px");
			equals(text("margin", "calc(1in + 1px) 0"), "calc(97px) 0px");
			equals(text("text-decoration-line", "overline underline"), "underline overline");
			equals(text("background", "url(a.png) no-repeat red"), "url(\"a.png\") no-repeat red");
			equals(text("display", "inline flow-root"), "inline-block");
			equals(text("color", "HSL(120 30% 50%)"), "rgb(89, 166, 89)");
			equals(text("color", "Red"), "red");
			equals(text("width", "calc(10% + 5px)"), "calc(10% + 5px)");
			equals(text("width", "clamp(1px, 2px, 3px)"), "calc(2px)");
			equals(text("grid-template-columns", "[a] 1fr repeat(2, 10px)"), "[a] 1fr repeat(2, 10px)");
			equals(text("width", "var(--w, 10px)"), "var(--w, 10px)");
			equals(text("width", "inherit"), "inherit");
		});
		test("rejects", () -> {
			for (c in [["width", "-1px"], ["counter-reset", "none 1"], ["color", "rgb(1, 2%, 3)"], ["width", "1px 2px"], ["font-weight", "sign(10%)"], ["margin", "auto inherit"],
				["width", "calc(1px+2px)"], ["no-such-property", "1px"], ["width", ""]])
				equals(CssValues.parse(c[0], c[1]), null, c.join(": "));
		});
		test("computes", () -> {
			equals(computed("margin-left", "1in"), "96px");
			equals(computed("width", "2em"), "32px");
			equals(computed("width", "calc(50% - 0px)"), "50%");
			equals(computed("color", "transparent"), "rgba(0, 0, 0, 0)");
			equals(computed("font-weight", "calc(0)"), "1");
			equals(computed("object-position", "right 10px top 5px"), "calc(100% - 10px) 5px");
			equals(computed("font-width", "semi-condensed"), "87.5%");
			equals(computed("border-top-width", "thick"), "5px");
		});
		test("relative colours: written as given, resolved when computed", () -> {
			equals(text("color", "rgba(from hsl(120deg 20% 50% / .5) r g calc(b * 2) / alpha)"), "rgb(from rgba(102, 153, 102, 0.5) r g calc(2 * b) / alpha)");
			equals(text("color", "rgb(from currentColor r g b)"), "rgb(from currentcolor r g b)");
			equals(computed("color", "rgb(from rebeccapurple r g b)"), "color(srgb 0.4 0.2 0.6)");
			equals(computed("color", "hsl(from rebeccapurple none s l / alpha)"), "hsl(none 50% 40%)");
			equals(computed("color", "lab(from lab(none 10 10) l a b)"), "lab(none 10 10)");
			equals(computed("color", "hsl(from lab(50 none none) h s l)"), "hsl(none none 46.6327%)");
			equals(computed("color", "color(from color(srgb 0.25 0.5 0.75) rec2020 r g b)"), "color(rec2020 0.420493 0.518024 0.741381)");
			equals(computed("color", "lch(from oklch(0.2 0.000004 180) l calc(c * 1000) h)"), "lch(7.22637 0 none)");
			equals(computed("color", "color(from color(display-p3 0.7 0.5 0.3 / 40%) display-p3 r g 0 / alpha)"), "color(display-p3 0.7 0.5 0 / 0.4)");
			for (c in ["rgb(from rebeccapurple r 10deg 10)", "rgb(from red, r, g, b)", "hsl(from red h s)", "rgb(from r g b)", "lab(from red l a x)"])
				equals(CssValues.parse("color", c), null, c);
		});
		test("numbers", () -> {
			equals(CssNumber.format(1 / 3), "0.333333");
			equals(CssNumber.format(1e6), "1e+06");
			equals(CssNumber.format(0.00001), "1e-05");
			equals(CssNumber.format(2147483647, true), "2147483647");
			equals(CssNumber.format(-0.0), "0");
			equals(CssNumber.format(99.99995), "100");
		});
		test("a value drawn from any property's grammar parses back to itself", () -> property(VALUE, c -> {
			var v = CssValues.parse(c.property, c.text);
			// (what a prose rule turns down is drawn again)
			assume(v != null || !PROSE.exists(c.property));
			require(v, '${c.property}: ${c.text} rejected');
			var s = CssValues.serialize(c.property, v);
			var w = CssValues.parse(c.property, s);
			require(w, '${c.property}: ${c.text} serializes as $s, rejected');
			equals(CssValues.serialize(c.property, w), s, '${c.property}: ${c.text}');
		}, {cases: 1500}));
	});
}

private function text(property:String, value:String):Null<String> {
	var v = CssValues.parse(property, value);
	return v == null ? null : CssValues.serialize(property, v);
}

private function computed(property:String, value:String):Null<String> {
	var v = CssValues.parse(property, value);
	return v == null ? null : CssValues.compute(property, v);
}

// (properties whose grammars the draw can't satisfy by its tree alone, and why)
private final UNDRAWABLE = [
	// a custom ident that may not be a keyword anywhere in the grammar: the draw picks its own, so only counters' none is left out
	"all" => "only CSS-wide keywords"
];

// (properties whose prose rules out some of what their grammars match, and what)
private final PROSE = [
	"transition-timing-function" => "steps()'s count at least 1, 2 for jump-none (Easing 1 §2.3)",
	"transition" => "steps()'s count; a duration not negative (Transitions 1 §2.2)",
	"transition-duration" => "not negative (Transitions 1 §2.2)",
	"filter" => "no negative amounts, nor a negative blur (Filter Effects 1 §5.1)",
	"backdrop-filter" => "no negative amounts, nor a negative blur (Filter Effects 1 §5.1)",
	"cursor" => "image-set() of URLs only (CSS UI 4 §5.1)"
];

private final VALUE:Gen<{property:String, text:String}> = c -> {
	var props = [for (p in CssData.properties) if (!UNDRAWABLE.exists(p.name) && p.alias == null) p];
	var p = props[c.choice(props.length - 1)];
	{property: p.name, text: draw(c, CssGrammars.of(p.syntax), [p.name], 0)};
}

// A text the grammar matches: an alternative, a count within the
// multiplier, each primitive a sample within its range.
private function draw(c:Choices, g:CssGrammar, ctx:Array<String>, depth:Int):String {
	// (deep in a recursive grammar: the first alternative, the fewest repetitions)
	var shallow = depth > 6;
	return switch g {
		case Keyword(k): k;
		case Delim(d): d;
		case Named(name, range): primitive(c, name, range) ?? {
				var t = CssGrammars.type(name, ctx);
				// (a type the grammar leaves to prose, as calc-size()'s keyword: not drawn)
				if (t == null || t.syntax == null) c.reject();
				draw(c, CssGrammars.of(t.syntax), ctx.concat([StringTools.endsWith(name, "()") ? name : '<$name>']), depth + 1);
			}
		case Prop(name):
			var p = CssGrammars.property(name);
			var syntax = p != null ? p.syntax : CssGrammars.type('\'$name\'', ctx).syntax;
			draw(c, CssGrammars.of(syntax), ctx.concat([name]), depth + 1);
		case Func(name, args): '$name(${args.match(Sequence([])) ? "" : draw(c, args, ctx, depth + 1)})';
		case Block("[", inner): '[${inner.match(Sequence([])) ? "" : draw(c, inner, ctx, depth + 1)}]';
		case Block(_, inner): '(${inner.match(Sequence([])) ? "" : draw(c, inner, ctx, depth + 1)})';
		case Sequence(xs):
			// (a comma beside a term drawn empty is left out, as Values 4 §2.6 says)
			var parts = [for (x in xs) draw(c, x, ctx, depth + 1)];
			spaced([for (k in 0...parts.length) if (!(xs[k].match(Delim(",")) && (k == 0 || parts[k - 1] == "" || k + 1 >= parts.length || parts[k + 1] == ""))) parts[k]]);
		case All(xs):
			var order = [for (k in 0...xs.length) k];
			shuffle(c, order);
			spaced([for (k in order) draw(c, xs[k], ctx, depth + 1)]);
		case Any(xs):
			var order = [for (k in 0...xs.length) k];
			shuffle(c, order);
			var n = 1 + (shallow ? 0 : c.choice(xs.length - 1));
			spaced([for (k in order.slice(0, n)) draw(c, xs[k], ctx, depth + 1)]);
		case One(xs): draw(c, xs[shallow ? 0 : c.choice(xs.length - 1)], ctx, depth + 1);
		case Repeat(x, min, max, comma):
			var top = max == -1 ? min + 2 : max > min + 2 ? min + 2 : max;
			var n = shallow ? min : min + c.choice(top - min);
			var parts = [for (_ in 0...n) draw(c, x, ctx, depth + 1)].filter(s -> s != "");
			parts.join(comma ? ", " : " ");
		case Required(x):
			var s = "";
			for (_ in 0...8) if ((s = draw(c, x, ctx, depth + 1)) != "") break;
			if (s == "") c.reject();
			s;
	}
}

private function spaced(parts:Array<String>):String
	return [for (p in parts) if (p != "") p].join(" ").split(" , ").join(", ");

private function shuffle(c:Choices, xs:Array<Int>)
	for (k in 0...xs.length - 1) {
		var j = k + c.choice(xs.length - 1 - k);
		var t = xs[k];
		xs[k] = xs[j];
		xs[j] = t;
	}

private function primitive(c:Choices, name:String, range:Null<CssRange>):Null<String> {
	var samples:Array<{v:Float, unit:String}> = switch name {
		case "length": [{v: 0, unit: ""}, {v: 1, unit: "px"}, {v: 2.5, unit: "em"}, {v: -3, unit: "pt"}, {v: 10, unit: "vw"}];
		case "percentage": [{v: 0, unit: "%"}, {v: 50, unit: "%"}, {v: -5, unit: "%"}];
		case "length-percentage": [{v: 1, unit: "px"}, {v: 50, unit: "%"}, {v: -2, unit: "em"}];
		case "number": [{v: 0, unit: ""}, {v: 1, unit: ""}, {v: 2.5, unit: ""}, {v: -1, unit: ""}];
		case "integer": [{v: 0, unit: ""}, {v: 1, unit: ""}, {v: 3, unit: ""}, {v: -2, unit: ""}];
		case "angle": [{v: 0, unit: "deg"}, {v: 45, unit: "deg"}, {v: 1, unit: "turn"}, {v: -10, unit: "grad"}];
		case "angle-percentage": [{v: 45, unit: "deg"}, {v: 10, unit: "%"}];
		case "time": [{v: 1, unit: "s"}, {v: 200, unit: "ms"}];
		case "frequency": [{v: 1, unit: "hz"}, {v: 2, unit: "khz"}];
		case "resolution": [{v: 1, unit: "dppx"}, {v: 96, unit: "dpi"}, {v: 2, unit: "x"}];
		case "flex": [{v: 1, unit: "fr"}, {v: 0.5, unit: "fr"}];
		case _: null;
	}
	if (samples != null) {
		var ok = samples.filter(s -> range == null || s.v >= range.min && s.v <= range.max && (range.unit == "" || s.unit == range.unit || s.v == 0));
		if (ok.length == 0) return CssNumber.format(range.min == Math.NEGATIVE_INFINITY ? 0 : range.min) + (range.unit != "" ? range.unit : samples[0].unit);
		var s = ok[c.choice(ok.length - 1)];
		return (name == "integer" ? Std.string(Std.int(s.v)) : CssNumber.format(s.v)) + s.unit;
	}
	var pick = (xs:Array<String>) -> xs[c.choice(xs.length - 1)];
	return switch name {
		// (four letters, one word: a feature tag, a language, a grid area alike)
		case "string": pick(["\"abcd\"", "'wght'"]);
		case "custom-ident" | "ident": pick(["foo", "bar-1"]);
		case "dashed-ident": "--x";
		case "url": pick(["url(a.png)", "url(\"b c.png\")"]);
		case "color": pick(["red", "#0f08", "rgb(1 2 3)", "hsl(120 50% 50%)", "transparent", "currentcolor", "lab(50 10 -20)", "color(display-p3 0.1 0.2 0.3)", "rgb(from red r g calc(b + 10) / alpha)", "oklch(from currentcolor l c h)"]);
		case "declaration-value" | "any-value": "a b";
		case "zero": "0";
		case "dimension": "1px";
		case "hex-color": "#abc";
		case _: null;
	}
}
