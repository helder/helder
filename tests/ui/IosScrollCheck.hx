import haxe.Timer;
import helder.os.*;
import helder.ui.*;
import helder.ui.draw.*;
import helder.ui.controls.TextField;

// The program on its own thread on iOS (IosCheck scroll: tests/gfx/ios.sh
// launches the app again with it): a list scrolled by its UIScrollView,
// UIKit animating the offset while the program blocks for 500 ms. Its
// offsets reach the compositor on the main thread (helder.ui.platform.apple.IosScroll), whose frames
// keep coming meanwhile at them, and the program has the view's offset
// afterwards; then text typed into a native field (a UITextField:
// UIKeyInput's insertText:) reaches its node.
@:hxmc.unsafe(gc)
class IosScrollCheck {
	static var failed = 0;

	static function check(what:String, ok:Bool, detail:String) {
		if (!ok) failed++;
		Sys.println('IosScrollCheck: ${ok ? "ok" : "FAIL"}: $what' + (detail == "" ? "" : ' ($detail)'));
	}

	public static function run() {
		var w = new helder.ui.UiWindow({title: "IosScrollCheck", width: 0, height: 0});
		var field = new TextField();
		field.host = Native;
		field.style.set({height: 40, flexShrink: 0, margin: 60});
		w.root.append(field);
		var list = new Node();
		list.style.set({overflow: Scroll, flexGrow: 1, rowGap: 2, padding: 4, background: 0xFFFFFFFF});
		for (i in 0...200) {
			var row = new Node();
			row.style.set({height: 40, flexShrink: 0, background: i % 2 == 0 ? 0xFFEFF6FF : 0xFFFFE0E0});
			row.append(new TextNode("Row " + i));
			list.append(row);
		}
		w.root.append(list);
		var c = w.compositor;
		if (c == null) {
			check("a compositor (the program on its own thread)", false, "none");
			Sys.exit(1);
		}
		var lock = new sys.thread.Mutex(), presents:Array<Float> = [], offsets:Array<Float> = [];
		c.onFrame = t -> {
			var o = c.offsets(list);
			lock.acquire();
			presents.push(t);
			offsets.push(o == null ? -1 : o.y);
			lock.release();
		};
		var step = 0, from = 0.0, to = 0.0, target = 0.0;
		App.run(() -> {
			step++;
			if (step == 1) check("the program on a thread of its own", OsThread.program != 0 && hxmc.NativeThread.current() == OsThread.program, 'thread ${OsThread.program}');
			if (step == 30) {
				// (UIKit animates the view's offset on the main thread, the program blocked meanwhile)
				var s:helder.ui.platform.apple.IosScroll = cast @:privateAccess w.iosScroll;
				var v:Null<hxmc.unsafe.Ptr> = s == null ? null : @:privateAccess s.views.get(list);
				check("the list has its UIScrollView", v != null, s == null ? "no helder.ui.platform.apple.IosScroll" : v == null ? "none for the list" : "");
				if (v == null) Sys.exit(1);
				var k = @:privateAccess s.k;
				target = 1200;
				OsThread.run(() -> {
					var p:hxmc.unsafe.Ptr<helder.os.apple.objc.CGPoint> = hxmc.unsafe.LibC.malloc(16);
					p.value.x = 0;
					p.value.y = target * k;
					helder.os.apple.objc.Msg.vPointBool(v, helder.os.apple.objc.ObjC.sel("setContentOffset:animated:"), p.value, true);
					hxmc.unsafe.LibC.free(cast p);
				});
				var l = c.layers, quads0 = l == null ? 0 : l.quadsTotal, frames0 = l == null ? 0 : l.frames;
				from = Timer.stamp();
				Sys.sleep(0.5);
				// (Core Animation's: the list's content moved as a layer, at most a thumb drawn again)
				if (l != null) check("on the system's layers: the list's layer moved, not drawn", l.frames > frames0 && l.quadsTotal - quads0 <= 8 * (l.frames - frames0),
					'${l.frames - frames0} frames committed, ${Math.round((l.quadsTotal - quads0) / Math.max(1, l.frames - frames0) * 10) / 10} quads drawn a frame');
				to = Timer.stamp();
			}
			if (step == 30 + 40) {
				lock.acquire();
				var during = [for (i in 0...presents.length) if (presents[i] > from && presents[i] <= to) i];
				var gaps = [for (i in 1...during.length) presents[during[i]] - presents[during[i - 1]]];
				var moving = during.length > 1 ? offsets[during[during.length - 1]] - offsets[during[0]] : 0.0;
				lock.release();
				gaps.sort(Reflect.compare);
				var median = gaps.length > 0 ? gaps[gaps.length >> 1] : 1.0, worst = gaps.length > 0 ? gaps[gaps.length - 1] : 1.0;
				check("the compositor's frames while the program was blocked for 500 ms", during.length >= 10,
					'${during.length} frames, median gap ${Math.round(median * 10000) / 10} ms, max ${Math.round(worst * 10000) / 10} ms');
				check("at the view's offsets as UIKit moved them", moving > 100, 'moved $moving');
				check("the program has the view's offset", Math.abs(list.scrollY - target) < 1, '${list.scrollY}, the view at $target');
				// (a native field: text typed in, as the keyboard types)
				field.focus();
			}
			if (step == 30 + 50) {
				var e = @:privateAccess (cast field.editor : helder.ui.platform.apple.IosViews.IosEditor);
				check("the field native", e != null, "");
				if (e != null) OsThread.run(() -> {
					var s = helder.os.apple.objc.ObjC.str("typed");
					helder.os.apple.objc.Msg.vPtr(@:privateAccess e.view, helder.os.apple.objc.ObjC.sel("insertText:"), s);
					helder.os.apple.objc.ObjC.release(s);
				});
			}
			if (step == 30 + 60) {
				check("text typed in the native field reaches its node", field.text == "typed", field.text);
				Sys.println("IosScrollCheck: " + (failed == 0 ? "ok" : '$failed FAILED'));
				Sys.exit(failed == 0 ? 0 : 1);
			}
			if (w.needsFrame() || step < 30 + 60) w.frame();
			w.device.settle();
		}, e -> w.handle(e));
	}
}
