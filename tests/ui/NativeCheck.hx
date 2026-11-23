import haxe.Timer;
import helder.os.*;
import helder.ui.*;
import helder.ui.draw.*;
import helder.ui.widgets.TextField;

// A native view over a scroller moved with the compositor's scroll
// (AsyncScrollWindow --native; macOS: an NSTextField): the program blocked
// while wheel input comes, the field read on the main thread before the
// program's next frame places it: where the compositor's offset puts it.
// Elsewhere (no native fields) skipped.
class NativeCheck {
	public static function run(w:UiWindow, list:Node) {
		var c = w.compositor;
		#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
		if (c == null || !Inject.supported) {
			Sys.println("NativeCheck: no compositor or input to inject here: skipped");
			w.close();
			return;
		}
		var field = new TextField();
		field.host = Native;
		field.text = "native";
		field.style.set({height: 22, shrink: 0});
		list.insert(field, 3);
		var step = 0, failed = 0;
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
				var moved = o == null ? 0.0 : o.y - from, expect = placed == null ? 0.0 : placed[1] - moved;
				check("the compositor scrolled while the program was blocked", moved > 0, from + " to " + (o == null ? null : o.y));
				check("the field moved with it before the program's next frame", placed != null && y != null && Math.abs(y - expect) < 0.5
					|| y == null && moved > 0, 'placed at ${placed == null ? null : placed[1]}, now at $y, expected $expect');
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

	#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
	// (the field's top in the window's points, y down; null: hidden)
	static function frameTop(f:TextField):Null<Float> @:privateAccess {
		var e:helder.ui.platform.MacViews.MacEditor = cast f.editor;
		if (e == null) return null;
		return OsThread.get(() -> {
			var v = e.field, c = e.views.content();
			if (helder.os.objc.Msg.b(v, helder.os.objc.ObjC.sel("isHidden"))) return null;
			var r = helder.os.objc.Msg.rect(v, helder.os.objc.ObjC.sel("frame")), b = helder.os.objc.Msg.rect(c, helder.os.objc.ObjC.sel("bounds"));
			var top:Null<Float> = b.size.height - r.origin.y - r.size.height;
			return top;
		});
	}
	#end
}
