import hxmc.unsafe.*;

// Scroll input put where the system's comes in, from a thread of its own,
// while the program is busy (AsyncScrollWindow): a wheel's pixels every
// 16 ms at the window's middle. macOS: NSEvents made from CGEvents, posted
// to the application's queue, which the main thread reads (CocoaWindow's
// pump); X11: wheel presses sent to the window by a connection of its
// own; elsewhere (Inject.supported false) none yet.
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
		#else
		return false;
		#end
	}

	public static function start(w:helder.os.Window, ms:Int):Inject {
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
				CG.CGEventPostToPid(Libc.getpid(), cg);
				i.sent++;
				CF.CFRelease(cg);
				helder.os.objc.Runtime.objc_autoreleasePoolPop(pool);
				Sys.sleep(0.016);
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
				Sys.sleep(0.016);
			}
			LibC.free(raw);
			if (!d.isNull()) helder.os.x11.Xlib.XCloseDisplay(d);
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
