package helder.css;

import helder.css.CssDisplay;

// An element's containment as it applies (CSS Containment 2): contain's
// keywords (strict and content as their sets) with content-visibility's
// (auto: layout, style and paint; hidden: size too), less what doesn't
// apply to its box (§3: size, layout and paint containment have no effect
// on an element without a principal box, a non-atomic inline, or an
// internal table or ruby box except for layout and paint on table cells).
// Size containment also has no effect on a table itself. Read by
// the box lane: a box with layout or paint containment is a stacking
// context and the containing block of its absolute and fixed descendants.
//
//   var c = style.containment();
//   if (c.has(Size)) ...;  // its intrinsic size its own, not its children's
enum abstract CssContain(Int) from Int to Int {
	var None = 0;
	var Size = 1;
	var InlineSize = 2;
	var Layout = 4;
	var Style = 8;
	var Paint = 16;

	public inline function has(c:CssContain):Bool
		return this & (c : Int) != 0;

	// (layout or paint containment: a stacking context, Contain 2 §3.2, §3.4)
	public var stacking(get, never):Bool;

	inline function get_stacking():Bool
		return has(Layout) || has(Paint);

	// (layout or paint containment: the containing block of absolute and fixed descendants)
	public var containingBlock(get, never):Bool;

	inline function get_containingBlock():Bool
		return has(Layout) || has(Paint);

	@:allow(helder.css)
	static function of(contain:Array<CssTerm>, visibility:Null<String>, display:CssDisplay):CssContain {
		var c = 0;
		for (t in contain) switch t {
			case Keyword("strict"): c |= Size | Layout | Style | Paint;
			case Keyword("content"): c |= Layout | Style | Paint;
			case Keyword("size"): c |= Size;
			case Keyword("inline-size"): c |= InlineSize;
			case Keyword("layout"): c |= Layout;
			case Keyword("style"): c |= Style;
			case Keyword("paint"): c |= Paint;
			case _:
		}
		if (visibility == "auto") c |= Layout | Style | Paint;
		if (visibility == "hidden") c |= Size | Layout | Style | Paint;
		var outer = display.outer, inner = display.inner;
		// (captions are block containers in the wrapper, outside the table grid)
		var internal = outer == CssOuterDisplay.Internal && inner != CssInnerDisplay.TableCaption;
		var none = outer == CssOuterDisplay.None || outer == CssOuterDisplay.Contents
			|| internal && inner != CssInnerDisplay.TableCell || outer == CssOuterDisplay.Inline && inner == CssInnerDisplay.Flow;
		if (none) return c & Style;
		if (inner == CssInnerDisplay.Table || internal) c &= ~(Size | InlineSize);
		return c;
	}
}
