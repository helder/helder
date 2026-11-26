package helder.text;

import haxe.io.Bytes;
import helder.test.Gen;
import helder.test.Test;
import helder.text.FontEncoder.FontGlyph;
import helder.text.FontEncoder.FontPoint;

// A face without a cmap table read all the same where no Unicode map is
// asked for (FontFile.parse's unicode false: a PDF's TrueType subsets, which
// reach their glyphs by CIDToGIDMap and often leave the cmap out): as a
// property, any font FontEncoder makes, its cmap taken out, has the same
// glyphs, advances and outlines, and no character's glyph; asked for its
// Unicode map, it is refused as before.
function tests() {
	describe("FontFile without a cmap", () -> {
		var box:Gen<Array<FontPoint>> = c -> {
			var x = c.draw(int(0, 800)), y = c.draw(int(-200, 600)), w = c.draw(int(10, 200)), h = c.draw(int(10, 300));
			[{x: x, y: y, on: true}, {x: x, y: y + h, on: true}, {x: x + w, y: y + h, on: true}, {x: x + w, y: y, on: true}];
		};
		var glyph:Gen<FontGlyph> = c -> {codes: [], advance: c.draw(int(0, 1200)), contours: c.draw(array(box, 0, 3))};
		var font:Gen<Array<FontGlyph>> = array(glyph, 1, 12).map(gs -> {
			// (each glyph but .notdef a character of its own, as a subset's)
			for (i in 1...gs.length)
				gs[i].codes = [0x61 + i];
			gs;
		});
		test("any font, its cmap taken out: the same glyphs, advances and outlines", () -> property(font, glyphs -> {
			var bytes = FontEncoder.encode({family: "Subset", unitsPerEm: 1000, ascender: 800, descender: -200, glyphs: glyphs});
			var whole = FontFile.parse(bytes), bare = FontFile.parse(withoutTable(bytes, "cmap"), 0, false);
			equals(bare.numGlyphs, whole.numGlyphs);
			for (g in 0...whole.numGlyphs) {
				equals(bare.advance(g), whole.advance(g));
				equals(outline(bare, g), outline(whole, g));
			}
			for (i in 1...glyphs.length)
				equals(bare.glyph(0x61 + i), 0);
		}));
		test("its Unicode map asked for: refused", () -> {
			var bytes = FontEncoder.encode({family: "Subset", unitsPerEm: 1000, ascender: 800, descender: -200, glyphs: [{codes: [], advance: 500, contours: []}]});
			var refused = try {
				FontFile.parse(withoutTable(bytes, "cmap"));
				false;
			} catch (e:String) e.indexOf("cmap") >= 0;
			assert(refused, "a face without a cmap read as a Unicode one");
		});
	});
}

// (the font with one table's record out of its directory: its count one less,
// the others' offsets as they were, the record's 16 bytes zeros at the end)
private function withoutTable(b:Bytes, tag:String):Bytes {
	var out = Bytes.alloc(b.length);
	out.blit(0, b, 0, b.length);
	var n = (b.get(4) << 8) | b.get(5), at = 12;
	for (i in 0...n) {
		var r = 12 + 16 * i;
		if (b.getString(r, 4) == tag) continue;
		out.blit(at, b, r, 16);
		at += 16;
	}
	out.fill(at, 12 + 16 * n - at, 0);
	out.set(4, ((at - 12) >> 4) >> 8);
	out.set(5, ((at - 12) >> 4) & 0xFF);
	return out;
}

// (a glyph's outline as text: its calls, in order)
private function outline(f:FontFile, g:Int):String {
	var o = new Recorder();
	f.outline(g, o);
	return o.out.toString();
}

private class Recorder implements Outline {
	public final out = new StringBuf();

	public function new() {}

	public function moveTo(x:Float, y:Float)
		out.add('M$x,$y ');

	public function lineTo(x:Float, y:Float)
		out.add('L$x,$y ');

	public function quadTo(cx:Float, cy:Float, x:Float, y:Float)
		out.add('Q$cx,$cy,$x,$y ');

	public function cubicTo(c1x:Float, c1y:Float, c2x:Float, c2y:Float, x:Float, y:Float)
		out.add('C$c1x,$c1y,$c2x,$c2y,$x,$y ');

	public function close()
		out.add('Z ');
}
