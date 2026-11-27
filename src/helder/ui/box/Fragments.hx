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
	// (how many times cleared: a fragment's id another's after it)
	public var epoch(default, null) = 0;

	var kinds = new haxe.ds.Vector<Int>(0);
	var boxes = new haxe.ds.Vector<Box>(0);
	var parents = new haxe.ds.Vector<Int>(0);
	var firsts = new haxe.ds.Vector<Int>(0);
	var lasts = new haxe.ds.Vector<Int>(0);
	var nexts = new haxe.ds.Vector<Int>(0);
	var xs = new haxe.ds.Vector<Float>(0);
	var ys = new haxe.ds.Vector<Float>(0);
	var ws = new haxe.ds.Vector<Float>(0);
	var hs = new haxe.ds.Vector<Float>(0);
	var baselines = new haxe.ds.Vector<Float>(0);
	var starts = new haxe.ds.Vector<Int>(0);
	var ends = new haxe.ds.Vector<Int>(0);
	var datas = new haxe.ds.Vector<Int>(0);
	// (how far each one's subtree paints above its top and down from it: ink, worked out once)
	var inkTops = new haxe.ds.Vector<Float>(0);
	var inkBottoms = new haxe.ds.Vector<Float>(0);
	public final runs:Array<Null<ShapedRun>> = [];
	// (by run: a line's plain text whose run is made when first asked for, glyphs(): its content, item, units
	// and fonts, the layout's palettes)
	final lazyContent:Array<Null<helder.ui.flow.InlineContent>> = [];
	final lazyItem:Array<Int> = [];
	final lazyStart:Array<Int> = [];
	final lazyEnd:Array<Int> = [];
	final lazyFonts:Array<Null<helder.text.FontSet>> = [];
	var palettes:Null<FontMatch> = null;

	public function new() {}

	public function clear() {
		count = 0;
		epoch++;
		runs.resize(0);
		lazyContent.resize(0);
		lazyFonts.resize(0);
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
		inkTops[id] = Math.NaN;
		return id;
	}

	// (every column a size up at once: a growth by one is a copy per fragment)
	// (a column at a larger size: Vector's, as an Array's capacity goes to the next power of two; one a type,
	// a generic copy goes an element at a time)
	static function ints(v:haxe.ds.Vector<Int>, n:Int):haxe.ds.Vector<Int> {
		var w = new haxe.ds.Vector<Int>(n);
		haxe.ds.Vector.blit(v, 0, w, 0, v.length);
		return w;
	}

	static function floats(v:haxe.ds.Vector<Float>, n:Int):haxe.ds.Vector<Float> {
		var w = new haxe.ds.Vector<Float>(n);
		haxe.ds.Vector.blit(v, 0, w, 0, v.length);
		return w;
	}

	static function refs(v:haxe.ds.Vector<Box>, n:Int):haxe.ds.Vector<Box> {
		var w = new haxe.ds.Vector<Box>(n);
		haxe.ds.Vector.blit(v, 0, w, 0, v.length);
		return w;
	}

	function grow() {
		// (doubling while small, then half as many more: a long document's columns a sixth empty, not a third)
		capacity = capacity < 64 ? 64 : capacity < 262144 ? capacity * 2 : capacity + (capacity >> 1);
		kinds = ints(kinds, capacity);
		boxes = refs(boxes, capacity);
		parents = ints(parents, capacity);
		firsts = ints(firsts, capacity);
		lasts = ints(lasts, capacity);
		nexts = ints(nexts, capacity);
		xs = floats(xs, capacity);
		ys = floats(ys, capacity);
		ws = floats(ws, capacity);
		hs = floats(hs, capacity);
		baselines = floats(baselines, capacity);
		starts = ints(starts, capacity);
		ends = ints(ends, capacity);
		datas = ints(datas, capacity);
		inkTops = floats(inkTops, capacity);
		inkBottoms = floats(inkBottoms, capacity);
	}

	// child appended to parent's children, at (x, y) in it
	// How far a fragment's subtree paints above its top (its own top 0)
	// and down from it: its border box, what its style paints past it (a
	// shadow, an outline), its children's but past a clip; everywhere
	// (infinities) where a transform moves it. Worked out once a fragment:
	// one reused keeps its subtree, and so its ink.
	public function inkTop(id:Int):Float {
		ink(id);
		return inkTops[id];
	}

	public function inkBottom(id:Int):Float {
		ink(id);
		return inkBottoms[id];
	}

	function ink(id:Int) {
		if (inkTops[id] == inkTops[id]) return;
		var top = 0.0, bottom = hs[id], b = boxes[id], k = kinds[id];
		var clips = false;
		if (b != null && (k == BOX || k == SPAN)) {
			var s = b.style;
			if (s.transformed) {
				inkTops[id] = Math.NEGATIVE_INFINITY;
				inkBottoms[id] = Math.POSITIVE_INFINITY;
				return;
			}
			var r = s.reach;
			if (r != r) r = s.reach = BoxPainter.reach(s);
			top -= r;
			bottom += r;
			clips = k == BOX && s.clips;
		}
		if (!clips) {
			var c = firsts[id];
			while (c >= 0) {
				ink(c);
				var t = ys[c] + inkTops[c], e = ys[c] + inkBottoms[c];
				if (t < top) top = t;
				if (e > bottom) bottom = e;
				c = nexts[c];
			}
		}
		inkTops[id] = top;
		inkBottoms[id] = bottom;
	}

	public function adopt(parent:Int, child:Int, x:Float, y:Float) {
		parents[child] = parent;
		nexts[child] = -1;
		xs[child] = x;
		ys[child] = y;
		if (lasts[parent] < 0) firsts[parent] = child else nexts[lasts[parent]] = child;
		lasts[parent] = child;
	}

	// a child taken out of its parent's children again
	public function remove(child:Int) {
		var p = parents[child];
		if (p < 0) return;
		var prev = -1, k = firsts[p];
		while (k >= 0 && k != child) {
			prev = k;
			k = nexts[k];
		}
		if (k < 0) return;
		if (prev < 0) firsts[p] = nexts[child] else nexts[prev] = nexts[child];
		if (lasts[p] == child) lasts[p] = prev;
		parents[child] = -1;
		nexts[child] = -1;
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

	// a text fragment's glyphs (null: none), made from its line's text the first time where they were left for later
	public function glyphs(id:Int):Null<ShapedRun> {
		var r = datas[id];
		if (r < 0 || r >= runs.length) return null;
		var g = runs[r];
		if (g != null) return g;
		var c = r < lazyContent.length ? lazyContent[r] : null;
		return c == null ? null : runs[r] = helder.ui.flow.LazyText.make(c, lazyItem[r], lazyStart[r], lazyEnd[r], lazyFonts[r], boxes[id], palettes);
	}

	// a text fragment's run left for later (glyphs()): an item's text from start to end in its content
	public function later(id:Int, content:helder.ui.flow.InlineContent, item:Int, start:Int, end:Int, fonts:helder.text.FontSet,
			palettes:FontMatch) {
		var r = runs.length;
		datas[id] = r;
		runs.push(null);
		lazyContent[r] = content;
		lazyItem[r] = item;
		lazyStart[r] = start;
		lazyEnd[r] = end;
		lazyFonts[r] = fonts;
		this.palettes = palettes;
	}

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
