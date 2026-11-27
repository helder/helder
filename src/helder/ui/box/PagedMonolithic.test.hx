package helder.ui.box;

import helder.test.Pages;
import helder.test.Test;

// Monolithic boxes on pages (Fragmentation 3 §4.3): taller than the page
// at its start, kept whole, its overflow continuing on the pages after,
// each one clipped to its area; pushed to the next page first when there
// is content before it. A line taller than the page sliced the same way;
// a formatting context's root going on with its float.
function tests() {
	describe("PagedMonolithic", () -> {
		test("a line taller than the page: its overflow on the pages after, the next block after it", () -> {
			var v = paged('<div id=l><div style="display:inline-block;vertical-align:top;width:20px;height:200px"></div></div><div id=b style="height:10px"></div>');
			equals(v.layout(), 3);
			// (its line in its block: up by what the pages before showed of it)
			var f = v.fragments;
			equals([for (p in 0...3) f.y(f.first(find(v, p, "l")))], [0.0, -80, -160]);
			equals([height(v, 0, "l"), height(v, 1, "l"), height(v, 2, "l"), on(v, 2, "b")], [80.0, 80, 40, 40]);
		});
		test("a formatting context's root whose float goes on: it goes on too, what follows after it", () -> {
			var v = paged('<div style="display:flow-root"><div style="float:left;width:20px"><div style="height:200px"></div></div>x</div><div id=b style="height:10px"></div>');
			equals(v.layout(), 3);
			equals([on(v, 1, "b"), on(v, 2, "b")], [Math.NaN, 40]);
		});
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
