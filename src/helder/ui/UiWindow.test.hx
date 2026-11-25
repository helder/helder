package helder.ui;

import helder.test.Test;
import helder.gfx.Color;
import helder.ui.UiWindow.SurfaceProps;

// A <Surface>'s background as markup gives it: a string ("#333333")
// parsed, a Color as it is
function tests() {
	describe("UiWindow", () -> {
		test("a background string: the colour it names", () -> {
			var p:SurfaceProps = {background: "#333333"};
			equals((p.background() : Int), (Color.rgb(0x333333) : Int));
		});
		test("transparent: a background clear, or of an alpha", () -> {
			var p:SurfaceProps = {background: "transparent"}, q:SurfaceProps = {background: "#00000080"};
			equals([p.background().a, q.background().a], [0, 128]);
		});
		test("a Color as it is", () -> {
			var p:SurfaceProps = {background: Color.rgb(0x161618)};
			equals((p.background() : Int), (Color.rgb(0x161618) : Int));
		});
	});
}
