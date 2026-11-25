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
// over an opaque green window behind it (a plain one of GDI's; --behind
// helder: a helder window, its state told, not checked), X11's 32-bit pixels and the
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
		// (drawn, its clicks passing through: pointer-events none)
		var bar = new Node();
		bar.style.set({position: Absolute, left: 10, top: 115, width: 180, height: 20, background: 0xFFFFFF00, pointerEvents: None});
		w.root.append(box);
		w.root.append(half);
		w.root.append(bar);
		// (both at one place: the window behind's own move not yet done)
		if (desk != null) w.window.moveTo(200, 200);
		#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
		if (desk == null) w.window.moveTo(200, 200);
		#end
		var step = 0, all = desk == null ? [w] : [desk, w], end = 40, downs = [0, 0];
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
				if (w.window.transparent) inputs(w);
				if (w.window.transparent && (desk != null || behindPlain()) && !helderBehind && Click.can()) end = 70;
			}
			// (a click on the box: its own; then where it is clear: the window
			// behind's, which it activates and raises, so it comes last)
			for (i => at in [[80.0, 70.0], [10.0, 10.0]]) {
				var s0 = 41 + i * 14, through = i == 1;
				if (step == s0) Click.move(w.window, at[0], at[1]);
				if (step == s0 + 4) {
					downs = [0, 0];
					#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
					Plain.downs = 0;
					Plain.styles(w.window.surface.handle);
					#elseif (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
					macState(w);
					#end
					Click.press(w.window, at[0], at[1]);
				}
				if (step == s0 + 12) {
					#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
					downs[0] += Plain.downs;
					#end
					check(through ? downs[0] >= 1 && downs[1] == 0 : downs[1] >= 1 && downs[0] == 0,
						'a click ${through ? "where it is clear: the window behind's" : "on the box: its own"} (presses: behind ${downs[0]}, it ${downs[1]})');
				}
			}
			if (step == end) {
				Sys.println("ShapeWindow: " + (failed == 0 ? "ok" : '$failed FAILED'));
				for (u in all)
					u.close();
				Sys.exit(failed > 0 ? 1 : 0);
			}
		}, e -> {
			if (e.kind == MouseDown) downs[e.window == w.window ? 1 : 0]++;
			for (u in all)
				if (u.window == e.window) u.handle(e);
		});
		Sys.exit(failed > 0 ? 1 : 0);
	}

	// (where it takes the pointer: the boxes it draws, in pixels, not the bar of pointer-events none)
	static function inputs(w:UiWindow) {
		var k = w.scale, r = w.window.inputRects;
		function box(x:Float, y:Float, bw:Float, bh:Float):Array<Int> {
			var x0 = Math.floor(x * k), y0 = Math.floor(y * k);
			return [x0, y0, Math.ceil((x + bw) * k) - x0, Math.ceil((y + bh) * k) - y0];
		}
		var want = box(50, 40, 60, 60).concat(box(130, 40, 40, 60));
		check(r != null && r.join(" ") == want.join(" "), 'its input: what it draws, the bar of pointer-events none left out (${r == null ? "everywhere" : r.join(" ")}, of ${want.join(" ")})');
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

	// (X11, and Windows' --behind helder: an opaque helder window of a known
	// colour, under the transparent one; Windows' otherwise a plain window
	// of GDI's: Plain; the clicks through the transparent one, macOS's too;
	// none on Wayland, which places them)
	static final helderBehind = Sys.args().indexOf("--behind") >= 0 && Sys.args()[Sys.args().indexOf("--behind") + 1] == "helder";

	#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
	// (the window at a press: whether it ignores the mouse, where it finds the pointer)
	static function macState(w:UiWindow) {
		var view = w.window.surface.handle;
		Sys.println(OsThread.get(() -> {
			var win = helder.os.objc.Msg.id(view, helder.os.objc.ObjC.sel("window"));
			var o = helder.os.objc.Msg.point(win, helder.os.objc.ObjC.sel("mouseLocationOutsideOfEventStream"));
			var p = helder.os.objc.Msg.pointPointPtr(view, helder.os.objc.ObjC.sel("convertPoint:fromView:"), o, hxmc.unsafe.Ptr.nil());
			var b = helder.os.objc.Msg.rect(view, helder.os.objc.ObjC.sel("bounds"));
			var g = helder.os.objc.Msg.point(helder.os.objc.ObjC.cls("NSEvent"), helder.os.objc.ObjC.sel("mouseLocation"));
			'ShapeWindow: at the press: ignores the mouse ${helder.os.objc.Msg.b(win, helder.os.objc.ObjC.sel("ignoresMouseEvents"))}, the pointer in the view at ${p.x}, ${b.size.height - p.y} points (the screen\'s ${g.x}, ${g.y}), its input ${w.window.inputRects}, its scale ${w.window.scale}';
		}));
	}
	#end

	static function behindPlain():Bool {
		#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
		return !Plain.hwnd.isNull();
		#else
		return false;
		#end
	}

	static function behind():Null<UiWindow> {
		#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64" || hxmc.target == "linux-x86_64" || hxmc.target == "linux-arm64" || hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
		if (Sys.systemName() == "Linux" && Sys.getEnv("WAYLAND_DISPLAY") != null && Sys.getEnv("HELDER_X11") != "1") return null;
		#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
		if (!helderBehind) {
			Plain.open(200, 200, W * 2, H * 2);
			return null;
		}
		#end
		var d = new UiWindow("ShapeWindow desk", W * 2, H * 2, null, false);
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
		if (desk != null) desk.device.settle();
		w.device.settle();
		Sys.sleep(0.3);
		var p = w.window.position(), k = w.window.scale;
		var under = desk != null ? desk.window.surface.handle : Plain.hwnd;
		Plain.state(under, w.window.surface.handle, desk == null ? null : @:privateAccess (cast desk.device.impl : helder.gfx.d3d11.D3D11Backend).occluded);
		function at(x:Float, y:Float):Array<Int> {
			var c = Screen.pixel(Math.round(p.x * k + x * k), Math.round(p.y * k + y * k));
			return [c & 0xFF, c >> 8 & 0xFF, c >> 16 & 0xFF];
		}
		// (a helder window behind: its state told, the screen's pixels told, not checked)
		if (helderBehind) {
			Sys.println('ShapeWindow: behind a helder window, the screen: ${at(10, 10)} ${at(80, 70)} ${at(150, 70)} (told, not checked)');
			return;
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

// (a click at x, y points of a window, the system's own: the pointer moved
// there first, then pressed and let go. macOS: CGEventPost (the HID's,
// where a test may: CI, or SHAPE_INPUT=1, as it moves the user's pointer);
// Windows: SetCursorPos, SendInput (the same); X11: XTest; not on Wayland)
@:hxmc.unsafe(gc)
class Click {
	public static function can():Bool {
		#if (hxmc.target == "linux-x86_64" || hxmc.target == "linux-arm64")
		return Sys.getEnv("WAYLAND_DISPLAY") == null && Xtst.ok;
		#else
		var ok = Sys.getEnv("GITHUB_ACTIONS") == "true" || Sys.getEnv("SHAPE_INPUT") == "1";
		if (!ok) Sys.println("ShapeWindow: clicks not sent (they move the pointer; CI or SHAPE_INPUT=1): skipped");
		return ok;
		#end
	}

	public static function move(w:Window, x:Float, y:Float)
		send(w, x, y, 0);

	public static function press(w:Window, x:Float, y:Float) {
		send(w, x, y, 1);
		Sys.sleep(0.05);
		send(w, x, y, 2);
	}

	// (0: a move, 1: the left button down, 2: up)
	static function send(w:Window, x:Float, y:Float, what:Int) {
		var p = w.position();
		#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
		var at:hxmc.unsafe.Ptr<helder.os.objc.CGPoint> = hxmc.unsafe.LibC.malloc(16);
		at.value.x = p.x + x;
		at.value.y = p.y + y;
		var ev = TapCG.CGEventCreateMouseEvent(hxmc.unsafe.Ptr.nil(), [5, 1, 2][what], at.value, 0);
		TapCG.CGEventPost(0, ev);
		SystemLayersWindow.CF.CFRelease(ev);
		hxmc.unsafe.LibC.free(at);
		#elseif (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
		var k = w.scale;
		if (what == 0) {
			ScreenDc.SetCursorPos(Math.round((p.x + x) * k), Math.round((p.y + y) * k));
			return;
		}
		// (INPUT_MOUSE, MOUSEINPUT: dx, dy, mouseData, dwFlags LEFTDOWN 2 or LEFTUP 4)
		var input:hxmc.unsafe.Ptr<hxmc.unsafe.Int32> = hxmc.unsafe.LibC.malloc(40);
		hxmc.unsafe.LibC.memset(cast input, 0, 40);
		input[0] = 0;
		input[5] = what == 1 ? 2 : 4;
		ScreenDc.SendInput(1, cast input, 40);
		hxmc.unsafe.LibC.free(cast input);
		#elseif (hxmc.target == "linux-x86_64" || hxmc.target == "linux-arm64")
		var d = w.surface.display;
		if (what == 0) Xtst.XTestFakeMotionEvent(d, -1, p.x + Math.round(x), p.y + Math.round(y), 0) else Xtst.XTestFakeButtonEvent(d, 1, what == 1 ? 1 : 0, 0);
		Xlib.XFlush(d);
		#end
	}
}

#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics") extern class TapCG {
	static function CGEventCreateMouseEvent(source:hxmc.unsafe.Ptr, type:Int, p:helder.os.objc.CGPoint, button:Int):hxmc.unsafe.Ptr;
	static function CGEventPost(tap:Int, ev:hxmc.unsafe.Ptr):Void;
}
#end

#if (hxmc.target == "linux-x86_64" || hxmc.target == "linux-arm64")
// (libXtst, loaded when there)
@:build(helder.os.Dl.build())
@:hxmc.unsafe(gc)
class Xtst {
	static function XTestFakeMotionEvent(d:hxmc.unsafe.Ptr, screen:Int, x:Int, y:Int, delay:haxe.Int64):Int;
	static function XTestFakeButtonEvent(d:hxmc.unsafe.Ptr, button:Int, press:Int, delay:haxe.Int64):Int;

	public static final ok = load("libXtst.so.6") == null;
}
#end

#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
// (a plain window behind the transparent one: no swap chain, its class's
// brush green (0x00BBGGRR) painting it; made on the main thread, whose loop
// reads its messages; its state told before the screen is read: shown,
// minimised, where it is in the z-order under the transparent one, its
// own pixels through PrintWindow, a helder window's last present)
@:hxmc.unsafe(gc)
class Plain {
	public static var hwnd = hxmc.unsafe.Ptr.nil();

	public static function open(x:Int, y:Int, w:Int, h:Int)
		hwnd = OsThread.get(() -> hxmc.unsafe.Arena.scopedValue(a -> {
			var name = a.wstring("ShapeWindowBehind"), instance = helder.os.win32.User32.Kernel32.GetModuleHandleW(hxmc.unsafe.Ptr.nil());
			var wc = a.make(helder.os.win32.User32.WNDCLASSEXW);
			wc.value.cbSize = 80;
			wc.value.lpfnWndProc = hxmc.unsafe.Callback.addr(proc);
			wc.value.hInstance = instance;
			wc.value.hbrBackground = ScreenPixel.CreateSolidBrush(0x0000FF00);
			wc.value.lpszClassName = name;
			helder.os.win32.User32.User32.RegisterClassExW(wc);
			// (WS_POPUP | WS_VISIBLE; scaled as helder's windows place theirs: points times the system's DPI)
			var k = helder.os.win32.User32.User32.GetDpiForSystem() / 96;
			helder.os.win32.User32.User32.CreateWindowExW(0, name, name, (0x80000000 : Int) | 0x10000000, Math.round(x * k), Math.round(y * k), Math.round(w * k), Math.round(h * k),
				hxmc.unsafe.Ptr.nil(), hxmc.unsafe.Ptr.nil(), instance, hxmc.unsafe.Ptr.nil());
		}));

	// (its presses: WM_LBUTTONDOWN)
	public static var downs = 0;

	@:hxmc.callback static function proc(hwnd:hxmc.unsafe.Ptr, message:Int, wParam:haxe.Int64, lParam:haxe.Int64):haxe.Int64 {
		if (message == 0x0201) downs++;
		return helder.os.win32.User32.User32.DefWindowProcW(hwnd, message, wParam, lParam);
	}

	// (the transparent window's extended styles and the cursor at a press: WS_EX_LAYERED and TRANSPARENT while it passes)
	public static function styles(top:hxmc.unsafe.Ptr)
		OsThread.get(() -> hxmc.unsafe.Arena.scopedValue(a -> {
			var p = a.make(helder.os.win32.User32.POINT);
			ScreenDc.GetCursorPos(p);
			var c = {x: p.value.x, y: p.value.y};
			helder.os.win32.User32.User32.ScreenToClient(top, p);
			var ex = ScreenDc.GetWindowLongPtrW(top, -20).toI64();
			Sys.println('ShapeWindow: at the press the cursor at ${c.x}, ${c.y} (in it ${p.value.x}, ${p.value.y}), its extended style 0x${StringTools.hex(ex.toInt())}');
			0;
		}));

	public static function state(under:hxmc.unsafe.Ptr, top:hxmc.unsafe.Ptr, occluded:Null<Bool>)
		OsThread.get(() -> hxmc.unsafe.Arena.scopedValue(a -> {
			// (GW_HWNDNEXT 2: the windows under top, in order)
			var n = 0, at = -1, next = ScreenDc.GetWindow(top, 2);
			while (!next.isNull() && n < 200 && at < 0) {
				if (next == under) at = n;
				next = ScreenDc.GetWindow(next, 2);
				n++;
			}
			var r = a.make(helder.os.win32.User32.RECT), q = a.make(helder.os.win32.User32.RECT);
			helder.os.win32.User32.User32.GetWindowRect(under, r);
			helder.os.win32.User32.User32.GetWindowRect(top, q);
			// (its own pixels: PrintWindow, PW_RENDERFULLCONTENT 2, into a bitmap of its size, the middle read)
			var w = r.value.right - r.value.left, h = r.value.bottom - r.value.top, screen = ScreenDc.GetDC(hxmc.unsafe.Ptr.nil());
			var dc = helder.os.win32.User32.Gdi32.CreateCompatibleDC(screen), bmp = ScreenPixel.CreateCompatibleBitmap(screen, w, h);
			var old = helder.os.win32.User32.Gdi32.SelectObject(dc, bmp), printed = ScreenDc.PrintWindow(under, dc, 2), c = ScreenPixel.GetPixel(dc, w >> 1, h >> 1);
			helder.os.win32.User32.Gdi32.SelectObject(dc, old);
			helder.os.win32.User32.Gdi32.DeleteObject(bmp);
			helder.os.win32.User32.Gdi32.DeleteDC(dc);
			ScreenDc.ReleaseDC(hxmc.unsafe.Ptr.nil(), screen);
			Sys.println('ShapeWindow: behind it: visible ${ScreenDc.IsWindowVisible(under)}, minimised ${ScreenDc.IsIconic(under)}, '
				+ (at < 0 ? "not under it in the z-order" : 'under it, ${at} windows between') + ', at ${r.value.left}, ${r.value.top} to ${r.value.right}, ${r.value.bottom}'
				+ ' (the transparent one ${q.value.left}, ${q.value.top} to ${q.value.right}, ${q.value.bottom}), PrintWindow ${printed} its middle 0x${StringTools.hex(c, 6)}'
				+ (occluded == null ? "" : ', its last present ${occluded ? "DXGI_STATUS_OCCLUDED" : "shown"}'));
			0;
		}));
}

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
	static function SetCursorPos(x:Int, y:Int):Int;
	static function GetCursorPos(p:hxmc.unsafe.Ptr<helder.os.win32.User32.POINT>):Int;
	static function GetWindowLongPtrW(hwnd:hxmc.unsafe.Ptr, index:Int):hxmc.unsafe.Ptr;
	static function SendInput(count:Int, inputs:hxmc.unsafe.Ptr, size:Int):Int;
	static function GetWindow(hwnd:hxmc.unsafe.Ptr, cmd:Int):hxmc.unsafe.Ptr;
	static function IsWindowVisible(hwnd:hxmc.unsafe.Ptr):Int;
	static function IsIconic(hwnd:hxmc.unsafe.Ptr):Int;
	static function PrintWindow(hwnd:hxmc.unsafe.Ptr, dc:hxmc.unsafe.Ptr, flags:Int):Int;
}

@:hxmc.c @:hxmc.lib("gdi32") extern class ScreenPixel {
	static function GetPixel(dc:hxmc.unsafe.Ptr, x:Int, y:Int):Int;
	static function CreateSolidBrush(color:Int):hxmc.unsafe.Ptr;
	static function CreateCompatibleBitmap(dc:hxmc.unsafe.Ptr, w:Int, h:Int):hxmc.unsafe.Ptr;
}
#end
