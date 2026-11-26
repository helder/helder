package helder.pdf;

import helder.pdf.PageText;
import helder.test.Test;

// A range's highlight: one box a line over its characters, a right-to-left
// line's too (its characters in logical order, their boxes from the right)
function tests() {
	// (characters 10 points wide on a baseline, their boxes from x0 by step)
	function line(text:String, x0:Float, step:Float):PageText {
		var boxes:Array<Float> = [];
		for (i in 0...text.length)
			boxes = boxes.concat([x0 + step * i + (step < 0 ? step : 0), 20, 10, 0, 0, -12]);
		return {text: text, boxes: boxes};
	}
	describe("PageTexts.spans", () -> {
		test("left to right: from the first character's start to the last's end", () -> {
			equals(PageTexts.spans(line("abcd", 10, 10), 1, 3), [[20.0, 20.0, 20.0, 0.0, 0.0, -12.0]]);
		});
		test("right to left: the same box, its first character at the right", () -> {
			// (logical order: the first character's box at 40 to 50, the last's at 10 to 20)
			equals(PageTexts.spans(line("אבגד", 50, -10), 0, 4), [[10.0, 20.0, 40.0, 0.0, 0.0, -12.0]]);
			equals(PageTexts.spans(line("אבגד", 50, -10), 1, 3), [[20.0, 20.0, 20.0, 0.0, 0.0, -12.0]]);
		});
		test("a line each", () -> {
			var a = line("ab", 10, 10), b = line("cd", 10, 10);
			var t:PageText = {text: "ab\ncd", boxes: a.boxes.concat([Math.NaN, Math.NaN, Math.NaN, Math.NaN, Math.NaN, Math.NaN]).concat(b.boxes)};
			equals(PageTexts.spans(t, 0, 5).length, 2);
		});
	});
}
