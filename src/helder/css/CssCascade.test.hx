package helder.css;

import helder.css.CssDisplay;
import helder.css.CssKeywords;
import helder.css.CssLength;
import helder.css.CssProperty;
import helder.css.CssSheet;
import helder.dom.Dom;
import helder.dom.Element;
import helder.test.Gen;
import helder.test.Test;

using Lambda;

// The cascade (Cascade 5) on helder.dom's documents: origins and
// importance, the style attribute, layers, specificity and order, the
// CSS-wide keywords, inheritance, var(), @media, @supports, @import,
// pseudo-elements, hints, the at-rules' data, logical properties, the
// typed values and their sharing. Then properties: the result doesn't
// depend on the order sheets come in when their declarations' cascade
// order is the same, an unset inherited property is its parent's
// computed value, and equal groups of values are one object.
function tests() {
	describe("CssCascade", () -> {
		test("origins and importance", () -> {
			var ua = CssSheet.parse("p { color: red; margin-top: 1px !important } div { color: blue }", UserAgent);
			var user = CssSheet.parse("p { color: green; margin-left: 5px !important } div { color: yellow !important }", User);
			var s = styles('<p id=x>a</p><div id=y></div>', "p { color: purple !important; margin-top: 2px !important; margin-left: 6px !important } div { color: black !important }", {userAgent: ua, user: [user]});
			// (author important over author, user and UA normal; UA important over author important; user important over author important)
			equals(text(s, "x", "color"), "rgb(128, 0, 128)");
			equals(text(s, "x", "margin-top"), "1px");
			equals(text(s, "x", "margin-left"), "5px");
			equals(text(s, "y", "color"), "rgb(255, 255, 0)");
		});
		test("specificity, order, the style attribute", () -> {
			var s = styles('<p id=x class=c style="color: green; margin-top: 3px !important">a</p>', "#x { color: red; margin-top: 1px !important } .c { color: blue } p { color: black }");
			equals(text(s, "x", "color"), "rgb(0, 128, 0)");
			equals(text(s, "x", "margin-top"), "3px");
			var t = styles('<p id=x class="a b">a</p>', ".a { color: red } .b { color: blue } .a.b { margin-top: 1px } .b.a { margin-top: 2px }");
			equals(text(t, "x", "color"), "rgb(0, 0, 255)");
			equals(text(t, "x", "margin-top"), "2px");
			// (an author !important beats a style attribute's normal declaration)
			var u = styles('<p id=x style="color: green">a</p>', "p { color: red !important }");
			equals(text(u, "x", "color"), "rgb(255, 0, 0)");
		});
		test("layers", () -> {
			var s = styles('<p id=x>a</p>', "@layer b, a; @layer a { p { color: red; margin-top: 1px !important } } @layer b { #x { color: blue; margin-top: 2px !important } } p { color: green; margin-top: 3px !important }");
			// (normal: unlayered over the last layer over the first; important: the first layer over the rest)
			equals(text(s, "x", "color"), "rgb(0, 128, 0)");
			equals(text(s, "x", "margin-top"), "2px");
			var t = styles('<p id=x>a</p>', "@layer { p { color: red } } @layer { p { color: blue } }");
			equals(text(t, "x", "color"), "rgb(0, 0, 255)");
		});
		test("initial, inherit, unset, revert, revert-layer", () -> {
			var ua = CssSheet.parse("p { margin-top: 7px; color: gray }", UserAgent);
			var s = styles('<div id=d><p id=x>a</p></div>', "div { color: red; margin-top: 4px } p { color: initial; margin-top: revert } @layer a { p { margin-left: 9px } } p { margin-left: revert-layer; margin-bottom: inherit; padding-top: unset }", {userAgent: ua});
			equals(text(s, "x", "color"), "rgb(0, 0, 0)");
			equals(text(s, "x", "margin-top"), "7px");
			equals(text(s, "x", "margin-left"), "9px");
			equals(text(s, "x", "margin-bottom"), "0px");
			equals(text(s, "x", "padding-top"), "0px");
			var t = styles('<div id=d><p id=x>a</p></div>', "div { color: red } p { color: unset }", {userAgent: ua});
			equals(text(t, "x", "color"), "rgb(255, 0, 0)");
		});
		test("inheritance and em", () -> {
			var s = styles('<div id=d><p id=x><b id=b>a</b></p></div>', "div { color: red; font-size: 20px; padding-bottom: 10px } p { font-size: 1.5em; padding-top: 2em } b { width: 2em }");
			equals(text(s, "b", "color"), "rgb(255, 0, 0)");
			equals(text(s, "x", "padding-bottom"), "0px");
			equals(text(s, "x", "font-size"), "30px");
			equals(text(s, "x", "padding-top"), "60px");
			equals(text(s, "b", "width"), "60px");
			equals(text(s, "b", "font-size"), "30px");
		});
		test("var()", () -> {
			var s = styles('<div id=d style="--m: 3px; --c: blue"><p id=x>a</p><p id=y>b</p></div>',
				"p { margin: var(--m) 1px; color: var(--missing, var(--c)); --a: var(--b); --b: var(--a); padding-top: var(--a, 5px) } #y { color: var(--a); width: var(--nope) }");
			equals(text(s, "x", "margin"), "3px 1px");
			equals(text(s, "x", "color"), "rgb(0, 0, 255)");
			equals(text(s, "x", "--m"), "3px");
			// (a cycle: both invalid, so var(--a)'s fallback; a missing name without one: invalid at computed-value time, as unset)
			equals(text(s, "x", "--a"), "");
			equals(text(s, "x", "padding-top"), "5px");
			equals(text(s, "y", "color"), "rgb(0, 0, 0)");
			equals(text(s, "y", "width"), "auto");
		});
		test("@media, @supports, @import", () -> {
			var files = ["http://x/a.css" => "p { padding-right: 1px }", "http://x/c.css" => "p { margin-left: 2px }"];
			var s = styles('<p id=x>a</p>', "@import url(a.css) screen; @import 'c.css' print; @media print { p { color: red } } @media screen { p { color: blue } } @supports (display: grid) { p { padding-top: 1px } } @supports (display: nope) { p { padding-top: 2px } } @media (min-width: 500px) and (orientation: portrait) { p { padding-left: 3px } }",
				{load: url -> files.get(url), url: "http://x/page.html"});
			equals(text(s, "x", "padding-right"), "0px");
			equals(text(s, "x", "margin-left"), "2px");
			equals(text(s, "x", "color"), "rgb(255, 0, 0)");
			equals(text(s, "x", "padding-top"), "1px");
			equals(text(s, "x", "padding-left"), "3px");
		});
		test("widths without a style", () -> {
			// (Borders 4: a width under none or hidden is computed as it is; the used one is 0, layout's; inherit takes it)
			var s = styles('<div style="border-width: 7px"><p id=a>a</p><p id=b>b</p></div>',
				"p { border-width: 5px; outline-width: 4px } #b { border-top-width: inherit; border-top-style: solid }");
			equals(text(s, "a", "border-top-width"), "5px");
			equals(text(s, "a", "outline-width"), "4px");
			equals(text(s, "b", "border-top-width"), "7px");
			var t = styles('<p id=a>a</p>', "");
			equals(text(t, "a", "border-top-width"), "3px");
		});
		test("blockification", () -> {
			var s = styles('<span id=f>a</span><span id=p>b</span><div id=x style="display: inline-flex"><span id=i>c</span><b id=c style="display: contents"><i id=n>d</i></b><em id=t style="display: table-cell">e</em></div><div style="display: grid"><span id=g style="display: inline-table">f</span></div><span id=s style="display: inline list-item; float: left">g</span><span id=r style="position: relative">h</span>',
				"html { display: inline } #f { float: right; display: inline-block } #p { position: absolute; float: left } #x::before { content: 'x' }");
			equals(s.computed(s.document.documentElement).text("display"), "block");
			equals(text(s, "f", "display"), "block");
			equals(text(s, "p", "display"), "block");
			equals(text(s, "p", "float"), "none");
			equals(text(s, "x", "display"), "inline-flex");
			equals(text(s, "i", "display"), "block");
			equals(text(s, "c", "display"), "contents");
			equals(text(s, "n", "display"), "block");
			equals(text(s, "t", "display"), "block");
			equals(text(s, "g", "display"), "table");
			equals(text(s, "s", "display"), "list-item");
			equals(text(s, "r", "display"), "inline");
			equals(s.computed(s.document.getElementById("x"), "before").text("display"), "block");
			var t = styles('<p>a</p>', "html { display: contents }");
			equals(t.computed(t.document.documentElement).text("display"), "block");
		});
		test("larger, smaller, bolder, lighter", () -> {
			var s = styles('<div id=a><p id=b><i id=c>a</i></p></div><div style="font-size: 20px"><p id=d>b</p></div><div style="font-size: 9px"><p id=e>c</p></div><div style="font-size: 48px"><p id=f>d</p></div>',
				"#a { font-size: larger } #b { font-size: larger; width: 1em } #c { font-size: smaller } #d { font-size: larger } #e { font-size: smaller } #f { font-size: larger }");
			// (a step along the table from one of its sizes, else 1.2)
			equals(text(s, "a", "font-size"), "18px");
			equals(text(s, "b", "font-size"), "24px");
			equals(text(s, "b", "width"), "24px");
			equals(text(s, "c", "font-size"), "18px");
			equals(text(s, "d", "font-size"), "24px");
			equals(text(s, "e", "font-size"), "7.5px");
			equals(text(s, "f", "font-size"), "57.6px");
			var weights = [50 => ["400", "50"], 300 => ["400", "100"], 400 => ["700", "100"], 600 => ["900", "400"], 800 => ["900", "700"], 950 => ["950", "700"]];
			for (w => want in weights) {
				var t = styles('<div style="font-weight: $w"><b id=b>a</b><i id=l>b</i></div>', "#b { font-weight: bolder } #l { font-weight: lighter }");
				equals(text(t, "b", "font-weight"), want[0], 'bolder $w');
				equals(text(t, "l", "font-weight"), want[1], 'lighter $w');
			}
			var u = styles('<b id=b>a</b>', "#b { font-weight: bolder }");
			equals(text(u, "b", "font-weight"), "700");
		});
		test("lh, rlh, rem", () -> {
			var s = styles('<div id=d><p id=p>a</p><p id=c>b</p><p id=f>c</p><p id=n>d</p></div>',
				"html { line-height: 20px; font-size: 20px; margin-top: 1rem; padding-top: 1rlh } div { font-size: 10px; line-height: 1.5 } #p { margin-top: 2lh; margin-left: 1rlh; width: calc(1lh + 1px) } #c { line-height: 2lh } #f { font-size: 1lh } #n { line-height: normal; margin-top: 1lh; margin-left: 1rlh }");
			equals(text(s, "p", "margin-top"), "30px");
			equals(text(s, "p", "margin-left"), "20px");
			equals(text(s, "p", "width"), "16px");
			// (in line-height and font-size: the parent's)
			equals(text(s, "c", "line-height"), "30px");
			equals(text(s, "f", "font-size"), "15px");
			// (normal: the font's metrics, not known yet)
			equals(text(s, "n", "margin-top"), "1lh");
			equals(text(s, "n", "margin-left"), "20px");
			// (the root's rem and rlh: its own)
			equals(s.computed(s.document.documentElement).text("margin-top"), "20px");
			equals(s.computed(s.document.documentElement).text("padding-top"), "20px");
			var t = styles('<p>a</p>', "html { font-size: 2rem; line-height: 2rlh }");
			equals(t.computed(t.document.documentElement).text("font-size"), "32px");
			equals(t.computed(t.document.documentElement).text("line-height"), "2rlh");
		});
		test("logical properties", () -> {
			var s = styles('<div id=l><p id=a>a</p></div><div id=r dir=rtl><p id=b>b</p><p id=c style="direction: var(--d)">c</p></div>',
				"p { margin-inline-start: 5px; padding-inline: 1px 2px; inset-block-start: 3px; inline-size: 50%; border-inline-end: 2px solid red; --d: ltr } #a { margin-left: 7px } #b { margin-right: 9px; margin-inline-start: 4px }");
			// (ltr: start is left; a physical declaration after it, more specific, wins)
			equals(text(s, "a", "margin-left"), "7px");
			equals(text(s, "a", "padding-left"), "1px");
			equals(text(s, "a", "padding-right"), "2px");
			equals(text(s, "a", "top"), "3px");
			equals(text(s, "a", "width"), "50%");
			equals(text(s, "a", "border-right-width"), "2px");
			equals(text(s, "a", "margin-inline-start"), "7px");
			// (rtl, inherited: start is right; the logical one after the physical one in a rule wins)
			equals(text(s, "b", "margin-right"), "4px");
			equals(text(s, "b", "padding-right"), "1px");
			equals(text(s, "b", "border-left-width"), "2px");
			equals(text(s, "b", "margin-inline"), "4px 0px");
			// (direction from var(), then the mapping)
			equals(text(s, "c", "margin-left"), "5px");
		});
		test("typed values", () -> {
			var s = styles('<div id=d style="color: rgb(255, 0, 0); font: bold 20px/1.5 Georgia, serif"><p id=p>a</p><span id=s>b</span></div>',
				"p { position: absolute; width: 50%; margin-top: 2em; border-top: 3px solid; opacity: 0.5; z-index: 2; background: url(a.png) no-repeat, linear-gradient(red, blue); counter-reset: x 3 y; display: flex } p::before { content: 'a' counter(x, roman) attr(id) open-quote }");
			var p = s.computed(s.document.getElementById("p"));
			equals(p.position.position == Absolute, true);
			equals(p.length(Width).kind == Percent, true);
			equals(p.resolve(Width, 300), 150.0);
			equals(p.spacing.marginTop.value, 40.0);
			equals(p.px(BorderTopWidth), 3.0);
			equals(p.color(BorderTopColor).r, 1.0);
			equals(p.color(BorderTopColor).g, 0.0);
			equals(p.number(Opacity), 0.5);
			equals(p.position.zIndex, 2.0);
			equals(p.box.display.inner == Flex, true);
			equals(p.box.display.outer == Block, true);
			equals(p.font.fontWeight, 700.0);
			equals(p.fontSize(), 20.0);
			equals(p.lineHeight(), 30.0);
			equals(p.families().join(", "), "Georgia, serif");
			var layers = p.backgrounds();
			equals(layers.length, 2);
			equals(layers[0].repeat.join(" "), "no-repeat no-repeat");
			equals(layers[1].repeat.join(" "), "repeat repeat");
			equals([for (c in p.counters(CounterReset)) '${c.name} ${c.value}'].join(", "), "x 3, y 0");
			equals(Std.string(s.computed(s.document.getElementById("p"), "before").generated()), "[Text(a),Counter(x,roman),Attribute(id),Quote(open-quote)]");
			equals(s.computed(s.document.getElementById("s")).generated(), null);
		});
		test("impact", () -> {
			equals(CssProperties.impact(Width) == Layout, true);
			equals(CssProperties.impact(FontSize) == Text, true);
			equals(CssProperties.impact(LetterSpacing) == Text, true);
			equals(CssProperties.impact(Color) == Paint, true);
			equals(CssProperties.impact(BorderTopWidth) == Layout, true);
			equals(CssProperties.impact(BorderTopColor) == Paint, true);
			equals(CssProperties.impact(Opacity) == Composite, true);
			equals(CssProperties.impact(Translate) == Composite, true);
			equals(CssProperties.impact(Cursor) == None, true);
			// (a logical property's: its physical one's)
			equals(CssProperties.impact(MarginInlineStart) == Layout, true);
			equals(CssProperties.physical(MarginInlineStart, true) == MarginRight, true);
		});
		test("display before blockification", () -> {
			var s = styles('<span id=a style="position: absolute">a</span><span id=b style="float: left; display: inline-flex">b</span><div style="display: flex"><span id=c>c</span></div><span id=d>d</span><div id=e style="position: absolute">e</div><p id=f style="display: block; position: absolute">f</p>', "");
			function of(id:String)
				return s.computed(s.document.getElementById(id));
			var a = of("a"), b = of("b"), c = of("c"), d = of("d"), e = of("e"), f = of("f");
			equals(text(s, "a", "display"), "block");
			equals(a.originalDisplay.outer, Inline);
			equals(CssText.join(b.originalDisplay.terms, CssText.term), "inline-flex");
			equals(b.display.inner, Flex);
			equals(c.originalDisplay.outer, Inline);
			equals(c.display.outer, Block);
			// (nothing blockified, or blockified to itself: display)
			equals(d.originalDisplay == d.display, true);
			equals(e.originalDisplay == e.display, true);
			equals(a.originalDisplay.original == a.originalDisplay, true);
			// (block from inline and block declared: displays, groups and styles apart)
			equals(a.display == f.display, false);
			equals(a.box == f.box, false);
			equals(CssText.join(f.display.terms, CssText.term), "block");
			var root = styles('<p>a</p>', "html { display: contents }");
			var html = root.computed(root.document.documentElement);
			equals(CssText.join(html.display.terms, CssText.term), "block");
			equals(html.originalDisplay.outer, Contents);
		});
		test("whether a pseudo-element's rule matches", () -> {
			var s = styles('<p id=a class=x>a</p><p id=b>b</p><div id=c>c</div>', "p::first-letter { color: red } .x::before { content: 'x' }");
			function has(id:String, name:String)
				return s.hasPseudo(s.document.getElementById(id), name);
			equals(has("a", "first-letter"), true);
			equals(has("b", "first-letter"), true);
			equals(has("c", "first-letter"), false);
			equals(has("a", "before"), true);
			equals(has("b", "before"), false);
			// (a name no sheet has: none)
			equals(has("a", "first-line"), false);
			equals(has("a", "after"), false);
		});
		test("media queries see the medium, viewport units the first page's area", () -> {
			// (a 5in by 3in medium, as WPT's print tests have it; the page 10in square with 2in margins)
			var css = "@page { size: 10in; margin: 2in } div { width: 100vw; height: 50vh } @media (min-width: 4in) and (max-width: 5in) { div { color: green } }";
			var media = {type: "print", width: 480.0, height: 288.0, resolution: 1.0, color: 8};
			var s = styles('<div id=d></div>', css, {media: media});
			equals(text(s, "d", "color"), "rgb(0, 128, 0)");
			equals(text(s, "d", "width"), "576px");
			equals(text(s, "d", "height"), "288px");
			// (page-margin-001's: the page's own margins, 10px 20px 30px 40px, off its size: the UA's A4, WeasyPrint's)
			var m = styles('<div id=d></div>', "@page { margin: 10px 20px 30px 40px } div { width: 100vw; height: 100vh }", {media: media});
			equals(text(m, "d", "width"), "733.701px");
			equals(text(m, "d", "height"), "1082.52px");
			// (size: auto, the printer's: the print medium's page)
			var a = styles('<div id=d></div>', "@page { size: auto; margin: 0 } div { width: 100vw }", {media: media});
			equals(text(a, "d", "width"), "480px");
			// (a viewport given, or a screen's: as it is)
			var g = styles('<div id=d></div>', css, {media: media, viewport: {width: 100, height: 40}});
			equals(text(g, "d", "width"), "100px");
			var screen = styles('<div id=d></div>', css, {media: {type: "screen", width: 300.0, height: 200.0, resolution: 1.0, color: 8}});
			equals(text(screen, "d", "width"), "300px");
		});
		test("values nested deeply kept apart", () -> {
			// (CssIntern's keys once were Std.string's, which elides deep nesting)
			var s = styles('<p id=a style="max-width: stretch(calc(0% + 100px))"></p><p id=b style="max-width: stretch(calc(10% + 50px))"></p>', "");
			equals(text(s, "a", "max-width"), "stretch(calc(0% + 100px))");
			equals(text(s, "b", "max-width"), "stretch(calc(10% + 50px))");
		});
		test("typed reads of values kept as terms", () -> {
			// (text-indent's grammar keeps it as terms: still a length to read, as the box lane does)
			var s = styles('<p id=p>a</p>', "p { text-indent: 2em; font-size: 10px; box-shadow-color: red }");
			var p = s.computed(s.document.getElementById("p"));
			equals(p.length(TextIndent).kind == Px, true);
			equals(p.length(TextIndent).value, 20.0);
			equals(p.resolve(TextIndent, 100), 20.0);
			equals(p.color(BoxShadowColor).r, 1.0);
		});
		test("typed reads by id don't allocate", () -> {
			var s = styles('<p id=p>a</p>', "p { width: 50%; position: absolute; color: red; opacity: 0.5; border-top: 2px solid; float: left }");
			var p = s.computed(s.document.getElementById("p"));
			var n = 0.0;
			// (once first: what a first read makes, lazily, isn't counted)
			function read() {
				n += p.length(Width).value + p.px(BorderTopWidth) + p.number(Opacity) + p.color(BorderTopColor).r;
				if (p.keyword(Position) == "absolute") n++;
				if (p.terms(Float).length == 1) n++;
				if (p.length(MarginInlineStart).kind == Px) n++;
			}
			read();
			var before = hxmc.GcStats.bytesAllocated();
			for (_ in 0...1000) read();
			var after = hxmc.GcStats.bytesAllocated();
			equals(after - before, 0.0, 'allocated ${after - before} bytes in 7,000 reads');
			equals(n > 0, true);
		});
		test("styles and groups shared", () -> {
			var s = styles('<div id=d><p id=a class=x>a</p><p id=b class=x>b</p><p id=c class=y>c</p></div>', ".x { margin-top: 1px } .y { margin-top: 2px } .y { color: red }");
			var a = s.computed(s.document.getElementById("a")), b = s.computed(s.document.getElementById("b")), c = s.computed(s.document.getElementById("c"));
			var d = s.computed(s.document.getElementById("d"));
			// (the same parent and cascade: one style; nothing inherited set: the parent's groups)
			equals(a == b, true);
			equals(a.font == d.font, true);
			equals(a.inheritedText == d.inheritedText, true);
			equals(c.inheritedText == d.inheritedText, false);
			equals(a.spacing == c.spacing, false);
			equals(a.border == c.border, true);
			equals(s.hits + s.shares >= 1, true);
		});
		test("pseudo-elements", () -> {
			var s = styles('<ul><li id=x>a</li></ul>', 'li::before { content: "> "; color: red } li::marker { color: blue } li { color: green }');
			var li = s.document.getElementById("x");
			equals(s.computed(li, "before").text("content"), "\"> \"");
			equals(s.computed(li, "before").text("color"), "rgb(255, 0, 0)");
			equals(s.computed(li, "marker").text("color"), "rgb(0, 0, 255)");
			equals(s.computed(li, "after").text("content"), "none");
			equals(s.computed(li, "marker").text("content"), "normal");
			equals(s.computed(li).text("content"), "normal");
			equals(s.computed(li).text("display"), "list-item");
		});
		test("the user agent's sheet and hints", () -> {
			var s = styles('<h1 id=h>a</h1><table><tr><td id=t bgcolor=red width=50>x</td></tr></table><p hidden id=p>a</p>', "");
			equals(text(s, "h", "font-size"), "32px");
			equals(text(s, "h", "display"), "block");
			equals(text(s, "p", "display"), "none");
			equals(text(s, "t", "background-color"), "rgba(0, 0, 0, 0)");
			var hinted = styles('<table><tr><td id=t bgcolor=red width=50>x</td></tr></table>', "td { width: 10px }", {hints: true});
			equals(text(hinted, "t", "background-color"), "rgb(255, 0, 0)");
			equals(text(hinted, "t", "width"), "10px");
			// (body's margins: its attributes', else 8px; an author's rule over both)
			var body = CssCascade.styles(Dom.parse('<!doctype html><body marginheight=3>'), {hints: true});
			equals(body.computed(body.document.body).text("margin"), "3px 8px");
			var zero = styles('<p>a</p>', "body { margin-top: 0 }", {hints: true});
			equals(zero.computed(zero.document.body).text("margin"), "0px 8px 8px");
		});
		test("at-rules' data", () -> {
			var s = styles('<p>a</p>', "@page :first { margin: 1in; size: A5; @top-center { content: 'x' } } @font-face { font-family: X; src: url(x.woff) } @counter-style thumbs { system: cyclic; symbols: '👍' }");
			var pages = s.pages.filter(p -> p.origin == Author);
			equals(pages.length, 1);
			equals(pages[0].selectors[0].pseudos, ["first"]);
			equals([for (d in pages[0].declarations) d.property].join(" "), "margin-top margin-right margin-bottom margin-left");
			equals(pages[0].descriptors[0].name, "size");
			equals(pages[0].margins.exists("top-center"), true);
			equals(s.fontFaces.length, 1);
			equals(s.counterStyles[0].name, "thumbs");
		});
		test("the result doesn't depend on the sheets' order, their cascade order the same", () -> property(RULES, rules -> {
			var doc = Dom.parse(DOC);
			var a = CssCascade.styles(doc, {author: [for (r in rules) CssSheet.parse(r, Author)]});
			var shuffled = rules.copy();
			shuffled.reverse();
			var b = CssCascade.styles(doc, {author: [for (r in shuffled) CssSheet.parse(r, Author)]});
			for (el in all(doc.documentElement)) for (p in PROPS) equals(b.computed(el).text(p), a.computed(el).text(p), '${el.localName} $p');
		}, {cases: 60}));
		test("equal groups of values are one object, and one object one set of values", () -> property(RULES, rules -> {
			var doc = Dom.parse(DOC);
			var s = CssCascade.styles(doc, {author: [for (r in rules) CssSheet.parse(r, Author)]});
			for (g in 0...CssGroups.COUNT) {
				var byValues = new Map<String, CssGroup>(), byObject = new Map<Int, String>();
				for (el in all(doc.documentElement)) for (pseudo in [null, "before"]) {
					var style = s.computed(el, pseudo);
					var group = @:privateAccess style.group(g);
					var key = [for (p in CssProperties.members[g]) CssIntern.key(group.terms(cast p))].join("|");
					if (byValues.exists(key)) equals(byValues[key] == group, true, '${CssProperties.groups[g]} made twice');
					byValues.set(key, group);
					if (byObject.exists(group.id)) equals(byObject[group.id], key, '${CssProperties.groups[g]} changed');
					byObject.set(group.id, key);
				}
			}
		}, {cases: 40}));
		test("an unset inherited property is its parent's computed value", () -> property(RULES, rules -> {
			var doc = Dom.parse(DOC);
			// (no user agent's sheet: what sets a property is the rules drawn)
			var s = CssCascade.styles(doc, {userAgent: CssSheet.parse("", UserAgent), author: [for (r in rules) CssSheet.parse(r, Author)]});
			for (el in all(doc.documentElement)) {
				var parent = el.parentElement;
				if (parent == null) continue;
				for (p in ["color", "font-size", "line-height", "text-align", "visibility", "letter-spacing"]) {
					var set = rules.exists(r -> r.indexOf('$p:') >= 0);
					if (!set) equals(s.computed(el).text(p), s.computed(parent).text(p), '${el.localName} $p');
				}
			}
		}, {cases: 60}));
	});
}

private final DOC = '<!doctype html><div class="a b" id=d><p class=a id=p><b class=b>x</b><i>y</i></p><ul><li class=b>z</li></ul></div>';
private final PROPS = ["color", "font-size", "margin-top", "padding-left", "width", "text-align", "border-top-width"];

// (rules each of its own specificity, :is() of a selector of that many
// classes, so no two tie: their order can't matter)
private final RULES:Gen<Array<String>> = c -> {
	var n = c.draw(int(1, 6));
	var used = new Map<Int, Bool>();
	[for (k in 0...n) {
		var spec = 0;
		do spec = c.draw(int(0, 30)) while (used.exists(spec));
		used.set(spec, true);
		var target = c.draw(pick(["div", "p", "b", "li", "*", ".a", ".b"]));
		var classes = [for (_ in 0...spec) ".q"].join("");
		var prop = c.draw(pick(["color: red", "color: blue", "font-size: 20px", "font-size: 1.5em", "margin-top: 2em", "padding-left: 3px", "width: 50%", "text-align: center",
			"border-top-width: thick", "font-size: inherit", "color: unset", "margin-top: initial"]));
		var important = c.draw(bool()) ? " !important" : "";
		'$target:not($classes.never-${k}x), $target:where(.zz) { $prop$important }';
	}];
}

private function all(root:Element):Array<Element> {
	var out = [root];
	for (k in 0...root.children.length) for (e in all(root.children.item(k))) out.push(e);
	return out;
}

private function styles(body:String, css:String, ?options:CssCascade.CssCascadeOptions):CssStyles {
	var doc = Dom.parse('<!doctype html><style>$css</style>$body');
	return CssCascade.styles(doc, options);
}

private function text(s:CssStyles, id:String, property:String):String
	return s.computed(s.document.getElementById(id)).text(property);
