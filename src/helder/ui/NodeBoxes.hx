package helder.ui;

import helder.ui.box.Box;
import helder.ui.box.BoxStyle;
import helder.ui.box.FontMatch;
import helder.ui.box.Fragments;
import helder.ui.box.Len;
import helder.ui.flow.Contexts;
import helder.ui.flow.FormattingContext;
import helder.ui.flow.Space;

// helder.ui's nodes laid out by the CSS engine: each node a box of the
// engine's tree, kept from one layout to the next, styled by its resolved
// style (Node.used); views laid out by the engine's block, flex and grid; a
// node with content of its own (a TextNode, an image, a custom drawn node)
// a box the measured context lays out by the node's own measureContent, so
// that what it paints is what it was measured as. Its results rounded to
// whole pixels and told to the nodes (round), so the rest of helder.ui (its
// paint walk, layers and compositor, events, focus, assistive technology)
// reads them as laid out.
@:allow(helder.ui)
@:access(helder.ui.Node)
class NodeBoxes {
	final fragments = new Fragments();
	final fonts = new FontMatch();
	final contexts:Contexts;
	final measured = new Measured();
	// (the root's containing block, as a document's: the root a positioned box in it, as large as the window, its
	// absolutely positioned children placed in its padding box)
	final icb:Box;
	var whole = 0;
	var width = Math.NaN;
	var height = Math.NaN;

	function new() {
		var flow = new helder.ui.flow.BlockFlow();
		contexts = new Contexts(flow);
		contexts.flex = new helder.ui.flow.FlexFlow(flow);
		contexts.grid = new helder.ui.flow.GridFlow(flow);
		var s = new BoxStyle();
		@:privateAccess {
			s.textPart = Resolve.root;
			s.displayRead = true;
			s.displayOuter = BoxStyle.BLOCK;
			s.displayInner = BoxStyle.FLOW;
			s.layoutRead = true;
			s.traits = BoxStyle.VISIBLE | BoxStyle.COLLAPSE | BoxStyle.WRAPS;
			s.opacityValue = 1;
		}
		icb = new Box(Block, s, null);
	}

	public static function run(root:Node, width:Float, height:Float, text:TextEngine, ?scrollers:Array<Node>):Bool {
		if (!root.dirty && root.lw == width && root.lh == height && !root.relaid) return false;
		var e = root.laidBy ?? (root.laidBy = new NodeBoxes());
		e.measured.text = text;
		if (e.width != width || e.height != height) {
			e.width = width;
			e.height = height;
			root.dirty = true;
		}
		// (laid out again where something in it changed: its cache let go with the root's)
		if (root.dirty) e.icb.uncache();
		var b = e.sync(root);
		if (b.parent != e.icb) {
			while (e.icb.first != null) e.icb.first.remove();
			e.icb.append(b);
		}
		var f = e.fragments;
		// (the layouts before kept for the cache, let go now and then)
		if (f.count > 3 * e.whole + 4096) {
			f.clear();
			Box.forgetFragments();
		}
		var fresh = f.count == 0;
		var space = new Space(f, e.fonts, width, height);
		space.fixedWidth = width;
		space.fixedHeight = height;
		var id = f.first(e.contexts.flow.layout(e.icb, space));
		if (fresh) e.whole = f.count;
		e.told(root, id);
		root.lx = 0;
		root.ly = 0;
		round(root, 0, 0, 0, 0, scrollers);
		return true;
	}

	// (a node's box: made, or styled again with its children's where it is dirty; its ancestors' caches let go)
	function sync(n:Node):Box {
		var b = n.laidBox;
		if (b != null && !n.dirty) return b;
		var s = n.used;
		// (the root as large as the window, whatever its style says)
		if (n.parent == null) s = rootStyle(n);
		var own = n.hasContent() && (n.children.length == 0 || n.contentOwnsChildren());
		var kind:helder.ui.box.BoxKind = own || s.inner == BoxStyle.FLEX || s.inner == BoxStyle.GRID ? Container : Block;
		if (b == null || b.kind != kind) {
			b = new Box(kind, s, n);
			b.flags |= Box.MADE;
			n.laidBox = b;
		} else @:privateAccess b.restyle(s);
		b.context = own ? measured : contexts.of(s.inner, _ -> {});
		// (its children's boxes, in order: none for a node whose content they are, nor for those not shown)
		while (b.first != null) b.first.remove();
		if (!own) for (c in n.children) if (!c.used.none) b.append(sync(c)) else hide(c);
		b.uncache();
		b.inlineCache = null;
		b.cacheWidth = b.minContent = b.maxContent = Math.NaN;
		n.dirty = false;
		// (round goes through it and what is in it: its children's places may have changed)
		n.relaid = true;
		return b;
	}

	// (the root's style: its own, as large as the window, made once for each size)
	function rootStyle(n:Node):BoxStyle {
		var look = @:privateAccess n.look ?? n.style;
		var sized = look.with({width: width, height: height, minWidth: 0, minHeight: 0, maxWidth: "auto", maxHeight: "auto"});
		return Resolve.of(sized, @:privateAccess n.states, Resolve.root, n.scope(), Resolve.VIEW);
	}

	static function hide(n:Node) {
		n.lx = n.ly = n.lw = n.lh = 0;
		n.dirty = false;
		n.relaid = true;
		for (c in n.children) hide(c);
	}

	// (the laid out fragments told to their nodes: each one's place in its parent's, its size, its content's
	// extent; a node whose fragment is the one it was told last, not laid out again, left as it is: a fragment
	// and what is in it never change)
	function told(n:Node, id:Int) {
		var f = fragments;
		if (n.lw != f.width(id) || n.lh != f.height(id)) n.relaid = true;
		n.lw = f.width(id);
		n.lh = f.height(id);
		if (id == n.laidFragment && !n.relaid) return;
		n.laidFragment = id;
		// (content measured is its own: its extent left as it is)
		var b = n.laidBox;
		if (b == null || b.context == measured) return;
		// (from its content box's start, each child's end margin, what a child not clipping overflows)
		var m = b.style.model(), padL = m.border[3] + Len.Lens.resolve(m.padding[3], n.lw, 0),
			padT = m.border[0] + Len.Lens.resolve(m.padding[0], n.lw, 0);
		var ext = [0.0, 0.0, 0.0], rtl = n.rtl();
		children(n, id, 0, 0, padL, padT, ext, rtl);
		// (right to left: from what reaches furthest left to the content box's right edge)
		if (rtl) ext[0] = n.lw - padL - m.border[1] - Len.Lens.resolve(m.padding[1], n.lw, 0) - ext[2];
		@:privateAccess n.contentWidth = ext[0];
		@:privateAccess n.contentHeight = ext[1];
	}

	// (the fragments under id, in order, through those of no node of their own (anonymous blocks, lines): each
	// node's told its place, at dx, dy from n's border box)
	function children(n:Node, id:Int, dx:Float, dy:Float, padL:Float, padT:Float, ext:Array<Float>, rtl:Bool) {
		var f = fragments, k = f.first(id);
		while (k >= 0) {
			var b = f.box(k), x = dx + f.x(k), y = dy + f.y(k);
			var c:Null<Node> = b == null || !Std.isOfType(b.source, Node) ? null : cast b.source;
			if (c != null && c.parent == n) {
				if (c.lx != x || c.ly != y) n.relaid = true;
				c.lx = x;
				c.ly = y;
				told(c, k);
				var cs = c.used, ow = c.lw, oh = c.lh;
				if (!cs.clips && !rtl) {
					ow = Math.max(ow, c.contentWidth + cs.paddingPx(3) + cs.borderPx(3));
					oh = Math.max(oh, c.contentHeight + cs.paddingPx(0) + cs.borderPx(0));
				}
				var mr = Len.Lens.resolve(cs.margin[1], n.lw, 0), mb = Len.Lens.resolve(cs.margin[2], n.lw, 0);
				ext[0] = Math.max(ext[0], x - padL + ow + mr);
				ext[1] = Math.max(ext[1], y - padT + oh + mb);
				ext[2] = Math.min(ext[2], x - padL);
			} else if (c == null) children(n, k, x, y, padL, padT, ext, rtl);
			k = f.next(k);
		}
	}

	// (a node's place and size, unrounded (lx...), rounded to whole pixels and told it, its children's from it;
	// the scrollers met listed)
	static function round(n:Node, parentAbsX:Float, parentAbsY:Float, parentRoundX:Float, parentRoundY:Float, scrollers:Null<Array<Node>>) {
		var ax = parentAbsX + n.lx, ay = parentAbsY + n.ly;
		// (where it is in its parent too: the parent moved and it not, it moved in its parent)
		if (!n.relaid && ax == n.rawX && ay == n.rawY && n.lw == n.rawW && n.lh == n.rawH && n.x == Math.fround(ax) - parentRoundX
			&& n.y == Math.fround(ay) - parentRoundY) return;
		n.relaid = false;
		n.rawX = ax;
		n.rawY = ay;
		n.rawW = n.lw;
		n.rawH = n.lh;
		var x0 = Math.fround(ax), y0 = Math.fround(ay), x1 = Math.fround(ax + n.lw), y1 = Math.fround(ay + n.lh);
		n.setLayout(x0 - parentRoundX, y0 - parentRoundY, x1 - x0, y1 - y0, x0, y0, n.contentWidth, n.contentHeight);
		if (scrollers != null && n.used.scrolls) scrollers.push(n);
		// (scrolled children: the scroll offset moves them when drawn and hit, not here)
		for (c in n.children)
			round(c, ax, ay, x0, y0, scrollers);
		n.measureInk();
	}
}

// (a node with content of its own laid out as it measures it: its width the
// space's (stretched or flexed: given; else its style's, else the
// container's), its height its content's at that width; its min-content
// and max-content widths its own)
@:access(helder.ui.Node)
private class Measured implements FormattingContext {
	public var text:Null<TextEngine> = null;

	public function new() {}

	public function layout(box:Box, space:Space):Int {
		var n:Node = cast box.source, s = box.style.model(), cb = space.width;
		var bpx = s.border[1] + s.border[3] + Len.Lens.resolve(s.padding[1], cb, 0) + Len.Lens.resolve(s.padding[3], cb, 0);
		var bpy = s.border[0] + s.border[2] + Len.Lens.resolve(s.padding[0], cb, 0) + Len.Lens.resolve(s.padding[2], cb, 0);
		var w = space.fixedWidth, h = space.fixedHeight;
		var maxW = helder.ui.flow.BlockFlow.size(s.maxWidth, cb, s.borderBox, bpx) + bpx;
		if (Math.isNaN(h) && !space.ignoreHeight) h = Len.Lens.resolve(s.height, space.height, Math.NaN);
		if (Math.isNaN(w)) {
			var sw = Len.Lens.resolve(s.width, cb, Math.NaN);
			// (its width its height's through its aspect ratio, else the room's)
			if (Math.isNaN(sw) && !Math.isNaN(h)) sw = helder.ui.flow.Ratio.width(box, h - bpy, bpx, bpy) + bpx;
			w = !Math.isNaN(sw) ? sw : cb - Len.Lens.resolve(s.margin[1], cb, 0) - Len.Lens.resolve(s.margin[3], cb, 0);
			var minW = helder.ui.flow.BlockFlow.size(s.minWidth, cb, s.borderBox, bpx) + bpx;
			if (!Math.isNaN(maxW) && w > maxW) w = maxW;
			if (!Math.isNaN(minW) && w < minW) w = minW;
		}
		// (its height its width's through its aspect ratio: its content's when taller, no more than its max-width
		// gives through it, Sizing 4 §5.1)
		var ratioH = Math.isNaN(h) && !space.ignoreHeight ? helder.ui.flow.Ratio.height(box, w - bpx, bpx, bpy) : Math.NaN;
		// (its content box measured: its padding and border around it)
		var size = n.measureContent(text, w - bpx, Math.isNaN(h) ? Math.NaN : h - bpy, w - bpx, Math.isNaN(h) ? Math.POSITIVE_INFINITY : h - bpy);
		if (!Math.isNaN(ratioH)) {
			var cap = helder.ui.flow.Ratio.height(box, maxW - bpx, bpx, bpy);
			h = Math.max(ratioH, Math.isNaN(cap) ? size.height : Math.min(size.height, cap)) + bpy;
		}
		if (Math.isNaN(h)) h = size.height + bpy;
		var lo = Len.Lens.resolve(s.minHeight, space.height, 0), hi = Len.Lens.resolve(s.maxHeight, space.height, Math.POSITIVE_INFINITY);
		if (Math.isNaN(space.fixedHeight)) h = Math.max(lo, Math.min(hi, h));
		box.marginLeft = Len.Lens.resolve(s.margin[3], cb, 0);
		box.marginRight = Len.Lens.resolve(s.margin[1], cb, 0);
		var mt = Len.Lens.resolve(s.margin[0], cb, 0), mb = Len.Lens.resolve(s.margin[2], cb, 0);
		box.topPositive = mt > 0 ? mt : 0;
		box.topNegative = mt < 0 ? mt : 0;
		box.bottomPositive = mb > 0 ? mb : 0;
		box.bottomNegative = mb < 0 ? mb : 0;
		box.through = false;
		var id = space.fragments.add(Fragments.BOX, box, Math.max(w, 0), Math.max(h, 0));
		// (a text's first line's: a row aligns its items on it)
		space.fragments.setBaseline(id, n.firstBaseline());
		return id;
	}

	public function intrinsic(box:Box, space:Space) {
		if (!Math.isNaN(box.minContent)) return;
		var n:Node = cast box.source, s = box.style.model();
		var bpx = s.border[1] + s.border[3] + Len.Lens.resolve(s.padding[1], 0, 0) + Len.Lens.resolve(s.padding[3], 0, 0);
		// (a width of its own: that, as a flex container's is, BlockFlow.intrinsic's)
		var own = helder.ui.flow.BlockFlow.size(s.width, Math.NaN, s.borderBox, bpx);
		if (!Math.isNaN(own)) {
			var lo = helder.ui.flow.BlockFlow.size(s.minWidth, Math.NaN, s.borderBox, bpx), hi = helder.ui.flow.BlockFlow.size(s.maxWidth, Math.NaN, s.borderBox, bpx);
			if (!Math.isNaN(hi)) own = Math.min(own, hi);
			if (!Math.isNaN(lo)) own = Math.max(own, lo);
			box.minContent = box.maxContent = own + bpx;
			return;
		}
		var max = n.measureContent(text, Math.NaN, Math.NaN, Math.POSITIVE_INFINITY, Math.POSITIVE_INFINITY).width;
		var min = Math.min(n.minContentWidth(text), max);
		// (a height of its own through its aspect ratio: that width, its content's min-content when wider)
		var bpy = s.border[0] + s.border[2] + Len.Lens.resolve(s.padding[0], 0, 0) + Len.Lens.resolve(s.padding[2], 0, 0);
		var rw = helder.ui.flow.Ratio.width(box, helder.ui.flow.BlockFlow.size(s.height, Math.NaN, s.borderBox, bpy), bpx, bpy);
		if (!Math.isNaN(rw)) min = max = Math.max(rw, min);
		box.minContent = min + bpx;
		box.maxContent = max + bpx;
	}
}
