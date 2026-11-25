import helder.os.*;
import helder.ui.*;
import helder.ui.draw.*;

// Two helder windows of one process on screen (Windows, the window lane,
// HELDER_BACKGROUND=1), each drawing its background alone: each one's own
// pixels (PrintWindow) and the screen's (GDI) where it is. A window that
// never drew a quad once showed nothing on DirectComposition's layers.
//   TwoWindows opaque: a green window and a blue one beside it
//   TwoWindows transparent: a green one, a transparent one over it, a red
//   box on its clear background: green through the clear pixels
@:hxmc.unsafe(gc)
class TwoWindows {
	static var failed = 0;

	static function check(ok:Bool, what:String) {
		if (!ok) failed++;
		Sys.println('TwoWindows: ${ok ? "ok" : "FAIL"}: $what');
	}

	static function main() {
		#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
		var see = Sys.args().indexOf("transparent") >= 0;
		var g = new UiWindow("TwoWindows green", 300, 200, null, false);
		g.background = Color.rgb(0x00FF00);
		g.window.moveTo(100, 100);
		var o = new UiWindow("TwoWindows " + (see ? "transparent" : "blue"), 200, 150, null, false, Standard, see);
		if (see) {
			o.background = Color.TRANSPARENT;
			var box = new Node();
			box.style.set({position: Absolute, left: 100, top: 50, width: 60, height: 60, background: 0xFFFF0000});
			o.root.append(box);
		} else o.background = Color.rgb(0x0000FF);
		o.window.moveTo(see ? 100 : 450, 100);
		var all = [g, o], step = 0;
		App.run(() -> {
			for (u in all)
				if (u.needsFrame() || step < 40) u.frame();
			if (++step < 40) return;
			for (u in all)
				u.device.settle();
			Sys.sleep(0.3);
			for (u in all)
				Sys.println('TwoWindows: ${u.window.title}: ${state(u)}');
			check(Win.printed(g) == 0x00FF00, 'the green one\'s own pixels: ${hex(Win.printed(g))}');
			check(Win.screen(g, 20, 180) == 0x00FF00, 'the green one on screen: ${hex(Win.screen(g, 20, 180))}');
			if (see) {
				check(Win.screen(o, 10, 10) == 0x00FF00, 'green through the transparent one\'s clear pixels: ${hex(Win.screen(o, 10, 10))}');
				check(Win.screen(o, 130, 80) == 0xFF0000, 'its box over it: ${hex(Win.screen(o, 130, 80))}');
			} else {
				check(Win.printed(o) == 0x0000FF, 'the blue one\'s own pixels: ${hex(Win.printed(o))}');
				check(Win.screen(o, 100, 75) == 0x0000FF, 'the blue one on screen: ${hex(Win.screen(o, 100, 75))}');
			}
			Sys.println("TwoWindows: " + (failed == 0 ? "ok" : '$failed FAILED'));
			for (u in all)
				u.close();
			Sys.exit(failed > 0 ? 1 : 0);
		}, e -> {
			for (u in all)
				if (u.window == e.window) u.handle(e);
		});
		#end
	}

	static function hex(c:Int):String
		return "#" + StringTools.hex(c, 6);

	#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
	static function state(u:UiWindow):String {
		var b:helder.gfx.d3d11.D3D11Backend = cast @:privateAccess u.device.impl, l = u.compositor == null ? null : u.compositor.layers;
		return 'composed ${b.composition != null}, system layers ${l != null}' + (l == null ? "" : ', frames on them ${l.frames}, single ${l.single}')
			+ ', its own frames ${b.quiet ? "quiet" : "presented"}';
	}
	#end
}

#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
// (pixels as RGB: GDI's 0x00BBGGRR turned)
@:hxmc.unsafe(gc)
class Win {
	static function rgb(c:Int):Int
		return (c & 0xFF) << 16 | (c & 0xFF00) | (c >> 16 & 0xFF);

	// (the screen's pixel at x, y points of u's content)
	public static function screen(u:UiWindow, x:Float, y:Float):Int {
		var p = u.window.position(), k = u.window.scale, dc = WinGdi.GetDC(hxmc.unsafe.Ptr.nil());
		var c = WinPixel.GetPixel(dc, Math.round((p.x + x) * k), Math.round((p.y + y) * k));
		WinGdi.ReleaseDC(hxmc.unsafe.Ptr.nil(), dc);
		return rgb(c);
	}

	// (its own pixels, PrintWindow's PW_RENDERFULLCONTENT | PW_CLIENTONLY: the middle of its content)
	public static function printed(u:UiWindow):Int {
		var hwnd = u.window.surface.handle, w = u.window.surface.width, h = u.window.surface.height;
		return OsThread.get(() -> {
			var screen = WinGdi.GetDC(hxmc.unsafe.Ptr.nil());
			var dc = helder.os.windows.User32.Gdi32.CreateCompatibleDC(screen), bmp = WinPixel.CreateCompatibleBitmap(screen, w, h);
			var old = helder.os.windows.User32.Gdi32.SelectObject(dc, bmp);
			var c = WinGdi.PrintWindow(hwnd, dc, 3) == 0 ? -1 : rgb(WinPixel.GetPixel(dc, w >> 1, h >> 1));
			helder.os.windows.User32.Gdi32.SelectObject(dc, old);
			helder.os.windows.User32.Gdi32.DeleteObject(bmp);
			helder.os.windows.User32.Gdi32.DeleteDC(dc);
			WinGdi.ReleaseDC(hxmc.unsafe.Ptr.nil(), screen);
			c;
		});
	}
}

@:hxmc.c @:hxmc.lib("user32") extern class WinGdi {
	static function GetDC(hwnd:hxmc.unsafe.Ptr):hxmc.unsafe.Ptr;
	static function ReleaseDC(hwnd:hxmc.unsafe.Ptr, dc:hxmc.unsafe.Ptr):Int;
	static function PrintWindow(hwnd:hxmc.unsafe.Ptr, dc:hxmc.unsafe.Ptr, flags:Int):Int;
}

@:hxmc.c @:hxmc.lib("gdi32") extern class WinPixel {
	static function GetPixel(dc:hxmc.unsafe.Ptr, x:Int, y:Int):Int;
	static function CreateCompatibleBitmap(dc:hxmc.unsafe.Ptr, w:Int, h:Int):hxmc.unsafe.Ptr;
}
#end
