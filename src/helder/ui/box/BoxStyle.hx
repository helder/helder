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

	public function new(css:CssStyle, anonymous = false) {
		this.css = css;
		this.anonymous = anonymous;
	}

	public function anonymousChild():BoxStyle
		return new BoxStyle(css, true);

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

	public function keyword(p:String):String
		return switch terms(p) {
			case [Keyword(k)] | [Ident(k)]: k;
			case [Part(_, [Keyword(k)])]: k;
			case _: "";
		}

	public function px(p:String):Float {
		if (!typed(p)) return 0;
		var id = idOf(p);
		if (id < 0) return 0;
		var l = css.length(cast id);
		return switch l.kind {
			case Px | Plain: l.value;
			case Relative: relative(l);
			case _: 0;
		}
	}

	// (a length in a font's unit helder.css leaves to layout: ex and ch as half an em, cap and ic
	// as 0.7 and 1, until the fonts' own metrics come here)
	function relative(l:CssLength):Float {
		var em = css.fontSize();
		return l.value * switch l.unit {
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
		var l = css.length(cast id);
		return switch l.kind {
			case Px | Plain: Px(l.value);
			case Relative: Px(relative(l));
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
	// (table-row, table-cell and the other internal displays)
	public static inline var TABLE_PART = 5;

	var displayRead = false;
	var displayNone = false;
	var displayContents = false;
	var displayList = false;
	var displayOuter = 0;
	var displayInner = 0;

	public var none(get, never):Bool;
	public var contents(get, never):Bool;
	public var listItem(get, never):Bool;
	public var outer(get, never):Int;
	public var inner(get, never):Int;

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
		// (a table's part with no table around it: CSS 2.1 §17.2.1's anonymous table, not in the slice yet)
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

	public var position(get, never):String;

	function get_position():String
		return keyword("position");

	public var positioned(get, never):Bool;

	function get_positioned():Bool
		return position != "static" && position != "";

	public var floating(get, never):Bool;

	function get_floating():Bool
		return keyword("float") == "left" || keyword("float") == "right";

	public var absolute(get, never):Bool;

	function get_absolute():Bool
		return position == "absolute" || position == "fixed";

	// overflow other than visible on either axis (clips, and roots a formatting context)
	public var clips(get, never):Bool;

	function get_clips():Bool {
		var x = keyword("overflow-x"), y = keyword("overflow-y");
		return x != "visible" && x != "" || y != "visible" && y != "";
	}

	public var rtl(get, never):Bool;

	function get_rtl():Bool
		return keyword("direction") == "rtl";

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

	function get_visible():Bool
		return keyword("visibility") != "hidden" && keyword("visibility") != "collapse";

	// a stacking context of its own (CSS 2.1 §9.9.1, Color 4's opacity, Transforms 1)
	public function stacking():Bool
		return positioned && zIndex() != null || opacity < 1 || keyword("transform") != "none" && terms("transform").length > 0
			|| keyword("position") == "fixed";

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

	function get_collapse():Bool {
		var k = keyword("white-space-collapse");
		return k == "collapse" || k == "";
	}

	public var preserveBreaks(get, never):Bool;

	function get_preserveBreaks():Bool
		return keyword("white-space-collapse") != "collapse";

	public var wraps(get, never):Bool;

	function get_wraps():Bool
		return keyword("text-wrap-mode") != "nowrap";
}
