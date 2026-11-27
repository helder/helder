package helder.ui.flow;

// The typed values InlineStyle gives, one per CSS property it reads (their
// keywords as CSS names them). `import helder.ui.flow.InlineValues;` imports all.

// white-space-collapse
enum abstract InlineCollapse(Int) {
	var Collapse;
	var Discard;
	var Preserve;
	var PreserveBreaks;
	var PreserveSpaces;
	var BreakSpaces;
}

// text-wrap-mode
enum abstract InlineWrap(Int) {
	var Wrap;
	var NoWrap;
}

// word-break (auto-phrase as normal; break-word as normal with overflow-wrap: anywhere)
enum abstract InlineWordBreak(Int) {
	var Normal;
	var BreakAll;
	var KeepAll;
	var BreakWord;
}

// overflow-wrap
enum abstract InlineOverflowWrap(Int) {
	var Normal;
	var BreakWord;
	var Anywhere;
}

// line-break
enum abstract InlineLineBreak(Int) {
	var Auto;
	var Loose;
	var Normal;
	var Strict;
	var Anywhere;
}

// hyphens
enum abstract InlineHyphens(Int) {
	var None;
	var Manual;
	var Auto;
}

// direction
enum abstract InlineDirection(Int) to Int {
	var Ltr;
	var Rtl;
}

// unicode-bidi
enum abstract InlineBidi(Int) {
	var Normal;
	var Embed;
	var Isolate;
	var BidiOverride;
	var IsolateOverride;
	var Plaintext;
}

// text-align, text-align-last (Auto: text-align-last's own, text-align's
// value but justify's start)
enum abstract InlineAlign(Int) {
	var Start;
	var End;
	var Left;
	var Right;
	var Center;
	var Justify;
	var MatchParent;
	var Auto;
}

// text-justify
enum abstract InlineJustify(Int) {
	var Auto;
	var None;
	var InterWord;
	var InterCharacter;
}

// vertical-align (its baseline-shift keyword or length: Length raises by
// verticalShift's pixels, Percent by that fraction of the line height)
enum abstract InlineVerticalAlign(Int) {
	var Baseline;
	var Sub;
	var Super;
	var TextTop;
	var TextBottom;
	var Middle;
	var Top;
	var Bottom;
	var Length;
	var Percent;
}

// text-transform, added up (one of the case's, full-width, full-size-kana)
enum abstract InlineTransform(Int) from Int to Int {
	var None = 0;
	var Capitalize = 1;
	var Uppercase = 2;
	var Lowercase = 3;
	var FullWidth = 4;
	var FullSizeKana = 8;
	public static inline var CASE = 3;
}

// font-style
enum abstract InlineFontStyle(Int) {
	var Normal;
	var Italic;
	var Oblique;
}

// font-kerning
enum abstract InlineKerning(Int) {
	var Auto;
	var Normal;
	var None;
}

// font-synthesis's longhands, added up: what may be synthesized (font-synthesis-style: oblique-only, Oblique alone)
enum abstract InlineSynthesis(Int) from Int to Int {
	var None = 0;
	var Weight = 1;
	var Style = 2;
	var Oblique = 4;
	var All = 7;
}

// font-variant-emoji (helder.text.FontSet's presentations, in its order)
enum abstract InlineEmoji(Int) to Int {
	var Normal = 0;
	var Text = 1;
	var Emoji = 2;
	var Unicode = 3;
}

// font-variant-ligatures, added up (what is turned off or on; 0: normal)
enum abstract InlineLigatures(Int) from Int to Int {
	var Normal = 0;
	var NoCommon = 1;
	var NoContextual = 2;
	var Discretionary = 4;
	var Historical = 8;
	// none: all of them off
	var None = 16;
}

// text-decoration-line, added up
enum abstract InlineDecoration(Int) from Int to Int {
	var None = 0;
	var Underline = 1;
	var Overline = 2;
	var LineThrough = 4;
}

// text-decoration-style
enum abstract InlineDecorationStyle(Int) {
	var Solid;
	var Double;
	var Dotted;
	var Dashed;
	var Wavy;
}

// text-overflow (its end side)
enum abstract InlineTextOverflow(Int) {
	var Clip;
	var Ellipsis;
}
