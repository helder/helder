import haxe.Timer;
import helder.os.*;
import helder.ui.*;
import helder.ui.draw.*;
import helder.ui.controls.TextField;

// A native view over a scroller moved with the compositor's scroll
// (AsyncScrollWindowCheck --native; macOS: an NSTextField, Windows: an EDIT): the program blocked
// while wheel input comes, the field read on the main thread before the
// program's next frame places it: where the compositor's offset puts it.
// Elsewhere (no native fields) skipped.
@:hxmc.unsafe(gc)
class NativeCheck {
	public static function run(w:helder.ui.UiWindow, list:Node) {
		var c = w.compositor;
		#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
		if (c == null || !Inject.supported) {
			Sys.println("NativeCheck: no compositor or input to inject here: skipped");
			w.close();
			return;
		}
		var field = new TextField();
		field.host = Native;
		field.text = "native";
		field.style.set({height: 22, flexShrink: 0});
		list.insert(field, 3);
		var step = 0, failed = 0, lock = new sys.thread.Mutex(), shownY = Math.NaN;
		// (the offset of the compositor's last frame: with Core Animation's
		// layers the field is in their tree and moves in its transaction, at it)
		c.onFrame = _ -> {
			var o = c.offsets(list);
			lock.acquire();
			shownY = o == null ? Math.NaN : o.y;
			lock.release();
		};
		App.run(() -> {
			step++;
			if (step == 14) {
				var placed = @:privateAccess field.placed, from = list.scrollY;
				var inject = Inject.start(w.window, 120, 0.04);
				Sys.sleep(0.3);
				inject.join();
				var o = c.offsets(list), y = frameTop(field);
				function check(what:String, ok:Bool, detail:String) {
					if (!ok) failed++;
					Sys.println('NativeCheck: ${ok ? "ok" : "FAIL"}: $what ($detail)');
				}
				lock.acquire();
				var shown = shownY;
				lock.release();
				var moved = o == null ? 0.0 : o.y - from, expect = placed == null ? 0.0 : placed[1] - moved;
				var drawn = placed == null || Math.isNaN(shown) ? expect : placed[1] - (shown - from);
				check("the compositor scrolled while the program was blocked", moved > 0, from + " to " + (o == null ? null : o.y));
				var at = @:privateAccess w.ui.layered ? drawn : expect;
				check("the field moved with it before the program's next frame", placed != null && y != null && Math.abs(y - at) < SNAP || y == null && moved > 0,
					'placed at ${placed == null ? null : placed[1]}, now at $y, expected $at');
				w.close();
				Sys.println("NativeCheck: " + (failed == 0 ? "ok" : '$failed FAILED'));
				Sys.exit(failed == 0 ? 0 : 1);
			}
			if (w.needsFrame()) w.frame();
			w.device.settle();
		}, e -> w.handle(e));
		#else
		Sys.println("NativeCheck: no native fields here: skipped");
		w.close();
		#end
	}

	#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
	// (an EDIT is placed on whole pixels)
	static inline var SNAP = 1.0;

	// (the field's top in the window's layout pixels; null: hidden)
	static function frameTop(f:TextField):Null<Float> @:privateAccess {
		var e:helder.ui.platform.windows.Views.WinEditor = cast f.editor;
		if (e == null) return null;
		var k = e.views.scale();
		return OsThread.get(() -> {
			if (WinRect.IsWindowVisible(e.hwnd) == 0) return null;
			var r:hxmc.unsafe.Ptr<hxmc.unsafe.Int32> = hxmc.unsafe.LibC.malloc(16);
			WinRect.GetWindowRect(e.hwnd, cast r);
			WinRect.ScreenToClient(e.views.hwnd, cast r);
			var top:Null<Float> = r[1] / k;
			hxmc.unsafe.LibC.free(cast r);
			return top;
		});
	}
	#end

	#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
	static inline var SNAP = 0.5;

	// (the field's top in the window's points, y down; null: hidden)
	static function frameTop(f:TextField):Null<Float> @:privateAccess {
		var e:helder.ui.platform.apple.MacViews.MacEditor = cast f.editor;
		if (e == null) return null;
		return OsThread.get(() -> {
			var v = e.field, c = e.views.content();
			if (helder.os.apple.objc.Msg.b(v, helder.os.apple.objc.ObjC.sel("isHidden"))) return null;
			// (in the window's content view, through a host where it is in the system's layer tree)
			var r = helder.os.apple.objc.Msg.rectRectPtr(v, helder.os.apple.objc.ObjC.sel("convertRect:toView:"), helder.os.apple.objc.Msg.rect(v, helder.os.apple.objc.ObjC.sel("bounds")), c);
			var b = helder.os.apple.objc.Msg.rect(c, helder.os.apple.objc.ObjC.sel("bounds"));
			var top:Null<Float> = b.size.height - r.origin.y - r.size.height;
			return top;
		});
	}
	#end
}

#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
@:hxmc.c @:hxmc.lib("user32") private extern class WinRect {
	static function IsWindowVisible(hwnd:hxmc.unsafe.Ptr):Int;
	static function GetWindowRect(hwnd:hxmc.unsafe.Ptr, r:hxmc.unsafe.Ptr):Int;
	static function ScreenToClient(hwnd:hxmc.unsafe.Ptr, p:hxmc.unsafe.Ptr):Int;
}
#end
