package helder.ui.box;

import helder.test.Pages;
import helder.test.Test;

// Fixed boxes on every page; an absolutely positioned box in its
// containing block across pages, broken where it's taller.
function tests() {
	describe("PagedPositioned", () -> {
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
	});
}
