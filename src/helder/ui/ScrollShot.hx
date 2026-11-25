package helder.ui;

import helder.os.Mods;

// What the program's last frame had of its scrollers, for the compositor
// (ScrollMirror.adopt): each scroller's box, view, range and offsets, its
// scrollbars; the nodes that may claim a drag or a wheel (a slider, a
// canvas, a pointer, wheel or gesture handler: the gate) and those that
// cover a scroller painted under them, in paint order, each with its clip;
// what the keys would scroll; the native views over scrollers, where
// they were placed. Taken on the program's thread (take) into
// entries kept from frame to frame; handed over whole, read by the
// compositor only.
@:allow(helder.ui)
@:access(helder.ui.Ui)
@:access(helder.ui.Scrolling)
class ScrollShot {
	// entry kinds
	public static inline var SCROLLER = 0;
	public static inline var GATE = 1;
	public static inline var COVER = 2;
	// what a node may claim
	public static inline var WHEEL = 1;
	public static inline var DRAG = 2;

	public var count(default, null) = 0;
	public final entries:Array<ShotEntry> = [];
	// the window's points to its pixels; its size in points
	public var scale = 1.0;
	public var width = 0.0;
	public var height = 0.0;
	// the host's settings (ScrollHost)
	public var elastic = false;
	public var kinetic = false;
	public var stretch = false;
	public var scrollDuration = 0.15;
	// the focus's nearest scroller (an entry; -1: none, the pointer's then;
	// -2: a focus with none around it); the scroll keys the program takes
	// itself (a handler, the keymap, a text field: KEY_* bits; -1 all)
	public var focus = -1;
	public var keys = 0;
	// the frame it was taken in
	public var frame = 0;
	// the native views over scrollers (a macOS field, a web view): each its
	// node, its scroller's entry, where the program placed it (x, y, w, h,
	// shown: 1, else 0; in the window's points)
	public final natives:Array<Node> = [];
	public final nativeAt:Array<Int> = [];
	public final placed:Array<Float> = [];

	public function new() {}

	// (the next entry, reused)
	function add(n:Node, kind:Int, up:Int, outer:Int):ShotEntry {
		if (count == entries.length) entries.push(new ShotEntry());
		var e = entries[count++];
		e.node = n;
		e.kind = kind;
		e.up = up;
		e.outer = outer;
		e.claims = 0;
		e.async = true;
		return e;
	}

	// ui's scrollers as they are now (after its update)
	public static function take(ui:Ui, shot:ScrollShot) {
		shot.count = 0;
		shot.scale = ui.scale;
		shot.width = ui.width;
		shot.height = ui.height;
		shot.elastic = ui.elastic;
		shot.kinetic = ui.kinetic;
		shot.stretch = ui.stretch;
		shot.scrollDuration = ui.scrollDuration;
		shot.frame++;
		var t = new Taking(ui, shot);
		t.walk(ui.root, -1, -1, -1e9, -1e9, 1e9, 1e9);
		var layers = ui.overlay.children;
		for (i in 0...layers.length) {
			var p = layers[i];
			// (a modal popup: what is under it takes no input)
			if (Std.isOfType(p, Popup) && (cast p : Popup).modal) {
				var e = shot.add(p, COVER, -1, -1);
				e.box(0, 0, ui.width, ui.height);
				e.clip(-1e9, -1e9, 1e9, 1e9);
				t.covers.resize(0);
			}
			t.walk(p, -1, -1, -1e9, -1e9, 1e9, 1e9);
		}
		// (the scroll keys: none while a field types or a node hears keys; else each the keymap does not bind)
		var f = ui.focus;
		shot.focus = -1;
		if (f != null) {
			shot.focus = -2;
			var p = f;
			while (p != null && shot.focus == -2) {
				if (p.style.overflow == Scroll) for (i in 0...shot.count)
					if (shot.entries[i].node == p && shot.entries[i].kind == SCROLLER) shot.focus = i;
				p = p.parent;
			}
		}
		shot.keys = keyClaims(ui);
		// (the native views in scrollers, where the program placed them)
		shot.natives.resize(0);
		shot.nativeAt.resize(0);
		shot.placed.resize(0);
		for (v in ui.natives) {
			var r = v.placed;
			if (r == null) continue;
			var sc = v.parent, at = -1;
			while (sc != null && sc.style.overflow != Scroll)
				sc = sc.parent;
			if (sc == null) continue;
			for (i in 0...shot.count)
				if (shot.entries[i].node == sc && shot.entries[i].kind == SCROLLER) at = i;
			if (at < 0) continue;
			shot.natives.push(v);
			shot.nativeAt.push(at);
			for (x in r)
				shot.placed.push(x);
		}
	}

	// the scroll keys, as bits
	public static inline var KEYS = 10;

	static final SCROLL_KEYS = [Key.UP, Key.DOWN, Key.LEFT, Key.RIGHT, Key.PAGE_UP, Key.PAGE_DOWN, Key.HOME, Key.END, Key.SPACE, Key.SPACE];

	// (its bit: Shift and Space the last)
	public static function keyBit(key:Int, mods:Int):Int {
		if (key == Key.SPACE && mods & Mods.SHIFT != 0) return 1 << 9;
		var i = SCROLL_KEYS.indexOf(key);
		return i < 0 ? 0 : 1 << i;
	}

	static function keyClaims(ui:Ui):Int {
		var f = ui.focus;
		if (f != null && f.takesText() || ui.pendingKeys.length > 0 || ui.dragging != null) return -1;
		var n = f != null ? f : ui.root;
		while (n != null) {
			if (n.onKeyDown != null) return -1;
			n = n.parent;
		}
		var stack = ui.contextStack(), bits = 0;
		for (i in 0...KEYS) {
			var m = ui.keymap.match([{key: SCROLL_KEYS[i], mods: i == 9 ? Mods.SHIFT : 0}], stack);
			if (m.exact.length > 0 || m.longer) bits |= 1 << i;
		}
		return bits;
	}
}

// (an entry: its node, its kind, the nearest scroller around it and the
// nearest entry (indices, -1: none); its box and clip, in the coordinates
// of that scroller's content (unscrolled, as Node.absX), the window's
// without one)
@:allow(helder.ui)
class ShotEntry {
	public var node:Null<Node> = null;
	public var kind = 0;
	public var up = -1;
	public var outer = -1;
	// what it may claim (WHEEL, DRAG), whether the compositor may scroll it (a scroller)
	public var claims = 0;
	public var async = true;
	public var x = 0.0;
	public var y = 0.0;
	public var w = 0.0;
	public var h = 0.0;
	public var cx0 = 0.0;
	public var cy0 = 0.0;
	public var cx1 = 0.0;
	public var cy1 = 0.0;
	// a scroller's: its view (the padding box, which clips its content), its
	// range from its start, its offsets, its axes, right to left
	public var vx = 0.0;
	public var vy = 0.0;
	public var vw = 0.0;
	public var vh = 0.0;
	// (its view's size as Scrolling measures it: less its padding)
	public var viewW = 0.0;
	public var viewH = 0.0;
	public var maxX = 0.0;
	public var maxY = 0.0;
	public var scrollX = 0.0;
	public var scrollY = 0.0;
	public var scrollsX = false;
	public var scrollsY = false;
	public var rtl = false;
	// (set by the program since it took the compositor's: its own wins)
	public var own = true;
	// (each axis's scrollbar, x then y: shown (its thumb hit), its track's
	// start, length and offset across, its thickness and inset, its thumb's length)
	public final bars:Array<Float> = [for (_ in 0...14) 0.0];

	public function new() {}

	inline function box(x:Float, y:Float, w:Float, h:Float) {
		this.x = x;
		this.y = y;
		this.w = w;
		this.h = h;
	}

	inline function clip(x0:Float, y0:Float, x1:Float, y1:Float) {
		cx0 = x0;
		cy0 = y0;
		cx1 = x1;
		cy1 = y1;
	}
}

@:access(helder.ui.Ui)
@:access(helder.ui.Scrolling)
@:access(helder.ui.ScrollShot)
private class Taking {
	final ui:Ui;
	final shot:ScrollShot;
	// (the scrollers done, by entry: what is painted over them covers them)
	public final covers:Array<Int> = [];

	public function new(ui, shot) {
		this.ui = ui;
		this.shot = shot;
	}

	// (n under the scroller entry up and the entry outer, clipped to x0...y1 in up's content's coordinates)
	public function walk(n:Node, up:Int, outer:Int, x0:Float, y0:Float, x1:Float, y1:Float) {
		var s = n.style;
		if (s.display == None || n.present != null && n.present.away) return;
		var claims = claimsOf(n);
		if (s.overflow == Scroll) {
			var mx = s.overflowX == Scroll ? Scrolling.maxScroll(n, true) : 0, my = s.overflowY == Scroll ? Scrolling.maxScroll(n, false) : 0;
			if (mx > 0 || my > 0) {
				var e = shot.add(n, ScrollShot.SCROLLER, up, outer), be = s.borderEdges;
				var i = shot.count - 1;
				e.box(n.absX, n.absY, n.width, n.height);
				e.clip(x0, y0, x1, y1);
				e.claims = claims;
				e.vx = n.absX + be.left;
				e.vy = n.absY + be.top;
				e.vw = n.width - be.horizontal;
				e.vh = n.height - be.vertical;
				e.viewW = Scrolling.viewSize(n, true);
				e.viewH = Scrolling.viewSize(n, false);
				e.maxX = mx;
				e.maxY = my;
				e.scrollX = n.scrollX;
				e.scrollY = n.scrollY;
				e.scrollsX = s.overflowX == Scroll;
				e.scrollsY = s.overflowY == Scroll;
				e.rtl = n.rtl();
				e.own = ui.mirrorOwn(n);
				bars(n, e);
				var inner = covers.length;
				walkChildren(n, i, i, -1e9, -1e9, 1e9, 1e9);
				covers.resize(inner);
				covers.push(i);
				return;
			}
		}
		if (claims != 0) {
			var e = shot.add(n, ScrollShot.GATE, up, outer);
			e.box(n.absX, n.absY, n.width, n.height);
			e.clip(x0, y0, x1, y1);
			e.claims = claims;
			outer = shot.count - 1;
		} else if (n.width > 0 && n.height > 0 && over(n)) {
			var e = shot.add(n, ScrollShot.COVER, up, outer);
			e.box(n.absX, n.absY, n.width, n.height);
			e.clip(x0, y0, x1, y1);
			outer = shot.count - 1;
		}
		if (s.overflow != Visible) {
			var be = s.borderEdges;
			x0 = Math.max(x0, n.absX + be.left);
			y0 = Math.max(y0, n.absY + be.top);
			x1 = Math.min(x1, n.absX + n.width - be.right);
			y1 = Math.min(y1, n.absY + n.height - be.bottom);
			if (x1 <= x0 || y1 <= y0) return;
		}
		walkChildren(n, up, outer, x0, y0, x1, y1);
	}

	function walkChildren(n:Node, up:Int, outer:Int, x0:Float, y0:Float, x1:Float, y1:Float) {
		var order = n.paintOrder();
		if (order != null) {
			for (c in order)
				walk(c, up, outer, x0, y0, x1, y1);
			return;
		}
		for (c in n.children)
			if (c.style.position == Relative) walk(c, up, outer, x0, y0, x1, y1);
		for (c in n.children)
			if (c.style.position != Relative) walk(c, up, outer, x0, y0, x1, y1);
	}

	// (whether n is over a scroller painted before it that it is not in)
	function over(n:Node):Bool {
		if (covers.length == 0) return false;
		var ox = Scrolling.scrolled(n, true), oy = Scrolling.scrolled(n, false);
		var ax = n.absX - ox, ay = n.absY - oy, bx = ax + n.width, by = ay + n.height;
		for (i in covers) {
			var e = shot.entries[i], s = e.node;
			if (s == null) continue;
			var sx = e.x - Scrolling.scrolled(s, true), sy = e.y - Scrolling.scrolled(s, false);
			if (ax < sx + e.w && bx > sx && ay < sy + e.h && by > sy) return true;
		}
		return false;
	}

	// (what n may claim: a drag (a pointer's handler, a recogniser, a drag's
	// data, selectable text, its own drawing: a canvas) or a wheel)
	static function claimsOf(n:Node):Int {
		var c = 0;
		if (n.onWheel != null) c |= ScrollShot.WHEEL;
		if (n.onPointerDown != null || n.onPointerMove != null || n.onPointerUp != null || n.dragData != null || n.onDragStart != null)
			c |= ScrollShot.DRAG;
		var gs = n.gestures;
		if (gs != null) for (g in gs)
			if (!Std.isOfType(g, helder.ui.gesture.Tap)) c |= ScrollShot.DRAG;
		if (n.selectable) c |= ScrollShot.DRAG;
		return c;
	}

	// (its scrollbars' geometry, as Scrolling.thumb measures it, unstretched)
	function bars(n:Node, e:ShotEntry) {
		var shown = !ui.overlayBars || ui.barShown(n) > 0;
		for (k in 0...2) {
			var x = k == 0, o = k * 7, b = e.bars;
			b[o] = 0;
			if ((x ? n.style.overflowX : n.style.overflowY) != Scroll || Scrolling.maxScroll(n, x) <= 0 || Scrolling.barSize(n) <= 0) continue;
			var t = Scrolling.track(n, x);
			if (t[1] <= 0) continue;
			b[o] = shown ? 1 : 0;
			b[o + 1] = t[0];
			b[o + 2] = t[1];
			b[o + 3] = t[2];
			b[o + 4] = Scrolling.barSize(n);
			b[o + 5] = Scrolling.barInset(n);
			b[o + 6] = Scrolling.thumbLength(t[1], Scrolling.viewSize(n, x), x ? n.contentWidth : n.contentHeight);
		}
	}
}
