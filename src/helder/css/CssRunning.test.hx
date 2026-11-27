package helder.css;

import helder.test.Test;

// Named strings on pages (GCPM 3 §1.2): first, start, last, first-except.
function tests() {
	describe("CssRunning", () -> {
		test("a page's values and the entry value", () -> {
			var r = new CssRunning<String>();
			r.page();
			equals(r.value("t"), null);
			r.assign("t", "A", true);
			r.assign("t", "B");
			equals([for (w in ["first", "start", "last", "first-except"]) r.value("t", w)], ["A", "A", "B", null]);
			r.page();
			equals([for (w in ["first", "start", "last", "first-except"]) r.value("t", w)], ["B", "B", "B", "B"]);
			r.assign("t", "C");
			equals([for (w in ["first", "start", "last", "first-except"]) r.value("t", w)], ["C", "B", "C", null]);
		});
	});
}
