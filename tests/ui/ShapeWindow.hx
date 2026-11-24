import helder.os.*;
import helder.ui.*;
import helder.ui.draw.*;
#if (hxmc.target == "linux-x86_64" || hxmc.target == "linux-arm64")
import helder.os.x11.Xlib;
#end

// A transparent window (helder.os.Window's transparent; bun run test
// window on macOS and Windows, wayland on Linux: tests/ui/shape.sh): an
// opaque red box and a half-transparent blue one on a clear background.
// Its frame read back keeps its alpha, premultiplied; then what the system
// shows, where a test can see it: macOS's capture of the window (its own:
// no permission, though a machine may give empty ones), Windows' screen
// over an opaque green window behind it, X11's 32-bit pixels and the
// screen composed over a green window (where a compositing manager runs;
// else opaque, said so), weston's screenshot over its green background.
//   ShapeWindow [--transparent no]: the system can't (X11 without a
//   compositing manager): opaque, as said
@:hxmc.unsafe(gc)
class ShapeWindow {
	static inline var W = 200;
	static inline var H = 150;
	static var failed = 0;

	static function check(ok:Bool, what:String) {
		if (!ok) failed++;
		Sys.println('ShapeWindow: ${ok ? "ok" : "FAIL"}: $what');
	}

	static function main() {
		var a = Sys.args(), t = a.indexOf("--transparent"), expect = t < 0 ? "yes" : a[t + 1];
		var desk = behind();
		var w = new UiWindow("ShapeWindow", W, H, null, false, Standard, true);
		w.background = Color.TRANSPARENT;
		var box = new Node(), half = new Node();
		box.style.set({position: Absolute, left: 50, top: 40, width: 60, height: 60, background: 0xFFFF0000});
		half.style.set({position: Absolute, left: 130, top: 40, width: 40, height: 60, background: 0x800000FF});
		w.root.append(box);
		w.root.append(half);
		if (desk != null) {
			var p = desk.window.position();
			w.window.moveTo(p.x, p.y);
		}
		var step = 0, all = desk == null ? [w] : [desk, w];
		App.run(() -> {
			if (++step == 12) {
				check(w.window.transparent == (expect == "yes"), 'transparent: ${w.window.transparent}, ${expect == "yes" ? "asked for and composed so" : "not here: opaque"}');
				w.capture = captured = haxe.io.Bytes.alloc(w.device.width * w.device.height * 4);
			}
			for (u in all)
				if (u.needsFrame() || step < 40) u.frame();
			w.device.settle();
			if (step == 14) frame(w);
			// (the window server's after some of its frames)
			if (step == 40) {
				Sys.sleep(0.3);
				system(w, desk);
				Sys.println("ShapeWindow: " + (failed == 0 ? "ok" : '$failed FAILED'));
				for (u in all)
					u.close();
				Sys.exit(failed > 0 ? 1 : 0);
			}
		}, e -> for (u in all) if (u.window == e.window) u.handle(e));
		Sys.exit(failed > 0 ? 1 : 0);
	}

	// (the frame read back, RGBA: at points x, y)
	static function frame(w:UiWindow) {
		var px = captured;
		var k = w.device.width / W;
		function at(x:Float, y:Float):Array<Int> {
			var o = (Math.round(y * k) * w.device.width + Math.round(x * k)) * 4;
			return [for (i in 0...4) px.get(o + i)];
		}
		var clear = at(10, 10), red = at(80, 70), blue = at(150, 70);
		if (w.window.transparent) {
			check(clear[3] == 0 && clear[0] == 0, 'the frame: clear where nothing is drawn ($clear)');
			check(near(blue, [0, 0, 128, 128]), 'the frame: the half box premultiplied ($blue)');
		} else check(clear[3] == 255, 'the frame: opaque where the window is ($clear)');
		check(near(red, [255, 0, 0, 255]), 'the frame: the box opaque ($red)');
	}

	static var captured:Null<haxe.io.Bytes> = null;

	static function near(a:Array<Int>, b:Array<Int>):Bool {
		for (i in 0...4)
			if (Math.abs(a[i] - b[i]) > 3) return false;
		return true;
	}

	// (the system's pixels at x, y points of the window, RGB: green behind it,
	// the box over it, the half box blended over it, premultiplied)
	static function screen(what:String, at:(x:Float, y:Float) -> Array<Int>) {
		var clear = at(10, 10), red = at(80, 70), half = at(150, 70);
		check(near(clear.slice(0, 3).concat([0]), [0, 255, 0, 0]), '$what: green behind through the clear pixels ($clear)');
		check(near(red.slice(0, 3).concat([0]), [255, 0, 0, 0]), '$what: the box over it ($red)');
		check(near(half.slice(0, 3).concat([0]), [0, 127, 128, 0]), '$what: the half box blended over it ($half)');
	}

	// (Windows, X11: an opaque window of a known colour, under the transparent one)
	static function behind():Null<UiWindow> {
		#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64" || hxmc.target == "linux-x86_64" || hxmc.target == "linux-arm64")
		if (Sys.systemName() == "Linux" && Sys.getEnv("WAYLAND_DISPLAY") != null && Sys.getEnv("HELDER_X11") != "1") return null;
		var d = new UiWindow("ShapeWindow desk", W, H, null, false);
		d.background = Color.rgb(0x00FF00);
		d.window.moveTo(200, 200);
		return d;
		#else
		return null;
		#end
	}

	// (what the system shows)
	static function system(w:UiWindow, desk:Null<UiWindow>) {
		if (!w.window.transparent) return;
		#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
		var view = w.window.surface.handle;
		var id = OsThread.get(() -> helder.os.objc.Msg.i(helder.os.objc.Msg.id(view, helder.os.objc.ObjC.sel("window")), helder.os.objc.ObjC.sel("windowNumber")).toInt());
		var img = SystemLayersWindow.Capture.window(id);
		if (img == null) return Sys.println("ShapeWindow: no window capture here: skipped");
		// (BGRA, the title bar above the content)
		var k = img.width / W, top = img.height - Math.round(H * k);
		function at(x:Float, y:Float):Array<Int> {
			var o = ((top + Math.round(y * k)) * img.width + Math.round(x * k)) * 4;
			return [img.pixels.get(o + 2), img.pixels.get(o + 1), img.pixels.get(o), img.pixels.get(o + 3)];
		}
		// (nothing in it, its title bar neither: the process may not read the screen, Screen Recording)
		var any = false, i = 3;
		while (!any && i < img.pixels.length) {
			any = img.pixels.get(i) != 0;
			i += 4;
		}
		if (!any) return Sys.println("ShapeWindow: the window's capture empty (no Screen Recording here): skipped");
		var clear = at(10, 10), red = at(80, 70);
		check(clear[3] == 0, 'the window server: clear where nothing is drawn ($clear)');
		check(red[3] == 255 && red[0] > 200 && red[1] < 60, 'the window server: the box opaque ($red)');
		#elseif (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
		desk.device.settle();
		w.device.settle();
		Sys.sleep(0.3);
		var p = w.window.position(), k = w.window.scale;
		function at(x:Float, y:Float):Array<Int> {
			var c = Screen.pixel(Math.round(p.x * k + x * k), Math.round(p.y * k + y * k));
			return [c & 0xFF, c >> 8 & 0xFF, c >> 16 & 0xFF];
		}
		screen("the screen", at);
		#elseif (hxmc.target == "linux-x86_64" || hxmc.target == "linux-arm64")
		if (w.window.surface.kind == X11) x11(w) else wayland(w);
		#end
	}

	#if (hxmc.target == "linux-x86_64" || hxmc.target == "linux-arm64")
	// (X11: the window's own pixels, 32 bits with their alpha; the root's,
	// composed by the compositing manager, the window behind through the clear ones)
	static function x11(w:UiWindow) {
		var s = w.window.surface;
		function at(id:haxe.Int64, x:Int, y:Int):Array<Int> {
			var img = Xlib.XGetImage(s.display, id, x, y, 1, 1, (-1 : haxe.Int64), X.ZPixmap);
			if (img.isNull()) return [-1, -1, -1, -1];
			var d = img.value.data, c = [d[2], d[1], d[0], img.value.depth == 32 ? d[3] : 255];
			Xlib.XDestroyImage(img);
			return c;
		}
		var id = s.handle.toI64(), clear = at(id, 10, 10), red = at(id, 80, 70);
		check(clear[3] == 0, 'X11: the window\'s pixels clear where nothing is drawn ($clear)');
		check(red[3] == 255 && red[0] > 200, 'X11: its box opaque ($red)');
		var p = w.window.position(), root = Xlib.XDefaultRootWindow(s.display);
		screen("X11's screen", (x, y) -> at(root, p.x + Math.round(x), p.y + Math.round(y)));
	}

	// (Wayland: weston's screenshot, its background green (tests/os/wayland.sh's
	// weston.ini); where the box is, the window)
	static function wayland(w:UiWindow) {
		var dir = Sys.getEnv("XDG_RUNTIME_DIR") + "/shape-" + Std.random(1 << 30);
		sys.FileSystem.createDirectory(dir);
		var old = Sys.getCwd();
		Sys.setCwd(dir);
		var code = Sys.command("weston-screenshooter > /dev/null 2>&1");
		Sys.setCwd(old);
		var shots = [for (f in sys.FileSystem.readDirectory(dir)) if (StringTools.endsWith(f, ".png")) f];
		if (code != 0 || shots.length == 0) return Sys.println("ShapeWindow: no weston screenshot (weston --debug, weston-screenshooter): skipped");
		var img = helder.image.Image.decode(sys.io.File.getBytes('$dir/${shots[0]}')), px = img.pixels, k = w.window.scale;
		function at(x:Int, y:Int):Array<Int> {
			var o = (y * img.width + x) * 4;
			return [px.get(o), px.get(o + 1), px.get(o + 2)];
		}
		// (the box's top left: the first red pixel, row by row)
		var bx = -1, by = -1, i = 0;
		while (bx < 0 && i < img.width * img.height) {
			var c = at(i % img.width, Std.int(i / img.width));
			if (c[0] > 240 && c[1] < 20 && c[2] < 20) {
				bx = i % img.width;
				by = Std.int(i / img.width);
			}
			i++;
		}
		if (bx < 0) {
			check(false, "Wayland: the box in weston's screenshot");
			return;
		}
		var ox = bx - Math.round(50 * k), oy = by - Math.round(40 * k);
		screen("weston's output", (x, y) -> at(ox + Math.round(x * k), oy + Math.round(y * k)));
		for (f in shots)
			sys.FileSystem.deleteFile('$dir/$f');
		sys.FileSystem.deleteDirectory(dir);
	}
	#end
}

#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
// (the screen's pixel, GDI's: the composed desktop, 0x00BBGGRR)
@:hxmc.unsafe(gc)
class Screen {
	public static function pixel(x:Int, y:Int):Int {
		var dc = ScreenDc.GetDC(hxmc.unsafe.Ptr.nil());
		var c = ScreenPixel.GetPixel(dc, x, y);
		ScreenDc.ReleaseDC(hxmc.unsafe.Ptr.nil(), dc);
		return c;
	}
}

@:hxmc.c @:hxmc.lib("user32") extern class ScreenDc {
	static function GetDC(hwnd:hxmc.unsafe.Ptr):hxmc.unsafe.Ptr;
	static function ReleaseDC(hwnd:hxmc.unsafe.Ptr, dc:hxmc.unsafe.Ptr):Int;
}

@:hxmc.c @:hxmc.lib("gdi32") extern class ScreenPixel {
	static function GetPixel(dc:hxmc.unsafe.Ptr, x:Int, y:Int):Int;
}
#end
