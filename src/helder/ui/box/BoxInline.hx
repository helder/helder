package helder.ui.box;

import helder.css.CssTerm;
import helder.text.FontFeature;
import helder.ui.box.Len.Lens;
import helder.ui.flow.InlineStyle;
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

	inline function k(p:String):String
		return s.keyword(p);

	function len(l:Len):Float {
		var v = Lens.resolve(l, cb, 0);
		return Math.isNaN(v) ? 0 : v;
	}

	public function fontFamilies():Array<String>
		return box.style.families();

	public function fontSize():Float
		return s.css.fontSize();

	public function fontWeight():Int
		return Std.int(s.number("font-weight", 400));

	public function fontStyle():InlineFontStyle
		return switch k("font-style") {
			case "italic": Italic;
			case "oblique": Oblique;
			case _: switch s.terms("font-style") {
					case [Keyword("oblique"), _]: Oblique;
					case _: Normal;
				}
		}

	public function fontStretch():Float
		return switch s.terms("font-stretch") {
			case [Percentage(p)]: p;
			case _: 100;
		}

	public function fontVariations():Null<Map<String, Float>> {
		var t = s.terms("font-variation-settings");
		if (t.length == 0 || t[0].match(Keyword("normal"))) return null;
		var out = new Map<String, Float>(), tag:Null<String> = null;
		for (x in t) switch x {
			case Str(v): tag = v;
			case Number(v, _) if (tag != null): out.set(tag, v);
			case _:
		}
		return out;
	}

	public function fontFeatures():Null<Array<FontFeature>> {
		var t = s.terms("font-feature-settings");
		if (t.length == 0 || t[0].match(Keyword("normal"))) return null;
		var text = [for (x in t) switch x {
			case Str(v): "'" + v + "'";
			case Number(v, _): Std.string(Std.int(v));
			case Keyword(v): v;
			case Delim(","): ",";
			case _: "";
		}].join(" ").replace(" ,", ",");
		return FontFeature.parse(text);
	}

	public function fontKerning():InlineKerning
		return switch k("font-kerning") {
			case "normal": Normal;
			case "none": None;
			case _: Auto;
		}

	public function fontLigatures():InlineLigatures {
		var v = 0;
		for (t in s.terms("font-variant-ligatures")) switch t {
			case Keyword("none"): v |= InlineLigatures.None;
			case Keyword("no-common-ligatures"): v |= InlineLigatures.NoCommon;
			case Keyword("no-contextual"): v |= InlineLigatures.NoContextual;
			case Keyword("discretionary-ligatures"): v |= InlineLigatures.Discretionary;
			case Keyword("historical-ligatures"): v |= InlineLigatures.Historical;
			case _:
		}
		return v;
	}

	public function color():Int
		return s.color("color");

	public function lineHeight():Float
		return switch s.terms("line-height") {
			case [Dimension(v, "px")]: v;
			case [Number(n, _)]: n * fontSize();
			case [Percentage(p)]: p * fontSize() / 100;
			case _: Math.NaN;
		}

	// (none in a list marker: browsers leave a marker's text unspaced)
	public function letterSpacing():Float
		return box.pseudo == "marker" ? 0 : s.px("letter-spacing");

	public function wordSpacing():Float
		return box.pseudo == "marker" ? 0 : s.px("word-spacing");

	public function textTransform():InlineTransform {
		var v = 0;
		for (t in s.terms("text-transform")) switch t {
			case Keyword("capitalize"): v |= InlineTransform.Capitalize;
			case Keyword("uppercase"): v |= InlineTransform.Uppercase;
			case Keyword("lowercase"): v |= InlineTransform.Lowercase;
			case Keyword("full-width"): v |= InlineTransform.FullWidth;
			case Keyword("full-size-kana"): v |= InlineTransform.FullSizeKana;
			case _:
		}
		return v;
	}

	public function whiteSpaceCollapse():InlineCollapse
		return switch k("white-space-collapse") {
			case "discard": Discard;
			case "preserve": Preserve;
			case "preserve-breaks": PreserveBreaks;
			case "preserve-spaces": PreserveSpaces;
			case "break-spaces": BreakSpaces;
			case _: Collapse;
		}

	public function textWrapMode():InlineWrap
		return k("text-wrap-mode") == "nowrap" ? NoWrap : Wrap;

	public function tabSize():Float
		return switch s.terms("tab-size") {
			case [Number(n, _)]: n;
			case [Dimension(v, _)]: -v;
			case _: 8;
		}

	public function wordBreak():InlineWordBreak
		return switch k("word-break") {
			case "break-all": BreakAll;
			case "keep-all": KeepAll;
			case "break-word": BreakWord;
			case _: Normal;
		}

	public function overflowWrap():InlineOverflowWrap
		return switch k("overflow-wrap") {
			case "break-word": BreakWord;
			case "anywhere": Anywhere;
			case _: Normal;
		}

	public function lineBreak():InlineLineBreak
		return switch k("line-break") {
			case "loose": Loose;
			case "normal": Normal;
			case "strict": Strict;
			case "anywhere": Anywhere;
			case _: Auto;
		}

	public function hyphens():InlineHyphens
		return switch k("hyphens") {
			case "none": None;
			case "auto": Auto;
			case _: Manual;
		}

	public function lang():Null<String> {
		var n = box.node;
		while (n != null) {
			if (n.nodeType == helder.dom.Node.ELEMENT_NODE) {
				var el:helder.dom.Element = cast n;
				var l = el.getAttribute("lang") ?? el.getAttributeNS("http://www.w3.org/XML/1998/namespace", "lang");
				if (l != null) return l;
			}
			n = n.parentNode;
		}
		return null;
	}

	public function direction():InlineDirection
		return s.rtl ? Rtl : Ltr;

	public function unicodeBidi():InlineBidi
		return switch k("unicode-bidi") {
			case "embed": Embed;
			case "isolate": Isolate;
			case "bidi-override": BidiOverride;
			case "isolate-override": IsolateOverride;
			case "plaintext": Plaintext;
			case _: Normal;
		}

	// (a list marker's text is its own, at its start whatever its item's alignment)
	public function textAlign():InlineAlign
		return box.pseudo == "marker" ? Start : align(k("text-align-all"), Start);

	public function textAlignLast():InlineAlign
		return box.pseudo == "marker" ? Auto : align(k("text-align-last"), Auto);

	static function align(v:String, fallback:InlineAlign):InlineAlign
		return switch v {
			case "start": Start;
			case "end": End;
			case "left" | "-webkit-left": Left;
			case "right" | "-webkit-right": Right;
			case "center" | "-webkit-center": Center;
			case "justify": Justify;
			case "match-parent": MatchParent;
			case "auto": Auto;
			case _: fallback;
		}

	public function textJustify():InlineJustify
		return switch k("text-justify") {
			case "none": None;
			case "inter-word": InterWord;
			case "inter-character": InterCharacter;
			case _: Auto;
		}

	public function textIndent():Float
		return len(box.style.len("text-indent"));

	public function textIndentEachLine():Bool
		return s.terms("text-indent").contains(Keyword("each-line"));

	public function textIndentHanging():Bool
		return s.terms("text-indent").contains(Keyword("hanging"));

	public function textOverflow():InlineTextOverflow {
		if (!s.clips) return Clip;
		var t = s.terms("text-overflow");
		return t.length > 0 && t[t.length - 1].match(Keyword("ellipsis")) ? Ellipsis : Clip;
	}

	public function lineClamp():Int
		return switch s.terms("line-clamp") {
			case [Number(n, _)]: Std.int(n);
			case _: 0;
		}

	public function verticalAlign():InlineVerticalAlign
		return switch box.style.verticalAlign().kind {
			case "sub": Sub;
			case "super": Super;
			case "text-top": TextTop;
			case "text-bottom": TextBottom;
			case "middle": Middle;
			case "top": Top;
			case "bottom": Bottom;
			case "length": Length;
			case "percent": Percent;
			case _: Baseline;
		}

	public function verticalShift():Float {
		var v = box.style.verticalAlign();
		return v.kind == "percent" ? v.shift / 100 : v.shift;
	}

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
		return starts() ? len(s.margin[startSide()]) : 0;

	public function marginEnd():Float
		return ends() ? len(s.margin[endSide()]) : 0;

	public function borderStart():Float
		return starts() ? s.border[startSide()] : 0;

	public function borderEnd():Float
		return ends() ? s.border[endSide()] : 0;

	public function paddingStart():Float
		return starts() ? len(s.padding[startSide()]) : 0;

	public function paddingEnd():Float
		return ends() ? len(s.padding[endSide()]) : 0;

	public function marginTop():Float
		return len(s.margin[0]);

	public function marginBottom():Float
		return len(s.margin[2]);

	public function borderTop():Float
		return s.border[0];

	public function borderBottom():Float
		return s.border[2];

	public function paddingTop():Float
		return len(s.padding[0]);

	public function paddingBottom():Float
		return len(s.padding[2]);

	public function textDecoration():InlineDecoration {
		var v = 0;
		for (t in s.terms("text-decoration-line")) switch t {
			case Keyword("underline"): v |= InlineDecoration.Underline;
			case Keyword("overline"): v |= InlineDecoration.Overline;
			case Keyword("line-through"): v |= InlineDecoration.LineThrough;
			case _:
		}
		return v;
	}

	public function textDecorationStyle():InlineDecorationStyle
		return switch k("text-decoration-style") {
			case "double": Double;
			case "dotted": Dotted;
			case "dashed": Dashed;
			case "wavy": Wavy;
			case _: Solid;
		}

	public function textDecorationColor():Int
		return switch s.terms("text-decoration-color") {
			case [Color(c)]: BoxStyle.argb(c, color());
			case _: color();
		}

	public function textDecorationThickness():Float
		return switch s.terms("text-decoration-thickness") {
			case [Dimension(v, _)]: v;
			case [Percentage(p)]: p * fontSize() / 100;
			case _: Math.NaN;
		}
}
