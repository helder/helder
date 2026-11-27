package helder.text;

import haxe.io.Bytes;
import helder.test.Gen;
import helder.test.Test;
import sys.io.File;

using StringTools;

// WOFF and WOFF2 (tests/text/woff, made by make.py there) read as the TTF
// or OTF they were made from: the same metrics, names, characters' glyphs,
// advances and outlines, glyph by glyph. WOFF2's transformed glyf and loca
// (Inter's, Ahem's, Google Fonts' Open Sans by Google's encoder), its
// transformed hmtx, CFF outlines, a collection of two; a damaged file an
// error "Woff: ..." or "Brotli: ...", never a crash, a hang or memory past
// its bound (the fuzz lane soaks it)
function tests() {
	var dir = "tests/text/woff";
	describe("Woff", () -> {
		test("WOFF 1.0: TrueType and CFF outlines", () -> {
			same(font("src/helder/text/fonts/Inter.ttf"), FontFile.parse(file("inter.woff")));
			same(font("tests/canvas/fonts/DejaVuSans-pdf.otf"), FontFile.parse(file("dejavu-cff.woff")));
		});
		test("WOFF2: glyf and loca transformed, Inter (variable) and Ahem", () -> {
			same(font("src/helder/text/fonts/Inter.ttf"), FontFile.parse(file("inter.woff2")));
			same(font("tests/flow/fixtures/Ahem.ttf"), FontFile.parse(file("ahem.woff2")));
		});
		test("WOFF2: hmtx transformed too, its left side bearings the glyphs' xMin", () -> {
			same(font("src/helder/text/fonts/Inter.ttf"), FontFile.parse(file("inter-hmtx.woff2")));
		});
		test("WOFF2: Google Fonts' Open Sans, by Google's encoder", () -> {
			same(font('$dir/opensans-latin.ttf'), FontFile.parse(file("opensans-latin.woff2")));
		});
		test("WOFF2: CFF outlines", () -> {
			same(font("tests/canvas/fonts/DejaVuSans-pdf.otf"), FontFile.parse(file("dejavu-cff.woff2")));
		});
		test("WOFF2: a collection of two faces", () -> {
			var b = file("pair.woff2");
			equals(FontFile.faceCount(b), 2);
			same(font("tests/text/coretext/Inter-Bold-subset.ttf"), FontFile.parse(b, 0));
			same(font("tests/canvas/fonts/DejaVuSans-pdf.ttf"), FontFile.parse(b, 1));
		});
		test("the rebuilt sfnt's tables: checksums right, offsets aligned, records sorted", () -> {
			var s = Woff.sfnt(file("inter-hmtx.woff2")), n = s.get(4) << 8 | s.get(5), last = "";
			for (i in 0...n) {
				var r = 12 + 16 * i, tag = s.getString(r, 4), at = u32(s, r + 8), length = u32(s, r + 12);
				assert(tag > last, 'records sorted: $tag after $last');
				last = tag;
				equals(at & 3, 0);
				var sum = 0;
				for (k in 0...(length + 3) >> 2)
					sum += u32(s, at + 4 * k);
				equals(sum, u32(s, r + 4), tag);
			}
		});
		test("a damaged file: an error, never another exception", () -> {
			var b = file("ahem.woff2");
			// (the last byte or three: padding after the stream)
			for (n in [0, 4, 12, 47, 48, 60, 200, b.length - 4]) {
				var e = error(() -> FontFile.parse(b.sub(0, n)));
				assert(e != null && (e.startsWith("Woff: ") || e.startsWith("Brotli: ") || e.startsWith("FontFile: ")), '$n bytes: $e');
			}
		});
		// (its sfnt then read by FontFile, any error of its allowed: FontFile's
		// own reading of a damaged sfnt is not this file's)
		test("a mutated WOFF or WOFF2: unwrapped, or an error of its own", () -> {
			var seeds = [for (f in ["ahem.woff2", "opensans-latin.woff2", "dejavu-cff.woff", "pair.woff2"]) f => file(f)];
			property(mutated(seeds), b -> {
				var s = null;
				var e = error(() -> s = Woff.sfnt(b));
				assert(e == null || e.startsWith("Woff: ") || e.startsWith("Brotli: "), e);
				if (s != null) try {
					for (i in 0...FontFile.faceCount(s)) {
						var f = FontFile.parse(s, i);
						for (g in 0...f.numGlyphs) f.outline(g, new Nothing());
					}
				} catch (_:Dynamic) {}
			}, {cases: 200, seconds: 3, limit: 10, memory: 256});
		});
	});
}

private function file(name:String):Bytes
	return File.getBytes('tests/text/woff/$name');

private function font(path:String):FontFile
	return FontFile.parse(File.getBytes(path));

// (a and b alike: metrics, names, every character's glyph to U+FFFF, and
// each glyph's advance and outline)
private function same(a:FontFile, b:FontFile) {
	equals([b.unitsPerEm, b.ascender, b.descender, b.lineGap, b.numGlyphs, b.weight], [a.unitsPerEm, a.ascender, a.descender, a.lineGap, a.numGlyphs, a.weight]);
	equals([b.family, b.subfamily, b.postScriptName], [a.family, a.subfamily, a.postScriptName]);
	var chars = [for (c in 0...0x10000) if (a.glyph(c) != b.glyph(c)) c];
	equals(chars, []);
	var differ = [for (g in 0...a.numGlyphs) if (a.advance(g) != b.advance(g) || outline(a, g) != outline(b, g)) g];
	equals(differ, []);
}

private function outline(f:FontFile, g:Int):String {
	var o = new Recorder();
	f.outline(g, o);
	return o.out.toString();
}

private function u32(b:Bytes, p:Int):Int
	return b.get(p) << 24 | b.get(p + 1) << 16 | b.get(p + 2) << 8 | b.get(p + 3);

private function error(f:() -> Void):Null<String>
	return try {
		f();
		null;
	} catch (e:Dynamic) Std.string(e);

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

private class Nothing implements Outline {
	public function new() {}

	public function moveTo(x:Float, y:Float) {}

	public function lineTo(x:Float, y:Float) {}

	public function quadTo(cx:Float, cy:Float, x:Float, y:Float) {}

	public function cubicTo(c1x:Float, c1y:Float, c2x:Float, c2y:Float, x:Float, y:Float) {}

	public function close() {}
}
