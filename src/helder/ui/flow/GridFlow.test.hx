package helder.ui.flow;

import helder.dom.Dom;
import helder.dom.Element;
import helder.test.Test;
import helder.ui.box.DocumentView;
import helder.ui.box.FontMatch;
import helder.ui.box.Fragments;

// Grid layout's steps on small cases (Taffy's fixtures, through the
// box-conformance lane, are its real test): fr tracks and gaps,
// auto-placement and spans, named areas and lines, auto-fill and
// auto-fit, fit-content(), alignment in an area, an
// absolutely positioned child in the area its lines give.
function tests() {
	describe("GridFlow", () -> {
		test("fr columns share what fixed ones and gaps leave; items placed in order", () -> {
			var v = view('<div style="display:grid;grid-template-columns:50px 1fr 2fr;column-gap:10px;width:220px"><div id=a></div><div id=b></div><div id=c></div><div id=d style="height:5px"></div></div>');
			equals([rect(v, "a")[2], rect(v, "b")[0], rect(v, "b")[2], rect(v, "c")[0], rect(v, "c")[2]], [50.0, 60, 50, 120, 100]);
			equals(rect(v, "d"), [0.0, 0, 50, 5]);
		});
		test("spans, named areas, and alignment in an area", () -> {
			var v = view('<div style="display:grid;grid-template-columns:40px 40px;grid-template-rows:30px;grid-template-areas:\'x y\';width:80px">'
				+ '<div id=a style="grid-area:y;width:10px;height:10px;justify-self:center;align-self:end"></div>'
				+ '<div id=b style="grid-column:1 / span 2;height:5px"></div></div>');
			equals(rect(v, "a"), [55.0, 20, 10, 10]);
			equals(rect(v, "b"), [0.0, 30, 80, 5]);
		});
		test("named lines, an auto-fill repeat as many times as fit, fit-content() at most its argument", () -> {
			var v = view('<div style="display:grid;grid-template-columns:[a] 20px [b] repeat(auto-fill, 30px [c]) 15px;width:125px">'
				+ '<div id=a style="grid-column:b / 2 c"></div><div id=b style="grid-column:-2"></div></div>'
				+ '<div style="display:grid;grid-template-columns:fit-content(15px) 1fr;width:100px"><div id=c>x x</div></div>');
			equals(rect(v, "a"), [20.0, 0, 60, 0]);
			equals(rect(v, "b"), [110.0, 0, 15, 0]);
			equals(rect(v, "c"), [0.0, 0, 15, 20]);
		});
		test("auto-fit: the empty tracks collapse", () -> {
			var v = view('<div style="display:grid;position:relative;grid-template-columns:repeat(auto-fit, 30px);column-gap:5px;width:100px;height:10px">'
				+ '<div id=a style="grid-column:2"></div><div id=b style="position:absolute;grid-column:1 / -1;left:0;right:0;height:5px"></div></div>');
			equals(rect(v, "a"), [0.0, 0, 30, 10]);
			equals(rect(v, "b")[2], 30.0);
		});
		test("an absolutely positioned child: its lines' area its containing block", () -> {
			var v = view('<div style="display:grid;position:relative;grid-template-columns:30px 30px;grid-template-rows:20px 20px;width:60px">'
				+ '<div id=a style="position:absolute;grid-column:2;grid-row:2;left:0;right:0;top:0;bottom:0"></div></div>');
			equals(rect(v, "a"), [30.0, 20, 30, 20]);
		});
	});
}

private function view(body:String):DocumentView {
	var doc = Dom.parse('<!doctype html><style>body { margin: 0; font: 10px/1 Ahem }</style><body>$body');
	var f = new FontMatch();
	f.register(sys.io.File.getBytes("tests/flow/fixtures/Ahem.ttf"), "Ahem");
	var v = DocumentView.html(doc, {fonts: f});
	v.layout(800, 600);
	return v;
}

private function rect(v:DocumentView, id:String):Array<Float> {
	var el:Element = v.document.getElementById(id);
	var f = v.fragments;
	for (k in 0...f.count) if (f.kind(k) == Fragments.BOX && helder.ui.box.BoxTree.nodeOf(f.box(k)) == el && inTree(f, k, v.root)) {
		var at = f.absolute(k);
		return [at.x, at.y, f.width(k), f.height(k)];
	}
	return [];
}

private function inTree(f:Fragments, k:Int, root:Int):Bool {
	var p = k;
	while (p >= 0) {
		if (p == root) return true;
		p = f.parent(p);
	}
	return false;
}
