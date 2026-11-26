package helder.ui.flow;

import helder.ui.box.Box;

// How a box lays out its contents (CSS 2.1 §9.4, Display 3's inner
// display): flow (blocks and lines), and later flex, grid, table. Each is
// an object a program creates (Contexts), so the ones it never uses are
// not in it.
interface FormattingContext {
	// The box laid out in the space: its fragment (its border box), its
	// used margins and collapsing margins on the box (Box.marginLeft...).
	function layout(box:Box, space:Space):Int;

	// Its min-content and max-content border-box widths (Box.minContent, maxContent).
	function intrinsic(box:Box, space:Space):Void;
}
