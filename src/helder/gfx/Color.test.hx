package helder.gfx;

import helder.test.Test;

function tests() {
	describe("Color", () -> {
		test("a literal parsed when compiled", () -> {
			var c:Color = '#3366ff';
			equals((c : Int), 0xFF3366FF);
			var t:Color = 'transparent';
			equals((t : Int), 0);
		});
		test("another string when run", () -> {
			var s = 'rgb(255 0 0 / 50%)';
			var c:Color = s;
			equals([c.r, c.g, c.b, c.a], [255, 0, 0, 128]);
		});
		test("a token stays a token", () -> {
			var c:Color = 'var(--primary)/50';
			equals(c.isToken, true);
			equals(c.tokenName(), 'primary');
		});
		test("as floats", () -> {
			var v = Color.rgb(0xFF0000).toVec4();
			equals([v.x, v.y, v.z, v.w], [1.0, 0.0, 0.0, 1.0]);
		});
	});
}
