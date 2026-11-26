package helder.ui.flow;

import helder.text.FontFeature;
import helder.ui.flow.InlineValues;

// What the inline formatting context reads of an element's computed style
// (the box tree's styles implement it; InlineBasicStyle is a plain one):
// typed and resolved, lengths in CSS pixels (percentages resolved by the
// implementer, but vertical-align's: verticalShift). InlineContent reads
// each style once, when it is built, so a style may be computed lazily.
// An inline box's edges: its inline start and end (its direction's) margin,
// border and padding, and its border and padding above and below (its
// fragments' rectangles). Styles are compared by identity (interned): two
// items with one style share what is derived from it (its fonts).
interface InlineStyle {
	// font-family's list (generic families by their CSS names)
	function fontFamilies():Array<String>;
	function fontSize():Float;
	function fontWeight():Int;
	function fontStyle():InlineFontStyle;
	// font-stretch, a percentage (100: normal)
	function fontStretch():Float;
	// font-variation-settings (null: none)
	function fontVariations():Null<Map<String, Float>>;
	// font-feature-settings (null: normal)
	function fontFeatures():Null<Array<FontFeature>>;
	function fontKerning():InlineKerning;
	function fontLigatures():InlineLigatures;
	// 0xAARRGGBB
	function color():Int;
	// pixels; NaN: normal (the font's own)
	function lineHeight():Float;
	function letterSpacing():Float;
	function wordSpacing():Float;
	function textTransform():InlineTransform;
	function whiteSpaceCollapse():InlineCollapse;
	function textWrapMode():InlineWrap;
	// tab-size: a number of spaces when positive, else -pixels
	function tabSize():Float;
	function wordBreak():InlineWordBreak;
	function overflowWrap():InlineOverflowWrap;
	function lineBreak():InlineLineBreak;
	function hyphens():InlineHyphens;
	// a BCP 47 tag (null: none)
	function lang():Null<String>;
	function direction():InlineDirection;
	function unicodeBidi():InlineBidi;
	// the block container's (the root's): text-align, text-align-last,
	// text-justify, text-indent (pixels, each-line, hanging), text-overflow,
	// line-clamp's lines (0: none)
	function textAlign():InlineAlign;
	function textAlignLast():InlineAlign;
	function textJustify():InlineJustify;
	function textIndent():Float;
	function textIndentEachLine():Bool;
	function textIndentHanging():Bool;
	// ellipsis only where it applies: the block's overflow is not visible
	function textOverflow():InlineTextOverflow;
	function lineClamp():Int;
	function verticalAlign():InlineVerticalAlign;
	// vertical-align's length (pixels, Length) or percentage (a fraction of the line height, Percent)
	function verticalShift():Float;
	// an inline box's edges
	function marginStart():Float;
	function marginEnd():Float;
	function borderStart():Float;
	function borderEnd():Float;
	function paddingStart():Float;
	function paddingEnd():Float;
	function borderTop():Float;
	function borderBottom():Float;
	function paddingTop():Float;
	function paddingBottom():Float;
	function textDecoration():InlineDecoration;
	function textDecorationStyle():InlineDecorationStyle;
	// 0xAARRGGBB
	function textDecorationColor():Int;
	// pixels; NaN: auto
	function textDecorationThickness():Float;
}
