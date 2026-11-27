package helder.ui.flow;

import helder.ui.box.Box;

// A long document laid out where it is seen, as if its blocks had
// content-visibility: auto: a block far from the window (top...bottom of
// the root's formatting context) whose layout isn't kept is given an
// estimated height (estimate's: its last layout's, else its text's) and
// its contents are skipped, until the window comes near it. Only a block
// with nothing in it that reaches outside it (Box.LAZY: no floats, nothing
// positioned) is.
class Lazy {
	public var top = 0.0;
	public var bottom = 0.0;
	// (a block's content height at a content width, its contents unlaid)
	final estimate:(box:Box, width:Float) -> Float;
	// (the blocks skipped in the last layout, in order: their tops and heights)
	public final boxes:Array<Box> = [];
	final tops:Array<Float> = [];
	final heights:Array<Float> = [];

	public function new(estimate:(box:Box, width:Float) -> Float)
		this.estimate = estimate;

	// how many blocks the last layout skipped
	public var count(get, never):Int;

	inline function get_count():Int
		return tops.length;

	public function reset() {
		boxes.resize(0);
		tops.resize(0);
		heights.resize(0);
	}

	// The content height to give a block at top, width wide, its contents
	// skipped; NaN: laid out.
	public function skip(box:Box, top:Float, width:Float):Float {
		if (box.flags & Box.LAZY == 0) return Math.NaN;
		// (a table its last size, its width not its containing block's: what its columns take)
		var h = box.kind == TableWrapper && box.laidHeight > 0 ? box.laidHeight : estimate(box, width);
		if (top <= bottom && top + h >= this.top) return Math.NaN;
		boxes.push(box);
		tops.push(top);
		heights.push(h);
		if (box.flags & Box.KEPT != 0) release(box);
		return h;
	}

	// (what its contents' last layout kept let go, laid out again when it is: a long document holds what is near
	// the window, not all it was shown)
	static function release(box:Box) {
		var stack = [box];
		while (stack.length > 0) {
			var b = stack.pop();
			b.flags &= ~Box.KEPT;
			b.lines = null;
			b.inlineCache = null;
			b.uncache();
			var c = b.first;
			while (c != null) {
				stack.push(c);
				c = c.next;
			}
		}
	}

	// Whether a block the last layout skipped is in top...bottom.
	public function skipped(top:Float, bottom:Float):Bool
		return first(top, bottom) >= 0;

	// The blocks the last layout skipped in top...bottom.
	public function within(top:Float, bottom:Float):Array<Box> {
		var k = first(top, bottom), out = [];
		if (k < 0) return out;
		while (k < tops.length && tops[k] <= bottom) {
			if (tops[k] + heights[k] >= top) out.push(boxes[k]);
			k++;
		}
		return out;
	}

	// (the first skipped block in top...bottom; -1: none)
	function first(top:Float, bottom:Float):Int {
		// (the first whose top is past top's less the tallest: the tops are in the flow's order)
		var lo = 0, hi = tops.length;
		while (lo < hi) {
			var mid = (lo + hi) >> 1;
			if (tops[mid] + heights[mid] < top) lo = mid + 1 else hi = mid;
		}
		for (k in lo...tops.length) {
			if (tops[k] > bottom) return -1;
			if (tops[k] + heights[k] >= top) return k;
		}
		return -1;
	}
}
