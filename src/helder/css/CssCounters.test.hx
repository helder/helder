package helder.css;

import helder.css.CssCounters;
import helder.css.CssSheet;
import helder.dom.Dom;
import helder.dom.Element;
import helder.test.Gen;
import helder.test.Test;

// Counter styles (Counter Styles 3: the predefined ones, @counter-style's
// systems and descriptors), counters through a document (Lists 3: scopes,
// list items, ol's start, reversed and li's value, counters()), quotes,
// and the @page cascade (selectors' specificity, margin boxes, size,
// bleed, marks). Then properties: numeric and alphabetic styles are the
// numbers they say, and a list's markers count its items.
function tests() {
	describe("CssCounters", () -> {
		test("predefined styles", () -> {
			var f = new CssCounterStyles();
			equals(f.format(14, "decimal"), "14");
			equals(f.format(-3, "decimal"), "-3");
			equals(f.format(7, "decimal-leading-zero"), "07");
			equals(f.format(1994, "upper-roman"), "MCMXCIV");
			equals(f.format(4000, "lower-roman"), "4000");
			equals(f.format(28, "lower-alpha"), "ab");
			equals(f.format(2, "lower-greek"), "β");
			equals(f.format(1, "armenian"), "Ա");
			equals(f.format(19999, "georgian"), "ჵჰშჟთ");
			equals(f.format(15, "hebrew"), "טו");
			equals(f.format(203, "cjk-decimal"), "二〇三");
			equals(f.format(3, "arabic-indic"), "٣");
			equals(f.marker(2, "disc"), "• ");
			equals(f.marker(2, "decimal"), "2. ");
			equals(f.marker(3, "cjk-earthly-branch"), "寅、");
			equals(f.format(13, "cjk-earthly-branch"), "一三");
			// (the CJK longhands: informal drops the 1 before a marker, Chinese only in 10 to 19, and keeps one zero in a run)
			equals(f.format(11, "japanese-informal"), "十一");
			equals(f.format(1001, "japanese-informal"), "千一");
			equals(f.format(11, "simp-chinese-informal"), "十一");
			equals(f.format(111, "simp-chinese-informal"), "一百一十一");
			equals(f.format(1001, "trad-chinese-informal"), "一千零一");
			equals(f.format(-5, "trad-chinese-formal"), "負伍");
			equals(f.format(10000, "japanese-informal"), "一〇〇〇〇");
			equals(f.format(100, "ethiopic-numeric"), "፻");
			equals(f.format(10000, "ethiopic-numeric"), "፼");
			equals(f.format(12345, "ethiopic-numeric"), "፼፳፫፻፵፭");
			// (predefined names in any case; an unknown one decimal)
			equals(f.format(3, "UPPER-ROMAN"), "III");
			equals(f.format(3, "nope"), "3");
		});
		test("@counter-style", () -> {
			var f = formats("@counter-style a { system: extends upper-roman; range: infinite 5; pad: 3 '*'; }"
				+ "@counter-style b { system: extends decimal; negative: '(' ')'; pad: 3 '0'; }"
				+ "@counter-style c { system: fixed 5; symbols: x y; suffix: ')'; }"
				+ "@counter-style d { system: symbolic; symbols: '*' '†'; }"
				+ "@counter-style e { system: additive; additive-symbols: 3 a, 2 b; }"
				+ "@counter-style f { system: cyclic; symbols: '\\25E6'; prefix: '['; suffix: '] '; }"
				+ "@counter-style g { system: alphabetic; symbols: x; }"
				+ "@counter-style decimal { system: cyclic; symbols: z; }"
				+ "@counter-style lower-roman { system: cyclic; symbols: r; }"
				+ "@counter-style h { system: extends h2; } @counter-style h2 { system: extends h; }");
			equals([for (v in -3...7) f.format(v, "a")].join(" "), "-III -II -*I 0 **I *II III *IV **V 6");
			equals([for (v in -2...3) f.format(v, "b")].join(" "), "(2) (1) 000 001 002");
			equals([for (v in 4...8) f.format(v, "c")].join(" "), "4 x y 7");
			equals(f.marker(5, "c"), "x)");
			equals([for (v in 1...6) f.format(v, "d")].join(" "), "* † ** †† ***");
			// (4 has no representation here: decimal's)
			equals([for (v in 2...6) f.format(v, "e")].join(" "), "b a 4 ab");
			equals(f.marker(9, "f"), "[◦] ");
			// (an alphabetic system needs two symbols: no style; decimal can't be redefined, lower-roman can)
			equals(f.format(3, "g"), "3");
			equals(f.format(3, "decimal"), "3");
			equals(f.format(3, "lower-roman"), "r");
			// (an extends loop: decimal's)
			equals(f.format(4, "h"), "4");
		});
		test("descriptors' syntax", () -> {
			var text = (descriptor:String, value:String) -> CssCounterDescriptors.text(descriptor, Css.values(value));
			equals(text("system", "fixed 100"), "fixed 100");
			equals(text("system", "extends none"), null);
			equals(text("additive-symbols", "\"X\" 1"), "1 \"X\"");
			equals(text("additive-symbols", "1 \"I\", 5 \"V\""), null);
			equals(text("pad", "-1 \"X\""), null);
			equals(text("range", "0 -1"), null);
			equals(text("range", "infinite 0, 5 10"), "infinite 0, 5 10");
			equals(text("prefix", "url(a.png)"), "url(\"a.png\")");
			equals(text("symbols", "ident \"X\""), "ident \"X\"");
			equals(text("symbols", "initial \"X\""), null);
			equals(text("fallback", "none"), null);
		});
		test("lists' hints as their CSS compiles", () -> {
			var doc = Dom.parse('<ol start=3 reversed><li value=-2></ol><ol start=5></ol><ol reversed></ol>');
			inline function of(ds:Null<Array<CssSheet.CssDeclared>>)
				return [for (d in ds ?? []) '${d.property} ${d.id} ${CssValues.serialize(d.property, d.value)} ${d.important}'];
			var ols = doc.getElementsByTagName("ol");
			equals(of(CssHints.lists(cast ols.item(0))), of(CssSheet.attribute("counter-reset: reversed(list-item) 4")));
			equals(of(CssHints.lists(cast ols.item(1))), of(CssSheet.attribute("counter-reset: list-item 4")));
			equals(of(CssHints.lists(cast ols.item(2))), of(CssSheet.attribute("counter-reset: reversed(list-item)")));
			equals(of(CssHints.lists(cast doc.getElementsByTagName("li").item(0))), of(CssSheet.attribute("counter-set: list-item -2")));
		});
		test("lists", () -> {
			var lines = markers('<ol><li>a<li>b<ol><li>c<li>d</ol><li value=7>e<li>f</ol>'
				+ '<ol start=3><li>g<li>h</ol><ol reversed><li>i<li>j<li>k</ol><ol reversed start=10><li>l<li>m</ol>'
				+ '<ul><li>n</ul><ol style="list-style-type: lower-alpha"><li>o<li style="list-style-type: \'→ \'">p</ol>');
			equals(lines.join(" | "), "1. a | 2. b | 1. c | 2. d | 7. e | 8. f | 3. g | 4. h | 3. i | 2. j | 1. k | 10. l | 9. m | • n | a. o | → p");
		});
		test("counters, scopes and quotes", () -> {
			var css = "body { counter-reset: s; } h2 { counter-increment: s; counter-reset: t; } h3 { counter-increment: t; }"
				+ "h2::before { content: counter(s, upper-roman) '. '; } h3::before { content: counters(s, '.') '.' counter(t) ' '; }"
				+ "q::before { content: open-quote; } q::after { content: close-quote; } q { quotes: '«' '»' '‹' '›'; }"
				+ "p::before { content: attr(title) ': '; } .x::before { content: counter(fresh) ' '; }";
			var lines = generated('<h2>A</h2><h3>a</h3><h3>b</h3><h2>B</h2><h3>c</h3><p title=T><q>x <q>y</q></q></p><div class=x>z</div>', css, ["h2", "h3", "p", "div"]);
			equals(lines.join(" | "), "I. A | 1.1 a | 1.2 b | II. B | 2.1 c | T: «x ‹y›» | 0 z");
		});
		test("sibling scopes", () -> {
			// (Lists 3 §4.4.2: a sibling's reset replaces the counter, a child's nests in it)
			var css = "div { counter-reset: c 5; } span { counter-increment: c; } span::before { content: counters(c, '/') ' '; }";
			var lines = generated('<section><div></div><p><span>a</span></p><div></div><p><span>b</span></p><div><p><span>c</span></p><div><p><span>d</span></p></div></div></section>', css, ["p"]);
			equals(lines.join(" | "), "6 a | 6 b | 6 c | 6/6 d");
		});
		test("@page", () -> {
			var doc = Dom.parse('<!doctype html><style>html { font-size: 20px; color: red }'
				+ '@page { margin: 1in; size: A5 landscape; marks: crop; @top-center { content: "T"; } @bottom-right { content: counter(page); color: blue } }'
				+ '@page :first { margin-top: 2in; } @page :left { margin-left: 3in; } @page :first:left { margin-left: 4in; }'
				+ '@page wide { size: 400px 300px; bleed: 1em; margin: 0 } @page :blank { margin: 5px } @page wide:blank { margin: 6px }</style><p>a</p>');
			var s = CssCascade.styles(doc);
			var first = s.pageStyle(0, null, false, false), second = s.pageStyle(1, null, true, false);
			equals(first.style.text("margin-top"), "192px");
			equals(first.style.text("margin-left"), "96px");
			equals(second.style.text("margin-top"), "96px");
			equals(second.style.text("margin-left"), "288px");
			equals(s.pageStyle(0, null, true, false).style.text("margin-left"), "384px");
			// (the page inherits from the root element)
			equals(first.style.text("color"), "rgb(255, 0, 0)");
			equals(Math.round(first.width), 794);
			equals(Math.round(first.height), 559);
			equals(first.crop, true);
			equals(first.bleed, 8.0);
			var wide = s.pageStyle(3, "wide", false, false);
			equals(wide.width, 400.0);
			equals(wide.bleed, 20.0);
			equals(wide.style.text("margin-top"), "0px");
			// (a name over :blank: (1, 0, 0) against (0, 1, 0))
			equals(s.pageStyle(3, "wide", false, true).style.text("margin-top"), "6px");
			equals(s.pageStyle(3, null, false, true).style.text("margin-top"), "5px");
			// (margin boxes: their content, Paged Media 3 §6.2's alignment, the page's inherited properties)
			var top = s.marginBoxStyle(1, null, false, false, "top-center");
			equals(top.text("content"), "\"T\"");
			equals(top.text("text-align"), "center");
			equals(top.text("color"), "rgb(255, 0, 0)");
			var right = s.marginBoxStyle(1, null, false, false, "bottom-right");
			equals(right.text("text-align"), "right");
			equals(right.text("color"), "rgb(0, 0, 255)");
			equals(s.marginBoxStyle(1, null, false, false, "left-top").text("content"), "none");
			equals(s.marginBoxStyle(1, null, false, false, "left-top").text("vertical-align"), "top");
			equals(s.marginBoxStyle(1, null, false, false, "middle"), null);
		});
		test("numeric and alphabetic styles are the numbers they say", () -> property(int(-100000, 100000), v -> {
			var f = new CssCounterStyles();
			equals(f.format(v, "decimal"), Std.string(v));
			// (base 26 read back)
			if (v >= 1) {
				var s = f.format(v, "lower-alpha"), n = 0;
				for (k in 0...s.length) n = n * 26 + (s.charCodeAt(k) - "a".code + 1);
				equals(n, v);
			}
			// (roman's additive symbols sum back, in range)
			if (v >= 1 && v <= 3999) {
				var s = f.format(v, "upper-roman"), total = 0, k = 0;
				var values = ["M" => 1000, "D" => 500, "C" => 100, "L" => 50, "X" => 10, "V" => 5, "I" => 1];
				while (k < s.length) {
					var a = values[s.charAt(k)], b = k + 1 < s.length ? values[s.charAt(k + 1)] : 0;
					total += a < b ? -a : a;
					k++;
				}
				equals(total, v);
			}
		}, {cases: 300}));
		test("a list's markers count its items", () -> property(LISTS, l -> {
			var items = [for (k in 0...l.count) '<li${l.values.exists(k) ? ' value=${l.values[k]}' : ""}>x</li>'].join("");
			var attrs = (l.start != null ? ' start=${l.start}' : "") + (l.reversed ? " reversed" : "");
			var got = markers('<ol$attrs>$items</ol>');
			var n = l.start ?? (l.reversed ? l.count : 1);
			for (k in 0...l.count) {
				if (l.values.exists(k)) n = l.values[k];
				equals(got[k], '$n. x');
				n += l.reversed ? -1 : 1;
			}
		}, {cases: 100}));
		test("GCPM's content parts", () -> {
			var doc = Dom.parse('<!doctype html><style>p::after { content: "a" string(title, last) element(head) leader(dotted) leader("-") target-counter("#t", page) }</style><p id=p>x</p><h1 id=t>T</h1>');
			var styles = CssCascade.styles(doc);
			var counters = new CssCounters(styles);
			var p = doc.getElementById("p");
			counters.enter(p);
			var list = counters.content(p, "after");
			equals(Std.string([for (x in list) switch x {
				case Target(t): 'Target(${t.kind},${t.name},${t.element?.localName})';
				case x: Std.string(x);
			}]), "[Text(a),StringValue(title,last),RunningElement(head,first),Leader(. ),Leader(-),Target(counter,page,h1)]");
		});
		test("string-set evaluated at its element", () -> {
			var doc = Dom.parse('<!doctype html><style>body { counter-reset: h } h2 { counter-increment: h; string-set: title content(), number counter(h, upper-roman) ". " content(text) } h2::before { content: "§" } h3 { string-set: note content(before) "/" content(first-letter) attr(id) } h3::before { content: "(n)" }</style><h2>  One  <i>two</i> </h2><h2>Three</h2><h3 id=x>"Quoted</h3><p>none</p>');
			var styles = CssCascade.styles(doc);
			var counters = new CssCounters(styles);
			var out = [];
			for (el in [for (e in doc.body.children) e]) {
				counters.enter(el);
				for (s in counters.strings(el)) out.push('${s.name}=${s.value}');
				counters.exit(el);
			}
			equals(out.join("|"), "title=One two|number=I. One two|title=Three|number=II. Three|note=(n)/\"Qx");
		});
		test("running elements and bookmarks", () -> {
			var doc = Dom.parse('<!doctype html><style>header { position: running(head) } h2 { bookmark-label: "Part " counter(h) } section { counter-increment: h } .closed { bookmark-state: closed }</style><header id=r>Head</header><h1>Title  one</h1><section><h2 class=closed>A</h2></section><p>p</p>');
			var styles = CssCascade.styles(doc);
			equals(styles.computed(doc.getElementById("r")).running(), "head");
			equals(styles.computed(doc.body).running(), null);
			var counters = new CssCounters(styles);
			var out = [];
			function walk(el:Element) {
				counters.enter(el);
				var b = counters.bookmark(el);
				if (b != null) out.push('${b.level} ${b.label} ${b.open}');
				for (c in [for (e in el.children) e]) walk(c);
				counters.exit(el);
			}
			walk(doc.documentElement);
			equals(out.join("|"), "1 Title one true|2 Part 1 false");
		});
		test("cross-references resolved once the pages are known", () -> {
			var doc = Dom.parse('<!doctype html><style>body { counter-reset: chapter } h1 { counter-increment: chapter } h1::before { content: "Ch. " counter(chapter) } a::after { content: target-counter(attr(href url), page) " " target-counter(attr(href), chapter, upper-roman) " " target-counters(attr(href), chapter, ".") " " target-text(attr(href)) " " target-text(attr(href), before) " " target-text(attr(href), first-letter) " " target-counter("#none", page) }</style><a href="#b">see</a><h1 id=a>Alpha</h1><h1 id=b>Beta</h1>');
			var styles = CssCascade.styles(doc);
			var counters = new CssCounters(styles);
			var link = null;
			function walk(el:Element) {
				counters.enter(el);
				for (p in ["before", "after"]) if (styles.computed(el, p).generated() != null) {
					counters.enter(el, p);
					var c = counters.content(el, p);
					if (el.localName == "a") link = c;
					counters.exit(el, p);
				}
				for (c in [for (e in el.children) e]) walk(c);
				counters.exit(el);
			}
			walk(doc.documentElement);
			function texts()
				return [for (x in link) switch x {
					case Target(t): t.text;
					case Text(t): t;
					case _: "?";
				}].join("");
			// (unresolved until the pages are known)
			equals(texts(), "null null null null null null null");
			counters.resolveTargets(el -> el.getAttribute("id") == "b" ? 7 : 1);
			equals(texts(), "7 II 2 Beta Ch. 2 B ");
		});
	});
}

private final LISTS:Gen<{count:Int, start:Null<Int>, reversed:Bool, values:Map<Int, Int>}> = c -> {
	var count = c.draw(int(1, 12));
	var values = new Map<Int, Int>();
	var start = c.draw(bool()) ? c.draw(int(-50, 50)) : null, reversed = c.draw(bool());
	// (a value in a reversed list without a start: CSS Lists 3's start isn't HTML's ordinal value there)
	if (start != null || !reversed) for (k in 0...count) if (c.draw(int(0, 5)) == 0) values.set(k, c.draw(int(-20, 20)));
	{count: count, start: start, reversed: reversed, values: values};
}

private function formats(css:String):CssCounterStyles {
	var rules = [];
	for (r in CssSheet.parse(css, Author).rules) switch r {
		case CounterStyle(c): rules.push(c);
		case _:
	}
	return new CssCounterStyles(rules);
}

// (each list item's marker and text, in tree order)
private function markers(html:String):Array<String> {
	var doc = Dom.parse('<!doctype html>$html');
	var styles = CssCascade.styles(doc);
	var counters = new CssCounters(styles);
	var out = [];
	function walk(el:Element) {
		counters.enter(el);
		if (styles.computed(el).box.display.listItem) out.push(parts(counters.marker(el)) + el.firstChild.nodeValue);
		var c = el.firstElementChild;
		while (c != null) {
			walk(c);
			c = c.nextElementSibling;
		}
		counters.exit(el);
	}
	walk(doc.documentElement);
	return out;
}

// (each element with text: its ::before, its text and children's, its ::after)
private function generated(html:String, css:String, tags:Array<String>):Array<String> {
	var doc = Dom.parse('<!doctype html><style>$css</style>$html');
	var styles = CssCascade.styles(doc);
	var counters = new CssCounters(styles);
	var lines = [];
	function line(el:Element):String {
		counters.enter(el);
		var out = "";
		for (p in ["before"]) if (styles.computed(el, p).generated() != null) {
			counters.enter(el, p);
			out += parts(counters.content(el, p));
			counters.exit(el, p);
		}
		var n = el.firstChild;
		while (n != null) {
			if (n.nodeType == helder.dom.Node.TEXT_NODE) out += n.nodeValue else if (n.nodeType == helder.dom.Node.ELEMENT_NODE) out += line(cast n);
			n = n.nextSibling;
		}
		if (styles.computed(el, "after").generated() != null) {
			counters.enter(el, "after");
			out += parts(counters.content(el, "after"));
			counters.exit(el, "after");
		}
		counters.exit(el);
		return out;
	}
	function walk(el:Element) {
		if (tags.contains(el.localName)) {
			lines.push(line(el));
			return;
		}
		counters.enter(el);
		var c = el.firstElementChild;
		while (c != null) {
			walk(c);
			c = c.nextElementSibling;
		}
		counters.exit(el);
	}
	walk(doc.documentElement);
	return lines;
}

private function parts(p:Null<Array<CssGeneratedPart>>):String
	return p == null ? "" : [for (x in p) switch x {
		case Text(t): t;
		case _: "";
	}].join("");
