package helder.ui.box;

import helder.dom.Dom;
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
	var arabic = has([for (c in 0x627...0x64B) if (c < 0x63B || c > 0x640) c]);
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
	var alpha = "abcdefghijklmnopqrstuvwxyz".split("");
	var mixed:Gen<String> = c -> [c.draw(letterWord(alpha)), c.draw(ligatures), c.draw(letterWord(hebrew)), c.draw(letterWord(alpha))].join(" ");
	var punct = c -> c.draw(pick(["2026", "12", "3.5", "(", ")", "!", ",", ".", "-", ":", "0"]));
	var wide:Gen<String> = c -> [c.draw(letterWord(letters)), c.draw(punct), c.draw(letterWord(hebrew)), c.draw(punct), c.draw(letterWord(arabic)), c.draw(punct), c.draw(ligatures)].join(" ");
	var texts = oneOf([ligatures, words(letterWord(letters)), words(letterWord("aeiouf".split(""), marks)), words(letterWord(hebrew)), words(letterWord(arabic)), mixed, wide]);
	describe("a paragraph's PDF text", () -> {
		test("comes back from Pdf.text as its characters", () -> property(texts, t -> {
			var pdf = PagedView.toPdf(page(t), {fonts: fonts()});
			equals(Pdf.text(Pdf.open(pdf).pages[0]).trim(), t);
		}, {cases: 100}));
		test("a right-to-left run that reads the same backwards: each letter's box where it was drawn", () -> {
			for (t in ["\u05D0\u05D0", "\u05D0\u05D1\u05D0", "a \u05D0\u05D0 b"]) {
				var v = new PagedView(Dom.parse(page(t)), {fonts: fonts()});
				var runs = Pdf.runs(Pdf.open(v.pdf()).pages[0]);
				var d = new helder.canvas.doc.Document(), p = d.newPage(1500, 75);
				p.scale(0.75, 0.75);
				v.paint(0, p, false);
				for (op in p.ops) if (op.kind == Text) boxes(runs[0], op);
			}
		});
		test("each character's box from Pdf.runs where its glyph was drawn", () -> property(texts, t -> {
			var v = new PagedView(Dom.parse(page(t)), {fonts: fonts()});
			var runs = Pdf.runs(Pdf.open(v.pdf()).pages[0]);
			equals(runs.length, 1);
			if (runs.length != 1) return;
			equals(runs[0].text, t);
			// (the page painted again into a recorder, as pdf() paints it: in points)
			var d = new helder.canvas.doc.Document(), p = d.newPage(1500, 75);
			p.scale(0.75, 0.75);
			v.paint(0, p, false);
			for (op in p.ops) if (op.kind == Text) boxes(runs[0], op);
		}, {cases: 100}));
	});
}

private function page(t:String):String
	return '<!doctype html><style>@page { size: 2000px 100px; margin: 10px } body { margin: 0; font: 16px "DejaVu Sans"; white-space: nowrap }</style><p>$t</p>';

// (each glyph's characters have a box from Pdf.runs: its own where it shows
// them alone, else one of an ActualText's that holds where it was drawn)
private function boxes(run:helder.pdf.PdfRun, op:helder.canvas.doc.Recorder.Op) {
	var r = op.run, m = op.matrix, tol = 0.05;
	for (k in 0...r.count) {
		var c = r.starts[k], n = r.ends[k] - c;
		if (n <= 0) continue;
		var gx = m.a * r.xs[k] + m.c * r.ys[k] + m.e, gy = m.b * r.xs[k] + m.d * r.ys[k] + m.f;
		var box = [for (g in run.glyphs) if (g.start <= c && c < g.end) g][0];
		if (box == null) {
			fail('no box for ${run.text.substr(c, n)} at $c');
			return;
		}
		if (box.start == c && box.end == c + n) assert(Math.abs(box.x - gx) < tol, '${run.text.substr(c, n)} at ${box.x}, drawn at $gx');
		else assert(gx > box.x - tol && gx < box.x + box.ax + tol, '${run.text.substr(c, n)} drawn at $gx, outside ${box.x} to ${box.x + box.ax}');
		var top = Math.min(box.y, box.y + box.uy), bottom = Math.max(box.y, box.y + box.uy);
		assert(top < gy && gy < bottom, 'the baseline $gy outside $top to $bottom');
	}
}

private final FONT = "tests/canvas/fonts/DejaVuSans-pdf.ttf";

private function fonts():FontMatch {
	var f = new FontMatch();
	f.register(sys.io.File.getBytes(FONT), "DejaVu Sans");
	return f;
}
