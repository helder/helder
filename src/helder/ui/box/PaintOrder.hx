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

	// the box whose background is the canvas's (the root's, else body's, CSS 2.1 §14.2)
	public var canvas(default, null):Null<Box> = null;

	final f:Fragments;
	var state = 0;

	public function new(fragments:Fragments, root:Int) {
		f = fragments;
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
		var c = new Collected();
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
		var order = [for (k in 0...c.deferred.length) k];
		order.sort((a, b) -> c.z[a] != c.z[b] ? c.z[a] - c.z[b] : a - b);
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
						c.block(BACKGROUND, k, kx, ky, st);
						c.outline(k, kx, ky, st);
						var saved = state;
						state = st;
						var inner = clip(k, b, kx, ky);
						state = saved;
						if (b.kind == BlockReplaced) c.atom(REPLACED, k, kx, ky, st);
						walk(k, kx, ky, c, inner);
						if (b.table != null && b.table.collapse) c.block(BORDERS, k, kx, ky, st);
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
