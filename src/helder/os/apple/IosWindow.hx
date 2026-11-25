package helder.os.apple;

import helder.os.Event;
import helder.os.apple.objc.*;
import helder.os.apple.IosApp;
import hxmc.unsafe.*;

// helder.os.Window on iOS: a UIWindow on the main screen, full screen (its
// title and size are the system's), whose root view controller's view is
// an HxmcView (a UIView subclass made at run time) backed by a
// CAMetalLayer (+layerClass), which gfx's Metal back end draws to as on
// macOS (Surface kind Cocoa: the layer, the view). One window per app.
// The program runs inside UIKit's loop (IosApp): App.run turns the main
// run loop without waiting (poll: CFRunLoopRunInMode until nothing is
// left), and the frames are a CADisplayLink's on the main run loop (the
// view its target): asked for (requestVsync: the link running), its
// callback keeps the vsync's time (the link's timestamp, in
// haxe.Timer.stamp()'s seconds) and stops the run loop's wait, and the
// next turn draws; paused while the app sleeps (App.wait), is inactive or
// in the background.
// Every finger and pencil is a pointer (Pointers: Pointer* events,
// coalesced touches as samples, the touches' times, cancels), and nothing
// else: no mouse events or scrolls are made of them; positions in pixels
// from the top left. The
// view's size and safe area (the status bar, the notch, the home
// indicator: Window.safeTop, ...) are measured in layoutSubviews and
// safeAreaInsetsDidChange: a Resize event when either changed, ScaleChange
// when the scale did (another screen); a rotation is a new size, a Resize.
// The app going to the background is
// a Suspend event (IosApp's delegate; no frame is drawn then: iOS
// refuses GPU work in the background, and App.run sleeps in the run loop),
// coming back Resume; the layer stays, so the Surface is not lost. While
// the app is inactive (willResignActive: a call, the app switcher) no
// frame is drawn either, without an event. The controller is an
// HxmcViewController (made at run time) whose status bar and home
// indicator Window.immersive hides. Text input (Window.startTextInput) is
// the view's UIKeyInput: first responder while it is on, the keyboard
// shown (its traits Window.textKind's: Traits); what it inserts a
// TextInput event (a newline: Enter's KeyDown and KeyUp), deleteBackward
// Backspace's. No composition: helder.ui's fields are UIKit's own editors
// on iOS (helder.ui.platform.apple.IosViews), this is a drawn field's. The
// keyboard's frame (UIKeyboardWillChangeFrameNotification) is
// Window.keyboard: its overlap with the view, its animation's duration, a
// Resize.
// The program runs on a thread of its own (helder.os.OsThread), UIKit on
// the main one: every call into UIKit goes there (OsThread.run), and while
// the program runs on, the main thread turns the run loop itself (pump),
// so that UIKit's own scrolling (IosScroll), animations and the keyboard
// keep the display's pace. What UIKit tells meanwhile (touches, read at
// once; the layout; text typed) is the program's at its next call
// (OsThread.soon), its events on its thread (OsThread.back).
@:allow(helder.os)
@:hxmc.unsafe(gc)
class IosWindow {
	static var current:Null<IosWindow> = null;
	static var viewClass = Ptr.nil();
	static var mode = Ptr.nil(); // the run loop's default mode, a CFString
	static var suspended = false;
	// (willResignActive until didBecomeActive)
	static var inactive = false;
	// the display link (CADisplayLink*), whether it runs, its last vsync not drawn yet and its time
	static var link = Ptr.nil();
	static var linked = false;
	static var due = false;
	static var vsyncAt = 0.0;
	static var hidden = false;
	// helder.os.StatusBar's: UIStatusBarStyle (default 0, lightContent 1, darkContent 3), hidden
	static var barStyle = 0;
	static var barHidden = false;
	static final event = new Event();
	// the App.run callback, for the view's and the delegate's events
	static var onEvent:Null<Event->Void>;

	final owner:Window;
	final window:Ptr; // UIWindow*
	final controller:Ptr; // its root UIViewController
	final view:Ptr; // HxmcView
	final layer:Ptr; // CAMetalLayer*, the view's
	final surface:Surface;
	var scale = 1.0;
	var immersive = false;
	// the safe area's insets, in pixels
	var safeTop = 0;
	var safeLeft = 0;
	var safeBottom = 0;
	var safeRight = 0;
	// a touch's position in pixels (locate's)
	var lastX = 0.0;
	// (Window.startTextInput on: the view may be first responder)
	var typing = false;
	var lastY = 0.0;
	final size:Ptr<CGSize>;
	// (a drawn field's traits: Window.textKind)
	var kind = TextKind.PLAIN;

	// (made on the main thread, as UIKit's views must be: OsThread)
	static function make(owner:Window, title:String, width:Int, height:Int):IosWindow
		return OsThread.get(() -> new IosWindow(owner, title, width, height));

	function new(owner:Window, title:String, width:Int, height:Int) {
		if (current != null) throw "helder.os: an iOS app has one window";
		this.owner = owner;
		if (viewClass.isNull()) start();
		size = LibC.malloc(16);
		#if hxmc.dev_host
		// (hxmc dev's host: the window, its controller and view as the last build left them)
		var kept = helder.dev.Hosted.hosted() ? helder.dev.Hosted.get(helder.dev.Hosted.UI_VIEW) : Ptr.nil();
		if (!kept.isNull()) {
			window = helder.dev.Hosted.get(helder.dev.Hosted.UI_WINDOW);
			controller = helder.dev.Hosted.get(helder.dev.Hosted.UI_CONTROLLER);
			view = kept;
			layer = Msg.id(view, ObjC.sel("layer"));
		} else {
		#end
		var screen = Msg.id(ObjC.cls("UIScreen"), ObjC.sel("mainScreen"));
		var bounds = Msg.rect(screen, ObjC.sel("bounds"));
		window = Msg.idRect(Msg.id(ObjC.cls("UIWindow"), ObjC.sel("alloc")), ObjC.sel("initWithFrame:"), bounds);
		view = Msg.idRect(Msg.id(viewClass, ObjC.sel("alloc")), ObjC.sel("initWithFrame:"), bounds);
		Msg.vBool(view, ObjC.sel("setMultipleTouchEnabled:"), true);
		layer = Msg.id(view, ObjC.sel("layer"));
		controller = Msg.id(Msg.id(controllerClass, ObjC.sel("alloc")), ObjC.sel("init"));
		Msg.vPtr(controller, ObjC.sel("setView:"), view);
		Msg.vPtr(window, ObjC.sel("setRootViewController:"), controller);
		#if hxmc.dev_host
		if (helder.dev.Hosted.hosted()) {
			helder.dev.Hosted.set(helder.dev.Hosted.UI_WINDOW, window);
			helder.dev.Hosted.set(helder.dev.Hosted.UI_CONTROLLER, controller);
			helder.dev.Hosted.set(helder.dev.Hosted.UI_VIEW, view);
		}
		}
		#end
		surface = new Surface(Cocoa, layer, view, 1, 1);
		current = this;
		measure();
		var name = Traits.constant("UIKeyboardWillChangeFrameNotification");
		if (!name.isNull())
			Msg.vPtrPtrPtrPtr(Msg.id(ObjC.cls("NSNotificationCenter"), ObjC.sel("defaultCenter")), ObjC.sel("addObserver:selector:name:object:"), view, ObjC.sel("hxmcKeyboard:"), name,
				Ptr.nil());
		Msg.v(window, ObjC.sel("makeKeyAndVisible"));
		// (the display's frames: the link on the main run loop, held until a frame is asked for)
		link = Runtime.objc_retain(Msg.idPtrPtr(ObjC.cls("CADisplayLink"), ObjC.sel("displayLinkWithTarget:selector:"), view, ObjC.sel("hxmcFrame:")));
		Msg.vBool(link, ObjC.sel("setPaused:"), true);
		Msg.vPtrPtr(link, ObjC.sel("addToRunLoop:forMode:"), Msg.id(ObjC.cls("NSRunLoop"), ObjC.sel("mainRunLoop")), mode);
		linked = false;
		due = false;
		#if helder.fullscreen
		setImmersive(true);
		#end
	}

	static var controllerClass = Ptr.nil();

	// the controller's class: its status bar and home indicator hidden while
	// immersive, the status bar's style and hiding helder.os.StatusBar's
	static function controllerMethods(cls:Ptr, replace:Bool) {
		function add(sel:Ptr, imp:Ptr, types:Ptr)
			if (replace) Runtime.class_replaceMethod(cls, sel, imp, types) else Runtime.class_addMethod(cls, sel, imp, types);
		add(ObjC.sel("prefersStatusBarHidden"), Callback.addr(prefersBarHidden), Mem.cstr("B@:"));
		add(ObjC.sel("prefersHomeIndicatorAutoHidden"), Callback.addr(prefersHidden), Mem.cstr("B@:"));
		add(ObjC.sel("preferredStatusBarStyle"), Callback.addr(preferredStyle), Mem.cstr("q@:"));
	}

	@:hxmc.callback static function prefersHidden(self:Ptr, cmd:Ptr):Int
		return hidden ? 1 : 0;

	@:hxmc.callback static function prefersBarHidden(self:Ptr, cmd:Ptr):Int
		return hidden || barHidden ? 1 : 0;

	@:hxmc.callback static function preferredStyle(self:Ptr, cmd:Ptr):Int64
		return barStyle;

	// helder.os.StatusBar: the style and hiding asked of the controller again
	static function statusBar(style:Int, hide:Bool)
		OsThread.run(() -> {
			barStyle = style;
			barHidden = hide;
			if (current != null) Msg.v(current.controller, ObjC.sel("setNeedsStatusBarAppearanceUpdate"));
		});

	// Window.immersive: the status bar and the home indicator hidden (the controller asked again)
	function setImmersive(on:Bool)
		OsThread.run(() -> {
			immersive = on;
			hidden = on;
			Msg.v(controller, ObjC.sel("setNeedsStatusBarAppearanceUpdate"));
			Msg.v(controller, ObjC.sel("setNeedsUpdateOfHomeIndicatorAutoHidden"));
		});

	// ---- the display's frames (CADisplayLink)

	@:hxmc.callback static function displayFrame(self:Ptr, cmd:Ptr, sender:Ptr):Void {
		vsyncAt = FrameClock.toStamp(Msg.f(sender, ObjC.sel("timestamp")), QuartzCore.CACurrentMediaTime(), haxe.Timer.stamp());
		due = true;
		// (the turn's wait ends: the frame is drawn next)
		CF.CFRunLoopStop(CF.CFRunLoopGetMain());
	}

	// a turn's frame (the link's state the main thread's, OsThread): 0 none
	// to draw (no window, suspended or inactive), 1 the vsync's (its time
	// taken: vsyncTaken), 2 not come yet. One handoff and static functions
	// with static arguments: the loop's frames allocate nothing
	static function next():Int {
		OsThread.run(nextNow);
		return nextState;
	}

	static var nextState = 0;
	static var vsyncTaken = 0.0;

	static function nextNow() {
		if (current == null || suspended || inactive) {
			nextState = 0;
		} else if (due) {
			due = false;
			vsyncTaken = vsyncAt;
			nextState = 1;
		} else {
			nextState = 2;
		}
	}

	// the link running: a callback at the next vsync
	static function requestVsync()
		OsThread.run(() -> {
			if (linked || link.isNull()) return;
			linked = true;
			Msg.vBool(link, ObjC.sel("setPaused:"), false);
		});

	// held: no callback until asked for again
	static function pauseVsync()
		OsThread.run(() -> {
			if (!linked) return;
			linked = false;
			Msg.vBool(link, ObjC.sel("setPaused:"), true);
		});

	static function start() {
		mode = ObjC.str("kCFRunLoopDefaultMode");
		OsThread.waitMain = pump;
		OsThread.wakeMain = wakeMain;
		#if hxmc.dev_host
		// (hxmc dev: the view's class and the app delegate's an earlier build made: their methods this build's)
		var made = Runtime.objc_getClass(Mem.cstr("HxmcView"));
		if (!made.isNull()) {
			Runtime.class_replaceMethod(Runtime.object_getClass(made), ObjC.sel("layerClass"), Callback.addr(layerClass), Mem.cstr("#@:"));
			Runtime.class_replaceMethod(made, ObjC.sel("layoutSubviews"), Callback.addr(layoutSubviews), Mem.cstr("v@:"));
			Runtime.class_replaceMethod(made, ObjC.sel("safeAreaInsetsDidChange"), Callback.addr(layoutSubviews), Mem.cstr("v@:"));
			Runtime.class_replaceMethod(made, ObjC.sel("touchesBegan:withEvent:"), Callback.addr(touchesBegan), Mem.cstr("v@:@@"));
			Runtime.class_replaceMethod(made, ObjC.sel("touchesMoved:withEvent:"), Callback.addr(touchesMoved), Mem.cstr("v@:@@"));
			Runtime.class_replaceMethod(made, ObjC.sel("touchesEnded:withEvent:"), Callback.addr(touchesEnded), Mem.cstr("v@:@@"));
			Runtime.class_replaceMethod(made, ObjC.sel("touchesCancelled:withEvent:"), Callback.addr(touchesCancelled), Mem.cstr("v@:@@"));
			Runtime.class_replaceMethod(made, ObjC.sel("hxmcFrame:"), Callback.addr(displayFrame), Mem.cstr("v@:@"));
			Runtime.class_replaceMethod(made, ObjC.sel("hxmcKeyboard:"), Callback.addr(keyboardFrame), Mem.cstr("v@:@"));
			keyInput(made, true);
			var vc = Runtime.objc_getClass(Mem.cstr("HxmcViewController"));
			if (vc.isNull()) controllerClass = makeController() else {
				controllerMethods(vc, true);
				controllerClass = vc;
			}
			IosApp.adopt();
			viewClass = made;
			IosApp.running = true;
			return;
		}
		#end
		var cls = Runtime.objc_allocateClassPair(ObjC.cls("UIView"), Mem.cstr("HxmcView"), 0);
		// (+layerClass: a class method, on the metaclass)
		Runtime.class_addMethod(Runtime.object_getClass(cls), ObjC.sel("layerClass"), Callback.addr(layerClass), Mem.cstr("#@:"));
		Runtime.class_addMethod(cls, ObjC.sel("layoutSubviews"), Callback.addr(layoutSubviews), Mem.cstr("v@:"));
		Runtime.class_addMethod(cls, ObjC.sel("safeAreaInsetsDidChange"), Callback.addr(layoutSubviews), Mem.cstr("v@:"));
		Runtime.class_addMethod(cls, ObjC.sel("touchesBegan:withEvent:"), Callback.addr(touchesBegan), Mem.cstr("v@:@@"));
		Runtime.class_addMethod(cls, ObjC.sel("touchesMoved:withEvent:"), Callback.addr(touchesMoved), Mem.cstr("v@:@@"));
		Runtime.class_addMethod(cls, ObjC.sel("touchesEnded:withEvent:"), Callback.addr(touchesEnded), Mem.cstr("v@:@@"));
		Runtime.class_addMethod(cls, ObjC.sel("touchesCancelled:withEvent:"), Callback.addr(touchesCancelled), Mem.cstr("v@:@@"));
		Runtime.class_addMethod(cls, ObjC.sel("hxmcFrame:"), Callback.addr(displayFrame), Mem.cstr("v@:@"));
		Runtime.class_addMethod(cls, ObjC.sel("hxmcKeyboard:"), Callback.addr(keyboardFrame), Mem.cstr("v@:@"));
		keyInput(cls, false);
		Runtime.objc_registerClassPair(cls);
		viewClass = cls;
		controllerClass = makeController();
		IosApp.running = true;
	}

	// UIKeyInput's methods (and canBecomeFirstResponder) on the view's class
	static function keyInput(cls:Ptr, replace:Bool) {
		inline function add(sel:String, imp:Ptr, types:String)
			if (replace) Runtime.class_replaceMethod(cls, ObjC.sel(sel), imp, Mem.cstr(types)) else Runtime.class_addMethod(cls, ObjC.sel(sel), imp, Mem.cstr(types));
		add("canBecomeFirstResponder", Callback.addr(canBecomeFirstResponder), "B@:");
		add("hasText", Callback.addr(hasText), "B@:");
		add("insertText:", Callback.addr(insertText), "v@:@");
		add("deleteBackward", Callback.addr(deleteBackward), "v@:");
		// (UITextInputTraits, which UIKeyInput adopts)
		add("keyboardType", Callback.addr(keyboardType), "q@:");
		add("returnKeyType", Callback.addr(returnKeyType), "q@:");
		add("autocapitalizationType", Callback.addr(capitalization), "q@:");
		add("autocorrectionType", Callback.addr(correction), "q@:");
		add("spellCheckingType", Callback.addr(correction), "q@:");
		add("isSecureTextEntry", Callback.addr(secure), "B@:");
		add("textContentType", Callback.addr(contentType), "@@:");
		var protocol = Runtime.objc_getProtocol(Mem.cstr("UIKeyInput"));
		if (!protocol.isNull()) Runtime.class_addProtocol(cls, protocol);
	}

	// Window.startTextInput and stopTextInput: the view first responder (the keyboard up) or not
	function textInput(on:Bool)
		OsThread.run(() -> {
			typing = on;
			var first = Msg.b(view, ObjC.sel("isFirstResponder"));
			if (on && !first) Msg.b(view, ObjC.sel("becomeFirstResponder")) else if (!on && first) Msg.b(view, ObjC.sel("resignFirstResponder"));
		});

	// Window.textKind: the traits the view answers, the keyboard made again when it is up
	function setKind(k:TextKind)
		OsThread.run(() -> {
			kind = k;
			if (Msg.b(view, ObjC.sel("isFirstResponder"))) Msg.v(view, ObjC.sel("reloadInputViews"));
		});

	static inline function kindNow():TextKind
		return current == null ? TextKind.PLAIN : current.kind;

	@:hxmc.callback static function keyboardType(self:Ptr, cmd:Ptr):Int64
		return Traits.keyboardType(kindNow());

	@:hxmc.callback static function returnKeyType(self:Ptr, cmd:Ptr):Int64
		return Traits.returnKeyType(kindNow());

	@:hxmc.callback static function capitalization(self:Ptr, cmd:Ptr):Int64
		return Traits.capitalization(kindNow());

	@:hxmc.callback static function correction(self:Ptr, cmd:Ptr):Int64
		return Traits.correction(kindNow());

	@:hxmc.callback static function secure(self:Ptr, cmd:Ptr):Int
		return kindNow().secure ? 1 : 0;

	@:hxmc.callback static function contentType(self:Ptr, cmd:Ptr):Ptr
		return Traits.contentType(kindNow());

	// the keyboard's frame to come (its end, the screen's points): its overlap
	// with the view's bottom (none while it floats: an iPad's undocked one),
	// over its animation's duration
	@:hxmc.callback static function keyboardFrame(self:Ptr, cmd:Ptr, note:Ptr):Void {
		var w = current;
		if (w == null || w.view != self) return;
		var info = Msg.id(note, ObjC.sel("userInfo"));
		if (info.isNull()) return;
		var end = Msg.idPtr(info, ObjC.sel("objectForKey:"), Traits.constant("UIKeyboardFrameEndUserInfoKey"));
		var time = Msg.idPtr(info, ObjC.sel("objectForKey:"), Traits.constant("UIKeyboardAnimationDurationUserInfoKey"));
		if (end.isNull()) return;
		var r = Msg.rectRectPtr(self, ObjC.sel("convertRect:fromView:"), Msg.rect(end, ObjC.sel("CGRectValue")), Ptr.nil());
		var h = Msg.rect(self, ObjC.sel("bounds")).size.height;
		var over = r.origin.y + r.size.height < h - 1 ? 0.0 : Math.max(0, Math.min(h, h - r.origin.y));
		var seconds = time.isNull() ? 0 : Msg.f(time, ObjC.sel("doubleValue"));
		OsThread.soon(() -> {
			w.owner.keyboardChanged(over, seconds);
			var e = event;
			e.kind = Resize;
			e.window = w.owner;
			e.x = w.surface.width;
			e.y = w.surface.height;
			dispatch(e);
		});
	}

	@:hxmc.callback static function canBecomeFirstResponder(self:Ptr, cmd:Ptr):Int
		return current != null && current.typing ? 1 : 0;

	// (always: Backspace reaches the field, which knows whether it has text)
	@:hxmc.callback static function hasText(self:Ptr, cmd:Ptr):Int
		return 1;

	@:hxmc.callback static function insertText(self:Ptr, cmd:Ptr, text:Ptr):Void {
		var w = current, s = ObjC.string(text);
		if (w == null || s == null) return;
		OsThread.soon(() -> w.insert(s));
	}

	function insert(s:String) {
		var typed = new StringBuf();
		for (cp in new haxe.iterators.StringIteratorUnicode(s))
			if (cp == "\n".code || cp == "\r".code) {
				typeText(typed.toString());
				typed = new StringBuf();
				press(0xFF0D);
			} else if (cp >= 0x20 && cp != 0x7F) typed.addChar(cp);
		typeText(typed.toString());
	}

	@:hxmc.callback static function deleteBackward(self:Ptr, cmd:Ptr):Void {
		var w = current;
		if (w != null) OsThread.soon(() -> w.press(0xFF08));
	}

	function typeText(text:String) {
		if (text == "") return;
		var e = event;
		e.kind = TextInput;
		e.window = owner;
		e.text = text;
		e.mods = 0;
		dispatch(e);
	}

	// a key without a character: its KeyDown and KeyUp
	function press(key:Int) {
		var e = event;
		for (kind in [KeyDown, KeyUp]) {
			e.kind = kind;
			e.window = owner;
			e.key = key;
			e.mods = 0;
			e.text = "";
			dispatch(e);
		}
	}

	static function makeController():Ptr {
		var vc = Runtime.objc_allocateClassPair(ObjC.cls("UIViewController"), Mem.cstr("HxmcViewController"), 0);
		controllerMethods(vc, false);
		Runtime.objc_registerClassPair(vc);
		return vc;
	}

	@:hxmc.callback static function layerClass(self:Ptr, cmd:Ptr):Ptr
		return ObjC.cls("CAMetalLayer");

	// the size in pixels, the scale and the safe area, from the view; the
	// layer's drawables follow. Whether the size or the safe area changed
	function measure():Bool {
		var s = Msg.f(Msg.id(ObjC.cls("UIScreen"), ObjC.sel("mainScreen")), ObjC.sel("nativeScale"));
		if (s <= 0) s = 1;
		var scaled = s != scale;
		scale = s;
		Msg.vFloat(view, ObjC.sel("setContentScaleFactor:"), s);
		Msg.vFloat(layer, ObjC.sel("setContentsScale:"), s);
		var b = Msg.rect(view, ObjC.sel("bounds"));
		var w = Math.round(b.size.width * s), h = Math.round(b.size.height * s);
		if (w < 1) w = 1;
		if (h < 1) h = 1;
		size.value.width = w;
		size.value.height = h;
		Msg.vSize(layer, ObjC.sel("setDrawableSize:"), size.value);
		var i = Msg.insets(view, ObjC.sel("safeAreaInsets"));
		var t = Math.round(i.top * s), l = Math.round(i.left * s), bt = Math.round(i.bottom * s), r = Math.round(i.right * s);
		var changed = w != surface.width || h != surface.height || t != safeTop || l != safeLeft || bt != safeBottom || r != safeRight;
		safeTop = t;
		safeLeft = l;
		safeBottom = bt;
		safeRight = r;
		if (w != surface.width || h != surface.height) surface.resized(w, h);
		if (scaled && onEvent != null) {
			var e = event;
			e.kind = ScaleChange;
			e.window = owner;
			dispatch(e);
		}
		return changed;
	}

	@:hxmc.callback static function layoutSubviews(self:Ptr, cmd:Ptr):Void {
		var w = current;
		if (w != null && w.view == self) OsThread.soon(w.laidOut);
	}

	// (on the main thread, the program waiting: its size and safe area measured, told)
	function laidOut() {
		if (!measure()) return;
		var e = event;
		e.kind = Resize;
		e.window = owner;
		e.x = surface.width;
		e.y = surface.height;
		dispatch(e);
	}

	// ---- touches: every finger a pointer (Pointers: a UITouch's slot by its
	// address, its coalesced touches as samples)

	@:hxmc.callback static function touchesBegan(self:Ptr, cmd:Ptr, touches:Ptr, ev:Ptr):Void {
		var w = current;
		if (w == null) return;
		var all = w.read(touches, Ptr.nil());
		OsThread.soon(() -> for (t in all) {
			var p = Pointers.press(w.owner, t.key, t.type, t.x, t.y, t.force, t.time);
			if (p != null) w.send(PointerDown, p, 1);
		});
	}

	@:hxmc.callback static function touchesMoved(self:Ptr, cmd:Ptr, touches:Ptr, ev:Ptr):Void {
		var w = current;
		if (w == null) return;
		var all = w.read(touches, ev);
		OsThread.soon(() -> for (t in all) {
			var p = Pointers.find(t.key, t.type);
			if (p == null) continue;
			// (the touches the screen saw since the last: the latest is t)
			var k = 0;
			while (k < t.samples.length) {
				@:privateAccess p.sample(t.samples[k], t.samples[k + 1], t.samples[k + 2]);
				k += 3;
			}
			@:privateAccess p.moveTo(t.x, t.y, t.force, t.time);
			w.send(PointerMove, p, 0);
		});
	}

	@:hxmc.callback static function touchesEnded(self:Ptr, cmd:Ptr, touches:Ptr, ev:Ptr):Void
		lift(touches, false);

	@:hxmc.callback static function touchesCancelled(self:Ptr, cmd:Ptr, touches:Ptr, ev:Ptr):Void
		lift(touches, true);

	static function lift(touches:Ptr, cancelled:Bool) {
		var w = current;
		if (w == null) return;
		var all = w.read(touches, Ptr.nil());
		OsThread.soon(() -> for (t in all) {
			var p = Pointers.find(t.key, t.type);
			if (p != null) {
				@:privateAccess p.moveTo(t.x, t.y, p.pressure, t.time);
				Pointers.lift(p, cancelled, t.time);
				w.send(cancelled ? PointerCancel : PointerUp, p, cancelled ? 0 : 1);
			}
		});
	}

	// (the touches as they are now, read on the main thread: UIKit changes
	// a UITouch as its finger moves, and its coalesced ones are the event's)
	function read(touches:Ptr, ev:Ptr):Array<TouchAt> {
		var all = Msg.id(touches, ObjC.sel("allObjects")), n = Msg.i(all, ObjC.sel("count")), out = [];
		var i:Int64 = 0;
		while (i < n) {
			var t = Msg.idInt(all, ObjC.sel("objectAtIndex:"), i);
			i++;
			var samples = [];
			var co = ev.isNull() ? Ptr.nil() : Msg.idPtr(ev, ObjC.sel("coalescedTouchesForTouch:"), t);
			var cn = co.isNull() ? 0 : Msg.i(co, ObjC.sel("count"));
			var j:Int64 = 0;
			while (j < cn - 1) {
				var c = Msg.idInt(co, ObjC.sel("objectAtIndex:"), j);
				j++;
				locate(c);
				samples.push(lastX);
				samples.push(lastY);
				samples.push(time(c));
			}
			locate(t);
			out.push(new TouchAt(key(t), type(t), lastX, lastY, force(t), time(t), samples));
		}
		return out;
	}

	// a UITouch's key (Pointers: its address, folded)
	static inline function key(t:Ptr):Int {
		var a = t.toI64();
		return (a >> 32).toInt() ^ a.toInt();
	}

	// UITouchTypePencil (2): a pen; the others fingers (indirect pointers too)
	static inline function type(t:Ptr):PointerType
		return Msg.i(t, ObjC.sel("type")) == 2 ? Pen : Touch;

	// its force, 0 to 1 (1 where the screen measures none)
	static function force(t:Ptr):Float {
		var max = Msg.f(t, ObjC.sel("maximumPossibleForce"));
		return max > 0 ? Math.min(1, Msg.f(t, ObjC.sel("force")) / max) : 1;
	}

	// a touch's time (ms: UITouch.timestamp, seconds since the boot)
	static function time(t:Ptr):Float
		return Msg.f(t, ObjC.sel("timestamp")) * 1000;

	function locate(t:Ptr) {
		var p = Msg.pointPtr(t, ObjC.sel("locationInView:"), view);
		lastX = p.x * scale;
		lastY = p.y * scale;
	}

	function send(kind:EventKind, p:Pointer, button:Int) {
		var e = event;
		Pointers.fill(e, kind, p, button);
		dispatch(e);
	}


	// ---- the app's lifecycle (IosApp's delegate)

	// willResignActive (on) and didBecomeActive: no frames meanwhile, no event
	static function activate(on:Bool) {
		inactive = !on;
		if (!on) pauseVsync();
	}

	// (the program waiting, on the main thread: IosApp's)
	static function suspend(on:Bool) {
		if (on == suspended) return;
		suspended = on;
		if (on) pauseVsync();
		if (AppAudio.hold != null) AppAudio.hold(on);
		App.lifecycle(on);
		var w = current;
		if (w == null) return;
		var e = event;
		// (the background: every finger let go)
		if (on) Pointers.cancelAll(w.owner, e, onEvent);
		e.kind = on ? Suspend : Resume;
		e.window = w.owner;
		e.x = w.surface.width;
		e.y = w.surface.height;
		dispatch(e);
	}

	// (on the program's thread: OsThread)
	static function dispatch(e:Event) {
		var f = onEvent;
		if (f != null) OsThread.back(() -> f(e));
	}

	// whether a frame can be drawn now (active: not in the background, nor inactive)
	// the run loop's pending sources, without waiting (the view's and the
	// delegate's callbacks come from inside); served from inside a callout
	// (a callback waiting for the program: OsThread.nested), what came
	// meanwhile only, the run loop not run again inside UIKit's own call
	static function poll(onEvent:Event->Void) {
		polled = onEvent;
		OsThread.run(pollNow);
	}

	// (the program's arguments, the main thread's to read in the handoff)
	static var polled:Null<Event->Void>;
	static var waited = 0.0;

	static function pollNow() {
		onEvent = polled;
		if (mode.isNull() || OsThread.nested()) return;
		while (CF.CFRunLoopRunInMode(mode, 0, true) == 4) {}
	}

	// waits for a source of the run loop, or seconds (< 0: no limit)
	static function wait(seconds:Float) {
		waited = seconds;
		OsThread.run(waitNow);
	}

	static function waitNow() {
		if (mode.isNull() || OsThread.nested()) return;
		CF.CFRunLoopRunInMode(mode, waited < 0 ? 1e9 : waited, true);
	}

	// the main thread's wait while the program runs on: the run loop turned
	// (UIKit's touches, layout, scroll views and animations), until a
	// source is handled or a call comes (wakeMain stops it)
	static function pump():Bool {
		if (mode.isNull()) return false;
		var pool = Runtime.objc_autoreleasePoolPush();
		CF.CFRunLoopRunInMode(mode, 1.0, true);
		Runtime.objc_autoreleasePoolPop(pool);
		return true;
	}

	static function wakeMain() {
		var main = CF.CFRunLoopGetMain();
		CF.CFRunLoopStop(main);
		CF.CFRunLoopWakeUp(main);
	}

	function destroy()
		OsThread.run(destroyNow);

	function destroyNow() {
		current = null;
		Msg.vPtr(Msg.id(ObjC.cls("NSNotificationCenter"), ObjC.sel("defaultCenter")), ObjC.sel("removeObserver:"), view);
		// (the link's target is this build's view class's method: gone with it, also at a hand-over)
		if (!link.isNull()) {
			Msg.v(link, ObjC.sel("invalidate"));
			Runtime.objc_release(link);
			link = Ptr.nil();
			linked = due = false;
		}
		#if hxmc.dev_host
		// (handing over: the window, its controller and view left to the next build)
		if (helder.dev.Hosted.handingOver && helder.dev.Hosted.get(helder.dev.Hosted.UI_VIEW) == view) {
			LibC.free(size);
			return;
		}
		#end
		Msg.vBool(window, ObjC.sel("setHidden:"), true);
		Runtime.objc_release(controller);
		Runtime.objc_release(view);
		Runtime.objc_release(window);
		LibC.free(size);
	}

	// the general pasteboard's text (UIPasteboard)
	static function writeClipboard(text:String)
		OsThread.run(() -> {
			var s = ObjC.str(text);
			Msg.vPtr(Msg.id(ObjC.cls("UIPasteboard"), ObjC.sel("generalPasteboard")), ObjC.sel("setString:"), s);
			ObjC.release(s);
		});

	// helder.os.Haptics: a selection's tick (UISelectionFeedbackGenerator),
	// a medium impact (UIImpactFeedbackGenerator, style 1), each made and let go
	// the root view controller of the window shown (nil: none yet; helder.os.Links presents over it)
	static function controllerNow():Ptr
		return current == null ? Ptr.nil() : current.controller;

	static function haptic(strong:Bool)
		OsThread.run(() -> hapticNow(strong));

	static function hapticNow(strong:Bool) {
		var g = strong ? Msg.idInt(Msg.id(ObjC.cls("UIImpactFeedbackGenerator"), ObjC.sel("alloc")), ObjC.sel("initWithStyle:"), 1) : Msg.id(Msg.id(ObjC.cls("UISelectionFeedbackGenerator"),
			ObjC.sel("alloc")), ObjC.sel("init"));
		if (g.isNull()) return;
		if (strong) Msg.v(g, ObjC.sel("impactOccurred")) else Msg.v(g, ObjC.sel("selectionChanged"));
		ObjC.release(g);
	}

	static function readClipboard():Null<String>
		return OsThread.get(readClipboardNow);

	static function readClipboardNow():Null<String> {
		var pool = Runtime.objc_autoreleasePoolPush();
		var text = ObjC.string(Msg.id(Msg.id(ObjC.cls("UIPasteboard"), ObjC.sel("generalPasteboard")), ObjC.sel("string")));
		Runtime.objc_autoreleasePoolPop(pool);
		return text;
	}

	// the system's appearance (the trait collection's interface style: 2 dark)
	static function dark():Bool
		return OsThread.get(() -> Msg.i(Msg.id(ObjC.cls("UITraitCollection"), ObjC.sel("currentTraitCollection")), ObjC.sel("userInterfaceStyle")) == 2);
}

// (a touch as UIKit had it when it told: the program's at its next call)
private class TouchAt {
	public final key:Int;
	public final type:PointerType;
	public final x:Float;
	public final y:Float;
	public final force:Float;
	public final time:Float;
	// (its coalesced touches before it: x, y, time each)
	public final samples:Array<Float>;

	public function new(key, type, x, y, force, time, samples) {
		this.key = key;
		this.type = type;
		this.x = x;
		this.y = y;
		this.force = force;
		this.time = time;
		this.samples = samples;
	}
}
