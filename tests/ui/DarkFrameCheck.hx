import helder.ui.UiWindow;
import helder.ui.UiWindow.Surface;
import helder.view.*;
import helder.view.graph.Graph.*;
import hxmc.unsafe.*;

// Windows: the frame dark wherever the ui is (UiWindow's setDark: Window.dark,
// DWMWA_USE_IMMERSIVE_DARK_MODE, read back with DwmGetWindowAttribute). A
// window that follows the system: the system's appearance at first, then a
// flip of it (Settings.dark, as the system's change sets it); a window with
// its own <Surface dark>: that, and a change of it, the system's flip not.
// Exits non-zero on a frame that is not as its ui.
@:renderer(helder.ui.view.NodeRenderer)
class DarkFrameCheck implements Markup {
	static var ok = true;

	static function check(what:String, w:UiWindow, want:Bool) {
		var ui = w.ui.dark, frame = attribute(w);
		var good = ui == want && frame == (want ? 1 : 0);
		if (!good) ok = false;
		Sys.println('DarkFrameCheck: $what: ui ${ui ? "dark" : "light"}, the frame\'s attribute $frame: ' + (good ? "ok" : "FAIL"));
	}

	static function attribute(w:UiWindow):Int {
		var hwnd:Ptr = @:privateAccess (cast w.window.native : helder.os.windows.WinWindow).hwnd;
		return helder.os.OsThread.get(() -> Arena.scopedValue(a -> {
			var v:Ptr<Int32> = a.alloc(4);
			v.value = -1;
			DwmGet.DwmGetWindowAttribute(hwnd, 20, v, 4) >= 0 ? v.value : -1;
		}));
	}

	// (the system's appearance as its change sets it: Settings' own signal)
	static function system(d:Bool) {
		@:privateAccess helder.os.Settings.current().dark(d);
		flush();
	}

	static function main() {
		var start = helder.os.Settings.dark.peek(), own = signal(!start);
		var follows:Null<UiWindow> = null;
		UiWindow.run(<>
			<Surface title="follows" width={160} height={100} ref={w -> follows = w}/>
			<Surface title="its own" width={160} height={100} dark={own} ref={fixed -> helder.async.Async.launch(_ -> {
				// (both open, their first frames shown)
				helder.async.Async.delay(0.3);
				check("follows the system, at first", follows, start);
				check("its own, at first", fixed, !start);
				system(!start);
				check("follows the system, flipped", follows, !start);
				check("its own, the system flipped", fixed, !start);
				system(start);
				check("follows the system, flipped back", follows, start);
				own(start);
				flush();
				check("its own, changed", fixed, start);
				Sys.exit(ok ? 0 : 1);
			})}/>
		</>);
	}
}

@:hxmc.c @:hxmc.lib("dwmapi") extern class DwmGet {
	static function DwmGetWindowAttribute(hwnd:Ptr, attribute:Int, value:Ptr, size:Int):Int;
}
