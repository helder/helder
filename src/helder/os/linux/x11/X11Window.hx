package helder.os.linux.x11;

import helder.os.DragOperation;
import helder.os.Event;
import helder.os.TitleBar;
import helder.os.linux.x11.Xlib;
import hxmc.unsafe.*;

// helder.os.Window on X11: one Display connection for the process, opened
// with the first window; WM_DELETE_WINDOW turns the close button into a
// Close event. A key's text comes from XLookupString (Latin-1, or a Unicode
// KeySym; no input method yet: compose sequences and IMEs), the wheel
// from buttons 4 to 7. The scale stays 1. Run by hxmc dev's host
// (-D hxmc.dev-host: helder.dev.Hosted), the connection and the first window
// are the host's: made by the first build, left by each build that hands
// over (its input method and contexts closed) and taken by the next, at the
// size the window has.
@:allow(helder.os)
@:hxmc.unsafe(gc)
class X11Window {
	static var display = Ptr.nil();
	static var wmDelete:Int64 = 0;
	// one XEvent buffer, and the Event dispatched from it
	static var xev:Ptr = Ptr.nil();
	static final event = new Event();
	static final open:Array<X11Window> = [];
	// the clipboard: the atoms, the text this process owns it with (null: it
	// does not), the reads waiting for SelectionNotify
	static var CLIPBOARD:Int64 = 0;
	static var UTF8_STRING:Int64 = 0;
	static var INCR:Int64 = 0;
	// the selections this process sends in parts (INCR): to a requestor's
	// property, the next part when it deletes the last
	static final sending:Array<{requestor:Int64, property:Int64, target:Int64, data:haxe.io.Bytes, at:Int}> = [];
	// (parts of 64 KB, for a text over 256 KB)
	static inline var PART = 65536;
	static inline var INCR_OVER = 262144;
	static var TARGETS:Int64 = 0;
	static var HXMC_CLIPBOARD:Int64 = 0;
	static var clipboardText:Null<String> = null;
	// the input method (nil: none, XLookupString then)
	static var im = Ptr.nil();
	static final clipboardReads:Array<{window:X11Window, callback:Null<String>->Void}> = [];
	// the cursors made (by Cursor; 0: not yet)
	static final cursors:Array<Int64> = [];
	// XDND's atoms (drops: Event.Drop), the window manager's states
	static var XdndAware:Int64 = 0;
	static var XdndEnter:Int64 = 0;
	static var XdndPosition:Int64 = 0;
	static var XdndStatus:Int64 = 0;
	static var XdndLeave:Int64 = 0;
	static var XdndDrop:Int64 = 0;
	static var XdndFinished:Int64 = 0;
	static var XdndSelection:Int64 = 0;
	static var XdndTypeList:Int64 = 0;
	static var XdndActionCopy:Int64 = 0;
	static var XdndActionMove:Int64 = 0;
	static var XdndActionLink:Int64 = 0;
	static var XdndProxy:Int64 = 0;
	static var URI_LIST:Int64 = 0;
	static var HXMC_DND:Int64 = 0;
	static var NET_WM_STATE:Int64 = 0;
	static var NET_WM_STATE_FULLSCREEN:Int64 = 0;
	static var NET_FRAME_EXTENTS:Int64 = 0;

	final owner:Window;
	final id:Int64;
	final surface:Surface;
	// this window's input context (nil: none)
	var ic = Ptr.nil();
	// a drag over it (XDND): its source (0: none), whether it carries files,
	// where the pointer is (the root's pixels), the drop's time
	var dragButton = 0;
	var dragTime:Int64 = 0;
	var dragState = 0;
	var dndSource:Int64 = 0;
	var dndFiles = false;
	var dndX = 0;
	var dndY = 0;
	// asked of the window manager (_NET_WM_STATE)
	var fullscreen = false;
	var maximized = false;
	// an inset title bar's last press on a drag region (a double press maximises)
	var lastDrag = 0.0;

	function new(owner:Window, title:String, width:Int, height:Int) {
		this.owner = owner;
		if (display.isNull()) connect();
		var screen = Xlib.XDefaultScreen(display);
		var black = Xlib.XBlackPixel(display, screen);
		#if hxmc.dev_host
		// (the host's window, as the last build left it)
		var kept = helder.dev.Hosted.hosted() && open.length == 0 ? helder.dev.Hosted.get(helder.dev.Hosted.X11_WINDOW) : Ptr.nil();
		if (!kept.isNull()) {
			id = kept.toI64();
			var w = haxe.Int64.toInt(helder.dev.Hosted.get(helder.dev.Hosted.WIDTH).toI64()), h = haxe.Int64.toInt(helder.dev.Hosted.get(helder.dev.Hosted.HEIGHT).toI64());
			if (w > 0 && h > 0) {
				width = w;
				height = h;
			}
			Sys.stderr().writeString("helder.dev: the host's window 0x" + StringTools.hex(haxe.Int64.toInt(id)) + " (process " + helder.dev.Hosted.pid() + ")\n");
		} else {
			id = Xlib.XCreateSimpleWindow(display, Xlib.XRootWindow(display, screen), 0, 0, width, height, 0, black, black);
			if (helder.dev.Hosted.hosted() && open.length == 0) {
				helder.dev.Hosted.set(helder.dev.Hosted.X11_WINDOW, Ptr.ofI64(id));
				helder.dev.Hosted.set(helder.dev.Hosted.WIDTH, Ptr.ofI64(width));
				helder.dev.Hosted.set(helder.dev.Hosted.HEIGHT, Ptr.ofI64(height));
				Sys.stderr().writeString("helder.dev: the host's window 0x" + StringTools.hex(haxe.Int64.toInt(id)) + " (process " + helder.dev.Hosted.pid() + ")\n");
			}
		}
		#else
		id = owner.clear ? clearWindow(screen, width, height) : 0;
		if (id == 0) id = Xlib.XCreateSimpleWindow(display, Xlib.XRootWindow(display, screen), 0, 0, width, height, 0, black, black);
		#end
		Arena.scoped(a -> {
			Xlib.XStoreName(display, id, a.cstring(title));
			var atoms:Ptr<Int64> = a.alloc(8);
			atoms.value = wmDelete;
			Xlib.XSetWMProtocols(display, id, atoms, 1);
		});
		// (inset: no decorations, Motif's hints asked of the window manager:
		// flags MWM_HINTS_DECORATIONS, decorations 0)
		if (owner.titlebar != Standard) Arena.scoped(a -> {
			var hints:Ptr<Int64> = a.alloc(40);
			for (i in 0...5)
				hints[i] = 0;
			hints[0] = 2;
			var atom = Xlib.XInternAtom(display, a.cstring("_MOTIF_WM_HINTS"), 0);
			Xlib.XChangeProperty(display, id, atom, atom, 32, X.PropModeReplace, hints, 5);
		});
		Xlib.XSelectInput(display, id, (X.KeyPressMask | X.KeyReleaseMask | X.ButtonPressMask | X.ButtonReleaseMask | X.PointerMotionMask
			| X.StructureNotifyMask | X.ExposureMask | X.PropertyChangeMask : Int64));
		// (XDND version 5: drops of files)
		Arena.scoped(a -> {
			var v:Ptr<Int64> = a.alloc(8);
			v.value = 5;
			Xlib.XChangeProperty(display, id, XdndAware, X.XA_ATOM, 32, X.PropModeReplace, v, 1);
		});
		Xlib.XMapWindow(display, id);
		if (!im.isNull()) {
			// (XIMPreeditNothing | XIMStatusNothing: the input method draws its own)
			ic = Xlib.XCreateIC(im, Mem.cstr("inputStyle"), 0x0008 | 0x0400, Mem.cstr("clientWindow"), id, Mem.cstr("focusWindow"), id, Ptr.nil());
			if (!ic.isNull()) Xlib.XSetICFocus(ic);
		}
		Xlib.XFlush(display);
		surface = new Surface(X11, display, Ptr.ofI64(id), width, height);
		if (visual != 0) surface.see(true, visual);
		queueLock.acquire();
		open.push(this);
		queueLock.release();
		#if hxmc.dev_host
		// (handing over: the input context closed, the window left to the next build; another window closed)
		if (helder.dev.Hosted.hosted()) helder.dev.Hot.onDispose(() -> if (open.indexOf(this) >= 0) {
			if (helder.dev.Hosted.get(helder.dev.Hosted.X11_WINDOW).toI64() == id) {
				queueLock.acquire();
				open.remove(this);
				queueLock.release();
				if (!ic.isNull()) Xlib.XDestroyIC(ic);
				ic = Ptr.nil();
				if (open.length == 0) handOver();
			} else destroy();
		});
		#end
	}

	#if hxmc.dev_host
	// (the last window left to the host: the input method closed, the connection kept)
	static function handOver() {
		cursors.resize(0);
		clipboardText = null;
		if (!im.isNull()) Xlib.XCloseIM(im);
		im = Ptr.nil();
		Xlib.XFlush(display);
		LibC.free(xev);
		display = Ptr.nil();
	}
	#end

	static function connect() {
		// (before any other call: the render thread's EGL presents through the
		// same display, Mesa's software path by Xlib's own calls)
		Xlib.XInitThreads();
		#if hxmc.dev_host
		display = helder.dev.Hosted.hosted() ? helder.dev.Hosted.get(helder.dev.Hosted.X11_DISPLAY) : Ptr.nil();
		if (display.isNull()) {
			display = Xlib.XOpenDisplay(Ptr.nil());
			if (helder.dev.Hosted.hosted()) helder.dev.Hosted.set(helder.dev.Hosted.X11_DISPLAY, display);
		}
		#else
		display = Xlib.XOpenDisplay(Ptr.nil());
		#end
		// (a server started with the program, Xvfb's under xvfb-run, may not take
		// connections yet: asked again for a moment while DISPLAY names one)
		var d = Sys.getEnv("DISPLAY"), since = haxe.Timer.stamp();
		while (display.isNull() && d != null && d != "" && haxe.Timer.stamp() - since < 2) {
			Sys.sleep(0.05);
			display = Xlib.XOpenDisplay(Ptr.nil());
			#if hxmc.dev_host
			if (!display.isNull() && helder.dev.Hosted.hosted()) helder.dev.Hosted.set(helder.dev.Hosted.X11_DISPLAY, display);
			#end
		}
		if (display.isNull()) throw "helder.os: cannot open the X display (DISPLAY=" + Sys.getEnv("DISPLAY") + ")";
		wmDelete = Xlib.XInternAtom(display, Mem.cstr("WM_DELETE_WINDOW"), 0);
		CLIPBOARD = Xlib.XInternAtom(display, Mem.cstr("CLIPBOARD"), 0);
		UTF8_STRING = Xlib.XInternAtom(display, Mem.cstr("UTF8_STRING"), 0);
		TARGETS = Xlib.XInternAtom(display, Mem.cstr("TARGETS"), 0);
		HXMC_CLIPBOARD = Xlib.XInternAtom(display, Mem.cstr("HXMC_CLIPBOARD"), 0);
		INCR = Xlib.XInternAtom(display, Mem.cstr("INCR"), 0);
		XdndAware = Xlib.XInternAtom(display, Mem.cstr("XdndAware"), 0);
		XdndEnter = Xlib.XInternAtom(display, Mem.cstr("XdndEnter"), 0);
		XdndPosition = Xlib.XInternAtom(display, Mem.cstr("XdndPosition"), 0);
		XdndStatus = Xlib.XInternAtom(display, Mem.cstr("XdndStatus"), 0);
		XdndLeave = Xlib.XInternAtom(display, Mem.cstr("XdndLeave"), 0);
		XdndDrop = Xlib.XInternAtom(display, Mem.cstr("XdndDrop"), 0);
		XdndFinished = Xlib.XInternAtom(display, Mem.cstr("XdndFinished"), 0);
		XdndSelection = Xlib.XInternAtom(display, Mem.cstr("XdndSelection"), 0);
		XdndTypeList = Xlib.XInternAtom(display, Mem.cstr("XdndTypeList"), 0);
		XdndActionCopy = Xlib.XInternAtom(display, Mem.cstr("XdndActionCopy"), 0);
		XdndActionMove = Xlib.XInternAtom(display, Mem.cstr("XdndActionMove"), 0);
		XdndActionLink = Xlib.XInternAtom(display, Mem.cstr("XdndActionLink"), 0);
		XdndProxy = Xlib.XInternAtom(display, Mem.cstr("XdndProxy"), 0);
		URI_LIST = Xlib.XInternAtom(display, Mem.cstr("text/uri-list"), 0);
		HXMC_DND = Xlib.XInternAtom(display, Mem.cstr("HXMC_DND"), 0);
		NET_WM_STATE = Xlib.XInternAtom(display, Mem.cstr("_NET_WM_STATE"), 0);
		NET_WM_STATE_FULLSCREEN = Xlib.XInternAtom(display, Mem.cstr("_NET_WM_STATE_FULLSCREEN"), 0);
		NET_FRAME_EXTENTS = Xlib.XInternAtom(display, Mem.cstr("_NET_FRAME_EXTENTS"), 0);
		xev = LibC.malloc((X.EVENT_SIZE : Int64));
		openInputMethod();
		// (the main thread reads the connection while the program runs on its own: OsThread)
		if (OsThread.wanted()) {
			mainXev = LibC.malloc((X.EVENT_SIZE : Int64));
			wakeMain = pipe();
			wakeProgram = pipe();
			OsThread.waitMain = pump;
			OsThread.wakeMain = () -> pipeWrite(wakeMain >>> 16);
		}
	}

	// the input method in a UTF-8 locale (the environment's, else C.UTF-8);
	// the user's (XMODIFIERS), else Xlib's own (dead keys and compose)
	static function openInputMethod() {
		var l = Select.setlocale(0, Mem.cstr("")); // LC_CTYPE
		var name = l.isNull() ? "" : (cast l : CString).toString();
		if (name.indexOf("UTF-8") < 0 && name.indexOf("utf8") < 0 && name.indexOf("UTF8") < 0) Select.setlocale(0, Mem.cstr("C.UTF-8"));
		Xlib.XSetLocaleModifiers(Mem.cstr(""));
		im = Xlib.XOpenIM(display, Ptr.nil(), Ptr.nil(), Ptr.nil());
		if (im.isNull()) {
			Xlib.XSetLocaleModifiers(Mem.cstr("@im=none"));
			im = Xlib.XOpenIM(display, Ptr.nil(), Ptr.nil(), Ptr.nil());
		}
	}

	function dragFiles(paths:Array<String>, allowed:Array<DragOperation>, done:DragOperation->Void):Bool {
		if (!X11FileDrag.start(this, dragButton, dragTime, dragState, paths, allowed, done)) return false;
		dragButton = 0;
		return true;
	}

	function destroy() {
		var drag = X11FileDrag.active;
		if (drag != null && drag.window == this) drag.finish(DragOperation.None);
		#if hxmc.dev_host
		// (the host's window: left to the next build when handing over, else gone with the host's state)
		if (helder.dev.Hosted.hosted() && helder.dev.Hosted.get(helder.dev.Hosted.X11_WINDOW).toI64() == id) {
			if (helder.dev.Hosted.handingOver) {
				queueLock.acquire();
				open.remove(this);
				queueLock.release();
				if (!ic.isNull()) Xlib.XDestroyIC(ic);
				ic = Ptr.nil();
				if (open.length == 0) handOver();
				return;
			}
			helder.dev.Hosted.set(helder.dev.Hosted.X11_WINDOW, Ptr.nil());
			if (open.length == 1) helder.dev.Hosted.set(helder.dev.Hosted.X11_DISPLAY, Ptr.nil());
		}
		#end
		queueLock.acquire();
		open.remove(this);
		queueLock.release();
		if (!ic.isNull()) Xlib.XDestroyIC(ic);
		ic = Ptr.nil();
		#if helder.soft
		Blit.forget(surface);
		#end
		Xlib.XDestroyWindow(display, id);
		Xlib.XFlush(display);
		for (r in clipboardReads.copy())
			if (r.window == this) {
				clipboardReads.remove(r);
				r.callback(null);
			}
		if (open.length == 0) {
			// (the cursors and the selection go with the connection)
			cursors.resize(0);
			clipboardText = null;
			// (not while the main thread reads it)
			readLock.acquire();
			Xlib.XCloseDisplay(display);
			LibC.free(xev);
			display = Ptr.nil();
			readLock.release();
		}
	}

	// where it takes the pointer (Window.input: x, y, width, height in
	// pixels; null: everywhere): its input shape (XShape's ShapeInput),
	// elsewhere the pointer the windows' under it
	function setInput(rects:Null<Array<Int>>) {
		if (!XShape.ok) {
			Sys.println("helder.os: no libXext: the window takes the pointer everywhere");
			return;
		}
		if (rects == null) {
			// (no mask: the window's bounds again)
			XShape.XShapeCombineMask(display, id, 2, 0, 0, 0, 0);
		} else Arena.scoped(a -> {
			var n = rects.length >> 2, r:Ptr<UInt16> = a.alloc(8 * n + 8);
			for (i in 0...n * 4)
				r[i] = Std.int(Math.max(-32768, Math.min(32767, rects[i]))) & 0xFFFF;
			XShape.XShapeCombineRectangles(display, id, 2, 0, 0, r, n, 0, 0);
		});
		Xlib.XFlush(display);
	}

	// (Window.backdrop: KDE's blur behind the window, its whole area
	// (_KDE_NET_WM_BLUR_BEHIND_REGION empty); blur and mica alike, no glass;
	// none where no one made the atom: KWin does)
	function setBackdrop(b:WindowBackdrop):Bool {
		if (b == Glass) return false;
		var atom = Arena.scopedValue(a -> Xlib.XInternAtom(display, a.cstring("_KDE_NET_WM_BLUR_BEHIND_REGION"), 1));
		if (atom == 0) return b == None;
		if (b == None) Xlib.XDeleteProperty(display, id, atom) else Arena.scoped(a -> Xlib.XChangeProperty(display, id, atom, X.XA_CARDINAL, 32, X.PropModeReplace, a.alloc(8), 0));
		Xlib.XFlush(display);
		return true;
	}

	// (a transparent window's visual, 0: opaque)
	var visual = 0;

	// (a window of a 32-bit ARGB visual where a compositing manager runs
	// (_NET_WM_CM_S0 owned): its alpha composed; 0: none, opaque then)
	function clearWindow(screen:Int, width:Int, height:Int):Int64
		return Arena.scopedValue(a -> {
			if (Xlib.XGetSelectionOwner(display, Xlib.XInternAtom(display, a.cstring("_NET_WM_CM_S" + screen), 0)) == 0) {
				Sys.println("helder.os: no compositing manager on X11: the window opaque");
				return (0 : Int64);
			}
			var info:Ptr<Int64> = a.alloc(64);
			// (TrueColor 4)
			if (Xlib.XMatchVisualInfo(display, screen, 32, 4, info) == 0) {
				Sys.println("helder.os: no 32-bit visual on X11: the window opaque");
				return (0 : Int64);
			}
			var v = Ptr.ofI64(info[0]), root = Xlib.XRootWindow(display, screen), at:Ptr<Int64> = a.alloc(112);
			LibC.memset(at, 0, 112);
			at[12] = Xlib.XCreateColormap(display, root, v, 0);
			visual = haxe.Int64.toInt(info[1]);
			// (CWBackPixel, CWBorderPixel, CWColormap; InputOutput 1)
			return Xlib.XCreateWindow(display, root, 0, 0, width, height, 0, 32, 1, v, (1 << 1) | (1 << 3) | (1 << 13), at);
		});

	// the title: WM_NAME (Latin-1 for old window managers) and _NET_WM_NAME (UTF-8)
	function setTitle(t:String)
		Arena.scoped(a -> {
			Xlib.XStoreName(display, id, a.cstring(t));
			var utf8 = haxe.io.Bytes.ofString(t), p = a.alloc(utf8.length + 1);
			for (i in 0...utf8.length)
				(p : Ptr<UInt8>)[i] = utf8.get(i);
			Xlib.XChangeProperty(display, id, Xlib.XInternAtom(display, a.cstring("_NET_WM_NAME"), 0), UTF8_STRING, 8, 0, p, utf8.length);
			Xlib.XFlush(display);
		});

	function resize(w:Int, h:Int) {
		Xlib.XResizeWindow(display, id, w, h);
		Xlib.XFlush(display);
	}

	// (EWMH: a _NET_WM_STATE message to the root, add 1 or remove 0, from an application)
	function setFullscreen(on:Bool) {
		fullscreen = on;
		sendMessage(Xlib.XDefaultRootWindow(display), id, NET_WM_STATE, on ? 1 : 0, NET_WM_STATE_FULLSCREEN, 0, 1, 0,
			X.SubstructureRedirectMask | X.SubstructureNotifyMask);
		Xlib.XFlush(display);
	}

	// (Window.onTop, taskbar: an EWMH state asked of the window manager, added or removed)
	function setState(name:String, on:Bool) {
		Arena.scoped(a -> sendMessage(Xlib.XDefaultRootWindow(display), id, NET_WM_STATE, on ? 1 : 0, Xlib.XInternAtom(display, a.cstring(name), 0), 0, 1, 0,
			X.SubstructureRedirectMask | X.SubstructureNotifyMask));
		Xlib.XFlush(display);
	}

	// (Window.workArea: the window manager's _NET_WORKAREA, the current
	// desktop's first; without one the screen)
	function workArea():{x:Int, y:Int, width:Int, height:Int} {
		var p = Arena.scopedValue(a -> sourceProperty(Xlib.XDefaultRootWindow(display), Xlib.XInternAtom(display, a.cstring("_NET_WORKAREA"), 0)));
		if (p != null && p.format == 32 && p.bytes.length >= 32)
			return {x: p.bytes.getInt32(0), y: p.bytes.getInt32(8), width: p.bytes.getInt32(16), height: p.bytes.getInt32(24)};
		var s = Xlib.XDefaultScreen(display);
		return {x: 0, y: 0, width: Xlib.XDisplayWidth(display, s), height: Xlib.XDisplayHeight(display, s)};
	}

	function minimize() {
		Xlib.XIconifyWindow(display, id, Xlib.XDefaultScreen(display));
		Xlib.XFlush(display);
	}

	// (EWMH: _NET_WM_STATE's two maximised states, added or removed)
	function maximize(on:Bool) {
		maximized = on;
		Arena.scoped(a -> sendMessage(Xlib.XDefaultRootWindow(display), id, NET_WM_STATE, on ? 1 : 0, Xlib.XInternAtom(display, a.cstring("_NET_WM_STATE_MAXIMIZED_VERT"), 0),
			Xlib.XInternAtom(display, a.cstring("_NET_WM_STATE_MAXIMIZED_HORZ"), 0), 1, 0, X.SubstructureRedirectMask | X.SubstructureNotifyMask));
		Xlib.XFlush(display);
	}

	// an inset title bar's press at x, y (the root's: rx, ry): an edge or a
	// drag region given to the window manager (_NET_WM_MOVERESIZE: the
	// pointer's implicit grab let go first, as EWMH asks; button 1, from an
	// application), a double press on a drag region maximising. True: the
	// window manager's, not the app's
	function titlePress(x:Int, y:Int, rx:Int, ry:Int):Bool {
		if (owner.titlebar == Standard) return false;
		var app = owner.titlebarAt == null ? Content : owner.titlebarAt(x, y);
		var h = TitleBars.hit(x, y, surface.width, surface.height, 6, !maximized && !fullscreen, app);
		var d = TitleBars.x11(h);
		if (d < 0) return false;
		if (h == Drag) {
			var now = haxe.Timer.stamp();
			if (now - lastDrag < 0.4) {
				lastDrag = 0;
				maximize(!maximized);
				return true;
			}
			lastDrag = now;
		}
		Xlib.XUngrabPointer(display, 0);
		Arena.scoped(a -> sendMessage(Xlib.XDefaultRootWindow(display), id, Xlib.XInternAtom(display, a.cstring("_NET_WM_MOVERESIZE"), 0), rx, ry, d, 1, 1,
			X.SubstructureRedirectMask | X.SubstructureNotifyMask));
		Xlib.XFlush(display);
		return true;
	}

	// (EWMH: _NET_ACTIVE_WINDOW asked of the window manager, from an application; raised meanwhile)
	function raise() {
		Xlib.XRaiseWindow(display, id);
		sendMessage(Xlib.XDefaultRootWindow(display), id, Arena.scopedValue(a -> Xlib.XInternAtom(display, a.cstring("_NET_ACTIVE_WINDOW"), 0)), 1, 0, 0, 0, 0,
			X.SubstructureRedirectMask | X.SubstructureNotifyMask);
		Xlib.XFlush(display);
	}

	// the content's top left on the root window
	function position():{x:Int, y:Int}
		return Arena.scopedValue(a -> {
			var x:Ptr<Int32> = a.alloc(4), y:Ptr<Int32> = a.alloc(4), child:Ptr<Int64> = a.alloc(8);
			Xlib.XTranslateCoordinates(display, id, Xlib.XDefaultRootWindow(display), 0, 0, x, y, child);
			{x: x.value, y: y.value};
		});

	// (the window manager places its frame where the window asks: the
	// frame's left and top edges, _NET_FRAME_EXTENTS, taken off)
	function moveTo(x:Int, y:Int) {
		var p = takeProperty(NET_FRAME_EXTENTS, false);
		var left = 0, top = 0;
		if (p != null && p.format == 32 && p.bytes.length >= 32) {
			left = p.bytes.getInt32(0);
			top = p.bytes.getInt32(16);
		}
		Xlib.XMoveWindow(display, id, x - left, y - top);
		Xlib.XFlush(display);
	}

	// a client message of format 32 to a window (its five longs)
	static function sendMessage(to:Int64, window:Int64, type:Int64, l0:Int64, l1:Int64, l2:Int64, l3:Int64, l4:Int64, mask:Int)
		Arena.scoped(a -> {
			var raw:Ptr<UInt8> = a.alloc(X.EVENT_SIZE);
			for (i in 0...X.EVENT_SIZE)
				raw[i] = 0;
			var m:Ptr<XClientMessageEvent> = cast raw;
			m.value.type = X.ClientMessage;
			m.value.display = display;
			m.value.window = window;
			m.value.message_type = type;
			m.value.format = 32;
			// (data.l at 56: l[0] to l[4])
			var l:Ptr<Int64> = cast raw.add(56);
			l[0] = l0;
			l[1] = l1;
			l[2] = l2;
			l[3] = l3;
			l[4] = l4;
			Xlib.XSendEvent(display, to, 0, (mask : Int64), cast raw);
		});

	// XDND's messages to this window (the source's): an enter (does it carry
	// text/uri-list), positions (each answered: accepted with a copy, or
	// not), a leave, the drop (its files asked for: XdndSelection converted
	// into HXMC_DND, then dropArrived)
	function dnd(m:Ptr<XClientMessageEvent>):Bool {
		var raw:Ptr<UInt8> = cast m;
		var l:Ptr<Int64> = cast raw.add(56);
		var type = m.value.message_type;
		if (type == XdndEnter) {
			dndSource = l[0];
			dndFiles = false;
			if ((l[1].toInt() & 1) != 0) {
				var p = sourceProperty(dndSource, XdndTypeList);
				if (p != null) for (i in 0...p.bytes.length >> 3)
					if (p.bytes.getInt64(8 * i) == URI_LIST) dndFiles = true;
			} else for (i in 2...5)
				if (l[i] == URI_LIST) dndFiles = true;
			return true;
		}
		if (type == XdndPosition) {
			if (dndSource != l[0]) return true;
			var at = l[2].toInt();
			dndX = at >>> 16;
			dndY = at & 0xFFFF;
			sendMessage(dndSource, dndSource, XdndStatus, id, dndFiles ? 1 : 0, 0, 0, dndFiles ? XdndActionCopy : 0, 0);
			Xlib.XFlush(display);
			return true;
		}
		if (type == XdndLeave) {
			dndSource = 0;
			return true;
		}
		if (type == XdndDrop) {
			if (dndSource != l[0]) return true;
			if (!dndFiles) {
				sendMessage(dndSource, dndSource, XdndFinished, id, 0, 0, 0, 0, 0);
				dndSource = 0;
			} else
				Xlib.XConvertSelection(display, XdndSelection, URI_LIST, HXMC_DND, id, l[2]);
			Xlib.XFlush(display);
			return true;
		}
		return false;
	}

	// the dropped files arrived: their paths (Event.files), where the drop
	// was; the source told it is done
	function dropArrived(s:Ptr<XSelectionEvent>, e:Event):Bool {
		var p = s.value.property == (0 : Int64) ? null : takeProperty(s.value.property);
		var source = dndSource;
		dndSource = 0;
		if (source != (0 : Int64)) {
			sendMessage(source, source, XdndFinished, id, p != null ? 1 : 0, p != null ? XdndActionCopy : 0, 0, 0, 0);
			Xlib.XFlush(display);
		}
		if (p == null) return false;
		var files = UriList.paths(p.bytes.toString());
		if (files.length == 0) return false;
		Arena.scoped(a -> {
			var x:Ptr<Int32> = a.alloc(4), y:Ptr<Int32> = a.alloc(4), child:Ptr<Int64> = a.alloc(8);
			Xlib.XTranslateCoordinates(display, Xlib.XDefaultRootWindow(display), id, dndX, dndY, x, y, child);
			e.x = x.value;
			e.y = y.value;
		});
		e.kind = Drop;
		e.files = files;
		return true;
	}

	// another window's property (the source's XdndTypeList), not deleted
	static function sourceProperty(window:Int64, property:Int64):Null<{type:Int64, format:Int, bytes:haxe.io.Bytes}>
		return Arena.scopedValue(a -> {
			var type:Ptr<Int64> = a.alloc(8), format:Ptr<Int32> = a.alloc(4), count:Ptr<Int64> = a.alloc(8), after:Ptr<Int64> = a.alloc(8);
			var data:Ptr<Ptr> = a.alloc(8);
			if (Xlib.XGetWindowProperty(display, window, property, 0, 1024, 0, X.AnyPropertyType, type, format, count, after, data) != 0) null else {
				var n = count.value.toInt() * (format.value == 32 ? 8 : format.value == 16 ? 2 : 1);
				var b = haxe.io.Bytes.alloc(n);
				if (!data.value.isNull()) {
					if (n > 0) BytesPtr.copyIn(b, 0, data.value, n);
					Xlib.XFree(data.value);
				}
				{type: type.value, format: format.value, bytes: b};
			}
		});

	// WM_NORMAL_HINTS: XSizeHints with PMinSize (flags at 0, min_width and min_height at 24 and 28)
	function setMinSize(w:Int, h:Int)
		Arena.scoped(a -> {
			var hints = a.alloc(80);
			for (i in 0...80)
				(hints : Ptr<UInt8>)[i] = 0;
			(hints : Ptr<Int64>).value = 1 << 4;
			(hints.add(24) : Ptr<Int32>).value = w;
			(hints.add(28) : Ptr<Int32>).value = h;
			Xlib.XSetWMNormalHints(display, id, hints);
			Xlib.XFlush(display);
		});

	// (cursorfont.h: XC_left_ptr, XC_hand2, XC_xterm, XC_crosshair, XC_fleur,
	// XC_X_cursor, XC_sb_h_double_arrow, XC_sb_v_double_arrow; the font has no
	// open or closed hand: XC_hand1 and XC_fleur)
	function setCursor(c:Cursor) {
		var i:Int = c;
		while (cursors.length <= i)
			cursors.push(0);
		if (cursors[i] == 0) cursors[i] = Xlib.XCreateFontCursor(display, [68, 60, 152, 34, 52, 0, 108, 116, 58, 52][i]);
		Xlib.XDefineCursor(display, id, cursors[i]);
		Xlib.XFlush(display);
	}

	// owns CLIPBOARD with text (answering SelectionRequest from then on)
	function writeClipboard(text:String) {
		clipboardText = text;
		Xlib.XSetSelectionOwner(display, CLIPBOARD, id, 0);
		if (Xlib.XGetSelectionOwner(display, CLIPBOARD) != id) clipboardText = null;
		Xlib.XFlush(display);
	}

	// the text this process owns the clipboard with, else the owner's
	// (converted to UTF8_STRING into a property of this window: SelectionNotify)
	function readClipboard(callback:Null<String>->Void) {
		if (clipboardText != null && Xlib.XGetSelectionOwner(display, CLIPBOARD) == id) {
			callback(clipboardText);
			return;
		}
		if (Xlib.XGetSelectionOwner(display, CLIPBOARD) == 0) {
			callback(null);
			return;
		}
		clipboardReads.push({window: this, callback: callback});
		Xlib.XConvertSelection(display, CLIPBOARD, UTF8_STRING, HXMC_CLIPBOARD, id, 0);
		Xlib.XFlush(display);
	}

	// The clipboard's text (UTF-8 or Latin-1), or its list of formats.
	static function answerSelection(r:Ptr<XSelectionRequestEvent>) {
		Arena.scoped(a -> {
			var property = r.value.property == 0 ? r.value.target : r.value.property;
			var ok = clipboardText != null && r.value.selection == CLIPBOARD;
			if (ok) {
				if (r.value.target == TARGETS) {
					var atoms:Ptr<Int64> = a.alloc(24);
					atoms[0] = TARGETS;
					atoms[1] = UTF8_STRING;
					atoms[2] = X.XA_STRING;
					Xlib.XChangeProperty(display, r.value.requestor, property, X.XA_ATOM, 32, X.PropModeReplace, atoms, 3);
				} else if (r.value.target == UTF8_STRING || r.value.target == X.XA_STRING) {
					var b = r.value.target == UTF8_STRING ? haxe.io.Bytes.ofString(clipboardText) : latin1(clipboardText);
					sendSelectionBytes(a, r.value.requestor, property, r.value.target, b);
				} else ok = false;
			}
			notifySelection(a, r, ok ? property : 0);
		});
		Xlib.XFlush(display);
	}

	static function sendSelectionBytes(a:Arena, requestor:Int64, property:Int64, target:Int64, b:haxe.io.Bytes) {
		if (b.length > INCR_OVER) {
			// in parts: INCR (with the size), then each part as the requestor deletes the last
			var size:Ptr<Int64> = a.alloc(8);
			size.value = b.length;
			if (find(requestor) == null) Xlib.XSelectInput(display, requestor, (X.PropertyChangeMask : Int64));
			Xlib.XChangeProperty(display, requestor, property, INCR, 32, X.PropModeReplace, size, 1);
			sending.push({requestor: requestor, property: property, target: target, data: b, at: 0});
		} else
			Xlib.XChangeProperty(display, requestor, property, target, 8, X.PropModeReplace, a.copyBytes(b), b.length);
	}

	static function notifySelection(a:Arena, r:Ptr<XSelectionRequestEvent>, property:Int64) {
		var raw = a.alloc(X.EVENT_SIZE);
		var n:Ptr<XSelectionEvent> = raw;
		n.value.type = X.SelectionNotify;
		n.value.display = display;
		n.value.requestor = r.value.requestor;
		n.value.selection = r.value.selection;
		n.value.target = r.value.target;
		n.value.property = property;
		n.value.time = r.value.time;
		Xlib.XSendEvent(display, r.value.requestor, 0, 0, raw);
	}

	static function latin1(s:String):haxe.io.Bytes {
		var b = haxe.io.Bytes.alloc(s.length);
		for (i in 0...s.length) {
			var c = StringTools.fastCodeAt(s, i);
			b.set(i, c < 256 ? c : "?".code);
		}
		return b;
	}

	// the parts of a selection coming in (INCR), and their type
	var incoming:Null<haxe.io.BytesBuffer> = null;
	var incomingType:Int64 = 0;

	// the property's contents, deleted (null: none)
	function takeProperty(property:Int64, delete = true):Null<{type:Int64, format:Int, bytes:haxe.io.Bytes}>
		return Arena.scopedValue(a -> {
			var type:Ptr<Int64> = a.alloc(8), format:Ptr<Int32> = a.alloc(4), count:Ptr<Int64> = a.alloc(8), after:Ptr<Int64> = a.alloc(8);
			var data:Ptr<Ptr> = a.alloc(8);
			if (Xlib.XGetWindowProperty(display, id, property, 0, 1 << 24, delete ? 1 : 0, X.AnyPropertyType, type, format, count, after, data) != 0) null else {
				// (32-bit items come as longs)
				var n = count.value.toInt() * (format.value == 32 ? 8 : format.value == 16 ? 2 : 1);
				var b = haxe.io.Bytes.alloc(n);
				if (!data.value.isNull()) {
					if (n > 0) BytesPtr.copyIn(b, 0, data.value, n);
					Xlib.XFree(data.value);
				}
				{type: type.value, format: format.value, bytes: b};
			}
		});

	static function decode(type:Int64, b:haxe.io.Bytes):Null<String>
		return type == UTF8_STRING ? b.toString() : type == X.XA_STRING ? [for (i in 0...b.length) String.fromCharCode(b.get(i))].join("") : null;

	// the converted selection arrived (or was refused): the first read of
	// this window gets it; one sent in parts (INCR) when its last part comes
	function selectionArrived(e:Ptr<XSelectionEvent>) {
		var text:Null<String> = null;
		if (e.value.property != (0 : Int64)) {
			var p = takeProperty(e.value.property);
			if (p != null && p.type == INCR) {
				// (its deletion, done, asks for the first part)
				incoming = new haxe.io.BytesBuffer();
				Xlib.XFlush(display);
				return;
			}
			if (p != null && p.format == 8) text = decode(p.type, p.bytes);
		}
		deliver(text);
	}

	// a part of an incoming selection (a property with a new value): the last, empty, ends it
	function partArrived(property:Int64) {
		var p = takeProperty(property);
		Xlib.XFlush(display);
		if (p == null) return;
		if (p.bytes.length > 0) {
			incoming.add(p.bytes);
			incomingType = p.type;
			return;
		}
		var all = incoming.getBytes();
		incoming = null;
		deliver(decode(incomingType, all));
	}

	// the next part of a selection sent in parts, after the requestor deleted the last
	static function nextPart(requestor:Int64, property:Int64) {
		for (s in sending)
			if (s.requestor == requestor && s.property == property) {
				var n = s.data.length - s.at;
				if (n > PART) n = PART;
				Arena.scoped(a -> {
					var p:Ptr = n > 0 ? a.copyBytes(s.data.sub(s.at, n)) : a.alloc(1);
					Xlib.XChangeProperty(display, requestor, property, s.target, 8, X.PropModeReplace, p, n);
				});
				s.at += n;
				// (the empty part sent: done)
				if (n == 0) sending.remove(s);
				Xlib.XFlush(display);
				return;
			}
	}

	function deliver(text:Null<String>) {
		for (r in clipboardReads)
			if (r.window == this) {
				clipboardReads.remove(r);
				r.callback(text);
				break;
			}
	}

	static function find(id:Int64):Null<X11Window> {
		for (w in open)
			if (w.id == id) return w;
		return null;
	}

	// dispatches the pending events: those the main thread read, where it
	// reads them (routed as it read them), else the connection's
	static function poll(onEvent:Event->Void) {
		if (OsThread.program != 0 && wakeMain >= 0) {
			pipeDrain(wakeProgram & 0xFFFF);
			queueLock.acquire();
			var events = queued.copy(), routes = queuedRoutes.copy();
			queued.resize(0);
			queuedRoutes.resize(0);
			queueLock.release();
			for (i in 0...events.length) {
				LibC.memcpy(xev, BytesPtr.of(events[i], 0, X.EVENT_SIZE), (X.EVENT_SIZE : Int64));
				free.push(events[i]);
				preRouted = routes[2 * i];
				preGesture = routes[2 * i + 1];
				handle(onEvent);
			}
			preRouted = -1;
			X11FileDrag.active?.tick();
			return;
		}
		while (!display.isNull() && Xlib.XPending(display) > 0) {
			Xlib.XNextEvent(display, xev);
			handle(onEvent);
		}
		X11FileDrag.active?.tick();
	}

	// (the XEvent in xev dispatched)
	static function handle(onEvent:Event->Void) {
		{
			var any:Ptr<XAnyEvent> = xev, drag = X11FileDrag.active;
			if (drag != null && any.value.window == drag.window.id && drag.input(any.value.type, xev)) return;
			// (what the input method takes: a dead key, a compose sequence's keys)
			if (!im.isNull() && Xlib.XFilterEvent(xev, 0) != 0) return;
			// (the keyboard mapping changed: another layout; it has no window)
			if (any.value.type == X.MappingNotify) {
				Xlib.XRefreshKeyboardMapping(xev);
				return;
			}
			// (a requestor deleted a part this process sent: the next)
			if (any.value.type == X.PropertyNotify) {
				var pe:Ptr<XPropertyEvent> = xev;
				if (pe.value.state == X.PropertyDelete) nextPart(pe.value.window, pe.value.atom);
				var pw = find(pe.value.window);
				if (pe.value.state == X.PropertyNewValue && pw != null && pw.incoming != null && pe.value.atom == HXMC_CLIPBOARD) pw.partArrived(pe.value.atom);
				return;
			}
			var w = find(any.value.window);
			if (w == null) return;
			var e = event;
			e.kind = None;
			e.window = w.owner;
			switch any.value.type {
				case X.ClientMessage:
					var m:Ptr<XClientMessageEvent> = xev;
					if (!(drag != null && drag.window == w && drag.clientMessage(m)) && !w.dnd(m) && m.value.l0 == wmDelete) e.kind = Close;
				case X.SelectionRequest:
					var request:Ptr<XSelectionRequestEvent> = xev;
					if (drag != null && drag.window == w && request.value.selection == XdndSelection) drag.answer(request) else answerSelection(request);
				case X.SelectionClear:
					var clear:Ptr<XSelectionClearEvent> = xev;
					if (clear.value.selection == CLIPBOARD) clipboardText = null;
					if (clear.value.selection == XdndSelection && drag != null && drag.window == w
						&& Xlib.XGetSelectionOwner(display, XdndSelection) != w.id) drag.finish(DragOperation.None);
				case X.SelectionNotify:
					var s:Ptr<XSelectionEvent> = xev;
					if (s.value.selection == XdndSelection) w.dropArrived(s, e) else w.selectionArrived(xev);
				case X.Expose:
					var x:Ptr<XExposeEvent> = xev;
					// (a frame drawn on the CPU: the server keeps none, the last one put again)
					#if helder.soft
					if (x.value.count == 0) Blit.repaint(w.surface, Ptr.nil());
					#end
					if (x.value.count == 0) e.kind = Redraw;
				case X.ConfigureNotify:
					var c:Ptr<XConfigureEvent> = xev;
					if (c.value.width != w.surface.width || c.value.height != w.surface.height) {
						w.surface.resized(c.value.width, c.value.height);
						#if hxmc.dev_host
						if (helder.dev.Hosted.hosted() && helder.dev.Hosted.get(helder.dev.Hosted.X11_WINDOW).toI64() == w.id) {
							helder.dev.Hosted.set(helder.dev.Hosted.WIDTH, Ptr.ofI64(c.value.width));
							helder.dev.Hosted.set(helder.dev.Hosted.HEIGHT, Ptr.ofI64(c.value.height));
						}
						#end
						e.kind = Resize;
						e.x = c.value.width;
						e.y = c.value.height;
					}
				case t = X.KeyPress | X.KeyRelease:
					var k:Ptr<XKeyEvent> = xev;
					e.kind = t == X.KeyPress ? KeyDown : KeyUp;
					e.key = Xlib.XLookupKeysym(xev, 0).toInt();
					e.mods = mods(k.value.state);
					if (t == X.KeyPress) {
						dispatch(e, onEvent);
						// then its characters
						var s = w.typed(k);
						if (s == "" || e.mods & (Mods.CONTROL | Mods.ALT) != 0) return;
						e.kind = TextInput;
						e.text = s;
					}
				case t = X.ButtonPress | X.ButtonRelease | X.MotionNotify:
					var b:Ptr<XKeyEvent> = xev;
					var button = t == X.MotionNotify ? 0 : (b.value.keycode : Int);
					e.x = b.value.x;
					e.y = b.value.y;
					e.mods = mods(b.value.state);
					if (button >= 4 && button <= 7) {
						// (the wheel: buttons 4 and 5 up and down, 6 and 7 left and right; a notch on the press)
						if (t != X.ButtonPress) return;
						e.kind = Scroll;
						e.deltaX = button == 6 ? -40 : button == 7 ? 40 : 0;
						e.deltaY = button == 4 ? -40 : button == 5 ? 40 : 0;
					} else {
						if (t == X.ButtonPress && button == 1 && w.titlePress(b.value.x, b.value.y, b.value.x_root, b.value.y_root)) return;
						if (t == X.ButtonPress && button >= 1 && button <= 3) w.dragButton = button;
						if (t == X.ButtonRelease && w.dragButton == button) w.dragButton = 0;
						if (t == X.MotionNotify && w.dragButton != 0 && b.value.state & (1 << (7 + w.dragButton)) == 0) w.dragButton = 0;
						w.dragTime = b.value.time;
						w.dragState = b.value.state;
						e.kind = t == X.ButtonPress ? MouseDown : t == X.ButtonRelease ? MouseUp : MouseMove;
						e.button = button;
					}
			}
			if (e.kind != None) dispatch(e, onEvent);
		}
	}

	// (e to the program, routed by its window's compositor: as the main thread read it, else now)
	static function dispatch(e:Event, onEvent:Event->Void) {
		if (preRouted >= 0) {
			e.routed = preRouted;
			e.gesture = preGesture;
			preRouted = -1;
		} else
			Window.routed(e);
		onEvent(e);
	}

	// --- the input read on the main thread while the program runs on (OsThread.waitMain)

	// (the events read, each an XEvent's bytes, their routes and gestures; spare buffers; the main thread's XEvent)
	static final queued:Array<haxe.io.Bytes> = [];
	static final queuedRoutes:Array<Int> = [];
	static final free:Array<haxe.io.Bytes> = [];
	static final queueLock = new sys.thread.Mutex();
	// (held while the main thread reads the connection: closed only outside it)
	static final readLock = new sys.thread.Mutex();
	static var mainXev:Ptr = Ptr.nil();
	static var preRouted = -1;
	static var preGesture = 0;
	// (the pipes that wake the main thread, a call handed to it, and the program's wait, events read: read | write << 16)
	static var wakeMain = -1;
	static var wakeProgram = -1;
	static final peeked = new Event();

	// the main thread's wait: the connection read (at most 50 ms: what a
	// reply's read on the program's thread queued is taken then), each input
	// event routed to its window's compositor at once, queued for the
	// program's poll, which is woken
	static function pump():Bool {
		readLock.acquire();
		var d = display;
		var fd = d.isNull() ? -1 : Xlib.XConnectionNumber(d), pending = d.isNull() ? 0 : Xlib.XPending(d);
		readLock.release();
		if (fd < 0) return false;
		if (pending == 0) waitTwo(fd, wakeMain & 0xFFFF, 0.05);
		pipeDrain(wakeMain & 0xFFFF);
		var any = false;
		readLock.acquire();
		while (!display.isNull() && Xlib.XPending(display) > 0) {
			Xlib.XNextEvent(display, mainXev);
			queueLock.acquire();
			var b = free.length > 0 ? free.pop() : haxe.io.Bytes.alloc(X.EVENT_SIZE);
			queueLock.release();
			BytesPtr.copyIn(b, 0, mainXev, X.EVENT_SIZE);
			var e = peek(mainXev), r = 0, g = 0;
			if (e != null) {
				Window.routed(e);
				r = e.routed;
				g = e.gesture;
			}
			queueLock.acquire();
			queued.push(b);
			queuedRoutes.push(r);
			queuedRoutes.push(g);
			queueLock.release();
			any = true;
		}
		readLock.release();
		if (any) pipeWrite(wakeProgram >>> 16);
		return true;
	}

	// (what handle would make of an input event for the compositor, nothing else done)
	static function peek(x:Ptr):Null<Event> {
		var any:Ptr<XAnyEvent> = x, e = peeked;
		queueLock.acquire();
		var w = find(any.value.window);
		queueLock.release();
		if (w == null) return null;
		if (X11FileDrag.active?.window == w) return null;
		e.window = w.owner;
		e.phase = e.momentum = 0;
		e.eased = false;
		switch any.value.type {
			case X.KeyPress:
				var k:Ptr<XKeyEvent> = x;
				e.kind = KeyDown;
				e.key = Xlib.XLookupKeysym(x, 0).toInt();
				e.mods = mods(k.value.state);
			case t = X.ButtonPress | X.ButtonRelease | X.MotionNotify:
				var b:Ptr<XKeyEvent> = x;
				var button = t == X.MotionNotify ? 0 : (b.value.keycode : Int);
				e.x = b.value.x;
				e.y = b.value.y;
				e.mods = mods(b.value.state);
				if (button >= 4 && button <= 7) {
					if (t != X.ButtonPress) return null;
					e.kind = Scroll;
					e.deltaX = button == 6 ? -40 : button == 7 ? 40 : 0;
					e.deltaY = button == 4 ? -40 : button == 5 ? 40 : 0;
				} else {
					e.kind = t == X.ButtonPress ? MouseDown : t == X.ButtonRelease ? MouseUp : MouseMove;
					e.button = button;
				}
			case _:
				return null;
		}
		return e;
	}

	// (a pipe: read | write << 16, non-blocking; -1 none)
	static function pipe():Int {
		var ends = pipeEnds();
		if (ends < 0) return -1;
		Posix.fcntl(ends & 0xFFFF, 4, 0x800);
		Posix.fcntl(ends >>> 16, 4, 0x800);
		return ends;
	}

	// (POSIX's, none in WebAssembly)
	#if (hxmc.target != "wasm32-wasi")
	@:hxmc.kernel static function pipeEnds():Int {
		var fds:hxmc.Span<Int> = hxmc.Span.stack(2);
		return helder.async.Fds.pipe(fds) != 0 ? -1 : fds[0] | (fds[1] << 16);
	}

	@:hxmc.kernel static function pipeWrite(fd:Int) {
		var b:hxmc.Span<UInt8> = hxmc.Span.stack(1);
		b[0] = 1;
		helder.async.Fds.write(fd, b);
	}

	@:hxmc.kernel static function pipeDrain(fd:Int) {
		var b:hxmc.Span<UInt8> = hxmc.Span.stack(64);
		while (helder.async.Fds.read(fd, b) > 0) {}
	}
	#else
	static function pipeEnds():Int
		return -1;

	static function pipeWrite(fd:Int) {}

	static function pipeDrain(fd:Int) {}
	#end

	// (until either descriptor has data (b < 0: a alone), or seconds; ppoll, as Wayland waits)
	static function waitTwo(a:Int, b:Int, seconds:Float) {
		Arena.scoped(m -> {
			var pfd:Ptr<Int32> = cast m.alloc(16);
			pfd[0] = a;
			pfd[1] = 1;
			pfd[2] = b;
			pfd[3] = 1;
			var ts:Ptr<Int64> = cast m.alloc(16);
			ts[0] = Std.int(seconds);
			ts[1] = Std.int((seconds - Std.int(seconds)) * 1e9);
			helder.os.linux.wayland.WaylandClient.WlLibc.ppoll(pfd, b < 0 ? 1 : 2, ts, Ptr.nil());
		});
	}

	// waits for the connection's socket to have data, or seconds
	// (App.wait: with helder.async's loop, its wait, the connection among what it polls)
	static function waitFor(seconds:Float) {
		var loop = helder.async.Driven.MainLoop.main;
		if (loop == null) return wait(seconds);
		if (X11FileDrag.active != null) seconds = X11FileDrag.active.waitTime(seconds);
		// (the main thread reads the connection: woken by its pipe once it queued events)
		if (OsThread.program != 0 && wakeProgram >= 0) {
			queueLock.acquire();
			var any = queued.length > 0;
			queueLock.release();
			if (!any) loop.wait(seconds, wakeProgram & 0xFFFF);
			return;
		}
		if (!display.isNull() && Xlib.XPending(display) > 0) return;
		loop.wait(seconds, display.isNull() ? -1 : Xlib.XConnectionNumber(display));
	}

	static function wait(seconds:Float) {
		if (X11FileDrag.active != null) seconds = X11FileDrag.active.waitTime(seconds);
		if (OsThread.program != 0 && wakeProgram >= 0) {
			queueLock.acquire();
			var any = queued.length > 0;
			queueLock.release();
			if (!any) waitTwo(wakeProgram & 0xFFFF, -1, seconds);
			return;
		}
		if (display.isNull() || Xlib.XPending(display) > 0) return;
		var fd = Xlib.XConnectionNumber(display);
		Arena.scoped(a -> {
			var set:Ptr<Int64> = a.alloc(128);
			set[fd >> 6] = (1 : Int64) << (fd & 63);
			var tv:Ptr<Int64> = a.alloc(16);
			tv[0] = Std.int(seconds);
			tv[1] = Std.int((seconds - Std.int(seconds)) * 1e6);
			Select.select(fd + 1, set, Ptr.nil(), Ptr.nil(), tv);
		});
	}

	// the modifiers of an event's state (ShiftMask, ControlMask, Mod1Mask: Alt, Mod4Mask: Super)
	static function mods(state:Int):Int
		return (state & 1 != 0 ? Mods.SHIFT : 0) | (state & 4 != 0 ? Mods.CONTROL : 0) | (state & 8 != 0 ? Mods.ALT : 0) | (state & 64 != 0 ? Mods.META : 0);

	// what a key press types: the input context's text (UTF-8), else the
	// KeySym's character; control characters left out
	function typed(k:Ptr<XKeyEvent>):String {
		if (ic.isNull()) {
			var cp = character(k);
			return cp == 0 ? "" : String.fromCharCode(cp);
		}
		return Arena.scopedValue(a -> {
			var buf:Ptr<UInt8> = a.alloc(64), ks:Ptr<Int64> = a.alloc(8), status:Ptr<Int32> = a.alloc(4);
			var n = Xlib.Xutf8LookupString(ic, k, buf, 63, ks, status);
			// (XLookupChars 2, XLookupBoth 4: text there)
			if (n <= 0 || (status.value != 2 && status.value != 4)) "" else {
				var b = haxe.io.Bytes.alloc(n);
				for (i in 0...n)
					b.set(i, buf[i]);
				var s = b.toString();
				var c = StringTools.fastCodeAt(s, 0);
				c < 0x20 || c == 0x7F ? "" : s;
			}
		});
	}

	// the code point a key press types (0: none): its KeySym with the
	// modifiers applied, Latin-1 or a Unicode KeySym (0x100xxxx)
	static function character(k:Ptr<XKeyEvent>):Int
		return Arena.scopedValue(a -> {
			var buf = a.alloc(16);
			var ks:Ptr<Int64> = a.alloc(8);
			Xlib.XLookupString(k, buf, 15, ks, Ptr.nil());
			var s = ks.value.toInt();
			s >= 0x20 && s <= 0x7E || s >= 0xA0 && s <= 0xFF ? s : s & 0xFF000000 == 0x01000000 ? s & 0xFFFFFF : 0;
		});
}
