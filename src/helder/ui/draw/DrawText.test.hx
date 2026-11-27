package helder.ui.draw;

import helder.test.Test;
import helder.text.FontEncoder;
import helder.text.FontFile;
import helder.text.SystemFonts;
import helder.ui.Font;

// DrawText's kept paragraphs: a font replaced in place (FontFile.replace:
// a font asset reloaded, an app's own font redrawn) shapes the same text
// again, with the new font's glyphs and advances; a font's hyphens and
// language (Style.hyphens, Node.lang) given to TextLayout
function tests() {
	describe("DrawText", () -> {
		test("a font replaced: the same text shaped again", () -> {
			var box = [[{x: 0.0, y: 0.0, on: true}, {x: 0.0, y: 500.0, on: true}, {x: 100.0, y: 500.0, on: true}, {x: 100.0, y: 0.0, on: true}]];
			function font(name:String, glyphs:Array<FontGlyph>)
				return FontEncoder.encode({family: "Replaced", postScriptName: name, unitsPerEm: 1000, ascender: 800, descender: -200, glyphs: glyphs});
			var fonts = new SystemFonts();
			var face = fonts.add(font("A", [{codes: [], advance: 500, contours: []}, {codes: [97], advance: 500, contours: box}, {codes: [98], advance: 300, contours: box}]))[0];
			var text = new DrawText(fonts), f = new Font("Replaced", 10, 400, false, 1.2);
			equals(text.layout("ab", f, Math.NaN).width, 8.0);
			equals(text.layout("ab", f, 100).width, 8.0);
			// (the glyphs in another order, other advances: the old shaping's would be wrong)
			face.replace(FontFile.parse(font("B", [
				{codes: [], advance: 500, contours: []},
				{codes: [120], advance: 100, contours: box},
				{codes: [97], advance: 800, contours: box},
				{codes: [98], advance: 300, contours: box}
			])));
			equals(text.layout("ab", f, Math.NaN).width, 11.0);
			equals(text.layout("ab", f, 100).width, 11.0);
		});
		test("hyphens: auto by the font's language, a paragraph kept laid out again when they change", () -> {
			helder.text.Hyphenation.add(helder.text.hyphenation.Nl.patterns());
			var fonts = new SystemFonts();
			fonts.add(helder.asset.Embed.bytes("helder/text/fonts/Inter.ttf"));
			var text = new DrawText(fonts);
			function font(hyphens:Hyphens, ?lang:String)
				return new Font("Inter", 16, 400, false, 1.25, 0, 0, Normal, null, "", hyphens, lang);
			function lines(p:helder.ui.Paragraph):Array<String> {
				var l = (cast p : DrawText.DrawParagraph).layout;
				return [
					for (line in l.lines)
						l.text.substring(line.start, line.end) + (l.glyphChar(line.glyphEnd - 1) == 0xAD && !l.glyphHidden(line.glyphEnd - 1) ? "-" : "")
				];
			}
			var manual = text.layout("woordenboek", font(Manual, "nl"), 50);
			equals(lines(manual), ["woordenboek"]);
			// (the same paragraph let go and laid out again: hyphenated now)
			var auto = text.layout("woordenboek", font(Auto, "nl"), 50, null, 0, false, -1, -1, manual);
			equals(lines(auto), ["woor-", "den-", "boek"]);
			equals(lines(text.layout("woordenboek", font(Auto, "ja"), 50)), ["woordenboek"]);
			equals(lines(text.layout("woordenboek", font(Auto), 50)), ["woordenboek"]);
			equals(lines(text.layout("woor\u00ADdenboek", font(None, "nl"), 50)), ["woor\u00ADdenboek"]);
			equals(lines(text.layout("woor\u00ADdenboek", font(Manual, "nl"), 50)), ["woor\u00AD-", "denboek"]);
		});
	});
}
