package helder.text;

import helder.test.Test;

// font-variant-emoji's choice of a face (FontSet.presentation, TextLayout):
// a monochrome face and a colour one that both have ❤ (Emoji, text by
// default) and ⭐ (emoji by default), in either order; VS15 and VS16 over
// the property
function tests() {
	var colour = FontFile.parse(sys.io.File.getBytes("tests/text/colr/noto-colrv1-subset.ttf"));
	var square:Array<FontEncoder.FontPoint> = [{x: 100, y: 0, on: true}, {x: 100, y: 700, on: true}, {x: 800, y: 700, on: true}, {x: 800, y: 0, on: true}];
	var mono = FontFile.parse(FontEncoder.encode({
		family: "Mono",
		unitsPerEm: 1000,
		ascender: 800,
		descender: -200,
		glyphs: [{codes: [], advance: 500, contours: []}, {codes: [0x2764], advance: 900, contours: [square]}, {codes: [0x2B50], advance: 900, contours: [square]}]
	}));
	// (the face of each glyph shown: M mono, C colour)
	function faces(text:String, presentation:Int, colourFirst:Bool):String {
		var set = colourFirst ? new FontSet(colour, [mono], 40) : new FontSet(mono, [colour], 40);
		set.presentation = presentation;
		var l = new TextLayout(text, set, 1, Math.POSITIVE_INFINITY), out = "";
		for (i in 0...l.glyphCount)
			if (!l.glyphHidden(i)) out += l.glyphFont(i) == mono ? "M" : "C";
		return out;
	}
	var heart = String.fromCharCode(0x2764), star = String.fromCharCode(0x2B50);
	describe("Emoji", () -> {
		test("the properties: Emoji and Emoji_Presentation", () -> {
			equals([Emoji.emoji(0x2764), Emoji.presentation(0x2764)], [true, false]);
			equals([Emoji.emoji(0x1F600), Emoji.presentation(0x1F600)], [true, true]);
			equals([Emoji.emoji("A".code), Emoji.emoji("3".code), Emoji.presentation("3".code)], [false, true, false]);
		});
		test("normal and unicode: as Emoji_Presentation says, whichever face comes first", () -> {
			for (p in [FontSet.NORMAL, FontSet.UNICODE]) {
				equals(faces(heart + star, p, true), "MC");
				equals(faces(heart + star, p, false), "MC");
			}
		});
		test("text and emoji: the face without colour, the one with it", () -> {
			equals(faces(heart + star, FontSet.TEXT, true), "MM");
			equals(faces(heart + star, FontSet.EMOJI, false), "CC");
		});
		test("VS15 and VS16 over the property", () -> {
			equals(faces(star + "\u{FE0E}", FontSet.EMOJI, true), "M");
			equals(faces(heart + "\u{FE0F}", FontSet.TEXT, false), "C");
		});
	});
}
