package helder.ui;

import helder.os.Mods;
import helder.gfx.Color;

// Ui's scrolling: the wheel's (the nearest Overflow Scroll ancestor that
// can move that way), the keys' (eased: scrollBy), scrollIntoView, and the
// scrollbars' geometry and their thumbs dragged (a click on a track pages).
// A scroller's offsets run from scrollStart (0, or right to left sideways
// less maxScroll) over maxScroll.
@:allow(helder.ui)
@:access(helder.ui.Ui)
class Scrolling {
	// the wheel's scroll from target: its nearest scroller that can move that way
	// (the scroller it moved: ui.wheelNode, the host's latch)
	static function wheel(ui:ScrollHost, target:Node, deltaX:Float, deltaY:Float, eased = false) {
		ui.wheelNode = null;
		var n = target;
		while (n != null) {
			if (n.style.overflow == Scroll && (canScroll(n, deltaX, true) || canScroll(n, deltaY, false))) {
				ui.wheelNode = n;
				// (a mouse's notch: glided to, slowing, from where a glide is heading)
				if (eased) {
					scrollBy(ui, n, deltaX, deltaY, true);
					return;
				}
				stopGlide(ui, n);
				var bx = n.scrollX, by = n.scrollY;
				n.scrollX += deltaX;
				n.scrollY += deltaY;
				clamp(n);
				// (what it could not scroll, past its end: Stretch's)
				// (under half a point: none, what floating point leaves of a move that fit)
				ui.overNode = n;
				ui.overX = over(deltaX - (n.scrollX - bx));
				ui.overY = over(deltaY - (n.scrollY - by));
				if (n.onScroll != null) n.onScroll();
				ui.requestFrame();
				return;
			}
			n = n.parent;
		}
		// (none could: all of it past the end of the innermost that scrolls on the move's axis)
		var alongX = Math.abs(deltaX) > Math.abs(deltaY);
		n = target;
		while (n != null) {
			if (n.style.overflow == Scroll && (alongX ? n.style.overflowX : n.style.overflowY) == Scroll && maxScroll(n, alongX) > 0) {
				ui.overNode = n;
				ui.overX = deltaX;
				ui.overY = deltaY;
				return;
			}
			n = n.parent;
		}
	}

	// whether a wheel on n by deltaX, deltaY would scroll something: a
	// scroller at n or around it (the innermost first) not at its end that way
	static inline function over(d:Float):Float
		return Math.abs(d) < 0.5 ? 0 : d;

	static function scrollsAt(ui:Ui, n:Null<Node>, deltaX:Float, deltaY:Float):Bool {
		while (n != null) {
			if (n.style.overflow == Scroll && (canScroll(n, deltaX, true) || canScroll(n, deltaY, false))) return true;
			n = n.parent;
		}
		return false;
	}

	// keys that scroll, when the focus took none of them (as a browser's):
	// the arrows by 40 pixels, Page Up and Down and Space (Shift: up) by
	// seven eighths of the view, Home and End to the ends; the nearest
	// scroller that can move that way around the focus, else the pointer
	static inline var ARROW_STEP = 40;

	static function keyScroll(ui:Ui, key:Int, mods:Int):Bool {
		if (ui.focus != null && ui.focus.takesText()) return false;
		return keyScrollFrom(ui, ui.focus != null ? ui.focus : ui.hover, key, mods);
	}

	// (from n, the focus or the pointer's node)
	static function keyScrollFrom(ui:ScrollHost, n:Null<Node>, key:Int, mods:Int):Bool {
		if (mods & (Mods.CONTROL | Mods.META | Mods.ALT) != 0) return false;
		var x = key == Key.LEFT || key == Key.RIGHT;
		var back = key == Key.UP || key == Key.LEFT || key == Key.PAGE_UP || key == Key.HOME || key == Key.SPACE && mods & Mods.SHIFT != 0;
		var page = key == Key.PAGE_UP || key == Key.PAGE_DOWN || key == Key.SPACE, edge = key == Key.HOME || key == Key.END;
		if (!(x || page || edge || key == Key.UP || key == Key.DOWN)) return false;
		while (n != null) {
			if (n.style.overflow == Scroll) {
				var s = n.style, view = (x ? n.width : n.height) - (x ? s.borderEdges.horizontal + s.padding.horizontal : s.borderEdges.vertical + s.padding.vertical);
				var d = edge ? maxScroll(n, x) + 1 : page ? Math.max(1, view * 0.875) : ARROW_STEP;
				if (back) d = -d;
				if (canScroll(n, d, x)) {
					scrollBy(ui, n, x ? d : 0, x ? 0 : d);
					return true;
				}
			}
			n = n.parent;
		}
		return false;
	}

	// scrolls by dx, dy glided (ScrollGlide: a wheel's notch over its
	// distance's time, as Chromium's; keys' over Ui.scrollDuration), on from
	// where a glide is heading at its speed; at once where scrollDuration is 0
	static function scrollBy(ui:ScrollHost, n:Node, dx:Float, dy:Float, out = false) {
		var g = ui.glides.get(n);
		var gliding = g != null && g.gliding;
		var tx = clampTo(n, true, (gliding ? g.toX : n.scrollX) + dx), ty = clampTo(n, false, (gliding ? g.toY : n.scrollY) + dy);
		if (ui.scrollDuration <= 0) {
			ui.scrollTo(n, tx, ty);
			return;
		}
		if (g == null) ui.glides.set(n, g = new ScrollGlide(n, (x, y) -> {
			setScroll(ui, n, true, x);
			setScroll(ui, n, false, y);
		}, ui));
		g.fixed = out ? 0 : ui.scrollDuration;
		g.to(n.scrollX, n.scrollY, {x: tx, y: ty});
	}

	// (a scroll of another kind: n's glide stopped where it is)
	static function stopGlide(ui:ScrollHost, n:Node) {
		var g = ui.glides.get(n);
		if (g != null) g.stop();
	}

	static function canScroll(n:Node, d:Float, x:Bool):Bool {
		if (d == 0 || (x ? n.style.overflowX : n.style.overflowY) != Scroll) return false;
		var lo = scrollStart(n, x), v = x ? n.scrollX : n.scrollY;
		return d > 0 ? v < lo + maxScroll(n, x) : v > lo;
	}

	// how far n scrolls on the axis (from scrollStart)
	static function maxScroll(n:Node, x:Bool):Float {
		var s = n.style, inset = x ? s.borderEdges.horizontal + s.padding.horizontal : s.borderEdges.vertical + s.padding.vertical;
		var view = (x ? n.width : n.height) - inset;
		// (less than half a pixel over: none, the box being rounded and the content not, as Chromium snaps scrollHeight)
		var over = (x ? n.contentWidth : n.contentHeight) - view;
		return over < 0.5 ? 0 : over;
	}

	// its least offset on the axis: 0, but right to left, sideways, its
	// content overflows to the left: scrolled from 0 (its right end) down to
	// less maxScroll, as Chromium's scrollLeft
	static function scrollStart(n:Node, x:Bool):Float
		return x && n.rtl() ? -maxScroll(n, true) : 0;

	static inline function clampTo(n:Node, x:Bool, v:Float):Float {
		var lo = scrollStart(n, x);
		return Math.max(lo, Math.min(v, lo + maxScroll(n, x)));
	}

	// a scroller's offsets back within its extent
	static function clamp(n:Node) {
		var x = clampTo(n, true, n.scrollX), y = clampTo(n, false, n.scrollY);
		if (x != n.scrollX || y != n.scrollY) {
			n.scrollX = x;
			n.scrollY = y;
			if (n.onScroll != null) n.onScroll();
		}
	}

	// scrolls n's scrolling ancestors, nearest first, as little as brings it
	// into each one's view (its far edge at the view's, unless it is larger)
	static function scrollIntoView(ui:Ui, n:Node) {
		var p = n.parent, shiftX = 0.0, shiftY = 0.0;
		while (p != null) {
			if (p.style.overflow == Scroll) {
				for (x in [false, true]) {
					var s = p.style, inset = x ? s.borderEdges.left + s.padding.left : s.borderEdges.top + s.padding.top;
					var start = (x ? n.absX - p.absX - shiftX : n.absY - p.absY - shiftY) - inset, end = start + (x ? n.width : n.height);
					var view = viewSize(p, x), cur = x ? p.scrollX : p.scrollY;
					if (start < cur) setScroll(ui, p, x, start) else if (end > cur + view) setScroll(ui, p, x, Math.min(start, end - view));
				}
				shiftX += p.scrollX;
				shiftY += p.scrollY;
			}
			p = p.parent;
		}
	}

	// n brought into its nearest vertical scroller's view, margin clear of
	// its edges and of bottom (window pixels: a keyboard's top), scrolled
	// as little as that takes, glided over duration seconds (0: at once)
	static function reveal(ui:Ui, n:Node, margin:Float, bottom:Float, duration:Float) {
		var p = n.parent;
		while (p != null && !(p.style.overflow == Scroll && p.style.overflowY == Scroll))
			p = p.parent;
		if (p == null) return;
		var b = n.windowBounds(), v = p.windowBounds(), s = p.style;
		var top = v.y + s.borderEdges.top + s.padding.top, end = Math.min(v.y + v.height - s.borderEdges.bottom - s.padding.bottom, bottom);
		var d = 0.0;
		if (b.y - margin < top) d = b.y - margin - top else if (b.y + b.height + margin > end) d = Math.min(b.y + b.height + margin - end, b.y - margin - top);
		var y = clampTo(p, false, p.scrollY + d);
		if (Math.abs(y - p.scrollY) < 0.5) return;
		if (duration <= 0) {
			ui.scrollTo(p, p.scrollX, y);
			return;
		}
		var g = ui.glides.get(p);
		if (g == null) ui.glides.set(p, g = new ScrollGlide(p, (x, y) -> {
			setScroll(ui, p, true, x);
			setScroll(ui, p, false, y);
		}, ui));
		g.fixed = duration;
		g.to(p.scrollX, p.scrollY, {x: p.scrollX, y: y});
	}

	static function viewSize(n:Node, x:Bool):Float {
		var s = n.style;
		return (x ? n.width : n.height) - (x ? s.borderEdges.horizontal + s.padding.horizontal : s.borderEdges.vertical + s.padding.vertical);
	}

	// a scrollbar's track on axis x (horizontal) or y: its start and length
	// along the axis (absolute), its offset across it; right to left, the
	// vertical one on the left, as Chromium has it
	static function track(n:Node, x:Bool):Array<Float> {
		var be = n.style.borderEdges, i = barInset(n), rtl = n.rtl(), b = barSize(n);
		// (the other axis's bar, if any, takes the corner: its track's width where it has one)
		var corner = maxScroll(n, !x) > 0 ? (legacy(n) ? gutter(n) : b + i) : 0;
		return x ? [n.absX + be.left + i + (rtl ? corner : 0), n.width - be.horizontal - 2 * i - corner, n.absY + n.height - be.bottom - i - b] : [
			n.absY + be.top + i, n.height - be.vertical - 2 * i - corner, rtl ? n.absX + be.left + i : n.absX + n.width - be.right - i - b];
	}

	// (a scroller's scrollbar thickness: its style's, 0 for none; its Ui's
	// look's: helder's 6, macOS's overlay thumb 7, its always-shown thumb 8 in
	// a 15-point track)
	static function barSize(n:Node):Float {
		var look = n.ui == null ? ScrollbarLook.Plain : n.ui.scrollbarLook, a = art(n);
		var full = a != null ? a[1] : look == ScrollbarLook.MacLegacy ? 8.0 : look == ScrollbarLook.MacOverlay ? 7.0 : Ui.SCROLLBAR;
		return switch n.style.scrollbarWidth {
			case None: 0;
			case Thin: full * 2 / 3;
			case _: full;
		}
	}

	// (the thumb's inset from the box's edge and its track's ends: macOS's always-shown scrollers 3)
	static function barInset(n:Node):Float {
		var a = art(n);
		return a != null ? a[2] : legacy(n) ? 3 : Ui.SCROLLBAR_INSET;
	}

	// (the platform's scrollbars' metrics, where its art draws them: null, helder's)
	static function art(n:Node):Null<Array<Float>> {
		var ui = n.ui;
		if (ui == null || ui.scrollbarArt == null || ui.scrollbarLook == ScrollbarLook.Plain) return null;
		return ui.scrollbarArt.metrics(ui.scrollbarLook == ScrollbarLook.MacOverlay);
	}

	static inline function legacy(n:Node):Bool
		return n.ui != null && n.ui.scrollbarLook == ScrollbarLook.MacLegacy;

	// (macOS's always-shown scroller's track, across: the thumb, its insets and a 1-point border)
	static function gutter(n:Node):Float {
		var a = art(n);
		return a != null ? a[0] : barSize(n) + 2 * barInset(n) + 1;
	}

	// (the scrollbar colours n inherits: its track's or its thumb's; null: none given)
	static function inheritedBar(n:Node, track:Bool):Null<Color> {
		var p = n;
		while (p != null) {
			var c = track ? p.style.scrollbarTrackColor : p.style.scrollbarColor;
			if (c != null) return c;
			p = p.parent;
		}
		return null;
	}

	static function thumbLength(trackLength:Float, view:Float, content:Float):Float
		return Math.min(trackLength, Math.max(Ui.MIN_THUMB, trackLength * view / content));

	// the thumb's rectangle (x, y, w, h: absolute, unscrolled), or null when n
	// does not overflow on the axis
	static function thumb(n:Node, x:Bool):Null<Array<Float>> {
		if ((x ? n.style.overflowX : n.style.overflowY) != Scroll) return null;
		var max = maxScroll(n, x);
		if (max <= 0) return null;
		if (barSize(n) <= 0) return null;
		var t = track(n, x);
		if (t[1] <= 0) return null;
		var len = thumbLength(t[1], viewSize(n, x), x ? n.contentWidth : n.contentHeight);
		// (past an end, stretching: the thumb shrinks against it, as AppKit's)
		var f = ((x ? n.scrollX : n.scrollY) - scrollStart(n, x)) / max, over = f < 0 ? -f * max : f > 1 ? (f - 1) * max : 0.0;
		if (over > 0) len = Math.max(Math.min(len, Ui.MIN_THUMB / 2), len * (1 - over / Math.max(1, viewSize(n, x))));
		var at = t[0] + (t[1] - len) * Math.max(0, Math.min(1, f));
		var b = barSize(n);
		return x ? [at, t[2], len, b] : [t[2], at, b, len];
	}

	// a node's offset from window to its own (unscrolled) coordinates: its
	// ancestors' scrolling
	static function scrolled(n:Node, x:Bool):Float {
		var d = 0.0, p = n.parent;
		while (p != null) {
			if (p.style.overflow == Scroll) d += x ? p.scrollX : p.scrollY;
			p = p.parent;
		}
		return d;
	}

	// a press on a scrollbar of target or an ancestor: starts dragging its
	// thumb, or pages towards the press on its track
	static function scrollbarDown(ui:Ui, target:Node, px:Float, py:Float):Bool {
		var n = target;
		while (n != null) {
			// (overlay scrollbars: found only while shown)
			if (n.style.overflow == Scroll && (!ui.overlayBars || ui.barShown(n) > 0))
				for (x in [false, true]) {
					var t = thumb(n, x);
					if (t == null) continue;
					var tr = track(n, x);
					var lx = px + scrolled(n, true), ly = py + scrolled(n, false);
					var along = x ? lx : ly, across = x ? ly : lx;
					var i = barInset(n);
					if (across < tr[2] - i || across > tr[2] + barSize(n) + i || along < tr[0] || along > tr[0] + tr[1]) continue;
					var start = x ? t[0] : t[1], len = x ? t[2] : t[3];
					if (along >= start && along <= start + len) {
						ui.drag = n;
						ui.dragX = x;
						ui.dragFrom = x ? px : py;
						ui.dragScroll = x ? n.scrollX : n.scrollY;
						ui.requestFrame();
					} else if (ui.routed != ScrollMirror.TAKEN) {
						// (the compositor's click: it pages)
						var page = viewSize(n, x) * (along < start ? -1 : 1);
						setScroll(ui, n, x, (x ? n.scrollX : n.scrollY) + page);
					}
					return true;
				}
			n = n.parent;
		}
		return false;
	}

	// the scrollers a platform's scroll views drive (Ui.scrollViews): those
	// that overflow and show (some of their box within what clips them), in
	// paint order, the records kept by node
	static function views(ui:Ui):Array<ScrollView> {
		var out = ui.scrollList;
		out.resize(0);
		ui.scrollPass++;
		var layers = ui.overlay.children;
		// (a modal popup: what is under it takes no input at all)
		inline function modalAbove(i:Int):Bool {
			var any = false;
			for (j in i + 1...layers.length)
				if (Std.isOfType(layers[j], Popup) && (cast layers[j] : Popup).modal) any = true;
			return any;
		}
		collect(ui, ui.root, 0, 0, 0, 0, ui.width, ui.height, false, modalAbove(-1), null, out);
		var from = out.length;
		for (v in out)
			v.layerIndex = -1;
		for (i in 0...layers.length) {
			collect(ui, layers[i], 0, 0, 0, 0, ui.width, ui.height, true, modalAbove(i), null, out);
			for (k in from...out.length)
				out[k].layerIndex = i;
			from = out.length;
		}
		// (the popups above each: their boxes over it, in its box)
		for (v in out) {
			var c = v.covers;
			c.resize(0);
			for (j in v.layerIndex + 1...layers.length) {
				var p = layers[j];
				var x0 = Math.max(p.absX, v.x), y0 = Math.max(p.absY, v.y), x1 = Math.min(p.absX + p.width, v.x + v.width), y1 = Math.min(p.absY + p.height, v.y + v.height);
				if (x1 <= x0 || y1 <= y0) continue;
				c.push(x0 - v.x);
				c.push(y0 - v.y);
				c.push(x1 - x0);
				c.push(y1 - y0);
			}
		}
		// (those gone from the tree or no longer scrolling: let go)
		var gone = [for (n => v in ui.scrollKept) if (v.pass != ui.scrollPass) n];
		for (n in gone)
			ui.scrollKept.remove(n);
		return out;
	}

	// (ox, oy: the scrolling of n's ancestors; x0 to y1: what clips it, on screen)
	static function collect(ui:Ui, n:Node, ox:Float, oy:Float, x0:Float, y0:Float, x1:Float, y1:Float, layer:Bool, covered:Bool, parent:Null<ScrollView>,
			out:Array<ScrollView>) {
		var s = n.style;
		if (s.display == None || n.present != null && n.present.away) return;
		if (s.overflow != Visible) {
			var be = s.borderEdges, bx = n.absX - ox + be.left, by = n.absY - oy + be.top;
			var bw = n.width - be.horizontal, bh = n.height - be.vertical;
			if (s.overflow == Scroll) {
				var mx = s.overflowX == Scroll ? maxScroll(n, true) : 0, my = s.overflowY == Scroll ? maxScroll(n, false) : 0;
				if ((mx > 0 || my > 0) && bx < x1 && by < y1 && bx + bw > x0 && by + bh > y0) {
					var v = ui.scrollKept.get(n);
					if (v == null) ui.scrollKept.set(n, v = new ScrollView(n));
					v.x = bx;
					v.y = by;
					v.width = bw;
					v.height = bh;
					v.contentWidth = bw + mx;
					v.contentHeight = bh + my;
					v.offsetX = n.scrollX - scrollStart(n, true);
					v.offsetY = n.scrollY;
					v.scrollsX = mx > 0;
					v.scrollsY = my > 0;
					v.bars = barSize(n) > 0;
					v.layer = layer;
					v.covered = covered;
					v.parent = parent;
					v.pass = ui.scrollPass;
					out.push(v);
					parent = v;
				}
				ox += n.scrollX;
				oy += n.scrollY;
			}
			x0 = Math.max(x0, bx);
			y0 = Math.max(y0, by);
			x1 = Math.min(x1, bx + bw);
			y1 = Math.min(y1, by + bh);
			if (x1 <= x0 || y1 <= y0) return;
		}
		var order = n.paintOrder();
		if (order != null) {
			for (c in order)
				collect(ui, c, ox, oy, x0, y0, x1, y1, layer, covered, parent, out);
			return;
		}
		for (c in n.children)
			if (c.style.position == Relative) collect(ui, c, ox, oy, x0, y0, x1, y1, layer, covered, parent, out);
		for (c in n.children)
			if (c.style.position != Relative) collect(ui, c, ox, oy, x0, y0, x1, y1, layer, covered, parent, out);
	}

	// whether a platform's drag at x, y moving the content by dx, dy (the
	// scroll's way) is n's to scroll (Ui.nativeBegins): none while a
	// gesture of the tree has a pointer, or a node there follows the
	// pointer's moves (a slider: as scrollsAt); else the nearest scroller
	// around the point that can move that way, or, at the ends, the
	// innermost that scrolls on that axis (its edge stretching)
	static function begins(ui:Ui, n:Node, x:Float, y:Float, dx:Float, dy:Float):Bool {
		if (ui.gestureHeld()) return false;
		var t = ui.hit(x, y), p = t;
		while (p != null) {
			if (p.onPointerMove != null) return false;
			p = p.parent;
		}
		var first:Null<Node> = null, alongX = Math.abs(dx) > Math.abs(dy);
		p = t;
		while (p != null) {
			if (p.style.overflow == Scroll) {
				if (canScroll(p, dx, true) || canScroll(p, dy, false)) return p == n;
				var v = ui.scrollKept.get(p);
				if (first == null && v != null && (alongX ? v.scrollsX : v.scrollsY)) first = p;
			}
			p = p.parent;
		}
		return first == n;
	}

	// whether a platform's scroll view takes drags at n: a scroller around
	// it listed by the last Ui.scrollViews, not under a popup (elsewhere a
	// finger's drag is TouchScroll's: its Wheel events, its glide)
	static function nativeAt(ui:Ui, n:Null<Node>):Bool {
		while (n != null) {
			if (n.style.overflow == Scroll) {
				var v = ui.scrollKept.get(n);
				if (v != null && v.pass == ui.scrollPass && !v.covered) return true;
			}
			n = n.parent;
		}
		return false;
	}

	// a platform's scroll view moved n to its offsets x, y from its start
	// (Ui.nativeScrolled: past the ends while its edge stretches, as Safari's
	// scrollTop)
	static function moved(ui:ScrollHost, n:Node, x:Float, y:Float) {
		stopGlide(ui, n);
		x += scrollStart(n, true);
		if (x == n.scrollX && y == n.scrollY) return;
		n.scrollX = x;
		n.scrollY = y;
		if (n.onScroll != null) n.onScroll();
		ui.requestFrame();
	}

	static function setScroll(ui:ScrollHost, n:Node, x:Bool, v:Float) {
		v = clampTo(n, x, v);
		if (v == (x ? n.scrollX : n.scrollY)) return;
		if (x) n.scrollX = v; else n.scrollY = v;
		if (n.onScroll != null) n.onScroll();
		ui.requestFrame();
	}
}
