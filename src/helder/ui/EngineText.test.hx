package helder.ui;

import helder.test.Test;

// The CSS engine's text (EngineText) against helder.text's own (DrawText):
// the same widths, heights, lines, min-content widths, carets, hits and
// selections for one font; its baseline the engine's, a font's ascent
// rounded as Chromium has it.
function tests() {
	final draw = new helder.ui.draw.DrawText(), engine = new EngineText();
	final font = new Font("sans-serif", 14, 400, false, 1.25);
	final texts = [
		{text: "Hello world", width: Math.NaN},
		{text: "The quick brown fox jumps over the lazy dog", width: 120.0},
		{text: "a\nbb\nccc", width: Math.NaN},
		{text: "", width: 100.0},
		{text: "Task 12: water the plants and call back", width: 200.0}
	];
	// (the same sums in another order: their last bits apart on a target)
	function near(a:Float, b:Float)
		equals(Math.abs(a - b) < 1e-6, true, '$a, $b');
	describe("engine text", () -> {
		test("the same measures as DrawText's", () -> {
			for (t in texts) {
				var a = draw.layout(t.text, font, t.width), b = engine.layout(t.text, font, t.width);
				near(b.width, a.width);
				near(b.height, a.height);
				equals(b.lineCount, a.lineCount);
				near(b.minWidth, a.minWidth);
				// (the engine's a whole pixel: its font's ascent rounded)
				equals(b.baseline > a.baseline - 1 && b.baseline <= a.baseline + 0.5, true);
			}
		});
		test("carets and hits, across hard breaks", () -> {
			var t = "a\nbb\nccc", a = draw.layout(t, font, Math.NaN), b = engine.layout(t, font, Math.NaN);
			for (i in 0...t.length + 1) {
				equals(b.caret(i).x, a.caret(i).x);
				equals(b.caret(i).y, a.caret(i).y);
			}
			for (y in [5.0, 25.0, 40.0]) for (x in [0.0, 5.0, 30.0]) equals(b.hit(x, y), a.hit(x, y));
		});
		test("a selection's rectangles", () -> {
			var t = "The quick brown fox jumps over the lazy dog", a = draw.layout(t, font, 120), b = engine.layout(t, font, 120);
			var ra = a.selection(4, 30), rb = b.selection(4, 30);
			equals(rb.length, ra.length);
			for (i in 0...ra.length) {
				near(rb[i].x, ra[i].x);
				near(rb[i].y, ra[i].y);
				near(rb[i].width, ra[i].width);
			}
		});
		test("an empty text: a line of its height", () -> {
			var p = engine.layout("", font, 100);
			equals(p.lineCount, 1);
			equals(p.height, 17.5);
			equals(p.caret(0).height, 17.5);
		});
		test("a span in its own font: as wide as DrawText lays it", () -> {
			var bold = new Font("sans-serif", 14, 700, false, 1.25), spans = [new TextSpan(4, 9, bold)];
			var a = draw.layout("The quick fox", font, Math.NaN, spans), b = engine.layout("The quick fox", font, Math.NaN, spans);
			near(b.width, a.width);
			near(b.caret(9).x, a.caret(9).x);
		});
	});
}
