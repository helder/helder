package helder.ui.box;

import helder.dom.Dom;
import helder.test.Test;

// Pages: their size and margins from @page, content broken between
// blocks and lines (forced breaks, a blank page for a side, avoid,
// orphans and widows), margins truncated at a break, a block's border
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

private function height(v:PagedView, page:Int, id:String):Float {
	var k = find(v, page, id);
	return k < 0 ? Math.NaN : v.fragments.height(k);
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
