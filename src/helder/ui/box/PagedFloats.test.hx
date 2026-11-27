package helder.ui.box;

import helder.test.Pages;
import helder.test.Test;

// Floats across pages: one that doesn't fit the next page's with its
// line, or broken, its continuation at the next page's top; one that
// avoids a break or is forced to the next page there whole, the floats
// after it too.
function tests() {
	describe("PagedFloats", () -> {
		test("a float avoiding a break inside, taller than a page: to the next page whole, broken there where it must", () -> {
			var v = paged('<div style="height:30px"></div><div style="float:left;break-inside:avoid;width:20px"><div id=a style="height:60px"></div><div id=b style="height:60px"></div></div>');
			equals(v.layout(), 3);
			equals([on(v, 0, "a"), on(v, 1, "a"), on(v, 2, "b")], [Math.NaN, 0, 0]);
		});
		test("a float that doesn't fit: broken beside its lines, its rest at the next page's top", () -> {
			var v = paged('<div style="height:30px"></div><p id=p style="margin:0;widows:1;orphans:1">x<br>x<br><span id=f style="float:left;width:20px;height:40px"></span>x<br>x</p>');
			equals(v.layout(), 2);
			equals([lineCount(v, 0, "p"), lineCount(v, 1, "p")], [4, 0]);
			equals([on(v, 0, "f"), height(v, 0, "f"), on(v, 1, "f"), height(v, 1, "f")], [50.0, 30, 0, 10]);
		});
		test("a block-level float that can't break and doesn't fit: the next page's whole, alone", () -> {
			var v = paged('<div id=a style="height:50px"></div><div id=f style="float:left;width:20px;height:40px;overflow:auto"></div><div id=b>b</div>');
			equals(v.layout(), 2);
			equals([on(v, 1, "f"), on(v, 0, "b")], [0.0, 50]);
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
	});
}
