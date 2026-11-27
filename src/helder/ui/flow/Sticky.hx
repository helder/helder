package helder.ui.flow;

import helder.ui.box.Box;
import helder.ui.box.Fragments;

// Sticky positioning (CSS Positioned Layout 3 §3.4) at a scroll of 0, after
// layout: a sticky box's border box is moved, within its containing
// block (its margin box kept in it), as far as its insets ask it to be
// from its scrollport's edges: the nearest ancestor that clips (its
// padding box), else the viewport. Outer sticky boxes first, inner ones
// then from where those put them. On pages (no scrollport) a sticky box
// stays where flow put it, positioned all the same.
class Sticky {
	public static function apply(f:Fragments, root:Int, width:Float, height:Float) {
		if (root < 0) return;
		var stack = [root];
		while (stack.length > 0) {
			var id = stack.pop();
			if (f.kind(id) == Fragments.BOX && f.box(id).style.position == "sticky") stick(f, id, width, height);
			var c = f.first(id);
			var kids = [];
			while (c >= 0) {
				kids.push(c);
				c = f.next(c);
			}
			var k = kids.length;
			while (k-- > 0) stack.push(kids[k]);
		}
	}

	static function stick(f:Fragments, id:Int, width:Float, height:Float) {
		var b = f.box(id), s = b.style;
		var at = f.absolute(id), w = f.width(id), h = f.height(id);
		// (the scrollport: the nearest ancestor that clips, its padding box; else the viewport)
		var px = 0.0, py = 0.0, pw = width, ph = height;
		var p = f.parent(id);
		while (p >= 0) {
			var pb = f.box(p);
			if (f.kind(p) == Fragments.BOX && pb.style.clips) {
				var m = pb.style.model(), o = f.absolute(p);
				px = o.x + m.border[3];
				py = o.y + m.border[0];
				pw = f.width(p) - m.border[1] - m.border[3];
				ph = f.height(p) - m.border[0] - m.border[2];
				break;
			}
			p = f.parent(p);
		}
		// (its containing block: its parent's content box)
		var parent = f.parent(id);
		if (parent < 0) return;
		var pm = f.box(parent).style.model(), po = f.absolute(parent), pwid = f.width(parent);
		var cx0 = po.x + pm.border[3] + BlockFlow.res(pm.padding[3], pwid), cy0 = po.y + pm.border[0] + BlockFlow.res(pm.padding[0], pwid);
		var cx1 = po.x + pwid - pm.border[1] - BlockFlow.res(pm.padding[1], pwid);
		var cy1 = po.y + f.height(parent) - pm.border[2] - BlockFlow.res(pm.padding[2], pwid);
		var m = s.model();
		var mt = BlockFlow.res(m.margin[0], pwid), mb = BlockFlow.res(m.margin[2], pwid);
		var ml = BlockFlow.res(m.margin[3], pwid), mr = BlockFlow.res(m.margin[1], pwid);
		var top = BlockFlow.auto(s.inset(0), ph), bottom = BlockFlow.auto(s.inset(2), ph);
		var left = BlockFlow.auto(s.inset(3), pw), right = BlockFlow.auto(s.inset(1), pw);
		var dx = 0.0, dy = 0.0;
		if (!Math.isNaN(top) && at.y < py + top) dy = Math.min(py + top - at.y, Math.max(0, cy1 - (at.y + h + mb)));
		if (!Math.isNaN(bottom) && at.y + h + dy > py + ph - bottom) dy = Math.max(py + ph - bottom - (at.y + h), Math.min(0, cy0 - (at.y - mt)));
		if (!Math.isNaN(left) && at.x < px + left) dx = Math.min(px + left - at.x, Math.max(0, cx1 - (at.x + w + mr)));
		if (!Math.isNaN(right) && at.x + w + dx > px + pw - right) dx = Math.max(px + pw - right - (at.x + w), Math.min(0, cx0 - (at.x - ml)));
		if (dx != 0 || dy != 0) f.moveTo(id, f.x(id) + dx, f.y(id) + dy);
	}
}
