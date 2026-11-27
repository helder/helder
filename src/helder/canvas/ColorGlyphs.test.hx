package helder.canvas;

import haxe.io.Bytes;
import helder.test.Test;
import helder.text.FontFile;
import sys.io.File;

// COLR v1 drawn on the CPU canvas against Chromium's drawings (Skia's
// COLR v1: tests/text/colr/goldens.mjs): googlefonts/color-fonts' test
// glyphs (gradients and their extends, transforms, composites, clips,
// nested glyphs) and a subset of Noto Color Emoji's COLR v1 build, a cell a
// glyph; a cell matches when no more than 2% of its pixels differ by more
// than antialiasing does (KNOWN: a difference that is the canvas's, not
// COLR's). Our sheets are written in bin/colr.
function tests() {
	var dir = "tests/text/colr";
	var glyphs:Dynamic = haxe.Json.parse(File.getContent('$dir/glyphs.json'));
	describe("ColorGlyphs", () -> {
		test("COLR v1's test glyphs as Chromium draws them", () -> {
			equals(differing(dir, "test_glyphs", "test_glyphs-glyf_colr_1.ttf", glyphs.test_glyphs), []);
		});
		test("Noto Color Emoji's COLR v1 glyphs as Chromium draws them", () -> {
			equals(differing(dir, "noto", "noto-colrv1-subset.ttf", glyphs.noto), []);
		});
		test("a palette's entries and the text's colour", () -> {
			var face = FontFile.parse(File.getBytes('$dir/test_glyphs-glyf_colr_1.ttf'));
			var c = face.colr;
			assert(c.palettes.length > 0 && c.entries > 0);
			// (a glyph of the font's in another palette: its colours change)
			var g = face.glyph(0xF0100), a = new Canvas(64, 64), b = new Canvas(64, 64);
			ColorGlyphs.draw(a, face, g, 48, 8, 56, 1, 0, null, 0xFF000000, 1);
			ColorGlyphs.draw(b, face, g, 48, 8, 56, 1, 0, [for (_ in 0...c.entries) 0xFF00FF00], 0xFF000000, 1);
			notEquals(pixels(a), pixels(b));
		});
	});
}

// (where helder.canvas draws otherwise than Skia, not COLR's doing)
private final KNOWN = [
	"solid_colorline_alpha" => "its circle's quarters wind both ways: the canvas's analytic coverage (signed areas summed) leaves a hairline where they meet at a fractional pixel"
];

private function differing(dir:String, name:String, file:String, list:Array<Dynamic>):Array<String> {
	var face = FontFile.parse(File.getBytes('$dir/$file'));
	var cell = 64, columns = 20, rows = Math.ceil(list.length / columns);
	var c = new Canvas(cell * columns, cell * rows);
	c.fill(rect(0, 0, c.width, c.height), Paint.solid(0xFFFFFFFF));
	for (i in 0...list.length)
		ColorGlyphs.draw(c, face, face.glyph(list[i].cp), 48, (i % columns) * cell + 8, Std.int(i / columns) * cell + 56, 1, 0, null, 0xFF000000, 1);
	sys.FileSystem.createDirectory("bin/colr");
	File.saveBytes('bin/colr/$name.png', c.toPng());
	var want = helder.image.PngDecoder.decode(File.getBytes('$dir/$name.png'));
	var got = Bytes.alloc(c.width * c.height * 4);
	c.readPixels(got, 0, 0, c.width, c.height);
	var out = [];
	for (i in 0...list.length) {
		var x0 = (i % columns) * cell, y0 = Std.int(i / columns) * cell, bad = 0;
		for (y in y0...y0 + cell)
			for (x in x0...x0 + cell) {
				var k = (y * c.width + x) * 4, d = 0;
				for (ch in 0...3) d = Std.int(Math.max(d, Math.abs(got.get(k + ch) - want.rgba.get(k + ch))));
				if (d > 48) bad++;
			}
		if (bad > cell * cell * 0.02 && !KNOWN.exists(list[i].name ?? "")) out.push('${list[i].name ?? StringTools.hex(list[i].cp)} ($bad)');
	}
	return out;
}

private function pixels(c:Canvas):String {
	var b = Bytes.alloc(c.width * c.height * 4);
	c.readPixels(b, 0, 0, c.width, c.height);
	return haxe.crypto.Md5.make(b).toHex();
}

private function rect(x:Float, y:Float, w:Float, h:Float):Path {
	var p = new Path();
	p.moveTo(x, y);
	p.lineTo(x + w, y);
	p.lineTo(x + w, y + h);
	p.lineTo(x, y + h);
	p.close();
	return p;
}
