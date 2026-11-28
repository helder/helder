package helder.ui.box;

import helder.css.CssTerm;
import helder.ui.box.Len;

// What few boxes' styles have that layout and paint read, apart from
// BoxStyle so that a style stays small: CSS's initial values until set (by
// code, or read from the cascade's style: CssBoxStyle). Lists of terms
// where layout reads them as terms (the grid's, a transform's).
@:allow(helder.ui)
class BoxRare {
	// width's keyword where it is one (min-content, max-content, fit-content: BoxStyle.contentSized)
	public var widthKeyword(default, null) = "";
	// min-width's and max-width's (a flex item's: FlexFlow)
	public var minWidthKeyword(default, null) = "";
	public var maxWidthKeyword(default, null) = "";
	// clip: rect()'s top, right, bottom, left (null: auto)
	public var clip(default, null):Null<Array<Len>> = null;
	// z-index (null: auto)
	public var zIndex(default, null):Null<Int> = null;
	public var intrinsicWidth(default, null) = 0.0;
	public var intrinsicHeight(default, null) = 0.0;
	public var pointerEvents(default, null) = "auto";
	public var visibility(default, null) = "visible";
	// generated content: content normal (a marker's own text), list-style-type
	public var contentNormal(default, null) = true;
	public var listStyleType(default, null) = "disc";
	// text-align's keyword (a block's: start)
	public var textAlign(default, null) = "start";
	public var boxDecorationBreak(default, null) = "slice";
	// fragmentation: break-before, -after, -inside, their legacy page-break-* (auto), page, orphans, widows
	public var breakBefore(default, null) = "auto";
	public var breakAfter(default, null) = "auto";
	public var breakInside(default, null) = "auto";
	public var pageBreakBefore(default, null) = "auto";
	public var pageBreakAfter(default, null) = "auto";
	public var pageBreakInside(default, null) = "auto";
	public var page(default, null) = "auto";
	public var orphans(default, null) = 2.0;
	public var widows(default, null) = 2.0;
	// tables: border-collapse, border-spacing (horizontal, vertical), table-layout, caption-side, empty-cells
	public var borderCollapse(default, null) = false;
	public var borderSpacing(default, null):Array<Float> = [0, 0];
	public var tableLayout(default, null) = "auto";
	public var captionSide(default, null) = "top";
	public var emptyCells(default, null) = "show";
	// the grid's: its templates, auto tracks, areas, auto-flow, an item's lines (start and end, rows then columns)
	public var gridTemplateRows(default, null):Array<CssTerm> = [Keyword("none")];
	public var gridTemplateColumns(default, null):Array<CssTerm> = [Keyword("none")];
	public var gridAutoRows(default, null):Array<CssTerm> = [Keyword("auto")];
	public var gridAutoColumns(default, null):Array<CssTerm> = [Keyword("auto")];
	public var gridTemplateAreas(default, null):Array<CssTerm> = [Keyword("none")];
	public var gridAutoFlow(default, null):Array<CssTerm> = [Keyword("row")];
	public var gridLines(default, null):Array<Array<CssTerm>> = [[Keyword("auto")], [Keyword("auto")], [Keyword("auto")], [Keyword("auto")]];
	// transform's functions and transform-origin
	public var transform(default, null):Array<CssTerm> = [Keyword("none")];
	public var transformOrigin(default, null):Array<CssTerm> = [Percentage(50), Percentage(50)];
	public var fontPalette(default, null):Array<CssTerm> = [Keyword("normal")];
	// text-decoration-thickness: from-font
	public var fromFont(default, null) = false;

	public function new() {}

	// A length's terms as a Len: a dimension or number its px, a percentage, a calc(), the first length among
	// keywords (text-indent's with hanging or each-line); else Auto.
	public static function toLen(t:Array<CssTerm>):Len
		return switch t {
			case [Dimension(v, _)]: Px(v);
			case [Percentage(v)]: Percent(v);
			case [Calc(n, _, _)]: Calc(n);
			case [Number(v, _)]: Px(v);
			case [Part(_, inner)]: toLen(inner);
			case _ if (t.length > 1): {
					for (x in t) switch x {
						case Dimension(_, _) | Percentage(_) | Calc(_, _, _): return toLen([x]);
						case _:
					}
					Auto;
				}
			case _: Auto;
		}
}
