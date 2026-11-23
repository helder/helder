package helder.ui.draw;

import helder.os.objc.*;
import hxmc.unsafe.*;

// A UiWindow's scrollers driven by UIScrollViews on iOS (Ui.nativeScroll),
// as WebKit's: one per scroller that overflows (Ui.scrollViews), of a class
// made here (HxmcScrollView), over the window's view at the scroller's box,
// clear and taking no touch itself; its pan recogniser is the view's (the
// touches the view's, cancelled to the tree once it pans), and begins only
// for the scroller Ui.nativeBegins gives the drag. Its offsets come back
// (scrollViewDidScroll: Ui.nativeScrolled, past the ends while it bounces);
// the program's scrolls go to it. So iOS's own deceleration, bounce,
// indicators (but where scrollbar-width is none) and status bar tap (the
// first scroller that scrolls down) are the app's. A touch stops one gliding
// (Ui.nativeHalt). Kept in step after each frame. The views are the main
// thread's (helder.os.OsThread); their offsets go to the window's
// compositor at once as they move, so that a glide and a bounce keep the
// display's pace while the program is busy, and to the program at its
// next call (OsThread.soon); a drag's start is asked of the program
// (OsThread.hold).
@:hxmc.unsafe(gc)
class IosScroll {
	static var viewClass = Ptr.nil();
	static var delegate = Ptr.nil();
	static var rect:Ptr<CGRect> = Ptr.nil();
	static var size:Ptr<CGSize> = Ptr.nil();
	static var point:Ptr<CGPoint> = Ptr.nil();
	// (each scroll view's: its owner and node, by its address)
	static final owners = new Map<Int, {s:IosScroll, n:Node}>();

	final ui:Ui;
	final view:Ptr;
	final views = new Map<Node, Ptr>();
	// what each was given (its frame, content size, offset: UIKit's points) and whether it shows its bars, scrolls to top
	final sent = new Map<Node, Array<Float>>();
	final seen = new Map<Node, Bool>();
	// (UIKit's points a UI pixel, as of the last update)
	var k = 1.0;
	#if (hxmc.target != "wasm32-wasi")
	// the window's compositor (null: none), told the offsets as they move
	public var compositor:Null<Compositor> = null;
	#end

	public function new(window:helder.os.Window, ui:Ui) {
		this.ui = ui;
		view = window.surface.handle;
		if (viewClass.isNull()) helder.os.OsThread.run(classes);
		ui.nativeBars = true;
		ui.nativeHalt = halt;
	}

	static function classes() {
		rect = LibC.malloc(32);
		size = LibC.malloc(16);
		point = LibC.malloc(16);
		var c = ObjC.cls("HxmcScrollView"), fresh = c.isNull();
		if (fresh) c = Runtime.objc_allocateClassPair(ObjC.cls("UIScrollView"), Mem.cstr("HxmcScrollView"), 0);
		Runtime.class_replaceMethod(c, ObjC.sel("gestureRecognizerShouldBegin:"), Callback.addr(shouldBegin), Mem.cstr("B@:@"));
		if (fresh) Runtime.objc_registerClassPair(c);
		viewClass = c;
		var d = ObjC.cls("HxmcScrollDelegate");
		fresh = d.isNull();
		if (fresh) d = Runtime.objc_allocateClassPair(ObjC.cls("NSObject"), Mem.cstr("HxmcScrollDelegate"), 0);
		Runtime.class_replaceMethod(d, ObjC.sel("scrollViewDidScroll:"), Callback.addr(didScroll), Mem.cstr("v@:@"));
		if (fresh) {
			var p = Runtime.objc_getProtocol(Mem.cstr("UIScrollViewDelegate"));
			if (!p.isNull()) Runtime.class_addProtocol(d, p);
			Runtime.objc_registerClassPair(d);
		}
		delegate = Msg.id(Msg.id(d, ObjC.sel("alloc")), ObjC.sel("init"));
	}

	// (UIKit's points a UI pixel)
	function points():Float {
		var b = Msg.rect(view, ObjC.sel("bounds"));
		return ui.width > 0 ? b.size.width / ui.width : 1.0;
	}

	// (UiWindow: after each frame)
	public function update()
		helder.os.OsThread.run(updateNow);

	function updateNow() {
		if (!ui.nativeScroll) {
			clear();
			return;
		}
		var list = ui.scrollViews(), top = true;
		k = points();
		seen.clear();
		for (s in list) {
			var n = s.node, v = views.get(n), last = sent.get(n);
			seen.set(n, true);
			if (v == null) {
				v = make(n);
				last = [-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 0];
				sent.set(n, last);
			}
			var x = s.x * k, y = s.y * k, w = s.width * k, h = s.height * k;
			if (x != last[0] || y != last[1] || w != last[2] || h != last[3]) {
				rect.value.origin.x = last[0] = x;
				rect.value.origin.y = last[1] = y;
				rect.value.size.width = last[2] = w;
				rect.value.size.height = last[3] = h;
				Msg.vRect(v, ObjC.sel("setFrame:"), rect.value);
			}
			var cw = s.contentWidth * k, ch = s.contentHeight * k;
			if (cw != last[4] || ch != last[5]) {
				size.value.width = last[4] = cw;
				size.value.height = last[5] = ch;
				Msg.vSize(v, ObjC.sel("setContentSize:"), size.value);
			}
			// (the program's scroll: what the view last said differs)
			var ox = s.offsetX * k, oy = s.offsetY * k;
			if (Math.abs(ox - last[6]) > 0.01 || Math.abs(oy - last[7]) > 0.01) {
				point.value.x = last[6] = ox;
				point.value.y = last[7] = oy;
				Msg.vPointBool(v, ObjC.sel("setContentOffset:animated:"), point.value, false);
			}
			// (where its offsets start: Scrolling.moved's, a right-to-left one's negative)
			last[10] = @:privateAccess Scrolling.scrollStart(n, true);
			var bars = s.bars ? 1 : 0;
			if (bars != last[8]) {
				last[8] = bars;
				Msg.vBool(v, ObjC.sel("setShowsVerticalScrollIndicator:"), s.bars);
				Msg.vBool(v, ObjC.sel("setShowsHorizontalScrollIndicator:"), s.bars);
			}
			// (the status bar's tap: one scroll view takes it, the first that scrolls down outside a popup)
			var tops = top && s.scrollsY && !s.layer;
			if (tops) top = false;
			if ((tops ? 1 : 0) != last[9]) {
				last[9] = tops ? 1 : 0;
				Msg.vBool(v, ObjC.sel("setScrollsToTop:"), tops);
			}
		}
		for (n in [for (n in views.keys()) n])
			if (!seen.exists(n)) drop(n);
	}

	function make(n:Node):Ptr {
		rect.value.origin.x = rect.value.origin.y = 0;
		rect.value.size.width = rect.value.size.height = 1;
		var v = Msg.idRect(Msg.id(viewClass, ObjC.sel("alloc")), ObjC.sel("initWithFrame:"), rect.value);
		Msg.vBool(v, ObjC.sel("setUserInteractionEnabled:"), false);
		// (UIScrollViewContentInsetAdjustmentNever: the safe area is the layout's)
		Msg.vInt(v, ObjC.sel("setContentInsetAdjustmentBehavior:"), 2);
		Msg.vBool(v, ObjC.sel("setScrollsToTop:"), false);
		Msg.vPtr(v, ObjC.sel("setDelegate:"), delegate);
		Msg.vPtr(view, ObjC.sel("addSubview:"), v);
		Msg.vPtr(view, ObjC.sel("addGestureRecognizer:"), Msg.id(v, ObjC.sel("panGestureRecognizer")));
		views.set(n, v);
		owners.set(key(v), {s: this, n: n});
		return v;
	}

	function drop(n:Node) {
		var v = views.get(n);
		if (v == null) return;
		views.remove(n);
		sent.remove(n);
		owners.remove(key(v));
		Msg.vPtr(v, ObjC.sel("setDelegate:"), Ptr.nil());
		Msg.vPtr(view, ObjC.sel("removeGestureRecognizer:"), Msg.id(v, ObjC.sel("panGestureRecognizer")));
		Msg.v(v, ObjC.sel("removeFromSuperview"));
		Runtime.objc_release(v);
	}

	function clear()
		for (n in [for (n in views.keys()) n])
			drop(n);

	// (Ui.nativeHalt: the views gliding stopped where they are)
	function halt():Bool
		return helder.os.OsThread.get(haltNow);

	function haltNow():Bool {
		var any = false;
		for (v in views)
			if (Msg.b(v, ObjC.sel("isDecelerating"))) {
				var o = Msg.point(v, ObjC.sel("contentOffset"));
				point.value.x = o.x;
				point.value.y = o.y;
				Msg.vPointBool(v, ObjC.sel("setContentOffset:animated:"), point.value, false);
				any = true;
			}
		return any;
	}

	public function dispose() {
		helder.os.OsThread.run(clear);
		ui.nativeHalt = null;
		ui.nativeBars = false;
	}

	static inline function key(v:Ptr):Int {
		var a = v.toI64();
		return (a >> 32).toInt() ^ a.toInt();
	}

	// (its pan: begins for the drag Ui.nativeBegins gives its scroller; the content's scroll the finger's other way)
	@:hxmc.callback static function shouldBegin(self:Ptr, cmd:Ptr, g:Ptr):Int {
		var o = owners.get(key(self));
		if (o == null || g != Msg.id(self, ObjC.sel("panGestureRecognizer"))) return 1;
		var s = o.s, k = s.k;
		var at = Msg.pointPtr(g, ObjC.sel("locationInView:"), s.view), d = Msg.pointPtr(g, ObjC.sel("velocityInView:"), s.view);
		if (d.x == 0 && d.y == 0) d = Msg.pointPtr(g, ObjC.sel("translationInView:"), s.view);
		var x = at.x / k, y = at.y / k, dx = -d.x, dy = -d.y;
		return helder.os.OsThread.hold(() -> s.ui.nativeBegins(o.n, x, y, dx, dy)) ? 1 : 0;
	}

	@:hxmc.callback static function didScroll(self:Ptr, cmd:Ptr, v:Ptr):Void {
		var o = owners.get(key(v));
		if (o == null) return;
		var s = o.s, k = s.k, p = Msg.point(v, ObjC.sel("contentOffset")), last = s.sent.get(o.n), n = o.n;
		if (last != null) {
			last[6] = p.x;
			last[7] = p.y;
		}
		var x = p.x / k, y = p.y / k;
		#if (hxmc.target != "wasm32-wasi")
		if (s.compositor != null && last != null) s.compositor.nativeScrolled(n, x + last[10], y);
		#end
		helder.os.OsThread.soon(() -> s.ui.nativeScrolled(n, x, y));
	}
}
