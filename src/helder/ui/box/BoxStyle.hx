package helder.ui.box;

import helder.css.CssColors;
import helder.css.CssContain;
import helder.css.CssDisplay;
import helder.css.CssLength;
import helder.css.CssProperties;
import helder.css.CssProperty;
import helder.css.CssRgba;
import helder.css.CssShorthands;
import helder.css.CssStyle;
import helder.css.CssTerm;
import helder.ui.box.Len;
import helder.ui.box.Len.Lens;

using StringTools;

// What layout and paint read of a computed style, typed: the one place
// that knows how helder.css stores it (its typed reads by property id:
// lengths, colours, display, numbers; terms for the rest), so a new
// storage changes this file alone. Callers name properties as CSS does;
// each name is the property's id once. An anonymous box's style is its
// parent's inherited values and the initial ones (CSS 2.1 §9.2.1.1).
class BoxStyle {
	public final css:CssStyle;
	public final anonymous:Bool;
	// (its InlineStyles by split edges, BoxInline.of's)
	@:allow(helder.ui.box.BoxInline) final inlines:Array<Null<BoxInline>> = [null, null, null, null];

	public function new(css:CssStyle, anonymous = false) {
		this.css = css;
		this.anonymous = anonymous;
	}

	// (how far it paints past its box, BoxPainter.reach's: kept once known; NaN until then)
	@:allow(helder.ui.box) var reach = Math.NaN;
	// (whether it draws text decorations: text-decoration-line not none; read once)
	var decorating = -1;

	public function decorates():Bool {
		if (decorating < 0) {
			var lines = terms("text-decoration-line");
			decorating = lines.length > 0 && !lines[0].match(Keyword("none")) ? 1 : 0;
		}
		return decorating == 1;
	}

	public function anonymousChild():BoxStyle
		return new BoxStyle(css, true);

	// The same box's style from another computed style (a live document
	// restyled): an anonymous table part's display kept.
	public function restyled(next:CssStyle):BoxStyle {
		var s = new BoxStyle(next, anonymous);
		if (anonymous && displayRead) {
			s.displayRead = true;
			s.displayNone = displayNone;
			s.displayContents = displayContents;
			s.displayList = displayList;
			s.displayOuter = displayOuter;
			s.displayInner = displayInner;
			s.displayPart = displayPart;
		}
		return s;
	}

	// An anonymous box of a table's display (CSS 2.1 §17.2.1): its parent's inherited values.
	public function anonymousTable(inner:Int, part:Int, outer = BLOCK):BoxStyle {
		var s = new BoxStyle(css, true);
		s.displayRead = true;
		s.displayInner = inner;
		s.displayPart = part;
		s.displayOuter = outer;
		return s;
	}

	public function terms(p:String):Array<CssTerm> {
		var id = idOf(p);
		if (id < 0) return [];
		if (anonymous && !CssProperties.inherits(cast id)) return CssShorthands.initialTerms(p) ?? [];
		return css.terms(cast id);
	}

	// (names to ids, once each; -1: not a property in scope)
	static final ids = new Map<String, Int>();

	static function idOf(p:String):Int {
		var id = ids.get(p);
		if (id == null) {
			var found = CssProperties.of(p);
			ids.set(p, id = found == null ? -1 : (cast found : Int));
		}
		return id;
	}

	// (the typed reads where the value is the element's own; an anonymous box's reset ones are initial)
	inline function typed(p:String):Bool
		return !anonymous || CssProperties.inherits(cast idOf(p));

	public function keyword(p:String):String {
		// (keywords the groups keep as an index, read without terms made for them)
		if (!anonymous) {
			var k:Int = switch p {
				case "white-space-collapse": cast css.inheritedText.whiteSpaceCollapse;
				case "text-wrap-mode": cast css.inheritedText.textWrapMode;
				case "word-break": cast css.inheritedText.wordBreak;
				case "line-break": cast css.inheritedText.lineBreak;
				case "overflow-wrap": cast css.inheritedText.overflowWrap;
				case "hyphens": cast css.inheritedText.hyphens;
				case "direction": cast css.inheritedText.direction;
				case "text-align-last": cast css.inheritedText.textAlignLast;
				case "font-kerning": cast css.font.fontKerning;
				case "list-style-position": cast css.list.listStylePosition;
				case "visibility": cast css.ui.visibility;
				case "pointer-events": cast css.ui.pointerEvents;
				case "float": cast css.box.float;
				case "box-sizing": cast css.box.boxSizing;
				case "overflow-x": cast css.box.overflowX;
				case "overflow-y": cast css.box.overflowY;
				case "unicode-bidi": cast css.box.unicodeBidi;
				case "position": cast css.position.position;
				case "outline-style": cast css.outline.outlineStyle;
				case "text-decoration-style": cast css.decoration.textDecorationStyle;
				case _: -2;
			}
			if (k >= 0) return CssProperties.keywords(cast idOf(p))[k];
		}
		return switch terms(p) {
			case [Keyword(k)] | [Ident(k)]: k;
			case [Part(_, [Keyword(k)])]: k;
			case _: "";
		}
	}

	public function px(p:String):Float {
		if (!typed(p)) return 0;
		var id = idOf(p);
		if (id < 0) return 0;
		if (unstyled(p)) return 0;
		var l = lengthOf(p, id);
		return switch l.kind {
			case Px | Plain: l.value;
			case Relative: relative(l);
			// (a property its group keeps as terms: text-indent's)
			case Other: switch termLen(terms(p)) {
					case Px(v): v;
					case _: 0;
				}
			case _: 0;
		}
	}

	// (a border's or outline's used width under a none or hidden style: 0,
	// Borders 4 §4.3; its computed one, helder.css's, is as written)
	function unstyled(p:String):Bool {
		var style = switch p {
			case "border-top-width": "border-top-style";
			case "border-right-width": "border-right-style";
			case "border-bottom-width": "border-bottom-style";
			case "border-left-width": "border-left-style";
			case "outline-width": "outline-style";
			case _: return false;
		}
		var k = keyword(style);
		return k == "none" || k == "hidden" && p != "outline-width";
	}

	// (the groups' typed fields where layout reads often: CssStyle.length interns its terms again)
	function lengthOf(p:String, id:Int):CssLength
		return switch p {
			case "margin-top": css.spacing.marginTop;
			case "margin-right": css.spacing.marginRight;
			case "margin-bottom": css.spacing.marginBottom;
			case "margin-left": css.spacing.marginLeft;
			case "padding-top": css.spacing.paddingTop;
			case "padding-right": css.spacing.paddingRight;
			case "padding-bottom": css.spacing.paddingBottom;
			case "padding-left": css.spacing.paddingLeft;
			case "border-top-width": css.border.borderTopWidth;
			case "border-right-width": css.border.borderRightWidth;
			case "border-bottom-width": css.border.borderBottomWidth;
			case "border-left-width": css.border.borderLeftWidth;
			case "width": css.box.width;
			case "height": css.box.height;
			case "min-width": css.box.minWidth;
			case "min-height": css.box.minHeight;
			case "max-width": css.box.maxWidth;
			case "max-height": css.box.maxHeight;
			case "letter-spacing": css.inheritedText.letterSpacing;
			case "word-spacing": css.inheritedText.wordSpacing;
			case "line-height": css.font.lineHeight;
			case "font-size": css.font.fontSize;
			case "outline-width": css.outline.outlineWidth;
			case "outline-offset": css.outline.outlineOffset;
			case _: css.length(cast id);
		}

	// (a length from terms, a font-relative unit resolved)
	function termLen(t:Array<CssTerm>):Len
		return switch toLen(t) {
			case Px(v):
				var unit = "px";
				for (x in t) switch x {
					case Dimension(_, u): unit = u;
					case _:
				}
				unit == "px" ? Px(v) : Px(unitPx(v, unit));
			case l: l;
		}

	// (a length in a font's unit helder.css leaves to layout: ex and ch as half an em, cap and ic
	// as 0.7 and 1, until the fonts' own metrics come here)
	function relative(l:CssLength):Float
		return unitPx(l.value, l.unit);

	function unitPx(value:Float, unit:String):Float {
		var em = css.fontSize();
		return value * switch unit {
			case "ex" | "ch": em / 2;
			case "cap": em * 0.7;
			case "ic" | "em": em;
			case "lh": css.lineHeight() ?? em * 1.2;
			case _: 0;
		}
	}

	public function len(p:String):Len {
		if (!typed(p)) return toLen(terms(p));
		var id = idOf(p);
		if (id < 0) return Auto;
		if (unstyled(p)) return Px(0);
		var l = lengthOf(p, id);
		return switch l.kind {
			case Px | Plain: Px(l.value);
			case Relative: Px(relative(l));
			case Other: termLen(terms(p));
			case Percent: Percent(l.value);
			case Mixed if (l.calc != null): Calc(l.calc);
			case _: Auto;
		}
	}

	public static function toLen(t:Array<CssTerm>):Len
		return switch t {
			case [Dimension(v, _)]: Px(v);
			case [Percentage(v)]: Percent(v);
			case [Calc(n, _, _)]: Calc(n);
			case [Number(v, _)]: Px(v);
			case [Part(_, inner)]: toLen(inner);
			// (a length among keywords: text-indent's with hanging or each-line)
			case _ if (t.length > 1): {
					for (x in t) switch x {
						case Dimension(_, _) | Percentage(_) | Calc(_, _, _): return toLen([x]);
						case _:
					}
					Auto;
				}
			case _: Auto;
		}

	public function number(p:String, fallback = 0.0):Float {
		if (!typed(p)) return switch terms(p) {
			case [Number(v, _)]: v;
			case _: fallback;
		}
		var id = idOf(p);
		var v = id < 0 ? Math.NaN : css.number(cast id);
		return Math.isNaN(v) ? fallback : v;
	}

	// The colour as 0xAARRGGBB; currentcolor is the color property's.
	public function color(p:String):Int {
		if (!typed(p)) return 0;
		var id = idOf(p);
		return id < 0 ? 0 : rgba(css.color(cast id));
	}

	static function rgba(c:CssRgba):Int {
		inline function byte(x:Float):Int {
			var v = Math.round((Math.isNaN(x) ? 0 : x) * 255);
			return v < 0 ? 0 : v > 255 ? 255 : v;
		}
		// (system colours: the light scheme's, CssColors.system)
		if (c.keyword != null && c.keyword != "currentcolor") switch c.keyword {
			case "transparent": return 0;
			case k:
				var s = CssColors.system(k);
				if (s != null) return (byte(c.a * s[3]) << 24) | (Std.int(s[0]) << 16) | (Std.int(s[1]) << 8) | Std.int(s[2]);
		}
		return (byte(c.a) << 24) | (byte(c.r) << 16) | (byte(c.g) << 8) | byte(c.b);
	}

	public static function argb(c:CssColorValue, current:Int):Int {
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

	function display() {
		if (displayRead) return;
		displayRead = true;
		if (anonymous) return;
		var d = css.display;
		switch d.outer {
			case None: displayNone = true;
			case Contents: displayContents = true;
			case Inline: displayOuter = INLINE;
			case _: displayOuter = BLOCK;
		}
		displayList = d.listItem;
		displayInner = switch d.inner {
			case FlowRoot: FLOW_ROOT;
			case Table: TABLE;
			case Flex: FLEX;
			case Grid | GridLanes: GRID;
			case TableRowGroup | TableHeaderGroup | TableFooterGroup | TableRow | TableCell | TableColumnGroup | TableColumn | TableCaption: TABLE_PART;
			case _: FLOW;
		}
		displayPart = switch d.inner {
			case TableRowGroup: ROW_GROUP;
			case TableHeaderGroup: HEADER_GROUP;
			case TableFooterGroup: FOOTER_GROUP;
			case TableRow: ROW;
			case TableCell: CELL;
			case TableColumnGroup: COLUMN_GROUP;
			case TableColumn: COLUMN;
			case TableCaption: CAPTION;
			case _: 0;
		}
		if (d.outer == Internal && displayInner != TABLE_PART) displayOuter = BLOCK;
	}

	// ---- the text part: what inline layout and fonts read of it, typed
	// (InlineBasicStyle's fields; its edges, lang and direction the box's,
	// BoxInline's), read once. text-indent apart: a percentage of the
	// containing block's width.

	var textPart:Null<helder.ui.flow.InlineBasicStyle> = null;
	var indentLen = Len.Auto;

	public var text(get, never):helder.ui.flow.InlineBasicStyle;
	public var textIndent(get, never):Len;

	inline function get_text():helder.ui.flow.InlineBasicStyle
		return textPart ??= readText();

	inline function get_textIndent():Len {
		if (textPart == null) textPart = readText();
		return indentLen;
	}

	function readText():helder.ui.flow.InlineBasicStyle {
		var t = new helder.ui.flow.InlineBasicStyle();
		t.families = families();
		t.size = css.fontSize();
		t.weight = Std.int(number("font-weight", 400));
		var fs = terms("font-style");
		t.style = switch keyword("font-style") {
			case "italic": Italic;
			case "oblique": Oblique;
			case _: switch fs {
					case [Keyword("oblique"), _]: Oblique;
					case _: Normal;
				}
		}
		t.angle = switch fs {
			case [Keyword("oblique"), Dimension(v, "deg")]: v;
			case [Keyword("oblique"), Dimension(v, "turn")]: v * 360;
			case [Keyword("oblique"), Dimension(v, "rad")]: v * 180 / Math.PI;
			case [Keyword("oblique"), Dimension(v, "grad")]: v * 0.9;
			case _: 14;
		}
		t.stretch = switch terms("font-width") {
			case [Percentage(p)]: p;
			case [Keyword(k)]: helder.text.FontFaces.FontFaceDescriptors.STRETCH.get(k) ?? 100;
			case _: 100;
		}
		var synthesis = 0;
		if (keyword("font-synthesis-weight") != "none") synthesis |= helder.ui.flow.InlineValues.InlineSynthesis.Weight;
		switch keyword("font-synthesis-style") {
			case "none":
			case "oblique-only": synthesis |= helder.ui.flow.InlineValues.InlineSynthesis.Oblique;
			case _: synthesis |= helder.ui.flow.InlineValues.InlineSynthesis.Style | helder.ui.flow.InlineValues.InlineSynthesis.Oblique;
		}
		t.synthesis = synthesis;
		t.opticalSizing = keyword("font-optical-sizing") != "none";
		t.variations = TextTerms.variations(terms("font-variation-settings"));
		t.features = TextTerms.features(this);
		t.kerning = switch keyword("font-kerning") {
			case "normal": Normal;
			case "none": None;
			case _: Auto;
		}
		t.ligatures = TextTerms.ligatures(terms("font-variant-ligatures"));
		t.emoji = switch keyword("font-variant-emoji") {
			case "text": Text;
			case "emoji": Emoji;
			case "unicode": Unicode;
			case _: Normal;
		}
		t.colour = color("color");
		t.height = switch terms("line-height") {
			case [Dimension(v, "px")]: v;
			case [Number(n, _)]: n * t.size;
			case [Percentage(p)]: p * t.size / 100;
			case _: Math.NaN;
		}
		t.letters = px("letter-spacing");
		t.words = px("word-spacing");
		t.transform = TextTerms.transform(terms("text-transform"));
		t.collapse = switch keyword("white-space-collapse") {
			case "discard": Discard;
			case "preserve": Preserve;
			case "preserve-breaks": PreserveBreaks;
			case "preserve-spaces": PreserveSpaces;
			case "break-spaces": BreakSpaces;
			case _: Collapse;
		}
		t.wrap = keyword("text-wrap-mode") == "nowrap" ? NoWrap : Wrap;
		t.tab = switch terms("tab-size") {
			case [Number(n, _)]: n;
			case [Dimension(v, _)]: -v;
			case _: 8;
		}
		t.breakWord = switch keyword("word-break") {
			case "break-all": BreakAll;
			case "keep-all": KeepAll;
			case "break-word": BreakWord;
			case _: Normal;
		}
		t.overflow = switch keyword("overflow-wrap") {
			case "break-word": BreakWord;
			case "anywhere": Anywhere;
			case _: Normal;
		}
		t.breakLine = switch keyword("line-break") {
			case "loose": Loose;
			case "normal": Normal;
			case "strict": Strict;
			case "anywhere": Anywhere;
			case _: Auto;
		}
		t.hyphen = switch keyword("hyphens") {
			case "none": None;
			case "auto": Auto;
			case _: Manual;
		}
		t.dir = rtl ? Rtl : Ltr;
		t.bidi = switch keyword("unicode-bidi") {
			case "embed": Embed;
			case "isolate": Isolate;
			case "bidi-override": BidiOverride;
			case "isolate-override": IsolateOverride;
			case "plaintext": Plaintext;
			case _: Normal;
		}
		t.align = TextTerms.align(keyword("text-align-all"), Start);
		t.alignLast = TextTerms.align(keyword("text-align-last"), Auto);
		t.justify = switch keyword("text-justify") {
			case "none": None;
			case "inter-word": InterWord;
			case "inter-character": InterCharacter;
			case _: Auto;
		}
		indentLen = len("text-indent");
		var ti = terms("text-indent");
		t.indentEachLine = ti.contains(Keyword("each-line"));
		t.indentHanging = ti.contains(Keyword("hanging"));
		var to = terms("text-overflow");
		t.textOverflowEnd = to.length > 0 && to[to.length - 1].match(Keyword("ellipsis")) ? Ellipsis : Clip;
		t.clamp = switch terms("line-clamp") {
			case [Number(n, _)]: Std.int(n);
			case _: 0;
		}
		var va = verticalAlign();
		t.vertical = TextTerms.vertical(va.kind);
		t.shift = va.kind == "percent" ? va.shift / 100 : va.shift;
		t.decoration = TextTerms.decoration(terms("text-decoration-line"));
		t.decorationStyle = switch keyword("text-decoration-style") {
			case "double": Double;
			case "dotted": Dotted;
			case "dashed": Dashed;
			case "wavy": Wavy;
			case _: Solid;
		}
		t.decorationColour = switch terms("text-decoration-color") {
			case [Color(c)]: argb(c, t.colour);
			case _: t.colour;
		}
		t.decorationThickness = switch terms("text-decoration-thickness") {
			case [Dimension(v, _)]: v;
			case [Percentage(p)]: p * t.size / 100;
			case _: Math.NaN;
		}
		return t;
	}

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

	function readPaint() {
		paintRead = true;
		bgColor = color("background-color");
		var images = BackgroundParts.split(terms("background-image"));
		if (!(images.length == 1 && (images[0].length == 0 || images[0][0].match(Keyword("none"))))) bgParts = new BackgroundParts(this, images);
		// (the colour's clip: the bottom layer's)
		var clips = bgParts != null ? bgParts.clips : BackgroundParts.split(terms("background-clip"));
		bgClip = switch clips[(images.length - 1) % clips.length] {
			case [Keyword(k)]: k;
			case _: "border-box";
		}
		var r = [], any = false;
		for (c in CORNERS) switch terms('border-$c-radius') {
			case [a, b]:
				r.push(a);
				r.push(b);
				if (!zero(a) || !zero(b)) any = true;
			case [a]:
				r.push(a);
				r.push(a);
				if (!zero(a)) any = true;
			case _:
				r.push(Number(0, true));
				r.push(Number(0, true));
		}
		if (any) radiusTerms = r;
		for (side in SIDES) {
			sideStyles.push(keyword('border-$side-style'));
			sideColors.push(color('border-$side-color'));
		}
		var shadow = terms("box-shadow");
		if (shadow.length > 0 && !shadow[0].match(Keyword("none"))) {
			var list = [], current = color("color");
			var one = new BoxShadow();
			list.push(one);
			for (t in shadow) switch t {
				case Delim(","):
					one = new BoxShadow();
					list.push(one);
				case Color(c): one.color = argb(c, current);
				case Keyword("inset"): one.inset = true;
				case Dimension(v, _): one.lengths.push(v);
				case _:
			}
			for (o in list) {
				if (o.color == -1) o.color = current;
				while (o.lengths.length < 4) o.lengths.push(0);
			}
			shadowList = list;
		}
		outlineStyleValue = keyword("outline-style");
		if (outlineStyleValue != "none" && outlineStyleValue != "") {
			outlineWidthValue = px("outline-width");
			outlineOffsetValue = px("outline-offset");
			outlineColorValue = switch terms("outline-color") {
				case [Keyword("auto" | "invert")]: color("color");
				case _: color("outline-color");
			}
		}
	}

	static function zero(t:CssTerm):Bool
		return switch t {
			case Dimension(v, _) | Number(v, _) | Percentage(v): v == 0;
			case _: false;
		}

	static final CORNERS = ["top-left", "top-right", "bottom-right", "bottom-left"];

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

	function readLayout() {
		layoutRead = true;
		orderValue = Std.int(number("order", 0));
		growValue = number("flex-grow", 0);
		shrinkValue = number("flex-shrink", 1);
		basisWord = keyword("flex-basis");
		basisValue = len("flex-basis");
		directionValue = keyword("flex-direction");
		wrapValue = keyword("flex-wrap");
		for (p in ALIGNS) {
			var k = keyword(p);
			aligns.push(k == "" ? helder.css.CssText.join(terms(p), helder.css.CssText.term) : k);
		}
		rowGapValue = keyword("row-gap") == "normal" ? Len.Auto : len("row-gap");
		columnGapValue = keyword("column-gap") == "normal" ? Len.Auto : len("column-gap");
		for (s in SIDES) insets.push(len(s));
		floatValue = keyword("float");
		clearValue = keyword("clear");
	}

	static final ALIGNS = ["justify-content", "align-content", "align-items", "align-self", "justify-items", "justify-self"];

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

	static final SIDES = ["top", "right", "bottom", "left"];

	public function model():BoxStyle {
		if (modelRead) return this;
		modelRead = true;
		// (an anonymous box's are all initial: none, zero, auto)
		if (anonymous) {
			for (_ in 0...4) {
				margin.push(Px(0));
				padding.push(Px(0));
				border.push(0);
			}
			return this;
		}
		for (s in SIDES) {
			margin.push(len('margin-$s'));
			padding.push(len('padding-$s'));
			border.push(px('border-$s-width'));
		}
		width = len("width");
		height = len("height");
		minWidth = len("min-width");
		minHeight = len("min-height");
		maxWidth = len("max-width");
		maxHeight = len("max-height");
		borderBox = keyword("box-sizing") == "border-box";
		readRatio(terms("aspect-ratio"));
		return this;
	}

	function readRatio(terms:Array<CssTerm>) {
		var a = Math.NaN, b = 1.0, over = false;
		for (t in terms) switch t {
			case Number(v, _):
				if (over) b = v else a = v;
			case Delim("/"):
				over = true;
			case Part(_, inner):
				readRatio(inner);
				return;
			case _:
		}
		if (Math.isNaN(a)) return;
		ratioAuto = terms[0].match(Keyword("auto")) || terms[terms.length - 1].match(Keyword("auto"));
		var r = a / b;
		if (r > 0 && Math.isFinite(r)) ratio = r;
	}

	// ---- positioning and the rest layout asks

	// (what layout asks of every box, read once: a bit each, position's keyword)
	var traits = -1;
	var positionWord = "";

	static inline var FLOATING = 1;
	static inline var CLIPS = 2;
	static inline var RTL = 4;
	static inline var VISIBLE = 8;
	static inline var COLLAPSE = 16;
	static inline var BREAKS = 32;
	static inline var WRAPS = 64;

	function trait(bit:Int):Bool {
		if (traits < 0) {
			positionWord = keyword("position");
			var f = keyword("float"), x = keyword("overflow-x"), y = keyword("overflow-y"), v = keyword("visibility"), c = keyword("white-space-collapse");
			// (paint containment clips as overflow does, to the padding box, Contain 2 §3.4)
			traits = (f == "left" || f == "right" ? FLOATING : 0) | ((x != "visible" && x != "") || (y != "visible" && y != "") || containment.has(Paint) ? CLIPS : 0)
				| (keyword("direction") == "rtl" ? RTL : 0) | (v != "hidden" && v != "collapse" ? VISIBLE : 0) | (c == "collapse" || c == "" ? COLLAPSE : 0)
				| (c != "collapse" ? BREAKS : 0) | (keyword("text-wrap-mode") != "nowrap" ? WRAPS : 0);
		}
		return traits & bit != 0;
	}

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
		if (sized < 0) {
			var k = keyword("width");
			sized = k == "min-content" || k == "max-content" || k == "fit-content" ? 1 : 0;
		}
		return sized == 1;
	}

	var sized = -1;

	// CSS Masking 1: clip's offsets are from the border box's top and left.
	@:allow(helder.ui.box.PaintOrder)
	function positionedClip(x:Float, y:Float, w:Float, h:Float):Null<Array<Float>> {
		return switch terms("clip") {
			case [Func("rect", [top, Delim(","), right, Delim(","), bottom, Delim(","), left])]:
				var t = Lens.resolve(termLen([top]), Math.NaN, 0), r = Lens.resolve(termLen([right]), Math.NaN, w);
				var b = Lens.resolve(termLen([bottom]), Math.NaN, h), l = Lens.resolve(termLen([left]), Math.NaN, 0);
				[x + l, y + t, Math.max(0, r - l), Math.max(0, b - t)];
			case _: null;
		}
	}

	// overflow scroll or auto on either axis: a scroll container whose content scrolls
	public var scrolls(get, never):Bool;

	function get_scrolls():Bool {
		if (overflows < 0) {
			var x = keyword("overflow-x"), y = keyword("overflow-y");
			overflows = (x == "auto" || x == "scroll" || y == "auto" || y == "scroll" ? 1 : 0) | (x == "hidden" || y == "hidden" ? 2 : 0);
		}
		return overflows & 1 != 0;
	}

	// overflow hidden, auto or scroll on either axis: a scroll container (clip makes none, Overflow 3 §3)
	public var scrollContainer(get, never):Bool;

	function get_scrollContainer():Bool
		return scrolls || overflows & 2 != 0;

	// (scrolls' and scrollContainer's, read once: 1 scrolls, 2 hidden)
	var overflows = -1;

	// a transform (transform, translate, rotate, scale): what it paints moved
	public var transformed(get, never):Bool;

	function get_transformed():Bool {
		if (moved < 0) moved = anonymous || keyword("transform") == "none" && keyword("translate") == "none" && keyword("rotate") == "none"
			&& keyword("scale") == "none" ? 0 : 1;
		return moved == 1;
	}

	var moved = -1;

	// overflow other than visible on either axis (clips, and roots a formatting context)
	public var clips(get, never):Bool;

	inline function get_clips():Bool
		return trait(CLIPS);

	public var rtl(get, never):Bool;

	inline function get_rtl():Bool
		return trait(RTL);

	// z-index: null for auto
	public function zIndex():Null<Int>
		return switch terms("z-index") {
			case [Number(v, _)]: Std.int(v);
			case _: null;
		}

	public var opacity(get, never):Float;

	// (read once: every paint order asks every context)
	var opacityValue = Math.NaN;

	function get_opacity():Float {
		if (opacityValue != opacityValue) opacityValue = number("opacity", 1);
		return opacityValue;
	}

	public var visible(get, never):Bool;

	inline function get_visible():Bool
		return trait(VISIBLE);

	// a stacking context of its own (CSS 2.1 §9.9.1, Color 4's opacity, Transforms 1)
	public function stacking():Bool {
		if (stacks < 0)
			stacks = positioned && zIndex() != null || opacity < 1 || keyword("transform") != "none" && terms("transform").length > 0
				|| keyword("position") == "fixed" || containment.stacking ? 1 : 0;
		return stacks == 1;
	}

	var stacks = -1;

	// ---- containment (CSS Containment 2)

	var contained = -1;

	// what applies (CssContain: contain's, content-visibility's), read once; an anonymous box none
	public var containment(get, never):CssContain;

	function get_containment():CssContain {
		if (contained < 0) contained = anonymous ? 0 : css.containment();
		return contained;
	}

	// contain-intrinsic-width or -height's length, size containment's size (Sizing 4 §5.4; none: 0; auto: its
	// length, the last remembered size not kept)
	public function intrinsicSize(width:Bool):Float {
		for (t in terms(width ? "contain-intrinsic-width" : "contain-intrinsic-height")) switch t {
			case Dimension(v, _): return v;
			case Number(v, _): return v;
			case _:
		}
		return 0;
	}

	// content-visibility: hidden, its contents not laid out nor painted, Contain 2 §4
	public var hidden(get, never):Bool;

	inline function get_hidden():Bool
		return !anonymous && keyword("content-visibility") == "hidden";

	// ---- the font

	var familyList:Null<Array<String>> = null;

	// font-family's names, generic ones as their keywords, a quoted name
	// that is one ("serif") in its quotes (read once)
	public function families():Array<String> {
		if (familyList == null) familyList = familiesOf(terms("font-family"));
		return familyList;
	}

	public static function familiesOf(terms:Array<CssTerm>):Array<String> {
		var out = [], word = [];
		for (t in terms) switch t {
			case Delim(","):
				if (word.length > 0) out.push(word.join(" "));
				word = [];
			case Str(v) if (helder.ui.flow.InlineFonts.generic(v)): word.push('"$v"');
			case Ident(v) | Str(v) | Keyword(v) | Raw(v): word.push(v);
			case _:
		}
		if (word.length > 0) out.push(word.join(" "));
		return out;
	}

	// ---- vertical-align (Inline 3's longhands: baseline-shift, then alignment-baseline)

	// "baseline", "sub", "super", "top", "bottom", "middle", "text-top",
	// "text-bottom", "length" (shift: px up) or "percent" (shift: of the line height)
	public function verticalAlign():{kind:String, shift:Float}
		return aligned ??= align();

	var aligned:Null<{kind:String, shift:Float}> = null;

	function align():{kind:String, shift:Float} {
		switch terms("baseline-shift") {
			case [Keyword(k)] if (k != "baseline"): return {kind: k == "center" ? "middle" : k, shift: 0};
			case [Dimension(v, _)] if (v != 0): return {kind: "length", shift: v};
			case [Percentage(p)] if (p != 0): return {kind: "percent", shift: p};
			case [Calc(_, _, _)]: return {kind: "length", shift: Lens.resolve(len("baseline-shift"), 0, 0)};
			case _:
		}
		return switch keyword("alignment-baseline") {
			case "middle" | "central": {kind: "middle", shift: 0};
			case "text-top" | "text-before-edge": {kind: "text-top", shift: 0};
			case "text-bottom" | "text-after-edge": {kind: "text-bottom", shift: 0};
			case _: {kind: "baseline", shift: 0};
		}
	}

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

	public function new(s:BoxStyle, images:Array<Array<CssTerm>>) {
		this.images = images;
		clips = split(s.terms("background-clip"));
		origins = split(s.terms("background-origin"));
		sizes = split(s.terms("background-size"));
		repeats = split(s.terms("background-repeat"));
		xs = split(s.terms("background-position-x"));
		ys = split(s.terms("background-position-y"));
		attachments = split(s.terms("background-attachment"));
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
