package helder.ui.platform.web;

import hxmc.unsafe.*;

// A UiWindow's scrollers driven by the browser's own scrolling
// (Ui.nativeScroll): one clear element per scroller that overflows
// (Ui.scrollViews), overflow auto over a spacer of the content's size, in a
// layer over the canvas, nested as the scrollers are (so the browser moves
// the inner ones with the outer and chains a scroll at an end), made by
// src/helder/ui/imports.mjs. Its touch pans, wheels, trackpad momentum,
// and overscroll are the browser's; its scrolls come back
// (Ui.nativeScrolled), the program's scrolls go to it. Their scrollbars are
// hidden and helder draws its own, so that they are in order with what the
// tree draws (the page draws an element over the canvas, over everything);
// the popups over one are cut out of it (ScrollView.covers: clip-path), so
// that a wheel or a touch there is the popup's, and under a modal popup it
// takes no input at all. The pointer's events over them reach the canvas's
// listeners (helder.os's imports), and a touch's drag the tree takes (a
// node following the pointer: Ui.scrollsAt) is not panned. Kept in step after each frame:
// what changed sent as JSON, the scrolls polled.
@:hxmc.unsafe(gc)
class Scroll {
	final ui:Ui;
	final canvas:Int;
	// what each view was given: its parent, box, content, axes, bars, covered; its offsets
	final sent = new Map<Int, Array<Float>>();
	final views = new Map<Int, Node>();
	// (the popups' rectangles each was given, as their JSON)
	final sentCovers = new Map<Int, String>();
	final seen = new Map<Int, Bool>();
	// (the views by their scroller, at the last update: web.Layers places a scroller's content in its own)
	final byNode = new Map<Node, ScrollView>();

	public function new(canvas:Int, ui:Ui) {
		this.ui = ui;
		this.canvas = canvas;
		// (the scrollbars helder's, drawn in order with what the tree draws: the page's would be over all of it;
		// but a view holding its scroller's content as a layer of the page's, stacked, whose bars overlay: the page's)
		ui.nativeBars = false;
		ui.barsOf = n -> pageBars.exists(n);
	}

	// (the scrollers whose views show the page's own scrollbars)
	final pageBars = new Map<Node, Bool>();

	// (UiWindow: after each frame)
	public function update() {
		var list = ui.nativeScroll ? ui.scrollViews() : [];
		var buf = new StringBuf(), any = false;
		buf.add('{"w":');
		buf.add(num(ui.width));
		buf.add(',"v":[');
		seen.clear();
		byNode.clear();
		for (s in list) {
			seen.set(s.id, true);
			byNode.set(s.node, s);
			views.set(s.id, s.node);
			var p = s.parent, last = sent.get(s.id);
			// (inside its parent's content: where it is, its parent scrolled to 0)
			var x = p == null ? s.x : s.x - p.x + p.offsetX, y = p == null ? s.y : s.y - p.y + p.offsetY;
			var now:Array<Float> = [p == null ? 0 : p.id, x, y, s.width, s.height, s.contentWidth, s.contentHeight, (s.scrollsX ? 1 : 0) | (s.scrollsY ? 2 : 0),
				s.bars ? 1 : 0, s.covered ? 1 : 0];
			var covers = "[" + [for (c in s.covers) num(c)].join(",") + "]", coversChanged = sentCovers.get(s.id) != covers;
			var fresh = last == null, moved = fresh || Math.abs(s.offsetX - last[10]) > 0.01 || Math.abs(s.offsetY - last[11]) > 0.01, changed = fresh;
			if (!fresh)
				for (i in 0...now.length)
					if (now[i] != last[i]) changed = true;
			if (!changed && !moved && !coversChanged) continue;
			now.push(s.offsetX);
			now.push(s.offsetY);
			sent.set(s.id, now);
			if (any) buf.add(',');
			any = true;
			buf.add('{"i":');
			buf.add(s.id);
			if (changed) {
				buf.add(',"g":[');
				for (i in 0...10) {
					if (i > 0) buf.add(',');
					buf.add(num(now[i]));
				}
				buf.add(']');
			}
			if (coversChanged) {
				sentCovers.set(s.id, covers);
				buf.add(',"c":');
				buf.add(covers);
			}
			if (moved) {
				buf.add(',"o":[');
				buf.add(num(s.offsetX));
				buf.add(',');
				buf.add(num(s.offsetY));
				buf.add(']');
			}
			buf.add('}');
		}
		buf.add('],"r":[');
		var first = true;
		for (id in [for (id in sent.keys()) id])
			if (!seen.exists(id)) {
				sent.remove(id);
				sentCovers.remove(id);
				var n = views.get(id);
				if (n != null) pageBars.remove(n);
				views.remove(id);
				if (!first) buf.add(',');
				first = false;
				any = true;
				buf.add(id);
			}
		buf.add(']}');
		if (any) Arena.scoped(a -> Scrolls.scroll_update(canvas, a.cstring(buf.toString())));
	}

	// a scroller's view (null: none at the last update)
	public function viewOf(n:Node):Null<ScrollView>
		return byNode.get(n);

	// the views' scrolls since the last frame, taken
	public function poll()
		Arena.scoped(a -> {
			var p:Ptr<Int32> = a.alloc(12);
			while (Scrolls.scroll_event(p) != 0) {
				// (-id: whether that view shows the page's scrollbars)
				if (p[0] < 0) {
					var n = views.get(-p[0]);
					if (n != null) {
						if (p[1] != 0) pageBars.set(n, true) else pageBars.remove(n);
						ui.requestFrame();
					}
					continue;
				}
				var id = p[0], n = views.get(id), last = sent.get(id);
				if (n == null) continue;
				var x = p[1] / 256, y = p[2] / 256;
				if (last != null) {
					last[10] = x;
					last[11] = y;
				}
				ui.nativeScrolled(n, x, y);
			}
		});

	public function dispose() {
		ui.nativeBars = false;
		ui.barsOf = null;
		ui.nativeScroll = false;
		update();
	}

	static function num(v:Float):String {
		var r = Math.round(v * 100) / 100;
		return r == Math.ffloor(r) ? Std.string(Std.int(r)) : Std.string(r);
	}
}
