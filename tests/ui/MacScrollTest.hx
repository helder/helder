import helder.os.objc.*;
import helder.ui.*;
import helder.ui.draw.UiWindow;
import hxmc.unsafe.*;

// macOS's NSScrollViews driving the scrollers (helder.ui.draw.MacScroll), in
// process: a page scrolling down with a row of cards scrolling sideways at
// its top; scroll events made by Core Graphics (precise pixels, as a
// trackpad's) handed to the window as its event loop does
// (Window.nativeScroll): the page's view scrolls and the page follows; over
// the row the row does; the program's scroll moves the view; a scroll with
// Control stays the program's; scrolling="helder" takes the views away.
//   MacScrollTest
@:hxmc.unsafe(gc)
class MacScrollTest {
	static var failed = 0;
	static var checks = 0;
	static final at:Ptr<CGPoint> = LibC.malloc(16);

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('MacScrollTest: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	// the NSScrollViews under a view
	static function scrollViews(v:Ptr, out:Array<Ptr>):Array<Ptr> {
		var subs = Msg.id(v, ObjC.sel("subviews"));
		for (i in 0...Msg.i(subs, ObjC.sel("count")).toInt()) {
			var s = Msg.idInt(subs, ObjC.sel("objectAtIndex:"), i);
			if (Msg.bPtr(s, ObjC.sel("isKindOfClass:"), ObjC.cls("NSScrollView"))) out.push(s);
			scrollViews(s, out);
		}
		return out;
	}

	// a trackpad's scroll of dx, dy pixels (the content's way: negative
	// scrolls down) at x, y (points): its began, changed and ended events
	// (CGScrollPhase 1, 2, 4), as NSEvents, to the window: whether taken
	static function scroll(w:UiWindow, x:Float, y:Float, dx:Int, dy:Int, control = false):Bool {
		var taken = true;
		for (phase in [1, 2, 4]) {
			var d = phase == 2;
			var ev = CGScroll.CGEventCreateScrollWheelEvent2(Ptr.nil(), 0, 2, d ? dy : 0, d ? dx : 0, 0);
			CGScroll.CGEventSetIntegerValueField(ev, 99, phase); // (kCGScrollWheelEventScrollPhase)
			if (control) CGScroll.CGEventSetFlags(ev, 1 << 18);
			var ns = Msg.idPtr(ObjC.cls("NSEvent"), ObjC.sel("eventWithCGEvent:"), ev);
			var k = w.window.scale;
			if (w.window.nativeScroll == null || !w.window.nativeScroll(ns, Math.round(x * k), Math.round(y * k))) taken = false;
			CGScroll.CFRelease(ev);
		}
		return taken;
	}

	static function main() {
		var w = new UiWindow("MacScrollTest", 400, 300);
		var page = new Node("page"), row = new Node("row");
		page.style.set({width: 400, height: 300, overflow: Scroll, background: Color.rgb(0xffffff)});
		row.style.set({height: 80, shrink: 0, overflow: Scroll, direction: Row});
		for (i in 0...5) {
			var c = new Node("card" + i);
			c.style.set({width: 120, height: 80, shrink: 0});
			row.append(c);
		}
		page.append(row);
		for (i in 0...20) {
			var r = new Node("item" + i);
			r.style.set({height: 40, shrink: 0});
			page.append(r);
		}
		w.root.append(page);
		var content = Msg.id(Msg.id(w.window.surface.handle, ObjC.sel("window")), ObjC.sel("contentView"));
		var step = 0, frames = 0;
		w.onFrame = () -> {
			frames++;
			switch step {
				case 0:
					var views = scrollViews(content, []);
					check("two scroll views, the row's inside the page's", views.length == 2, "" + views.length);
					check("over the row, sideways, the row's", scroll(w, 200, 40, -150, 0));
					step = 1;
				case 1:
					check("the row scrolled by its view", Math.abs(row.scrollX - 150) < 1, "" + row.scrollX);
					check("over the page, down, the page's", scroll(w, 200, 200, 0, -120));
					step = 2;
				case 2:
					check("the page scrolled by its view", Math.abs(page.scrollY - 120) < 1 && row.scrollX > 0, page.scrollY + " " + row.scrollX);
					w.ui.scrollTo(page, 0, 300);
					step = 3;
				case 3:
					var views = scrollViews(content, []), y = -1.0;
					for (v in views)
						if (Msg.b(v, ObjC.sel("hasVerticalScroller")))
							y = Msg.rect(Msg.id(v, ObjC.sel("contentView")), ObjC.sel("bounds")).origin.y;
					check("the program's scroll moves the view", Math.abs(y - 300) < 1 && page.scrollY == 300, y + " " + page.scrollY);
					check("a scroll with Control the program's", !scroll(w, 200, 200, 0, -40, true));
					w.nativeScroll(false);
					step = 4;
				case 4:
					check("scrolling=\"helder\": no scroll view, the scroll the program's", scrollViews(content, []).length == 0 && !scroll(w, 200, 200, 0, -40));
					step = 5;
					w.close();
			}
			if (frames > 50) w.close();
			w.ui.requestFrame();
		};
		UiWindow.run();
		Sys.println('MacScrollTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed failed'));
		Sys.exit(failed == 0 && checks >= 9 ? 0 : 1);
	}
}

@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics") extern class CGScroll {
	// (units: 0 pixels; the wheels: vertical, horizontal)
	static function CGEventCreateScrollWheelEvent2(source:Ptr, units:Int, wheelCount:Int, wheel1:Int, wheel2:Int, wheel3:Int):Ptr;
	static function CGEventSetFlags(ev:Ptr, flags:Int64):Void;
	static function CGEventSetIntegerValueField(ev:Ptr, field:Int, value:Int64):Void;
	static function CFRelease(o:Ptr):Void;
}
