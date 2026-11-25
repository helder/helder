import helder.os.*;
import helder.ui.*;

// A click on an inactive window makes the app active and the window key,
// as in any Mac app, unbundled too (macOS; the system's own click,
// CGEventPost, which moves the pointer: CI's, or HELDER_TEST_INPUT=1; run
// without HELDER_BACKGROUND, the app a regular one).
//   KeyClickCheck: helder.ui's window, its compositor's (the system's layers)
//   KeyClickCheck --plain: helder.os's window alone
@:hxmc.unsafe(gc)
class KeyClickCheck {
	static function main() {
		#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
		if (Sys.getEnv("GITHUB_ACTIONS") != "true" && Sys.getEnv("HELDER_TEST_INPUT") != "1") {
			Sys.println("KeyClickCheck: skipped (a real click: CI's, or HELDER_TEST_INPUT=1)");
			return;
		}
		if (Sys.getEnv("HELDER_BACKGROUND") == "1") {
			Sys.println("KeyClickCheck: skipped (HELDER_BACKGROUND=1: never active by design)");
			return;
		}
		var plain = Sys.args().indexOf("--plain") >= 0, ui:Null<UiWindow> = null, win:Window, presses = 0;
		if (plain) win = new Window("KeyClickCheck", 300, 200) else {
			ui = new UiWindow("KeyClickCheck", 300, 200);
			var n = new Node();
			n.style.set({width: 300, height: 200, background: 0xFF2F7FE8});
			n.onClick = _ -> presses++;
			ui.root.append(n);
			win = ui.window;
		}
		var view = win.surface.handle, step = 0, clicked = 0.0, before = "";
		function state():String
			return OsThread.get(() -> {
				var M = helder.os.apple.objc.Msg, O = helder.os.apple.objc.ObjC;
				var app = M.id(O.cls("NSApplication"), O.sel("sharedApplication")), w = M.id(view, O.sel("window"));
				var front = M.id(M.id(O.cls("NSWorkspace"), O.sel("sharedWorkspace")), O.sel("frontmostApplication"));
				var mine = M.b(M.id(O.cls("NSRunningApplication"), O.sel("currentApplication")), O.sel("isActive"));
				'active ${M.b(app, O.sel("isActive"))} key ${M.b(w, O.sel("isKeyWindow"))} main ${M.b(w, O.sel("isMainWindow"))} running-active $mine policy ${M.i(app, O.sel("activationPolicy"))} front ${front.isNull() ? "none" : helder.os.apple.objc.ObjC.string(M.id(front, O.sel("localizedName")))}';
			});
		App.run(() -> {
			step++;
			if (step == 40) {
				Sys.println('KeyClickCheck: shown: ${state()}');
				// (another app in front: Finder, the app deactivated)
				OsThread.run(() -> {
					var M = helder.os.apple.objc.Msg, O = helder.os.apple.objc.ObjC;
					var s = O.str("com.apple.finder"), apps = M.idPtr(O.cls("NSRunningApplication"), O.sel("runningApplicationsWithBundleIdentifier:"), s);
					O.release(s);
					var f = M.id(apps, O.sel("firstObject"));
					if (!f.isNull()) M.bInt(f, O.sel("activateWithOptions:"), 2);
					M.v(M.id(O.cls("NSApplication"), O.sel("sharedApplication")), O.sel("deactivate"));
				});
			}
			if (step == 100) {
				before = state();
				Sys.println('KeyClickCheck: before the click: $before');
				Click.press(win, 150, 100);
				clicked = haxe.Timer.stamp();
			}
			if (clicked > 0 && haxe.Timer.stamp() - clicked > 1.5) {
				var after = state(), ok = after.indexOf("active true key true") == 0;
				Sys.println('KeyClickCheck: ${ok ? "ok" : "FAIL"}: a click on the inactive window${plain ? " (helder.os's)" : ""}: $after${plain ? "" : ', $presses presses reached helder'}');
				win.close();
				Sys.exit(ok ? 0 : 1);
			}
			if (ui != null && (ui.needsFrame() || step < 5)) ui.frame();
			App.wait(0.016);
		}, e -> if (ui != null) ui.handle(e));
		#else
		Sys.println("KeyClickCheck: macOS's: skipped");
		#end
	}
}

#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
// (the system's own click at x, y points of w's content: CGEventPost, the HID's)
@:hxmc.unsafe(gc)
private class Click {
	public static function press(w:Window, x:Float, y:Float) {
		if (Sys.getEnv("GITHUB_ACTIONS") != "true" && Sys.getEnv("HELDER_TEST_INPUT") != "1") return;
		var p = w.position();
		var at:hxmc.unsafe.Ptr<helder.os.apple.objc.CGPoint> = hxmc.unsafe.LibC.malloc(16);
		at.value.x = p.x + x;
		at.value.y = p.y + y;
		for (type in [5, 1, 2]) {
			var ev = CG.CGEventCreateMouseEvent(hxmc.unsafe.Ptr.nil(), type, at.value, 0);
			CG.CGEventPost(0, ev);
			CF.CFRelease(ev);
			Sys.sleep(0.05);
		}
		hxmc.unsafe.LibC.free(at);
	}
}

@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics") private extern class CG {
	static function CGEventCreateMouseEvent(source:hxmc.unsafe.Ptr, type:Int, p:helder.os.apple.objc.CGPoint, button:Int):hxmc.unsafe.Ptr;
	static function CGEventPost(tap:Int, ev:hxmc.unsafe.Ptr):Void;
}

@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation") private extern class CF {
	static function CFRelease(p:hxmc.unsafe.Ptr):Void;
}
#end
