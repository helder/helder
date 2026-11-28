package helder.ui.flow;

import helder.ui.box.Box;
import helder.ui.box.FontMatch;
import helder.ui.box.Fragments;

// The constraint space a box is laid out in (LayoutNG's): its containing
// block's width, the height percentages resolve against (NaN: indefinite),
// and what the whole layout shares: the block formatting context's floats
// and where the box is in it, the absolutely positioned boxes waiting for
// their containing block. Layout's cache is keyed on its sizes.
class Space {
	public final fragments:Fragments;
	public final fonts:FontMatch;
	public var width:Float;
	public var height:Float;
	// a width the box takes as its own (shrink-to-fit's, a flex item's); NaN: its own rules
	public var fixedWidth = Math.NaN;
	// a border-box height the box takes as its own (a stretched or flexed flex item's); NaN: its own rules
	public var fixedHeight = Math.NaN;
	// its own height (height, min-height, max-height) left out: its content's (a flex item's content size)
	public var ignoreHeight = false;
	// the box's border widths instead of its style's (top, right, bottom, left): a cell's in
	// the collapsing border model, half of what won on each side
	public var borders:Null<Array<Float>> = null;
	// A table cell's natural border-box height, returned for row alignment.
	@:allow(helder.ui.flow.BlockFlow)
	@:allow(helder.ui.flow.TableFlow)
	var cellContentHeight = Math.NaN;
	// where a line at y of height h may go (y from the box's border box top; offset from its left),
	// and how far down it widens (next: infinity when it doesn't): floats narrow it (null: the whole width)
	public var lineWidth:Null<(y:Float, h:Float) -> Null<{offset:Float, width:Float, next:Float}>> = null;
	// a float met in a line at y (from the box's border box top): laid out and placed by the block; where
	// its margin box ends
	public var placeFloat:Null<(box:Box, y:Float) -> Float> = null;
	// the last n floats placeFloat placed taken out again (the lines laid out anew around them)
	public var unplace:Null<(n:Int) -> Void> = null;
	// an absolutely positioned box met in a line, its static position (from the box's border box)
	public var placeAbsolute:Null<(box:Box, x:Float, y:Float) -> Void> = null;
	// the block formatting context's floats (null: none yet)
	public var exclusions:Null<Exclusions> = null;
	// the containing block's content box's left, the box's border box's top, in the layout's
	// coordinates (where its floats are): what is known before the box's own margins are
	public var left = 0.0;
	public var top = 0.0;
	// the list item's inline-start edge, relative to the anonymous block with its first line
	public var outsideMarkerOffset = Math.NaN;
	// the absolutely positioned boxes for the nearest positioned ancestor, and the fixed ones for the root
	public var positioned:Null<Positioned> = null;
	public var fixed:Null<Positioned> = null;
	// a page's fixed boxes: the root places those its layout didn't come to as well
	public var repeated:Null<Repeated> = null;
	// the fragmentainer an in-flow box is laid out in (null: none, one
	// continuous flow) and its border box's top there; not passed on by
	// child(): floats, absolutely positioned boxes, atomics and table
	// cells are monolithic
	public var fragmentation:Null<Fragmentation> = null;
	public var pageTop = 0.0;
	// what must still fit below an in-flow box's content there: its cloned ancestors' bottom borders and padding
	public var reserve = 0.0;
	// no pixel grid (print, PagedView's): a collapsed border split in halves exactly, and the fonts' metrics and
	// leading unrounded (InlineConstraints.exactMetrics), not in whole pixels as Chromium's
	public var exact = false;
	// (a long document laid out to a cut: the root's formatting context's blocks past it not yet, Lazy)
	public var lazy:Null<Lazy> = null;
	// (how many layouts at other sizes a box keeps beside its last, BlockFlow's cache: fewer in a long document,
	// each one all of it)
	public var kept = 3;

	public function new(fragments:Fragments, fonts:FontMatch, width:Float, height:Float) {
		this.fragments = fragments;
		this.fonts = fonts;
		this.width = width;
		this.height = height;
	}

	// A child space made again in one given before (what a lazy layout
	// skipped kept nothing of): as child gives it, the parent's this.
	public function again(parent:Space, width:Float, height:Float):Space {
		this.width = width;
		this.height = height;
		fixedWidth = fixedHeight = Math.NaN;
		ignoreHeight = false;
		borders = null;
		cellContentHeight = Math.NaN;
		lineWidth = null;
		placeFloat = null;
		unplace = null;
		placeAbsolute = null;
		exclusions = parent.exclusions;
		positioned = parent.positioned;
		fixed = parent.fixed;
		left = parent.left;
		top = parent.top;
		outsideMarkerOffset = Math.NaN;
		repeated = null;
		fragmentation = null;
		pageTop = 0;
		reserve = 0;
		exact = parent.exact;
		lazy = null;
		return this;
	}

	public function child(width:Float, height:Float):Space {
		var s = new Space(fragments, fonts, width, height);
		s.exclusions = exclusions;
		s.positioned = positioned;
		s.fixed = fixed;
		s.left = left;
		s.top = top;
		s.exact = exact;
		s.kept = kept;
		return s;
	}
}
