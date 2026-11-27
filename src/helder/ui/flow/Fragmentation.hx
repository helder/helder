package helder.ui.flow;

import helder.ui.box.Box;

// A fragmentainer flow is laid out in (CSS Fragmentation 3): what block
// layout asks at its break opportunities, and where a box resumes. The
// decisions (which break, its appeal, the tokens) are the object's: a
// paged host creates one (Breaks); a screen has none, and flow only
// tests it for null. Offsets are block offsets in the fragmentainer.
interface Fragmentation {
	// its block size
	var size(default, null):Float;
	// where a box resumes in this fragmentainer: null, from its start
	function resume(box:Box):Null<Resume>;
	// a box's content starts at top (flow says so before laying it out)
	function enter(box:Box, top:Float):Void;
	// class A: between in-flow siblings before and after in box, what is
	// before them ending at bottom; true: break here, after is not laid out.
	// Before null: after is box's first here, at bottom (a break there only
	// when it starts past the end, its margins truncated)
	function between(box:Box, before:Null<Box>, after:Box, bottom:Float):Bool;
	// class B: between box's lines line - 1 and line (from its first in
	// this fragmentainer, of count), the one before ending at bottom; true:
	// break here. Line first: the first here, at bottom (as before null)
	function inLines(box:Box, first:Int, line:Int, count:Int, bottom:Float):Bool;
	// in-flow content laid out, its border box ending at bottom (margins
	// aside: trailing ones are truncated, they make no page of their own)
	function placed(bottom:Float):Void;
	// whether layout stops: a break was taken (or a probe went past the
	// end): containers place nothing more
	var stopped(get, never):Bool;
}

// Where a box resumes: at a child (laid out from its start, its top
// margin truncated after an unforced break), or at a line; the block
// size it already took in the fragmentainers before.
typedef Resume = {
	child:Null<Box>,
	line:Int,
	consumed:Float,
	forced:Bool
}
