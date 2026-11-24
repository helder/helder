import helder.os.*;
import helder.os.objc.*;
import helder.os.win32.User32;
import helder.os.x11.Xlib;
import hxmc.Platform;
import hxmc.unsafe.*;

// helder.os's windows (`bun run test window`; Linux: Xvfb, Windows: also
// under Wine): files dropped through each system's own mechanism, Event.Drop
// with their paths and where; moveTo and position; fullscreen asked.
//
// - X11: a second connection is a drag source speaking XDND 5 to the window
//   (XdndEnter, XdndPosition, XdndDrop; the selection's text/uri-list
//   answered), the XdndStatus and XdndFinished it gets back checked;
// - Windows: an HDROP of two wide paths (DROPFILES) posted as WM_DROPFILES;
// - macOS: a dragging info of a class made here (a pasteboard of file URLs,
//   the destination window) given to the window's dragging destination,
//   draggingEntered: then performDragOperation:.
//
// Then files dragged out (Window.dragFiles; DragOut below).
class WindowTest {
	static var failed = 0;

	static function check(what:String, ok:Bool, detail = "") {
		Sys.println('WindowTest: ${ok ? "ok" : "FAIL"}: $what${detail == "" ? "" : " (" + detail + ")"}');
		if (!ok) failed++;
	}

	static function main() {
		var window = new Window("WindowTest", 200, 150);
		var dropped:Null<{files:Array<String>, x:Int, y:Int}> = null;
		var start = haxe.Timer.stamp(), step = 0, frames = 0;
		// (macOS gives a path's characters decomposed, as its file systems
		// keep them: é as e and its accent; ASCII there)
		var want = Platform.os() == 2 ? ["C:\\photos\\a b.png", "C:\\photos\\é.jpg"] : Platform.os() == 1 ? ["/tmp/photos/a b.png", "/tmp/photos/c.jpg"] : ["/tmp/photos/a b.png", "/tmp/photos/é.jpg"];
		var source:Null<DropSource> = null;
		var out:Null<DragOut> = null, outAt = 0.0;
		App.run(() -> {
			frames++;
			var t = haxe.Timer.stamp() - start;
			if (step == 0 && frames > 3) {
				step = 1;
				// (clear of macOS's menu bar, which a window's frame stays under)
				window.moveTo(120, 160);
				source = new DropSource(window, want, 20, 30);
			}
			if (step == 1) source.pump();
			if (step == 1 && (dropped != null || t > 5)) {
				step = 2;
				check("a drop: its files", dropped != null && dropped.files.join("|") == want.join("|"), dropped == null ? "none" : dropped.files.join("|"));
				// (where: X11 and Windows exactly, macOS where the pointer is)
				if (dropped != null && Platform.os() != 1) check("a drop: where", dropped.x == 20 && dropped.y == 30, '${dropped.x}, ${dropped.y}');
				source.finish(check);
				var p = window.position();
				check("moveTo, position", p != null && p.x == 120 && p.y == 160, p == null ? "null" : '${p.x}, ${p.y}');
				window.raise();
				integration(check);
				out = new DragOut(window, check);
				outAt = t;
			}
			if (step == 2) out.pump();
			if (step == 2 && (out.done != null || t > outAt + 5)) {
				step = 3;
				out.finish(check);
				window.fullscreen = true;
				outAt = t;
			}
			if (step == 3 && t > outAt + 1.5) {
				step = 4;
				// (asked: a window manager, Windows and macOS's spaces may take a while; X11 without one never)
				Sys.println('WindowTest: fullscreen ${window.fullscreen}, ${window.width}x${window.height}');
				window.fullscreen = false;
				App.quit();
			}
			App.wait(0.02);
		}, e -> switch e.kind {
			case Drop:
				dropped = {files: e.files.copy(), x: e.x, y: e.y};
			case Close:
				window.close();
			case _:
		});
		Sys.exit(failed > 0 ? 1 : 0);
	}
}

// the desktop's: the file types registered (Windows: HKCU's ProgID read
// back; Linux: the .desktop file in a data directory of the test's), the
// system's open dialog made (not shown: COM's IFileOpenDialog, NSOpenPanel),
// macOS's open request (application:openURLs:) reaching App.onOpen
function integration(check:(String, Bool, String) -> Void) {
	var types = [{mime: "image/jpeg", extensions: ["jpg", "jpeg"]}, {mime: "image/png", extensions: ["png"]}];
	if (Platform.os() == 0) {
		var dir = sys.FileSystem.fullPath(".") + "/bin/os/xdg";
		Sys.putEnv("XDG_DATA_HOME", dir);
		var w = FileTypes.register("helder-windowtest", "Window Test", "/opt/window test/viewer", types);
		var text = try sys.io.File.getContent(dir + "/applications/helder-windowtest.desktop") catch (e:Dynamic) "";
		check("FileTypes: a .desktop file", w.length == 1 && text.indexOf('Exec="/opt/window test/viewer" %F') >= 0 && text.indexOf("MimeType=image/jpeg;image/png;") >= 0, w.join(", "));
	}
	if (Platform.os() == 2) {
		var w = FileTypes.register("helder.windowtest", "Window Test", "C:\\tools\\viewer.exe", types);
		var command = Arena.scopedValue(a -> {
			var buf:Ptr<UInt16> = a.alloc(1024), size:Ptr<Int32> = a.alloc(4);
			size.value = 1024;
			// (HKEY_CURRENT_USER, RRF_RT_REG_SZ 2)
			var r = helder.os.win32.User32.Advapi32.RegGetValueW(Ptr.ofI64((0x80000001 : Int64)), a.wstring("Software\\Classes\\helder.windowtest.file\\shell\\open\\command"), Ptr.nil(), 2, Ptr.nil(), cast buf, cast size);
			var b = new StringBuf(), k = 0;
			if (r == 0) while (buf[k] != 0) b.addChar(buf[k++]);
			b.toString();
		});
		check("FileTypes: the ProgID's command", command == '"C:\\tools\\viewer.exe" "%1"', command);
		check("FileTypes: the extensions' OpenWithProgids", w.indexOf("HKCU\\Software\\Classes\\.jpg\\OpenWithProgids\\helder.windowtest.file") >= 0, w.length + " values");
		check("FileDialog: IFileOpenDialog made", !helder.os.win32.FileOpenDialog.make("Open", [{name: "Images", extensions: ["jpg"]}]).isNull(), "");
		#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
		WinDragOut.check(check);
		#end
	}
	if (Platform.os() == 1) {
		check("FileDialog: NSOpenPanel made", !helder.os.cocoa.OpenPanel.make("Open", [{name: "Images", extensions: ["jpg"]}]).isNull(), "");
		var got:Array<String> = [];
		App.onOpen = paths -> got = paths;
		var s = ObjC.str("/tmp/photos/a b.png");
		var url = Msg.idPtr(ObjC.cls("NSURL"), ObjC.sel("fileURLWithPath:"), s);
		var app = Msg.id(ObjC.cls("NSApplication"), ObjC.sel("sharedApplication"));
		Msg.vPtrPtr(Msg.id(app, ObjC.sel("delegate")), ObjC.sel("application:openURLs:"), app, Msg.idPtr(ObjC.cls("NSArray"), ObjC.sel("arrayWithObject:"), url));
		check("App.onOpen: application:openURLs:", got.join("|") == "/tmp/photos/a b.png", got.join("|"));
	}
}

// files dragged out of the window:
//
// - X11: a second connection's window is an XdndAware target under the
//   pointer; it answers XdndEnter and XdndPosition with XdndStatus (copy),
//   lets the button go, converts the selection at XdndDrop (its
//   text/uri-list checked) and sends XdndFinished: done(Copy);
// - macOS: the dragging items' file URLs, the source's operation mask and
//   its end (no session: AppKit's would follow the real mouse);
// - Windows: the Shell's data object (integration's WinDragOut).
private class DragOut {
	static final FILES = ["/tmp/photos/a b.png", "/tmp/photos/é.jpg"];

	public var done:Null<DragOperation>;

	final window:Window;
	final check:(String, Bool, String) -> Void;
	var d = Ptr.nil();
	var app:Int64 = 0;
	var target:Int64 = 0;
	var atoms:Map<String, Int64> = [];
	var entered = "";
	var released = false;
	var text = "";

	public function new(window:Window, check:(String, Bool, String) -> Void) {
		this.window = window;
		this.check = check;
		check("drag out: nothing to drag refused", !window.dragFiles([], null, 0, 0, [Copy], op -> {}), "");
		#if (hxmc.libc == "glibc")
		if (Platform.os() == 0) x11();
		#end
		#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
		mac();
		#end
	}

	public function pump() {
		#if (hxmc.libc == "glibc")
		if (!d.isNull()) pumpX11();
		#end
	}

	public function finish(check:(String, Bool, String) -> Void) {
		if (Platform.os() == 2) return;
		check("drag out: done with the target's operation", done == Copy, '$done');
		if (Platform.os() != 0) return;
		check("drag out: XdndEnter, version 5 with text/uri-list", entered == "5 true", entered);
		check("drag out: the selection's text/uri-list", text == "file:///tmp/photos/a%20b.png\r\nfile:///tmp/photos/%C3%A9.jpg\r\n", text);
	}

	#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
	function mac() {
		var w:helder.os.cocoa.CocoaWindow = cast @:privateAccess window.native;
		// (ASCII: NSURL's path gives é decomposed)
		var files = ["/tmp/photos/a b.png", "/tmp/photos/c.jpg"];
		var items = @:privateAccess helder.os.cocoa.CocoaFileDrag.items(w, Ptr.nil(), files, null, 0, 0), got = [];
		for (i in 0...Msg.i(items, ObjC.sel("count")).toInt()) {
			var url = Msg.id(Msg.idInt(items, ObjC.sel("objectAtIndex:"), i), ObjC.sel("item"));
			got.push(ObjC.string(Msg.id(url, ObjC.sel("path"))));
		}
		check("drag out: a dragging item per file URL", got.join("|") == files.join("|"), got.join("|"));
		var drag = @:privateAccess new helder.os.cocoa.CocoaFileDrag([Copy, Move], op -> done = op), source = @:privateAccess drag.source;
		var answers = Msg.bPtr(source, ObjC.sel("respondsToSelector:"), ObjC.sel("draggingSession:sourceOperationMaskForDraggingContext:"))
			&& Msg.bPtr(source, ObjC.sel("respondsToSelector:"), ObjC.sel("draggingSession:endedAtPoint:operation:"));
		@:privateAccess helder.os.cocoa.CocoaFileDrag.active.push(drag);
		var mask = @:privateAccess helder.os.cocoa.CocoaFileDrag.operations(source, Ptr.nil(), Ptr.nil(), 0);
		check("drag out: the source's methods, its mask copy and move", answers && mask == 17, 'mask $mask');
		// (NSDragOperationCopy)
		@:privateAccess helder.os.cocoa.CocoaFileDrag.ended(source, Ptr.nil(), Ptr.nil(), 0, 0, 1);
	}
	#end

	#if (hxmc.libc == "glibc")
	function x11() {
		var w:helder.os.x11.X11Window = cast @:privateAccess window.native;
		app = @:privateAccess w.id;
		d = Xlib.XOpenDisplay(Ptr.nil());
		for (n in ["XdndAware", "XdndEnter", "XdndPosition", "XdndStatus", "XdndDrop", "XdndFinished", "XdndSelection", "XdndActionCopy", "text/uri-list", "HXMC_DRAG_OUT"])
			Arena.scoped(a -> atoms.set(n, Xlib.XInternAtom(d, a.cstring(n), 0)));
		var root = Xlib.XDefaultRootWindow(d);
		// (beside the window, the pointer over it)
		target = Xlib.XCreateSimpleWindow(d, root, 400, 100, 100, 100, 0, 0, 0);
		Arena.scoped(a -> {
			var v:Ptr<Int64> = a.alloc(8);
			v.value = 5;
			Xlib.XChangeProperty(d, target, atoms["XdndAware"], 4, 32, 0, v, 1);
		});
		Xlib.XMapWindow(d, target);
		Warp.XWarpPointer(d, 0, root, 0, 0, 0, 0, 450, 150);
		Xlib.XSync(d, 0);
		// (the press the drag takes: as a ButtonPress leaves it)
		@:privateAccess w.dragButton = 1;
		@:privateAccess w.dragTime = 0;
		check("drag out: started", window.dragFiles(FILES, null, 0, 0, [Copy, Move], op -> done = op), "");
	}

	function send(to:Int64, type:String, l0:Int64, l1:Int64, l2:Int64, l3:Int64, l4:Int64)
		Arena.scoped(a -> {
			var raw:Ptr<UInt8> = a.alloc(192);
			var m:Ptr<XClientMessageEvent> = cast raw;
			m.value.type = 33;
			m.value.display = d;
			m.value.window = to;
			m.value.message_type = atoms[type];
			m.value.format = 32;
			var l:Ptr<Int64> = cast raw.add(56);
			l[0] = l0;
			l[1] = l1;
			l[2] = l2;
			l[3] = l3;
			l[4] = l4;
			Xlib.XSendEvent(d, to, 0, 0, cast raw);
		});

	// (XButtonEvent: window 32, root 40, state 80, button 84, same_screen 88)
	function release()
		Arena.scoped(a -> {
			var raw:Ptr<UInt8> = a.alloc(192);
			(cast raw : Ptr<Int32>).value = 5;
			(cast raw.add(24) : Ptr<Ptr>).value = d;
			(cast raw.add(32) : Ptr<Int64>).value = app;
			(cast raw.add(40) : Ptr<Int64>).value = Xlib.XDefaultRootWindow(d);
			(cast raw.add(80) : Ptr<Int32>).value = 1 << 8;
			(cast raw.add(84) : Ptr<Int32>).value = 1;
			(cast raw.add(88) : Ptr<Int32>).value = 1;
			Xlib.XSendEvent(d, app, 0, 0, cast raw);
		});

	function pumpX11() {
		var ev:Ptr<UInt8> = LibC.malloc(192);
		while (Xlib.XPending(d) > 0) {
			Xlib.XNextEvent(d, cast ev);
			var type = (cast ev : Ptr<Int32>).value;
			if (type == 33) {
				var m:Ptr<XClientMessageEvent> = cast ev, l:Ptr<Int64> = cast ev.add(56), t = m.value.message_type;
				if (t == atoms["XdndEnter"]) entered = '${(l[1] >> 24).toInt()} ${l[2] == atoms["text/uri-list"]}';
				if (t == atoms["XdndPosition"]) {
					send(app, "XdndStatus", target, 1, 0, 0, atoms["XdndActionCopy"]);
					if (!released) release();
					released = true;
				}
				if (t == atoms["XdndDrop"]) Xlib.XConvertSelection(d, atoms["XdndSelection"], atoms["text/uri-list"], atoms["HXMC_DRAG_OUT"], target, l[2]);
			} else if (type == 31) {
				text = Arena.scopedValue(a -> {
					var kind:Ptr<Int64> = a.alloc(8), format:Ptr<Int32> = a.alloc(4), count:Ptr<Int64> = a.alloc(8), after:Ptr<Int64> = a.alloc(8);
					var data:Ptr<Ptr> = a.alloc(8);
					if (Xlib.XGetWindowProperty(d, target, atoms["HXMC_DRAG_OUT"], 0, 1024, 1, 0, kind, format, count, after, data) != 0 || data.value.isNull()) return "";
					var b = haxe.io.Bytes.alloc(count.value.toInt());
					BytesPtr.copyIn(b, 0, data.value, b.length);
					Xlib.XFree(data.value);
					return b.toString();
				});
				send(app, "XdndFinished", target, 1, atoms["XdndActionCopy"], 0, 0);
			}
		}
		LibC.free(ev);
		Xlib.XFlush(d);
	}
	#end
}

#if (hxmc.libc == "glibc")
@:hxmc.c @:hxmc.lib("libX11.so.6") private extern class Warp {
	static function XWarpPointer(d:Ptr, from:Int64, to:Int64, x:Int, y:Int, width:Int, height:Int, toX:Int, toY:Int):Int;
}
#end

// a drop made by the system's own means (above)
private class DropSource {
	final window:Window;
	final files:Array<String>;
	final x:Int;
	final y:Int;
	var d = Ptr.nil();
	var src:Int64 = 0;
	var target:Int64 = 0;
	var atoms:Map<String, Int64> = [];
	var accepted = -1;
	var finished = -1;
	var dropSent = false;
	var answered = false;

	public function new(window:Window, files:Array<String>, x:Int, y:Int) {
		this.window = window;
		this.files = files;
		this.x = x;
		this.y = y;
		if (Platform.os() == 2) windows() else if (Platform.os() == 1) mac() else x11();
	}

	public function pump()
		if (Platform.os() != 1 && Platform.os() != 2) pumpX11();

	public function finish(check:(String, Bool, String) -> Void) {
		if (Platform.os() == 1 || Platform.os() == 2) return;
		check("XDND: the position accepted (XdndStatus)", accepted == 1, 'accepted $accepted');
		check("XDND: XdndFinished, the drop taken", finished == 1, 'finished $finished');
	}

	// --- Windows: WM_DROPFILES of an HDROP
	function windows() {
		var hwnd = @:privateAccess (cast @:privateAccess window.native : helder.os.win32.Win32Window).hwnd;
		var chars = 0;
		for (f in files)
			chars += f.length + 1;
		// (DROPFILES: pFiles 20, pt, fNC, fWide; the paths, a 0 after each and one more)
		var mem = helder.os.win32.User32.Kernel32.GlobalAlloc(0x42, (20 + 2 * (chars + 1) : Int64));
		var p:Ptr<UInt8> = helder.os.win32.User32.Kernel32.GlobalLock(mem);
		var h:Ptr<Int32> = cast p;
		h[0] = 20;
		h[1] = x;
		h[2] = y;
		h[3] = 0;
		h[4] = 1;
		var w:Ptr<UInt16> = cast p.add(20), k = 0;
		for (f in files) {
			for (i in 0...f.length)
				w[k++] = StringTools.fastCodeAt(f, i);
			w[k++] = 0;
		}
		w[k] = 0;
		helder.os.win32.User32.Kernel32.GlobalUnlock(mem);
		helder.os.win32.User32.PostMessageW(hwnd, 0x0233, mem.toI64(), 0);
	}

	// --- macOS: the window's dragging destination given a dragging info of our own
	function mac() {
		var w = @:privateAccess (cast @:privateAccess window.native : helder.os.cocoa.CocoaWindow).window;
		MacDrag.make(w, files);
	}

	// --- X11: XDND from a second connection
	function x11() {
		target = @:privateAccess (cast @:privateAccess window.native : helder.os.x11.X11Window).id;
		d = helder.os.x11.Xlib.XOpenDisplay(Ptr.nil());
		var root = helder.os.x11.Xlib.XDefaultRootWindow(d);
		src = helder.os.x11.Xlib.XCreateSimpleWindow(d, root, 0, 0, 10, 10, 0, 0, 0);
		for (n in ["XdndEnter", "XdndPosition", "XdndStatus", "XdndDrop", "XdndFinished", "XdndSelection", "XdndActionCopy", "text/uri-list"])
			Arena.scoped(a -> atoms.set(n, helder.os.x11.Xlib.XInternAtom(d, a.cstring(n), 0)));
		helder.os.x11.Xlib.XSetSelectionOwner(d, atoms["XdndSelection"], src, 0);
		var p = window.position();
		send("XdndEnter", src, (5 : Int64) << 24, atoms["text/uri-list"], 0, 0);
		send("XdndPosition", src, 0, ((p.x + x : Int64) << 16) | (p.y + y), 0, atoms["XdndActionCopy"]);
		helder.os.x11.Xlib.XFlush(d);
	}

	function send(type:String, l0:Int64, l1:Int64, l2:Int64, l3:Int64, l4:Int64)
		Arena.scoped(a -> {
			var raw:Ptr<UInt8> = a.alloc(192);
			for (i in 0...192)
				raw[i] = 0;
			var m:Ptr<helder.os.x11.Xlib.XClientMessageEvent> = cast raw;
			m.value.type = 33;
			m.value.display = d;
			m.value.window = target;
			m.value.message_type = atoms[type];
			m.value.format = 32;
			var l:Ptr<Int64> = cast raw.add(56);
			l[0] = l0;
			l[1] = l1;
			l[2] = l2;
			l[3] = l3;
			l[4] = l4;
			helder.os.x11.Xlib.XSendEvent(d, target, 0, 0, cast raw);
		});

	// (a path's bytes percent-encoded but for letters, digits, / . - _)
	static function escape(path:String):String {
		var b = haxe.io.Bytes.ofString(path), out = new StringBuf();
		for (i in 0...b.length) {
			var c = b.get(i);
			if ((c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code) || (c >= "0".code && c <= "9".code) || c == "/".code || c == ".".code || c == "-".code || c == "_".code)
				out.addChar(c)
			else
				out.add("%" + StringTools.hex(c, 2));
		}
		return out.toString();
	}

	function pumpX11() {
		var ev:Ptr<UInt8> = LibC.malloc(192);
		while (helder.os.x11.Xlib.XPending(d) > 0) {
			helder.os.x11.Xlib.XNextEvent(d, cast ev);
			var type = (cast ev : Ptr<Int32>).value;
			if (type == 33) {
				var m:Ptr<helder.os.x11.Xlib.XClientMessageEvent> = cast ev, l:Ptr<Int64> = cast ev.add(56);
				if (m.value.message_type == atoms["XdndStatus"]) {
					accepted = l[1].toInt() & 1;
					if (!dropSent) {
						dropSent = true;
						send("XdndDrop", src, 0, 0, 0, 0);
					}
				}
				if (m.value.message_type == atoms["XdndFinished"]) finished = l[1].toInt() & 1;
			} else if (type == 30) {
				// (SelectionRequest: the files as text/uri-list into the requestor's property)
				var r:Ptr<helder.os.x11.Xlib.XSelectionRequestEvent> = cast ev;
				var list = [for (f in files) "file://" + escape(f)].join("\r\n") + "\r\n";
				var b = haxe.io.Bytes.ofString(list);
				Arena.scoped(a -> {
					helder.os.x11.Xlib.XChangeProperty(d, r.value.requestor, r.value.property, atoms["text/uri-list"], 8, 0, a.copyBytes(b), b.length);
					var raw:Ptr<UInt8> = a.alloc(192);
					for (i in 0...192)
						raw[i] = 0;
					var n:Ptr<helder.os.x11.Xlib.XSelectionEvent> = cast raw;
					n.value.type = 31;
					n.value.display = d;
					n.value.requestor = r.value.requestor;
					n.value.selection = r.value.selection;
					n.value.target = r.value.target;
					n.value.property = r.value.property;
					n.value.time = r.value.time;
					helder.os.x11.Xlib.XSendEvent(d, r.value.requestor, 0, 0, cast raw);
				});
				answered = true;
			}
		}
		LibC.free(ev);
		helder.os.x11.Xlib.XFlush(d);
	}
}

// (a dragging info: NSDraggingInfo's draggingPasteboard, draggingDestinationWindow
// and draggingSourceOperationMask, from a class made at run time)
private class MacDrag {
	static var pasteboard = Ptr.nil();
	static var destination = Ptr.nil();

	public static function make(window:Ptr, files:Array<String>) {
		destination = window;
		pasteboard = Runtime.objc_retain(Msg.id(ObjC.cls("NSPasteboard"), ObjC.sel("pasteboardWithUniqueName")));
		Msg.i(pasteboard, ObjC.sel("clearContents"));
		var urls = Msg.id(Msg.id(ObjC.cls("NSMutableArray"), ObjC.sel("alloc")), ObjC.sel("init"));
		for (f in files) {
			var s = ObjC.str(f);
			Msg.vPtr(urls, ObjC.sel("addObject:"), Msg.idPtr(ObjC.cls("NSURL"), ObjC.sel("fileURLWithPath:"), s));
			ObjC.release(s);
		}
		Msg.bPtr(pasteboard, ObjC.sel("writeObjects:"), urls);
		var cls = Runtime.objc_allocateClassPair(ObjC.cls("NSObject"), Mem.cstr("HxmcTestDrag"), 0);
		Runtime.class_addMethod(cls, ObjC.sel("draggingPasteboard"), Callback.addr(board), Mem.cstr("@@:"));
		Runtime.class_addMethod(cls, ObjC.sel("draggingDestinationWindow"), Callback.addr(dest), Mem.cstr("@@:"));
		Runtime.class_addMethod(cls, ObjC.sel("draggingSourceOperationMask"), Callback.addr(mask), Mem.cstr("Q@:"));
		Runtime.objc_registerClassPair(cls);
		var info = Msg.id(Msg.id(cls, ObjC.sel("alloc")), ObjC.sel("init"));
		var delegate = Msg.id(window, ObjC.sel("delegate"));
		var op = Msg.iPtr(delegate, ObjC.sel("draggingEntered:"), info);
		Sys.println('WindowTest: draggingEntered: $op');
		Msg.bPtr(delegate, ObjC.sel("performDragOperation:"), info);
	}

	@:hxmc.callback static function board(self:Ptr, cmd:Ptr):Ptr
		return pasteboard;

	@:hxmc.callback static function dest(self:Ptr, cmd:Ptr):Ptr
		return destination;

	@:hxmc.callback static function mask(self:Ptr, cmd:Ptr):Int64
		return 1;
}

#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
// a drag out's data object (DoDragDrop itself waits on a person): the
// Shell's, for two temp files, read back as CF_HDROP
private class WinDragOut {
	public static function check(check:(String, Bool, String) -> Void) {
		var dir = Sys.getEnv("TEMP") ?? "C:\\Windows\\Temp";
		var files = [dir + "\\drag a.txt", dir + "\\drag b.txt"];
		for (f in files)
			sys.io.File.saveContent(f, "x");
		// (the shell item array's, then the parent folder's: Wine's; on the
		// windows' thread, OLE's. TEMP may be a short name, the Shell's long)
		for (items in [true, false]) {
			var got = OsThread.get(() -> hdrop(@:privateAccess helder.os.win32.WinFileDrag.dataObject(files, items)));
			var names = [for (g in got) haxe.io.Path.withoutDirectory(g)].join("|");
			check('drag out: the Shell\'s data object as CF_HDROP (${items ? "items" : "folder"})', names == "drag a.txt|drag b.txt", got.join("|"));
		}
		for (f in files)
			sys.FileSystem.deleteFile(f);
	}

	static function hdrop(data:Ptr):Array<String> {
		var got = data.isNull() ? [] : Arena.scopedValue(a -> {
			// (FORMATETC: CF_HDROP, DVASPECT_CONTENT, every index, TYMED_HGLOBAL; STGMEDIUM: tymed, the HGLOBAL)
			var format = a.alloc(32), medium:Ptr<Ptr> = a.alloc(24), f:Ptr<Int32> = format;
			f[0] = 15;
			f[4] = 1;
			f[5] = -1;
			f[6] = 1;
			if (DataObject.GetData(data, format, medium) < 0) return [];
			var drop = medium[1], buf:Ptr<UInt16> = a.alloc(1024), out = [];
			for (i in 0...Shell32.DragQueryFileW(drop, -1, Ptr.nil(), 0)) {
				var n = Shell32.DragQueryFileW(drop, i, buf, 512), b = new StringBuf();
				for (k in 0...n)
					b.addChar(buf[k]);
				out.push(b.toString());
			}
			@:privateAccess helder.os.win32.WinFileDrag.DragOle32.ReleaseStgMedium(medium);
			return out;
		});
		helder.os.win32.Com.release(data);
		return got;
	}
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
private class DataObject {
	@:slot(3) static function GetData(self:Ptr, format:Ptr, medium:Ptr):Int;
}
#end
