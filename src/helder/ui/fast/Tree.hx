package helder.ui.fast;

import haxe.ds.ObjectMap;
import helder.ui.box.Box;
import helder.ui.box.BoxPainter;
import helder.ui.box.FontMatch;
import helder.ui.box.Fragments;
import helder.ui.box.HitTest;
import helder.ui.box.PaintOrder;
import helder.ui.box.PaintSpans;
import helder.ui.box.UiPainter;
import helder.ui.flow.BlockFlow;
import helder.ui.flow.Space;

// A fast tree in helder.ui: its root node's boxes laid out at this node's
// size by the engine's block and flex layout, painted from its paint order
// (made again from the last one where boxes kept their fragments, and
// contexts' calls copied from the last paint), hit, hovered, pressed and
// scrolled.
//
//   final tree = new Tree(list, app);  // app: its palette, a Theme
//   UiWindow.run(<UiWindow.Surface title="List">{tree}</UiWindow.Surface>);
class Tree extends helder.ui.Node {
	public final root:Node;
	// the theme its nodes resolve tokens in where none of theirs has one
	public var palette(default, set):Theme;
	@:noCompletion public final fonts = new FontMatch();
	// (the engine's own time, ms: layouts, paints)
	@:noCompletion public var layoutMs = 0.0;
	@:noCompletion public var paintMs = 0.0;

	final fragments = new Fragments();
	final scrolls = new ObjectMap<{}, Array<Float>>();
	final painter = new UiPainter(null, 0, 0);
	final spans = new PaintSpans();
	var order:Null<PaintOrder> = null;
	var spare:Null<PaintOrder> = null;
	var rootFragment = -1;
	var laidWidth = Math.NaN;
	var laidHeight = Math.NaN;
	var docHeight = 0.0;
	var whole = 0;
	var due = true;
	var orderDue = true;
	var orderFresh = false;
	var boxIndex:Null<ObjectMap<Box, Int>> = null;
	// (the nodes under the pointer, innermost first; those pressed)
	var pointed:Array<Node> = [];
	var held:Array<Node> = [];

	public function new(root:Node, ?theme:Theme) {
		super("tree");
		this.root = root;
		this.palette = theme ?? Theme.base;
		root.tree = this;
		onWheel = wheeled;
		onPointerMove = e -> hover(hit(e.localX, e.localY));
		onPointerLeave = _ -> hover(null);
		onPointerDown = e -> {
			press(chain(hit(e.localX, e.localY)));
			capture();
		}
		onPointerUp = e -> {
			var at = chain(hit(e.localX, e.localY)), was = held;
			press([]);
			for (n in was) if (n.onPress != null) {
				if (at.contains(n)) n.onPress();
				break;
			}
		}
		onPointerCancel = _ -> press([]);
	}

	function set_palette(t:Theme):Theme {
		palette = t;
		root.resolve(Resolve.root, t, 0);
		return t;
	}

	// (a change in the tree at a box: what it takes)
	@:allow(helder.ui.fast) function changed(b:Box, level:Int) {
		if (level == Resolve.LAYOUT) {
			var p:Null<Box> = b;
			while (p != null) {
				p.uncache();
				p.inlineCache = null;
				p.cacheWidth = p.minContent = p.maxContent = Math.NaN;
				p = p.parent;
			}
			due = true;
			markDirty();
			return;
		}
		// (the lines it is in keep its old inline style: built again)
		var p:Null<Box> = b;
		while (p != null) {
			p.inlineCache = null;
			p = p.parent;
		}
		if (level == Resolve.ORDER) {
			orderDue = true;
			orderFresh = true;
		}
		spans.fresh = true;
		layerChanged();
		if (ui != null) ui.requestFrame();
	}

	function hit(x:Float, y:Float):Null<Node>
		return rootFragment < 0 ? null : Node.of(HitTest.at(fragments, ordered(), x, y, scrolls)?.box);

	// (a node and its ancestors, innermost first)
	static function chain(n:Null<Node>):Array<Node> {
		var out = [];
		while (n != null) {
			out.push(n);
			n = n.parent;
		}
		return out;
	}

	function hover(n:Null<Node>) {
		var now = chain(n);
		for (o in pointed) if (!now.contains(o)) o.state(Style.HOVER, false);
		for (o in now) o.state(Style.HOVER, true);
		pointed = now;
	}

	function press(now:Array<Node>) {
		for (o in held) if (!now.contains(o)) o.state(Style.PRESSED, false);
		for (o in now) o.state(Style.PRESSED, true);
		held = now;
	}

	@:noCompletion override public function hasContent():Bool
		return true;

	@:allow(helder.ui) override function paintsLive():Bool
		return false;

	@:noCompletion override public function measureContent(text:helder.ui.TextEngine, knownWidth:Float, knownHeight:Float, availWidth:Float,
			availHeight:Float):helder.ui.Size {
		var w = !Math.isNaN(knownWidth) ? knownWidth : Math.isFinite(availWidth) ? availWidth : 800;
		var h = !Math.isNaN(knownHeight) ? knownHeight : ui != null ? ui.height : Math.isFinite(availHeight) ? availHeight : 600;
		if (w != laidWidth || h != laidHeight || due) {
			var t0 = haxe.Timer.stamp();
			layout(w, h);
			layoutMs += (haxe.Timer.stamp() - t0) * 1000;
			laidWidth = w;
			laidHeight = h;
			due = false;
		}
		return new helder.ui.Size(w, Math.isNaN(knownHeight) ? Math.max(docHeight, h) : knownHeight);
	}

	function layout(w:Float, h:Float) {
		// (the fragments of the layouts before, kept for the cache, a few times a whole layout's: let go)
		if (fragments.count > 3 * whole + 4096) {
			fragments.clear();
			Box.forgetFragments();
		}
		var fresh = fragments.count == 0;
		var b = root.box;
		var f = (b.context ?? Node.contexts().flow).layout(b, new Space(fragments, fonts, w, h));
		var off = BlockFlow.offset(b, w, h);
		fragments.moveTo(f, b.marginLeft + off.x, b.topPositive + b.topNegative + off.y);
		if (fresh) whole = fragments.count;
		rootFragment = f;
		orderDue = true;
		boxIndex = null;
		docHeight = fragments.y(f) + fragments.height(f) + Math.max(0, b.bottomPositive + b.bottomNegative);
	}

	@:noCompletion override public function paintContent(canvas:helder.ui.Canvas, x:Float, y:Float, width:Float, height:Float) {
		if (rootFragment < 0 || ui == null) return;
		var w = @:privateAccess ui.walk;
		var x0 = Math.max(w.x0, x), y0 = Math.max(w.y0, y), x1 = Math.min(w.x1, x + width), y1 = Math.min(w.y1, y + height);
		if (x1 <= x0 || y1 <= y0) return;
		var t0 = haxe.Timer.stamp();
		var order = ordered();
		canvas.translate(x, y);
		painter.begin(canvas, Math.ceil(width), Math.ceil(height), ui.scale, x0 - x, y0 - y, x1 - x, y1 - y);
		var bp = new BoxPainter(fragments, order, _ -> null);
		bp.scrolls = scrolls;
		bp.spans = spans;
		bp.area = [x0 - x, y0 - y, x1 - x, y1 - y];
		bp.canvasArea = [x0 - x, y0 - y, x1 - x0, y1 - y0];
		bp.paint(painter);
		painter.end();
		canvas.translate(-x, -y);
		paintMs += (haxe.Timer.stamp() - t0) * 1000;
	}

	// Where a node is in the window, as last laid out and scrolled: x, y, width, height (zeros: not laid out).
	public function rectOf(n:Node):Array<Float> {
		var id = fragmentOf(n.box);
		if (id < 0) return [0, 0, 0, 0];
		var p = fragments.absolute(id), x = absX + p.x, y = absY + p.y, b = n.box.parent;
		while (b != null) {
			var o = scrolls.get(Box.scrollKey(b));
			if (o != null) {
				x -= o[0];
				y -= o[1];
			}
			b = b.parent;
		}
		return [x, y, fragments.width(id), fragments.height(id)];
	}

	// (the paint order of the last layout: made again from the one before where boxes kept their fragments)
	function ordered():PaintOrder {
		if (!orderDue && order != null) return order;
		var last = orderFresh ? null : order;
		var made = spare != null ? spare.again(rootFragment, null, last) : new PaintOrder(fragments, rootFragment, null, order != null ? order.count : 0, null,
			last);
		spare = order;
		order = made;
		orderDue = orderFresh = false;
		return made;
	}

	// (a box's fragment in the last layout; -1: none)
	function fragmentOf(b:Box):Int {
		if (boxIndex == null) {
			var m = new ObjectMap<Box, Int>(), stack = [rootFragment];
			while (stack.length > 0) {
				var id = stack.pop();
				if (fragments.kind(id) == Fragments.BOX && !m.exists(fragments.box(id))) m.set(fragments.box(id), id);
				var c = fragments.first(id);
				while (c >= 0) {
					stack.push(c);
					c = fragments.next(c);
				}
			}
			boxIndex = m;
		}
		return boxIndex.exists(b) ? boxIndex.get(b) : -1;
	}

	// (the innermost scroll container under the wheel that can move: moved, within its content's extent)
	function wheeled(e:helder.ui.Event) {
		if (rootFragment < 0) return;
		var b = HitTest.at(fragments, ordered(), e.localX, e.localY, scrolls)?.box;
		while (b != null) {
			if (b.style.scrolls && scrollBy(b, e.deltaX, e.deltaY)) {
				layerChanged();
				ui.requestFrame();
				e.preventDefault();
				e.stop();
				return;
			}
			b = b.parent;
		}
	}

	function scrollBy(b:Box, dx:Float, dy:Float):Bool {
		var id = fragmentOf(b);
		if (id < 0) return false;
		var m = b.style.model();
		var cw = fragments.width(id) - m.border[1] - m.border[3], ch = fragments.height(id) - m.border[0] - m.border[2];
		var ew = 0.0, eh = 0.0, c = fragments.first(id);
		while (c >= 0) {
			ew = Math.max(ew, fragments.x(c) + fragments.width(c));
			eh = Math.max(eh, fragments.y(c) + fragments.height(c));
			c = fragments.next(c);
		}
		eh += helder.ui.box.Len.Lens.resolve(m.padding[2], cw, 0) - m.border[0];
		ew -= m.border[3];
		var o = scrolls.get(Box.scrollKey(b)) ?? [0.0, 0.0];
		var sx = Math.max(0, Math.min(o[0] + dx, ew - cw)), sy = Math.max(0, Math.min(o[1] + dy, eh - ch));
		if (sx == o[0] && sy == o[1]) return false;
		scrolls.set(Box.scrollKey(b), [sx, sy]);
		return true;
	}
}
