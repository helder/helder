package helder.ui.box;

import helder.test.Pages;
import helder.test.Test;

// Flex and grid containers across pages: breaks between a column's
// items, flex lines and grid rows; a line's items broken side by side.
function tests() {
	describe("PagedFlex", () -> {
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
		test("a flex line's items broken side by side: one that can't break pushed alone, another broken inside", () -> {
			var v = paged('<div style="display:flex;align-items:flex-start"><div id=a style="width:20px;height:40px"></div>'
				+ '<div id=b style="width:20px;margin-top:50px;height:40px;overflow:auto"></div>'
				+ '<div id=c style="width:20px"><div style="height:60px"></div><div id=d style="height:60px"></div></div></div>');
			equals(v.layout(), 2);
			equals([on(v, 0, "a"), on(v, 0, "c"), on(v, 0, "b")], [0.0, 0, Math.NaN]);
			equals([on(v, 1, "b"), on(v, 1, "d"), on(v, 1, "a")], [0.0, 0, Math.NaN]);
		});
	});
}
