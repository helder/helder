package helder.os;

import helder.test.Test;

// A string enum's literal (Literal.of), also one Haxe typed before the
// cast: a ternary's branch in a closure (markup's backdrop={...})
function tests() {
	describe("Literal", () -> {
		test("a literal converts", () -> {
			var b:WindowBackdrop = "sidebar";
			equals(b, Sidebar);
		});
		test("a literal in a closure's ternary converts", () -> {
			var on = [true, false];
			var f:() -> WindowBackdrop = () -> on[0] ? "none" : "sidebar";
			var g:Null<() -> WindowBackdrop> = on[0] ? () -> on[1] ? "none" : "sidebar" : null;
			equals(f(), None);
			equals(g == null ? null : g(), Sidebar);
		});
	});
}
