package helder.css;

import helder.css.CssData;
import helder.css.CssGrammar;
import helder.test.Gen;
import helder.test.Test;

// Every definition of the generated data parses, prints back to itself and
// references only what the data defines (in its context); then the shapes
// of a few, the errors, and a property: any tree prints to text that parses
// back to it.
@:test.interp
function tests() {
	describe("CssGrammars", () -> {
		test("every definition parses and prints back", () -> {
			var failed = [];
			for (d in definitions()) try {
				var g = CssGrammars.parse(d.syntax);
				if (!same(CssGrammars.parse(CssGrammars.print(g)), g)) failed.push('${d.name}: ${CssGrammars.print(g)}');
			} catch (e) failed.push('${d.name}: ${e.message}');
			equals(failed, []);
		});
		test("every reference is defined", () -> {
			var missing = [];
			for (d in definitions()) for (r in references(CssGrammars.parse(d.syntax)))
				if (CssGrammars.type(r, d.context) == null && (r.charAt(0) != "'" || CssGrammars.property(r.substr(1, r.length - 2)) == null))
					missing.push('${d.name}: $r');
			equals(missing, []);
		});
		test("shorthands' longhands and aliases are in the table", () -> {
			var missing = [];
			for (p in CssData.properties) for (l in p.longhands.concat(p.alias == null ? [] : [p.alias]))
				if (CssGrammars.property(l) == null) missing.push('${p.name}: $l');
			equals(missing, []);
		});
		test("shapes", () -> {
			equals(CssGrammars.parse("<'margin-top'>{1,4}"), Repeat(Prop("margin-top"), 1, 4, false));
			equals(CssGrammars.parse("a b | c && d || e"), One([Sequence([Keyword("a"), Keyword("b")]), Any([All([Keyword("c"), Keyword("d")]), Keyword("e")])]));
			equals(CssGrammars.parse("a || [ b || c ]"), Any([Keyword("a"), Any([Keyword("b"), Keyword("c")])]));
			equals(CssGrammars.parse("<length [0,∞]>#?"), Repeat(Repeat(Named("length", {min: 0, max: Math.POSITIVE_INFINITY, unit: ""}), 1, -1, true), 0, 1, false));
			equals(CssGrammars.parse("<angle [-90deg,90deg]>"), Named("angle", {min: -90, max: 90, unit: "deg"}));
			equals(CssGrammars.parse("[ a? b? ]! , <x>#{2,}"), Sequence([Required(Sequence([Repeat(Keyword("a"), 0, 1, false), Repeat(Keyword("b"), 0, 1, false)])), Delim(","), Repeat(Named("x", null), 2, -1, true)]));
			equals(CssGrammars.parse("rect( <top>, auto ) | name( )"), One([Func("rect", Sequence([Named("top", null), Delim(","), Keyword("auto")])), Func("name", Sequence([]))]));
			equals(CssGrammars.parse("'[' <custom-ident>* ']' | ( <x> ) | '+' | 'and'"), One([Block("[", Repeat(Named("custom-ident", null), 0, -1, false)), Block("(", Named("x", null)), Delim("+"), Keyword("and")]));
		});
		test("errors", () -> {
			for (bad in ["", "a |", "[ a", "<length", "<x [0,1>", "a{2,1}", "a{", "<'p'", "f( a", "a ]", "<angle [0deg,1s]>"])
				try {
					CssGrammars.parse(bad);
					fail('parsed: $bad');
				} catch (e) {}
		});
		test("a type in its context", () -> {
			equals(CssGrammars.type("rect()", ["clip"]).syntax, "rect( <top>, <right>, <bottom>, <left> )");
			equals(CssGrammars.type("length").syntax, null);
			equals(CssGrammars.type("no-such"), null);
		});
		test("any tree prints to text that parses back to it", () -> property(GRAMMAR, g -> {
			var text = CssGrammars.print(g);
			equals(CssGrammars.print(CssGrammars.parse(text)), text);
			assert(same(CssGrammars.parse(text), g), text);
		}, {cases: 300}));
	});
}

private typedef Definition = {name:String, syntax:String, context:Array<String>}

private function definitions():Array<Definition> {
	var out:Array<Definition> = [for (p in CssData.properties) if (p.syntax != null) {name: p.name, syntax: p.syntax, context: [p.name]}];
	for (t in CssData.types) if (t.syntax != null) out.push({name: '<${t.name}>', syntax: t.syntax, context: t.scope.concat([t.name.charAt(0) == "'" || StringTools.endsWith(t.name, "()") ? t.name : '<${t.name}>'])});
	for (d in CssData.descriptors) if (d.syntax != null) out.push({name: '${d.rule} ${d.name}', syntax: d.syntax, context: [d.rule, d.name]});
	return out;
}

// (`<x>` as "x", `<'p'>` as "'p'")
private function references(g:CssGrammar):Array<String>
	return switch g {
		case Named(name, _): [name];
		case Prop(name): ['\'$name\''];
		case Func(_, x) | Block(_, x) | Repeat(x, _, _, _) | Required(x): references(x);
		case Sequence(xs) | All(xs) | Any(xs) | One(xs): [for (x in xs) for (r in references(x)) r];
		case Keyword(_) | Delim(_): [];
	}

// (enumEq compares the ranges, anonymous structures, by reference)
private function same(a:CssGrammar, b:CssGrammar):Bool
	return switch [a, b] {
		case [Named(x, r), Named(y, s)]: x == y && (r == null ? s == null : s != null && r.min == s.min && r.max == s.max && r.unit == s.unit);
		case [Func(x, g), Func(y, h)] | [Block(x, g), Block(y, h)]: x == y && same(g, h);
		case [Repeat(g, a1, b1, c1), Repeat(h, a2, b2, c2)]: a1 == a2 && b1 == b2 && c1 == c2 && same(g, h);
		case [Required(g), Required(h)]: same(g, h);
		case [Sequence(xs), Sequence(ys)] | [All(xs), All(ys)] | [Any(xs), Any(ys)] | [One(xs), One(ys)]:
			xs.length == ys.length && [for (k in 0...xs.length) same(xs[k], ys[k])].indexOf(false) < 0;
		case _: Type.enumEq(a, b);
	}

private final LEAF:Gen<CssGrammar> = oneOf([
	pick(["auto", "none", "a", "x-start", "JIS-B5", "currentColor"]).map(k -> Keyword(k)),
	pick([",", "/", "+", ":", "<=", "*"]).map(d -> Delim(d)),
	pick(["length", "color", "rgb()", "an+b"]).map(n -> Named(n, null)),
	c -> {
		var min = c.draw(pick([0.0, -1, 0.5, Math.NEGATIVE_INFINITY])), max = c.draw(pick([1.0, 360, Math.POSITIVE_INFINITY]));
		// (a range of two infinities has no unit to write)
		Named("number", {min: min, max: max, unit: Math.isFinite(min) || Math.isFinite(max) ? c.draw(pick(["", "deg"])) : ""});
	},
	pick(["margin-top", "font-size"]).map(p -> Prop(p))
]);

private final GRAMMAR:Gen<CssGrammar> = recursive(LEAF, g -> oneOf([
	array(g, 2, 3).map(xs -> Sequence(xs)),
	array(g, 2, 3).map(xs -> All(xs)),
	array(g, 2, 3).map(xs -> Any(xs)),
	array(g, 2, 3).map(xs -> One(xs)),
	c -> {
		var min = c.draw(int(0, 3)), max = c.draw(pick([-1, 1, 2, 4]));
		Repeat(c.draw(g), min, max != -1 && max < min ? min : max, c.draw(bool()));
	},
	g.map(x -> Required(x)),
	c -> Func(c.draw(pick(["rect", "fit-content"])), c.draw(oneOf([g, constant(Sequence([]))]))),
	c -> Block(c.draw(pick(["[", "("])), c.draw(oneOf([g, constant(Sequence([]))])))
]), 4);
