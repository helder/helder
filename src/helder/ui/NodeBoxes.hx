package helder.ui;

import helder.ui.box.Box;
import helder.ui.box.BoxStyle;
import helder.ui.box.FontMatch;
import helder.ui.box.Fragments;
import helder.ui.box.Len;
import helder.ui.flow.Contexts;
import helder.ui.flow.FormattingContext;
import helder.ui.flow.Space;

// helder.ui's nodes laid out by the CSS engine (the port's first step: the
// switch to fast nodes as helder.ui.Node): each node a box of the engine's
// tree, kept from one layout to the next and styled again where the node
// is dirty, its style read into the box's (BoxStyle); views laid out by
// the engine's block, flex and grid; a node with content of its own (a
// TextNode, an image, a custom drawn node) a box the measured context
// lays out by the node's own measureContent, so that what it paints is
// what it was measured as. Its results written back as Layout's are
// (Layout.round), so the rest of helder.ui (its paint walk, layers and
// compositor, events, focus, assistive technology) runs on as it does.
// Layout.run's drop-in: Ui.layout, -D helder.engine.
@:allow(helder.ui)
@:access(helder.ui.Node)
class NodeBoxes {
	final fragments = new Fragments();
	final fonts = new FontMatch();
	final contexts:Contexts;
	final measured = new Measured();
	// (the root's containing block, as a document's: the root a positioned box in it, as large as the window, its
	// absolutely positioned children placed in its padding box as Layout places them)
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
			s.textPart = helder.ui.fast.Resolve.root;
			s.displayRead = true;
			s.displayOuter = BoxStyle.BLOCK;
			s.displayInner = BoxStyle.FLOW;
			s.layoutRead = true;
			s.traits = BoxStyle.VISIBLE | BoxStyle.COLLAPSE | BoxStyle.WRAPS;
			s.opacityValue = 1;
		}
		icb = new Box(Block, s, null);
	}

	// Layout.run's: the tree at root laid out at width by height (the root as large), its nodes told; false: nothing to do
	public static function run(root:Node, width:Float, height:Float, text:TextEngine, ?scrollers:Array<Node>):Bool {
		if (!root.dirty && root.lw == width && root.lh == height && !root.relaid) return false;
		var e = root.boxes ?? (root.boxes = new NodeBoxes());
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
		@:privateAccess Layout.round(root, 0, 0, 0, 0, scrollers);
		return true;
	}

	// (a node's box: made, or styled again with its children's where it is dirty; its ancestors' caches let go)
	function sync(n:Node):Box {
		var b = n.box;
		if (b != null && !n.dirty) return b;
		var s = styleOf(n);
		// (a fieldset's legend first in its column: outside the flex container in CSS, so no gap after it, as Layout
		// has it: its bottom margin less the gap)
		var p = n.parent;
		if (n.legend && p != null && p.style.display != Grid && (p.style.flexDirection == Column || p.style.flexDirection == ColumnReverse)
			&& firstShown(p) == n && p.style.rowGap != 0) {
			s = build(n);
			@:privateAccess s.margin[2] = Px(Len.Lens.resolve(s.margin[2], Math.NaN, 0) - p.style.rowGap);
		}
		// (the root as large as the window, whatever its style says, as Layout has it)
		if (n.parent == null) {
			s = build(n);
			@:privateAccess {
				s.width = Px(width);
				s.height = Px(height);
				s.minWidth = s.minHeight = Px(0);
				s.maxWidth = s.maxHeight = Len.Auto;
			}
		}
		var own = n.hasContent() && (n.children.length == 0 || n.contentOwnsChildren());
		var kind:helder.ui.box.BoxKind = own || s.inner == BoxStyle.FLEX || s.inner == BoxStyle.GRID ? Container : Block;
		if (b == null || b.kind != kind) {
			b = new Box(kind, s, n);
			b.flags |= Box.MADE;
			n.box = b;
		} else @:privateAccess b.restyle(s);
		b.context = own ? measured : contexts.of(s.inner, _ -> {});
		// (its children's boxes, in order: none for a node whose content they are, nor for those not shown)
		while (b.first != null) b.first.remove();
		if (!own) for (c in n.children) if (c.style.display != None) b.append(sync(c)) else hide(c);
		b.uncache();
		b.inlineCache = null;
		b.cacheWidth = b.minContent = b.maxContent = Math.NaN;
		n.dirty = false;
		// (round goes through it and what is in it: its children's places may have changed)
		n.relaid = true;
		return b;
	}

	static function firstShown(n:Node):Null<Node> {
		for (c in n.children) if (c.style.display != None && c.style.position != Absolute) return c;
		return null;
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
		if (id == n.boxFragment && !n.relaid) return;
		n.boxFragment = id;
		// (content measured is its own, its extent left as Layout leaves it)
		var b = n.box;
		if (b == null || b.context == measured) return;
		// (as Layout's: from its content box's start, each child's end margin, what a child not clipping overflows)
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
				var cs = c.style, ow = c.lw, oh = c.lh;
				if (cs.overflow == Visible && !rtl) {
					var cp:helder.os.Edges = cs.padding ?? helder.os.Edges.ZERO, cb = cs.borderEdges;
					ow = Math.max(ow, c.contentWidth + cp.left + cb.left);
					oh = Math.max(oh, c.contentHeight + cp.top + cb.top);
				}
				var cm:helder.os.Edges = cs.margin ?? helder.os.Edges.ZERO;
				ext[0] = Math.max(ext[0], x - padL + ow + (Math.isNaN(cm.right) ? 0 : cm.right));
				ext[1] = Math.max(ext[1], y - padT + oh + (Math.isNaN(cm.bottom) ? 0 : cm.bottom));
				ext[2] = Math.min(ext[2], x - padL);
			} else if (c == null) children(n, k, x, y, padL, padT, ext, rtl);
			k = f.next(k);
		}
	}

	// ---- a node's style as its box's: the box model, flex and grid, position, overflow

	// (the box styles made, by what of a node's style they read: one made for
	// all nodes styled alike, as a list's rows are; per hash, keys and styles)
	static final made = new haxe.ds.IntMap<Array<Any>>();
	static final key:Array<Float> = [for (_ in 0...64) 0.0];
	static var kn = 0;
	static var kh = 0;
	// (let go when many: a style animated through a width makes one a frame)
	static var count = 0;

	static function styleOf(n:Node):BoxStyle {
		var st = n.style;
		if (NodeGrid.has(st)) return build(n);
		kn = 0;
		kh = 17;
		var p:helder.os.Edges = st.padding ?? helder.os.Edges.ZERO, m:helder.os.Edges = st.margin ?? helder.os.Edges.ZERO, bw = st.borderEdges ?? helder.os.Edges.ZERO;
		// (no array made: a list's thousand rows each read)
		put(n.rtl() ? 1 : 0);
		put(int(st.display));
		put(int(st.flexDirection));
		put(int(st.justifyContent));
		put(int(st.alignContent));
		put(int(st.alignItems));
		put(int(st.alignSelf));
		put(int(st.position));
		put(int(st.overflow));
		put(int(st.overflowX));
		put(int(st.overflowY));
		put(m.top);
		put(m.right);
		put(m.bottom);
		put(m.left);
		put(p.top);
		put(p.right);
		put(p.bottom);
		put(p.left);
		put(bw.top);
		put(bw.right);
		put(bw.bottom);
		put(bw.left);
		put(st.order);
		put(st.flexGrow);
		put(st.flexShrink);
		put(st.rowGap);
		put(st.columnGap);
		put(st.flexWrap ? 1 : 0);
		put(st.aspectRatio);
		put(int(st.justifyItems));
		put(int(st.justifySelf));
		dim(st.width);
		dim(st.height);
		dim(st.minWidth);
		dim(st.minHeight);
		dim(st.maxWidth);
		dim(st.maxHeight);
		dim(st.flexBasis);
		dim(st.top);
		dim(st.right);
		dim(st.bottom);
		dim(st.left);
		var h = kh, at = made.get(h);
		if (at != null) {
			var i = 0;
			while (i < at.length) {
				if (same(at[i])) return at[i + 1];
				i += 2;
			}
		} else {
			if (++count > 4096) {
				made.clear();
				count = 1;
			}
			made.set(h, at = []);
		}
		var b = build(n);
		at.push(key.slice(0, kn));
		at.push(b);
		return b;
	}

	static inline function int<T>(v:T):Int
		return cast v;

	static function dim(d:Dim)
		switch (d : DimValue) {
			case Px(v):
				put(1);
				put(v);
			case Percent(v):
				put(2);
				put(v);
			case Calc(p, px):
				put(3);
				put(p);
				put(px);
			case v:
				put(4 + v.getIndex());
		}

	// (NaN, an auto margin, the same as itself)
	static inline function hashOf(v:Float):Int
		return v != v ? 7 : Std.int(v * 64);

	static function same(a:Array<Float>):Bool {
		if (a.length != kn) return false;
		for (i in 0...kn) if (a[i] != key[i] && (a[i] == a[i] || key[i] == key[i])) return false;
		return true;
	}

	static inline function put(v:Float) {
		key[kn++] = v;
		kh = kh * 31 + hashOf(v);
	}

	static function build(n:Node):BoxStyle {
		var st = n.style, s = new BoxStyle();
		@:privateAccess {
			s.textPart = helder.ui.fast.Resolve.root;
			s.displayRead = true;
			if (st.display == None) s.displayNone = true;
			s.displayOuter = BoxStyle.BLOCK;
			s.displayInner = st.display == Block ? BoxStyle.FLOW : st.display == Grid ? BoxStyle.GRID : BoxStyle.FLEX;
			var p:helder.os.Edges = st.padding ?? helder.os.Edges.ZERO, m:helder.os.Edges = st.margin ?? helder.os.Edges.ZERO, bw = st.borderEdges ?? helder.os.Edges.ZERO;
			for (v in [m.top, m.right, m.bottom, m.left]) s.margin.push(Math.isNaN(v) ? Len.Auto : Px(v));
			for (v in [p.top, p.right, p.bottom, p.left]) s.padding.push(Px(v));
			for (v in [bw.top, bw.right, bw.bottom, bw.left]) s.border.push(v);
			s.width = len(st.width);
			var keyword = sizing(st.width);
			var rare:Null<helder.ui.box.BoxRare> = null;
			function rare1():helder.ui.box.BoxRare
				return rare ??= new helder.ui.box.BoxRare();
			if (keyword != "") rare1().widthKeyword = keyword;
			var low = sizing(st.minWidth), high = sizing(st.maxWidth);
			if (low != "") rare1().minWidthKeyword = low;
			if (high != "") rare1().maxWidthKeyword = high;
			if (st.aspectRatio > 0) {
				s.ratio = st.aspectRatio;
				s.ratioAuto = false;
			}
			if (NodeGrid.has(st)) NodeGrid.fill(st, rare1());
			s.height = len(st.height);
			s.minWidth = len(st.minWidth);
			s.minHeight = len(st.minHeight);
			s.maxWidth = len(st.maxWidth);
			s.maxHeight = len(st.maxHeight);
			s.borderBox = true;
			s.modelRead = true;
			s.orderValue = st.order;
			s.growValue = st.flexGrow;
			s.shrinkValue = st.flexShrink;
			s.basisValue = len(st.flexBasis);
			s.basisWord = st.flexBasis == DimValue.Auto ? "auto" : sizing(st.flexBasis);
			s.directionValue = switch st.flexDirection {
				case Row: "row";
				case RowReverse: "row-reverse";
				case ColumnReverse: "column-reverse";
				case _: "column";
			}
			s.wrapValue = st.flexWrap ? "wrap" : "nowrap";
			s.aligns.push(switch st.justifyContent {
				case Start: "flex-start";
				case End: "flex-end";
				case Center: "center";
				case SpaceBetween: "space-between";
				case SpaceAround: "space-around";
				case SpaceEvenly: "space-evenly";
				case _: "normal";
			});
			s.aligns.push(switch st.alignContent {
				case Start: "flex-start";
				case End: "flex-end";
				case Center: "center";
				case Stretch: "stretch";
				case SpaceBetween: "space-between";
				case SpaceAround: "space-around";
				case SpaceEvenly: "space-evenly";
				case _: "normal";
			});
			// (a container's stretch, helder.ui's default: CSS's normal, which a grid's aspect-ratio items start at)
			s.aligns.push(st.alignItems == Stretch ? "normal" : align(st.alignItems, "normal"));
			s.aligns.push(align(st.alignSelf, "auto"));
			s.aligns.push(st.justifyItems == Stretch ? "normal" : align(st.justifyItems, "legacy"));
			s.aligns.push(align(st.justifySelf, "auto"));
			s.rowGapValue = Px(st.rowGap);
			s.columnGapValue = Px(st.columnGap);
			for (v in [st.top, st.right, st.bottom, st.left]) s.insets.push(len(v));
			s.layoutRead = true;
			s.positionWord = switch st.position {
				case Absolute: "absolute";
				case Sticky: "sticky";
				case _: "relative";
			}
			var scroll = st.overflow == Scroll || st.overflowX == Scroll || st.overflowY == Scroll;
			var hidden = st.overflow == Hidden || st.overflowX == Hidden || st.overflowY == Hidden;
			s.traits = (scroll || hidden ? BoxStyle.CLIPS : 0) | (scroll ? BoxStyle.SCROLLS : 0) | (hidden ? BoxStyle.HIDDEN_OVERFLOW : 0) | BoxStyle.VISIBLE
				| BoxStyle.COLLAPSE | BoxStyle.WRAPS | (n.rtl() ? BoxStyle.RTL : 0);
			s.opacityValue = 1;
			if (rare != null) s.rareRead = rare;
		}
		return s;
	}

	static function len(d:Dim):Len
		return switch (d : DimValue) {
			case Px(v): Px(v);
			case Percent(v): Percent(v);
			case Calc(p, px): px == 0 ? Percent(p) : p == 0 ? Px(px) : Len.Calc(helder.css.CssCalc.CssCalcNode.Sum([helder.css.CssCalc.CssCalcNode.Value(p, "%"), helder.css.CssCalc.CssCalcNode.Value(px, "px")]));
			case _: Len.Auto;
		}

	// (min-content, max-content, fit-content as CSS writes them; "": another size)
	static function sizing(d:Dim):String
		return switch (d : DimValue) {
			case MinContent: "min-content";
			case MaxContent: "max-content";
			case FitContent: "fit-content";
			case _: "";
		}

	static function align(a:Align, fallback:String):String
		return switch a {
			case Auto: fallback;
			case Start: "flex-start";
			case End: "flex-end";
			case Center: "center";
			case Stretch: "stretch";
			case Baseline: "baseline";
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
