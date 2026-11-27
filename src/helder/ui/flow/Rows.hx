package helder.ui.flow;

import haxe.ds.ObjectMap;
import helder.ui.box.Box;

// A flex or grid container's items in a fragmentainer (CSS Fragmentation
// with Flexbox §10 and Grid §12): rows down the block axis, a flex line's
// items or a grid's rows that spanning items join, each laid out first as
// one flow; a break between rows (a row's break-before and break-after its
// items': the one forcing a break, else avoiding one), or inside a row's
// item when it is the only one; each row placed after the one before as
// the layout spaced them, the first here at the top. Items sharing a row
// are whole: broken in parallel, they need a token of several resumes.
class Rows {
	final rows:Array<Row> = [];

	public function new() {}

	// an item in row key, its fragment at x and y in the content box, its margin box's top and bottom there
	public function add(key:Int, box:Box, frag:Int, x:Float, y:Float, top:Float, bottom:Float) {
		var r:Null<Row> = null;
		for (row in rows) if (row.key == key) r = row;
		if (r == null) rows.push(r = {key: key, items: [], top: top, bottom: bottom});
		r.items.push({box: box, frag: frag, x: x, y: y, after: bottom});
		if (top < r.top) r.top = top;
		if (bottom > r.bottom) r.bottom = bottom;
	}

	// The rows here, adopted by frag at left and top (the content box's), from where box resumes to a break;
	// h the content height laid out whole. The height they take here, whether a break was taken.
	public function place(box:Box, frag:Int, space:Space, flow:BlockFlow, left:Float, top:Float, h:Float):{height:Float, broken:Bool} {
		var fr = space.fragmentation, frags = space.fragments;
		if (rows.length == 0) return {height: h, broken: false};
		rows.sort((a, b) -> a.top < b.top ? -1 : a.top > b.top ? 1 : 0);
		var resume = fr.resume(box), first = 0;
		if (resume != null && (resume.child != null || resume.parallel != null))
			for (k in 0...rows.length) for (it in rows[k].items) if (it.box == resume.child || resume.parallel != null && resume.parallel.exists(it.box)) first = k;
		var base = space.reserve + space.pageTop + top;
		fr.enter(box, space.pageTop + top);
		var end = 0.0;
		for (k in first...rows.length) {
			var r = rows[k];
			var pos = k == first ? 0.0 : end + (r.top - rows[k - 1].bottom);
			var prev = k == first ? null : pick(rows[k - 1].items, "break-after", true);
			if ((k > first || resume == null) && fr.between(box, prev, pick(r.items, "break-before", false), base + (prev == null ? pos : end)))
				return {height: end, broken: true};
			// (several items crossing the fragmentainer's end, or resumed broken: each a parallel flow at its own break)
			var inside = k == first && resume != null && resume.parallel != null;
			if (r.items.length > 1 && (inside || base + pos + r.bottom - r.top > fr.size + 0.01)) {
				var p = parallel(box, frag, r, space, flow, left, top, pos, h, inside);
				if (p.tokens.iterator().hasNext() && p.progress) {
					if (fr.split(box, p.tokens, base + p.reach) || fr.stopped) return {height: p.reach, broken: true};
					// (the break not taken here: the row as it would go on, for the opportunities after it)
					fr.placed(base + pos + r.bottom - r.top);
					end = Math.max(p.reach, pos + r.bottom - r.top);
					continue;
				}
				if (inside) {
					end = p.reach;
					continue;
				}
			}
			var reach = pos;
			for (it in r.items) {
				var f = it.frag;
				var dy = fr.resume(it.box) != null ? 0 : it.y - r.top;
				// (alone in its row: laid out again in the fragmentainer, where it is in it)
				if (r.items.length == 1) {
					var cs = space.child(frags.width(it.frag), h);
					cs.fixedWidth = frags.width(it.frag);
					cs.fixedHeight = frags.height(it.frag);
					cs.fragmentation = fr;
					cs.pageTop = space.pageTop + top + pos + dy;
					cs.reserve = space.reserve;
					it.box.cacheFragment = -1;
					f = flow.child(it.box, cs);
				}
				frags.adopt(frag, f, left + it.x, top + pos + dy);
				var bottom = pos + dy + frags.height(f);
				fr.placed(space.pageTop + top + bottom);
				reach = Math.max(reach, bottom + it.after - (it.y + frags.height(it.frag)));
				if (fr.stopped) return {height: Math.max(end, bottom), broken: true};
			}
			end = reach;
		}
		return {height: end + Math.max(0, h - rows[rows.length - 1].bottom), broken: false};
	}

	// (a row's items each laid out in the fragmentainer with its own breaks, adopted at their places, the first
	// here at the top when resumed: one that ended in one before none; one that can't break and doesn't fit, below
	// the start, pushed whole to the next (a token from its start). The tokens of those that go on; whether any made
	// progress (ended here, or took more of its content than before); where the row's items end)
	function parallel(box:Box, frag:Int, r:Row, space:Space, flow:BlockFlow, left:Float, top:Float, pos:Float, h:Float, inside:Bool):{tokens:ObjectMap<Box, BreakToken>,
			progress:Bool, reach:Float} {
		var fr = space.fragmentation, frags = space.fragments;
		var tokens = new ObjectMap<Box, BreakToken>(), progress = false, reach = pos;
		var was = fr.resume(box);
		for (it in r.items) {
			// (the tokens the box resumed with are the resumed row's; a later row's items start afresh)
			var sub = inside ? fr.parallel(box, it.box) : new Breaks(fr.size, null);
			if (sub == null) continue;
			var before = inside && was.parallel != null ? was.parallel.get(it.box) : null;
			var dy = inside ? 0 : it.y - r.top, at = space.pageTop + top + pos + dy;
			function lay():Int {
				var cs = space.child(frags.width(it.frag), h);
				cs.fixedWidth = frags.width(it.frag);
				cs.fixedHeight = frags.height(it.frag);
				cs.fragmentation = sub;
				cs.pageTop = at;
				cs.reserve = space.reserve;
				it.box.cacheFragment = -1;
				return flow.child(it.box, cs);
			}
			var f = lay();
			if (sub.decide()) f = lay();
			var t = sub.token();
			var had = before == null || before.resumes.get(it.box) == null ? 0.0 : before.resumes.get(it.box).consumed;
			var took = t == null ? Math.POSITIVE_INFINITY : t.resumes.get(it.box) == null ? 0.0 : t.resumes.get(it.box).consumed;
			// (no part of it fits and it's not at the fragmentainer's start: the next one's whole)
			if ((t == null && at + frags.height(f) > fr.size + 0.01 || t != null && took <= had + 0.01) && at > space.pageTop + top + 0.01 && before == null) {
				tokens.set(it.box, new BreakToken(new ObjectMap(), null, null));
				continue;
			}
			if (t != null) tokens.set(it.box, t);
			if (took > had + 0.01) progress = true;
			for (d in sub.deferred) fr.defer(d);
			frags.adopt(frag, f, left + it.x, top + pos + dy);
			reach = Math.max(reach, pos + dy + frags.height(f));
		}
		return {tokens: tokens, progress: progress, reach: reach};
	}

	static function pick(items:Array<RowItem>, p:String, last:Bool):Box {
		var avoid:Null<Box> = null;
		for (it in items) switch it.box.style.keyword(p) {
			case "page" | "always" | "left" | "right" | "recto" | "verso": return it.box;
			case "avoid" | "avoid-page" if (avoid == null): avoid = it.box;
			case _:
		}
		return avoid ?? items[last ? items.length - 1 : 0].box;
	}
}

private typedef Row = {
	key:Int,
	items:Array<RowItem>,
	top:Float,
	bottom:Float
}

private typedef RowItem = {
	box:Box,
	frag:Int,
	x:Float,
	y:Float,
	// (its margin box's bottom in the content box)
	after:Float
}
