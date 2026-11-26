package helder.css;

import helder.css.CssSelector;
import helder.dom.Document;
import helder.dom.Dom;
import helder.dom.Element;
import helder.dom.ElementState;
import helder.dom.Node;
import helder.test.Gen;
import helder.test.Test;

using StringTools;

// helder.css's invalidation: the elements a change marks for restyle are
// at least those whose matched selectors changed (a property against
// matching everything again), and few more in the plain cases
function tests() {
	describe("marks", () -> {
		test("a hover on a row: the row's subtree, not its siblings'", () -> {
			var t = tracked("<div id=r1 class=row><span id=c1></span></div><div id=r2 class=row><span id=c2></span></div>", ".row:hover .cell, .row:hover");
			t.doc.getElementById("r1").setState(ElementState.HOVER, true);
			equals(ids(t.r), ["r1", "c1"]);
		});
		test("a class in the subject: the element alone", () -> {
			var t = tracked("<p id=a></p><p id=b></p>", ".x");
			t.doc.getElementById("a").className = "x";
			equals(ids(t.r), ["a"]);
		});
		test("a class a sibling combinator follows: the later siblings", () -> {
			var t = tracked("<p id=a></p><p id=b></p><p id=c></p>", ".x ~ p");
			t.doc.getElementById("a").className = "x";
			equals(ids(t.r), ["a", "b", "c"]);
		});
		test("a class no selector reads: the element alone (its hints, its style attribute)", () -> {
			var t = tracked("<p id=a><i id=i></i></p>", ".x .y");
			t.doc.getElementById("a").className = "z";
			equals(ids(t.r), ["a"]);
		});
		test("a guard: a state set where the compound's class is not invalidates nothing", () -> {
			var t = tracked("<div id=a class=row><i id=x class=x></i></div>", ".row:focus-within .x");
			t.doc.body.setState(ElementState.FOCUS_WITHIN, true);
			equals(t.r.dirty(), false);
			t.doc.getElementById("a").setState(ElementState.FOCUS_WITHIN, true);
			equals(ids(t.r), ["a", "x"]);
		});
		test("a guard reads the old class too: both of .a.b taken away at once", () -> {
			var t = tracked("<p id=a class='a b'></p><p id=b></p>", ".a.b + p");
			t.doc.getElementById("a").className = "";
			equals(ids(t.r), ["a", "b"]);
		});
		test("inside :has(): the document, conservatively", () -> {
			var t = tracked("<p id=a></p><p id=b></p>", "div:has(.x)");
			t.doc.getElementById("a").className = "x";
			equals(t.r.marked().length, t.doc.getElementsByTagName("*").length);
		});
		test("an inserted subtree is marked; siblings only when a selector counts them", () -> {
			var t = tracked("<ul id=u><li id=a></li></ul>", "li .x");
			var li = t.doc.createElement("li");
			li.id = "n";
			t.doc.getElementById("u").appendChild(li);
			equals(ids(t.r), ["n"]);
			var s = tracked("<ul id=u><li id=a></li></ul>", "li:last-child");
			var li2 = s.doc.createElement("li");
			li2.id = "n";
			s.doc.getElementById("u").appendChild(li2);
			equals(ids(s.r), ["u", "a", "n"]);
		});
		test("detached, nothing is told", () -> {
			var t = tracked("<p id=a></p>", ".x");
			t.r.detach();
			t.doc.getElementById("a").className = "x";
			equals(t.r.dirty(), false);
		});
	});
	describe("state", () -> {
		test(":hover, :focus, :focus-within, :target match the element's state", () -> {
			var doc = Dom.parse("<div id=a><input id=b></div>");
			var a = doc.getElementById("a"), b = doc.getElementById("b");
			b.setState(ElementState.FOCUS | ElementState.FOCUS_VISIBLE, true);
			a.setState(ElementState.FOCUS_WITHIN, true);
			b.setState(ElementState.FOCUS_WITHIN, true);
			equals([for (s in [":focus", ":focus-visible", ":focus-within", ":hover", ":target", ":visited"]) query(doc, s)], ["b", "b", "a b", "", "", ""]);
		});
		test(":checked: a dirty checkedness over the attribute", () -> {
			var doc = Dom.parse("<input id=a type=checkbox checked><input id=b type=checkbox>");
			doc.getElementById("a").setState(ElementState.CHECKED_DIRTY, true);
			doc.getElementById("b").setState(ElementState.CHECKED_DIRTY | ElementState.CHECKED, true);
			equals(query(doc, ":checked"), "b");
		});
		test(":valid and :invalid: a required control with no value", () -> {
			var doc = Dom.parse("<input id=a required><input id=b required value=x><input id=c><textarea id=d required></textarea><select id=e required><option value=''>-</option></select>");
			equals([query(doc, ":invalid"), query(doc, ":valid")], ["a d e", "b c"]);
		});
	});
	test("a change marks every element whose matched selectors changed (random documents, sheets, changes)", () -> property(CASE, c -> {
		var doc = Dom.parse(c.html);
		var list = [];
		for (s in c.selectors) {
			var l = CssSelector.parse(s);
			if (l != null) for (x in l) list.push(x);
		}
		var r = CssRestyle.attach(doc, CssInvalidation.of(list));
		var before = new Map<Element, String>();
		for (el in elements(doc))
			before.set(el, matched(list, el));
		for (m in c.changes)
			change(doc, m);
		for (el in elements(doc)) {
			var was = before.get(el), now = matched(list, el);
			if (was != now) assert(r.isMarked(el), '<${el.localName} id=${el.id} class=${el.className}> matched [$was], now [$now], not marked; after ${c.changes}');
		}
	}, {cases: 1000}));
}

private function tracked(html:String, sheet:String):{doc:Document, r:CssRestyle} {
	var doc = Dom.parse("<!doctype html>" + html);
	return {doc: doc, r: CssRestyle.attach(doc, CssInvalidation.of(require(CssSelector.parse(sheet))))};
}

private function ids(r:CssRestyle):Array<String>
	return [for (el in r.marked()) if (el.id != "") el.id];

private function query(doc:Document, s:String):String
	return [for (el in CssMatcher.query(require(CssSelector.parse(s)), doc)) el.id].join(" ");

private function elements(doc:Document):Array<Element>
	return CssMatcher.query(require(CssSelector.parse("*")), doc);

private function matched(list:Array<CssSelector>, el:Element):String
	return [for (k in 0...list.length) if (CssMatcher.matches(list[k], el)) k].join(",");

// (a change: its kind and numbers that pick an element, a name, a place)
private typedef Change = {kind:Int, a:Int, b:Int, c:Int};

private function change(doc:Document, m:Change) {
	var all = elements(doc), body = doc.body;
	if (all.length == 0 || body == null) return;
	var el = all[m.a % all.length];
	switch m.kind {
		case 0: el.setAttribute("class", CLASSES[m.b % CLASSES.length] + (m.c % 2 == 0 ? "" : " " + CLASSES[m.c % CLASSES.length]));
		case 1: el.removeAttribute("class");
		case 2: el.setAttribute("id", NAMES[m.b % NAMES.length]);
		case 3: if (m.b % 2 == 0) el.setAttribute("title", NAMES[m.c % NAMES.length]) else el.removeAttribute("title");
		case 4: el.setState(STATES[m.b % STATES.length], m.c % 2 == 0);
		case 5:
			// (a new element, before one of el's children or last)
			var n = doc.createElement(TAGS[m.b % TAGS.length]);
			if (m.c % 3 == 0) n.setAttribute("class", CLASSES[m.c % CLASSES.length]);
			var kids = [for (k in el.children) k];
			el.insertBefore(n, kids.length == 0 || m.c % 2 == 0 ? null : kids[m.c % kids.length]);
		case 6: if (el != doc.documentElement && el != body && el != doc.head) el.remove();
		case 7:
			if (m.b % 2 == 0) el.appendChild(doc.createTextNode(m.c % 2 == 0 ? "" : "t")) else {
				var t = el.firstChild;
				if (t != null && t.nodeType == Node.TEXT_NODE) (cast t : helder.dom.Text).data = m.c % 2 == 0 ? "" : "u";
			}
		default:
			var name = FORM[m.b % FORM.length];
			if (m.c % 2 == 0) el.setAttribute(name, name == "type" ? "checkbox" : "") else el.removeAttribute(name);
	}
}

private final TAGS = ["div", "p", "span", "li", "input"];
private final NAMES = ["x", "y"];
private final CLASSES = ["a", "b", "c"];
private final STATES = [ElementState.HOVER, ElementState.FOCUS, ElementState.FOCUS_WITHIN, ElementState.ACTIVE, ElementState.CHECKED | ElementState.CHECKED_DIRTY];
private final FORM = ["checked", "disabled", "required", "value", "type", "lang"];

private final ELEMENT:Gen<String> = recursive(c -> el(c, ""), inner -> c -> el(c, [for (_ in 0...c.draw(int(0, 4))) c.draw(inner)].join("")), 3);

private function el(c:helder.test.Choices, children:String):String {
	var tag = c.draw(pick(TAGS)), attrs = "";
	if (c.draw(bool())) attrs += ' id=${c.draw(pick(NAMES))}';
	if (c.draw(bool())) attrs += ' class="${c.draw(pick(CLASSES))}${c.draw(bool()) ? " " + c.draw(pick(CLASSES)) : ""}"';
	if (c.draw(int(0, 3)) == 0) attrs += ' title=x';
	if (tag == "input" && c.draw(bool())) attrs += ' type=checkbox';
	return tag == "input" ? '<input$attrs>' : '<$tag$attrs>$children</$tag>';
}

private final SIMPLE = TAGS.concat([
	"*", "#x", "#y", ".a", ".b", ".c", "[title]", "[title=x]", ":first-child", ":last-child", ":nth-child(2n)", ":nth-child(1 of .a)", ":empty",
	":not(.a)", ":is(p, .b)", ":hover", ":focus", ":focus-within", ":active", ":checked", ":disabled", ":required", ":invalid", ":lang(en)",
	":where(.c > *)"
]);

private final EXTRA = [".a", ".b", ".c", "#x", ":hover", ":focus-within", ":checked", "[title]", ":first-child", ":not(.b)"];

// (rare: anything inside :has() restyles the whole document, which would pass every case)
private final HAS = [":has(.a)", ":has(> .b)", ":has(+ .c)"];

private final COMBINATOR = [" ", " > ", " + ", " ~ "];

private final SELECTOR:Gen<String> = c -> {
	var one = () -> switch c.draw(int(0, 40)) {
		case 0: c.draw(pick(HAS));
		case k if (k < 20): c.draw(pick(CLASSES.map(x -> "." + x)));
		default: c.draw(pick(SIMPLE));
	};
	// (half the compounds two simple selectors: a tag, class or id with a class, a state, an attribute: the guards)
	var piece = () -> {
		var p = one();
		c.draw(bool()) ? p + c.draw(pick(EXTRA)) : p;
	};
	var s = piece();
	for (_ in 0...c.draw(int(0, 2)))
		s = s + c.draw(pick(COMBINATOR)) + piece();
	s;
};

// (class and state changes most, what a live page does most)
private final CHANGE:Gen<Change> = c -> {
	var k = c.draw(int(0, 15));
	{kind: k < 5 ? 0 : k < 7 ? 4 : k - 7, a: c.draw(int(0, 40)), b: c.draw(int(0, 9)), c: c.draw(int(0, 9))};
};

private final CASE:Gen<{html:String, selectors:Array<String>, changes:Array<Change>}> = c -> {
	html: (c.draw(bool()) ? "<!doctype html>" : "") + [for (_ in 0...c.draw(int(2, 6))) c.draw(ELEMENT)].join(""),
	selectors: c.draw(array(SELECTOR, 1, 6)),
	changes: c.draw(array(CHANGE, 2, 6))
};
