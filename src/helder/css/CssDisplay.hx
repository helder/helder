package helder.css;

import helder.css.CssTerm;

enum abstract CssOuterDisplay(Int) {
	var Block;
	var Inline;
	var RunIn;
	// a table's or ruby's part
	var Internal;
	var None;
	var Contents;
}

enum abstract CssInnerDisplay(Int) {
	var Flow;
	var FlowRoot;
	var Table;
	var Flex;
	var Grid;
	var GridLanes;
	var Ruby;
	var MathML;
	var TableRowGroup;
	var TableHeaderGroup;
	var TableFooterGroup;
	var TableRow;
	var TableCell;
	var TableColumnGroup;
	var TableColumn;
	var TableCaption;
	var RubyBase;
	var RubyText;
	var RubyBaseContainer;
	var RubyTextContainer;
}

// A computed display, decoded (Display 3 §2): its outer and inner types,
// whether it's a list item; original: the display before blockification
// (Display 3 §2.7), itself when there was none (an absolutely positioned
// box that was inline-level has its static position on the line). Interned
// per document.
class CssDisplay {
	public final outer:CssOuterDisplay;
	public final inner:CssInnerDisplay;
	public final listItem:Bool;
	public final terms:Array<CssTerm>;
	public var original(default, null):CssDisplay;
	@:allow(helder.css) var id = -1;

	function new(outer:CssOuterDisplay, inner:CssInnerDisplay, listItem:Bool, terms:Array<CssTerm>) {
		this.outer = outer;
		this.inner = inner;
		this.listItem = listItem;
		this.terms = terms;
		original = this;
	}

	@:allow(helder.css)
	static function of(t:Array<CssTerm>):CssDisplay {
		var outer = Block, inner = Flow, listItem = false, inlineDefault = false;
		for (x in t) switch x {
			case Keyword(k): switch k {
					case "block": outer = Block;
					case "inline": outer = Inline;
					case "run-in": outer = RunIn;
					case "none": outer = None;
					case "contents": outer = Contents;
					case "list-item": listItem = true;
					case "flow": inner = Flow;
					case "flow-root": inner = FlowRoot;
					case "table": inner = Table;
					case "flex": inner = Flex;
					case "grid": inner = Grid;
					case "grid-lanes": inner = GridLanes;
					case "ruby": inner = Ruby;
					case "math": inner = MathML;
					case "inline-block": outer = Inline; inner = FlowRoot;
					case "inline-table": outer = Inline; inner = Table;
					case "inline-flex": outer = Inline; inner = Flex;
					case "inline-grid": outer = Inline; inner = Grid;
					case "inline-grid-lanes": outer = Inline; inner = GridLanes;
					case _:
						var part = INTERNAL.get(k);
						if (part != null) {
							outer = Internal;
							inner = part;
						}
				}
			case _:
		}
		// (ruby and math alone are inline-level)
		if (t.length == 1 && (inner == Ruby || inner == MathML) && outer == Block) outer = Inline;
		return new CssDisplay(outer, inner, listItem, t);
	}

	static final INTERNAL = [
		"table-row-group" => TableRowGroup, "table-header-group" => TableHeaderGroup, "table-footer-group" => TableFooterGroup,
		"table-row" => TableRow, "table-cell" => TableCell, "table-column-group" => TableColumnGroup, "table-column" => TableColumn,
		"table-caption" => TableCaption, "ruby-base" => RubyBase, "ruby-text" => RubyText, "ruby-base-container" => RubyBaseContainer,
		"ruby-text-container" => RubyTextContainer
	];
}
