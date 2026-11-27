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
		test("line-height: normal holds the fallback faces a line's text is in (line-height-205)", () -> {
			// (A and the space in Ahem, the first available font; b in Inter, taller and deeper)
			var f = made([
				{family: "AB", ahem: true, ranges: "U+20,U+41"},
				{family: "AB", ahem: false, ranges: "U+62"},
				{family: "A", ahem: true},
				{family: "B", ahem: false}
			]);
			function line(build:InlineContent->Void, root:InlineBasicStyle):Array<Float> {
				var c = new InlineContent(root, f);
				build(c);
				c.finish();
				var l = new InlineLayout().layout(c, new InlineConstraints(1000));
				return [l.lines, l.lineHeight(0), l.lineBaseline(0)];
			}
			function big(family:String, ?change:InlineBasicStyle->Void)
				return style(family, s -> {
					s.size = 100;
					if (change != null) change(s);
				});
			var both = line(c -> c.addText("Ab", big("AB")), big("AB"));
			// (as one span in each face: Inter's ascent and descent, past Ahem's 80 and 20)
			var spans = line(c -> {
				c.openBox(big("A"));
				c.addText("A", big("A"));
				c.closeBox();
				c.openBox(big("B"));
				c.addText("b", big("B"));
				c.closeBox();
			}, big("AB"));
			equals(both, spans);
			assert(both[1] > 100, "taller than Ahem's 100");
			// (Ahem's alone without the b, and at a line-height given: the fallback's metrics left out)
			equals(line(c -> c.addText("AA", big("AB")), big("AB"))[1], 100.0);
			equals(line(c -> c.addText("Ab", big("AB", s -> s.height = 50)), big("AB", s -> s.height = 50))[1], 50.0);
		});
	});
}
