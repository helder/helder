package helder.text;

import helder.test.Test;
import helder.text.FontFaces;

// CSS Fonts 4 §5.2's matching among a family's @font-face faces: font-stretch,
// then font-style, then font-weight, each the nearest in the spec's order;
// the descriptors as @font-face writes them; unicode-range's composite faces
function tests() {
	var inter = FontFile.parse(helder.asset.Embed.bytes("helder/text/fonts/Inter.ttf"));
	// (a face of its own for each rule: the same font, its descriptors told apart by name)
	function set(rules:Array<{name:String, ?weight:String, ?stretch:String, ?style:String, ?ranges:String}>):FontFaces {
		var s = new FontFaces();
		for (r in rules) {
			var f = inter.instance([]);
			s.add("f", f, FontFaceDescriptors.parse(f, r.weight, r.stretch, r.style, r.ranges));
			names.set(f, r.name);
		}
		return s;
	}
	function picked(s:FontFaces, weight:Float, stretch = 100.0, ?style:FontStyle):Array<String>
		return [for (m in s.match("f", weight, stretch, style ?? Normal)) names.get(m.file)];

	describe("FontFaces", () -> {
		test("font-weight: within a range, else 400 to 500 up to 500 first, lighter below 400, heavier above 500", () -> {
			var s = set([{name: "thin", weight: "100 300"}, {name: "regular", weight: "400"}, {name: "bold", weight: "700 900"}]);
			equals(picked(s, 200), ["thin"]);
			equals(picked(s, 450), ["regular"]);
			equals(picked(s, 350), ["thin"]);
			equals(picked(s, 600), ["bold"]);
			equals(picked(s, 950), ["bold"]);
			var t = set([{name: "light", weight: "300"}, {name: "medium", weight: "500"}, {name: "black", weight: "900"}]);
			equals(picked(t, 400), ["medium"]);
			equals(picked(t, 450), ["medium"]);
			equals(picked(set([{name: "light", weight: "300"}, {name: "black", weight: "900"}]), 450), ["light"]);
		});
		test("font-stretch first: narrower first at or below 100%, wider first above", () -> {
			var s = set([{name: "condensed", stretch: "75%", weight: "900"}, {name: "normal", stretch: "100%", weight: "400"}, {name: "expanded", stretch: "125%"}]);
			equals(picked(s, 900, 90), ["condensed"]);
			equals(picked(s, 900, 110), ["expanded"]);
			equals(picked(s, 900, 100), ["normal"]);
			equals(picked(set([{name: "wide", stretch: "expanded"}, {name: "narrow", stretch: "condensed"}]), 400, 87.5), ["narrow"]);
		});
		test("font-style: italic, else oblique, else normal; oblique by angle, italic before the other side; normal before both", () -> {
			var s = set([{name: "normal"}, {name: "italic", style: "italic"}, {name: "oblique", style: "oblique 10deg 20deg"}]);
			equals(picked(s, 400, 100, Italic), ["italic"]);
			equals(picked(s, 400, 100, Oblique(15)), ["oblique"]);
			equals(picked(s, 400, 100, Oblique(30)), ["oblique"]);
			equals(picked(s, 400, 100, Normal), ["normal"]);
			var t = set([{name: "normal"}, {name: "italic", style: "italic"}]);
			equals(picked(t, 400, 100, Oblique(14)), ["italic"]);
			equals(picked(t, 400, 100, Oblique(-14)), ["normal"]);
			equals(picked(set([{name: "normal"}, {name: "oblique", style: "oblique"}]), 400, 100, Italic), ["oblique"]);
			equals(picked(set([{name: "italic", style: "italic"}]), 400, 100, Normal), ["italic"]);
		});
		test("unicode-range: faces of the same descriptors, the last defined first; a face used for its range alone", () -> {
			var s = set([{name: "latin", ranges: "U+0-7F"}, {name: "greek", ranges: "U+370-3FF"}, {name: "bold", weight: "700"}]);
			equals(picked(s, 400), ["greek", "latin"]);
			var latin = s.match("f", 400, 100, Normal)[1].file;
			equals([latin.has("a".code), latin.has(0x3B1)], [true, false]);
			equals(latin.unicodeRange, [0, 0x7F]);
		});
		test("descriptors as written: auto, keywords, ranges reversed, angles, wildcards", () -> {
			var d = FontFaceDescriptors.parse(inter, "bold", "condensed", "oblique 20deg 10deg", "U+4??, U+0025-00FF, u+1F600");
			equals([d.weight.min, d.weight.max, d.stretch.min, d.stretch.max, d.angle.min, d.angle.max], [700.0, 700, 75, 75, 10, 20]);
			equals(d.style, FontFaceStyle.Oblique);
			equals(d.ranges, [0x400, 0x4FF, 0x25, 0xFF, 0x1F600, 0x1F600]);
			// (auto: the font's own; Inter's wght axis its weights)
			var own = FontFaceDescriptors.parse(inter, "auto", null, null, null);
			equals([own.weight.min, own.weight.max], [100.0, 900]);
			equals(FontFaceDescriptors.parse(inter, "900 100", "50% 200%", "italic", null).weight.min, 100.0);
		});
		test("a family named here and none other: null for the others", () -> {
			var s = set([{name: "a"}]);
			equals(s.has("F"), true);
			equals(s.match("g", 400, 100, Normal), null);
		});
	});
}

private final names = new haxe.ds.ObjectMap<FontFile, String>();
