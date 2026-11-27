package helder.text;

import helder.test.Test;

// helder's Inter (fonts/Inter.ttf: what a web page ships and Look.base
// adds): one variable face whose weights are instances
function tests() {
	describe("Inter", () -> {
		var f = FontFile.parse(helder.asset.Embed.bytes("helder/text/fonts/Inter.ttf"));
		test("one family, its weight an axis", () -> {
			equals(f.family, "Inter");
			equals([for (a in f.axes) a.tag], ["wght"]);
		});
		test("400, 500 and 600: heavier and wider", () -> {
			var w = [for (w in [400, 500, 600]) f.instance(["wght" => w])];
			var h = f.glyph("H".code);
			assert(h != 0);
			assert(w[0].advance(h) < w[1].advance(h) && w[1].advance(h) < w[2].advance(h));
		});
		test("Latin Extended-A, punctuation, currency, arrows, ⌘", () -> {
			for (c in [0x151, 0x2014, 0x20AC, 0x2192, 0x2318])
				assert(f.glyph(c) != 0);
		});
	});
}
