package helder.ui.box;

import helder.css.CssTerm;
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
		if (box.first == null || box.style.keyword("content") != "normal") return style;
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
		return switch s.terms("font-width") {
			case [Percentage(p)]: p;
			case [Keyword(k)]: helder.text.FontFaces.FontFaceDescriptors.STRETCH.get(k) ?? 100;
			case _: 100;
		}

	public function fontStyleAngle():Float
		return switch s.terms("font-style") {
			case [Keyword("oblique"), Dimension(v, "deg")]: v;
			case [Keyword("oblique"), Dimension(v, "turn")]: v * 360;
			case [Keyword("oblique"), Dimension(v, "rad")]: v * 180 / Math.PI;
			case [Keyword("oblique"), Dimension(v, "grad")]: v * 0.9;
			case _: 14;
		}

	public function fontSynthesis():InlineSynthesis {
		var v = 0;
		if (k("font-synthesis-weight") != "none") v |= InlineSynthesis.Weight;
		switch k("font-synthesis-style") {
			case "none":
			case "oblique-only": v |= InlineSynthesis.Oblique;
			case _: v |= InlineSynthesis.Style | InlineSynthesis.Oblique;
		}
		return v;
	}

	public function fontOpticalSizing():Bool
		return k("font-optical-sizing") != "none";

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

	// font-variant-caps, -numeric, -east-asian, -position and historical-forms
	// as their features, font-feature-settings' over them (CSS Fonts 4 §7.2)
	public function fontFeatures():Null<Array<FontFeature>> {
		var out = variants(), asked = settings();
		if (asked != null)
			for (f in asked) {
				for (o in out.copy())
					if (o.tag == f.tag) out.remove(o);
				out.push(f);
			}
		return out.length == 0 ? null : out;
	}

	function variants():Array<FontFeature> {
		var out:Array<FontFeature> = [];
		inline function on(tags:Array<String>)
			for (t in tags) out.push({tag: t, value: 1});
		for (p in ["font-variant-caps", "font-variant-numeric", "font-variant-east-asian", "font-variant-position", "font-variant-alternates"])
			for (t in s.terms(p)) switch t {
				case Keyword(v): on(VARIANTS.get(v) ?? []);
				case _:
			}
		return out;
	}

	static final VARIANTS = [
		"small-caps" => ["smcp"], "all-small-caps" => ["smcp", "c2sc"], "petite-caps" => ["pcap"], "all-petite-caps" => ["pcap", "c2pc"],
		"unicase" => ["unic"], "titling-caps" => ["titl"], "lining-nums" => ["lnum"], "oldstyle-nums" => ["onum"], "proportional-nums" => ["pnum"],
		"tabular-nums" => ["tnum"], "diagonal-fractions" => ["frac"], "stacked-fractions" => ["afrc"], "ordinal" => ["ordn"], "slashed-zero" => ["zero"],
		"jis78" => ["jp78"], "jis83" => ["jp83"], "jis90" => ["jp90"], "jis04" => ["jp04"], "simplified" => ["smpl"], "traditional" => ["trad"],
		"full-width" => ["fwid"], "proportional-width" => ["pwid"], "ruby" => ["ruby"], "sub" => ["subs"], "super" => ["sups"], "historical-forms" => ["hist"]
	];

	function settings():Null<Array<FontFeature>> {
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

	public function fontEmoji():InlineEmoji
		return switch k("font-variant-emoji") {
			case "text": Text;
			case "emoji": Emoji;
			case "unicode": Unicode;
			case _: Normal;
		}

	public function color():Int
		return s.color("color");

	public function lineHeight():Float {
		if (lineHeightRead) return lineHeightValue;
		lineHeightRead = true;
		return lineHeightValue = switch s.terms("line-height") {
			case [Dimension(v, "px")]: v;
			case [Number(n, _)]: n * fontSize();
			case [Percentage(p)]: p * fontSize() / 100;
			case _: Math.NaN;
		}
	}

	// (lineHeight's, read once: a style's)
	var lineHeightRead = false;
	var lineHeightValue = Math.NaN;

	// (none in a list marker: browsers leave a marker's text unspaced)
	public function letterSpacing():Float
		return box.markerPseudo() ? 0 : s.px("letter-spacing");

	public function wordSpacing():Float
		return box.markerPseudo() ? 0 : s.px("word-spacing");

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
		var b = box;
		while (b != null) {
			if (b.lang != null) return b.lang;
			b = b.parent;
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
		return alignValue ??= box.markerPseudo() ? Start : align(k("text-align-all"), Start);

	public function textAlignLast():InlineAlign
		return alignLastValue ??= box.markerPseudo() ? Auto : align(k("text-align-last"), Auto);

	// (what the line builder asks each line and each box it places: read once, a style's and a width's)
	var alignValue:Null<InlineAlign> = null;
	var alignLastValue:Null<InlineAlign> = null;
	var justifyValue:Null<InlineJustify> = null;
	var indentValue = Math.NaN;
	var indentFlags = -1;
	var overflowValue:Null<InlineTextOverflow> = null;
	var clampValue = -1;
	var verticalValue:Null<InlineVerticalAlign> = null;
	var edgesValue:Null<Array<Float>> = null;

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
		return justifyValue ??= switch k("text-justify") {
			case "none": None;
			case "inter-word": InterWord;
			case "inter-character": InterCharacter;
			case _: Auto;
		}

	// (none in a list marker's own line: its item's indent is its item's text's)
	public function textIndent():Float {
		if (indentValue == indentValue) return indentValue;
		return indentValue = box.markerPseudo() ? 0 : len(box.style.len("text-indent"));
	}

	public function textIndentEachLine():Bool
		return indent() & 1 != 0;

	public function textIndentHanging():Bool
		return indent() & 2 != 0;

	function indent():Int {
		if (indentFlags >= 0) return indentFlags;
		var t = s.terms("text-indent");
		return indentFlags = (t.contains(Keyword("each-line")) ? 1 : 0) | (t.contains(Keyword("hanging")) ? 2 : 0);
	}

	public function textOverflow():InlineTextOverflow {
		if (overflowValue != null) return overflowValue;
		if (!s.clips) return overflowValue = Clip;
		var t = s.terms("text-overflow");
		return overflowValue = t.length > 0 && t[t.length - 1].match(Keyword("ellipsis")) ? Ellipsis : Clip;
	}

	public function lineClamp():Int {
		if (clampValue >= 0) return clampValue;
		return clampValue = switch s.terms("line-clamp") {
			case [Number(n, _)]: Std.int(n);
			case _: 0;
		}
	}

	public function verticalAlign():InlineVerticalAlign
		return verticalValue ??= switch box.style.verticalAlign().kind {
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
