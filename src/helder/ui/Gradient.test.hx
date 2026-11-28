package helder.ui;

import helder.test.Test;

// A box's gradient image: made at the box's pixels, kept while its size
// stays; in a live resize (Ui.live) the last one kept at a new size, drawn
// stretched, the box listed (Ui.stretched) to be made again after it.
function tests() {
	describe("Gradient", () -> {
		test("its image kept in a live resize, made again after it", () -> {
			var ui = new Ui(null, 200, 100), n = new Node();
			n.style = Style.of({width: 80, height: 40, backgroundImage: Gradient.parse("linear-gradient(90deg, #ff0000, #0000ff)")});
			ui.root.append(n);
			ui.update();
			var img = n.backgroundImage(2);
			equals([img.width, img.height], [160, 80]);
			n.style = n.style.with({width: 100});
			ui.update();
			ui.live = true;
			equals(n.backgroundImage(2) == img, true);
			equals(ui.stretched.length, 1);
			ui.live = false;
			var made = n.backgroundImage(2);
			equals([made.width, made.height], [200, 80]);
		});
	});
}
