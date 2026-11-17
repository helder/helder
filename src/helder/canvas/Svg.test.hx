package helder.canvas;

import helder.test.Test;

// Svg.parse of a constant read when compiled (SvgBuild: the shapes made
// again, no parser in the program) draws as Svg.read of the same text, its
// gradients, dashes, clips and transforms included; anything else read
// when the program runs
function tests() {
	describe("Svg", () -> {
		test("parse of a constant: as read draws it", () -> {
			var built = Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 40">'
				+ '<defs><linearGradient id="g" x1="0" x2="1"><stop offset="0" stop-color="#f00"/><stop offset="1" stop-color="#00f" stop-opacity="0.5"/></linearGradient>'
				+ '<clipPath id="c"><circle cx="20" cy="20" r="18"/></clipPath></defs>'
				+ '<g clip-path="url(#c)" transform="rotate(10 20 20)" opacity="0.8"><rect width="40" height="40" fill="url(#g)"/></g>'
				+ '<path d="M4 36 L36 4" stroke="currentColor" stroke-width="3" stroke-dasharray="4 2" stroke-linecap="round" fill="none"/></svg>');
			var text = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 40">'
				+ '<defs><linearGradient id="g" x1="0" x2="1"><stop offset="0" stop-color="#f00"/><stop offset="1" stop-color="#00f" stop-opacity="0.5"/></linearGradient>'
				+ '<clipPath id="c"><circle cx="20" cy="20" r="18"/></clipPath></defs>'
				+ '<g clip-path="url(#c)" transform="rotate(10 20 20)" opacity="0.8"><rect width="40" height="40" fill="url(#g)"/></g>'
				+ '<path d="M4 36 L36 4" stroke="currentColor" stroke-width="3" stroke-dasharray="4 2" stroke-linecap="round" fill="none"/></svg>';
			var read = Svg.read(text);
			equals({w: built.width, h: built.height}, {w: read.width, h: read.height});
			equals(built.render(64, 64, 0xFF00AA00).pixels.toHex(), read.render(64, 64, 0xFF00AA00).pixels.toHex());
		});
		test("parse of the same constant twice: one drawing", () -> {
			equals(Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 4 4"><rect width="4" height="4"/></svg>'),
				Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 4 4"><rect width="4" height="4"/></svg>'));
		});
		test("parse of a string made when running: read then", () -> {
			var n = 4 + Std.random(1);
			var svg = Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $n $n"><rect width="4" height="4"/></svg>');
			equals(svg.width, 4.0);
		});
	});
}
