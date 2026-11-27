package helder.ui.box;

import helder.pdf.Pdf;
import helder.test.Gen;
import helder.test.Test;

using StringTools;

// An HTML paragraph's text through the box tree's lines and PdfWriter comes
// back from Pdf.text as its characters: ligatures (DejaVu's fi, fl, ffi),
// combining marks, Hebrew, and both directions in one line. (PdfWriter's own
// property lays out with TextLayout, whose glyphs carry their clusters'
// ends; the box tree's line builder gave each glyph one unit, and a
// ligature's ToUnicode said its first letter only.)
function tests() {
	var face = helder.text.FontFile.parse(sys.io.File.getBytes(FONT));
	function has(cps:Array<Int>)
		return [for (c in cps) if (face.glyph(c) > 0) String.fromCharCode(c)];
	var letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,;:!?'()-".split("");
	var marks = has([for (c in 0x300...0x370) c]), hebrew = has([for (c in 0x5D0...0x5EB) c]);
	function words(word:Gen<String>):Gen<String>
		return array(word, 1, 6).map(ws -> ws.join(" "));
	function letterWord(set:Array<String>, ?marked:Array<String>):Gen<String>
		return c -> {
			var n = c.draw(int(1, 7)), b = new StringBuf();
			for (_ in 0...n) {
				b.add(c.draw(pick(set)));
				if (marked != null && c.draw(int(0, 3)) == 0) b.add(c.draw(pick(marked)));
			}
			b.toString();
		};
	var ligatures = words(pick(["fi", "fl", "ffi", "ffl", "ff", "float", "figure", "office", "waffle", "flu", "fit", "affix", "field", "flow"]));
	// (letters around the Hebrew: beside digits or punctuation it is not yet
	// right, "a fi א 0" reading "a fi 0א": the line's runs of each
	// direction are fragments of their own, each its own text to PdfWriter)
	var alpha = "abcdefghijklmnopqrstuvwxyz".split("");
	var mixed:Gen<String> = c -> [c.draw(letterWord(alpha)), c.draw(ligatures), c.draw(letterWord(hebrew)), c.draw(letterWord(alpha))].join(" ");
	var texts = oneOf([ligatures, words(letterWord(letters)), words(letterWord("aeiouf".split(""), marks)), words(letterWord(hebrew)), mixed]);
	describe("a paragraph's PDF text", () -> {
		test("comes back from Pdf.text as its characters", () -> property(texts, t -> {
			var html = '<!doctype html><style>@page { size: 2000px 100px; margin: 10px } body { margin: 0; font: 16px "DejaVu Sans"; white-space: nowrap }</style><p>$t</p>';
			var pdf = PagedView.toPdf(html, {fonts: fonts()});
			equals(Pdf.text(Pdf.open(pdf).pages[0]).trim(), t);
		}, {cases: 100}));
	});
}

private final FONT = "tests/canvas/fonts/DejaVuSans-pdf.ttf";

private function fonts():FontMatch {
	var f = new FontMatch();
	f.register(sys.io.File.getBytes(FONT), "DejaVu Sans");
	return f;
}
