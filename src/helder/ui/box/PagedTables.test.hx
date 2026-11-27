package helder.ui.box;

import helder.test.Pages;
import helder.test.Test;

// Tables across pages: breaks between rows, the header and footer on
// each page; a row taller than the page split inside its cells; its
// border, padding and spacing at a break sliced or cloned; a
// collapsed-border table's grid per page.
function tests() {
	describe("PagedTables", () -> {
		test("a row taller than the page: split inside its cells, each at its own break, a finished one empty after", () -> {
			var lines = [for (k in 0...10) "x"].join("<br>");
			var v = paged('<table style="border-spacing:0"><tr><td id=a style="padding:0;widows:1;orphans:1">$lines</td><td id=b style="padding:0">x</td></tr></table>');
			equals(v.layout(), 2);
			equals([lineCount(v, 0, "a"), lineCount(v, 1, "a"), lineCount(v, 0, "b"), lineCount(v, 1, "b")], [8, 2, 1, 0]);
			// (the row to the page's end, then as tall as its cells' rest)
			equals([height(v, 0, "a"), height(v, 1, "b")], [80.0, 20]);
		});
		test("a collapsed-border table across pages: each page's fragment its own grid, its rows' lines only", () -> {
			var rows = [for (k in 0...12) '<tr><td style="padding:0;border:1px solid">x</td></tr>'].join("");
			var v = paged('<table id=t style="border-collapse:collapse">$rows</table>');
			equals(v.layout(), 2);
			var shown = [for (p in 0...2) {
				var k = grid(v, p), g = TableGrid.of(v.fragments.box(k).table, k);
				[for (r in 0...12) g.hides(r) ? 0 : 1];
			}];
			equals(shown[0].indexOf(0) > 0 && shown[1][0] == 0 && shown[1][11] == 1, true);
			equals([for (r in 0...12) shown[0][r] + shown[1][r]], [for (_ in 0...12) 1]);
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
		test("a table broken: its border, padding and spacing sliced, to the page's end; cloned: whole on each page", () -> {
			// (a line each, of 20px: rows that don't break)
			var rows = [for (k in 0...6) '<tr><td id=r$k style="line-height:20px;padding:0">x</td></tr>'].join("");
			var v = paged('<table style="border:5px solid;padding:5px;border-spacing:0 5px">$rows</table>');
			equals(v.layout(), 3);
			// (the rows 15 down the first page, at the top of the next: their edges and spacing above there sliced)
			equals([on(v, 0, "r0"), on(v, 1, "r2"), on(v, 2, "r5")], [15.0, 0, 0]);
			equals([for (p in 0...3) edges(v, p)], ["end", "startend", "start"]);
			equals(v.fragments.height(grid(v, 0)), 80.0);
			var c = paged('<table style="border:5px solid;padding:5px;border-spacing:0 5px;box-decoration-break:clone">$rows</table>');
			equals(c.layout(), 3);
			// (its border and padding again, its spacing not)
			equals([on(c, 1, "r2"), on(c, 2, "r4")], [10.0, 10]);
			equals([for (p in 0...3) edges(c, p)], ["", "", ""]);
		});
	});
}

// (the table box's fragment on a page: its sliced edges)
private function edges(v:PagedView, page:Int):String {
	var k = grid(v, page), f = v.fragments;
	return (f.start(k) == Box.NO_START ? "start" : "") + (f.end(k) == Box.NO_END ? "end" : "");
}
