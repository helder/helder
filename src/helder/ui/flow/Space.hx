package helder.ui.flow;

import helder.ui.box.FontMatch;
import helder.ui.box.Fragments;

// The constraint space a box is laid out in (LayoutNG's): its containing
// block's width, the height percentages resolve against (NaN: indefinite),
// and what the whole layout shares. Layout's cache is keyed on it.
class Space {
	public final fragments:Fragments;
	public final fonts:FontMatch;
	public var width:Float;
	public var height:Float;
	// a width the box takes as its own (shrink-to-fit's, a flex item's); NaN: its own rules
	public var fixedWidth = Math.NaN;
	// the box's border widths instead of its style's (top, right, bottom, left): a cell's in
	// the collapsing border model, half of what won on each side
	public var borders:Null<Array<Float>> = null;
	// where a line at y of height h may go: floats narrow it (null: the whole width)
	public var lineWidth:Null<(y:Float, h:Float) -> {offset:Float, width:Float}> = null;

	public function new(fragments:Fragments, fonts:FontMatch, width:Float, height:Float) {
		this.fragments = fragments;
		this.fonts = fonts;
		this.width = width;
		this.height = height;
	}

	public function child(width:Float, height:Float):Space {
		var s = new Space(fragments, fonts, width, height);
		s.lineWidth = lineWidth;
		return s;
	}
}
