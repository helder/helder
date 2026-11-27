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
	final area:Null<Array<Float>>;
	public final window:Null<Array<Float>>;

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

	// (steps: about how many there will be, its columns made that long at once: the last order's count, say;
	// window: a long document's top and bottom in the root's space, what paints outside them left out, the
	// order a window's, for paints and hit tests inside it)
	public function new(fragments:Fragments, root:Int, ?area:Array<Float>, steps = 0, ?window:Array<Float>) {
		f = fragments;
		this.area = area;
		this.window = window;
		if (steps > 0) {
			this.steps.resize(steps);
			this.fragments.resize(steps);
			xs.resize(steps);
			ys.resize(steps);
			stateOf.resize(steps);
		}
		if (root < 0) return;
		canvas = canvasBox(f.box(root));
		context(root, f.x(root), f.y(root));
	}

	static function canvasBox(root:Box):Null<Box> {
		// (containment on the root or body: body's background not propagated, Contain 2 §3)
		if (hasBackground(root) || (root.style.containment : Int) != 0) return root;
		var c = root.first;
		while (c != null) {
			if (c.node != null && c.node.nodeName.toLowerCase() == "body" && c.pseudo == null) return (c.style.containment : Int) != 0 ? root : c;
			c = c.next;
		}
		return root;
	}

	public static function hasBackground(b:Box):Bool
		return b.style.color("background-color") >>> 24 != 0 || switch b.style.terms("background-image") {
			case [Keyword("none")] | []: false;
			case _: true;
		}

	function step(kind:Int, frag:Int, x:Float, y:Float) {
		steps[count] = kind;
		fragments[count] = frag;
		xs[count] = x;
		ys[count] = y;
		stateOf[count] = state;
		count++;
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
		var b = f.box(id), s = b.style;
		if (!atomic) {
			var m = Transforms.matrix(s, x, y, f.width(id), f.height(id));
			if (m != null || s.opacity < 1) push(LAYER, s.opacity, m, null, id);
		}
		if (area != null && b.flags & Box.SLICED != 0) push(CLIP, 1, null, area, id);
		if (b.absolute) {
			var rect = s.positionedClip(x, y, f.width(id), f.height(id));
			if (rect != null) push(CLIP, 1, null, rect, -1);
		}
		// (a context's lists, used again by the next: an app's every box positioned is a context)
		var c = spare.length > 0 ? spare.pop().reset() : new Collected();
		if (f.kind(id) == Fragments.SPAN) {
			step(BACKGROUND, id, x, y);
			c.outline(id, x, y, state);
			line(id, x, y, c, state);
		} else {
			step(BACKGROUND, id, x, y);
			c.outline(id, x, y, state);
			var inner = clip(id, b, x, y);
			if (b.kind == BlockReplaced || b.kind == InlineReplaced) step(REPLACED, id, x, y);
			walk(id, x, y, c, inner);
		}
		// (by z-index, then in tree order: an absolutely positioned box's fragment comes after its containing
		// block's in-flow children, a box before it in the tree painted under it otherwise)
		var order = [for (k in 0...c.deferred.length) k];
		if (order.length > 1) {
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
		context(c.deferred[k], c.deferredX[k], c.deferredY[k]);
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
	function walk(id:Int, x:Float, y:Float, c:Collected, st:Int) {
		var k = f.first(id);
		while (k >= 0) {
			var kx = x + f.x(k), ky = y + f.y(k);
			// (in a window: what paints wholly above or below it left out)
			if (window != null && (ky + f.inkBottom(k) < window[0] || ky + f.inkTop(k) > window[1])) {
				k = f.next(k);
				continue;
			}
			switch f.kind(k) {
				case Fragments.BOX:
					var b = f.box(k);
					if (apart(b)) c.defer(k, kx, ky, b.style.zIndex() ?? 0, st) else if (b.floating) {
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
						walk(k, kx, ky, c, inner);
						if (b.table != null && b.table.collapse) c.block(BORDERS, k, kx, ky, bs);
					}
				case Fragments.LINE:
					line(k, kx, ky, c, st);
				case _:
			}
			k = f.next(k);
		}
	}

	// (a line's contents in order: spans, text, atomic inlines)
	function line(id:Int, x:Float, y:Float, c:Collected, st:Int) {
		var k = f.first(id);
		while (k >= 0) {
			var kx = x + f.x(k), ky = y + f.y(k);
			var b = f.box(k);
			switch f.kind(k) {
				case Fragments.SPAN:
					if (apart(b)) c.defer(k, kx, ky, b.style.zIndex() ?? 0, st) else {
						c.atom(BACKGROUND, k, kx, ky, st);
						c.outline(k, kx, ky, st);
						line(k, kx, ky, c, st);
					}
				case Fragments.TEXT:
					c.atom(TEXT, k, kx, ky, st);
				case Fragments.BOX:
					if (apart(b)) c.defer(k, kx, ky, b.style.zIndex() ?? 0, st) else c.atom(-1, k, kx, ky, st);
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
	public final z:Array<Int> = [];
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

	public function defer(k:Int, x:Float, y:Float, z:Int, st:Int) {
		deferred.push(k);
		deferredX.push(x);
		deferredY.push(y);
		deferredState.push(st);
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
