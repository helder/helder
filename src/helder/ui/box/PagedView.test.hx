package helder.ui.box;

import helder.dom.Dom;
import helder.test.Test;

// Pages: their size and margins from @page, content broken between
// blocks and lines (forced breaks, a blank page for a side, avoid,
// orphans and widows; a float whole, the next page's with its line when
// it doesn't fit), margins truncated at a break, a block's border
// sliced; in Ahem, each line 10px.
function tests() {
	describe("PagedView", () -> {
		test("blocks: a page each that fits, the page area's height", () -> {
			var v = paged('<div id=a style="height:50px"></div><div id=b style="height:50px"></div><div id=c style="height:20px"></div>');
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
			var v = paged('<div id=a style="height:30px"></div><div id=b style="height:30px"></div><div id=c style="height:30px;break-before:avoid"></div>');
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
		test("a float that doesn't fit: the next page's, with its line; the lines there beside it", () -> {
			var v = paged('<div style="height:30px"></div><p id=p style="margin:0;widows:1;orphans:1">x<br>x<br><span id=f style="float:left;width:20px;height:40px"></span>x<br>x</p>');
			equals(v.layout(), 2);
			equals([lineCount(v, 0, "p"), lineCount(v, 1, "p")], [2, 2]);
			equals([on(v, 0, "f"), on(v, 1, "f")], [Math.NaN, 0]);
			equals(lineX(v, 1, "p"), 20.0);
		});
		test("a block-level float that doesn't fit: the next page's, a break before it", () -> {
			var v = paged('<div id=a style="height:50px"></div><div id=f style="float:left;width:20px;height:40px"></div><div id=b>b</div>');
			equals(v.layout(), 2);
			equals([on(v, 1, "f"), on(v, 1, "b")], [0.0, 0]);
		});
		test("a fixed box: on every page, against its page area", () -> {
			var v = paged('<div style="height:60px"></div><div style="height:60px"></div><div id=f style="position:fixed;bottom:0;right:0;width:10px;height:10px"></div><div style="height:60px"></div>');
			equals(v.layout(), 3);
			for (k in 0...3) equals([x(v, k, "f"), on(v, k, "f")], [170.0, 70]);
		});
		test("an absolutely positioned box: in its containing block across pages, broken where it's taller", () -> {
			var v = paged('<div style="position:relative"><div id=a style="position:absolute;bottom:0;width:10px;height:10px"></div><div style="height:60px"></div><div style="height:60px"></div></div>');
			equals(v.layout(), 2);
			// (the containing block 60px on each page: its bottom 50px down the second)
			equals([on(v, 0, "a"), on(v, 1, "a")], [Math.NaN, 50]);
			var t = paged('<div id=b style="position:absolute;top:40px;height:150px;width:10px"></div>x');
			equals(t.layout(), 3);
			equals([on(t, 0, "b"), height(t, 0, "b"), on(t, 1, "b"), height(t, 1, "b"), height(t, 2, "b")], [40.0, 40, 0, 80, 30]);
		});
		test("a column flex container across pages: between its items, the next page's from its top", () -> {
			var v = paged('<div id=c style="display:flex;flex-direction:column;row-gap:5px"><div id=a style="height:30px"></div><div id=b style="height:30px"></div><div id=d style="height:30px"></div></div>');
			equals(v.layout(), 2);
			equals([on(v, 0, "a"), on(v, 0, "b"), on(v, 1, "d")], [0.0, 35, 0]);
			equals([sliced(v, 0, "c"), sliced(v, 1, "c")], ["end", "start"]);
		});
		test("flex lines and grid rows: breaks between them", () -> {
			var items = [for (k in 0...6) '<div id=f$k style="width:50%;height:30px"></div>'].join("");
			var v = paged('<div style="display:flex;flex-wrap:wrap">$items</div>');
			equals(v.layout(), 2);
			equals([on(v, 0, "f3"), on(v, 1, "f4"), on(v, 1, "f5")], [30.0, 0, 0]);
			var cells = [for (k in 0...6) '<div id=g$k style="height:30px"></div>'].join("");
			var g = paged('<div style="display:grid;grid-template-columns:1fr 1fr">$cells</div>');
			equals(g.layout(), 2);
			equals([on(g, 0, "g2"), on(g, 1, "g4")], [30.0, 0]);
		});
		test("a margin collapsing through two parents, an absolutely positioned first child before: the lines' page offset", () -> {
			var lines = [for (k in 0...10) "x"].join("<br>");
			var v = paged('<div style="position:relative"><div style="position:absolute"></div><div><p id=p style="margin:20px 0 0;widows:1;orphans:1">$lines</p></div></div>');
			equals(v.layout(), 2);
			// (20px down the page: 6 lines of 10px before its end)
			equals([lineCount(v, 0, "p"), lineCount(v, 1, "p")], [6, 4]);
		});
		test("a row taller than the page: split inside its cells, each at its own break, a finished one empty after", () -> {
			var lines = [for (k in 0...10) "x"].join("<br>");
			var v = paged('<table style="border-spacing:0"><tr><td id=a style="padding:0;widows:1;orphans:1">$lines</td><td id=b style="padding:0">x</td></tr></table>');
			equals(v.layout(), 2);
			equals([lineCount(v, 0, "a"), lineCount(v, 1, "a"), lineCount(v, 0, "b"), lineCount(v, 1, "b")], [8, 2, 1, 0]);
			// (the row to the page's end, then as tall as its cells' rest)
			equals([height(v, 0, "a"), height(v, 1, "b")], [80.0, 20]);
		});
		test("a collapsed-border table across pages: each page's fragment its own grid, its rows' lines only", () -> {
			var rows = [for (k in 0...12) '<tr><td style="height:10px;padding:0;border:1px solid"></td></tr>'].join("");
			var v = paged('<table id=t style="border-collapse:collapse">$rows</table>');
			equals(v.layout(), 2);
			var shown = [for (p in 0...2) {
				var k = grid(v, p), g = TableGrid.of(v.fragments.box(k).table, k);
				[for (r in 0...12) g.hides(r) ? 0 : 1];
			}];
			equals(shown[0].indexOf(0) > 0 && shown[1][0] == 0 && shown[1][11] == 1, true);
			equals([for (r in 0...12) shown[0][r] + shown[1][r]], [for (_ in 0...12) 1]);
		});
		test("a float taller than the page: broken, its continuation at the next page's top", () -> {
			var v = paged('<div id=f style="float:left;width:20px"><div style="height:60px"></div><div id=g style="height:60px"></div></div>x');
			equals(v.layout(), 2);
			equals([on(v, 0, "f"), height(v, 0, "f"), on(v, 1, "f"), on(v, 1, "g")], [0.0, 80, 0, 0]);
		});
		test("a float that avoids a break, or one forced to the next page: there whole, the floats after it too", () -> {
			var v = paged('<div style="height:40px"></div><div id=a style="float:left;width:20px;height:60px;break-inside:avoid"></div><div id=b style="float:left;clear:left;width:20px;height:10px"></div>');
			equals(v.layout(), 2);
			equals([on(v, 0, "a"), on(v, 1, "a"), on(v, 1, "b")], [Math.NaN, 0, 60]);
			var f = paged('<div style="height:10px"></div><div id=c style="float:left;width:20px;height:10px;break-before:page"></div>');
			equals(f.layout(), 2);
			equals(on(f, 1, "c"), 0.0);
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
			var v = paged('<div id=a style="border:5px solid;box-decoration-break:clone"><div style="height:60px"></div><div style="height:60px"></div></div>');
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
		test("the PDF: bookmarks from headings, links to a URI and to an id", () -> {
			var v = paged('<h1 style="margin:0;font-size:10px">One</h1><p style="margin:0"><a href="#b">to b</a> <a href="https://example.com/">out</a></p><h2 id=b style="break-before:page;margin:0;font-size:10px">Two</h2>');
			var pdf = v.pdf().toString();
			equals([pdf.indexOf("/Outlines") > 0, pdf.indexOf("(One)") > 0, pdf.indexOf("(Two)") > 0], [true, true, true]);
			equals([pdf.indexOf("https://example.com/") > 0, pdf.indexOf("/Dests") > 0 || pdf.indexOf("/D [") > 0 || pdf.indexOf("(b)") > 0], [true, true]);
		});
		test("a table across pages: between rows, its header and footer on each", () -> {
			var rows = [for (k in 0...12) '<tr><td id=r$k style="height:10px;padding:0"></td></tr>'].join("");
			var v = paged('<table style="border-spacing:0"><thead><tr><td id=h style="height:10px;padding:0"></td></tr></thead><tfoot><tr><td id=f style="height:10px;padding:0"></td></tr></tfoot><tbody>$rows</tbody></table>');
			equals(v.layout(), 2);
			// (80px a page: the header, six rows, the footer)
			equals([on(v, 0, "h"), on(v, 0, "r5"), on(v, 0, "f")], [0.0, 60, 70]);
			equals([on(v, 1, "h"), on(v, 1, "r6"), on(v, 1, "r11"), on(v, 1, "f")], [0.0, 10, 60, 70]);
			equals(on(v, 0, "r6"), Math.NaN);
		});
		test("a margin at an unforced break truncated, kept at a forced one", () -> {
			var v = paged('<div style="height:70px"></div><div id=a style="margin-top:20px;height:20px"></div><div id=b style="margin-top:20px;break-before:page">b</div>');
			equals(v.layout(), 3);
			equals([on(v, 1, "a"), on(v, 2, "b")], [0.0, 20]);
		});
		test("a block across pages: its border sliced, its height to the page's end", () -> {
			var v = paged('<div id=a style="border:5px solid"><div style="height:60px"></div><div style="height:60px"></div></div>');
			equals(v.layout(), 2);
			// (broken: to the page's end, as its background)
			equals([height(v, 0, "a"), height(v, 1, "a")], [80.0, 65]);
			equals([sliced(v, 0, "a"), sliced(v, 1, "a")], ["end", "start"]);
		});
	});
}

private function paged(body:String):PagedView {
	var doc = Dom.parse('<!doctype html><style>@page { size: 200px 100px; margin: 10px } body { margin: 0; font: 10px/1 Ahem }</style><body>$body');
	return new PagedView(doc, {fonts: ahem()});
}

private function ahem():FontMatch {
	var f = new FontMatch();
	f.register(sys.io.File.getBytes("tests/flow/fixtures/Ahem.ttf"), "Ahem");
	return f;
}

// (an element's box's fragment on a page: -1 none)
private function find(v:PagedView, page:Int, id:String):Int {
	var el = v.document.getElementById(id), f = v.fragments;
	var stack = [v.pages[page].root];
	while (stack.length > 0) {
		var k = stack.pop();
		if (k < 0) continue;
		if (f.kind(k) == Fragments.BOX && f.box(k).node == el) return k;
		var c = f.first(k);
		while (c >= 0) {
			stack.push(c);
			c = f.next(c);
		}
	}
	return -1;
}

private function on(v:PagedView, page:Int, id:String):Float {
	var k = find(v, page, id);
	return k < 0 ? Math.NaN : v.fragments.absolute(k).y;
}

// (a page's table fragment: the one whose box has a grid)
private function grid(v:PagedView, page:Int):Int {
	var f = v.fragments, stack = [v.pages[page].root];
	while (stack.length > 0) {
		var k = stack.pop();
		if (f.kind(k) == Fragments.BOX && f.box(k).table != null) return k;
		var c = f.first(k);
		while (c >= 0) {
			stack.push(c);
			c = f.next(c);
		}
	}
	return -1;
}

private function x(v:PagedView, page:Int, id:String):Float {
	var k = find(v, page, id);
	return k < 0 ? Math.NaN : v.fragments.absolute(k).x;
}

private function height(v:PagedView, page:Int, id:String):Float {
	var k = find(v, page, id);
	return k < 0 ? Math.NaN : v.fragments.height(k);
}

// (where the first line of an element's box on a page starts its content)
private function lineX(v:PagedView, page:Int, id:String):Float {
	var k = find(v, page, id), f = v.fragments;
	var c = k < 0 ? -1 : f.first(k);
	while (c >= 0 && f.kind(c) != Fragments.LINE) c = f.next(c);
	if (c < 0) return Math.NaN;
	var t = f.first(c);
	return t < 0 ? Math.NaN : f.x(t);
}

private function lineCount(v:PagedView, page:Int, id:String):Int {
	var k = find(v, page, id), f = v.fragments, n = 0;
	var c = k < 0 ? -1 : f.first(k);
	while (c >= 0) {
		if (f.kind(c) == Fragments.LINE) n++;
		c = f.next(c);
	}
	return n;
}

// (the text of a page's margin boxes, or of its content)
private function texts(v:PagedView, page:Int, margins = true):Array<String> {
	var f = v.fragments, out = [];
	function walk(k:Int) {
		if (f.kind(k) == Fragments.TEXT && f.run(k) >= 0) out.push(f.runs[f.run(k)].text);
		var c = f.first(k);
		while (c >= 0) {
			walk(c);
			c = f.next(c);
		}
	}
	if (margins) for (b in v.pages[page].boxes) walk(b) else walk(v.pages[page].root);
	return margins ? [out.join("")] : out;
}

private function sliced(v:PagedView, page:Int, id:String):String {
	var k = find(v, page, id), f = v.fragments;
	return (f.start(k) == Box.NO_START ? "start" : "") + (f.end(k) == Box.NO_END ? "end" : "");
}
