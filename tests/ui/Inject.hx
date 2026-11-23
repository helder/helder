import hxmc.unsafe.*;

// Scroll input put where the system's comes in, from a thread of its own,
// while the program is busy (AsyncScrollWindow): a wheel's pixels every
// 16 ms at the window's middle. macOS: NSEvents made from CGEvents, posted
// to the application's queue, which the main thread reads (CocoaWindow's
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
		#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
		var view = w.surface.handle;
		var at = helder.os.OsThread.get(() -> {
			var win = helder.os.objc.Msg.id(view, helder.os.objc.ObjC.sel("window"));
			var r = helder.os.objc.Msg.rect(win, helder.os.objc.ObjC.sel("frame"));
			var screen = helder.os.objc.Msg.id(win, helder.os.objc.ObjC.sel("screen"));
			var s = helder.os.objc.Msg.rect(screen, helder.os.objc.ObjC.sel("frame"));
			[helder.os.objc.Msg.i(win, helder.os.objc.ObjC.sel("windowNumber")).toInt() * 1.0, r.origin.x + r.size.width / 2,
				s.size.height - (r.origin.y + r.size.height / 2)];
		});
		sys.thread.Thread.create(() -> {
			var until = haxe.Timer.stamp() + ms / 1000, app = helder.os.objc.Msg.id(helder.os.objc.ObjC.cls("NSApplication"), helder.os.objc.ObjC.sel("sharedApplication"));
			while (haxe.Timer.stamp() < until) {
				var pool = helder.os.objc.Runtime.objc_autoreleasePoolPush();
				var cg = CG.CGEventCreateScrollWheelEvent2(Ptr.nil(), 0, 1, -12, 0, 0);
				var p:Ptr<helder.os.objc.CGPoint> = LibC.malloc(16);
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
				helder.os.objc.Runtime.objc_autoreleasePoolPop(pool);
				Sys.sleep(every);
			}
			i.done.release();
		});
		#elseif (hxmc.target == "linux-x86_64" || hxmc.target == "linux-arm64")
		// (X11: wheel presses sent to the window from a connection of its own, as another client would)
		var id = w.surface.handle.toI64(), cx = Std.int(w.width / 2), cy = Std.int(w.height / 2);
		sys.thread.Thread.create(() -> {
			var d = helder.os.x11.Xlib.XOpenDisplay(Ptr.nil());
			var until = haxe.Timer.stamp() + ms / 1000;
			var raw:Ptr = LibC.malloc(192);
			while (!d.isNull() && haxe.Timer.stamp() < until) {
				if (onSent != null) onSent(haxe.Timer.stamp());
				for (press in [true, false]) {
					LibC.memset(raw, 0, 192);
					var b:Ptr<helder.os.x11.Xlib.XKeyEvent> = raw;
					b.value.type = press ? 4 : 5;
					b.value.display = d;
					b.value.window = id;
					b.value.x = cx;
					b.value.y = cy;
					b.value.keycode = 5;
					b.value.same_screen = 1;
					helder.os.x11.Xlib.XSendEvent(d, id, 0, 0, raw);
				}
				helder.os.x11.Xlib.XFlush(d);
				i.sent++;
				Sys.sleep(every);
			}
			LibC.free(raw);
			if (!d.isNull()) helder.os.x11.Xlib.XCloseDisplay(d);
			i.done.release();
		});
		#elseif (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
		var hwnd = w.surface.handle, cx = Std.int(w.width / 2), cy = Std.int(w.height / 2);
		sys.thread.Thread.create(() -> {
			var p:Ptr<Int32> = LibC.malloc(8);
			p[0] = cx;
			p[1] = cy;
			helder.os.win32.User32.ClientToScreen(hwnd, cast p);
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
}

#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics") private extern class CG {
	static function CGEventCreateScrollWheelEvent2(source:Ptr, units:Int, count:Int, wheel1:Int, wheel2:Int, wheel3:Int):Ptr;
	static function CGEventSetLocation(e:Ptr, p:helder.os.objc.CGPoint):Void;
	static function CGEventSetIntegerValueField(e:Ptr, field:Int, value:Int64):Void;
	static function CGEventPostToPid(pid:Int, e:Ptr):Void;
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
