package helder.ui.box;

import helder.canvas.Matrix;
import helder.dom.Node;
import helder.ui.flow.BlockFlow;

// What a point is over: the last thing painted there (PaintOrder backwards),
// through the transforms and clips around it. A text fragment gives the
// DOM position nearest the point, from its block's lines (InlineLayout's
// hit testing: a glyph's nearer half by its direction, a ligature's
// parts); a box its element (a pseudo-element's, its element's).
class HitTest {
	// (scrolls: scroll containers' offsets by their element, as BoxPainter's)
	public static function at(f:Fragments, order:PaintOrder, x:Float, y:Float, ?scrolls:haxe.ds.ObjectMap<Node, Array<Float>>):Null<{node:Node, offset:Int}> {
		var k = order.count;
		var inv = new Matrix();
		// (a run of steps whose bounds miss the point passed over at once)
		var runs = order.chunks();
		while (k-- > 0) {
			if (k % PaintOrder.CHUNK == PaintOrder.CHUNK - 1 || k == order.count - 1) {
				var r = Std.int(k / PaintOrder.CHUNK) * 4;
				if (x < runs[r] || y < runs[r + 1] || x > runs[r + 2] || y > runs[r + 3]) {
					k -= k % PaintOrder.CHUNK;
					continue;
				}
			}
			var step = order.steps[k];
			if (step == PaintOrder.OUTLINE || step == PaintOrder.BORDERS) continue;
			var id = order.fragments[k];
			var b = f.box(id);
			if (!b.style.visible || b.style.keyword("pointer-events") == "none") continue;
			var p = local(f, order, order.stateOf[k], x, y, inv, scrolls);
			if (p == null) continue;
			var fx = order.xs[k], fy = order.ys[k];
			if (p.x < fx || p.y < fy || p.x >= fx + f.width(id) || p.y >= fy + f.height(id)) continue;
			if (f.kind(id) == Fragments.TEXT && b.node != null) {
				// (the lines' answer when it is in this fragment's node: a marker's text, generated text, isn't in them)
				var at = text(f, id, p.x - fx, p.y - fy);
				return at != null && at.node == b.node ? at : {node: b.node, offset: offset(f, id, p.x - fx)};
			}
			var n = b;
			while (n != null && n.node == null) n = n.parent;
			if (n != null) return {node: n.node.nodeType == Node.TEXT_NODE ? n.node.parentNode : n.node, offset: -1};
		}
		return null;
	}

	// (the point in a state's space: each layer's transform undone, each clip tested; null outside a clip)
	static function local(f:Fragments, order:PaintOrder, st:Int, x:Float, y:Float, inv:Matrix, scrolls:Null<haxe.ds.ObjectMap<Node, Array<Float>>>):Null<{x:Float, y:Float}> {
		var chain = [];
		while (st != 0) {
			chain.push(st);
			st = order.parents[st];
		}
		var k = chain.length;
		while (k-- > 0) {
			var s = chain[k];
			switch order.kinds[s] {
				case PaintOrder.LAYER:
					var m = order.matrices[s];
					if (m != null) {
						if (!m.invertInto(inv)) return null;
						var nx = inv.mapX(x, y), ny = inv.mapY(x, y);
						x = nx;
						y = ny;
					}
				case PaintOrder.CLIP:
					var r = order.rects[s];
					if (x < r[0] || y < r[1] || x >= r[0] + r[2] || y >= r[1] + r[3]) return null;
					var o = order.scroller[s] && scrolls != null ? scrolls.get(f.box(order.layerFragment[s]).node) : null;
					if (o != null) {
						x += o[0];
						y += o[1];
					}
				case _:
			}
		}
		return {x: x, y: y};
	}

	// (the position in a text fragment's block's lines: the point taken to
	// the block's fragment, its inline boxes' relative offsets undone, as
	// the lines have them)
	static function text(f:Fragments, id:Int, x:Float, y:Float):Null<{node:Node, offset:Int}> {
		var owner = id;
		while (owner >= 0 && !(f.kind(owner) == Fragments.BOX && f.box(owner).lines != null && f.box(owner).lines.fragment == owner))
			owner = f.parent(owner);
		if (owner < 0) return null;
		var lines = f.box(owner).lines;
		var p = id;
		while (p != owner) {
			x += f.x(p);
			y += f.y(p);
			if (f.kind(p) == Fragments.SPAN) {
				var off = BlockFlow.offset(f.box(p), lines.width, Math.NaN);
				x -= off.x;
				y -= off.y;
			}
			p = f.parent(p);
		}
		return lines.hit(x, y);
	}

	// (the offset in the text node nearest x, from the fragment's glyph run: no lines kept for it)
	static function offset(f:Fragments, id:Int, x:Float):Int {
		var r = f.run(id), start = f.start(id), end = f.end(id);
		if (r < 0) return start;
		var run = f.glyphs(id), base = 0x7FFFFFFF;
		if (run == null) return start;
		// (its characters' offsets are in its content's whole text: the fragment's first the smallest)
		for (k in 0...run.count) if (run.start(k) < base) base = run.start(k);
		for (k in 0...run.count) {
			var gx = run.x(k), next = k + 1 < run.count ? run.x(k + 1) : f.width(id);
			if (x < (gx + next) / 2) return clamp(start + run.start(k) - base, start, end);
		}
		return end;
	}

	static inline function clamp(v:Int, a:Int, b:Int):Int
		return v < a ? a : v > b ? b : v;
}
