package helder.ui.flow;

import helder.test.Test;
import helder.text.FontFaces;
import helder.text.FontFile;
import helder.ui.flow.InlineValues;

// The document's faces through InlineFonts: a variable face's instance at
// the weight asked for, font-variation-settings over it, a weight or style a
// static face lacks synthesized as font-synthesis allows, an @font-face
// weight that claims bold, and unicode-range's composite faces
function tests() {
	var interData = helder.asset.Embed.bytes("helder/text/fonts/Inter.ttf"), ahemData = sys.io.File.getBytes("tests/flow/fixtures/Ahem.ttf");
	function made(rules:Array<{family:String, ahem:Bool, ?weight:String, ?ranges:String}>):InlineFonts {
		var faces = new FontFaces();
		for (r in rules) {
			var f = FontFile.parse(r.ahem ? ahemData : interData);
			faces.add(r.family, f, FontFaceDescriptors.parse(f, r.weight, null, null, r.ranges));
		}
		return new InlineFonts(null, faces);
	}
	function style(family:String, change:InlineBasicStyle->Void):InlineBasicStyle {
		var s = new InlineBasicStyle();
		s.families = [family];
		change(s);
		return s;
	}
	function set(f:InlineFonts, s:InlineBasicStyle)
		return f.set(f.idOf(s));

	describe("InlineFonts", () -> {
		test("a variable face: the instance at the weight, no bold synthesized; at 400 the face itself", () -> {
			var f = made([{family: "V", ahem: false}]);
			var bold = set(f, style("V", s -> s.weight = 700));
			equals(bold.primary.weight, 700);
			equals([bold.primary.varied, bold.bold], [true, false]);
			var regular = set(f, style("V", s -> {}));
			equals(regular.primary.varied, false);
		});
		test("font-variation-settings over the weight's wght", () -> {
			var s = set(made([{family: "V", ahem: false}]), style("V", s -> {
				s.weight = 700;
				s.variations = ["wght" => 300];
			}));
			equals(s.primary.weight, 300);
		});
		test("a static face: bold and italic synthesized, as font-synthesis allows", () -> {
			var f = made([{family: "S", ahem: true}]);
			equals(set(f, style("S", s -> s.weight = 700)).bold, true);
			equals(set(f, style("S", s -> s.weight = 500)).bold, false);
			equals(set(f, style("S", s -> {
				s.weight = 700;
				s.synthesis = InlineSynthesis.Style | InlineSynthesis.Oblique;
			})).bold, false);
			equals(set(f, style("S", s -> s.style = Italic)).oblique, true);
			equals(set(f, style("S", s -> {
				s.style = Italic;
				s.synthesis = InlineSynthesis.Oblique;
			})).oblique, false);
			equals(set(f, style("S", s -> {
				s.style = Oblique;
				s.synthesis = InlineSynthesis.Oblique;
			})).oblique, true);
		});
		test("an @font-face weight of 700: bold, none synthesized", () -> {
			equals(set(made([{family: "B", ahem: true, weight: "700"}]), style("B", s -> s.weight = 700)).bold, false);
		});
		test("unicode-range: each face for its characters, the last rule first", () -> {
			var s = set(made([{family: "U", ahem: false, ranges: "U+61-7A"}, {family: "U", ahem: true, ranges: "U+41-5A"}]), style("U", s -> {}));
			equals([s.faceFor("A".code).family, s.faceFor("a".code).family], ["Ahem", "Inter"]);
		});
	});
}
