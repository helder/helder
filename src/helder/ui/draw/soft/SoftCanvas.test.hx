package helder.ui.draw.soft;

import helder.test.Test;
import helder.gfx.Color;

// The CPU's canvas: a rectangle's pixels, its edge's coverage, a rounded
// clip, an opacity group drawn as one, nothing outside what is drawn
function tests() {
	describe("SoftCanvas", () -> {
		#if (target.name == "hxmc")
		function pixel(c:SoftCanvas, x:Int, y:Int):Int
			return c.frame.pixels.getInt32((y * c.frame.width + x) * 4);

		test("a rectangle: its fill, its half-covered edge", () -> {
			var c = new SoftCanvas();
			c.snap = false;
			c.begin(16, 16, Color.WHITE);
			c.rect(2, 2, 8.5, 8, 0, Color.BLACK, 0, 0);
			equals(pixel(c, 5, 5), 0xFF000000);
			equals(pixel(c, 12, 5), 0xFFFFFFFF);
			// (column 10: half of it, grey)
			var v = pixel(c, 10, 5) & 0xFF;
			assert(v > 120 && v < 136, 'edge $v');
		});

		test("a rounded clip cuts the corner", () -> {
			var c = new SoftCanvas();
			c.begin(16, 16, Color.WHITE);
			c.pushClip(0, 0, 16, 16, 8);
			c.rect(0, 0, 16, 16, 0, Color.BLACK, 0, 0);
			c.popClip();
			equals(pixel(c, 0, 0), 0xFFFFFFFF);
			equals(pixel(c, 8, 8), 0xFF000000);
		});

		test("an opacity group: what overlaps in it not seen through", () -> {
			var c = new SoftCanvas();
			c.groups = true;
			c.begin(16, 16, Color.WHITE);
			c.pushGroup(0.5, 0, 0, 16, 16);
			c.rect(0, 0, 8, 8, 0, Color.BLACK, 0, 0);
			c.rect(0, 0, 8, 8, 0, Color.BLACK, 0, 0);
			c.popOpacity();
			// (black at half over white, once: 128, where each at half would give 64)
			var v = pixel(c, 4, 4) & 0xFF;
			assert(v >= 127 && v <= 128, 'grey $v');
			equals(pixel(c, 12, 12), 0xFFFFFFFF);
		});

		test("bands: a shape across them, painted in order", () -> {
			var c = new SoftCanvas();
			c.snap = false;
			c.begin(64, 100, Color.WHITE);
			c.rect(4, 10, 40, 80, 8, Color.BLACK, 0, 0);
			c.rect(20, 14, 30, 30, 0, Color.rgb(0xFF0000), 0, 0);
			equals(pixel(c, 24, 18), 0xFF0000FF);
			equals(pixel(c, 10, 60), 0xFF000000);
			equals(pixel(c, 60, 60), 0xFFFFFFFF);
			// (a rounded corner: outside it white)
			equals(pixel(c, 4, 10), 0xFFFFFFFF);
		});

		test("a kept frame: only what was damaged drawn, and told", () -> {
			var c = new SoftCanvas();
			c.keep = true;
			var d = new helder.ui.draw.Damage();
			// (the first frame: all of it, whatever was damaged)
			c.begin(16, 16, Color.WHITE);
			d.add(0, 0, 4, 4);
			c.damage(d);
			c.redraw(0);
			c.rect(0, 0, 16, 16, 0, Color.BLACK, 0, 0);
			c.redraw(-1);
			equals(pixel(c, 12, 12), 0xFF000000);
			equals(c.regions, null);
			// (then the rectangle alone)
			c.begin(16, 16, Color.WHITE);
			d.clear();
			d.add(0, 0, 4, 4);
			c.damage(d);
			c.redraw(0);
			c.rect(0, 0, 16, 16, 0, Color.rgb(0xFF0000), 0, 0);
			c.redraw(-1);
			equals(pixel(c, 2, 2), 0xFF0000FF);
			equals(pixel(c, 12, 12), 0xFF000000);
			equals(c.regions.join(","), "0,0,4,4");
		});

		test("a group past a megabyte, frame after frame", () -> {
			var c = new SoftCanvas();
			c.groups = true;
			for (_ in 0...3) {
				c.begin(700, 500, Color.WHITE);
				c.pushGroup(0.5, 0, 0, 700, 500);
				c.rect(0, 0, 700, 500, 0, Color.BLACK, 0, 0);
				c.rect(0, 0, 700, 500, 0, Color.BLACK, 0, 0);
				c.popOpacity();
				var v = pixel(c, 350, 499) & 0xFF;
				assert(v >= 127 && v <= 128, 'grey $v');
			}
		});
		#end
	});
}
