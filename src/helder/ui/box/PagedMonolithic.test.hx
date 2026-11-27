package helder.ui.box;

import helder.test.Pages;
import helder.test.Test;

// Monolithic boxes on pages (Fragmentation 3 §4.3): taller than the page
// at its start, kept whole, its overflow continuing on the pages after,
// each one clipped to its area; pushed to the next page first when there
// is content before it.
function tests() {
	describe("PagedMonolithic", () -> {
		test("a monolithic box taller than the page: sliced, the content after it where it ends", () -> {
			var v = paged('<div id=m style="height:150px;width:10px;overflow:auto"></div><div id=t>x</div>');
			equals(v.layout(), 2);
			equals([on(v, 0, "m"), on(v, 1, "m"), height(v, 1, "m"), on(v, 1, "t")], [0.0, -80, 150, 70]);
			equals(v.fragments.box(find(v, 1, "m")).flags & Box.SLICED != 0, true);
		});
		test("one with content before it: the next page's, sliced from there", () -> {
			var v = paged('<div style="height:10px"></div><div id=m style="height:150px;width:10px;overflow:auto"></div>');
			equals(v.layout(), 3);
			equals([on(v, 0, "m"), on(v, 1, "m"), on(v, 2, "m")], [Math.NaN, 0, -80]);
		});
	});
}
