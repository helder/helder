package helder.css;

import helder.css.CssSheet;
import helder.dom.Dom;
import helder.test.Test;

// Sheets as data (CssSheetData): read back as they were written.
function tests() {
	describe("CssSheetData", () -> {
		test("the user agent's sheets, written and read back alike", () -> {
			for (s in [CssUserAgent.sheet(), CssUserAgent.sheet(true), CssUserAgent.hints(), CssUserAgent.app()]) {
				var data = CssSheetData.encode(s);
				same(CssSheetData.encode(CssSheetData.decode(data)), data);
				equals([for (i in 0...data.length) StringTools.fastCodeAt(data, i)].filter(c -> c < 1 || c > 127), []);
			}
		});
		test("every kind of rule and value", () -> {
			var css = '@import url(x.css) print; @media (min-width: 600px) and (not (hover)) { p { margin: calc(1em + 2px) } }'
				+ '@layer base { a:is(.x, #y)::before { content: "“q”" counter(c) } } @layer one, two;'
				+ 'li:nth-child(2n+1 of .a) > b ~ i + u, [lang|=en i]:not(:hover) { color: rgb(1 2 3 / 50%); --x: { a } }'
				+ '@page :first { margin: 1in; @top-center { content: "t" } } @font-face { font-family: F; src: url(f.woff) }'
				+ '@counter-style c { system: cyclic; symbols: "*" } p { width: var(--w, 10.5px); font-size: -0.25em; z-index: -3 }';
			var s = CssSheet.parse(css, Author);
			var data = CssSheetData.encode(s);
			same(CssSheetData.encode(CssSheetData.decode(data)), data);
		});
		test("a document styled by a sheet read back as by the sheet", () -> {
			var doc = Dom.parse("<!doctype html><h1 id=h>a</h1><p id=p>b <a id=a href=x>c</a></p><ul><li id=li>d</li></ul><table id=t><tr><td id=td>e</table>");
			var parsed = CssCascade.themed(doc, [CssUserAgent.sheet()]);
			var read = CssCascade.themed(doc, [CssSheetData.decode(CssSheetData.encode(CssUserAgent.sheet()))]);
			for (id in ["h", "p", "a", "li", "t", "td"]) for (p in ["display", "font-size", "font-weight", "margin-top", "color", "text-decoration-line", "border-spacing"])
				equals(read.computed(doc.getElementById(id)).text(p), parsed.computed(doc.getElementById(id)).text(p));
		});
	});
}

// (equal, else the first difference and what is around it)
private function same(a:String, b:String) {
	var i = 0;
	while (i < a.length && i < b.length && StringTools.fastCodeAt(a, i) == StringTools.fastCodeAt(b, i)) i++;
	if (i == a.length && i == b.length) return equals(a, b);
	equals(a.substr(i > 40 ? i - 40 : 0, 80), b.substr(i > 40 ? i - 40 : 0, 80));
}
