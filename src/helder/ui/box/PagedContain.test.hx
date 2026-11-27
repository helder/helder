package helder.ui.box;

import helder.test.Pages;
import helder.test.Test;

// Containment on pages: layout containment monolithic.
function tests() {
	describe("PagedContain", () -> {
		test("layout containment: monolithic, the next page's whole", () -> {
			var v = paged('<div style="height:40px"></div><div id=a style="contain:layout"><div style="height:30px"></div><div style="height:30px"></div></div>');
			equals(v.layout(), 2);
			equals([on(v, 0, "a"), on(v, 1, "a"), height(v, 1, "a")], [Math.NaN, 0, 60]);
		});
	});
}
