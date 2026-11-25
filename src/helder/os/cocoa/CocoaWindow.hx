package helder.os.cocoa;

import helder.os.DragOperation;
import helder.os.Event;
import helder.os.TitleBar;
import helder.os.objc.*;
import hxmc.unsafe.*;

// helder.os.Window on macOS: an NSWindow whose content view hosts a
// CAMetalLayer. One NSApplication for the process, set up with the first
// window. The loop stays hxmc's own (App.run): each frame drains Cocoa's
// event queue without waiting (nextEventMatchingMask with a past date) and
// the frame's pace comes from the layer's drawables (vsync), as on X11; a
// display link would call back on another thread, and the GPU layer is main
// thread only. A delegate class made at run time turns the close button into
// a Close event, resizes into Resize events and a new backing scale (another
// display) into ScaleChange (from inside sendEvent:). A drag of the window's
// edge is AppKit's own loop until the mouse is up: each of its resizes draws
// a frame (onFrame), and the layer shows a drawable of another size at its
// top left, unscaled, until the next.
// The content view holds the layer's view and, under it, a text view of a
// class made at run time (HxmcTextView): while text input is on
// (Window.startTextInput) it is the first responder, placed at the caret,
// and the keys go through it (interpretKeyEvents:), so that input methods
// and dead keys compose in it: its marked text comes as TextEditing events,
// what it is given to insert as TextInput (and not kept), its commands
// (moves, deletions: KeyDown's) ignored.
// The application has the menu bar Mac apps have: its own menu (Hide,
// Hide Others, Show All, Quit) and a Window menu (Minimize, Zoom, Close,
// the windows), their shortcuts taken before the keys are ours. Quit (and
// the Dock's) asks every window to close: a Close event each, as their
// close buttons; the app ends when it closes them.
// Sizes and positions are in pixels (points times the backing scale), y down.
@:allow(helder.os)
@:hxmc.unsafe(gc)
class CocoaWindow {
	static var app = Ptr.nil();
	static var delegate = Ptr.nil();
	static var mode = Ptr.nil(); // the run loop's default mode, an NSString
	static var textViewClass = Ptr.nil();
	static final event = new Event();
	static final open:Array<CocoaWindow> = [];
	// the App.run callbacks, for the delegate's events and a live resize's frames
	static var onEvent:Null<Event->Void>;
	static var onFrame:Null<Void->Void>;

	final owner:Window;
	final window:Ptr; // NSWindow*
	final view:Ptr; // the layer's view, filling the content view
	final textView:Ptr; // HxmcTextView, under it
	// text input on; the composition last told (TextEditing)
	var typing = false;
	var marked = "";
	final layer:Ptr; // CAMetalLayer*
	final surface:Surface;
	var scale = 1.0;
	var cursor:Cursor = Default;
	var dragEvent = Ptr.nil();
	var over = false; // the pointer over the content, at the last move
	// (an NSRect and a CGSize to pass by value)
	final rect:Ptr<CGRect>;
	final size:Ptr<CGSize>;

	// (made on the main thread, as AppKit's windows must be: OsThread)
	static function make(owner:Window, title:String, width:Int, height:Int):CocoaWindow
		return OsThread.get(() -> new CocoaWindow(owner, title, width, height));

	function new(owner:Window, title:String, width:Int, height:Int) {
		this.owner = owner;
		if (app.isNull()) start();
		rect = LibC.malloc(32);
		size = LibC.malloc(16);
		rect.value.origin.x = 0;
		rect.value.origin.y = 0;
		rect.value.size.width = width;
		rect.value.size.height = height;
		#if hxmc.dev_host
		// (hxmc dev's host: the first window, its views and layer as the last build left them)
		var kept = helder.dev.Hosted.hosted() && open.length == 0 ? helder.dev.Hosted.get(helder.dev.Hosted.UI_WINDOW) : Ptr.nil();
		if (!kept.isNull()) {
			window = kept;
			textView = helder.dev.Hosted.get(helder.dev.Hosted.UI_CONTROLLER);
			view = helder.dev.Hosted.get(helder.dev.Hosted.UI_VIEW);
			Msg.vBool(textView, ObjC.sel("setHidden:"), true);
			layer = helder.dev.Hosted.get(helder.dev.Hosted.MAC_LAYER);
			var t = ObjC.str(title);
			Msg.vPtr(window, ObjC.sel("setTitle:"), t);
			ObjC.release(t);
			surface = new Surface(Cocoa, layer, view, width, height);
			open.push(this);
			measure();
			return;
		}
		#end
		// titled, closable, miniaturizable, resizable (inset: the content under
		// the title bar, NSWindowStyleMaskFullSizeContentView); buffered backing
		var inset = owner.titlebar == Inset;
		window = Msg.idRectIntIntBool(Msg.id(ObjC.cls("NSWindow"), ObjC.sel("alloc")), ObjC.sel("initWithContentRect:styleMask:backing:defer:"), rect.value,
			(inset ? 15 | 1 << 15 : 15 : Int64), 2, false);
		if (inset) {
			// (the bar drawn by nothing but its buttons; no title: NSWindowTitleHidden)
			Msg.vBool(window, ObjC.sel("setTitlebarAppearsTransparent:"), true);
			Msg.vInt(window, ObjC.sel("setTitleVisibility:"), 1);
		}
		Msg.vBool(window, ObjC.sel("setReleasedWhenClosed:"), false);
		var t = ObjC.str(title);
		Msg.vPtr(window, ObjC.sel("setTitle:"), t);
		ObjC.release(t);
		Msg.vPtr(window, ObjC.sel("setDelegate:"), delegate);
		Msg.vBool(window, ObjC.sel("setAcceptsMouseMovedEvents:"), true);
		// (files dragged onto it: public.file-url; a full-screen space of its own: NSWindowCollectionBehaviorFullScreenPrimary)
		var pool = Runtime.objc_autoreleasePoolPush();
		var type = ObjC.str("public.file-url");
		Msg.vPtr(window, ObjC.sel("registerForDraggedTypes:"), Msg.idPtr(ObjC.cls("NSArray"), ObjC.sel("arrayWithObject:"), type));
		ObjC.release(type);
		Runtime.objc_autoreleasePoolPop(pool);
		Msg.vInt(window, ObjC.sel("setCollectionBehavior:"), 1 << 7);
		// (no line under the title bar: it would hide the content's top pixels)
		Msg.vInt(window, ObjC.sel("setTitlebarSeparatorStyle:"), 1);
		var content = Msg.id(window, ObjC.sel("contentView"));
		textView = Msg.idRect(Msg.id(textViewClass, ObjC.sel("alloc")), ObjC.sel("initWithFrame:"), rect.value);
		Msg.vBool(textView, ObjC.sel("setRichText:"), false);
		// (hidden while text input is off: shown, it takes the clicks over it,
		// their drags and releases, and shows its I-beam)
		Msg.vBool(textView, ObjC.sel("setHidden:"), true);
		Msg.vPtr(content, ObjC.sel("addSubview:"), textView);
		view = Msg.idRect(Msg.id(ObjC.cls("NSView"), ObjC.sel("alloc")), ObjC.sel("initWithFrame:"), rect.value);
		Msg.vInt(view, ObjC.sel("setAutoresizingMask:"), 18); // (width and height sizable)
		Msg.vPtr(content, ObjC.sel("addSubview:"), view);
		// a layer-hosting view: the layer first, then wantsLayer
		// (-D helder.soft: a plain layer, the CPU's frames its contents: helder.os.Blit)
		layer = Runtime.objc_retain(Msg.id(ObjC.cls(#if helder.soft "CALayer" #else "CAMetalLayer" #end), ObjC.sel("layer")));
		// (a drawable of another size than the view's, between a resize and its
		// frame: shown as it is, not stretched)
		var gravity = ObjC.str("topLeft");
		Msg.vPtr(layer, ObjC.sel("setContentsGravity:"), gravity);
		ObjC.release(gravity);
		Msg.vPtr(view, ObjC.sel("setLayer:"), layer);
		Msg.vBool(view, ObjC.sel("setWantsLayer:"), true);
		surface = new Surface(Cocoa, layer, view, width, height);
		// (transparent: the window and its layer not opaque, nothing drawn behind the layer's pixels)
		if (owner.clear) {
			Msg.vBool(window, ObjC.sel("setOpaque:"), false);
			Msg.vPtr(window, ObjC.sel("setBackgroundColor:"), Msg.id(ObjC.cls("NSColor"), ObjC.sel("clearColor")));
			Msg.vBool(layer, ObjC.sel("setOpaque:"), false);
			surface.see(true);
		}
		open.push(this);
		#if hxmc.dev_host
		if (helder.dev.Hosted.hosted() && open.length == 1) {
			helder.dev.Hosted.set(helder.dev.Hosted.UI_WINDOW, window);
			helder.dev.Hosted.set(helder.dev.Hosted.UI_CONTROLLER, textView);
			helder.dev.Hosted.set(helder.dev.Hosted.UI_VIEW, view);
			helder.dev.Hosted.set(helder.dev.Hosted.MAC_LAYER, layer);
		}
		#end
		measure();
		Msg.v(window, ObjC.sel("center"));
		// (shown with its first frame, not as an empty window before it; a
		// program slow to draw, or drawing nothing, shown after half a second)
		surface.onPresent = show;
		haxe.Timer.delay(show, 500);
	}

	var shown = false;

	// (the device's, on the program's thread: OsThread)
	function show()
		OsThread.run(showNow);

	function showNow() {
		surface.onPresent = null;
		if (shown || open.indexOf(this) < 0) return;
		shown = true;
		raise();
		// (a transparent window's shadow made from its first frame, not the empty window)
		if (surface.transparent) Msg.v(window, ObjC.sel("invalidateShadow"));
		// (shown, AppKit lays its title bar out again: the buttons back where the app placed them)
		layoutControls();
	}

	// (the app's icon in the Dock while it runs unbundled: HELDER_APP_ICON, a PNG
	// helder dev and run make from the manifest; a bundle's is its own)
	static function dockIcon() {
		var path = Sys.getEnv("HELDER_APP_ICON");
		if (path == null || path == "" || !sys.FileSystem.exists(path)) return;
		var s = ObjC.str(path);
		var img = Msg.idPtr(Msg.id(ObjC.cls("NSImage"), ObjC.sel("alloc")), ObjC.sel("initWithContentsOfFile:"), s);
		ObjC.release(s);
		if (img.isNull()) return;
		Msg.vPtr(app, ObjC.sel("setApplicationIconImage:"), img);
		ObjC.release(img);
	}

	static function start() {
		// (loads AppKit: its classes are found by name, so nothing else imports from it)
		AppKit.NSApplicationLoad();
		app = Msg.id(ObjC.cls("NSApplication"), ObjC.sel("sharedApplication"));
		dockIcon();
		#if hxmc.dev_host
		// (hxmc dev: the classes an earlier build made, their methods this build's; its delegate)
		var made = Runtime.objc_getClass(Mem.cstr("HxmcWindowDelegate"));
		if (!made.isNull() && helder.dev.Hosted.hosted()) {
			mode = ObjC.str("kCFRunLoopDefaultMode");
			Runtime.class_replaceMethod(made, ObjC.sel("windowShouldClose:"), Callback.addr(shouldClose), Mem.cstr("c@:@"));
			Runtime.class_replaceMethod(made, ObjC.sel("windowDidResize:"), Callback.addr(didResize), Mem.cstr("v@:@"));
			Runtime.class_replaceMethod(made, ObjC.sel("windowDidBecomeKey:"), Callback.addr(didChangeKey), Mem.cstr("v@:@"));
			Runtime.class_replaceMethod(made, ObjC.sel("windowDidResignKey:"), Callback.addr(didChangeKey), Mem.cstr("v@:@"));
			Runtime.class_replaceMethod(made, ObjC.sel("windowDidChangeBackingProperties:"), Callback.addr(didChangeScale), Mem.cstr("v@:@"));
			Runtime.class_replaceMethod(made, ObjC.sel("windowWillStartLiveResize:"), Callback.addr(startResize), Mem.cstr("v@:@"));
			Runtime.class_replaceMethod(made, ObjC.sel("windowDidEndLiveResize:"), Callback.addr(endResize), Mem.cstr("v@:@"));
			Runtime.class_replaceMethod(made, ObjC.sel("liveFrame:"), Callback.addr(liveFrame), Mem.cstr("v@:@"));
			Runtime.class_replaceMethod(made, ObjC.sel("applicationShouldTerminate:"), Callback.addr(shouldTerminate), Mem.cstr("Q@:@"));
		Runtime.class_replaceMethod(made, ObjC.sel("draggingEntered:"), Callback.addr(dragEntered), Mem.cstr("Q@:@"));
		Runtime.class_replaceMethod(made, ObjC.sel("draggingUpdated:"), Callback.addr(dragEntered), Mem.cstr("Q@:@"));
		Runtime.class_replaceMethod(made, ObjC.sel("prepareForDragOperation:"), Callback.addr(prepareDrag), Mem.cstr("c@:@"));
		Runtime.class_replaceMethod(made, ObjC.sel("performDragOperation:"), Callback.addr(performDrag), Mem.cstr("c@:@"));
			Runtime.class_replaceMethod(made, ObjC.sel("application:openURLs:"), Callback.addr(openURLs), Mem.cstr("v@:@@"));
			Runtime.class_replaceMethod(made, ObjC.sel("getURL:withReply:"), Callback.addr(getURL), Mem.cstr("v@:@@"));
			delegate = helder.dev.Hosted.get(helder.dev.Hosted.MAC_DELEGATE);
			var t = Runtime.objc_getClass(Mem.cstr("HxmcTextView"));
			Runtime.class_replaceMethod(t, ObjC.sel("insertText:replacementRange:"), Callback.addr(insertText), Mem.cstr("v@:@{_NSRange=QQ}"));
			Runtime.class_replaceMethod(t, ObjC.sel("insertText:"), Callback.addr(insertText), Mem.cstr("v@:@"));
			Runtime.class_replaceMethod(t, ObjC.sel("doCommandBySelector:"), Callback.addr(doCommand), Mem.cstr("v@::"));
			textViewClass = t;
			return;
		}
		#end
		// (regular: a Dock icon, key windows; HELDER_BACKGROUND=1 accessory: none, never active)
		Msg.iInt(app, ObjC.sel("setActivationPolicy:"), background ? 1 : 0);
		Msg.v(app, ObjC.sel("finishLaunching"));
		mode = ObjC.str("kCFRunLoopDefaultMode");
		OsThread.waitMain = pump;
		OsThread.wakeMain = wakeMain;
		var cls = Runtime.objc_allocateClassPair(ObjC.cls("NSObject"), Mem.cstr("HxmcWindowDelegate"), 0);
		Runtime.class_addMethod(cls, ObjC.sel("windowShouldClose:"), Callback.addr(shouldClose), Mem.cstr("c@:@"));
		Runtime.class_addMethod(cls, ObjC.sel("windowDidResize:"), Callback.addr(didResize), Mem.cstr("v@:@"));
		Runtime.class_addMethod(cls, ObjC.sel("windowDidBecomeKey:"), Callback.addr(didChangeKey), Mem.cstr("v@:@"));
		Runtime.class_addMethod(cls, ObjC.sel("windowDidResignKey:"), Callback.addr(didChangeKey), Mem.cstr("v@:@"));
		Runtime.class_addMethod(cls, ObjC.sel("windowDidChangeBackingProperties:"), Callback.addr(didChangeScale), Mem.cstr("v@:@"));
		Runtime.class_addMethod(cls, ObjC.sel("windowWillStartLiveResize:"), Callback.addr(startResize), Mem.cstr("v@:@"));
		Runtime.class_addMethod(cls, ObjC.sel("windowDidEndLiveResize:"), Callback.addr(endResize), Mem.cstr("v@:@"));
		Runtime.class_addMethod(cls, ObjC.sel("liveFrame:"), Callback.addr(liveFrame), Mem.cstr("v@:@"));
		// (the application's delegate too)
		Runtime.class_addMethod(cls, ObjC.sel("applicationShouldTerminate:"), Callback.addr(shouldTerminate), Mem.cstr("Q@:@"));
		// (the windows' dragging destination: NSWindow passes it its drags' messages)
		Runtime.class_addMethod(cls, ObjC.sel("draggingEntered:"), Callback.addr(dragEntered), Mem.cstr("Q@:@"));
		Runtime.class_addMethod(cls, ObjC.sel("draggingUpdated:"), Callback.addr(dragEntered), Mem.cstr("Q@:@"));
		Runtime.class_addMethod(cls, ObjC.sel("prepareForDragOperation:"), Callback.addr(prepareDrag), Mem.cstr("c@:@"));
		Runtime.class_addMethod(cls, ObjC.sel("performDragOperation:"), Callback.addr(performDrag), Mem.cstr("c@:@"));
		Runtime.class_addMethod(cls, ObjC.sel("application:openURLs:"), Callback.addr(openURLs), Mem.cstr("v@:@@"));
		Runtime.class_addMethod(cls, ObjC.sel("getURL:withReply:"), Callback.addr(getURL), Mem.cstr("v@:@@"));
		Runtime.objc_registerClassPair(cls);
		delegate = Msg.id(Msg.id(cls, ObjC.sel("alloc")), ObjC.sel("init"));
		Msg.vPtr(app, ObjC.sel("setDelegate:"), delegate);
		// (a URL of the app's schemes, kAEGetURL: NSApplication hands it to
		// application:openURLs: only from its own run loop, which this is not)
		Msg.vPtrPtrIntInt(Msg.id(ObjC.cls("NSAppleEventManager"), ObjC.sel("sharedAppleEventManager")), ObjC.sel("setEventHandler:andSelector:forEventClass:andEventID:"),
			delegate, ObjC.sel("getURL:withReply:"), 0x4755524C, 0x4755524C);
		#if hxmc.dev_host
		if (helder.dev.Hosted.hosted()) helder.dev.Hosted.set(helder.dev.Hosted.MAC_DELEGATE, delegate);
		#end
		menus();
		// (an NSRange by value after the text: not read)
		var t = Runtime.objc_allocateClassPair(ObjC.cls("NSTextView"), Mem.cstr("HxmcTextView"), 0);
		Runtime.class_addMethod(t, ObjC.sel("insertText:replacementRange:"), Callback.addr(insertText), Mem.cstr("v@:@{_NSRange=QQ}"));
		Runtime.class_addMethod(t, ObjC.sel("insertText:"), Callback.addr(insertText), Mem.cstr("v@:@"));
		Runtime.class_addMethod(t, ObjC.sel("doCommandBySelector:"), Callback.addr(doCommand), Mem.cstr("v@::"));
		Runtime.objc_registerClassPair(t);
		textViewClass = t;
	}

	// the menu bar: the application's menu and the Window menu
	static function menus() {
		var name = ObjC.string(Msg.id(Msg.id(ObjC.cls("NSProcessInfo"), ObjC.sel("processInfo")), ObjC.sel("processName")));
		function menu(title:String):Ptr {
			var t = ObjC.str(title);
			var m = Msg.idPtr(Msg.id(ObjC.cls("NSMenu"), ObjC.sel("alloc")), ObjC.sel("initWithTitle:"), t);
			ObjC.release(t);
			return m;
		}
		// (modifiers: NSEventModifierFlagOption, Command)
		function item(m:Ptr, title:String, action:Ptr, key:String, ?mods:Int) {
			var t = ObjC.str(title), k = ObjC.str(key);
			var it = Msg.idPtrPtrPtr(Msg.id(ObjC.cls("NSMenuItem"), ObjC.sel("alloc")), ObjC.sel("initWithTitle:action:keyEquivalent:"), t, action, k);
			if (mods != null) Msg.vInt(it, ObjC.sel("setKeyEquivalentModifierMask:"), mods);
			Msg.vPtr(m, ObjC.sel("addItem:"), it);
			ObjC.release(it);
			ObjC.release(t);
			ObjC.release(k);
		}
		function separator(m:Ptr)
			Msg.vPtr(m, ObjC.sel("addItem:"), Msg.id(ObjC.cls("NSMenuItem"), ObjC.sel("separatorItem")));
		function submenu(bar:Ptr, m:Ptr) {
			var it = Msg.id(Msg.id(ObjC.cls("NSMenuItem"), ObjC.sel("alloc")), ObjC.sel("init"));
			Msg.vPtr(it, ObjC.sel("setSubmenu:"), m);
			Msg.vPtr(bar, ObjC.sel("addItem:"), it);
			ObjC.release(it);
		}
		var bar = menu("");
		var own = menu(name);
		item(own, "Hide " + name, ObjC.sel("hide:"), "h");
		item(own, "Hide Others", ObjC.sel("hideOtherApplications:"), "h", (1 << 19) | (1 << 20));
		item(own, "Show All", ObjC.sel("unhideAllApplications:"), "");
		separator(own);
		item(own, "Quit " + name, ObjC.sel("terminate:"), "q");
		submenu(bar, own);
		var windows = menu("Window");
		item(windows, "Minimize", ObjC.sel("performMiniaturize:"), "m");
		item(windows, "Zoom", ObjC.sel("performZoom:"), "");
		item(windows, "Close", ObjC.sel("performClose:"), "w");
		separator(windows);
		submenu(bar, windows);
		Msg.vPtr(app, ObjC.sel("setMainMenu:"), bar);
		Msg.vPtr(app, ObjC.sel("setWindowsMenu:"), windows);
		ObjC.release(own);
		ObjC.release(windows);
		ObjC.release(bar);
	}

	// the size in pixels and the backing scale, from the content view; the
	// layer's drawables follow
	function measure():Bool {
		scale = Msg.f(window, ObjC.sel("backingScaleFactor"));
		var b = Msg.rect(view, ObjC.sel("bounds"));
		var w = Math.round(b.size.width * scale), h = Math.round(b.size.height * scale);
		Msg.vFloat(layer, ObjC.sel("setContentsScale:"), scale);
		size.value.width = w;
		size.value.height = h;
		#if !helder.soft
		Msg.vSize(layer, ObjC.sel("setDrawableSize:"), size.value);
		#end
		if (w == surface.width && h == surface.height) return false;
		surface.resized(w, h);
		return true;
	}

	function dragFiles(paths:Array<String>, image:Null<helder.image.Image>, x:Float, y:Float, allowed:Array<DragOperation>,
		done:DragOperation->Void):Bool
		return OsThread.get(() -> {
			if (dragEvent.isNull() || !CocoaFileDrag.begin(this, dragEvent, paths, image, x, y, allowed, done)) return false;
			rememberDragEvent(Ptr.nil());
			return true;
		});

	function rememberDragEvent(ev:Ptr) {
		if (!ev.isNull()) Runtime.objc_retain(ev);
		ObjC.release(dragEvent);
		dragEvent = ev;
	}

	function destroy() {
		helder.os.OsThread.run(() -> {
			open.remove(this);
			rememberDragEvent(Ptr.nil());
			#if hxmc.dev_host
			// (handing over: the window, its views and layer left to the next build)
			if (helder.dev.Hosted.handingOver && helder.dev.Hosted.get(helder.dev.Hosted.UI_WINDOW) == window) {
				LibC.free(rect);
				LibC.free(size);
				return;
			}
			#end
			#if helder.soft
			Blit.forget(surface);
			#end
			Msg.vPtr(window, ObjC.sel("setDelegate:"), Ptr.nil());
			Msg.v(window, ObjC.sel("close"));
			Runtime.objc_release(window);
			Runtime.objc_release(layer);
			Runtime.objc_release(view);
			Runtime.objc_release(textView);
			LibC.free(rect);
			LibC.free(size);
		});
	}

	function setTitle(t:String) {
		helder.os.OsThread.run(() -> {
			var s = ObjC.str(t);
			Msg.vPtr(window, ObjC.sel("setTitle:"), s);
			ObjC.release(s);
			keepControls();
		});
	}

	function resize(w:Int, h:Int) {
		helder.os.OsThread.run(() -> {
			size.value.width = w;
			size.value.height = h;
			Msg.vSize(window, ObjC.sel("setContentSize:"), size.value);
			if (measure()) resized();
		});
	}

	// (NSWindowStyleMaskFullScreen; toggleFullScreen: animates into its space: the getter follows when it is there)
	function isFullscreen():Bool
		return OsThread.get(() -> Msg.i(window, ObjC.sel("styleMask")).toInt() & (1 << 14) != 0);

	function setFullscreen(on:Bool)
		if (isFullscreen() != on) OsThread.run(() -> Msg.vPtr(window, ObjC.sel("toggleFullScreen:"), Ptr.nil()));

	// (the main screen's height: AppKit's y goes up from its bottom)
	static function screenHeight():Float {
		var screens = Msg.id(ObjC.cls("NSScreen"), ObjC.sel("screens"));
		return Msg.i(screens, ObjC.sel("count")) == 0 ? 0 : Msg.rect(Msg.idInt(screens, ObjC.sel("objectAtIndex:"), 0), ObjC.sel("frame")).size.height;
	}

	function position():{x:Int, y:Int}
		return OsThread.get(positionNow);

	function positionNow():{x:Int, y:Int} {
		var f = Msg.rect(window, ObjC.sel("frame"));
		var c = Msg.rectRect(window, ObjC.sel("contentRectForFrameRect:"), f);
		return {x: Math.round(c.origin.x), y: Math.round(screenHeight() - (c.origin.y + c.size.height))};
	}

	function moveTo(x:Int, y:Int) {
		helder.os.OsThread.run(() -> {
			var f = Msg.rect(window, ObjC.sel("frame"));
			var c = Msg.rectRect(window, ObjC.sel("contentRectForFrameRect:"), f);
			rect.value.origin.x = x - (c.origin.x - f.origin.x);
			rect.value.origin.y = screenHeight() - y - c.size.height - (c.origin.y - f.origin.y);
			Msg.vPoint(window, ObjC.sel("setFrameOrigin:"), rect.value.origin);
		});
	}

	// where it takes the pointer (Window.input: x, y, width, height in
	// pixels; null: everywhere): ignoresMouseEvents set by where the pointer
	// is at each poll (ignored, no event of its comes to say it moved)
	var input:Null<Array<Int>> = null;

	function setInput(rects:Null<Array<Int>>)
		OsThread.run(() -> {
			input = rects;
			if (rects == null) Msg.vBool(window, ObjC.sel("setIgnoresMouseEvents:"), false) else track();
		});

	function track() {
		var r = input;
		if (r == null) return;
		var p = Msg.pointPointPtr(view, ObjC.sel("convertPoint:fromView:"), Msg.point(window, ObjC.sel("mouseLocationOutsideOfEventStream")), Ptr.nil());
		var b = Msg.rect(view, ObjC.sel("bounds"));
		var x = p.x * scale, y = (b.size.height - p.y) * scale, on = false, i = 0;
		while (!on && i + 3 < r.length) {
			on = x >= r[i] && y >= r[i + 1] && x < r[i] + r[i + 2] && y < r[i + 1] + r[i + 3];
			i += 4;
		}
		if (on == Msg.b(window, ObjC.sel("ignoresMouseEvents"))) Msg.vBool(window, ObjC.sel("setIgnoresMouseEvents:"), !on);
	}

	// (the system's shadow: a transparent window's follows its pixels, made again as they change shape: invalidate)
	function shadow():Bool
		return OsThread.get(() -> Msg.b(window, ObjC.sel("hasShadow")));

	function setShadow(on:Bool)
		OsThread.run(() -> Msg.vBool(window, ObjC.sel("setHasShadow:"), on));

	function raise() {
		helder.os.OsThread.run(() -> {
			// (in the background: on screen, so that its frames present, but never key nor the app active)
			if (background) {
				Msg.v(window, ObjC.sel("orderFrontRegardless"));
				return;
			}
			Msg.vPtr(window, ObjC.sel("makeKeyAndOrderFront:"), Ptr.nil());
			Msg.vBool(app, ObjC.sel("activateIgnoringOtherApps:"), true);
		});
	}

	// whether the windows stay in the background (HELDER_BACKGROUND=1: tests run while the machine is in use)
	public static final background = Sys.getEnv("HELDER_BACKGROUND") == "1";

	// the system asks the app to open files or URLs (NSApplicationDelegate):
	// the files' paths and the other URLs (the app's schemes) to App.onOpen
	@:hxmc.callback static function openURLs(self:Ptr, cmd:Ptr, application:Ptr, urls:Ptr):Void {
		var paths = [];
		for (i in 0...Msg.i(urls, ObjC.sel("count")).toInt()) {
			var url = Msg.idInt(urls, ObjC.sel("objectAtIndex:"), i);
			var p = ObjC.string(Msg.id(url, Msg.b(url, ObjC.sel("isFileURL")) ? ObjC.sel("path") : ObjC.sel("absoluteString")));
			if (p != null) paths.push(p);
		}
		OsThread.back(() -> @:privateAccess App.open(paths));
	}

	// a URL the system asks the app to open (its direct object, keyDirectObject '----')
	@:hxmc.callback static function getURL(self:Ptr, cmd:Ptr, event:Ptr, reply:Ptr):Void {
		var url = ObjC.string(Msg.id(Msg.idInt(event, ObjC.sel("paramDescriptorForKeyword:"), 0x2D2D2D2D), ObjC.sel("stringValue")));
		if (url != null) OsThread.back(() -> @:privateAccess App.open([url]));
	}

	// a drag over a window: a copy when it carries file URLs (NSDragOperationCopy), else none
	@:hxmc.callback static function dragEntered(self:Ptr, cmd:Ptr, info:Ptr):Int64
		return draggedFiles(info).length > 0 ? 1 : 0;

	@:hxmc.callback static function prepareDrag(self:Ptr, cmd:Ptr, info:Ptr):Int
		return 1;

	// the drop: its files' paths (Event.files), where the pointer is in the window
	@:hxmc.callback static function performDrag(self:Ptr, cmd:Ptr, info:Ptr):Int {
		var w = find(Msg.id(info, ObjC.sel("draggingDestinationWindow")));
		var files = draggedFiles(info);
		if (w == null || files.length == 0) return 0;
		var p = Msg.pointPointPtr(w.view, ObjC.sel("convertPoint:fromView:"), Msg.point(w.window, ObjC.sel("mouseLocationOutsideOfEventStream")), Ptr.nil());
		var b = Msg.rect(w.view, ObjC.sel("bounds"));
		var e = event;
		e.kind = Drop;
		e.window = w.owner;
		e.files = files;
		e.x = Math.floor(p.x * w.scale);
		e.y = Math.floor((b.size.height - p.y) * w.scale);
		dispatch(e);
		return 1;
	}

	// (the dragging pasteboard's NSURLs that are files: their paths)
	static function draggedFiles(info:Ptr):Array<String> {
		var files = [];
		var pool = Runtime.objc_autoreleasePoolPush();
		var pb = Msg.id(info, ObjC.sel("draggingPasteboard"));
		var urls = pb.isNull() ? Ptr.nil() : Msg.idPtrPtr(pb, ObjC.sel("readObjectsForClasses:options:"), Msg.idPtr(ObjC.cls("NSArray"), ObjC.sel("arrayWithObject:"), ObjC.cls("NSURL")), Ptr.nil());
		if (!urls.isNull())
			for (i in 0...Msg.i(urls, ObjC.sel("count")).toInt()) {
				var url = Msg.idInt(urls, ObjC.sel("objectAtIndex:"), i);
				if (!Msg.b(url, ObjC.sel("isFileURL"))) continue;
				var path = ObjC.string(Msg.id(url, ObjC.sel("path")));
				if (path != null) files.push(path);
			}
		Runtime.objc_autoreleasePoolPop(pool);
		return files;
	}

	function setMinSize(w:Int, h:Int) {
		helder.os.OsThread.run(() -> {
			size.value.width = w;
			size.value.height = h;
			Msg.vSize(window, ObjC.sel("setContentMinSize:"), size.value);
			if (measure()) resized();
		});
	}

	// a resize told: as a Resize event, or at the next poll when there is
	// no loop yet (a size set before App.run: setContentSize: tells the
	// delegate at once)
	var pending = false;

	function resized(live = false) {
		if (onEvent == null) {
			pending = true;
			return;
		}
		pending = false;
		layoutControls();
		var e = live ? new Event() : event;
		e.kind = Resize;
		e.window = owner;
		e.x = surface.width;
		e.y = surface.height;
		if (!live) {
			dispatch(e);
			return;
		}
		// (a live resize's: handed to the program with its frame, in the call
		// the main thread waits for at most LIVE_WAIT, not waited out first)
		Window.routed(e);
		owing.acquire();
		owed = [for (o in owed) if (o.window != owner) o];
		owed.push(e);
		owing.release();
	}

	// (the live resize's Resize events not delivered yet, the newest of each window)
	static var owed:Array<Event> = [];
	static final owing = new sys.thread.Mutex();

	// (on the program's thread)
	static function deliver(f:Event->Void) {
		owing.acquire();
		var es = owed;
		owed = [];
		owing.release();
		for (e in es)
			f(e);
	}

	function setCursor(c:Cursor) {
		helder.os.OsThread.run(() -> {
			cursor = c;
			applyCursor();
		});
	}

	// the cursor at a move: the app's over the content (and while a button is
	// held), the arrow once as the pointer leaves it (AppKit's then: the
	// edges' resize cursors, the other windows')
	function hover(inside:Bool) {
		if (inside && (cursor != Default || !over)) applyCursor() else if (!inside && over)
			Msg.v(Msg.id(ObjC.cls("NSCursor"), ObjC.sel("arrowCursor")), ObjC.sel("set"));
		over = inside;
	}

	// (AppKit puts the arrow back as the pointer enters the window: set again on each move)
	function applyCursor() {
		var cls = ObjC.cls("NSCursor");
		var ns = switch cursor {
			case Pointer: Msg.id(cls, ObjC.sel("pointingHandCursor"));
			case Text: Msg.id(cls, ObjC.sel("IBeamCursor"));
			case Crosshair: Msg.id(cls, ObjC.sel("crosshairCursor"));
			case Move: Msg.id(cls, ObjC.sel("openHandCursor"));
			case NotAllowed: Msg.id(cls, ObjC.sel("operationNotAllowedCursor"));
			case ResizeEW: Msg.id(cls, ObjC.sel("resizeLeftRightCursor"));
			case ResizeNS: Msg.id(cls, ObjC.sel("resizeUpDownCursor"));
			case Grab: Msg.id(cls, ObjC.sel("openHandCursor"));
			case Grabbing: Msg.id(cls, ObjC.sel("closedHandCursor"));
			case _: Msg.id(cls, ObjC.sel("arrowCursor"));
		}
		Msg.v(ns, ObjC.sel("set"));
	}

	// text input on: the text view at that area (pixels from the top left)
	// and the first responder; off: neither, its composition dropped
	function textInput(on:Bool, x:Int, y:Int, width:Int, height:Int) {
		helder.os.OsThread.run(() -> {
			if (!on) {
				if (!typing) return;
				typing = false;
				if (marked != "") Msg.v(Msg.id(textView, ObjC.sel("inputContext")), ObjC.sel("discardMarkedText"));
				marked = "";
				clearText(textView);
				Msg.bPtr(window, ObjC.sel("makeFirstResponder:"), Ptr.nil());
				Msg.vBool(textView, ObjC.sel("setHidden:"), true);
				return;
			}
			var b = Msg.rect(view, ObjC.sel("bounds"));
			rect.value.origin.x = x / scale;
			rect.value.origin.y = b.size.height - (y + height) / scale;
			rect.value.size.width = Math.max(1, width / scale);
			rect.value.size.height = Math.max(1, height / scale);
			Msg.vRect(textView, ObjC.sel("setFrame:"), rect.value);
			if (!typing) {
				typing = true;
				Msg.vBool(textView, ObjC.sel("setHidden:"), false);
				Msg.bPtr(window, ObjC.sel("makeFirstResponder:"), textView);
			}
			Msg.v(Msg.id(textView, ObjC.sel("inputContext")), ObjC.sel("invalidateCharacterCoordinates"));
		});
	}

	static function clearText(tv:Ptr) {
		var e = ObjC.str("");
		Msg.vPtr(tv, ObjC.sel("setString:"), e);
		ObjC.release(e);
	}

	// the text view's marked text, told when it changed (TextEditing: the caret at its end)
	function composition() {
		if (!typing) return;
		var now = Msg.b(textView, ObjC.sel("hasMarkedText")) ? ObjC.string(Msg.id(textView, ObjC.sel("string"))) ?? "" : "";
		if (now == marked) return;
		marked = now;
		var e = event;
		e.kind = TextEditing;
		e.window = owner;
		e.text = now;
		e.x = now.length;
		dispatch(e);
	}

	// the text view is given text (an NSString or NSAttributedString): typed,
	// not kept; the composition it commits ends
	@:hxmc.callback static function insertText(self:Ptr, cmd:Ptr, text:Ptr):Void {
		var w:Null<CocoaWindow> = null;
		for (o in open)
			if (o.textView == self) w = o;
		if (w == null || text.isNull()) return;
		var s = Msg.bPtr(text, ObjC.sel("isKindOfClass:"), ObjC.cls("NSAttributedString")) ? Msg.id(text, ObjC.sel("string")) : text;
		var str = ObjC.string(s) ?? "";
		clearText(self);
		var e = event;
		e.window = w.owner;
		if (w.marked != "") {
			w.marked = "";
			e.kind = TextEditing;
			e.text = "";
			e.x = 0;
			dispatch(e);
		}
		var typed = new StringBuf();
		for (cp in new haxe.iterators.StringIteratorUnicode(str))
			if (cp >= 0x20 && cp != 0x7F && (cp < 0xF700 || cp > 0xF8FF)) typed.addChar(cp);
		if (typed.length == 0) return;
		e.kind = TextInput;
		e.text = typed.toString();
		e.mods = 0;
		dispatch(e);
	}

	// (its commands are the keys': KeyDown events)
	@:hxmc.callback static function doCommand(self:Ptr, cmd:Ptr, command:Ptr):Void {}

	// the general pasteboard's string (NSPasteboardTypeString: public.utf8-plain-text)
	static function writeClipboard(text:String) {
		helder.os.OsThread.run(() -> {
			var pb = Msg.id(ObjC.cls("NSPasteboard"), ObjC.sel("generalPasteboard"));
			Msg.i(pb, ObjC.sel("clearContents"));
			var s = ObjC.str(text), type = ObjC.str("public.utf8-plain-text");
			Msg.idPtrPtr(pb, ObjC.sel("setString:forType:"), s, type);
			ObjC.release(s);
			ObjC.release(type);
		});
	}

	static function readClipboard():Null<String> {
		return helder.os.OsThread.get(() -> {
			var pool = Runtime.objc_autoreleasePoolPush();
			var pb = Msg.id(ObjC.cls("NSPasteboard"), ObjC.sel("generalPasteboard"));
			var type = ObjC.str("public.utf8-plain-text");
			var text = ObjC.string(Msg.idPtr(pb, ObjC.sel("stringForType:"), type));
			ObjC.release(type);
			Runtime.objc_autoreleasePoolPop(pool);
			return text;
		});
	}

	// (ev's window; a pointer's event with none (one posted to the process,
	// not through the window server's hit test): the window under its place
	// on the screen, as AppKit would send it)
	static function owning(ev:Ptr):Null<CocoaWindow> {
		var w = find(Msg.id(ev, ObjC.sel("window")));
		if (w != null) return w;
		var type = Msg.i(ev, ObjC.sel("type")).toInt();
		if (type != NS.ScrollWheel && type != NS.MouseMoved && type != NS.LeftMouseDown && type != NS.LeftMouseUp && type != NS.LeftMouseDragged) return null;
		// (the frontmost window there that takes the mouse: one over another, a transparent one passing it through)
		var p = Msg.point(ev, ObjC.sel("locationInWindow")), ordered = Msg.id(app, ObjC.sel("orderedWindows"));
		for (i in 0...Msg.i(ordered, ObjC.sel("count")).toInt()) {
			var o = find(Msg.idInt(ordered, ObjC.sel("objectAtIndex:"), i));
			if (o == null || Msg.b(o.window, ObjC.sel("ignoresMouseEvents"))) continue;
			var r = Msg.rect(o.window, ObjC.sel("frame"));
			if (p.x >= r.origin.x && p.y >= r.origin.y && p.x < r.origin.x + r.size.width && p.y < r.origin.y + r.size.height) return o;
		}
		return null;
	}

	// (ev's place in the window's coordinates: from the screen's where it has no window)
	function location(ev:Ptr):CGPoint {
		var p = Msg.point(ev, ObjC.sel("locationInWindow"));
		return Msg.id(ev, ObjC.sel("window")).isNull() ? Msg.pointPoint(window, ObjC.sel("convertPointFromScreen:"), p) : p;
	}

	static function find(window:Ptr):Null<CocoaWindow> {
		for (w in open)
			if (w.window == window) return w;
		return null;
	}

	// (on the program's thread: OsThread; routed by the window's compositor
	// first, unless it was as it was read: pumped)
	static function dispatch(e:Event) {
		if (preRouted >= 0) {
			e.routed = preRouted;
			e.gesture = preGesture;
			preRouted = -1;
		} else
			Window.routed(e);
		var f = onEvent;
		if (f != null) OsThread.back(() -> f(e));
	}

	@:hxmc.callback static function shouldClose(self:Ptr, cmd:Ptr, sender:Ptr):Int {
		var w = find(sender);
		if (w != null) {
			var e = event;
			e.kind = Close;
			e.window = w.owner;
			dispatch(e);
		}
		// (NO: the window stays open until close())
		return 0;
	}

	// Quit: each window asked to close; NSTerminateCancel (the loop is ours)
	@:hxmc.callback static function shouldTerminate(self:Ptr, cmd:Ptr, sender:Ptr):Int64 {
		for (w in open.copy()) {
			var e = event;
			e.kind = Close;
			e.window = w.owner;
			dispatch(e);
		}
		return 0;
	}

	// another display: a new scale (ScaleChange), and a Resize when the pixels changed
	@:hxmc.callback static function didChangeScale(self:Ptr, cmd:Ptr, note:Ptr):Void {
		var w = find(Msg.id(note, ObjC.sel("object")));
		if (w == null) return;
		var scale = w.scale, resized = w.measure();
		if (w.scale != scale) {
			var e = event;
			e.kind = ScaleChange;
			e.window = w.owner;
			dispatch(e);
		}
		if (resized) w.resized();
	}

	@:hxmc.callback static function didResize(self:Ptr, cmd:Ptr, note:Ptr):Void {
		var t = haxe.Timer.stamp();
		resizedLive(note);
		held += haxe.Timer.stamp() - t;
	}

	// (the main thread's time in a live resize's callbacks, and its frames given up on: the resize check's)
	static var held = 0.0;
	static var late = 0;

	static function resizedLive(note:Ptr) {
		var w = find(Msg.id(note, ObjC.sel("object")));
		if (w != null) w.keepControls();
		if (w == null || !w.measure()) return;
		var live = w.surface.resizing || Msg.b(w.window, ObjC.sel("inLiveResize"));
		w.resized(live);
		// (a drag of the window's edge runs AppKit's own loop until the mouse is up, and
		// App.run draws nothing: a frame at the new size from here, as Win32Window's timer)
		if (live && !frameLive()) late++;
	}

	// (a live resize's frame waited for so long at most: presented in the
	// transaction that gives the window its new size, else the last frame
	// shows, at the window's top left, until it comes)
	static inline var LIVE_WAIT = 0.1;

	// while an edge is dragged, frames from a timer too: AppKit's loop runs
	// it (the common modes: its tracking mode's too), and the content moves
	// while the mouse holds still (as Win32Window's WM_TIMER)
	static var timer = Ptr.nil();

	@:hxmc.callback static function startResize(self:Ptr, cmd:Ptr, note:Ptr):Void {
		var w = find(Msg.id(note, ObjC.sel("object")));
		if (w != null) w.surface.resizing = true;
		if (!timer.isNull()) return;
		var t = Msg.idFloatPtrPtrPtrBool(ObjC.cls("NSTimer"), ObjC.sel("timerWithTimeInterval:target:selector:userInfo:repeats:"), 1 / 120, delegate,
			ObjC.sel("liveFrame:"), Ptr.nil(), true);
		timer = Runtime.objc_retain(t);
		var modes = ObjC.str("kCFRunLoopCommonModes");
		Msg.vPtrPtr(Msg.id(ObjC.cls("NSRunLoop"), ObjC.sel("currentRunLoop")), ObjC.sel("addTimer:forMode:"), timer, modes);
		ObjC.release(modes);
	}

	@:hxmc.callback static function endResize(self:Ptr, cmd:Ptr, note:Ptr):Void {
		var w = find(Msg.id(note, ObjC.sel("object")));
		if (w != null) w.surface.resizing = false;
		if (timer.isNull()) return;
		Msg.v(timer, ObjC.sel("invalidate"));
		Runtime.objc_release(timer);
		timer = Ptr.nil();
	}

	@:hxmc.callback static function liveFrame(self:Ptr, cmd:Ptr, t:Ptr):Void {
		var s = haxe.Timer.stamp();
		frameLive();
		held += haxe.Timer.stamp() - s;
	}

	static function frameLive():Bool
		return onFrame == null || App.windows.length == 0 || OsThread.within(step, LIVE_WAIT);

	// (a call given up on runs later: it delivers what is owed by then)
	static function step() {
		var f = onEvent;
		if (f != null) deliver(f);
		onFrame();
	}

	// waits for an event (left in the queue for poll), or seconds
	static function wait(seconds:Float) {
		helder.os.OsThread.run(() -> {
			if (app.isNull() || pumped.length > 0) return;
			var pool = Runtime.objc_autoreleasePoolPush();
			var until = Msg.idFloat(ObjC.cls("NSDate"), ObjC.sel("dateWithTimeIntervalSinceNow:"), seconds);
			Msg.idIntPtrPtrBool(app, ObjC.sel("nextEventMatchingMask:untilDate:inMode:dequeue:"), -1, until, mode, false);
			Runtime.objc_autoreleasePoolPop(pool);
		});
	}

	// dispatches the pending events
	static function poll(onFrame:Void->Void, onEvent:Event->Void) {
		deliver(onEvent);
		helder.os.OsThread.run(() -> {
			CocoaWindow.onFrame = onFrame;
			CocoaWindow.onEvent = onEvent;
			for (w in open.copy()) {
				if (w.pending) w.resized();
				w.track();
			}
			var past = Msg.id(ObjC.cls("NSDate"), ObjC.sel("distantPast"));
			var k = 0;
			while (!app.isNull()) {
				// (what the main thread read while the program ran on first, as routed then)
				var ev = Ptr.nil();
				if (k < pumped.length) {
					ev = pumped[k];
					preRouted = pumpedRoutes[2 * k];
					preGesture = pumpedRoutes[2 * k + 1];
					k++;
				} else {
					if (k > 0) {
						for (p in pumped)
							Runtime.objc_release(p);
						pumped.resize(0);
						pumpedRoutes.resize(0);
						k = 0;
					}
					preRouted = -1;
					ev = Msg.idIntPtrPtrBool(app, ObjC.sel("nextEventMatchingMask:untilDate:inMode:dequeue:"), -1, past, mode, true);
				}
				if (ev.isNull()) break;
				// (a wake of the main thread's read: nothing)
				if (Msg.i(ev, ObjC.sel("type")).toInt() == NS.ApplicationDefined) continue;
				var w = owning(ev);
				var type = Msg.i(ev, ObjC.sel("type")).toInt();
				// (a press on the title bar or an edge is AppKit's, a move or a resize:
				// its loop takes the release too, which the app would never see)
				if (w != null && (type == NS.LeftMouseDown || type == NS.RightMouseDown || type == NS.OtherMouseDown) && !w.inside(ev)) {
					Msg.vPtr(app, ObjC.sel("sendEvent:"), ev);
					continue;
				}
				var key = type == NS.KeyDown || type == NS.KeyUp;
				// (the menus' shortcuts first: Command and a key one of them has)
				if (type == NS.KeyDown && Msg.i(ev, ObjC.sel("modifierFlags")).toInt() & (1 << 20) != 0
					&& Msg.bPtr(Msg.id(app, ObjC.sel("mainMenu")), ObjC.sel("performKeyEquivalent:"), ev)) continue;
				if (w != null) w.translate(ev, type);
				if (w != null) w.composition();
				// (keys stay ours: unhandled, AppKit would beep at each)
				if (!key || w == null) Msg.vPtr(app, ObjC.sel("sendEvent:"), ev);
			}
			// (a composition changed outside a key: the input method's own window, a message)
			for (w in open.copy())
				w.composition();
		});
	}

	// --- the input read while the program runs on (OsThread.waitMain: Layers' compositor)

	// (the events the main thread read and kept for the program's next poll, retained; their routes and gestures)
	static final pumped:Array<Ptr> = [];
	static final pumpedRoutes:Array<Int> = [];
	static var preRouted = -1;
	static var preGesture = 0;
	// (a run loop mode of its own: only the window server's events come in it, not
	// the accessibility's requests, timers or delegates, which would touch the program's state)
	static var pumpMode = Ptr.nil();
	static final peeked = new Event();
	static final INPUT = (1 << NS.LeftMouseDown) | (1 << NS.LeftMouseUp) | (1 << NS.RightMouseDown) | (1 << NS.RightMouseUp) | (1 << NS.MouseMoved)
		| (1 << NS.LeftMouseDragged) | (1 << NS.RightMouseDragged) | (1 << NS.KeyDown) | (1 << NS.KeyUp) | (1 << 12) | (1 << NS.ApplicationDefined)
		| (1 << NS.ScrollWheel) | (1 << NS.OtherMouseDown) | (1 << NS.OtherMouseUp) | (1 << NS.OtherMouseDragged) | (1 << NS.Magnify);

	// (whether a window's compositor takes the input as it is read)
	static function routing():Bool {
		for (w in open)
			if (w.owner.route != null) return true;
		return false;
	}

	// the main thread's wait while the program runs on: the next input
	// event read, routed to its window's compositor at once, kept for the
	// program's poll; false where no window has a compositor
	static function pump():Bool {
		if (app.isNull() || !routing()) return false;
		var pool = Runtime.objc_autoreleasePoolPush();
		if (pumpMode.isNull()) pumpMode = ObjC.str("kCFRunLoopDefaultMode");
		var until = Msg.idFloat(ObjC.cls("NSDate"), ObjC.sel("dateWithTimeIntervalSinceNow:"), 1.0);
		var ev = Msg.idIntPtrPtrBool(app, ObjC.sel("nextEventMatchingMask:untilDate:inMode:dequeue:"), INPUT, until, pumpMode, true);
		if (!ev.isNull()) {
			var type = Msg.i(ev, ObjC.sel("type")).toInt();
			if (type != NS.ApplicationDefined) {
				var w = owning(ev), r = 0, g = 0;
				var e = w == null ? null : w.peek(ev, type);
				if (e != null) {
					Window.routed(e);
					r = e.routed;
					g = e.gesture;
				}
				pumped.push(Runtime.objc_retain(ev));
				pumpedRoutes.push(r);
				pumpedRoutes.push(g);
			}
		}
		Runtime.objc_autoreleasePoolPop(pool);
		return true;
	}

	// (from the program's thread: the main thread's read woken, a call handed to it)
	static var origin:Ptr<CGPoint> = Ptr.nil();

	static function wakeMain() {
		var pool = Runtime.objc_autoreleasePoolPush();
		if (origin.isNull()) {
			origin = LibC.malloc(16);
			origin.value.x = origin.value.y = 0;
		}
		var e = Msg.idIntPointIntFloatIntPtrIntIntInt(ObjC.cls("NSEvent"), ObjC.sel("otherEventWithType:location:modifierFlags:timestamp:windowNumber:context:subtype:data1:data2:"),
			NS.ApplicationDefined, origin.value, 0, 0, 0, Ptr.nil(), 0, 0, 0);
		if (!e.isNull()) Msg.vPtrBool(app, ObjC.sel("postEvent:atStart:"), e, false);
		// (a post alone wakes no run loop waiting in a mode of its own)
		CoreFoundation.CFRunLoopWakeUp(CoreFoundation.CFRunLoopGetMain());
		Runtime.objc_autoreleasePoolPop(pool);
	}

	// (what translate would make of ev for the compositor, nothing else done: its scroll, a press, a move, a key)
	function peek(ev:Ptr, type:Int):Null<Event> {
		var e = peeked;
		e.window = owner;
		e.phase = e.momentum = 0;
		e.mods = mods(ev);
		switch type {
			case NS.KeyDown:
				e.kind = KeyDown;
				e.key = keySym(ev);
				return e;
			case NS.LeftMouseDown | NS.RightMouseDown | NS.OtherMouseDown:
				e.kind = MouseDown;
				e.button = button(ev, type);
			case NS.LeftMouseUp | NS.RightMouseUp | NS.OtherMouseUp:
				e.kind = MouseUp;
				e.button = button(ev, type);
			case NS.MouseMoved | NS.LeftMouseDragged | NS.RightMouseDragged | NS.OtherMouseDragged:
				e.kind = MouseMove;
				e.button = 0;
			case NS.ScrollWheel:
				var dx = Msg.f(ev, ObjC.sel("scrollingDeltaX")), dy = Msg.f(ev, ObjC.sel("scrollingDeltaY"));
				e.phase = scrollPhase(Msg.i(ev, ObjC.sel("phase")).toInt());
				e.momentum = scrollPhase(Msg.i(ev, ObjC.sel("momentumPhase")).toInt());
				e.time = Msg.f(ev, ObjC.sel("timestamp")) * 1000;
				if (dx == 0 && dy == 0 && e.phase == 0 && e.momentum == 0) return null;
				var k = Msg.b(ev, ObjC.sel("hasPreciseScrollingDeltas")) ? scale : 40 * scale;
				e.kind = Scroll;
				e.eased = Msg.i(ev, ObjC.sel("phase")).toInt() == 0 && Msg.i(ev, ObjC.sel("momentumPhase")).toInt() == 0;
				e.deltaX = -dx * k;
				e.deltaY = -dy * k;
			case _:
				return null;
		}
		var p = Msg.pointPointPtr(view, ObjC.sel("convertPoint:fromView:"), location(ev), Ptr.nil());
		var b = Msg.rect(view, ObjC.sel("bounds"));
		e.x = Math.floor(p.x * scale);
		e.y = Math.floor((b.size.height - p.y) * scale);
		return e;
	}

	// whether a press is on the content, not the window's frame
	function inside(ev:Ptr):Bool {
		var content = Msg.id(window, ObjC.sel("contentView"));
		var hit = Msg.idPoint(Msg.id(content, ObjC.sel("superview")), ObjC.sel("hitTest:"), Msg.point(ev, ObjC.sel("locationInWindow")));
		if (!hit.isNull() && Msg.bPtr(hit, ObjC.sel("isDescendantOf:"), content)) return true;
		// (an inset title bar: the content's but the system's buttons, which AppKit tracks)
		return owner.titlebar == Inset && !hit.isNull() && !Msg.bPtr(hit, ObjC.sel("isKindOfClass:"), ObjC.cls("NSButton"));
	}

	// --- an inset title bar (Window.titlebar Inset): the system's buttons over the content

	// where the app placed them (points from the top left; -1: where AppKit does)
	var controlsX = -1.0;
	var controlsY = -1.0;

	inline function systemButton(i:Int):Ptr
		return Msg.idInt(window, ObjC.sel("standardWindowButton:"), i);

	// the three buttons' box in the content's pixels (null: none, full screen)
	function controls():Null<{x:Int, y:Int, width:Int, height:Int}>
		return OsThread.get(controlsNow);

	function controlsNow():Null<{x:Int, y:Int, width:Int, height:Int}> {
		if (isFullscreen()) return null;
		var close = systemButton(0), zoom = systemButton(2);
		if (close.isNull() || zoom.isNull()) return null;
		var a = Msg.rectRectPtr(close, ObjC.sel("convertRect:toView:"), Msg.rect(close, ObjC.sel("bounds")), Ptr.nil());
		var b = Msg.rectRectPtr(zoom, ObjC.sel("convertRect:toView:"), Msg.rect(zoom, ObjC.sel("bounds")), Ptr.nil());
		var h = Msg.rect(view, ObjC.sel("bounds")).size.height;
		var top = h - (a.origin.y + a.size.height);
		return {
			x: Math.round(a.origin.x * scale),
			y: Math.round(top * scale),
			width: Math.round((b.origin.x + b.size.width - a.origin.x) * scale),
			height: Math.round(a.size.height * scale)
		};
	}

	// (as Electron's trafficLightPosition: the title bar's container made as
	// tall as the buttons and twice the top margin, each button's origin set
	// in it; AppKit lays them out again at a resize, so again after each)
	// (asked at each frame: placed again when the place changed, or when
	// AppKit laid its title bar out again and put them back where it keeps them)
	function placeControls(x:Int, y:Int) {
		helder.os.OsThread.run(() -> {
			var px = x / scale, py = y / scale;
			if (px == controlsX && py == controlsY && placed()) return;
			controlsX = px;
			controlsY = py;
			layoutControls();
		});
	}

	// (AppKit lays its title bar out again after a title, a resize, a change
	// of key status, and puts the buttons back where it keeps them: that
	// layout done now and the buttons moved again in the same turn of the
	// main thread, before the window is drawn, so they are never seen there)
	function keepControls() {
		if (owner.titlebar != Inset || controlsX < 0 || isFullscreen()) return;
		var frame = Msg.id(Msg.id(window, ObjC.sel("contentView")), ObjC.sel("superview"));
		if (!frame.isNull()) Msg.v(frame, ObjC.sel("layoutSubtreeIfNeeded"));
		layoutControls();
	}

	@:hxmc.callback static function didChangeKey(self:Ptr, cmd:Ptr, note:Ptr):Void {
		var w = find(Msg.id(note, ObjC.sel("object")));
		if (w != null) w.keepControls();
	}

	// (the close button where layoutControls put it, in the window: AppKit moves
	// the title bar's container when it lays it out again, not the buttons in it)
	function placed():Bool {
		var c = controls();
		if (c == null) return true;
		return Math.abs(c.x / scale - controlsX) < 0.5 && Math.abs(c.y / scale - controlsY) < 0.5;
	}

	function layoutControls() {
		if (controlsX < 0 || isFullscreen()) return;
		var close = systemButton(0), mini = systemButton(1), zoom = systemButton(2);
		if (close.isNull() || mini.isNull() || zoom.isNull()) return;
		var container = Msg.id(Msg.id(close, ObjC.sel("superview")), ObjC.sel("superview"));
		if (container.isNull()) return;
		var f = Msg.rect(close, ObjC.sel("frame")), gap = Msg.rect(mini, ObjC.sel("frame")).origin.x - (f.origin.x + f.size.width);
		var c = Msg.rect(container, ObjC.sel("frame"));
		rect.value.origin.x = c.origin.x;
		rect.value.size.width = c.size.width;
		rect.value.size.height = f.size.height + 2 * controlsY;
		rect.value.origin.y = Msg.rect(window, ObjC.sel("frame")).size.height - rect.value.size.height;
		Msg.vRect(container, ObjC.sel("setFrame:"), rect.value);
		var x = controlsX;
		for (b in [close, mini, zoom]) {
			rect.value.origin.x = x;
			rect.value.origin.y = controlsY;
			Msg.vPoint(b, ObjC.sel("setFrameOrigin:"), rect.value.origin);
			x += f.size.width + gap;
		}
	}

	function minimize()
		OsThread.run(() -> Msg.vPtr(window, ObjC.sel("performMiniaturize:"), Ptr.nil()));

	function zoomed():Bool
		return OsThread.get(() -> Msg.b(window, ObjC.sel("isZoomed")));

	function zoom()
		OsThread.run(() -> Msg.vPtr(window, ObjC.sel("performZoom:"), Ptr.nil()));

	// a press on an inset title bar's drag region (the app's answer): the
	// window dragged by AppKit; a double click what the user set for title
	// bars (AppleActionOnDoubleClick: Minimize, None, else zoom). True: the
	// press was the window's, not the app's
	function dragged(ev:Ptr, x:Int, y:Int):Bool {
		if (owner.titlebar != Inset || owner.titlebarAt == null || owner.titlebarAt(x, y) != Drag) return false;
		if (Msg.i(ev, ObjC.sel("clickCount")).toInt() == 2) {
			var defaults = Msg.id(ObjC.cls("NSUserDefaults"), ObjC.sel("standardUserDefaults"));
			var key = ObjC.str("AppleActionOnDoubleClick");
			var v = Msg.idPtr(defaults, ObjC.sel("stringForKey:"), key);
			ObjC.release(key);
			var action = v.isNull() ? "" : ObjC.string(v);
			if (action == "Minimize") minimize() else if (action != "None") zoom();
			return true;
		}
		Msg.vPtr(window, ObjC.sel("performWindowDragWithEvent:"), ev);
		return true;
	}

	function translate(ev:Ptr, type:Int) {
		var e = event;
		e.kind = None;
		e.window = owner;
		e.phase = e.momentum = 0;
		switch type {
			case NS.KeyDown | NS.KeyUp:
				e.kind = type == NS.KeyDown ? KeyDown : KeyUp;
				e.key = keySym(ev);
				e.mods = mods(ev);
				if (type == NS.KeyDown && typing && e.mods & (Mods.CONTROL | Mods.META) == 0) {
					// (while an input method composes, its keys are its own)
					if (marked == "") dispatch(e);
					var pool = Runtime.objc_autoreleasePoolPush();
					Msg.vPtr(textView, ObjC.sel("interpretKeyEvents:"), Msg.idPtr(ObjC.cls("NSArray"), ObjC.sel("arrayWithObject:"), ev));
					Runtime.objc_autoreleasePoolPop(pool);
					return;
				}
				if (type == NS.KeyDown) {
					dispatch(e);
					// then its characters (not with Command or Control; not the function keys' private-use ones)
					if (e.mods & (Mods.CONTROL | Mods.META) != 0) return;
					var s = Msg.id(ev, ObjC.sel("characters"));
					if (s.isNull()) return;
					var str = ObjC.string(s);
					if (str == null) return;
					for (cp in new haxe.iterators.StringIteratorUnicode(str)) {
						if (cp < 0x20 || cp == 0x7F || (cp >= 0xF700 && cp <= 0xF8FF)) continue;
						e.kind = TextInput;
						e.text = String.fromCharCode(cp);
						dispatch(e);
					}
					return;
				}
			case NS.LeftMouseDown | NS.RightMouseDown | NS.OtherMouseDown:
				e.kind = MouseDown;
				e.mods = mods(ev);
				e.button = button(ev, type);
			case NS.LeftMouseUp | NS.RightMouseUp | NS.OtherMouseUp:
				e.kind = MouseUp;
				e.button = button(ev, type);
			case NS.MouseMoved | NS.LeftMouseDragged | NS.RightMouseDragged | NS.OtherMouseDragged:
				e.kind = MouseMove;
				e.button = 0;
			case NS.Magnify:
				// (a trackpad's pinch: a Scroll with Control, as browsers send
				// it; -180 ln(scale) pixels, as many as a wheel's notches for
				// that zoom at 1.25 a notch)
				var m = Msg.f(ev, ObjC.sel("magnification"));
				if (m == 0 || m <= -1) return;
				e.kind = Scroll;
				e.eased = false;
				e.mods = mods(ev) | Mods.CONTROL;
				e.deltaX = 0;
				e.deltaY = -180 * Math.log(1 + m);
			case NS.ScrollWheel:
				var dx = Msg.f(ev, ObjC.sel("scrollingDeltaX")), dy = Msg.f(ev, ObjC.sel("scrollingDeltaY"));
				// (a trackpad's gesture and its momentum: their phases, its ends without deltas too)
				e.phase = scrollPhase(Msg.i(ev, ObjC.sel("phase")).toInt());
				e.momentum = scrollPhase(Msg.i(ev, ObjC.sel("momentumPhase")).toInt());
				e.time = Msg.f(ev, ObjC.sel("timestamp")) * 1000;
				if (dx == 0 && dy == 0 && e.phase == 0 && e.momentum == 0) return;
				// (a trackpad's points, exact; a wheel's lines, 40 pixels each; the
				// content follows the fingers, so the view scrolls the other way)
				var precise = Msg.b(ev, ObjC.sel("hasPreciseScrollingDeltas"));
				var k = precise ? scale : 40 * scale;
				e.kind = Scroll;
				// (a trackpad's scrolls come in a gesture, then its momentum: each has a
				// phase; a mouse wheel's, precise or not (Logitech's are), have none:
				// eased, as macOS's own views and browsers glide a notch)
				e.eased = Msg.i(ev, ObjC.sel("phase")).toInt() == 0 && Msg.i(ev, ObjC.sel("momentumPhase")).toInt() == 0;
				e.mods = mods(ev);
				e.deltaX = -dx * k;
				e.deltaY = -dy * k;
			case _:
				return;
		}
		if (e.kind != KeyDown && e.kind != KeyUp) {
			var p = Msg.pointPointPtr(view, ObjC.sel("convertPoint:fromView:"), location(ev), Ptr.nil());
			var b = Msg.rect(view, ObjC.sel("bounds"));
			e.x = Math.floor(p.x * scale);
			e.y = Math.floor((b.size.height - p.y) * scale);
			if (e.kind == MouseMove) hover(type != NS.MouseMoved || p.x >= 0 && p.y >= 0 && p.x < b.size.width && p.y < b.size.height);
			switch type {
				case NS.LeftMouseDown | NS.RightMouseDown | NS.OtherMouseDown:
					rememberDragEvent(Ptr.nil());
					if (type == NS.LeftMouseDown && dragged(ev, e.x, e.y)) return;
					rememberDragEvent(ev);
				case NS.LeftMouseDragged | NS.RightMouseDragged | NS.OtherMouseDragged:
					if (!dragEvent.isNull()) rememberDragEvent(ev);
				case NS.LeftMouseUp | NS.RightMouseUp | NS.OtherMouseUp | NS.MouseMoved:
					rememberDragEvent(Ptr.nil());
				case _:
			}
		}
		dispatch(e);
	}

	// NSEventPhase (Began 1, Stationary 2, Changed 4, Ended 8, Cancelled 16,
	// MayBegin 32) as ScrollPhase's: MayBegin a Began (fingers down, still),
	// Stationary a Changed
	static function scrollPhase(p:Int):Int
		return p & (1 | 32) != 0 ? ScrollPhase.Began : p & (2 | 4) != 0 ? ScrollPhase.Changed : p & 8 != 0 ? ScrollPhase.Ended : p & 16 != 0 ? ScrollPhase.Cancelled : 0;

	// whether the system shows scrollbars over the content, while scrolling
	// (NSScroller.preferredScrollerStyle: 1 overlay; System Settings'
	// "Show scroll bars")
	static function overlayScrollbars():Bool
		return OsThread.get(() -> Msg.i(ObjC.cls("NSScroller"), ObjC.sel("preferredScrollerStyle")).toInt() == 1);

	// NSEventModifierFlags: Shift 1 << 17, Control 1 << 18, Option 1 << 19, Command 1 << 20
	static function mods(ev:Ptr):Int {
		var f = Msg.i(ev, ObjC.sel("modifierFlags")).toInt();
		return (f & (1 << 17) != 0 ? Mods.SHIFT : 0) | (f & (1 << 18) != 0 ? Mods.CONTROL : 0) | (f & (1 << 19) != 0 ? Mods.ALT : 0)
			| (f & (1 << 20) != 0 ? Mods.META : 0);
	}

	static function button(ev:Ptr, type:Int):Int
		return switch type {
			case NS.LeftMouseDown | NS.LeftMouseUp: 1;
			case NS.RightMouseDown | NS.RightMouseUp: 3;
			case _: Msg.i(ev, ObjC.sel("buttonNumber")).toInt() == 2 ? 2 : 0;
		}

	// the key as an X11 KeySym (Event.key): the keys without a character by
	// their key code, the others by their character without modifiers
	static function keySym(ev:Ptr):Int {
		switch Msg.i(ev, ObjC.sel("keyCode")).toInt() {
			case 53: return 0xFF1B; // Escape
			case 36 | 76: return 0xFF0D; // Return, Enter
			case 48: return 0xFF09; // Tab
			case 51: return 0xFF08; // BackSpace
			case 117: return 0xFFFF; // Delete
			case 123: return 0xFF51; // Left
			case 124: return 0xFF53; // Right
			case 125: return 0xFF54; // Down
			case 126: return 0xFF52; // Up
			case 115: return 0xFF50; // Home
			case 119: return 0xFF57; // End
			case 116: return 0xFF55; // Page Up
			case 121: return 0xFF56; // Page Down
			case 110: return 0xFF67; // Menu (kVK_ContextualMenu)
			// (F1 to F12: their key codes; their characters are private ones)
			case 122: return 0xFFBE;
			case 120: return 0xFFBF;
			case 99: return 0xFFC0;
			case 118: return 0xFFC1;
			case 96: return 0xFFC2;
			case 97: return 0xFFC3;
			case 98: return 0xFFC4;
			case 100: return 0xFFC5;
			case 101: return 0xFFC6;
			case 109: return 0xFFC7;
			case 103: return 0xFFC8;
			case 111: return 0xFFC9;
			case _:
		}
		var s = Msg.id(ev, ObjC.sel("charactersIgnoringModifiers"));
		if (s.isNull() || Msg.i(s, ObjC.sel("length")) == 0) return 0;
		var c:Int = Msg.u16Int(s, ObjC.sel("characterAtIndex:"), 0);
		// (Shift still applies: the unshifted letter, as X11's first KeySym)
		return c >= "A".code && c <= "Z".code ? c + 32 : c;
	}
}

// AppKit's C functions: one, to load the framework (CocoaWindow.start)
@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation") extern class CoreFoundation {
	static function CFRunLoopGetMain():Ptr;
	static function CFRunLoopWakeUp(l:Ptr):Void;
}

@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/AppKit.framework/AppKit") extern class AppKit {
	static function NSApplicationLoad():Bool;
}

// NSEventType
class NS {
	public static inline var LeftMouseDown = 1;
	public static inline var LeftMouseUp = 2;
	public static inline var RightMouseDown = 3;
	public static inline var RightMouseUp = 4;
	public static inline var MouseMoved = 5;
	public static inline var LeftMouseDragged = 6;
	public static inline var RightMouseDragged = 7;
	public static inline var KeyDown = 10;
	public static inline var KeyUp = 11;
	public static inline var ScrollWheel = 22;
	public static inline var OtherMouseDown = 25;
	public static inline var OtherMouseUp = 26;
	public static inline var OtherMouseDragged = 27;
	public static inline var Magnify = 30;
	public static inline var ApplicationDefined = 15;
}
