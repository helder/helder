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

private function sliced(v:PagedView, page:Int, id:String):String {
	var k = find(v, page, id), f = v.fragments;
	return (f.start(k) == Box.NO_START ? "start" : "") + (f.end(k) == Box.NO_END ? "end" : "");
}
