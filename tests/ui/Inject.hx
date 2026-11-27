import hxmc.unsafe.*;

// Scroll input put where the system's comes in, from a thread of its own,
// while the program is busy (AsyncScrollWindowCheck): a wheel's pixels every
// 16 ms at the window's middle. macOS: NSEvents made from CGEvents, posted
// to the application's queue, which the main thread reads (MacWindow's
// pump); X11: wheel presses sent to the window by a connection of its
// own; Windows: a wheel's notches from SendInput, the cursor at the
// window's middle (the window under it gets them); elsewhere
// (Inject.supported false) none yet.
@:hxmc.unsafe(gc)
class Inject {
	final done = new sys.thread.Lock();
	public var sent(default, null) = 0;

	function new() {}

	public static var supported(get, never):Bool;

	static function get_supported():Bool {
		if (Sys.getEnv("GITHUB_ACTIONS") != "true" && Sys.getEnv("HELDER_TEST_INPUT") != "1") return false;
		#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
		return true;
		#elseif (hxmc.target == "linux-x86_64" || hxmc.target == "linux-arm64")
		return Sys.getEnv("WAYLAND_DISPLAY") == null;
		#elseif (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
		return true;
		#else
		return false;
		#end
	}

	// every `every` seconds for ms, each sent's time (haxe.Timer.stamp) to sent
	public static function start(w:helder.os.Window, ms:Int, every = 0.016, ?onSent:Float->Void):Inject {
		var i = new Inject();
		if (!supported) {
			i.done.release();
			return i;
		}
		#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
		var view = w.surface.handle;
		var at = helder.os.OsThread.get(() -> {
			var win = helder.os.apple.objc.Msg.id(view, helder.os.apple.objc.ObjC.sel("window"));
			var r = helder.os.apple.objc.Msg.rect(win, helder.os.apple.objc.ObjC.sel("frame"));
			var screen = helder.os.apple.objc.Msg.id(win, helder.os.apple.objc.ObjC.sel("screen"));
			var s = helder.os.apple.objc.Msg.rect(screen, helder.os.apple.objc.ObjC.sel("frame"));
			[helder.os.apple.objc.Msg.i(win, helder.os.apple.objc.ObjC.sel("windowNumber")).toInt() * 1.0, r.origin.x + r.size.width / 2,
				s.size.height - (r.origin.y + r.size.height / 2)];
		});
		sys.thread.Thread.create(() -> {
			var until = haxe.Timer.stamp() + ms / 1000, app = helder.os.apple.objc.Msg.id(helder.os.apple.objc.ObjC.cls("NSApplication"), helder.os.apple.objc.ObjC.sel("sharedApplication"));
			while (haxe.Timer.stamp() < until) {
				var pool = helder.os.apple.objc.Runtime.objc_autoreleasePoolPush();
				var cg = CG.CGEventCreateScrollWheelEvent2(Ptr.nil(), 0, 1, -12, 0, 0);
				var p:Ptr<helder.os.apple.objc.CGPoint> = LibC.malloc(16);
				p.value.x = at[1];
				p.value.y = at[2];
				CG.CGEventSetLocation(cg, p.value);
				LibC.free(p);
				CG.CGEventSetIntegerValueField(cg, 91, Std.int(at[0]));
				CG.CGEventSetIntegerValueField(cg, 92, Std.int(at[0]));
				if (onSent != null) onSent(haxe.Timer.stamp());
				CG.CGEventPostToPid(Libc.getpid(), cg);
				i.sent++;
				CF.CFRelease(cg);
				helder.os.apple.objc.Runtime.objc_autoreleasePoolPop(pool);
				Sys.sleep(every);
			}
			i.done.release();
		});
		#elseif (hxmc.target == "linux-x86_64" || hxmc.target == "linux-arm64")
		// (X11: wheel presses sent to the window from a connection of its own, as another client would)
		var id = w.surface.handle.toI64(), cx = Std.int(w.width / 2), cy = Std.int(w.height / 2);
		sys.thread.Thread.create(() -> {
			var d = helder.os.linux.x11.Xlib.XOpenDisplay(Ptr.nil());
			var until = haxe.Timer.stamp() + ms / 1000;
			var raw:Ptr = LibC.malloc(192);
			while (!d.isNull() && haxe.Timer.stamp() < until) {
				if (onSent != null) onSent(haxe.Timer.stamp());
				for (press in [true, false]) {
					LibC.memset(raw, 0, 192);
					var b:Ptr<helder.os.linux.x11.Xlib.XKeyEvent> = raw;
					b.value.type = press ? 4 : 5;
					b.value.display = d;
					b.value.window = id;
					b.value.x = cx;
					b.value.y = cy;
					b.value.keycode = 5;
					b.value.same_screen = 1;
					helder.os.linux.x11.Xlib.XSendEvent(d, id, 0, 0, raw);
				}
				helder.os.linux.x11.Xlib.XFlush(d);
				i.sent++;
				Sys.sleep(every);
			}
			LibC.free(raw);
			if (!d.isNull()) helder.os.linux.x11.Xlib.XCloseDisplay(d);
			i.done.release();
		});
		#elseif (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
		var hwnd = w.surface.handle, cx = Std.int(w.width / 2), cy = Std.int(w.height / 2);
		sys.thread.Thread.create(() -> {
			var p:Ptr<Int32> = LibC.malloc(8);
			p[0] = cx;
			p[1] = cy;
			helder.os.windows.User32.ClientToScreen(hwnd, cast p);
			WinInput.SetCursorPos(p[0], p[1]);
			LibC.free(cast p);
			// (INPUT: INPUT_MOUSE, then MOUSEINPUT: dx, dy, mouseData, dwFlags MOUSEEVENTF_WHEEL, time, dwExtraInfo)
			var input:Ptr<Int32> = LibC.malloc(40);
			LibC.memset(cast input, 0, 40);
			input[4] = -120;
			input[5] = 0x0800;
			var until = haxe.Timer.stamp() + ms / 1000;
			while (haxe.Timer.stamp() < until) {
				if (onSent != null) onSent(haxe.Timer.stamp());
				if (WinInput.SendInput(1, cast input, 40) == 1) i.sent++;
				Sys.sleep(every);
			}
			LibC.free(cast input);
			i.done.release();
		});
		#else
		i.done.release();
		#end
		return i;
	}

	public function join()
		done.wait();

	#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
	// a wheel's n pixels (else a press and its release: click) at x, y points of
	// w's content, as NSEvents posted to the application's own queue, which
	// the main thread reads (no window server: a single CGEventPostToPid one
	// is dropped now and then); false, nothing sent, where not supported
	public static function at(w:helder.os.Window, x:Float, y:Float, click:Bool, pixels = 4):Bool {
		if (!supported) return false;
		var view = w.surface.handle;
		helder.os.OsThread.get(() -> {
			var M = helder.os.apple.objc.Msg, O = helder.os.apple.objc.ObjC;
			var pool = helder.os.apple.objc.Runtime.objc_autoreleasePoolPush();
			var win = M.id(view, O.sel("window")), app = M.id(O.cls("NSApplication"), O.sel("sharedApplication"));
			var n = M.i(win, O.sel("windowNumber"));
			var c = M.rect(M.id(win, O.sel("contentView")), O.sel("frame"));
			var loc:Ptr<helder.os.apple.objc.CGPoint> = LibC.malloc(16);
			// (the window's coordinates: y up)
			loc.value.x = x;
			loc.value.y = c.size.height - y;
			if (click) {
				// (NSEventTypeLeftMouseDown, NSEventTypeLeftMouseUp)
				for (type in [1, 2])
					M.vPtrBool(app, O.sel("postEvent:atStart:"), MouseMsg.mouse(O.cls("NSEvent"),
						O.sel("mouseEventWithType:location:modifierFlags:timestamp:windowNumber:context:eventNumber:clickCount:pressure:"), type, loc.value, 0,
						M.f(M.id(O.cls("NSProcessInfo"), O.sel("processInfo")), O.sel("systemUptime")), n, Ptr.nil(), 0, 1, type == 1 ? 1.0 : 0.0), false);
			} else {
				// (a wheel's CGEvent at the screen's point, in the window)
				var s = M.pointPoint(win, O.sel("convertPointToScreen:"), loc.value);
				var first = M.rect(M.idInt(M.id(O.cls("NSScreen"), O.sel("screens")), O.sel("objectAtIndex:"), 0), O.sel("frame"));
				var e = CG.CGEventCreateScrollWheelEvent2(Ptr.nil(), 0, 1, -pixels, 0, 0);
				loc.value.x = s.x;
				loc.value.y = first.size.height - s.y;
				CG.CGEventSetLocation(e, loc.value);
				CG.CGEventSetIntegerValueField(e, 91, n);
				CG.CGEventSetIntegerValueField(e, 92, n);
				M.vPtrBool(app, O.sel("postEvent:atStart:"), M.idPtr(O.cls("NSEvent"), O.sel("eventWithCGEvent:"), e), false);
				CF.CFRelease(e);
			}
			LibC.free(loc);
			helder.os.apple.objc.Runtime.objc_autoreleasePoolPop(pool);
			true;
		});
		return true;
	}

	// what the window server shows of a window now: its pixels as presented,
	// the system's layers composed (BGRA, rows stride bytes apart, its title
	// bar included; one buffer, the next call's too); null where they can't be read
	public static function screen(w:helder.os.Window):Null<{px:haxe.io.Bytes, width:Int, height:Int, stride:Int}> {
		if (!supported) return null;
		#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
		var view = w.surface.handle;
		var M = helder.os.apple.objc.Msg, O = helder.os.apple.objc.ObjC;
		var pool = helder.os.apple.objc.Runtime.objc_autoreleasePoolPush();
		var n = M.i(M.id(view, O.sel("window")), O.sel("windowNumber")).toInt();
		var r:Ptr<helder.os.apple.objc.CGRect> = LibC.malloc(32);
		// (CGRectNull: the window's own bounds)
		r.value.origin.x = Math.POSITIVE_INFINITY;
		r.value.origin.y = Math.POSITIVE_INFINITY;
		r.value.size.width = 0;
		r.value.size.height = 0;
		var img = CG.CGWindowListCreateImage(r.value, 8, n, 1);
		LibC.free(r);
		var out:Null<{px:haxe.io.Bytes, width:Int, height:Int, stride:Int}> = null;
		if (!img.isNull()) {
			var data = CG.CGDataProviderCopyData(CG.CGImageGetDataProvider(img));
			if (!data.isNull()) {
				var len = M.i(data, O.sel("length")).toInt();
				if (shown.length < len) shown = haxe.io.Bytes.alloc(len);
				BytesPtr.copyIn(shown, 0, M.id(data, O.sel("bytes")), len);
				out = {px: shown, width: CG.CGImageGetWidth(img).toInt(), height: CG.CGImageGetHeight(img).toInt(), stride: CG.CGImageGetBytesPerRow(img).toInt()};
				CF.CFRelease(data);
			}
			CF.CFRelease(img);
		}
		helder.os.apple.objc.Runtime.objc_autoreleasePoolPop(pool);
		return out;
		#else
		return null;
		#end
	}

	static var shown = haxe.io.Bytes.alloc(0);

	// one mouse event at x, y points of w's content (type: NSEvent's, 1 the
	// left button down, 2 up, 6 dragged, 5 moved), posted to the
	// application's own queue as a mouse's come (a drag's many queue
	// between frames); false, nothing sent, where not supported
	public static function mouse(w:helder.os.Window, x:Float, y:Float, type:Int):Bool {
		if (!supported) return false;
		var view = w.surface.handle;
		helder.os.OsThread.get(() -> {
			var M = helder.os.apple.objc.Msg, O = helder.os.apple.objc.ObjC;
			var pool = helder.os.apple.objc.Runtime.objc_autoreleasePoolPush();
			var win = M.id(view, O.sel("window")), app = M.id(O.cls("NSApplication"), O.sel("sharedApplication"));
			var n = M.i(win, O.sel("windowNumber"));
			var c = M.rect(M.id(win, O.sel("contentView")), O.sel("frame"));
			var loc:Ptr<helder.os.apple.objc.CGPoint> = LibC.malloc(16);
			loc.value.x = x;
			loc.value.y = c.size.height - y;
			M.vPtrBool(app, O.sel("postEvent:atStart:"), MouseMsg.mouse(O.cls("NSEvent"),
				O.sel("mouseEventWithType:location:modifierFlags:timestamp:windowNumber:context:eventNumber:clickCount:pressure:"), type, loc.value, 0,
				M.f(M.id(O.cls("NSProcessInfo"), O.sel("processInfo")), O.sel("systemUptime")), n, Ptr.nil(), 0, 1, type == 2 ? 0.0 : 1.0), false);
			LibC.free(loc);
			helder.os.apple.objc.Runtime.objc_autoreleasePoolPop(pool);
			true;
		});
		return true;
	}
	#end
}

#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics") private extern class CG {
	static function CGEventCreateScrollWheelEvent2(source:Ptr, units:Int, count:Int, wheel1:Int, wheel2:Int, wheel3:Int):Ptr;
	static function CGEventSetLocation(e:Ptr, p:helder.os.apple.objc.CGPoint):Void;
	static function CGEventSetIntegerValueField(e:Ptr, field:Int, value:Int64):Void;
	static function CGEventPostToPid(pid:Int, e:Ptr):Void;
	static function CGWindowListCreateImage(bounds:helder.os.apple.objc.CGRect, option:Int, window:Int, imageOption:Int):Ptr;
	static function CGImageGetDataProvider(image:Ptr):Ptr;
	static function CGDataProviderCopyData(provider:Ptr):Ptr;
	static function CGImageGetWidth(image:Ptr):Int64;
	static function CGImageGetHeight(image:Ptr):Int64;
	static function CGImageGetBytesPerRow(image:Ptr):Int64;
}

@:build(helder.os.apple.objc.Sender.build())
@:hxmc.unsafe(gc)
private class MouseMsg {
	static function mouse(self:Ptr, sel:Ptr, type:Int64, p:helder.os.apple.objc.CGPoint, flags:Int64, time:Float, window:Int64, context:Ptr, number:Int64, clicks:Int64, pressure:Float):Ptr;
}

@:hxmc.c @:hxmc.lib("/usr/lib/libSystem.B.dylib") private extern class Libc {
	static function getpid():Int;
}

@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation") private extern class CF {
	static function CFRelease(p:Ptr):Void;
}
#end

#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
@:hxmc.c @:hxmc.lib("user32") private extern class WinInput {
	static function SetCursorPos(x:Int, y:Int):Int;
	static function SendInput(count:Int, inputs:Ptr, size:Int):Int;
}
#end
