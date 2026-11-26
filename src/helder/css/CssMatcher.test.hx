package helder.css;

import helder.css.CssSelector;
import helder.dom.Dom;
import helder.dom.Element;
import helder.test.Test;

// helder.css's matching on helder.dom's trees: Level 4's pseudo-classes,
// HTML's case rules, quirks mode, the form states (WPT's selectors.js,
// tests/css's CssSelectorsCheck, has Level 3's)
function tests() {
	describe("Level 4", () -> {
		var html = '<div id=a><p id=b class=x>1</p><p id=c>2</p><span id=d><em id=e></em></span></div><div id=f><p id=g></p></div><section id=h></section>';
		test(":has() with each combinator", () -> {
			equals(ids(html, "div:has(p)"), ["a", "f"]);
			equals(ids(html, "div:has(> span > em)"), ["a"]);
			equals(ids(html, "p:has(+ p)"), ["b"]);
			equals(ids(html, "p:has(~ span)"), ["b", "c"]);
			equals(ids(html, "div:has(+ section)"), ["f"]);
			equals(ids(html, ":has(> #e)"), ["d"]);
			equals(ids(html, "div:not(:has(span))"), ["f"]);
		});
		test(":is(), :where(), :not() of lists", () -> {
			equals(ids(html, ":is(#b, #e, nope)"), ["b", "e"]);
			equals(ids(html, "div :where(p.x, em)"), ["b", "e"]);
			equals(ids(html, "p:not(.x, #g)"), ["c"]);
			equals(ids(html, ":is(div > p) + p"), ["c"]);
		});
		test(":nth-child(An+B of S), :nth-last-child, of-type", () -> {
			var list = "<ul><li id=1 class=a><li id=2><li id=3 class=a><li id=4 class=a><li id=5></ul>";
			equals(ids(list, ":nth-child(2 of .a)"), ["3"]);
			equals(ids(list, ":nth-last-child(1 of .a)"), ["4"]);
			equals(ids(list, "li:nth-child(odd)"), ["1", "3", "5"]);
			equals(ids(list, "li:nth-last-of-type(-n+2)"), ["4", "5"]);
			equals(ids(list, "li:only-of-type"), []);
		});
	});
	describe("HTML's case rules", () -> {
		test("type selectors and attribute names ASCII case-insensitive in HTML", () -> {
			equals(ids("<p id=a title=x></p><svg><foreignObject id=b></foreignObject></svg>", "P[TITLE]"), ["a"]);
			equals(ids("<svg><foreignObject id=b></foreignObject></svg>", "foreignobject"), []);
			equals(ids("<svg><foreignObject id=b></foreignObject></svg>", "foreignObject"), ["b"]);
		});
		test("HTML's case-insensitive attribute values, the i and s flags", () -> {
			var form = "<input id=a type=CHECKBOX><input id=b name=Box><input id=c name=box>";
			equals(ids(form, "[type=checkbox]"), ["a"]);
			equals(ids(form, "[type=checkbox s]"), []);
			equals(ids(form, "[name=box]"), ["c"]);
			equals(ids(form, "[name=box i]"), ["b", "c"]);
		});
		test("quirks mode: classes and IDs ASCII case-insensitive", () -> {
			equals(ids("<p id=Up class=Big></p>", ".big, #up"), ["Up"]);
			equals(ids("<!doctype html><p id=Up class=Big></p>", ".big"), []);
			equals(ids("<p id=Up class=Big></p>", "p.big"), ["Up"]);
			equals(ids("<p id=Up class=Big></p>", "#UP"), ["Up"]);
		});
		test("namespaces: SVG's elements", () -> {
			var svg = "<svg id=s><rect id=r /></svg><p id=p></p>";
			var ns = {prefixes: ["svg" => "http://www.w3.org/2000/svg"]};
			equals(idsNs(svg, "svg|rect, svg|*", ns), ["s", "r"]);
			equals(idsNs(svg, "|p", ns), []);
		});
	});
	describe("states", () -> {
		test(":disabled, :enabled: a fieldset's descendants but its first legend's, an optgroup's options", () -> {
			var form = "<fieldset id=f disabled><legend><input id=a></legend><input id=b></fieldset><select><optgroup disabled><option id=c></optgroup><option id=d></select>";
			equals(ids(form, ":disabled"), ["f", "b", null, "c"]);
			equals(ids(form, "input:enabled, option:enabled"), ["a", "d"]);
		});
		test(":checked: checkboxes and the select's selected option", () -> {
			equals(ids("<input id=a type=checkbox checked><input id=b type=radio><select><option id=c><option id=d></select>", ":checked"), ["a", "c"]);
			equals(ids("<select><option id=c><option id=d selected></select>", ":checked"), ["d"]);
		});
		test(":lang() by inheritance, wildcards", () -> {
			var doc = '<div lang=de-CH><p id=a></p></div><p id=b lang=en-Latn-US></p><p id=c lang=fr></p>';
			equals(ids(doc, ":lang(de)"), [null, "a"]);
			equals(ids(doc, ':lang("*-CH")'), [null, "a"]);
			equals(ids(doc, ":lang(en-US)"), ["b"]);
			equals(ids(doc, ":lang(fr, en)"), ["b", "c"]);
		});
		test(":empty, :root, :link, :read-write, :placeholder-shown, :defined", () -> {
			var doc = "<p id=a><!-- c --></p><p id=b> </p><a id=c href=x></a><a id=d></a><input id=e placeholder=p><textarea id=f readonly></textarea><x-y id=g></x-y>";
			equals(ids(doc, "p:empty"), ["a"]);
			equals(ids(doc, ":root").length, 1);
			equals(ids(doc, ":link"), ["c"]);
			equals(ids(doc, ":read-write"), ["e"]);
			equals(ids(doc, ":placeholder-shown"), ["e"]);
			equals(ids(doc, "body > :not(:defined)"), ["g"]);
		});
		test("interactive pseudo-classes never match", () -> equals(ids("<a id=a href=x></a>", "a:hover, a:focus, a:visited, a:active"), []));
	});
	test("a selector's pseudo-element is its originating element's to match", () -> {
		var doc = Dom.parse("<p id=a></p>");
		var s = require(CssSelector.parse("p::before"))[0];
		equals([CssMatcher.matches(s, doc.getElementById("a")), s.pseudo == Before], [true, true]);
	});
}

private function ids(html:String, selector:String):Array<Null<String>>
	return idsNs(html, selector, null);

private function idsNs(html:String, selector:String, ns:Null<CssNamespaces>):Array<Null<String>> {
	var doc = Dom.parse(html);
	return [for (e in CssMatcher.query(require(CssSelector.parse(selector, ns)), doc)) e.getAttribute("id")];
}
