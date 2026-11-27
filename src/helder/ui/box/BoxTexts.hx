package helder.ui.box;

import haxe.ds.ObjectMap;

// A position in a box tree's text: a text box and the offset in its text
// (an atomic box's 0 or 1, before or after it; another box's -1).
typedef BoxPosition = {box:Box, offset:Int};

// The text of a laid out box tree by position: its blocks with lines,
// indexed by where they are; the position nearest a point, a caret, the
// rectangles of a selection and its text. One tree, whatever made its
// boxes (a document, code, both): a selection runs across them.
class BoxTexts {
	// the boxes with lines in this layout, in the tree's order
	public final blocks:Array<Box> = [];

	final fragments:Fragments;
	// (each block's place, absolute; each in the buckets of BUCKET px its lines cover)
	final x0:Array<Float> = [];
	final y0:Array<Float> = [];
	final x1:Array<Float> = [];
	final y1:Array<Float> = [];
	final buckets:Array<Array<Int>> = [];
	final of = new ObjectMap<Box, Int>();

	static inline var BUCKET = 256;

	public function new(fragments:Fragments, root:Null<Box>) {
		this.fragments = fragments;
		// (in tree order: a box, its children, then its next sibling)
		var b = root;
		while (b != null) {
			if (b.lines != null && b.lines.fragment < fragments.count && fragments.box(b.lines.fragment) == b) blocks.push(b);
			b = after(b, root);
		}
		var tall = 0.0;
		for (k in 0...blocks.length) {
			var id = blocks[k].lines.fragment, o = fragments.absolute(id);
			x0.push(o.x);
			y0.push(o.y);
			x1.push(o.x + fragments.width(id));
			y1.push(o.y + fragments.height(id));
			tall = Math.max(tall, o.y + fragments.height(id));
			of.set(blocks[k], k);
		}
		var n = Std.int(Math.ceil(tall / BUCKET)) + 1;
		for (_ in 0...n) buckets.push([]);
		for (k in 0...blocks.length) {
			var a = Std.int(Math.max(0, Math.floor(y0[k] / BUCKET))), z = Std.int(Math.min(n - 1, Math.floor(y1[k] / BUCKET)));
			for (i in a...z + 1) buckets[i].push(k);
		}
	}

	// (the box after b in the tree's order, within root: its first child, else the next sibling of it or an ancestor)
	static function after(b:Box, root:Null<Box>):Null<Box> {
		if (b.first != null) return b.first;
		var x:Null<Box> = b;
		while (x != null && x != root && x.next == null) x = x.parent;
		return x == null || x == root ? null : x.next;
	}

	// The position nearest (x, y), as a selection's end follows the
	// pointer: from the lines of the innermost block whose fragment holds
	// the point, else of the block nearest it above or below; null: no
	// text. Transforms aside.
	public function position(x:Float, y:Float):Null<BoxPosition> {
		if (blocks.length == 0) return null;
		var best = -1, far = Math.POSITIVE_INFINITY;
		inline function consider(k:Int) {
			var dy = y < y0[k] ? y0[k] - y : y > y1[k] ? y - y1[k] : 0.0;
			var dx = x < x0[k] ? x0[k] - x : x > x1[k] ? x - x1[k] : 0.0;
			// (inside: the innermost, the last in the tree's order; else the nearest, down then across)
			var d = dy * 1e4 + dx;
			if (d < far || d == far && k > best) {
				far = d;
				best = k;
			}
		}
		// (the bucket the point is in, then rings of buckets around it until one beyond the nearest found)
		var at = Std.int(Math.max(0, Math.min(buckets.length - 1, Math.floor(y / BUCKET)))), r = 0;
		while (r <= buckets.length) {
			for (b in [at - r, at + r]) if (b >= 0 && b < buckets.length && (r > 0 || b == at)) for (k in buckets[b]) consider(k);
			if (best >= 0 && far / 1e4 < r * BUCKET) break;
			r++;
		}
		return blocks[best].lines.hit(x - x0[best], y - y0[best]);
	}

	// (the block whose lines hold a box: up from it to the nearest with lines; -1: none)
	public function blockOf(b:Box):Int {
		var p:Null<Box> = b;
		while (p != null) {
			var k = of.get(p);
			if (k != null) return k;
			p = p.parent;
		}
		return -1;
	}

	// The caret at a position, its line's height; null: not in any lines. Transforms aside.
	public function caret(p:BoxPosition):Null<{x:Float, y:Float, height:Float}> {
		var k = blockOf(p.box);
		if (k < 0) return null;
		var l = blocks[k].lines, u = l.unitOf(p.box, p.offset);
		if (u < 0) return null;
		var c = l.caret(u);
		return {x: x0[k] + c.x, y: y0[k] + c.y, height: c.height};
	}

	// The rectangles a selection from one position to another covers: each
	// line's selected runs, the line's height, block by block in the tree's
	// order (top...bottom: the blocks there alone). Transforms aside.
	public function rects(from:BoxPosition, to:BoxPosition, top = Math.NEGATIVE_INFINITY,
			bottom = Math.POSITIVE_INFINITY):Array<{x:Float, y:Float, width:Float, height:Float}> {
		var b0 = blockOf(from.box), b1 = blockOf(to.box);
		var u0 = b0 < 0 ? -1 : blocks[b0].lines.unitOf(from.box, from.offset), u1 = b1 < 0 ? -1 : blocks[b1].lines.unitOf(to.box, to.offset);
		if (b0 < 0 || b1 < 0 || u0 < 0 || u1 < 0) return [];
		if (b1 < b0 || b1 == b0 && u1 < u0) {
			var t = b0, v = u0;
			b0 = b1;
			u0 = u1;
			b1 = t;
			u1 = v;
		}
		var out = [];
		for (k in b0...b1 + 1) {
			if (y1[k] < top || y0[k] > bottom) continue;
			var l = blocks[k].lines;
			for (r in l.selection(k == b0 ? u0 : 0, k == b1 ? u1 : l.content.text.length))
				out.push({x: x0[k] + r.x, y: y0[k] + r.y, width: r.width, height: r.height});
		}
		return out;
	}

	// The text from one position to the other, either way round: each text
	// box's part between them in the tree's order, as its text has it.
	public static function text(from:BoxPosition, to:BoxPosition):String {
		if (!before(from, to)) {
			var t = from;
			from = to;
			to = t;
		}
		var out = new StringBuf(), b:Null<Box> = from.box;
		while (b != null) {
			if (b.kind == Text) {
				var a = b == from.box ? from.offset : 0, z = b == to.box ? to.offset : b.text.length;
				if (z > a) out.add(b.text.substring(a, z));
			}
			if (b == to.box) break;
			b = after(b, null);
		}
		return out.toString();
	}

	// (whether a is at or before b in the tree's order)
	static function before(a:BoxPosition, b:BoxPosition):Bool {
		if (a.box == b.box) return a.offset <= b.offset;
		var x:Null<Box> = a.box;
		while (x != null) {
			if (x == b.box) return true;
			x = after(x, null);
		}
		return false;
	}
}
