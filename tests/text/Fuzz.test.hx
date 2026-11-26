package text;

import haxe.io.Bytes;
import helder.test.Gen;
import helder.test.Test;
import helder.text.FontFile;
import helder.text.Outline;

// helder.text's font reader against the repository's small fonts mutated
// (Gen.mutated): one that parses answers for its glyphs (the character
// map, advances, kerning, bounds, outlines), or a read past its data
// throws haxe.io.Error (its callers' to catch, as helder.pdf's PdfFont
// does), never another error, a crash or a hang. Natively within 10 s a case and 256 MB more
// memory. The fuzz lane soaks it (HELDER_PROPERTY_SOAK).
function tests() {
	var seeds = new Map<String, Bytes>();
	for (f in ["tests/canvas/fonts/DejaVuSans-Bold-canvas.ttf", "tests/canvas/fonts/IPAGothic-canvas.ttf", "tests/text/var.ttf", "tests/text/coretext/Inter-Bold-subset.ttf"])
		seeds.set(f, sys.io.File.getBytes(f));

	test("a composite glyph that holds itself: drawn, not recursed for ever", () -> {
		var b = sys.io.File.getBytes("tests/canvas/fonts/DejaVuSans-Bold-canvas.ttf");
		// (glyph 97, a composite: its first component made glyph 97)
		var at = table(b, "glyf") + loca(b, 97);
		b.set(at + 12, 0);
		b.set(at + 13, 97);
		var out = new Count();
		FontFile.parse(b).outline(97, out);
		assert(out.n > 0);
	});
	test("a glyph whose contours' ends go back: each point drawn once", () -> {
		var b = sys.io.File.getBytes("tests/canvas/fonts/DejaVuSans-Bold-canvas.ttf");
		var whole = new Count();
		FontFile.parse(b).outline(6, whole);
		// (glyph 6's five contours' ends made last, 0, last, 0, last: the pdf
		// property's shrunk case, its glyph's 767 contours drawn 13 million segments)
		var at = table(b, "glyf") + loca(b, 6), last = b.get(at + 18) << 8 | b.get(at + 19);
		for (c in [1, 3]) {
			b.set(at + 10 + 2 * c, 0);
			b.set(at + 11 + 2 * c, 0);
		}
		for (c in [0, 2]) {
			b.set(at + 10 + 2 * c, last >> 8);
			b.set(at + 11 + 2 * c, last & 0xFF);
		}
		var out = new Count();
		FontFile.parse(b).outline(6, out);
		assert(out.n > 0 && out.n <= whole.n, '${out.n} segments, ${whole.n} in the glyph');
	});
	test("a mutated font: an error at parse, or its glyphs read", () -> property(mutated(seeds), b -> {
		var font = try FontFile.parse(b) catch (e:Dynamic) null;
		if (font == null) return;
		var out = new Count(), last = 0;
		try for (cp in "Hag é中".split("").map(s -> s.charCodeAt(0))) {
			var g = font.glyph(cp);
			font.advance(g);
			font.kerning(last, g);
			font.bounds(g);
			font.outline(g, out);
			last = g;
		} catch (e:haxe.io.Error) {}
	}, {cases: 150, seconds: 3, limit: 10, memory: 256}));
}

// (a table's offset, from the font's directory)
private function table(b:Bytes, tag:String):Int {
	for (i in 0...(b.get(4) << 8 | b.get(5)))
		if (b.getString(12 + 16 * i, 4) == tag) return u32(b, 12 + 16 * i + 8);
	throw 'no $tag';
}

// (a glyph's offset in glyf: head's indexToLocFormat, a short or long loca)
private function loca(b:Bytes, g:Int):Int {
	var head = table(b, "head"), l = table(b, "loca");
	if (b.get(head + 51) == 0) return (b.get(l + 2 * g) << 8 | b.get(l + 2 * g + 1)) * 2;
	return u32(b, l + 4 * g);
}

private function u32(b:Bytes, p:Int):Int
	return b.get(p) << 24 | b.get(p + 1) << 16 | b.get(p + 2) << 8 | b.get(p + 3);

// (an outline's segments counted)
private class Count implements Outline {
	public var n = 0;

	public function new() {}

	public function moveTo(x:Float, y:Float)
		n++;

	public function lineTo(x:Float, y:Float)
		n++;

	public function quadTo(cx:Float, cy:Float, x:Float, y:Float)
		n++;

	public function cubicTo(c1x:Float, c1y:Float, c2x:Float, c2y:Float, x:Float, y:Float)
		n++;

	public function close()
		n++;
}
