package helder.ui.box;

import helder.dom.Dom;
import helder.test.Pages;
import helder.test.Test;

// Pages: their size and margins from @page, content broken between
// blocks and lines (forced breaks, a blank page for a side, avoid,
// orphans and widows), lines resumed from their break, margins
// truncated at a break, a block's border sliced or cloned, named pages,
// margin boxes and their running content, the PDF's outline and links.
function tests() {
	describe("PagedView", () -> {
		test("toPdf: an HTML document's PDF in one call", () -> {
			var pdf = PagedView.toPdf('<!doctype html><style>@page { size: 300px 200px; margin: 10px } body { font: 10px Ahem } h1, p { margin: 0 }</style><h1 style="break-after:page">One</h1><p>Two</p>', {fonts: ahem()});
			equals(pdf.getString(0, 5), "%PDF-");
			equals(helder.pdf.Pdf.open(pdf).pages.length, 2);
		});
		test("the PDF in points: A4 595 by 842, a link's rectangle in points", () -> {
			var pdf = PagedView.toPdf('<!doctype html><style>@page { size: A4; margin: 0 } body { margin: 0 }</style><a href="https://example.com/" style="display:block;width:40px;height:20px"></a>');
			var page = helder.pdf.Pdf.open(pdf).pages[0];
			equals([page.width, page.height], [595.0, 842]);
			equals(pdf.toString().indexOf("/Rect [0 827 30 842]") > 0, true);
		});
		// (blocks of a line each of a line-height: whole, a line not broken; an empty block of a height is, as Chromium's)
		test("blocks: a page each that fits, the page area's height", () -> {
			var v = paged('<div id=a style="line-height:50px">a</div><div id=b style="line-height:50px">b</div><div id=c style="line-height:20px">c</div>');
			equals(v.layout(), 2);
			equals([v.pages[0].width, v.pages[0].height, v.pages[0].margins[0]], [200.0, 100, 10]);
			equals([on(v, 0, "a"), on(v, 1, "b"), on(v, 1, "c")], [0.0, 0, 50]);
		});
		test("forced breaks, and a blank page to start on the left side", () -> {
			var v = paged('<div id=a>a</div><div id=b style="break-before:page">b</div><div id=c style="break-before:left">c</div>');
			equals(v.layout(), 4);
			equals(v.pages[2].blank, true);
			equals(on(v, 3, "c"), 0.0);
			equals(on(v, 1, "b"), 0.0);
		});
		test("break-before: avoid takes the break before, a page's worth less full", () -> {
			var v = paged('<div id=a style="line-height:30px">a</div><div id=b style="line-height:30px">b</div><div id=c style="line-height:30px;break-before:avoid">c</div>');
			equals(v.layout(), 2);
			equals([on(v, 1, "b"), on(v, 1, "c")], [0.0, 30]);
		});
		test("lines: as many as fit, then widows on the next page", () -> {
			var lines = [for (k in 0...10) "x"].join("<br>");
			var v = paged('<p id=p style="margin:0;widows:3">$lines</p>');
			equals(v.layout(), 2);
			equals([lineCount(v, 0, "p"), lineCount(v, 1, "p")], [7, 3]);
		});
		test("lines resumed from their break; a block's top padding counted once", () -> {
			var lines = [for (k in 0...10) "x"].join("<br>");
			var v = paged('<p id=p style="margin:0;padding-top:30px;widows:1;orphans:1">$lines</p>');
			equals(v.layout(), 2);
			equals([lineCount(v, 0, "p"), lineCount(v, 1, "p")], [5, 5]);
		});
		test("a margin collapsing through two parents, an absolutely positioned first child before: the lines' page offset", () -> {
			var lines = [for (k in 0...10) "x"].join("<br>");
			var v = paged('<div style="position:relative"><div style="position:absolute"></div><div><p id=p style="margin:20px 0 0;widows:1;orphans:1">$lines</p></div></div>');
			equals(v.layout(), 2);
			// (20px down the page: 6 lines of 10px before its end)
			equals([lineCount(v, 0, "p"), lineCount(v, 1, "p")], [6, 4]);
		});
		test("content starting past the page's end, its margin: on the next page", () -> {
			var v = paged('<div id=a style="margin-top:120px">a</div>');
			equals(v.layout(), 2);
			equals(on(v, 1, "a"), 0.0);
		});
		test("@page border and padding: inside the margins, around the page area", () -> {
			var doc = Dom.parse('<!doctype html><style>@page { size: 200px 100px; margin: 10px; border: 5px solid; padding: 5px }</style>x');
			var v = new PagedView(doc, {fonts: ahem()});
			v.layout();
			equals(v.pages[0].area, [20.0, 20, 160, 60]);
		});
		test("margin boxes: counter(page) and counter(pages), where §6.3 puts them", () -> {
			var v = paged('<style>@page { @bottom-center { content: counter(page) " of " counter(pages) } }</style><div style="height:60px"></div><div style="height:60px"></div>');
			equals(v.layout(), 2);
			equals([texts(v, 0), texts(v, 1)], [["1 of 2"], ["2 of 2"]]);
			var f = v.pages[1].boxes[0];
			// (the bottom margin's height, the width between the corners)
			equals([v.fragments.x(f), v.fragments.y(f), v.fragments.width(f), v.fragments.height(f)], [10.0, 90, 180, 10]);
		});
		test("two boxes along a side share it by their content", () -> {
			var v = paged('<style>@page { font: 10px Ahem; @top-left { content: "aaa" } @top-right { content: "b" } }</style>x');
			v.layout();
			var b = v.pages[0].boxes;
			equals([v.fragments.width(b[0]), v.fragments.width(b[1])], [135.0, 45]);
		});
		test("string-set and string(): a running head, the page's first", () -> {
			var v = paged('<style>h1 { string-set: title content(); break-before: page; margin: 0; font-size: 10px } @page { @top-center { content: string(title) } }</style><h1>One</h1><h1>Two</h1>');
			equals(v.layout(), 2);
			equals([texts(v, 0), texts(v, 1)], [["One"], ["Two"]]);
		});
		test("a running element: out of the flow, in the margin box that names it", () -> {
			var v = paged('<style>header { position: running(head) } @page { @top-left { content: element(head) } }</style><header>head</header><p id=p style="margin:0">body</p>');
			v.layout();
			equals(texts(v, 0), ["head"]);
			equals(on(v, 0, "p"), 0.0);
		});
		test("target-counter() a page, a leader its line's room", () -> {
			var v = paged('<style>a::after { content: leader(".") target-counter(attr(href), page) }</style><p style="margin:0"><a href="#b">B</a></p><div id=b style="break-before:page">b</div>');
			equals(v.layout(), 2);
			var t = texts(v, 0, false).join("");
			equals([t.indexOf("B") >= 0, t.indexOf(".2") >= 0, t.split(".").length > 10], [true, true, true]);
		});
		test("box-decoration-break: clone, each fragment's border whole, room kept for the bottom one", () -> {
			var v = paged('<div id=a style="border:5px solid;box-decoration-break:clone"><div style="line-height:60px">x</div><div style="line-height:60px">x</div></div>');
			equals(v.layout(), 2);
			equals([height(v, 0, "a"), height(v, 1, "a")], [80.0, 70]);
			equals([sliced(v, 0, "a"), sliced(v, 1, "a")], ["", ""]);
		});
		test("named pages: a change of page name a break, each page its @page's size", () -> {
			var v = paged('<style>@page wide { size: 300px 100px }</style><div id=a>a</div><div id=b style="page:wide">b</div><div id=c style="page:wide">c</div>');
			equals(v.layout(), 2);
			equals([v.pages[0].width, v.pages[1].width], [200.0, 300]);
			equals(v.pages[1].name, "wide");
			equals([on(v, 1, "b"), on(v, 1, "c")], [0.0, 10]);
		});
		test("a line's text in the tree's order: a box's own before its children's after it, ::before and ::after, a marker first", () -> {
			var v = paged('<style>.a::after { content: "z" } .b::before { content: "w" }</style><p style="margin:0">v<span class=a>one<b>two</b></span> x<i class=b>y</i></p><ol style="margin:0"><li>five</li></ol>');
			equals(v.layout(), 1);
			equals(texts(v, 0, false), ["v", "one", "two", "z", " x", "w", "y", "1.", "five"]);
		});
		test("a list marker's disc on a page: drawn as its text, read first in the PDF", () -> {
			var v = paged('<ul style="margin:0"><li>five</li></ul>');
			equals(helder.pdf.Pdf.text(helder.pdf.Pdf.open(v.pdf()).pages[0]), "\u2022 five");
		});
		test("the PDF: bookmarks from headings, links to a URI and to an id", () -> {
			var v = paged('<h1 style="margin:0;font-size:10px">One</h1><p style="margin:0"><a href="#b">to b</a> <a href="https://example.com/">out</a></p><h2 id=b style="break-before:page;margin:0;font-size:10px">Two</h2>');
			var pdf = v.pdf().toString();
			equals([pdf.indexOf("/Outlines") > 0, pdf.indexOf("(One)") > 0, pdf.indexOf("(Two)") > 0], [true, true, true]);
			equals([pdf.indexOf("https://example.com/") > 0, pdf.indexOf("/Dests") > 0 || pdf.indexOf("/D [") > 0 || pdf.indexOf("(b)") > 0], [true, true]);
		});
		test("a margin at an unforced break truncated, kept at a forced one", () -> {
			var v = paged('<div style="height:70px"></div><div id=a style="margin-top:20px;height:20px"></div><div id=b style="margin-top:20px;break-before:page">b</div>');
			equals(v.layout(), 3);
			equals([on(v, 1, "a"), on(v, 2, "b")], [0.0, 20]);
		});
		test("a block across pages: its border sliced, its height to the page's end", () -> {
			var v = paged('<div id=a style="border:5px solid"><div style="line-height:60px">x</div><div style="line-height:60px">x</div></div>');
			equals(v.layout(), 2);
			// (broken: to the page's end, as its background)
			equals([height(v, 0, "a"), height(v, 1, "a")], [80.0, 65]);
			equals([sliced(v, 0, "a"), sliced(v, 1, "a")], ["end", "start"]);
		});
	});
}
