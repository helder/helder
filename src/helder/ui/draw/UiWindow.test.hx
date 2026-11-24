package helder.ui.draw;

import helder.test.Test;
import helder.ui.Color;

// A <Surface>'s background as markup gives it: a string ("#333333")
// parsed, a Color as it is
function tests() {
	describe("UiWindow", () -> {
		test("a background string: the colour it names", () -> {
			equals((@:privateAccess UiWindow.colour("#333333") : Int), (Color.rgb(0x333333) : Int));
			equals((@:privateAccess UiWindow.colour("#7fb8ff") : Int), (Color.rgb(0x7fb8ff) : Int));
		});
		test("a Color as it is", () -> {
			equals((@:privateAccess UiWindow.colour(Color.rgb(0x161618)) : Int), (Color.rgb(0x161618) : Int));
			equals((@:privateAccess UiWindow.colour(0xFFFFFFFF) : Int), 0xFFFFFFFF);
		});
	});
}
