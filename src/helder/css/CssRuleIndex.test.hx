package helder.css;

import helder.css.CssRuleIndex;
import helder.dom.Dom;
import helder.dom.Element;
import helder.test.Gen;
import helder.test.Test;

using StringTools;

// helder.css's rule index and ancestor Bloom filter: what they match is
// what matching every selector does, in the same order; the filter
// rejects without wrongly rejecting
function tests() {
	describe("index", () -> {
		test("buckets: id, class, tag, attribute, universal", () -> {
			var index = indexOf("#a, .b, p, [title], :first-child, div > .c");
			var doc = Dom.parse("<div id=a class='b c' title=t><p></p></div>");
			var div:Element = cast doc.getElementById("a");
			var out = [];
			index.candidates(div, out);
			equals([for (e in out) e.selector.toString()].join(" | "), "#a | .b | div > .c | [title] | :first-child");
		});
		test("keys ASCII-lowercased: quirks mode's classes and SVG's tags find their rules", () -> {
			var index = indexOf(".Big, foreignObject");
			var doc = Dom.parse("<p class=big></p><svg><foreignObject></foreignObject></svg>");
			equals(names(index, doc), ["p:.Big", "foreignObject:foreignObject"]);
		});
		test("the order added, across buckets", () -> {
			var index = indexOf("p, .a, #b, *");
			equals(names(index, Dom.parse("<!doctype html><p id=b class=a></p>")).filter(s -> s.startsWith("p:")), ["p:p", "p:.a", "p:#b", "p:*"]);
		});
	});
	describe("Bloom filter", () -> {
		test("ancestor hashes: compounds a child or descendant combinator follows", () -> {
			equals(require(CssSelector.parse("#x .y > p.z"))[0].hashes.length, 2);
			equals(require(CssSelector.parse("a + b"))[0].hashes, []);
			equals(require(CssSelector.parse("div a + b"))[0].hashes.length, 1);
			// (the bench's catch: p is a sibling of li's parent, not an ancestor)
			equals(require(CssSelector.parse("p + * > li"))[0].hashes, []);
			equals(require(CssSelector.parse("div > p + * > li"))[0].hashes, [CssHash.of("div")]);
		});
		test("a sibling of an ancestor is not one: p + * > li matches", () -> {
			var index = indexOf("p + * > li");
			equals(names(index, Dom.parse("<!doctype html><p></p><ul><li></li></ul>")), ["li:p + * > li"]);
		});
		test("rejects what cannot match, and counts it", () -> {
			var index = indexOf("nav a, .menu a, #top a, a");
			var doc = Dom.parse("<!doctype html><div><a></a></div><nav><a></a></nav>");
			index.walk(doc, (_, _) -> {});
			equals([index.visited, index.rejected, index.matched], [8, 5, 3]);
		});
		test("pushed and popped: empty again after a walk", () -> {
			var bloom = CssBloom.of(cast Dom.parse("<div class='a b'><p id=c><i></i></p></div>").getElementsByTagName("i").item(0));
			equals(bloom.depth, 4);
			for (_ in 0...4)
				bloom.pop();
			equals([bloom.depth, bloom.mightHave(CssHash.of("div")) ? 1 : 0], [0, 0]);
		});
	});
	test("a walk matches what each selector matches, in order (random documents and sheets)", () -> property(CASE, c -> {
		var doc = Dom.parse(c.html), list = [for (s in c.selectors) {var l = CssSelector.parse(s); if (l != null) for (x in l) x;}];
		var index = new CssRuleIndex<Int>();
		for (k in 0...list.length)
			index.add(list[k], k);
		var got = [];
		index.walk(doc, (el, m) -> got.push([for (e in m) e.value].join(",")));
		var want = [for (el in CssMatcher.query(CssSelector.parse("*"), doc)) [for (k in 0...list.length) if (CssMatcher.matches(list[k], el)) k].join(",")];
		equals(got, want);
	}, {cases: 400}));
}

private function indexOf(sheet:String):CssRuleIndex<String> {
	var index = new CssRuleIndex<String>();
	for (s in require(CssSelector.parse(sheet)))
		index.add(s, s.toString());
	return index;
}

private function names(index:CssRuleIndex<String>, doc:helder.dom.Document):Array<String> {
	var out = [];
	index.walk(doc, (el, m) -> for (e in m) out.push(el.localName + ":" + e.value));
	return out;
}

// (documents of a few tags, ids, classes and attributes, nested; selectors of the same names)
private final TAGS = ["div", "p", "a", "span", "ul", "li"];
private final NAMES = ["x", "y", "Z"];

private final ELEMENT:Gen<String> = recursive(c -> el(c, ""), inner -> c -> el(c, [for (_ in 0...c.draw(int(0, 3))) c.draw(inner)].join("")), 4);

private function el(c:helder.test.Choices, children:String):String {
	var tag = c.draw(pick(TAGS)), attrs = "";
	if (c.draw(bool())) attrs += ' id=${c.draw(pick(NAMES))}';
	if (c.draw(bool())) attrs += ' class="${c.draw(pick(NAMES))} ${c.draw(pick(NAMES))}"';
	if (c.draw(bool())) attrs += ' title=${c.draw(pick(NAMES))}';
	return '<$tag$attrs>$children</$tag>';
}

private final SIMPLE = TAGS.concat(["*", "#x", "#y", ".x", ".y", ".Z", "[title]", "[title=x]", ":first-child", ":not(.x)", ":is(p, .y)"]);
private final COMBINATOR = [" ", " > ", " + ", " ~ "];

private final SELECTOR:Gen<String> = c -> {
	var s = c.draw(pick(SIMPLE));
	for (_ in 0...c.draw(int(0, 3)))
		s = s + c.draw(pick(COMBINATOR)) + c.draw(pick(SIMPLE)) + (c.draw(bool()) ? c.draw(pick(SIMPLE.filter(x -> x.charAt(0) != "*" && TAGS.indexOf(x) < 0))) : "");
	s;
};

private final CASE:Gen<{html:String, selectors:Array<String>}> = c -> {
	html: (c.draw(bool()) ? "<!doctype html>" : "") + [for (_ in 0...c.draw(int(1, 4))) c.draw(ELEMENT)].join(""),
	selectors: c.draw(array(SELECTOR, 1, 20))
};
