package helder.css;

import helder.css.CssSelector;
import helder.test.Gen;
import helder.test.Test;

// helder.css's selectors: parsed, their specificity (Selectors 4's
// examples), printed back; matching is tested against helder.dom
function tests() {
	describe("specificity", () -> {
		test("Selectors 4's examples", () -> equals([
			for (s in ["*", "li", "ul li", "ul ol+li", "h1 + *[rel=up]", "ul ol li.red", "li.red.level", "#x34y", "#s12:not(FOO)", ".foo :is(.bar, #baz)"])
				spec(s)
		], ["(0, 0, 0)", "(0, 0, 1)", "(0, 0, 2)", "(0, 0, 3)", "(0, 1, 1)", "(0, 1, 3)", "(0, 2, 1)", "(1, 0, 0)", "(1, 0, 1)", "(1, 1, 0)"]));
		test(":where() none, :nth-child(of) and :has() their arguments', pseudo-elements a type's", () -> equals([
			for (s in [":where(#a) b", ":nth-child(2n of .a, #b)", "a::before", "a:before", ":has(> #a, .b)", "::slotted(.a)"])
				spec(s)
		], ["(0, 0, 1)", "(1, 1, 0)", "(0, 0, 2)", "(0, 0, 2)", "(1, 0, 0)", "(0, 0, 1)"]));
		test("compared as Ints", () -> {
			var a = require(CssSelector.parse("#a"))[0].specificity, b = require(CssSelector.parse(".a.b.c.d"))[0].specificity;
			assert(a.compare(b) > 0);
		});
	});
	describe("parse", () -> {
		test("compounds and combinators", () -> switch CssSelector.parse("div > p.a ~ *#b + span em") {
			case [s]:
				equals(s.combinators, [Child, SubsequentSibling, NextSibling, Descendant]);
				equals(s.compounds[1], [Type("p", AnyNamespace), Class("a")]);
				equals(s.compounds[2], [Universal(AnyNamespace), Id("b")]);
			case r: fail('$r');
		});
		test("attributes: operators, namespaces, flags", () -> {
			var ns = {prefixes: ["x" => "http://x"]};
			equals(simple('[a="b" i]'), Attribute("a", NoNamespace, Equals, "b", Insensitive));
			equals(simple("[a|=b]"), Attribute("a", NoNamespace, DashMatch, "b", AsDocument));
			equals(simple("[ *|a ^= 'b' s ]"), Attribute("a", AnyNamespace, Prefix, "b", Sensitive));
			equals(require(CssSelector.parse("[x|a$=b]", ns))[0].compounds[0][0], Attribute("a", Uri("http://x"), Suffix, "b", AsDocument));
			equals(CssSelector.parse("[x|a]"), null);
		});
		test("type namespaces: declared prefixes, the default", () -> {
			var ns = {prefixes: ["svg" => "http://www.w3.org/2000/svg"], defaultNamespace: "http://www.w3.org/1999/xhtml"};
			equals(require(CssSelector.parse("svg|rect", ns))[0].compounds[0][0], Type("rect", Uri("http://www.w3.org/2000/svg")));
			equals(require(CssSelector.parse("p", ns))[0].compounds[0][0], Type("p", Uri("http://www.w3.org/1999/xhtml")));
			equals(require(CssSelector.parse("*|p, |p", ns)).map(s -> s.compounds[0][0]), [Type("p", AnyNamespace), Type("p", NoNamespace)]);
			equals(CssSelector.parse("svg|rect"), null);
		});
		test("pseudo-classes and elements", () -> {
			equals(simple(":nth-child(2n+1 of .a)").match(Pseudo(NthChild(_, [_]))), true);
			equals(simple(":LANG(en, '*-CH')"), Pseudo(Lang(["en", "*-CH"])));
			equals(simple(":hover"), Pseudo(Never("hover")));
			equals(require(CssSelector.parse("p::before:hover"))[0].pseudo, Before);
			equals(require(CssSelector.parse("p:first-line"))[0].pseudo, FirstLine);
			equals(require(CssSelector.parse("::footnote-call"))[0].pseudo, FootnoteCall);
		});
		test("invalid: unknown names, misplaced pseudo-elements, nested :has()", () -> equals([
			for (s in [":nope", "::nope", "p::before.a", "p::before span", ":not(::before)", ":not(p::after)", ":has(:has(a))", ":nth-child(of a)", "#1", "a,", "a >", "a | b"])
				CssSelector.parse(s) == null
		], [for (_ in 0...12) true]));
		test(":is() and :where() forgive, :not() does not", () -> {
			equals(require(CssSelector.parse(":is(:nope, a)"))[0].toString(), ":is(a)");
			equals(require(CssSelector.parse(":where(:nope)"))[0].toString(), ":where()");
			equals(CssSelector.parse(":not(:nope, a)"), null);
		});
		test("relative selectors", () -> {
			var l = require(CssSelector.relativeList(Css.values("> a, b, + c")));
			equals(l.map(s -> s.relative), [Child, Descendant, NextSibling]);
		});
		test("printed", () -> equals(require(CssSelector.parse("a.b > #c:not([d~='e' i]) + f::after"))[0].toString(), 'a.b > #c:not([d~="e" i]) + f::after'));
	});
	describe("properties", () -> {
		test("a selector printed parses to the same print", () -> property(SELECTOR, text -> {
			var l = CssSelector.parse(text);
			assume(l != null);
			var printed = SelectorPrinter.list(l);
			var again = CssSelector.parse(printed);
			equals(again == null ? null : SelectorPrinter.list(again), printed);
		}, {cases: 300}));
		test("any text parses or is null, never throws", () -> property(string(char(true), 0, 80), text -> CssSelector.parse(text), {cases: 300}));
	});
}

private function spec(s:String):String
	return Std.string(require(CssSelector.parse(s))[0].specificity);

private function simple(s:String):CssSimple
	return require(CssSelector.parse(s))[0].compounds[0][0];

private final PIECES = [
	"a", "div", "*", "|", "*|", ".x", "#y", "[a]", "[a=b]", "[a~='b c' i]", "[*|a^=b]", ":first-child", ":nth-child(2n+1)", ":nth-child(odd of .x)",
	":not(.x, p)", ":is(a, :nope)", ":where(#y)", ":has(> a)", ":lang(en)", ":hover", "::before", ":after", " ", " > ", " + ", " ~ ", ",", "\\31 x"
];

private final SELECTOR:Gen<String> = array(pick(PIECES), 1, 8).map(a -> a.join(""));
