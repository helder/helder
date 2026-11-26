package helder.dom;

// An element's dynamic state, the bits an engine sets as a person uses the
// document (hover, focus...) and form controls' state no attribute holds
// (a checkbox's checkedness once clicked, indeterminate): Element.state, an
// engine's extra as source offsets are, not the DOM's. A printed page keeps
// every bit off. CHECKED counts only with CHECKED_DIRTY set (HTML's dirty
// checkedness flag); without it the checked attribute says.
enum abstract ElementState(Int) to Int {
	var HOVER = 1;
	var ACTIVE = 2;
	var FOCUS = 4;
	var FOCUS_VISIBLE = 8;
	// (the engine sets it on the focused element's ancestors and itself)
	var FOCUS_WITHIN = 16;
	var TARGET = 32;
	var CHECKED = 64;
	var CHECKED_DIRTY = 128;
	var INDETERMINATE = 256;
}
