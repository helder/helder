package helder.test;

import helder.dom.Dom;
import helder.ui.box.Box;
import helder.ui.box.FontMatch;
import helder.ui.box.Fragments;
import helder.ui.box.PagedView;

// The paged host's tests' pages: a body in Ahem 10px/1 on 200x100 pages
// with 10px margins (an 80px page area, a line each 10px), and what
// they read of an element's box's fragments on a page (NaN: none there).

function paged(body:String):PagedView {
	var doc = Dom.parse('<!doctype html><style>@page { size: 200px 100px; margin: 10px } body { margin: 0; font: 10px/1 Ahem }</style><body>$body');
	return new PagedView(doc, {fonts: ahem()});
}

function ahem():FontMatch {
	var f = new FontMatch();
	f.register(sys.io.File.getBytes("tests/flow/fixtures/Ahem.ttf"), "Ahem");
	return f;
}

// (an element's box's fragment on a page: -1 none)
function find(v:PagedView, page:Int, id:String):Int {
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

function on(v:PagedView, page:Int, id:String):Float {
	var k = find(v, page, id);
	return k < 0 ? Math.NaN : v.fragments.absolute(k).y;
}

// (a page's table fragment: the one whose box has a grid)
function grid(v:PagedView, page:Int):Int {
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

function x(v:PagedView, page:Int, id:String):Float {
	var k = find(v, page, id);
	return k < 0 ? Math.NaN : v.fragments.absolute(k).x;
}

function height(v:PagedView, page:Int, id:String):Float {
	var k = find(v, page, id);
	return k < 0 ? Math.NaN : v.fragments.height(k);
}

// (where the first line of an element's box on a page starts its content)
function lineX(v:PagedView, page:Int, id:String):Float {
	var k = find(v, page, id), f = v.fragments;
	var c = k < 0 ? -1 : f.first(k);
	while (c >= 0 && f.kind(c) != Fragments.LINE) c = f.next(c);
	if (c < 0) return Math.NaN;
	var t = f.first(c);
	return t < 0 ? Math.NaN : f.x(t);
}

function lineCount(v:PagedView, page:Int, id:String):Int {
	var k = find(v, page, id), f = v.fragments, n = 0;
	var c = k < 0 ? -1 : f.first(k);
	while (c >= 0) {
		if (f.kind(c) == Fragments.LINE) n++;
		c = f.next(c);
	}
	return n;
}

// (the text of a page's margin boxes, or of its content)
function texts(v:PagedView, page:Int, margins = true):Array<String> {
	var f = v.fragments, out = [];
	function walk(k:Int) {
		if (f.kind(k) == Fragments.TEXT && f.glyphs(k) != null) out.push(f.glyphs(k).shown());
		var c = f.first(k);
		while (c >= 0) {
			walk(c);
			c = f.next(c);
		}
	}
	if (margins) for (b in v.pages[page].boxes) walk(b) else walk(v.pages[page].root);
	return margins ? [out.join("")] : out;
}

function sliced(v:PagedView, page:Int, id:String):String {
	var k = find(v, page, id), f = v.fragments;
	return (f.start(k) == Box.NO_START ? "start" : "") + (f.end(k) == Box.NO_END ? "end" : "");
}
