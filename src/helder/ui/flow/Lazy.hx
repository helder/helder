package helder.ui.flow;

import helder.ui.box.Box;

// A long document laid out from its top to a bottom it is cut at (what
// is seen, then further a slice at a time): the root's formatting
// context's children from the first whose top is past bottom, or not
// styled yet (Box.UNSTYLED: a resize's restyle comes to it later), not
// laid out, nor what comes after them in each block around them. What is
// laid out is exact: nothing estimated, a block around a cut only as tall
// as what is laid out of it.
class Lazy {
	public var bottom = 0.0;
	// (each cut's block and its first child not laid out, innermost first: what is left, in the document's order)
	public final blocks:Array<Box> = [];
	public final rests:Array<Box> = [];
	// where the last layout stopped, in the root's formatting context: what is above it is laid out (a root
	// box as tall as the viewport, html { height: 100% }, ends far above it)
	public var at = Math.POSITIVE_INFINITY;

	// (a box to lay out first, the cut off till the layout has passed it (its ancestors here); then a margin past
	// it)
	var target:Null<haxe.ds.ObjectMap<Box, Bool>> = null;
	var margin = 0.0;

	public function new() {}

	// Lays out to box at least, and margin past it.
	public function reach(box:Box, margin:Float) {
		var m = new haxe.ds.ObjectMap<Box, Bool>(), b = box;
		while (b != null) {
			m.set(b, true);
			b = b.parent;
		}
		target = m;
		this.margin = margin;
	}

	// (a child laid out at top: past the box to reach where it holds it, the cut margin past it)
	public function passed(child:Box, top:Float) {
		if (target == null || !target.exists(child)) return;
		target = null;
		bottom = Math.max(bottom, top + margin);
	}

	// whether a box to reach is still ahead
	public var reaching(get, never):Bool;

	inline function get_reaching():Bool
		return target != null;

	// how many cuts the last layout made
	public var count(get, never):Int;

	inline function get_count():Int
		return blocks.length;

	public function reset() {
		at = Math.POSITIVE_INFINITY;
		blocks.resize(0);
		rests.resize(0);
	}

	// Whether the layout of block stops before child, at top in the root's
	// formatting context: past bottom, or not styled yet.
	public function cut(block:Box, child:Box, top:Float):Bool {
		if (target != null && child.flags & Box.UNSTYLED == 0 || top <= bottom && child.flags & Box.UNSTYLED == 0) return false;
		at = Math.min(at, top);
		stop(block, child);
		return true;
	}

	// The layout of block stopped before child, a cut in what came before it.
	public function stop(block:Box, child:Box) {
		blocks.push(block);
		rests.push(child);
	}
}
