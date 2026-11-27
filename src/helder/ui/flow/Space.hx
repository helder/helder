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
	// where a line at y of height h may go (y from the box's border box top; offset from its left),
	// and how far down it widens (next: infinity when it doesn't): floats narrow it (null: the whole width)
	public var lineWidth:Null<(y:Float, h:Float) -> Null<{offset:Float, width:Float, next:Float}>> = null;
	// a float met in a line at y (from the box's border box top): laid out and placed by the block
	public var placeFloat:Null<(box:Box, y:Float) -> Void> = null;
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
	// the absolutely positioned boxes for the nearest positioned ancestor, and the fixed ones for the root
	public var positioned:Null<Positioned> = null;
	public var fixed:Null<Positioned> = null;
	// the fragmentainer an in-flow box is laid out in (null: none, one
	// continuous flow) and its border box's top there; not passed on by
	// child(): floats, absolutely positioned boxes, atomics and table
	// cells are monolithic
	public var fragmentation:Null<Fragmentation> = null;
	public var pageTop = 0.0;
	// what must still fit below an in-flow box's content there: its cloned ancestors' bottom borders and padding
	public var reserve = 0.0;

	public function new(fragments:Fragments, fonts:FontMatch, width:Float, height:Float) {
		this.fragments = fragments;
		this.fonts = fonts;
		this.width = width;
		this.height = height;
	}

	public function child(width:Float, height:Float):Space {
		var s = new Space(fragments, fonts, width, height);
		s.exclusions = exclusions;
		s.positioned = positioned;
		s.fixed = fixed;
		s.left = left;
		s.top = top;
		return s;
	}
}
