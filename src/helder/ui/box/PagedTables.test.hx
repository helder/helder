package helder.ui.box;

import helder.test.Pages;
import helder.test.Test;

// Tables across pages: breaks between rows, the header and footer on
// each page; a row taller than the page split inside its cells; a
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
		test("a table across pages: between rows, its header and footer on each", () -> {
			var rows = [for (k in 0...12) '<tr><td id=r$k style="height:10px;padding:0"></td></tr>'].join("");
			var v = paged('<table style="border-spacing:0"><thead><tr><td id=h style="height:10px;padding:0"></td></tr></thead><tfoot><tr><td id=f style="height:10px;padding:0"></td></tr></tfoot><tbody>$rows</tbody></table>');
			equals(v.layout(), 2);
			// (80px a page: the header, six rows, the footer)
			equals([on(v, 0, "h"), on(v, 0, "r5"), on(v, 0, "f")], [0.0, 60, 70]);
			equals([on(v, 1, "h"), on(v, 1, "r6"), on(v, 1, "r11"), on(v, 1, "f")], [0.0, 10, 60, 70]);
			equals(on(v, 0, "r6"), Math.NaN);
		});
	});
}
