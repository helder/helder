package helder.text;

import helder.test.Gen;
import helder.test.Test;
import sys.io.File;

// COLR and CPAL read from damaged fonts (Gen.mutated: the COLR v1 test
// glyphs and Noto's subset): a glyph's paint, null or none, never another
// exception, a hang or memory past its bound; a cycle's last reference
// nothing, the rest drawn
// (the fuzz lane soaks it)
function tests() {
	describe("Colr", () -> {
		test("the test font's paints: every base glyph's read", () -> {
			var f = FontFile.parse(File.getBytes("tests/text/colr/test_glyphs-glyf_colr_1.ttf"));
			var glyphs:Dynamic = haxe.Json.parse(File.getContent("tests/text/colr/glyphs.json"));
			var none = [for (g in (glyphs.test_glyphs : Array<Dynamic>)) if (f.colorPaint(f.glyph(g.cp)) == null) g.name];
			equals(none, []);
			equals(f.colr.palettes.length > 0, true);
		});
		test("a mutated colour font: its paints read, or none", () -> {
			var seeds = [for (n in ["test_glyphs-glyf_colr_1.ttf", "noto-colrv1-subset.ttf"]) n => File.getBytes('tests/text/colr/$n')];
			property(mutated(seeds), b -> {
				var f = try FontFile.parse(b) catch (_:Dynamic) null;
				if (f == null) return;
				var c = try f.colr catch (e:Dynamic) {
					assert(false, 'COLR threw: $e');
					null;
				}
				if (c == null) return;
				for (g in 0...f.numGlyphs) {
					var e = try {
						f.colorPaint(g);
						null;
					} catch (e:Dynamic) Std.string(e);
					assert(e == null, e);
				}
			}, {cases: 100, seconds: 3, limit: 10, memory: 256});
		});
	});
}
