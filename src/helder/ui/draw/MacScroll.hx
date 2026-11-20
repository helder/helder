package helder.ui.draw;

import helder.os.objc.*;
import hxmc.unsafe.*;

// A UiWindow's scrollers driven by NSScrollViews on macOS (Ui.nativeScroll):
// one per scroller that overflows (Ui.scrollViews), clear (no background,
// a flipped document view of the content's size), over the window's view,
// nested as the scrollers are: a trackpad's scroll and its momentum, or a
// wheel's, under the pointer goes to the innermost (Window.nativeScroll,
// latched for the gesture and its momentum; AppKit chains what it cannot
// take outwards), so macOS's own elasticity (scrollX/scrollY past the ends
// while it stretches), smooth wheel scrolling and overlay scrollers (but
// where scrollbar-width is none) are the app's. Its offsets come back (its
// clip view's bounds changing: Ui.nativeScrolled), the program's scrolls go
// to it. A scroll with Control (a pinch's zoom) and one elsewhere stay the
// program's Scroll events. Kept in step after each frame.
@:hxmc.unsafe(gc)
class MacScroll {
	static var docClass = Ptr.nil();
	static var observerClass = Ptr.nil();
	static var rect:Ptr<CGRect> = Ptr.nil();
	static var point:Ptr<CGPoint> = Ptr.nil();
	// (each clip view's: its owner and node, by its address)
	static final owners = new Map<Int, {s:MacScroll, n:Node}>();

	final ui:Ui;
	final view:Ptr;
	final content:Ptr;
	final observer:Ptr;
	final views = new Map<Node, Ptr>();
	final clips = new Map<Node, Ptr>();
	// what each was given: its parent's node id, frame, content size, bars; its offsets (points)
	final sent = new Map<Node, Array<Float>>();
	final parents = new Map<Node, Null<Node>>();
	final seen = new Map<Node, Bool>();
	// the scroll view a gesture (and its momentum) goes to
	var latched = Ptr.nil();

	public function new(window:helder.os.Window, ui:Ui) {
		this.ui = ui;
		view = window.surface.handle;
		content = Msg.id(Msg.id(view, ObjC.sel("window")), ObjC.sel("contentView"));
		if (docClass.isNull()) classes();
		observer = Msg.id(Msg.id(observerClass, ObjC.sel("alloc")), ObjC.sel("init"));
		ui.nativeBars = true;
		window.nativeScroll = take;
	}

	static function classes() {
		rect = LibC.malloc(32);
		point = LibC.malloc(16);
		var d = ObjC.cls("HxmcScrollDocument"), fresh = d.isNull();
		if (fresh) d = Runtime.objc_allocateClassPair(ObjC.cls("NSView"), Mem.cstr("HxmcScrollDocument"), 0);
		Runtime.class_replaceMethod(d, ObjC.sel("isFlipped"), Callback.addr(yes), Mem.cstr("B@:"));
		if (fresh) Runtime.objc_registerClassPair(d);
		docClass = d;
		var o = ObjC.cls("HxmcScrollObserver");
		fresh = o.isNull();
		if (fresh) o = Runtime.objc_allocateClassPair(ObjC.cls("NSObject"), Mem.cstr("HxmcScrollObserver"), 0);
		Runtime.class_replaceMethod(o, ObjC.sel("hxmcScrolled:"), Callback.addr(scrolled), Mem.cstr("v@:@"));
		if (fresh) Runtime.objc_registerClassPair(o);
		observerClass = o;
	}

	@:hxmc.callback static function yes(self:Ptr, cmd:Ptr):Int
		return 1;

	// (UiWindow: after each frame)
	public function update() {
		var list = ui.nativeScroll ? ui.scrollViews() : [];
		seen.clear();
		var vb = Msg.rect(view, ObjC.sel("bounds")), k = ui.width > 0 ? vb.size.width / ui.width : 1.0, flipped = Msg.b(view, ObjC.sel("isFlipped"));
		for (s in list) {
			var n = s.node, v = views.get(n), last = sent.get(n);
			seen.set(n, true);
			var p = s.parent == null ? null : s.parent.node;
			if (v == null || parents.get(n) != p) {
				if (v != null) drop(n);
				v = make(n, p);
				last = [-1, -1, -1, -1, -1, -1, -1, -1e9, -1e9];
				sent.set(n, last);
			}
			// (inside its parent's document, flipped: where it is, its parent scrolled to 0; else the window's view's
			// box, in the content view)
			var x = 0.0, y = 0.0;
			if (s.parent != null) {
				x = (s.x - s.parent.x + s.parent.offsetX) * k;
				y = (s.y - s.parent.y + s.parent.offsetY) * k;
			}
			var w = s.width * k, h = s.height * k;
			if (s.parent == null) {
				rect.value.origin.x = s.x * k;
				rect.value.origin.y = flipped ? s.y * k : vb.size.height - (s.y + s.height) * k;
				rect.value.size.width = w;
				rect.value.size.height = h;
				var r = Msg.rectRectPtr(view, ObjC.sel("convertRect:toView:"), rect.value, content);
				x = r.origin.x;
				y = r.origin.y;
			}
			if (x != last[0] || y != last[1] || w != last[2] || h != last[3]) {
				rect.value.origin.x = last[0] = x;
				rect.value.origin.y = last[1] = y;
				rect.value.size.width = last[2] = w;
				rect.value.size.height = last[3] = h;
				Msg.vRect(v, ObjC.sel("setFrame:"), rect.value);
			}
			var cw = s.contentWidth * k, ch = s.contentHeight * k;
			if (cw != last[4] || ch != last[5]) {
				rect.value.origin.x = rect.value.origin.y = 0;
				rect.value.size.width = last[4] = cw;
				rect.value.size.height = last[5] = ch;
				Msg.vRect(Msg.id(v, ObjC.sel("documentView")), ObjC.sel("setFrame:"), rect.value);
			}
			var bars = (s.bars && s.scrollsX ? 1 : 0) | (s.bars && s.scrollsY ? 2 : 0);
			if (bars != last[6]) {
				last[6] = bars;
				Msg.vBool(v, ObjC.sel("setHasHorizontalScroller:"), bars & 1 != 0);
				Msg.vBool(v, ObjC.sel("setHasVerticalScroller:"), bars & 2 != 0);
			}
			// (the program's scroll: what the view last said differs)
			if (Math.abs(s.offsetX - last[7]) > 0.01 || Math.abs(s.offsetY - last[8]) > 0.01) {
				last[7] = s.offsetX;
				last[8] = s.offsetY;
				var clip = clips.get(n);
				point.value.x = s.offsetX * k;
				point.value.y = s.offsetY * k;
				Msg.vPoint(clip, ObjC.sel("scrollToPoint:"), point.value);
				Msg.vPtr(v, ObjC.sel("reflectScrolledClipView:"), clip);
			}
		}
		// (the inner ones first: a parent's removal takes its children's views with it)
		for (n in [for (n in views.keys()) n])
			if (!seen.exists(n)) drop(n);
	}

	function make(n:Node, parent:Null<Node>):Ptr {
		rect.value.origin.x = rect.value.origin.y = 0;
		rect.value.size.width = rect.value.size.height = 1;
		var v = Msg.idRect(Msg.id(ObjC.cls("NSScrollView"), ObjC.sel("alloc")), ObjC.sel("initWithFrame:"), rect.value);
		Msg.vBool(v, ObjC.sel("setDrawsBackground:"), false);
		Msg.vBool(v, ObjC.sel("setAutohidesScrollers:"), true);
		var clip = Msg.id(v, ObjC.sel("contentView"));
		Msg.vBool(clip, ObjC.sel("setDrawsBackground:"), false);
		var doc = Msg.idRect(Msg.id(docClass, ObjC.sel("alloc")), ObjC.sel("initWithFrame:"), rect.value);
		Msg.vPtr(v, ObjC.sel("setDocumentView:"), doc);
		ObjC.release(doc);
		Msg.vBool(clip, ObjC.sel("setPostsBoundsChangedNotifications:"), true);
		var center = Msg.id(ObjC.cls("NSNotificationCenter"), ObjC.sel("defaultCenter"));
		var name = ObjC.str("NSViewBoundsDidChangeNotification");
		Msg.vPtrPtrPtrPtr(center, ObjC.sel("addObserver:selector:name:object:"), observer, ObjC.sel("hxmcScrolled:"), name, clip);
		ObjC.release(name);
		var into = parent == null ? null : views.get(parent);
		if (into != null) Msg.vPtr(Msg.id(into, ObjC.sel("documentView")), ObjC.sel("addSubview:"), v) else Msg.vPtr(content, ObjC.sel("addSubview:"), v);
		views.set(n, v);
		clips.set(n, clip);
		parents.set(n, parent);
		owners.set(key(clip), {s: this, n: n});
		return v;
	}

	function drop(n:Node) {
		var v = views.get(n), clip = clips.get(n);
		if (v == null) return;
		if (latched == v) latched = Ptr.nil();
		views.remove(n);
		clips.remove(n);
		sent.remove(n);
		parents.remove(n);
		owners.remove(key(clip));
		var center = Msg.id(ObjC.cls("NSNotificationCenter"), ObjC.sel("defaultCenter"));
		Msg.vPtrPtrPtr(center, ObjC.sel("removeObserver:name:object:"), observer, Ptr.nil(), clip);
		Msg.v(v, ObjC.sel("removeFromSuperview"));
		ObjC.release(v);
	}

	public function dispose() {
		for (n in [for (n in views.keys()) n])
			drop(n);
		ui.nativeBars = false;
		ObjC.release(observer);
	}

	// (Window.nativeScroll: x, y in pixels) a scroll at the start of a
	// gesture, or a wheel's, to the innermost scroll view under it; the rest
	// of the gesture and its momentum to the same
	function take(ev:Ptr, x:Int, y:Int):Bool {
		if (!ui.nativeScroll) return false;
		// (NSEventPhaseBegan 1, MayBegin 32; Ended 8, Cancelled 16: the momentum's the same)
		var phase = Msg.i(ev, ObjC.sel("phase")).toInt(), momentum = Msg.i(ev, ObjC.sel("momentumPhase")).toInt();
		var starts = phase & (1 | 32) != 0 || phase == 0 && momentum == 0;
		if (!starts) {
			if (latched.isNull()) return false;
			Msg.vPtr(latched, ObjC.sel("scrollWheel:"), ev);
			// (its momentum over: the next gesture finds its own)
			if (momentum & (8 | 16) != 0) latched = Ptr.nil();
			return true;
		}
		// (Control: a pinch's zoom, the program's)
		if (Msg.i(ev, ObjC.sel("modifierFlags")).toInt() & (1 << 18) != 0) return false;
		var k = Msg.f(Msg.id(view, ObjC.sel("window")), ObjC.sel("backingScaleFactor")), vb = Msg.rect(view, ObjC.sel("bounds"));
		var u = ui.width > 0 ? vb.size.width / ui.width : 1.0;
		var s = ui.scrollViewAt(x / k / u, y / k / u);
		var v = s == null ? Ptr.nil() : views.get(s.node);
		latched = v;
		if (v.isNull()) return false;
		Msg.vPtr(v, ObjC.sel("scrollWheel:"), ev);
		return true;
	}

	static inline function key(v:Ptr):Int {
		var a = v.toI64();
		return (a >> 32).toInt() ^ a.toInt();
	}

	// (a clip view's bounds moved: its offsets the scroller's, points)
	@:hxmc.callback static function scrolled(self:Ptr, cmd:Ptr, note:Ptr):Void {
		var clip = Msg.id(note, ObjC.sel("object")), o = owners.get(key(clip));
		if (o == null) return;
		var s = o.s, vb = Msg.rect(s.view, ObjC.sel("bounds")), k = s.ui.width > 0 ? vb.size.width / s.ui.width : 1.0;
		var b = Msg.rect(clip, ObjC.sel("bounds")), last = s.sent.get(o.n);
		var x = b.origin.x / k, y = b.origin.y / k;
		if (last != null) {
			last[7] = x;
			last[8] = y;
		}
		s.ui.nativeScrolled(o.n, x, y);
	}
}
