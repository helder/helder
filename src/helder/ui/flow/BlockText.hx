package helder.ui.flow;

import helder.ui.box.Box;

// A block container's lines kept for hit testing, carets and selection
// (InlineLayout's, in its boxes' positions through InlineContent): its content and
// constraints, laid out again on the first question (the floats beside it
// stay where they were). Its coordinates are its fragment's: the lines'
// origin at x, y in it.
class BlockText {
	public final content:InlineContent;
	public final fragment:Int;
	public final x:Float;
	public final y:Float;

	final constraints:InlineConstraints;
	var laid:Null<InlineLayout> = null;

	public function new(content:InlineContent, constraints:InlineConstraints, fragment:Int, x:Float, y:Float) {
		this.content = content;
		this.constraints = constraints;
		this.fragment = fragment;
		this.x = x;
		this.y = y;
	}

	// (the width the lines were laid out in: what percentages in them resolve against)
	public var width(get, never):Float;

	inline function get_width():Float
		return constraints.width;

	function lines():InlineLayout
		return laid ??= new InlineLayout().layout(content, constraints);

	// The position nearest (px, py) in the fragment: a text box and the offset in its text (an atomic's 0 or 1).
	public function hit(px:Float, py:Float):Null<{box:Box, offset:Int}> {
		var h = lines().hitTest(px - x, py - y);
		if (h.item < 0) return null;
		var p = content.position(h.offset);
		return p.box == null ? null : {box: p.box, offset: p.offset};
	}

	// A position's unit in the content; -1: not in it.
	public inline function unitOf(box:Box, offset:Int):Int
		return content.unitOf(box, offset);

	// The caret before a unit, in the fragment.
	public function caret(unit:Int):{x:Float, y:Float, height:Float} {
		var c = lines().caret(unit);
		return {x: x + c.x, y: y + c.y, height: c.height};
	}

	// The rectangles of the units from...to, in the fragment.
	public function selection(from:Int, to:Int):Array<{x:Float, y:Float, width:Float, height:Float}>
		return [for (r in lines().selection(from, to)) {x: x + r.x, y: y + r.y, width: r.width, height: r.height}];
}
