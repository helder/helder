package helder.ui.box;

import helder.css.CssContain;
import helder.css.CssColors;
import helder.css.CssTerm;
import helder.ui.box.Len;
import helder.ui.box.Len.Lens;
import helder.ui.flow.InlineBasicStyle;

using StringTools;

// What layout and paint read of a box's computed style, typed: its
// display, its box model, its text part (what inline layout and fonts
// read), what paint reads, flex and alignment, the traits every box is
// asked, and what few boxes have apart (BoxRare). A record whose values
// are CSS's initial ones until set: by code (a box made from code), or
// read, a part at a time when first asked, from the cascade's computed
// style (CssBoxStyle, the one place that knows how helder.css stores it),
// so that a program whose boxes are all made from code links no cascade.
// An anonymous box's style is its parent's inherited values and the
// initial ones (CSS 2.1 §9.2.1.1).
@:allow(helder.ui)
class BoxStyle {
	public final anonymous:Bool;
	// (its InlineStyles by split edges, BoxInline.of's)
	@:allow(helder.ui.box.BoxInline) final inlines:Array<Null<BoxInline>> = [null, null, null, null];

	public function new(anonymous = false) {
		this.anonymous = anonymous;
	}

	// the cascade's computed style it was read from (null: made from code)
	public var css(get, never):Null<helder.css.CssStyle>;

	function get_css():Null<helder.css.CssStyle>
		return null;

	// (how far it paints past its box, BoxPainter.reach's: kept once known; NaN until then)
	@:allow(helder.ui.box) var reach = Math.NaN;

	// An anonymous child's: its inherited values (the text part), the initial ones for the rest.
	public function anonymousChild():BoxStyle {
		var s = new BoxStyle(true);
		s.textPart = text;
		s.traits = traits < 0 ? -1 : traits & (RTL | VISIBLE | COLLAPSE | BREAKS | WRAPS);
		return s;
	}

	// An anonymous box of a table's display (CSS 2.1 §17.2.1): its parent's inherited values.
	public function anonymousTable(inner:Int, part:Int, outer = BLOCK):BoxStyle {
		var s = anonymousChild();
		s.displayRead = true;
		s.displayInner = inner;
		s.displayPart = part;
		s.displayOuter = outer;
		return s;
	}

	// (whether it draws text decorations: text-decoration-line not none)
	public function decorates():Bool
		return text.decoration != 0;

	// A CSS colour value as 0xAARRGGBB, currentcolor as current.
	public static function argb(c:helder.css.CssColors.CssColorValue, current:Int):Int {
		switch c.keyword {
			case "currentcolor": return current;
			case "transparent": return 0;
			case null:
			case k:
				var s = CssColors.system(k);
				if (s != null) return (Math.round(s[3] * c.alpha * 255) << 24) | (Std.int(s[0]) << 16) | (Std.int(s[1]) << 8) | Std.int(s[2]);
		}
		var rgb:Array<Float> = switch c.space {
			case "rgb" | "hsl" | "hwb": CssColors.srgb(c);
			case "srgb": [for (x in c.c) x * 255];
			case _: null;
		}
		if (rgb == null || rgb.length < 3) return 0xFF000000;
		inline function byte(x:Float):Int {
			var v = Math.round(Math.isNaN(x) ? 0 : x);
			return v < 0 ? 0 : v > 255 ? 255 : v;
		}
		var a = byte((Math.isNaN(c.alpha) ? 0 : c.alpha) * 255);
		return (a << 24) | (byte(rgb[0]) << 16) | (byte(rgb[1]) << 8) | byte(rgb[2]);
	}

	// A length's terms as a Len: a dimension or number its px, a percentage, a calc(), the first length among
	// keywords; else Auto.
	public static function toLen(t:Array<CssTerm>):Len
		return BoxRare.toLen(t);

	// ---- display (Display 3: outer and inner)

	public static inline var BLOCK = 0;
	public static inline var INLINE = 1;

	public static inline var FLOW = 0;
	public static inline var FLOW_ROOT = 1;
	public static inline var TABLE = 2;
	public static inline var FLEX = 3;
	public static inline var GRID = 4;
	// (table-row, table-cell and the other internal displays: which one, `part`)
	public static inline var TABLE_PART = 5;

	public static inline var ROW_GROUP = 1;
	public static inline var HEADER_GROUP = 2;
	public static inline var FOOTER_GROUP = 3;
	public static inline var ROW = 4;
	public static inline var CELL = 5;
	public static inline var COLUMN_GROUP = 6;
	public static inline var COLUMN = 7;
	public static inline var CAPTION = 8;

	var displayRead = false;
	var displayNone = false;
	var displayContents = false;
	var displayList = false;
	var displayOuter = 0;
	var displayInner = 0;
	var displayPart = 0;
	// (the display it had before being blockified (a flex or grid item's): its outer one)
	var originalOuter = 0;

	public var none(get, never):Bool;
	public var contents(get, never):Bool;
	public var listItem(get, never):Bool;
	public var outer(get, never):Int;
	public var inner(get, never):Int;
	// a table part's display (ROW, CELL...), else 0
	public var part(get, never):Int;

	function get_part():Int {
		display();
		return displayPart;
	}

	function get_none():Bool {
		display();
		return displayNone;
	}

	function get_contents():Bool {
		display();
		return displayContents;
	}

	function get_listItem():Bool {
		display();
		return displayList;
	}

	function get_outer():Int {
		display();
		return displayOuter;
	}

	function get_inner():Int {
		display();
		return displayInner;
	}

	// the outer display it had before being blockified (BLOCK or INLINE)
	public var originalDisplayOuter(get, never):Int;

	function get_originalDisplayOuter():Int {
		display();
		return originalOuter;
	}

	function display() {
		if (displayRead) return;
		displayRead = true;
		readDisplay();
	}

	// (the cascade's display: CssBoxStyle's; here a block's, or what code set)
	function readDisplay() {}

	// ---- the text part: what inline layout and fonts read of it, typed
	// (InlineBasicStyle's fields; its edges, lang and direction the box's,
	// BoxInline's), read once. text-indent apart: a percentage of the
	// containing block's width.

	var textPart:Null<InlineBasicStyle> = null;
	var indentLen = Len.Auto;

	public var text(get, never):InlineBasicStyle;
	public var textIndent(get, never):Len;

	inline function get_text():InlineBasicStyle
		return textPart ??= readText();

	inline function get_textIndent():Len {
		if (textPart == null) textPart = readText();
		return indentLen;
	}

	// (the cascade's text part: CssBoxStyle's; here the initial one)
	function readText():InlineBasicStyle
		return new InlineBasicStyle();

	// font-family's names, generic ones as their keywords, a quoted name that is one ("serif") in its quotes
	public inline function families():Array<String>
		return text.families;

	// ---- paint's: the background, the corners' radii, the borders' styles and
	// colours, box shadows and the outline, read once (paint reads them per
	// box and per frame, its terms parsed no more)

	var paintRead = false;
	var bgColor = 0;
	var bgParts:Null<BackgroundParts> = null;
	var bgClip = "border-box";
	var radiusTerms:Null<Array<CssTerm>> = null;
	final sideStyles:Array<String> = [];
	final sideColors:Array<Int> = [];
	var shadowList:Null<Array<BoxShadow>> = null;
	var outlineStyleValue = "";
	var outlineWidthValue = 0.0;
	var outlineOffsetValue = 0.0;
	var outlineColorValue = 0;

	// Its paint and box model written into another (made if null): a node's own while a motion moves its
	// background, border colour or radius (helder.ui.NodePaint), the values over it, nothing interned.
	public function paintInto(into:Null<BoxStyle>, bg:Int, borderColor:Int, radius:Float):BoxStyle {
		var s = into ?? new BoxStyle();
		if (!paintRead) readPaint();
		model();
		s.textPart = text;
		s.traits = traits;
		s.modelRead = true;
		s.margin.resize(0);
		s.padding.resize(0);
		s.border.resize(0);
		for (k in 0...4) {
			s.margin.push(margin[k]);
			s.padding.push(padding[k]);
			s.border.push(border[k]);
		}
		s.paintRead = true;
		s.bgColor = bg;
		s.bgParts = bgParts;
		s.bgClip = bgClip;
		s.radiusTerms = radius != radius ? radiusTerms : radius > 0 ? [for (_ in 0...8) Dimension(radius, "px")] : null;
		s.sideStyles.resize(0);
		s.sideColors.resize(0);
		for (k in 0...4) {
			s.sideStyles.push(sideStyles[k]);
			s.sideColors.push(borderColor);
		}
		s.shadowList = shadowList;
		s.outlineStyleValue = outlineStyleValue;
		s.outlineWidthValue = outlineWidthValue;
		s.outlineOffsetValue = outlineOffsetValue;
		s.outlineColorValue = outlineColorValue;
		s.opacityValue = opacityValue;
		return s;
	}

	// (the cascade's paint part: CssBoxStyle's; here its initial values, or what code set)
	function readPaint() {
		paintRead = true;
		if (sideStyles.length == 0) for (_ in 0...4) {
			sideStyles.push("none");
			sideColors.push(0);
		}
	}

	// background-color, and its layers' lists apart (null: no image)
	public var backgroundColor(get, never):Int;
	public var background(get, never):Null<BackgroundParts>;
	// (the background colour's clip box: the bottom layer's background-clip)
	public var backgroundClip(get, never):String;
	// the corners' radii as written, horizontal and vertical each, top-left first (null: square corners)
	public var radii(get, never):Null<Array<CssTerm>>;
	// box-shadow's shadows, the first on top (null: none)
	public var shadows(get, never):Null<Array<BoxShadow>>;
	public var outlineStyle(get, never):String;
	public var outlineWidth(get, never):Float;
	public var outlineOffset(get, never):Float;
	public var outlineColor(get, never):Int;

	// a side's border style and colour (top, right, bottom, left)
	public inline function borderStyle(side:Int):String {
		if (!paintRead) readPaint();
		return sideStyles[side];
	}

	public inline function borderColor(side:Int):Int {
		if (!paintRead) readPaint();
		return sideColors[side];
	}

	inline function get_backgroundColor():Int {
		if (!paintRead) readPaint();
		return bgColor;
	}

	inline function get_backgroundClip():String {
		if (!paintRead) readPaint();
		return bgClip;
	}

	inline function get_background():Null<BackgroundParts> {
		if (!paintRead) readPaint();
		return bgParts;
	}

	inline function get_radii():Null<Array<CssTerm>> {
		if (!paintRead) readPaint();
		return radiusTerms;
	}

	inline function get_shadows():Null<Array<BoxShadow>> {
		if (!paintRead) readPaint();
		return shadowList;
	}

	inline function get_outlineStyle():String {
		if (!paintRead) readPaint();
		return outlineStyleValue;
	}

	inline function get_outlineWidth():Float {
		if (!paintRead) readPaint();
		return outlineWidthValue;
	}

	inline function get_outlineOffset():Float {
		if (!paintRead) readPaint();
		return outlineOffsetValue;
	}

	inline function get_outlineColor():Int {
		if (!paintRead) readPaint();
		return outlineColorValue;
	}

	// ---- flex, alignment, gaps, insets, float and clear: read once (layout
	// reads them per item and per pass, by name no more)

	var layoutRead = false;
	var orderValue = 0;
	var growValue = 0.0;
	var shrinkValue = 1.0;
	var basisValue = Len.Auto;
	var basisWord = "auto";
	var directionValue = "row";
	var wrapValue = "nowrap";
	final aligns:Array<String> = [];
	var rowGapValue = Len.Auto;
	var columnGapValue = Len.Auto;
	final insets:Array<Len> = [];
	var floatValue = "";
	var clearValue = "";

	// (the cascade's layout part: CssBoxStyle's; here its initial values, or what code set)
	function readLayout() {
		layoutRead = true;
		if (aligns.length == 0) for (v in ["normal", "normal", "normal", "auto", "legacy", "auto"]) aligns.push(v);
		if (insets.length == 0) for (_ in 0...4) insets.push(Len.Auto);
	}

	public var order(get, never):Int;
	public var flexGrow(get, never):Float;
	public var flexShrink(get, never):Float;
	// flex-basis: a length or percentage (Auto: auto or a keyword), and its keyword ("": a length's)
	public var flexBasis(get, never):Len;
	public var flexBasisKeyword(get, never):String;
	public var flexDirection(get, never):String;
	public var flexWrap(get, never):String;
	// the alignment properties as written (a keyword, else its words: "safe center", "first baseline")
	public var justifyContent(get, never):String;
	public var alignContent(get, never):String;
	public var alignItems(get, never):String;
	public var alignSelf(get, never):String;
	public var justifyItems(get, never):String;
	public var justifySelf(get, never):String;
	// row-gap and column-gap (Auto: normal)
	public var rowGap(get, never):Len;
	public var columnGap(get, never):Len;
	// float's and clear's keywords
	public var floatSide(get, never):String;
	public var clearSide(get, never):String;

	// top, right, bottom or left (0 to 3)
	public inline function inset(side:Int):Len {
		if (!layoutRead) readLayout();
		return insets[side];
	}

	inline function get_order():Int {
		if (!layoutRead) readLayout();
		return orderValue;
	}

	inline function get_flexGrow():Float {
		if (!layoutRead) readLayout();
		return growValue;
	}

	inline function get_flexShrink():Float {
		if (!layoutRead) readLayout();
		return shrinkValue;
	}

	inline function get_flexBasis():Len {
		if (!layoutRead) readLayout();
		return basisValue;
	}

	inline function get_flexBasisKeyword():String {
		if (!layoutRead) readLayout();
		return basisWord;
	}

	inline function get_flexDirection():String {
		if (!layoutRead) readLayout();
		return directionValue;
	}

	inline function get_flexWrap():String {
		if (!layoutRead) readLayout();
		return wrapValue;
	}

	inline function alignment(k:Int):String {
		if (!layoutRead) readLayout();
		return aligns[k];
	}

	inline function get_justifyContent():String
		return alignment(0);

	inline function get_alignContent():String
		return alignment(1);

	inline function get_alignItems():String
		return alignment(2);

	inline function get_alignSelf():String
		return alignment(3);

	inline function get_justifyItems():String
		return alignment(4);

	inline function get_justifySelf():String
		return alignment(5);

	inline function get_rowGap():Len {
		if (!layoutRead) readLayout();
		return rowGapValue;
	}

	inline function get_columnGap():Len {
		if (!layoutRead) readLayout();
		return columnGapValue;
	}

	inline function get_floatSide():String {
		if (!layoutRead) readLayout();
		return floatValue;
	}

	inline function get_clearSide():String {
		if (!layoutRead) readLayout();
		return clearValue;
	}

	// ---- the box model, read once

	var modelRead = false;

	public final margin:Array<Len> = [];
	public final padding:Array<Len> = [];
	// top, right, bottom, left; 0 under a none or hidden style (the cascade's)
	public final border:Array<Float> = [];

	// a side's (0 top, 1 right, 2 bottom, 3 left) padding in px where it is a length (a percentage's 0: no box here)
	public function paddingPx(side:Int):Float {
		model();
		return switch padding[side] {
			case Px(v): v;
			case _: 0;
		}
	}

	// a side's border width
	public inline function borderPx(side:Int):Float {
		model();
		return border[side];
	}

	// its border's widths and its padding as edges (top, right, bottom, left; horizontal, vertical), made once
	public var borderEdges(get, never):helder.os.Edges;
	public var paddingEdges(get, never):helder.os.Edges;

	var bordersKept:Null<helder.os.Edges> = null;
	var paddingsKept:Null<helder.os.Edges> = null;

	function get_borderEdges():helder.os.Edges
		return bordersKept ??= new helder.os.Edges(borderPx(0), borderPx(1), borderPx(2), borderPx(3));

	function get_paddingEdges():helder.os.Edges
		return paddingsKept ??= new helder.os.Edges(paddingPx(0), paddingPx(1), paddingPx(2), paddingPx(3));

	// its border and padding across the axis: horizontal (left and right) or vertical
	public function edgesAcross(x:Bool):Float
		return x ? borderPx(1) + borderPx(3) + paddingPx(1) + paddingPx(3) : borderPx(0) + borderPx(2) + paddingPx(0) + paddingPx(2);
	public var width(default, null) = Len.Auto;
	public var height(default, null) = Len.Auto;
	public var minWidth(default, null) = Len.Auto;
	public var minHeight(default, null) = Len.Auto;
	// Auto: none
	public var maxWidth(default, null) = Len.Auto;
	public var maxHeight(default, null) = Len.Auto;
	public var borderBox(default, null) = false;
	// aspect-ratio's width / height (NaN: auto, or degenerate); auto: natural
	// ratio first, a replaced element's
	public var ratio(default, null) = Math.NaN;
	public var ratioAuto(default, null) = true;

	public function model():BoxStyle {
		if (modelRead) return this;
		modelRead = true;
		readModel();
		return this;
	}

	// (the cascade's box model: CssBoxStyle's; here the initial one (none, zero, auto), or what code set)
	function readModel() {
		if (margin.length > 0) return;
		for (_ in 0...4) {
			margin.push(Px(0));
			padding.push(Px(0));
			border.push(0);
		}
	}

	// ---- the traits every box is asked, read once: a bit each, position's keyword

	var traits = -1;
	var positionWord = "static";
	// (overflow-x's and overflow-y's keywords, read with the traits)
	var overflowXWord = "visible";
	var overflowYWord = "visible";

	static inline var FLOATING = 1;
	static inline var CLIPS = 2;
	static inline var RTL = 4;
	static inline var VISIBLE = 8;
	static inline var COLLAPSE = 16;
	static inline var BREAKS = 32;
	static inline var WRAPS = 64;
	// (overflow scroll or auto on either axis; hidden on either; a transform; a stacking context; content-visibility: hidden)
	static inline var SCROLLS = 128;
	static inline var HIDDEN_OVERFLOW = 256;
	static inline var MOVED = 512;
	static inline var STACKS = 1024;
	static inline var CONTENT_HIDDEN = 2048;
	// (its lines cut with an ellipsis without clipping: a fast text's, whose lines alone are in it)
	static inline var CUTS = 4096;

	inline function trait(bit:Int):Bool {
		if (traits < 0) traits = readTraits();
		return traits & bit != 0;
	}

	// (the cascade's traits: CssBoxStyle's; here the initial ones, visible text that collapses and wraps)
	function readTraits():Int
		return VISIBLE | COLLAPSE | WRAPS;

	public var position(get, never):String;

	function get_position():String {
		trait(0);
		return positionWord;
	}

	public var positioned(get, never):Bool;

	function get_positioned():Bool
		return position != "static" && position != "";

	public var floating(get, never):Bool;

	inline function get_floating():Bool
		return trait(FLOATING);

	public var absolute(get, never):Bool;

	function get_absolute():Bool
		return position == "absolute" || position == "fixed";

	// width: min-content, max-content or fit-content (Sizing 3 §3.2)
	public var contentSized(get, never):Bool;

	function get_contentSized():Bool {
		var k = rare.widthKeyword;
		return k == "min-content" || k == "max-content" || k == "fit-content";
	}

	// CSS Masking 1: clip's offsets are from the border box's top and left.
	@:allow(helder.ui.box.PaintOrder)
	function positionedClip(x:Float, y:Float, w:Float, h:Float):Null<Array<Float>> {
		var c = rare.clip;
		if (c == null) return null;
		var t = Lens.resolve(c[0], Math.NaN, 0), r = Lens.resolve(c[1], Math.NaN, w);
		var b = Lens.resolve(c[2], Math.NaN, h), l = Lens.resolve(c[3], Math.NaN, 0);
		return [x + l, y + t, Math.max(0, r - l), Math.max(0, b - t)];
	}

	// overflow scroll or auto on either axis: a scroll container whose content scrolls
	public var scrolls(get, never):Bool;

	inline function get_scrolls():Bool
		return trait(SCROLLS);

	// overflow-x's and overflow-y's keywords (visible, hidden, clip, scroll, auto)
	public var overflowX(get, never):String;
	public var overflowY(get, never):String;

	function get_overflowX():String {
		if (traits < 0) traits = readTraits();
		return overflowXWord;
	}

	function get_overflowY():String {
		if (traits < 0) traits = readTraits();
		return overflowYWord;
	}

	// it scrolls on the axis (overflow scroll or auto): the wheel, the keys, a scrollbar
	public inline function scrollsOn(x:Bool):Bool {
		var w = x ? overflowX : overflowY;
		return w == "scroll" || w == "auto";
	}

	// overflow hidden, auto or scroll on either axis: a scroll container (clip makes none, Overflow 3 §3)
	public var scrollContainer(get, never):Bool;

	inline function get_scrollContainer():Bool
		return trait(SCROLLS) || trait(HIDDEN_OVERFLOW);

	// a transform (transform, translate, rotate, scale): what it paints moved
	public var transformed(get, never):Bool;

	inline function get_transformed():Bool
		return trait(MOVED);

	// overflow other than visible on either axis (clips, and roots a formatting context)
	public var clips(get, never):Bool;

	inline function get_clips():Bool
		return trait(CLIPS);

	// (its lines' text-overflow applies: it clips, or cuts them without)
	public inline function cuts():Bool
		return trait(CLIPS | CUTS);

	public var rtl(get, never):Bool;

	inline function get_rtl():Bool
		return trait(RTL);

	// z-index: null for auto
	public inline function zIndex():Null<Int>
		return rare.zIndex;

	public var opacity(get, never):Float;

	// (read once: every paint order asks every context)
	var opacityValue = Math.NaN;

	function get_opacity():Float {
		if (opacityValue != opacityValue) opacityValue = readOpacity();
		return opacityValue;
	}

	function readOpacity():Float
		return 1;

	public var visible(get, never):Bool;

	inline function get_visible():Bool
		return trait(VISIBLE);

	// a stacking context of its own (CSS 2.1 §9.9.1, Color 4's opacity, Transforms 1)
	public inline function stacking():Bool
		return trait(STACKS);

	// ---- containment (CSS Containment 2)

	var contained = -1;

	// what applies (CssContain: contain's, content-visibility's), read once; an anonymous box none
	public var containment(get, never):CssContain;

	function get_containment():CssContain {
		if (contained < 0) contained = readContainment();
		return contained;
	}

	function readContainment():Int
		return 0;

	// contain-intrinsic-width or -height's length, size containment's size (Sizing 4 §5.4; none: 0; auto: its
	// length, the last remembered size not kept)
	public function intrinsicSize(width:Bool):Float
		return width ? rare.intrinsicWidth : rare.intrinsicHeight;

	// content-visibility: hidden, its contents not laid out nor painted, Contain 2 §4
	public var hidden(get, never):Bool;

	inline function get_hidden():Bool
		return trait(CONTENT_HIDDEN);

	// ---- vertical-align (Inline 3's longhands: baseline-shift, then alignment-baseline)

	// "baseline", "sub", "super", "top", "bottom", "middle", "text-top",
	// "text-bottom", "length" (shift: px up) or "percent" (shift: of the line height)
	public function verticalAlign():{kind:String, shift:Float}
		return aligned ??= readAlign();

	var aligned:Null<{kind:String, shift:Float}> = null;

	function readAlign():{kind:String, shift:Float}
		return {kind: "baseline", shift: 0};

	// ---- white space (Text 4's longhands)

	public var collapse(get, never):Bool;

	inline function get_collapse():Bool
		return trait(COLLAPSE);

	public var preserveBreaks(get, never):Bool;

	inline function get_preserveBreaks():Bool
		return trait(BREAKS);

	public var wraps(get, never):Bool;

	inline function get_wraps():Bool
		return trait(WRAPS);

	// ---- what few boxes have: a side object, read once (BoxRare)

	var rareRead:Null<BoxRare> = null;

	public var rare(get, never):BoxRare;

	inline function get_rare():BoxRare
		return rareRead ??= readRare();

	function readRare():BoxRare
		return new BoxRare();
}

// A box's background layers' lists, each split at its commas once
// (Backgrounds 3 §2: a list's values repeat to the images' count).
class BackgroundParts {
	public final images:Array<Array<CssTerm>>;
	public final clips:Array<Array<CssTerm>>;
	public final origins:Array<Array<CssTerm>>;
	public final sizes:Array<Array<CssTerm>>;
	public final repeats:Array<Array<CssTerm>>;
	public final xs:Array<Array<CssTerm>>;
	public final ys:Array<Array<CssTerm>>;
	public final attachments:Array<Array<CssTerm>>;

	public function new(images, clips, origins, sizes, repeats, xs, ys, attachments) {
		this.images = images;
		this.clips = clips;
		this.origins = origins;
		this.sizes = sizes;
		this.repeats = repeats;
		this.xs = xs;
		this.ys = ys;
		this.attachments = attachments;
	}

	// (a list's items at its commas)
	public static function split(t:Array<CssTerm>):Array<Array<CssTerm>> {
		var out:Array<Array<CssTerm>> = [[]];
		for (x in t) if (x.match(Delim(","))) out.push([]) else out[out.length - 1].push(x);
		return out;
	}
}

// One of box-shadow's shadows: its colour, inset, and its x and y offsets, blur and spread.
class BoxShadow {
	public var color = -1;
	public var inset = false;
	public final lengths:Array<Float> = [];

	public function new() {}
}
