package helder.ui.flow;

import helder.dom.Dom;
import helder.dom.Element;
import helder.test.Test;
import helder.ui.box.DocumentView;
import helder.ui.box.FontMatch;
import helder.ui.box.Fragments;

// Flex layout's steps on small cases (Taffy's fixtures, through the
// box-conformance lane, are its real test): growing and shrinking,
// justify-content and align-items, aspect-ratio, wrapping, a column,
// text an item.
function tests() {
	describe("FlexFlow", () -> {
		test("items grow by their factors, shrink by theirs times their bases", () -> {
			var v = view('<div style="display:flex;width:300px"><div id=a style="width:50px;flex-grow:1"></div><div id=b style="width:50px;flex-grow:3"></div></div>'
				+ '<div style="display:flex;width:100px"><div id=c style="width:100px"></div><div id=d style="width:50px;flex-shrink:2"></div></div>');
			equals([rect(v, "a")[2], rect(v, "b")[2]], [100.0, 200]);
			equals([rect(v, "c")[2], rect(v, "d")[2]], [75.0, 25]);
		});
		test("justify-content and align-items place items in the free space", () -> {
			var v = view('<div style="display:flex;justify-content:space-between;align-items:center;width:100px;height:50px">'
				+ '<div id=a style="width:20px;height:10px"></div><div id=b style="width:20px;height:20px"></div></div>');
			equals(rect(v, "a"), [0.0, 20, 20, 10]);
			equals(rect(v, "b"), [80.0, 15, 20, 20]);
		});
		test("aspect-ratio: a base size from a definite cross size, stretched ones' too", () -> {
			var v = view('<div style="display:flex;align-items:start;width:300px"><div id=a style="height:40px;aspect-ratio:2"></div></div>'
				+ '<div style="display:flex;height:30px"><div id=b style="aspect-ratio:2"></div></div>'
				+ '<div style="display:flex;flex-direction:column;width:100px"><div id=c style="aspect-ratio:2"></div></div>');
			equals(rect(v, "a")[2], 80.0);
			equals(rect(v, "b")[2], 60.0);
			equals(rect(v, "c"), [0.0, 70, 100, 50]);
		});
		test("wrapping: lines as items fit, a column's items stretched", () -> {
			var v = view('<div style="display:flex;flex-wrap:wrap;width:100px"><div id=a style="width:60px;height:10px"></div><div id=b style="width:60px;height:10px"></div></div>'
				+ '<div style="display:flex;flex-direction:column;width:100px"><div id=c style="height:10px"></div></div>');
			equals([rect(v, "a")[1], rect(v, "b")[1]], [0.0, 10]);
			equals(rect(v, "c")[2], 100.0);
		});
		test("text in a flex container: an anonymous item", () -> {
			var v = view('<div id=f style="display:flex;width:200px;align-items:flex-end;height:30px">abc<span id=s style="width:10px;height:10px"></span></div>');
			equals(rect(v, "s"), [30.0, 20, 10, 10]);
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

// (an element's border box in the page: x, y, width, height)
private function rect(v:DocumentView, id:String):Array<Float> {
	var el:Element = v.document.getElementById(id);
	var f = v.fragments;
	for (k in 0...f.count) if (f.kind(k) == Fragments.BOX && f.box(k).node == el && inTree(f, k, v.root)) {
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
