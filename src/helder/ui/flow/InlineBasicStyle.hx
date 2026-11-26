package helder.ui.flow;

import helder.text.FontFeature;
import helder.ui.flow.InlineValues;

// InlineStyle as plain fields, CSS's initial values: the tests', and a
// style for what has no computed style of its own. copy() makes one to
// change (styles are compared by identity: a changed style is another).
class InlineBasicStyle implements InlineStyle {
	public var families:Array<String> = ["sans-serif"];
	public var size = 16.0;
	public var weight = 400;
	public var style:InlineFontStyle = Normal;
	public var stretch = 100.0;
	public var variations:Null<Map<String, Float>> = null;
	public var features:Null<Array<FontFeature>> = null;
	public var kerning:InlineKerning = Auto;
	public var ligatures:InlineLigatures = Normal;
	public var colour = 0xFF000000;
	public var height = Math.NaN;
	public var letters = 0.0;
	public var words = 0.0;
	public var transform:InlineTransform = None;
	public var collapse:InlineCollapse = Collapse;
	public var wrap:InlineWrap = Wrap;
	public var tab = 8.0;
	public var breakWord:InlineWordBreak = Normal;
	public var overflow:InlineOverflowWrap = Normal;
	public var breakLine:InlineLineBreak = Auto;
	public var hyphen:InlineHyphens = Manual;
	public var language:Null<String> = null;
	public var dir:InlineDirection = Ltr;
	public var bidi:InlineBidi = Normal;
	public var align:InlineAlign = Start;
	public var alignLast:InlineAlign = Auto;
	public var justify:InlineJustify = Auto;
	public var indent = 0.0;
	public var indentEachLine = false;
	public var indentHanging = false;
	public var textOverflowEnd:InlineTextOverflow = Clip;
	public var clamp = 0;
	public var vertical:InlineVerticalAlign = Baseline;
	public var shift = 0.0;
	public var margins = [0.0, 0.0, 0.0, 0.0];
	public var borders = [0.0, 0.0, 0.0, 0.0];
	public var paddings = [0.0, 0.0, 0.0, 0.0];
	public var decoration:InlineDecoration = None;
	public var decorationStyle:InlineDecorationStyle = Solid;
	public var decorationColour = 0xFF000000;
	public var decorationThickness = Math.NaN;

	public function new() {}

	// a copy, its arrays its own
	public function copy():InlineBasicStyle {
		var s = new InlineBasicStyle();
		s.families = families.copy();
		s.size = size;
		s.weight = weight;
		s.style = style;
		s.stretch = stretch;
		s.variations = variations;
		s.features = features;
		s.kerning = kerning;
		s.ligatures = ligatures;
		s.colour = colour;
		s.height = height;
		s.letters = letters;
		s.words = words;
		s.transform = transform;
		s.collapse = collapse;
		s.wrap = wrap;
		s.tab = tab;
		s.breakWord = breakWord;
		s.overflow = overflow;
		s.breakLine = breakLine;
		s.hyphen = hyphen;
		s.language = language;
		s.dir = dir;
		s.bidi = bidi;
		s.align = align;
		s.alignLast = alignLast;
		s.justify = justify;
		s.indent = indent;
		s.indentEachLine = indentEachLine;
		s.indentHanging = indentHanging;
		s.textOverflowEnd = textOverflowEnd;
		s.clamp = clamp;
		s.vertical = vertical;
		s.shift = shift;
		s.margins = margins.copy();
		s.borders = borders.copy();
		s.paddings = paddings.copy();
		s.decoration = decoration;
		s.decorationStyle = decorationStyle;
		s.decorationColour = decorationColour;
		s.decorationThickness = decorationThickness;
		return s;
	}

	// the same margin, border and padding on every side
	public function edges(margin:Float, border:Float, padding:Float):InlineBasicStyle {
		margins = [margin, margin, margin, margin];
		borders = [border, border, border, border];
		paddings = [padding, padding, padding, padding];
		return this;
	}

	public function fontFamilies()
		return families;

	public function fontSize()
		return size;

	public function fontWeight()
		return weight;

	public function fontStyle()
		return style;

	public function fontStretch()
		return stretch;

	public function fontVariations()
		return variations;

	public function fontFeatures()
		return features;

	public function fontKerning()
		return kerning;

	public function fontLigatures()
		return ligatures;

	public function color()
		return colour;

	public function lineHeight()
		return height;

	public function letterSpacing()
		return letters;

	public function wordSpacing()
		return words;

	public function textTransform()
		return transform;

	public function whiteSpaceCollapse()
		return collapse;

	public function textWrapMode()
		return wrap;

	public function tabSize()
		return tab;

	public function wordBreak()
		return breakWord;

	public function overflowWrap()
		return overflow;

	public function lineBreak()
		return breakLine;

	public function hyphens()
		return hyphen;

	public function lang()
		return language;

	public function direction()
		return dir;

	public function unicodeBidi()
		return bidi;

	public function textAlign()
		return align;

	public function textAlignLast()
		return alignLast;

	public function textJustify()
		return justify;

	public function textIndent()
		return indent;

	public function textIndentEachLine()
		return indentEachLine;

	public function textIndentHanging()
		return indentHanging;

	public function textOverflow()
		return textOverflowEnd;

	public function lineClamp()
		return clamp;

	public function verticalAlign()
		return vertical;

	public function verticalShift()
		return shift;

	public function marginStart()
		return margins[0];

	public function marginEnd()
		return margins[1];

	public function marginTop()
		return margins[2];

	public function marginBottom()
		return margins[3];

	public function borderStart()
		return borders[0];

	public function borderEnd()
		return borders[1];

	public function borderTop()
		return borders[2];

	public function borderBottom()
		return borders[3];

	public function paddingStart()
		return paddings[0];

	public function paddingEnd()
		return paddings[1];

	public function paddingTop()
		return paddings[2];

	public function paddingBottom()
		return paddings[3];

	public function textDecoration()
		return decoration;

	public function textDecorationStyle()
		return decorationStyle;

	public function textDecorationColor()
		return decorationColour;

	public function textDecorationThickness()
		return decorationThickness;
}
