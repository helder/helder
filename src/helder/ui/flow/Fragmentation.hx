package helder.ui.flow;

import haxe.ds.ObjectMap;
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
	// this fragmentainer, of count), the one before ending at bottom, at
	// the line's break (where its lines resume); true: break here. Line
	// first: the first here, at bottom (as before null)
	function inLines(box:Box, first:Int, line:Int, count:Int, bottom:Float, at:InlineBreak):Bool;
	// past box's content, its height going on, the content ending at
	// bottom; true: break here, the box to the fragmentainer's end, the rest
	// of its height in the next (resumed at line BreakToken.PAST)
	// (forced: taken, nothing after it here: a formatting context's root whose float goes on)
	function after(box:Box, bottom:Float, ?forced:Bool):Bool;
	// a float placed, its margin box ending at bottom: content before the
	// break opportunities after it (a float is whole: one that doesn't fit
	// takes the break before it, its line's or its own)
	function floated(bottom:Float):Void;
	// in-flow content laid out, its border box ending at bottom (margins
	// aside: trailing ones are truncated, they make no page of their own)
	function placed(bottom:Float):Void;
	// whether layout stops: a break was taken (or a probe went past the
	// end): containers place nothing more
	var stopped(get, never):Bool;
	// an absolutely positioned box its host lays out once the content is
	// in fragmentainers (LayoutNG's out-of-flow fragmentation): its
	// containing block broken across them, or the box not fitting in this
	// one
	function defer(d:Deferred):Void;
	// a parallel flow in box (a table cell beside the others in its row):
	// its own breaks in this fragmentainer, from its token in box's resume;
	// null: it ended in a fragmentainer before
	function parallel(box:Box, child:Box):Null<Fragmentainer>;
	// a flex or grid container's rows in this fragmentainer (Rows): made
	// here and called through FragmentRows, not by the container, so that
	// a program without a paged host (no Breaks made) links none of them
	function rows():FragmentRows;
	// (the rest: a fragmentainer of size inside this one, from a token; a
	// float carried whole to the next; a box's break-inside avoids a break,
	// its break-before forces one: Breaks', asked of the fragmentainer so
	// that a program without a paged host makes none)
	function sub(size:Float, from:Null<BreakToken>):Fragmentainer;
	function push(float:Box):Void;
	function avoids(b:Box):Bool;
	function forcesBefore(b:Box):Bool;
	// box broken inside, its parallel flows each at its own break (tokens:
	// those that go on), what is before the break ending at bottom; true:
	// break here (box resumes with the tokens, BreakToken.SPLIT). tall: box
	// is taller than a fragmentainer, its own break-inside: avoid not kept
	// (Fragmentation 3 §4.4: nowhere it would fit)
	function split(box:Box, tokens:ObjectMap<Box, BreakToken>, bottom:Float, ?tall:Bool):Bool;
	// a monolithic box past the fragmentainer's end, its border box's top at
	// top: true: break inside it (resumed at BreakToken.MONO: whole again,
	// its overflow continuing in the next, Fragmentation 3 §4.3's slicing
	// of monolithic content, as LayoutNG's); last resort, a break before it
	// first
	function monolithic(box:Box, top:Float):Bool;
	// a line of box's past the fragmentainer's end, starting at at, its top at top (above 0: what the ones before
	// showed of it): true: break inside it (resumed at BreakToken.LINE, its overflow continuing, as a monolithic
	// box's, Fragmentation 3 §4.3, as LayoutNG's); last resort, a break before it first
	function overflowing(box:Box, at:InlineBreak, top:Float):Bool;
	// a float broken across fragmentainers: its token carried to the next,
	// wherever the break is (uncarry: its line went to the next itself)
	function carry(float:Box, token:BreakToken):Void;
	function uncarry(float:Box):Void;
	// whether a float in box goes on in the next fragmentainer (carried)
	function carrying(box:Box):Bool;
	// the floats carried here host places at its content's top: those whose
	// nearest ancestor resumed here it is
	function carried(host:Box):Array<{box:Box, token:BreakToken}>;
}

// An absolutely positioned box deferred: its static place (x, y) in its
// containing block, that at cbx, cby in its owner's fragment here, cbw by
// cbh here; an alignment in an area (Positioned's).
// A fragmentainer of its own (Breaks), inside another: its breaks decided
// once its flow is laid out, the token it resumes with, what it deferred
interface Fragmentainer extends Fragmentation {
	var deferred(default, null):Array<Deferred>;
	function decide():Bool;
	function token():Null<BreakToken>;
}

// (Rows, as flex and grid containers call it)
interface FragmentRows {
	function add(key:Int, box:Box, frag:Int, x:Float, y:Float, top:Float, bottom:Float):Void;
	function place(box:Box, frag:Int, space:Space, flow:BlockFlow, left:Float, top:Float, h:Float):{height:Float, broken:Bool};
}

typedef Deferred = {
	box:Box,
	owner:Box,
	x:Float,
	y:Float,
	cbx:Float,
	cby:Float,
	cbw:Float,
	cbh:Float,
	align:Null<Array<Float>>
}

// Where a box resumes: at a child (laid out from its start, its top
// margin truncated after an unforced break), or at a line (its lines laid
// out from its break, from); the block size it already took in the
// fragmentainers before.
typedef Resume = {
	child:Null<Box>,
	line:Int,
	from:Null<InlineBreak>,
	// (broken inside: its parallel flows' tokens, by box)
	?parallel:ObjectMap<Box, BreakToken>,
	consumed:Float,
	forced:Bool,
	// (at BreakToken.LINE: what the fragmentainers before took of its line)
	?shift:Float
}
