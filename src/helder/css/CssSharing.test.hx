package helder.css;

import helder.css.CssProperty;
import helder.dom.Document;
import helder.dom.Dom;
import helder.dom.Element;
import helder.dom.ElementState;
import helder.test.Gen;
import helder.test.Test;

// The style-sharing cache: what it shares, what it must not, and a
// property: every element's every computed value the same with the cache
// and without it
function tests() {
	describe("shares", () -> {
		test("siblings and cousins of the same kind, before matching", () -> {
			var doc = Dom.parse("<!doctype html><style>li { color: red } .x li { margin-top: 1px }</style><ul class=x><li>a<li>b<li>c</ul><ul class=x><li>d<li>e</ul>");
			var s = CssCascade.styles(doc);
			for (el in all(doc))
				s.computed(el);
			// (the first li matched; its 2 siblings, the second ul and its 2 cousins shared)
			equals(s.shares, 5);
		});
		test("not with an id, a positional rule, another state or a class apart", () -> {
			var doc = Dom.parse("<!doctype html><style>li:first-child { color: red } p + p { color: blue } #a { color: green }</style><ul><li>a<li>b</ul><p>c<p>d<div id=a></div><div id=b></div><span class=a></span><span class=b></span>");
			doc.getElementsByTagName("span").item(1).setState(ElementState.HOVER, true);
			var s = CssCascade.styles(doc);
			for (el in all(doc))
				s.computed(el);
			equals(s.shares, 0);
		});
		test("an id no selector names shares; a link's href by its presence alone", () -> {
			var doc = Dom.parse("<!doctype html><style>#z { color: red } a:link { color: blue }</style><p id=a></p><p id=b></p><a href=x></a><a href=y></a>");
			var s = CssCascade.styles(doc);
			for (el in all(doc))
				s.computed(el);
			equals(s.shares, 2);
		});
		test("cousins whose parents differ in what a rule reads are told apart", () -> {
			// (no ids: an id is never shared; the divs' styles are one object, nothing else telling them apart)
			var doc = Dom.parse("<!doctype html><style>.a p { color: red }</style><div class=a><p></p></div><div class=b><p></p></div>");
			var s = CssCascade.styles(doc), ps = doc.getElementsByTagName("p");
			var divs = doc.getElementsByTagName("div");
			equals(s.computed(cast divs.item(0)) == s.computed(cast divs.item(1)), true);
			equals([s.computed(cast ps.item(0)).text("color"), s.computed(cast ps.item(1)).text("color")], ["rgb(255, 0, 0)", "rgb(0, 0, 0)"]);
		});
	});
	test("every value the same with the cache and without it (random documents and sheets)", () -> property(CASE, c -> {
		var a = Dom.parse(c), b = Dom.parse(c);
		var shared = CssCascade.styles(a), plain = CssCascade.styles(b, {share: false});
		var ea = all(a), eb = all(b);
		for (k in 0...ea.length) {
			var x = shared.computed(ea[k]), y = plain.computed(eb[k]);
			for (p in 0...CssProperties.COUNT) {
				if (CssProperties.logical(cast p)) continue;
				var n = CssProperties.name(cast p);
				if (x.text(n) != y.text(n)) fail('<${ea[k].localName} class=${ea[k].className}> $n: ${x.text(n)} shared, ${y.text(n)} not; $c');
			}
		}
	}, {cases: 300}));
}

private function all(doc:Document):Array<Element>
	return CssMatcher.query(CssSelector.parse("*") ?? [], doc);

// (documents of a few tags, classes and attributes, nested, with a sheet of rules on them)
private final TAGS = ["div", "p", "span", "li", "ul", "a", "input"];
private final CLASSES = ["a", "b"];

private final ELEMENT:Gen<String> = recursive(c -> el(c, ""), inner -> c -> el(c, [for (_ in 0...c.draw(int(0, 4))) c.draw(inner)].join("")), 3);

private function el(c:helder.test.Choices, children:String):String {
	var tag = c.draw(pick(TAGS)), attrs = "";
	if (c.draw(int(0, 4)) == 0) attrs += ' id=i${c.draw(int(0, 3))}';
	if (c.draw(bool())) attrs += ' class="${c.draw(pick(CLASSES))}"';
	if (c.draw(int(0, 3)) == 0) attrs += ' title=${c.draw(pick(["x", "y"]))}';
	if (c.draw(int(0, 4)) == 0) attrs += ' lang=${c.draw(pick(["en", "fr"]))}';
	if (tag == "a" && c.draw(bool())) attrs += ' href=x';
	if (tag == "input" && c.draw(bool())) attrs += c.draw(pick([" type=checkbox checked", " disabled", " required"]));
	if (c.draw(int(0, 5)) == 0) attrs += ' style="margin-left: ${c.draw(int(0, 3))}px"';
	return tag == "input" ? '<input$attrs>' : '<$tag$attrs>$children</$tag>';
}

private final SIMPLE = TAGS.concat([
	"*", ".a", ".b", "#i0", "[title]", "[title=x]", ":lang(en)", ":link", ":first-child", ":last-child", ":nth-child(2n)", ":empty", ":not(.a)",
	":is(p, .b)", ":checked", ":disabled", ":required", ":has(.a)", ":only-child"
]);

private final COMBINATOR = [" ", " > ", " + ", " ~ "];

private final SELECTOR:Gen<String> = c -> {
	var s = c.draw(pick(SIMPLE));
	if (c.draw(bool())) s += c.draw(pick([".a", ".b", "[title]", ":first-child", ":not(.b)"]));
	for (_ in 0...c.draw(int(0, 2)))
		s = s + c.draw(pick(COMBINATOR)) + c.draw(pick(SIMPLE));
	s;
};

private final DECLARATION:Gen<String> = c -> c.draw(pick([
	'color: ${c.draw(pick(["red", "blue", "inherit"]))}', 'margin-top: ${c.draw(int(0, 3))}em', 'display: ${c.draw(pick(["block", "inline", "flex", "none"]))}',
	'font-size: ${c.draw(pick(["12px", "larger", "2em"]))}', 'width: ${c.draw(int(1, 9))}0%', 'padding-left: var(--p, 1px)', '--p: ${c.draw(int(0, 3))}px'
]));

private final CASE:Gen<String> = c -> {
	var rules = [for (_ in 0...c.draw(int(1, 8))) '${c.draw(SELECTOR)} { ${c.draw(DECLARATION)}; ${c.draw(DECLARATION)} }'];
	(c.draw(bool()) ? "<!doctype html>" : "") + '<style>${rules.join("\n")}</style>' + [for (_ in 0...c.draw(int(2, 6))) c.draw(ELEMENT)].join("");
};
