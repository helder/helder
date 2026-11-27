package helder.ui.box;

import helder.text.FontFeature;
import helder.ui.box.Len.Lens;
import helder.ui.flow.InlineStyle;
import helder.ui.flow.InlineFonts;
import helder.ui.flow.InlineShaper;
import helder.ui.flow.InlineValues;

using StringTools;

// A box's computed style as the inline formatting context reads it
// (helder.ui.flow's InlineStyle), one per box: an item's style is its box
// (`box`), and a split inline box's parts keep their edges where the box
// starts and ends. Percentages resolve against the containing block's
// width given.
class BoxInline implements InlineStyle {
	public final box:Box;

	final s:BoxStyle;
	final cb:Float;
	var markerGap = 0.0;

	function new(box:Box, cb:Float) {
		this.box = box;
		s = box.style.model();
		this.cb = cb;
	}

	// A box's, one for its style, its split edges and a containing block's width: styles are
	// compared by identity (InlineFonts' and the shaper's caches), so boxes of one style share
	// one (its `box`: the first of them).
	public static function of(box:Box, cb:Float):BoxInline {
		var style = box.style;
		var edges = box.kind == Text ? 0 : box.flags & (Box.NO_START | Box.NO_END);
		var b = style.inlines[edges];
		if (b == null || b.cb != cb) style.inlines[edges] = b = new BoxInline(box, cb);
		return b;
	}

	@:allow(helder.ui.flow.BlockLines)
	static function insideMarker(box:Box, cb:Float, fonts:InlineFonts):BoxInline {
		var style = of(box, cb);
		if (box.first == null || !box.style.rare.contentNormal) return style;
		var gap = 0.0;
		if (box.first.kind == InlineReplaced) {
			gap = 7;
		} else {
			var symbol = box.markerSymbol();
			if (symbol == null || style.fontSize() == 0) return style;
			var id = fonts.idOf(style), set = fonts.set(id), shaper = fonts.shaper;
			var flags = box.style.rtl ? InlineShaper.RTL : 0;
			var glyph = shaper.width(shaper.shape(set, id, symbol, 0, symbol.length, flags, 0, 0));
			var space = shaper.width(shaper.shape(set, id, " ", 0, 1, 0, 0, 0));
			// A painted bullet reserves its shape's width plus an em, independent of the glyph's advance.
			var diameter = Std.int((Std.int(fonts.ascent(id) * 2 / 3) + 1) / 2);
			gap = diameter + 1 + style.fontSize() - glyph - space;
		}
		var adjusted = new BoxInline(box, cb);
		adjusted.markerGap = gap;
		return adjusted;
	}

	function len(l:Len):Float {
		var v = Lens.resolve(l, cb, 0);
		return Math.isNaN(v) ? 0 : v;
	}

	// (the style's text part: what the box doesn't change)
	var t(get, never):helder.ui.flow.InlineBasicStyle;

	inline function get_t():helder.ui.flow.InlineBasicStyle
		return s.text;

	public function fontFamilies():Array<String>
		return t.families;

	public function fontSize():Float
		return t.size;

	public function fontWeight():Int
		return t.weight;

	public function fontStyle():InlineFontStyle
		return t.style;

	public function fontStretch():Float
		return t.stretch;

	public function fontStyleAngle():Float
		return t.angle;

	public function fontSynthesis():InlineSynthesis
		return t.synthesis;

	public function fontOpticalSizing():Bool
		return t.opticalSizing;

	public function fontVariations():Null<Map<String, Float>>
		return t.variations;

	public function fontFeatures():Null<Array<FontFeature>>
		return t.features;

	public function fontKerning():InlineKerning
		return t.kerning;

	public function fontLigatures():InlineLigatures
		return t.ligatures;

	public function fontEmoji():InlineEmoji
		return t.emoji;

	public function color():Int
		return t.colour;

	public function lineHeight():Float
		return t.height;

	// (none in a list marker: browsers leave a marker's text unspaced)
	public function letterSpacing():Float
		return box.markerPseudo() ? 0 : t.letters;

	public function wordSpacing():Float
		return box.markerPseudo() ? 0 : t.words;

	public function textTransform():InlineTransform
		return t.transform;

	public function whiteSpaceCollapse():InlineCollapse
		return t.collapse;

	public function textWrapMode():InlineWrap
		return t.wrap;

	public function tabSize():Float
		return t.tab;

	public function wordBreak():InlineWordBreak
		return t.breakWord;

	public function overflowWrap():InlineOverflowWrap
		return t.overflow;

	public function lineBreak():InlineLineBreak
		return t.breakLine;

	public function hyphens():InlineHyphens
		return t.hyphen;

	public function lang():Null<String> {
		var b = box;
		while (b != null) {
			if (b.lang != null) return b.lang;
			b = b.parent;
		}
		return null;
	}

	public function direction():InlineDirection
		return t.dir;

	public function unicodeBidi():InlineBidi
		return t.bidi;

	// (a list marker's text is its own, at its start whatever its item's alignment)
	public function textAlign():InlineAlign
		return box.markerPseudo() ? Start : t.align;

	public function textAlignLast():InlineAlign
		return box.markerPseudo() ? Auto : t.alignLast;

	public function textJustify():InlineJustify
		return t.justify;

	// (what the line builder asks each line: read once, a width's)
	var indentValue = Math.NaN;
	var edgesValue:Null<Array<Float>> = null;

	// (none in a list marker's own line: its item's indent is its item's text's)
	public function textIndent():Float {
		if (indentValue == indentValue) return indentValue;
		return indentValue = box.markerPseudo() ? 0 : len(s.textIndent);
	}

	public function textIndentEachLine():Bool
		return t.indentEachLine;

	public function textIndentHanging():Bool
		return t.indentHanging;

	// (an ellipsis where the block clips, or cuts its lines)
	public function textOverflow():InlineTextOverflow
		return s.cuts() ? t.textOverflowEnd : Clip;

	public function lineClamp():Int
		return t.clamp;

	public function verticalAlign():InlineVerticalAlign
		return t.vertical;

	public function verticalShift():Float
		return t.shift;

	// (start and end: left and right in left-to-right text; a split box's parts lack the edges where it goes on)
	inline function startSide():Int
		return s.rtl ? 1 : 3;

	inline function endSide():Int
		return s.rtl ? 3 : 1;

	inline function starts():Bool
		return box.flags & Box.NO_START == 0;

	inline function ends():Bool
		return box.flags & Box.NO_END == 0;

	public function marginStart():Float
		return edges()[0];

	public function marginEnd():Float
		return edges()[1] + markerGap;

	public function borderStart():Float
		return edges()[2];

	public function borderEnd():Float
		return edges()[3];

	public function paddingStart():Float
		return edges()[4];

	public function paddingEnd():Float
		return edges()[5];

	public function marginTop():Float
		return edges()[6];

	public function marginBottom():Float
		return edges()[7];

	public function borderTop():Float
		return edges()[8];

	public function borderBottom():Float
		return edges()[9];

	public function paddingTop():Float
		return edges()[10];

	public function paddingBottom():Float
		return edges()[11];

	// (its margins, borders and paddings: start, end, then top and bottom each)
	function edges():Array<Float> {
		if (edgesValue != null) return edgesValue;
		var st = starts(), en = ends();
		return edgesValue = [
			st ? len(s.margin[startSide()]) : 0, en ? len(s.margin[endSide()]) : 0,
			st ? s.border[startSide()] : 0, en ? s.border[endSide()] : 0,
			st ? len(s.padding[startSide()]) : 0, en ? len(s.padding[endSide()]) : 0,
			len(s.margin[0]), len(s.margin[2]), s.border[0], s.border[2], len(s.padding[0]), len(s.padding[2])
		];
	}

	public function textDecoration():InlineDecoration
		return t.decoration;

	public function textDecorationStyle():InlineDecorationStyle
		return t.decorationStyle;

	public function textDecorationColor():Int
		return t.decorationColour;

	public function textDecorationThickness():Float
		return t.decorationThickness;
}
