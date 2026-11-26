package helder.ui.box;

import helder.canvas.Matrix;
import helder.dom.Node;

// What a point is over: the last thing painted there (PaintOrder backwards),
// through the transforms and clips around it. A text fragment gives its
// text node and the offset nearest the point; a box its element (a
// pseudo-element's, its element's).
class HitTest {
	public static function at(f:Fragments, order:PaintOrder, x:Float, y:Float):Null<{node:Node, offset:Int}> {
		var k = order.count;
		var inv = new Matrix();
		while (k-- > 0) {
			var step = order.steps[k];
			if (step == PaintOrder.OUTLINE || step == PaintOrder.BORDERS) continue;
			var id = order.fragments[k];
			var b = f.box(id);
			if (!b.style.visible || b.style.keyword("pointer-events") == "none") continue;
			var p = local(order, order.stateOf[k], x, y, inv);
			if (p == null) continue;
			var fx = order.xs[k], fy = order.ys[k];
			if (p.x < fx || p.y < fy || p.x >= fx + f.width(id) || p.y >= fy + f.height(id)) continue;
			if (f.kind(id) == Fragments.TEXT && b.node != null) return {node: b.node, offset: offset(f, id, p.x - fx)};
			var n = b;
			while (n != null && n.node == null) n = n.parent;
			if (n != null) return {node: n.node.nodeType == Node.TEXT_NODE ? n.node.parentNode : n.node, offset: -1};
		}
		return null;
	}

	// (the point in a state's space: each layer's transform undone, each clip tested; null outside a clip)
	static function local(order:PaintOrder, st:Int, x:Float, y:Float, inv:Matrix):Null<{x:Float, y:Float}> {
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
				case _:
			}
		}
		return {x: x, y: y};
	}

	// (the offset in the text node nearest x, from the fragment's glyph run)
	static function offset(f:Fragments, id:Int, x:Float):Int {
		var r = f.run(id), start = f.start(id), end = f.end(id);
		if (r < 0) return start;
		var run = f.runs[r];
		for (k in 0...run.count) {
			var gx = run.xs[k], next = k + 1 < run.count ? run.xs[k + 1] : f.width(id);
			if (x < (gx + next) / 2) return clamp(start + run.starts[k], start, end);
		}
		return end;
	}

	static inline function clamp(v:Int, a:Int, b:Int):Int
		return v < a ? a : v > b ? b : v;
}
