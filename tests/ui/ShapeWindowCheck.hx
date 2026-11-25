import helder.gfx.Color;
import helder.os.*;
import helder.ui.*;
import helder.ui.draw.*;
#if (hxmc.target == "linux-x86_64" || hxmc.target == "linux-arm64")
import helder.os.linux.x11.Xlib;
#end

// A transparent window (helder.os.Window's transparent; bun run test
// window on macOS and Windows, wayland on Linux: tests/ui/shape.sh): an
// opaque red box and a half-transparent blue one on a clear background.
// Its frame read back keeps its alpha, premultiplied; then what the system
// shows, where a test can see it: macOS's capture of the window (its own:
// no permission, though a machine may give empty ones), Windows' screen
// over an opaque green window behind it (a plain one of GDI's; --behind
// helder: a helder window), X11's 32-bit pixels and the
// screen composed over a green window (where a compositing manager runs;
// else opaque, said so), weston's screenshot over its green background.
//   ShapeWindowCheck [--transparent no]: the system can't (X11 without a
//   compositing manager): opaque, as said
@:hxmc.unsafe(gc)
class ShapeWindowCheck {
	static inline var W = 200;
	static inline var H = 150;
	static var failed = 0;

	static function check(ok:Bool, what:String) {
		if (!ok) failed++;
		Sys.println('ShapeWindowCheck: ${ok ? "ok" : "FAIL"}: $what');
	}

	static function main() {
		var a = Sys.args(), t = a.indexOf("--transparent"), expect = t < 0 ? "yes" : a[t + 1];
		var desk = behind();
		var w = new helder.ui.UiWindow("ShapeWindowCheck", W, H, null, false, Standard, true);
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
		var step = 0, all = desk == null ? [w] : [desk, w], end = 40, downs = [0, 0], edge:Null<helder.ui.UiWindow> = null;
		var clickStart = 0, clickIndex = 0, retried = false;
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
				// (macOS: each window ordered front at its first frame, or 500 ms after it is made, the one
				// behind's maybe after this one's, another app's window maybe over both: their levels set,
				// over other apps' windows, this one over the one behind)
				#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
				if (desk != null) {
					level(desk.window, 3);
					level(w.window, 4);
				}
				#end
				system(w, desk);
				if (w.window.transparent) inputs(w);
				backdrops(w);
				if (w.window.transparent && (desk != null || behindPlain()) && Click.can()) {
					clickStart = step + 1;
					end = -1;
				}
			}
			// (a click on the box: its own; then where it is clear: the window
			// behind's, which it activates and raises, so it comes last)
			if (clickStart > 0) {
				var through = clickIndex == 1;
				var x = through ? 10.0 : 80.0, y = through ? 10.0 : 70.0;
				var s0 = clickStart;
				// (twice: a runner's first posted move was seen dropped)
				if (step == s0 || step == s0 + 2) Click.move(w.window, x, y);
				if (step == s0 + 4) {
					downs = [0, 0];
					#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
					Plain.downs = 0;
					Plain.styles(w.window.surface.handle);
					#elseif (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
					macState(w);
					#end
					Click.press(w.window, x, y);
				}
				if (step == s0 + 12) {
					#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
					downs[0] += Plain.downs;
					#end
					var passed = through ? downs[0] >= 1 && downs[1] == 0 : downs[1] >= 1 && downs[0] == 0;
					var what = 'a click ${through ? "where it is clear: the window behind's" : "on the box: its own"} (presses: behind ${downs[0]}, it ${downs[1]})';
					if (!passed && !retried) {
						Sys.println('ShapeWindowCheck: first attempt failed: $what; retrying once');
						retried = true;
						clickStart = step + 2;
					} else {
						check(passed, what);
						retried = false;
						clickIndex++;
						clickStart = clickIndex < 2 ? step + 2 : 0;
						if (clickStart == 0) end = step + 3;
					}
				}
			}
			// (then a window at the work area's right edge, as the time tracker's)
			if (step == end && edge == null) {
				edge = edgeWindow();
				all.push(edge);
				end += 30;
			} else if (step == end) {
				edgeChecks(edge);
				Sys.println("ShapeWindowCheck: " + (failed == 0 ? "ok" : '$failed FAILED'));
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

	// (the system's material behind it, as the system tells: macOS's view
	// under the layer's, Windows' DWMWA_SYSTEMBACKDROP_TYPE, X11's property
	// (the atom made first, as KWin does); none where the system has none)
	static function backdrops(w:helder.ui.UiWindow) {
		var win = w.window;
		if (!win.transparent) {
			win.backdrop = WindowBackdrop.Blur;
			check(win.backdrop == WindowBackdrop.None, "backdrop: none on an opaque window");
			return;
		}
		#if (hxmc.target == "linux-x86_64" || hxmc.target == "linux-arm64")
		// (X11: none without KWin's atom; then the atom made, as KWin does, and the property set)
		if (win.surface.kind == X11) {
			win.backdrop = WindowBackdrop.Blur;
			check(win.backdrop == WindowBackdrop.None, "backdrop: none on X11 without KWin");
			hxmc.unsafe.Arena.scoped(a -> Xlib.XInternAtom(win.surface.display, a.cstring("_KDE_NET_WM_BLUR_BEHIND_REGION"), 0));
		}
		#end
		for (b in [WindowBackdrop.Blur, WindowBackdrop.Mica, WindowBackdrop.Glass]) {
			win.backdrop = b;
			var got = win.backdrop, seen = shows(win, b);
			if (got == WindowBackdrop.None) check(seen == null || seen == WindowBackdrop.None, 'backdrop $b: not here, none left (${seen ?? "none to read"})');
			else check(seen == b, 'backdrop $b: the system\'s ($seen)');
		}
		win.backdrop = WindowBackdrop.None;
		var left = shows(win, WindowBackdrop.None);
		check(win.backdrop == WindowBackdrop.None && (left == null || left == WindowBackdrop.None), "backdrop none: the system's gone");
	}

	// (the backdrop the system has for the window, as its APIs say; null: none to read)
	static function shows(win:Window, asked:WindowBackdrop):Null<WindowBackdrop> {
		#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
		var view = win.surface.handle;
		return OsThread.get(() -> {
			var content = helder.os.apple.objc.Msg.id(helder.os.apple.objc.Msg.id(view, helder.os.apple.objc.ObjC.sel("window")), helder.os.apple.objc.ObjC.sel("contentView"));
			var subs = helder.os.apple.objc.Msg.id(content, helder.os.apple.objc.ObjC.sel("subviews"));
			var first = helder.os.apple.objc.Msg.idInt(subs, helder.os.apple.objc.ObjC.sel("objectAtIndex:"), 0);
			var name = helder.os.apple.objc.ObjC.string(helder.os.apple.objc.Msg.id(helder.os.apple.objc.Msg.id(first, helder.os.apple.objc.ObjC.sel("className")), helder.os.apple.objc.ObjC.sel("description")));
			if (name == "NSGlassEffectView") return WindowBackdrop.Glass;
			if (name != "NSVisualEffectView") return WindowBackdrop.None;
			var m = helder.os.apple.objc.Msg.i(first, helder.os.apple.objc.ObjC.sel("material")).toInt();
			var behind = helder.os.apple.objc.Msg.i(first, helder.os.apple.objc.ObjC.sel("blendingMode")).toInt() == 0;
			return !behind ? WindowBackdrop.None : m == 13 ? WindowBackdrop.Blur : m == 21 ? WindowBackdrop.Mica : WindowBackdrop.None;
		});
		#elseif (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
		var v:hxmc.unsafe.Ptr<hxmc.unsafe.Int32> = hxmc.unsafe.LibC.malloc(4);
		v.value = 0;
		var hr = ScreenDwm.DwmGetWindowAttribute(win.surface.handle, 38, cast v, 4), t = v.value;
		hxmc.unsafe.LibC.free(cast v);
		return hr < 0 ? null : t == 3 ? WindowBackdrop.Blur : t == 2 ? WindowBackdrop.Mica : WindowBackdrop.None;
		#elseif (hxmc.target == "linux-x86_64" || hxmc.target == "linux-arm64")
		if (win.surface.kind != X11) return null;
		var d = win.surface.display;
		var atom = hxmc.unsafe.Arena.scopedValue(a -> Xlib.XInternAtom(d, a.cstring("_KDE_NET_WM_BLUR_BEHIND_REGION"), 1));
		if (atom == 0) return null;
		return hxmc.unsafe.Arena.scopedValue(a -> {
			var type:hxmc.unsafe.Ptr<haxe.Int64> = a.alloc(8), format:hxmc.unsafe.Ptr<hxmc.unsafe.Int32> = a.alloc(4), n:hxmc.unsafe.Ptr<haxe.Int64> = a.alloc(8),
				after:hxmc.unsafe.Ptr<haxe.Int64> = a.alloc(8), data:hxmc.unsafe.Ptr<hxmc.unsafe.Ptr> = a.alloc(8);
			type.value = 0;
			Xlib.XGetWindowProperty(d, win.surface.handle.toI64(), atom, 0, 16, 0, 0, type, format, n, after, data);
			if (!data.value.isNull()) Xlib.XFree(data.value);
			type.value == X.XA_CARDINAL ? asked : WindowBackdrop.None;
		});
		#else
		return null;
		#end
	}

	static inline var EDGE = 120;

	// (borderless, transparent, over the others, out of the task bar, full
	// height at the right of its screen's work area)
	static function edgeWindow():helder.ui.UiWindow {
		var e = new helder.ui.UiWindow("ShapeWindowCheck edge", EDGE, 200, null, false, None, true);
		e.background = Color.TRANSPARENT;
		var strip = new Node();
		strip.style.set({position: Absolute, right: 0, top: 0, bottom: 0, width: 8, background: 0xFFFF0000});
		e.root.append(strip);
		e.window.onTop = true;
		e.window.taskbar = false;
		var a = e.window.workArea();
		if (a != null) {
			e.window.resize(EDGE, a.height);
			e.window.moveTo(a.x + a.width - EDGE, a.y);
		}
		return e;
	}

	static function edgeChecks(e:helder.ui.UiWindow) {
		var win = e.window, a = win.workArea(), p = win.position();
		if (a == null) Sys.println("ShapeWindowCheck: the edge window: no work area here (Wayland places windows): its place not checked");
		else {
			check(a.width > 0 && a.height > 0, 'the work area: ${a.x}, ${a.y}, ${a.width} x ${a.height}');
			check(p != null && p.x == a.x + a.width - EDGE && p.y == a.y, 'the edge window at the work area\'s right edge (${p.x}, ${p.y})');
			var h = Math.round(win.height / win.scale);
			check(Math.abs(h - a.height) <= 1, 'the edge window full height in it ($h of ${a.height})');
		}
		#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
		var view = win.surface.handle;
		var got = OsThread.get(() -> {
			var w = helder.os.apple.objc.Msg.id(view, helder.os.apple.objc.ObjC.sel("window"));
			[helder.os.apple.objc.Msg.i(w, helder.os.apple.objc.ObjC.sel("styleMask")).toInt(), helder.os.apple.objc.Msg.i(w, helder.os.apple.objc.ObjC.sel("level")).toInt(),
				helder.os.apple.objc.Msg.i(w, helder.os.apple.objc.ObjC.sel("collectionBehavior")).toInt(), helder.os.apple.objc.Msg.b(w, helder.os.apple.objc.ObjC.sel("isExcludedFromWindowsMenu")) ? 1 : 0,
				helder.os.apple.objc.Msg.b(w, helder.os.apple.objc.ObjC.sel("canBecomeKeyWindow")) ? 1 : 0];
		});
		check(got[0] == 0 && got[4] == 1, 'macOS: borderless, and may be key (style ${got[0]}, key ${got[4]})');
		check(got[1] == 3, 'macOS: on top, the floating level (${got[1]})');
		check(got[2] & (1 << 6) != 0 && got[3] == 1, 'macOS: out of the window cycle and the Window menu (${got[2]}, ${got[3]})');
		#elseif (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
		var st = ScreenDc.GetWindowLongPtrW(win.surface.handle, -16).toI64(), ex = ScreenDc.GetWindowLongPtrW(win.surface.handle, -20).toI64();
		check(st & (0x80000000 : haxe.Int64) != 0 && st & 0xC00000 == 0, 'Windows: WS_POPUP, no caption (style 0x${StringTools.hex(st.toInt())})');
		check(ex & 0x8 != 0, 'Windows: on top, WS_EX_TOPMOST (0x${StringTools.hex(ex.toInt())})');
		check(ex & 0x80 != 0, 'Windows: out of the task bar, WS_EX_TOOLWINDOW');
		#elseif (hxmc.target == "linux-x86_64" || hxmc.target == "linux-arm64")
		if (win.surface.kind == X11) {
			var d = win.surface.display, hints = hxmc.unsafe.Arena.scopedValue(a -> Xlib.XInternAtom(d, a.cstring("_MOTIF_WM_HINTS"), 1));
			var dec = hxmc.unsafe.Arena.scopedValue(a -> {
				var type:hxmc.unsafe.Ptr<haxe.Int64> = a.alloc(8), format:hxmc.unsafe.Ptr<hxmc.unsafe.Int32> = a.alloc(4), n:hxmc.unsafe.Ptr<haxe.Int64> = a.alloc(8),
					after:hxmc.unsafe.Ptr<haxe.Int64> = a.alloc(8), data:hxmc.unsafe.Ptr<hxmc.unsafe.Ptr> = a.alloc(8);
				Xlib.XGetWindowProperty(d, win.surface.handle.toI64(), hints, 0, 5, 0, 0, type, format, n, after, data);
				var v = data.value.isNull() || n.value < 3 ? -1 : haxe.Int64.toInt((cast data.value : hxmc.unsafe.Ptr<haxe.Int64>)[2]);
				if (!data.value.isNull()) Xlib.XFree(data.value);
				v;
			});
			check(dec == 0, 'X11: no decorations, Motif\'s hints ($dec)');
			Sys.println("ShapeWindowCheck: X11: on top and out of the task bar asked of the window manager (_NET_WM_STATE): none here to read them");
		} else {
			check(!win.onTop && win.taskbar, "Wayland: on top and out of the task bar: not to be asked (false, true)");
		}
		#end
	}

	// (where it takes the pointer: the boxes it draws, in pixels, not the bar of pointer-events none)
	static function inputs(w:helder.ui.UiWindow) {
		var k = w.scale, given = w.window.inputRects;
		var r = given == null ? null : [for (b in given) for (v in [b.x, b.y, b.width, b.height]) Std.int(v)];
		function box(x:Float, y:Float, bw:Float, bh:Float):Array<Int> {
			var x0 = Math.floor(x * k), y0 = Math.floor(y * k);
			return [x0, y0, Math.ceil((x + bw) * k) - x0, Math.ceil((y + bh) * k) - y0];
		}
		var want = box(50, 40, 60, 60).concat(box(130, 40, 40, 60));
		check(r != null && r.join(" ") == want.join(" "), 'its input: what it draws, the bar of pointer-events none left out (${r == null ? "everywhere" : r.join(" ")}, of ${want.join(" ")})');
	}

	// (the frame read back, RGBA: at points x, y)
	static function frame(w:helder.ui.UiWindow) {
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
	static function level(win:Window, n:Int) {
		var view = win.surface.handle;
		OsThread.get(() -> {
			var w = helder.os.apple.objc.Msg.id(view, helder.os.apple.objc.ObjC.sel("window"));
			helder.os.apple.objc.Msg.vInt(w, helder.os.apple.objc.ObjC.sel("setLevel:"), n);
			helder.os.apple.objc.Msg.v(w, helder.os.apple.objc.ObjC.sel("orderFrontRegardless"));
			0;
		});
	}

	// (the window at a press: whether it ignores the mouse, where it finds the pointer)
	static function macState(w:helder.ui.UiWindow) {
		var view = w.window.surface.handle;
		Sys.println(OsThread.get(() -> {
			var win = helder.os.apple.objc.Msg.id(view, helder.os.apple.objc.ObjC.sel("window"));
			var o = helder.os.apple.objc.Msg.point(win, helder.os.apple.objc.ObjC.sel("mouseLocationOutsideOfEventStream"));
			var p = helder.os.apple.objc.Msg.pointPointPtr(view, helder.os.apple.objc.ObjC.sel("convertPoint:fromView:"), o, hxmc.unsafe.Ptr.nil());
			var b = helder.os.apple.objc.Msg.rect(view, helder.os.apple.objc.ObjC.sel("bounds"));
			var g = helder.os.apple.objc.Msg.point(helder.os.apple.objc.ObjC.cls("NSEvent"), helder.os.apple.objc.ObjC.sel("mouseLocation"));
			// (the window server's window there, and ours front to back)
			var M = helder.os.apple.objc.Msg, S = helder.os.apple.objc.ObjC;
			var at = M.iPointInt(S.cls("NSWindow"), S.sel("windowNumberAtPoint:belowWindowWithWindowNumber:"), g, 0).toInt();
			var ordered = M.id(M.id(S.cls("NSApplication"), S.sel("sharedApplication")), S.sel("orderedWindows"));
			var order = [for (i in 0...M.i(ordered, S.sel("count")).toInt()) {
				var o = M.idInt(ordered, S.sel("objectAtIndex:"), i);
				M.i(o, S.sel("windowNumber")).toInt() + (M.b(o, S.sel("ignoresMouseEvents")) ? " (ignores)" : "") + " level " + M.i(o, S.sel("level")).toInt();
			}];
			Sys.println('ShapeWindowCheck: at the press: the window server\'s window there ${at}, this one ${M.i(win, S.sel("windowNumber")).toInt()}, ours front to back ${order.join(", ")}');
			'ShapeWindowCheck: at the press: ignores the mouse ${helder.os.apple.objc.Msg.b(win, helder.os.apple.objc.ObjC.sel("ignoresMouseEvents"))}, the pointer in the view at ${p.x}, ${b.size.height - p.y} points (the screen\'s ${g.x}, ${g.y}), its input ${w.window.inputRects}, its scale ${w.window.scale}';
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

	static function behind():Null<helder.ui.UiWindow> {
		#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64" || hxmc.target == "linux-x86_64" || hxmc.target == "linux-arm64" || hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
		if (Sys.systemName() == "Linux" && Sys.getEnv("WAYLAND_DISPLAY") != null && Sys.getEnv("HELDER_X11") != "1") return null;
		#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
		if (!helderBehind) {
			Plain.open(200, 200, W * 2, H * 2);
			return null;
		}
		#end
		var d = new helder.ui.UiWindow("ShapeWindowCheck desk", W * 2, H * 2, null, false);
		d.background = Color.rgb(0x00FF00);
		d.window.moveTo(200, 200);
		return d;
		#else
		return null;
		#end
	}

	// (what the system shows)
	static function system(w:helder.ui.UiWindow, desk:Null<helder.ui.UiWindow>) {
		if (!w.window.transparent) return;
		#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
		var view = w.window.surface.handle;
		var id = OsThread.get(() -> helder.os.apple.objc.Msg.i(helder.os.apple.objc.Msg.id(view, helder.os.apple.objc.ObjC.sel("window")), helder.os.apple.objc.ObjC.sel("windowNumber")).toInt());
		var img = SystemLayersWindowCheck.Capture.window(id);
		if (img == null) return Sys.println("ShapeWindowCheck: no window capture here: skipped");
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
		if (!any) return Sys.println("ShapeWindowCheck: the window's capture empty (no Screen Recording here): skipped");
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
		screen(helderBehind ? "the screen over a helder window" : "the screen", at);
		#elseif (hxmc.target == "linux-x86_64" || hxmc.target == "linux-arm64")
		if (w.window.surface.kind == X11) x11(w) else wayland(w);
		#end
	}

	#if (hxmc.target == "linux-x86_64" || hxmc.target == "linux-arm64")
	// (X11: the window's own pixels, 32 bits with their alpha; the root's,
	// composed by the compositing manager, the window behind through the clear ones)
	static function x11(w:helder.ui.UiWindow) {
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
	static function wayland(w:helder.ui.UiWindow) {
		var dir = Sys.getEnv("XDG_RUNTIME_DIR") + "/shape-" + Std.random(1 << 30);
		sys.FileSystem.createDirectory(dir);
		var old = Sys.getCwd();
		Sys.setCwd(dir);
		var code = Sys.command("weston-screenshooter > /dev/null 2>&1");
		Sys.setCwd(old);
		var shots = [for (f in sys.FileSystem.readDirectory(dir)) if (StringTools.endsWith(f, ".png")) f];
		if (code != 0 || shots.length == 0) return Sys.println("ShapeWindowCheck: no weston screenshot (weston --debug, weston-screenshooter): skipped");
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
	// (whether can allowed them: nothing is sent before, as it moves the user's pointer)
	static var allowed = false;

	public static function can():Bool {
		allowed = Sys.getEnv("GITHUB_ACTIONS") == "true" || Sys.getEnv("HELDER_TEST_INPUT") == "1" || Sys.getEnv("SHAPE_INPUT") == "1";
		if (!allowed) Sys.println("ShapeWindowCheck: clicks skipped (set HELDER_TEST_INPUT=1 to allow moving the pointer)");
		#if (hxmc.target == "linux-x86_64" || hxmc.target == "linux-arm64")
		allowed = allowed && Sys.getEnv("WAYLAND_DISPLAY") == null && Xtst.ok;
		#end
		return allowed;
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
		if (!allowed) return;
		var p = w.position();
		#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
		var at:hxmc.unsafe.Ptr<helder.os.apple.objc.CGPoint> = hxmc.unsafe.LibC.malloc(16);
		at.value.x = p.x + x;
		at.value.y = p.y + y;
		var ev = TapCG.CGEventCreateMouseEvent(hxmc.unsafe.Ptr.nil(), [5, 1, 2][what], at.value, 0);
		TapCG.CGEventPost(0, ev);
		SystemLayersWindowCheck.CF.CFRelease(ev);
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
	static function CGEventCreateMouseEvent(source:hxmc.unsafe.Ptr, type:Int, p:helder.os.apple.objc.CGPoint, button:Int):hxmc.unsafe.Ptr;
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
			var name = a.wstring("ShapeWindowBehind"), instance = helder.os.windows.User32.Kernel32.GetModuleHandleW(hxmc.unsafe.Ptr.nil());
			var wc = a.make(helder.os.windows.User32.WNDCLASSEXW);
			wc.value.cbSize = 80;
			wc.value.lpfnWndProc = hxmc.unsafe.Callback.addr(proc);
			wc.value.hInstance = instance;
			wc.value.hbrBackground = ScreenPixel.CreateSolidBrush(0x0000FF00);
			wc.value.lpszClassName = name;
			helder.os.windows.User32.User32.RegisterClassExW(wc);
			// (WS_POPUP | WS_VISIBLE; scaled as helder's windows place theirs: points times the system's DPI)
			var k = helder.os.windows.User32.User32.GetDpiForSystem() / 96;
			helder.os.windows.User32.User32.CreateWindowExW(0, name, name, (0x80000000 : Int) | 0x10000000, Math.round(x * k), Math.round(y * k), Math.round(w * k), Math.round(h * k),
				hxmc.unsafe.Ptr.nil(), hxmc.unsafe.Ptr.nil(), instance, hxmc.unsafe.Ptr.nil());
		}));

	// (its presses: WM_LBUTTONDOWN)
	public static var downs = 0;

	@:hxmc.callback static function proc(hwnd:hxmc.unsafe.Ptr, message:Int, wParam:haxe.Int64, lParam:haxe.Int64):haxe.Int64 {
		if (message == 0x0201) downs++;
		return helder.os.windows.User32.User32.DefWindowProcW(hwnd, message, wParam, lParam);
	}

	// (the transparent window's extended styles and the cursor at a press: WS_EX_LAYERED and TRANSPARENT while it passes)
	public static function styles(top:hxmc.unsafe.Ptr)
		OsThread.get(() -> hxmc.unsafe.Arena.scopedValue(a -> {
			var p = a.make(helder.os.windows.User32.POINT);
			ScreenDc.GetCursorPos(p);
			var c = {x: p.value.x, y: p.value.y};
			helder.os.windows.User32.User32.ScreenToClient(top, p);
			var ex = ScreenDc.GetWindowLongPtrW(top, -20).toI64();
			Sys.println('ShapeWindowCheck: at the press the cursor at ${c.x}, ${c.y} (in it ${p.value.x}, ${p.value.y}), its extended style 0x${StringTools.hex(ex.toInt())}');
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
			var r = a.make(helder.os.windows.User32.RECT), q = a.make(helder.os.windows.User32.RECT);
			helder.os.windows.User32.User32.GetWindowRect(under, r);
			helder.os.windows.User32.User32.GetWindowRect(top, q);
			// (its own pixels: PrintWindow, PW_RENDERFULLCONTENT 2, into a bitmap of its size, the middle read)
			var w = r.value.right - r.value.left, h = r.value.bottom - r.value.top, screen = ScreenDc.GetDC(hxmc.unsafe.Ptr.nil());
			var dc = helder.os.windows.User32.Gdi32.CreateCompatibleDC(screen), bmp = ScreenPixel.CreateCompatibleBitmap(screen, w, h);
			var old = helder.os.windows.User32.Gdi32.SelectObject(dc, bmp), printed = ScreenDc.PrintWindow(under, dc, 2), c = ScreenPixel.GetPixel(dc, w >> 1, h >> 1);
			helder.os.windows.User32.Gdi32.SelectObject(dc, old);
			helder.os.windows.User32.Gdi32.DeleteObject(bmp);
			helder.os.windows.User32.Gdi32.DeleteDC(dc);
			ScreenDc.ReleaseDC(hxmc.unsafe.Ptr.nil(), screen);
			Sys.println('ShapeWindowCheck: behind it: visible ${ScreenDc.IsWindowVisible(under)}, minimised ${ScreenDc.IsIconic(under)}, '
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
	static function GetCursorPos(p:hxmc.unsafe.Ptr<helder.os.windows.User32.POINT>):Int;
	static function GetWindowLongPtrW(hwnd:hxmc.unsafe.Ptr, index:Int):hxmc.unsafe.Ptr;
	static function SendInput(count:Int, inputs:hxmc.unsafe.Ptr, size:Int):Int;
	static function GetWindow(hwnd:hxmc.unsafe.Ptr, cmd:Int):hxmc.unsafe.Ptr;
	static function IsWindowVisible(hwnd:hxmc.unsafe.Ptr):Int;
	static function IsIconic(hwnd:hxmc.unsafe.Ptr):Int;
	static function PrintWindow(hwnd:hxmc.unsafe.Ptr, dc:hxmc.unsafe.Ptr, flags:Int):Int;
}

@:hxmc.c @:hxmc.lib("dwmapi") extern class ScreenDwm {
	static function DwmGetWindowAttribute(hwnd:hxmc.unsafe.Ptr, attribute:Int, value:hxmc.unsafe.Ptr, size:Int):Int;
}

@:hxmc.c @:hxmc.lib("gdi32") extern class ScreenPixel {
	static function GetPixel(dc:hxmc.unsafe.Ptr, x:Int, y:Int):Int;
	static function CreateSolidBrush(color:Int):hxmc.unsafe.Ptr;
	static function CreateCompatibleBitmap(dc:hxmc.unsafe.Ptr, w:Int, h:Int):hxmc.unsafe.Ptr;
}
#end
