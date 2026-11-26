package helder.ui.box;

import helder.css.CssColors;
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

	public function anonymousChild():BoxStyle
		return new BoxStyle(css, true);

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
		// (system colours: the light scheme's canvas white, the rest as their text, black)
		if (c.keyword != null && c.keyword != "currentcolor") switch c.keyword {
			case "transparent": return 0;
			case "canvas" | "field" | "buttonface" | "window": return (byte(c.a) << 24) | 0xFFFFFF;
			case _: if (c.r == 0 && c.g == 0 && c.b == 0) return (byte(c.a) << 24);
		}
		return (byte(c.a) << 24) | (byte(c.r) << 16) | (byte(c.g) << 8) | byte(c.b);
	}

	public static function argb(c:CssColorValue, current:Int):Int {
		switch c.keyword {
			case "currentcolor": return current;
			case "transparent": return 0;
			case "canvas": return 0xFFFFFFFF;
			case _:
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
		return this;
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
			traits = (f == "left" || f == "right" ? FLOATING : 0) | ((x != "visible" && x != "") || (y != "visible" && y != "") ? CLIPS : 0)
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

	function get_opacity():Float
		return number("opacity", 1);

	public var visible(get, never):Bool;

	inline function get_visible():Bool
		return trait(VISIBLE);

	// a stacking context of its own (CSS 2.1 §9.9.1, Color 4's opacity, Transforms 1)
	public function stacking():Bool
		return positioned && zIndex() != null || opacity < 1 || keyword("transform") != "none" && terms("transform").length > 0
			|| keyword("position") == "fixed";

	// ---- the font

	var familyList:Null<Array<String>> = null;

	// font-family's names, generic ones as their keywords (read once)
	public function families():Array<String> {
		if (familyList != null) return familyList;
		var out = [], word = [];
		for (t in terms("font-family")) switch t {
			case Delim(","):
				if (word.length > 0) out.push(word.join(" "));
				word = [];
			case Ident(v) | Str(v) | Keyword(v): word.push(v);
			case _:
		}
		if (word.length > 0) out.push(word.join(" "));
		return familyList = out;
	}

	// ---- vertical-align (Inline 3's longhands: baseline-shift, then alignment-baseline)

	// "baseline", "sub", "super", "top", "bottom", "middle", "text-top",
	// "text-bottom", "length" (shift: px up) or "percent" (shift: of the line height)
	public function verticalAlign():{kind:String, shift:Float} {
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
