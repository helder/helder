package studio;

import helder.test.Test;

function tests() {
	describe("Sharp", () -> {
		test("the canvas' pixels a point, in halves, at least 1", () -> {
			var f = [{w: 1280.0, h: 720.0}];
			equals(Sharp.scale(0.1, f), 1.0);
			equals(Sharp.scale(1, f), 1.0);
			equals(Sharp.scale(2.2, f), 2.5);
			equals(Sharp.scale(3, f), 3.0);
		});
		test("bounded: a side, the pixels in all, MOST", () -> {
			equals(Sharp.scale(6, [{w: 1280.0, h: 720.0}]), 3.0);
			equals(Sharp.scale(3, [for (_ in 0...8) {w: 1280.0, h: 720.0}]), 1.5);
			equals(Sharp.scale(9, [{w: 100.0, h: 100.0}]), Sharp.MOST);
			equals(Sharp.scale(3, []), 3.0);
		});
	});
}
