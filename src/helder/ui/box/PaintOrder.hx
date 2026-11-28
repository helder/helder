package helder.ui.box;

import helder.canvas.Matrix;

// The order fragments paint in, CSS 2.1 Appendix E: per stacking context
// its own background, its negative z-index children, its in-flow blocks'
// backgrounds and borders, its inline content (inline boxes' backgrounds,
// text, atomic inlines painted whole, replaced content), positioned
// descendants and z-index 0 children in tree order, positive z-index
// children, then outlines. Each step has a state: the transforms,
// opacities and overflow clips around it. Paint runs it forwards, hit
// testing backwards.
class PaintOrder {
	public static inline var BACKGROUND = 0;
	public static inline var TEXT = 1;
	public static inline var REPLACED = 2;
	public static inline var OUTLINE = 3;
	// a table's collapsed borders, over its cells' backgrounds
	public static inline var BORDERS = 4;

	// state kinds
	public static inline var ROOT = 0;
	public static inline var LAYER = 1;
	public static inline var CLIP = 2;

	public var count(default, null) = 0;
	public final steps:Array<Int> = [];
	public final fragments:Array<Int> = [];
	public final xs:Array<Float> = [];
	public final ys:Array<Float> = [];
	public final stateOf:Array<Int> = [];

	// (states: a tree; a layer's opacity and transform, a clip's rectangle, in the parent's space)
	public final parents:Array<Int> = [0];
	public final kinds:Array<Int> = [ROOT];
	public final alphas:Array<Float> = [1];
	public final matrices:Array<Null<Matrix>> = [null];
	public final rects:Array<Array<Float>> = [null];
	public final layerFragment:Array<Int> = [-1];
	// (whether a state is under a transform: steps outside the view are not culled there)
	public final transformed:Array<Bool> = [false];
	// (a clip's box scrolls (overflow scroll or auto: what it holds moved by
	// its scroll, BoxPainter.scrolls); a state inside one)
	public final scroller:Array<Bool> = [false];
	public final scrolled:Array<Bool> = [false];
	// (inside scrollers: the outermost one's clip, x0, y0, x1, y1, which no
	// scroll moves and what they hold is never seen past; null outside one)
	final scrollClip:Array<Null<Array<Float>>> = [null];

	// the box whose background is the canvas's (the root's, else body's, CSS 2.1 §14.2)
	public var canvas(default, null):Null<Box> = null;

	final f:Fragments;
	var state = 0;
	// (a page's area: what a monolithic box sliced across pages is clipped to)
	var area:Null<Array<Float>>;
	public var window(default, null):Null<Array<Float>>;

	// The steps in runs of CHUNK, each run's bounds (x0, y0, x1, y1, four a
	// run) in the root's space: what its fragments' border boxes and their
	// reach (BoxPainter.reach: shadows, outlines) cover; a run with a step
	// under a transform covers everything, one in a scroller its outermost
	// scroller's clip (where what scrolls in it can be seen). What paint
	// culls and hit testing passes over a run at a time, made on first use.
	public static inline var CHUNK = 64;

	public function chunks():Array<Float> {
		if (runs != null) return runs;
		var out = [];
		var k = 0;
		while (k < count) {
			var x0 = Math.POSITIVE_INFINITY, y0 = Math.POSITIVE_INFINITY, x1 = Math.NEGATIVE_INFINITY, y1 = Math.NEGATIVE_INFINITY;
			var end = k + CHUNK < count ? k + CHUNK : count;
			while (k < end) {
				var id = fragments[k];
				var clip = scrollClip[stateOf[k]];
				if (transformed[stateOf[k]]) {
					x0 = y0 = Math.NEGATIVE_INFINITY;
					x1 = y1 = Math.POSITIVE_INFINITY;
				} else if (clip != null) {
					if (clip[0] < x0) x0 = clip[0];
					if (clip[1] < y0) y0 = clip[1];
					if (clip[2] > x1) x1 = clip[2];
					if (clip[3] > y1) y1 = clip[3];
				} else {
					var s = f.box(id).style, r = s.reach;
					if (r != r) r = s.reach = BoxPainter.reach(s);
					var x = xs[k], y = ys[k];
					if (x - r < x0) x0 = x - r;
					if (y - r < y0) y0 = y - r;
					if (x + f.width(id) + r > x1) x1 = x + f.width(id) + r;
					if (y + f.height(id) + r > y1) y1 = y + f.height(id) + r;
				}
				k++;
			}
			out.push(x0);
			out.push(y0);
			out.push(x1);
			out.push(y1);
		}
		return runs = out;
	}

	var runs:Null<Array<Float>> = null;

	final spare:Array<Collected> = [];
	var scrolls:Null<haxe.ds.ObjectMap<{}, Array<Float>>> = null;

	// A scroller's page: its offset over its height, whole (0: not a scroller, or none given).
	public static function pageOf(f:Fragments, id:Int, offset:Float):Int {
		var h = f.height(id);
		return h <= 0 ? 0 : Math.floor(offset / h);
	}

	// (steps: about how many there will be, its columns made that long at once: the last order's count, say;
	// window: a long document's top and bottom in the root's space, what paints outside them left out, the
	// order a window's, for paints and hit tests inside it)
	// scrolls: its scrollers' offsets by Box.scrollKey, given: their content ordered only in a band of pages around
	// what they show (a page their height: the band one above the page shown, it and one below), made afresh by the
	// caller when a scroller's page changes)
	public function new(fragments:Fragments, root:Int, ?area:Array<Float>, steps = 0, ?window:Array<Float>, ?last:PaintOrder,
			?scrolls:haxe.ds.ObjectMap<{}, Array<Float>>) {
		f = fragments;
		this.scrolls = scrolls;
		if (steps > 0) {
			this.steps.resize(steps);
			this.fragments.resize(steps);
			xs.resize(steps);
			ys.resize(steps);
			stateOf.resize(steps);
		}
		make(root, area, window, last);
	}

	// This order made again for another layout (its arrays' room kept: a
	// frame's order allocates nothing once they are as long as it), the last
	// one's contexts copied where they are the same (last: not this one).
	public function again(root:Int, ?window:Array<Float>, ?last:PaintOrder, ?scrolls:haxe.ds.ObjectMap<{}, Array<Float>>):PaintOrder {
		this.scrolls = scrolls;
		count = 0;
		parents.resize(1);
		kinds.resize(1);
		layerFragment.resize(1);
		alphas.resize(1);
		matrices.resize(1);
		rects.resize(1);
		transformed.resize(1);
		scroller.resize(1);
		scrolled.resize(1);
		scrollClip.resize(1);
		ctxFrag.resize(0);
		ctxFrom.resize(0);
		ctxX.resize(0);
		ctxY.resize(0);
		ctxAtomic.resize(0);
		ctxStep0.resize(0);
		ctxStep1.resize(0);
		ctxState0.resize(0);
		ctxState1.resize(0);
		ctxEntry.resize(0);
		ctxEnd.resize(0);
		runs = null;
		reused = 0;
		ctxBounds.resize(0);
		current = -1;
		state = 0;
		canvas = null;
		make(root, null, window, last);
		return this;
	}

	function make(root:Int, area:Null<Array<Float>>, window:Null<Array<Float>>, last:Null<PaintOrder>) {
		this.area = area;
		this.window = window;
		epoch = f.epoch;
		stamp = ++stamps;
		basis = -1;
		this.last = last != null && last != this && last.f == f && last.epoch == epoch && area == null && window == null && last.area == null
			&& last.window == null ? last : null;
		if (this.last != null) basis = this.last.stamp;
		if (root >= 0) {
			canvas = canvasBox(f.box(root));
			context(root, f.x(root), f.y(root));
		}
		this.last = null;
	}

	// (each stacking context's steps and states, a run of each, by its fragment: what the next order, the layout
	// after this one, copies where the fragment is the same one, at the same place, in a state like it)
	var epoch = 0;
	var last:Null<PaintOrder> = null;
	// how many contexts were copied from the last order
	public var reused(default, null) = 0;
	// (each context's record by its fragment: where ctxStamp is this order's stamp)
	final ctxOf:Array<Int> = [];
	final ctxStamp:Array<Int> = [];
	var stamp = 0;
	static var stamps = 0;

	// (this order's number; the number of the order its contexts were copied from, -1: none)
	public var id(get, never):Int;
	public var basis(default, null) = -1;

	inline function get_id():Int
		return stamp;

	// (the contexts' records, in the order they were made (a context's own after it, ctxEnd): their first step
	// and the one after their last, whether they hold no state of their own (flat: their steps all in the one
	// they start in), the record of the order before they were copied from (-1: made here))
	@:allow(helder.ui.box) var contexts(get, never):Int;
	@:allow(helder.ui.box) final ctxFrom:Array<Int> = [];

	inline function get_contexts():Int
		return ctxFrag.length;

	@:allow(helder.ui.box) inline function contextStart(r:Int):Int
		return ctxStep0[r];

	@:allow(helder.ui.box) inline function contextEnd(r:Int):Int
		return ctxStep1[r];

	@:allow(helder.ui.box) inline function contextFlat(r:Int):Bool
		return ctxState1[r] == ctxState0[r];

	inline function contextOf(id:Int):Int
		return id < ctxStamp.length && ctxStamp[id] == stamp ? ctxOf[id] : -1;

	function setContext(id:Int, r:Int) {
		if (id >= ctxStamp.length) {
			ctxStamp.resize(id + 1 + (id >> 2));
			ctxOf.resize(ctxStamp.length);
		}
		ctxStamp[id] = stamp;
		ctxOf[id] = r;
	}
	final ctxFrag:Array<Int> = [];
	final ctxX:Array<Float> = [];
	final ctxY:Array<Float> = [];
	final ctxAtomic:Array<Bool> = [];
	final ctxStep0:Array<Int> = [];
	final ctxStep1:Array<Int> = [];
	final ctxState0:Array<Int> = [];
	final ctxState1:Array<Int> = [];
	final ctxEntry:Array<Int> = [];
	// (the records after it that are its own contexts' up to this one)
	final ctxEnd:Array<Int> = [];

	function record(id:Int, x:Float, y:Float, atomic:Bool, entry:Int):Int {
		var r = ctxFrag.length;
		setContext(id, r);
		ctxFrag.push(id);
		ctxFrom.push(-1);
		ctxX.push(x);
		ctxY.push(y);
		ctxAtomic.push(atomic);
		ctxStep0.push(count);
		ctxStep1.push(count);
		ctxState0.push(parents.length);
		ctxState1.push(parents.length);
		ctxEntry.push(entry);
		ctxEnd.push(r + 1);
		ctxBounds.push(Math.POSITIVE_INFINITY);
		ctxBounds.push(Math.POSITIVE_INFINITY);
		ctxBounds.push(Math.NEGATIVE_INFINITY);
		ctxBounds.push(Math.NEGATIVE_INFINITY);
		return r;
	}

	// (the last order's steps of the context at id copied, where it can be: its fragment the same, at x, y, the
	// state it is in clipped, scrolled and transformed as that one was)
	function reuse(id:Int, x:Float, y:Float, atomic:Bool):Bool {
		var l = last;
		if (l == null) return false;
		var r = l.contextOf(id);
		if (r < 0 || l.ctxX[r] != x || l.ctxY[r] != y || l.ctxAtomic[r] != atomic) return false;
		var e = l.ctxEntry[r];
		if (l.transformed[e] != transformed[state] || l.scrolled[e] != scrolled[state] || !sameClip(l.scrollClip[e], scrollClip[state])) return false;
		var p0 = l.ctxState0[r], p1 = l.ctxState1[r], s0 = l.ctxStep0[r], s1 = l.ctxStep1[r];
		var base = parents.length, entry = state;
		inline function map(st:Int):Int
			return st == e ? entry : base + st - p0;
		for (st in p0...p1) {
			parents.push(map(l.parents[st]));
			kinds.push(l.kinds[st]);
			alphas.push(l.alphas[st]);
			matrices.push(l.matrices[st]);
			rects.push(l.rects[st]);
			layerFragment.push(l.layerFragment[st]);
			transformed.push(l.transformed[st]);
			scroller.push(l.scroller[st]);
			scrolled.push(l.scrolled[st]);
			scrollClip.push(l.scrollClip[st]);
		}
		var shift = count - s0;
		if (count + s1 - s0 > steps.length) {
			var n = count + s1 - s0;
			steps.resize(n);
			fragments.resize(n);
			xs.resize(n);
			ys.resize(n);
			stateOf.resize(n);
		}
		for (k in s0...s1) {
			steps[count] = l.steps[k];
			fragments[count] = l.fragments[k];
			xs[count] = l.xs[k];
			ys[count] = l.ys[k];
			stateOf[count] = map(l.stateOf[k]);
			count++;
		}
		reused++;
		// (its own contexts' records with it: the order after this one copies them where this one is made again)
		var first = ctxFrag.length;
		for (q in r...l.ctxEnd[r]) {
			setContext(l.ctxFrag[q], ctxFrag.length);
			ctxFrag.push(l.ctxFrag[q]);
			ctxFrom.push(q);
			ctxX.push(l.ctxX[q]);
			ctxY.push(l.ctxY[q]);
			ctxAtomic.push(l.ctxAtomic[q]);
			ctxStep0.push(l.ctxStep0[q] + shift);
			ctxStep1.push(l.ctxStep1[q] + shift);
			ctxState0.push(l.ctxState0[q] - p0 + base);
			ctxState1.push(l.ctxState1[q] - p0 + base);
			ctxEntry.push(map(l.ctxEntry[q]));
			ctxEnd.push(l.ctxEnd[q] - r + first);
			for (v in 0...4) ctxBounds.push(l.ctxBounds[4 * q + v]);
		}
		into(first, current);
		return true;
	}

	static function sameClip(a:Null<Array<Float>>, b:Null<Array<Float>>):Bool
		return a == b || a != null && b != null && a[0] == b[0] && a[1] == b[1] && a[2] == b[2] && a[3] == b[3];

	static function canvasBox(root:Box):Null<Box> {
		// (containment on the root or body: body's background not propagated, Contain 2 §3)
		if (hasBackground(root) || (root.style.containment : Int) != 0) return root;
		var c = root.first;
		while (c != null) {
			var body = c.flags & Box.BODY != 0 ? c : root.kind == TableWrapper && c.source == root.source ? tableBody(c) : null;
			if (body != null) return (body.style.containment : Int) != 0 ? root : body;
			c = c.next;
		}
		return root;
	}

	// (a root table can wrap its body in anonymous rows and cells)
	static function tableBody(table:Box):Null<Box> {
		var c = table.first;
		while (c != null) {
			if (c.flags & Box.BODY != 0) return c;
			if (c.source == null) {
				var body = tableBody(c);
				if (body != null) return body;
			}
			c = c.next;
		}
		return null;
	}

	public static function hasBackground(b:Box):Bool
		return b.style.backgroundColor >>> 24 != 0 || b.style.background != null;

	function step(kind:Int, frag:Int, x:Float, y:Float) {
		steps[count] = kind;
		fragments[count] = frag;
		xs[count] = x;
		ys[count] = y;
		stateOf[count] = state;
		count++;
		// (its context's bounds: its border box and what its style paints past it)
		if (current >= 0) {
			var s = f.box(frag).style, r = s.reach;
			if (r != r) r = s.reach = BoxPainter.reach(s);
			widen(current, x - r, y - r, x + f.width(frag) + r, y + f.height(frag) + r);
		}
	}

	// (the context being made: its record, whose bounds its steps widen; -1: none)
	var current = -1;

	// (each context's record's bounds: its steps' and its own contexts', in the space of the state it starts in
	// before its scrolls, 4 a record)
	final ctxBounds:Array<Float> = [];

	inline function widen(r:Int, x0:Float, y0:Float, x1:Float, y1:Float) {
		var k = 4 * r;
		if (x0 < ctxBounds[k]) ctxBounds[k] = x0;
		if (y0 < ctxBounds[k + 1]) ctxBounds[k + 1] = y0;
		if (x1 > ctxBounds[k + 2]) ctxBounds[k + 2] = x1;
		if (y1 > ctxBounds[k + 3]) ctxBounds[k + 3] = y1;
	}

	// (a context's bounds into its parent's, as it ends)
	inline function into(r:Int, parent:Int)
		if (parent >= 0) widen(parent, ctxBounds[4 * r], ctxBounds[4 * r + 1], ctxBounds[4 * r + 2], ctxBounds[4 * r + 3]);

	// (whether a flat context's steps all miss x0...x1, y0...y1, its bounds moved back by dx, dy: its state's
	// scrolls)
	@:allow(helder.ui.box) inline function contextMisses(r:Int, dx:Float, dy:Float, x0:Float, y0:Float, x1:Float, y1:Float):Bool {
		var k = 4 * r;
		return ctxBounds[k] - dx > x1 || ctxBounds[k + 1] - dy > y1 || ctxBounds[k + 2] - dx < x0 || ctxBounds[k + 3] - dy < y0;
	}

	function push(kind:Int, alpha:Float, m:Null<Matrix>, rect:Null<Array<Float>>, frag:Int):Int {
		parents.push(state);
		kinds.push(kind);
		alphas.push(alpha);
		matrices.push(m);
		rects.push(rect);
		layerFragment.push(frag);
		transformed.push(transformed[state] || m != null);
		// (the root's and body's overflow are the viewport's, not a scroller's)
		var sc = kind == CLIP && frag >= 0 && rect != area && f.box(frag).parent != null && f.box(frag).parent.parent != null && f.box(frag).style.scrolls;
		scroller.push(sc);
		scrolled.push(scrolled[state] || sc);
		scrollClip.push(scrollClip[state] ?? (sc ? [rect[0], rect[1], rect[0] + rect[2], rect[1] + rect[3]] : null));
		return state = parents.length - 1;
	}

	// ---- a stacking context

	function context(id:Int, x:Float, y:Float, atomic = false) {
		var saved = state;
		if (reuse(id, x, y, atomic)) return;
		var rec = record(id, x, y, atomic, state), outer = current;
		current = rec;
		paintContext(id, x, y, collectContext(id, x, y, atomic));
		state = saved;
		ctxStep1[rec] = count;
		ctxState1[rec] = parents.length;
		ctxEnd[rec] = ctxFrag.length;
		current = outer;
		into(rec, outer);
	}

	function collectContext(id:Int, x:Float, y:Float, atomic:Bool, ?ancestor:Collected):Collected {
		var saved = state;
		var b = f.box(id), s = b.style;
		if (!atomic) {
			var m = s.transformed ? Transforms.matrix(s, x, y, f.width(id), f.height(id)) : null;
			if (m != null || s.opacity < 1) push(LAYER, s.opacity, m, null, id);
		}
		if (area != null && b.flags & Box.SLICED != 0) push(CLIP, 1, null, area, id);
		if (b.absolute) {
			var rect = s.positionedClip(x, y, f.width(id), f.height(id));
			if (rect != null) push(CLIP, 1, null, rect, -1);
		}
		var c = spare.length > 0 ? spare.pop().reset() : new Collected();
		c.rootState = state;
		c.outline(id, x, y, state);
		var scope = ancestor ?? c;
		if (f.kind(id) == Fragments.SPAN)
			line(id, x, y, c, state, scope);
		else
			walk(id, x, y, c, clip(id, b, x, y), scope);
		state = saved;
		return c;
	}

	function paintContext(id:Int, x:Float, y:Float, c:Collected) {
		var saved = state, b = f.box(id);
		state = c.rootState;
		step(BACKGROUND, id, x, y);
		if (b.kind == BlockReplaced || b.kind == InlineReplaced) step(REPLACED, id, x, y);
		// (by z-index, then in tree order: an absolutely positioned box's fragment comes after its containing
		// block's in-flow children, a box before it in the tree painted under it otherwise)
		// (its own list, kept with the context's: no array a context, most defer nothing)
		var order = c.order;
		order.resize(0);
		for (k in 0...c.deferred.length) order.push(k);
		// (in tree order already and one z-index, a list's rows: as they are)
		var sorted = true;
		if (order.length > 1) {
			var z0 = c.z[0], before = -1;
			for (k in 0...c.deferred.length) {
				var r = rank(f.box(c.deferred[k]));
				if (c.z[k] != z0 || r < before) {
					sorted = false;
					break;
				}
				before = r;
			}
		}
		if (!sorted) {
			var at = [for (k in 0...c.deferred.length) rank(f.box(c.deferred[k]))];
			order.sort((a, b) -> {
				var za = c.z[a], zb = c.z[b];
				if (za != zb) return za < zb ? -1 : 1;
				return at[a] != at[b] ? at[a] - at[b] : a - b;
			});
		}
		for (k in order) if (c.z[k] < 0) deferred(c, k);
		for (k in 0...c.blocks.length) {
			state = c.blockState[k];
			step(c.blockSteps[k], c.blocks[k], c.blockX[k], c.blockY[k]);
		}
		for (k in 0...c.floats.length) {
			state = c.floatState[k];
			context(c.floats[k], c.floatX[k], c.floatY[k], true);
		}
		for (k in 0...c.inlines.length) {
			state = c.inlineState[k];
			var fr = c.inlines[k];
			switch c.inlineStep[k] {
				case -1: context(fr, c.inlineX[k], c.inlineY[k], true);
				case kind: step(kind, fr, c.inlineX[k], c.inlineY[k]);
			}
		}
		for (k in order) if (c.z[k] >= 0) deferred(c, k);
		for (k in 0...c.outlines.length) {
			state = c.outlineState[k];
			step(OUTLINE, c.outlines[k], c.outlineX[k], c.outlineY[k]);
		}
		state = saved;
		spare.push(c);

	}

	// (a box's place in its tree, depth first: every box numbered once, on
	// first ask, kept on the boxes for the paint orders after this one)
	static function rank(b:Box):Int {
		if (b.rank < 0) {
			var top = b;
			while (top.parent != null) top = top.parent;
			var n = 0, x:Null<Box> = top;
			while (x != null) {
				x.rank = n++;
				if (x.first != null) x = x.first else {
					while (x != top && x.next == null) x = x.parent;
					x = x == top ? null : x.next;
				}
			}
		}
		return b.rank;
	}

	function deferred(c:Collected, k:Int) {
		state = c.deferredState[k];
		var id = c.deferred[k], x = c.deferredX[k], y = c.deferredY[k];
		var prepared = c.deferredGroups[k];
		if (prepared == null) context(id, x, y) else paintContext(id, x, y, prepared);
	}

	function queueContext(scope:Collected, id:Int, x:Float, y:Float, st:Int) {
		var s = f.box(id).style, prepared:Null<Collected> = null;
		// Relative and absolute boxes at z-index: auto paint as a group, but their positioned descendants
		// participate in the enclosing stacking context (CSS 2 Appendix E).
		if (!s.stacking() && !s.transformed && s.position != "sticky" && (last == null || last.contextOf(id) < 0)
			&& containsDeferred(id)) {
			var saved = state;
			state = st;
			prepared = collectContext(id, x, y, false, scope);
			state = saved;
		}
		scope.defer(id, x, y, s.zIndex() ?? 0, st, prepared);
	}

	// (a group whose children all paint within it can use the regular context's reuse)
	// (each fragment's answer, kept while its fragments are: a fragment and what is in it never change, an
	// app's boxes all relative, each asked of all under it; the orders made again from this one keep them)
	// (made afresh, no order before it: what was restyled may answer otherwise, a z-index changed)
	var deferMemo:Array<Int> = [];
	var deferFor:Null<Fragments> = null;
	var deferStamp = -1;

	function containsDeferred(id:Int):Bool {
		if (deferStamp != stamp) {
			deferStamp = stamp;
			deferMemo = last != null && last.deferFor == f ? last.deferMemo : [];
			deferFor = f;
		}
		var memo = deferMemo, mark = f.epoch + 1;
		if (id < memo.length && memo[id] >> 1 == mark) return memo[id] & 1 != 0;
		var v = scanDeferred(id);
		if (id >= memo.length) memo.resize(id + 1 + (id >> 2));
		memo[id] = mark << 1 | (v ? 1 : 0);
		return v;
	}

	// (a descendant painted elsewhere than in tree order after it: positioned or a stacking context at a z-index
	// other than 0, not inside a stacking context of its own between; at z-index auto or 0 they come right after
	// it in tree order either way, an app's all-relative tree its contexts as they were)
	function scanDeferred(id:Int):Bool {
		var inlineParent = f.kind(id) == Fragments.LINE || f.kind(id) == Fragments.SPAN;
		var k = f.first(id);
		while (k >= 0) {
			switch f.kind(k) {
				case Fragments.BOX:
					var b = f.box(k);
					if (apart(b)) {
						var z = b.style.zIndex();
						if (z != null && z != 0) return true;
						if (!b.style.stacking() && containsDeferred(k)) return true;
					} else if (!inlineParent && !b.floating && containsDeferred(k)) return true;
				case Fragments.SPAN:
					var b = f.box(k);
					if (apart(b)) {
						var z = b.style.zIndex();
						if (z != null && z != 0) return true;
						if (!b.style.stacking() && containsDeferred(k)) return true;
					} else if (containsDeferred(k)) return true;
				case Fragments.LINE:
					if (containsDeferred(k)) return true;
				case _:
			}
			k = f.next(k);
		}
		return false;
	}

	// (an overflow clip around a box's contents: its padding box)
	function clip(id:Int, b:Box, x:Float, y:Float):Int {
		if (!b.style.clips || b.kind == Inline) return state;
		var s = b.style.model();
		var r = [x + s.border[3], y + s.border[0], f.width(id) - s.border[1] - s.border[3], f.height(id) - s.border[0] - s.border[2]];
		var saved = state;
		var st = push(CLIP, 1, null, r, id);
		state = saved;
		return st;
	}

	// (a context's descendants in flow: blocks, lines, and what paints apart)
	function walk(id:Int, x:Float, y:Float, c:Collected, st:Int, scope:Collected) {
		var k = f.first(id);
		// (a scroller's content: its band of pages alone, a long list's rows out of it left out)
		var lo = Math.NEGATIVE_INFINITY, hi = Math.POSITIVE_INFINITY;
		if (scrolls != null && f.kind(id) == Fragments.BOX && f.box(id).style.scrolls) {
			var o = scrolls.get(Box.scrollKey(f.box(id))), h = f.height(id);
			if (h > 0) {
				var top = y + pageOf(f, id, o == null ? 0 : o[1]) * h;
				lo = top - h;
				hi = top + 2 * h;
			}
		}
		while (k >= 0) {
			var kx = x + f.x(k), ky = y + f.y(k);
			// (in a window: what paints wholly above or below it left out)
			if (window != null && (ky + f.inkBottom(k) < window[0] || ky + f.inkTop(k) > window[1]) || ky + f.inkBottom(k) < lo || ky + f.inkTop(k) > hi) {
				k = f.next(k);
				continue;
			}
			switch f.kind(k) {
				case Fragments.BOX:
					var b = f.box(k);
					if (apart(b)) queueContext(scope, k, kx, ky, st) else if (b.floating) {
						// (a float: after the blocks' backgrounds, before the inline content, painted whole, step 5)
						c.floats.push(k);
						c.floatX.push(kx);
						c.floatY.push(ky);
						c.floatState.push(st);
					} else {
						var saved = state;
						state = st;
						// (sliced across pages: it and its contents clipped to the page's area)
						var bs = area != null && b.flags & Box.SLICED != 0 ? push(CLIP, 1, null, area, k) : st;
						c.block(BACKGROUND, k, kx, ky, bs);
						c.outline(k, kx, ky, bs);
						state = bs;
						var inner = clip(k, b, kx, ky);
						state = saved;
						if (b.kind == BlockReplaced) c.atom(REPLACED, k, kx, ky, bs);
						walk(k, kx, ky, c, inner, scope);
						if (b.table != null && b.table.collapse) c.block(BORDERS, k, kx, ky, bs);
					}
				case Fragments.LINE:
					line(k, kx, ky, c, st, scope);
				case _:
			}
			k = f.next(k);
		}
	}

	// (a line's contents in order: spans, text, atomic inlines)
	function line(id:Int, x:Float, y:Float, c:Collected, st:Int, scope:Collected) {
		var k = f.first(id);
		while (k >= 0) {
			var kx = x + f.x(k), ky = y + f.y(k);
			var b = f.box(k);
			switch f.kind(k) {
				case Fragments.SPAN:
					if (apart(b)) queueContext(scope, k, kx, ky, st) else {
						c.atom(BACKGROUND, k, kx, ky, st);
						c.outline(k, kx, ky, st);
						line(k, kx, ky, c, st, scope);
					}
				case Fragments.TEXT:
					c.atom(TEXT, k, kx, ky, st);
				case Fragments.BOX:
					if (apart(b)) queueContext(scope, k, kx, ky, st) else c.atom(-1, k, kx, ky, st);
				case _:
			}
			k = f.next(k);
		}
	}

	// (positioned, or a stacking context: painted in its context's later steps)
	static function apart(b:Box):Bool
		return b.style.positioned || b.style.stacking();
}

private class Collected {
	public var rootState = 0;
	public final blocks:Array<Int> = [];
	public final blockX:Array<Float> = [];
	public final blockY:Array<Float> = [];
	public final blockState:Array<Int> = [];
	public final blockSteps:Array<Int> = [];
	public final floats:Array<Int> = [];
	public final floatX:Array<Float> = [];
	public final floatY:Array<Float> = [];
	public final floatState:Array<Int> = [];
	public final inlines:Array<Int> = [];
	public final inlineStep:Array<Int> = [];
	public final inlineX:Array<Float> = [];
	public final inlineY:Array<Float> = [];
	public final inlineState:Array<Int> = [];
	public final deferred:Array<Int> = [];
	public final deferredX:Array<Float> = [];
	public final deferredY:Array<Float> = [];
	public final deferredState:Array<Int> = [];
	public final deferredGroups:Array<Null<Collected>> = [];
	public final z:Array<Int> = [];
	public final order:Array<Int> = [];
	public final outlines:Array<Int> = [];
	public final outlineX:Array<Float> = [];
	public final outlineY:Array<Float> = [];
	public final outlineState:Array<Int> = [];

	public function reset():Collected {
		blocks.resize(0);
		blockX.resize(0);
		blockY.resize(0);
		blockState.resize(0);
		blockSteps.resize(0);
		floats.resize(0);
		floatX.resize(0);
		floatY.resize(0);
		floatState.resize(0);
		inlines.resize(0);
		inlineStep.resize(0);
		inlineX.resize(0);
		inlineY.resize(0);
		inlineState.resize(0);
		deferred.resize(0);
		deferredX.resize(0);
		deferredY.resize(0);
		deferredState.resize(0);
		deferredGroups.resize(0);
		z.resize(0);
		outlines.resize(0);
		outlineX.resize(0);
		outlineY.resize(0);
		outlineState.resize(0);
		return this;
	}

	public function new() {}

	public function outline(k:Int, x:Float, y:Float, st:Int) {
		outlines.push(k);
		outlineX.push(x);
		outlineY.push(y);
		outlineState.push(st);
	}

	public function block(kind:Int, k:Int, x:Float, y:Float, st:Int) {
		blocks.push(k);
		blockSteps.push(kind);
		blockX.push(x);
		blockY.push(y);
		blockState.push(st);
	}

	public function defer(k:Int, x:Float, y:Float, z:Int, st:Int, group:Null<Collected>) {
		deferred.push(k);
		deferredX.push(x);
		deferredY.push(y);
		deferredState.push(st);
		deferredGroups.push(group);
		this.z.push(z);
	}

	public function atom(kind:Int, k:Int, x:Float, y:Float, st:Int) {
		inlines.push(k);
		inlineStep.push(kind);
		inlineX.push(x);
		inlineY.push(y);
		inlineState.push(st);
	}
}
