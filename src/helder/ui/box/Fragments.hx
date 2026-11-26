package helder.ui.box;

import helder.canvas.ShapedRun;

// Layout's output, flat (LayoutNG's fragments as struct-of-arrays): a
// fragment is an id into these columns, no object each. Box fragments
// (a block's, an atomic inline's), line boxes, inline boxes' parts on a
// line (spans) and text fragments, each with its parent, its children and
// its place in its parent's border box (x, y: the parent's top left).
// Text fragments draw a glyph run (`runs`, helder.canvas's: what paint and
// PdfWriter share).
class Fragments {
	public static inline var BOX = 0;
	public static inline var LINE = 1;
	public static inline var SPAN = 2;
	public static inline var TEXT = 3;

	public var count(default, null) = 0;

	final kinds:Array<Int> = [];
	final boxes:Array<Box> = [];
	final parents:Array<Int> = [];
	final firsts:Array<Int> = [];
	final lasts:Array<Int> = [];
	final nexts:Array<Int> = [];
	final xs:Array<Float> = [];
	final ys:Array<Float> = [];
	final ws:Array<Float> = [];
	final hs:Array<Float> = [];
	final baselines:Array<Float> = [];
	final starts:Array<Int> = [];
	final ends:Array<Int> = [];
	final datas:Array<Int> = [];
	public final runs:Array<ShapedRun> = [];

	public function new() {}

	public function clear() {
		count = 0;
		runs.resize(0);
	}

	var capacity = 0;

	public function add(kind:Int, box:Box, width:Float, height:Float):Int {
		var id = count++;
		if (id >= capacity) grow();
		kinds[id] = kind;
		boxes[id] = box;
		parents[id] = -1;
		firsts[id] = -1;
		lasts[id] = -1;
		nexts[id] = -1;
		xs[id] = 0;
		ys[id] = 0;
		ws[id] = width;
		hs[id] = height;
		baselines[id] = Math.NaN;
		starts[id] = 0;
		ends[id] = 0;
		datas[id] = -1;
		return id;
	}

	// (every column a size up at once: a growth by one is a copy per fragment)
	function grow() {
		capacity = capacity < 64 ? 64 : capacity * 2;
		kinds.resize(capacity);
		boxes.resize(capacity);
		parents.resize(capacity);
		firsts.resize(capacity);
		lasts.resize(capacity);
		nexts.resize(capacity);
		xs.resize(capacity);
		ys.resize(capacity);
		ws.resize(capacity);
		hs.resize(capacity);
		baselines.resize(capacity);
		starts.resize(capacity);
		ends.resize(capacity);
		datas.resize(capacity);
	}

	// child appended to parent's children, at (x, y) in it
	public function adopt(parent:Int, child:Int, x:Float, y:Float) {
		parents[child] = parent;
		nexts[child] = -1;
		xs[child] = x;
		ys[child] = y;
		if (lasts[parent] < 0) firsts[parent] = child else nexts[lasts[parent]] = child;
		lasts[parent] = child;
	}

	// (a fragment made again: its children dropped)
	public function empty(id:Int) {
		firsts[id] = -1;
		lasts[id] = -1;
	}

	public inline function kind(id:Int):Int
		return kinds[id];

	public inline function box(id:Int):Box
		return boxes[id];

	public inline function parent(id:Int):Int
		return parents[id];

	public inline function first(id:Int):Int
		return firsts[id];

	public inline function next(id:Int):Int
		return nexts[id];

	public inline function x(id:Int):Float
		return xs[id];

	public inline function y(id:Int):Float
		return ys[id];

	public inline function width(id:Int):Float
		return ws[id];

	public inline function height(id:Int):Float
		return hs[id];

	public inline function moveTo(id:Int, x:Float, y:Float) {
		xs[id] = x;
		ys[id] = y;
	}

	public inline function resize(id:Int, w:Float, h:Float) {
		ws[id] = w;
		hs[id] = h;
	}

	// a line's or text's baseline, a box's last line's (from its top); NaN: none
	public inline function baseline(id:Int):Float
		return baselines[id];

	public inline function setBaseline(id:Int, b:Float)
		baselines[id] = b;

	// a text fragment's range of its box's text; a span's edges (Box.NO_START, NO_END)
	public inline function start(id:Int):Int
		return starts[id];

	public inline function end(id:Int):Int
		return ends[id];

	public inline function setRange(id:Int, start:Int, end:Int) {
		starts[id] = start;
		ends[id] = end;
	}

	// a text fragment's glyph run (runs), else -1
	public inline function run(id:Int):Int
		return datas[id];

	public inline function setRun(id:Int, run:Int)
		datas[id] = run;

	// the fragment's top left in the root's coordinates (relative offsets included)
	public function absolute(id:Int):{x:Float, y:Float} {
		var x = 0.0, y = 0.0;
		while (id >= 0) {
			x += xs[id];
			y += ys[id];
			id = parents[id];
		}
		return {x: x, y: y};
	}

	// (bytes a fragment takes in these columns: 7 floats' and ints' and a box's reference)
	public static inline var BYTES = 5 * 8 + 8 * 4 + 8;
}
