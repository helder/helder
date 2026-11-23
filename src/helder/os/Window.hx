package helder.os;

#if (!helder.os || helder.os == "android")
import helder.os.android.AndroidWindow;
#end
#if (!helder.os || helder.os == "macos")
import helder.os.cocoa.CocoaWindow;
#end
#if (!helder.os || helder.os == "ios")
import helder.os.uikit.UIKitWindow;
#end
#if (!helder.os || helder.os == "web")
import helder.os.web.CanvasWindow;
#end
#if (!helder.os || helder.os == "windows")
import helder.os.win32.Win32Window;
#end
#if (!helder.os || helder.os == "linux")
import helder.os.x11.X11Window;
import helder.os.wayland.WaylandWindow;
#end
import helder.os.TitleBar;
import helder.view.graph.Graph;
import helder.view.graph.Read;
import helder.view.graph.Signal;
import hxmc.Platform;

// A top-level window, its size in points (pixels on X11). Its Surface
// carries the native handles for helder.gfx, its size in pixels. Cocoa on
// macOS (helder.os.cocoa.CocoaWindow), Win32 on Windows
// (helder.os.win32.Win32Window), a canvas in the browser (WebAssembly:
// helder.os.web.CanvasWindow, its size in CSS pixels), X11 elsewhere
// (helder.os.x11.X11Window); on Android the activity's window
// (helder.os.android.AndroidWindow: full screen, one per app, the size and
// title the system's), on iOS a UIWindow (helder.os.uikit.UIKitWindow: the
// same); on Linux with WAYLAND_DISPLAY set, Wayland's
// (helder.os.wayland.WaylandWindow; X11 where it cannot connect, or HELDER_X11=1).
class Window {
	@:typescript public final surface:Surface;
	// its title bar's text (the browser: the page's title)
	@:typescript public var title(default, set):String;
	@:typescript public var closed(default, null) = false;

	// the native window, the target's (Platform.os() is known when compiling: the
	// other's code is never reached, as long as no field or method has its type;
	// a build for one system, helder.os, types only its own: helder.compiler.Os)
	final native:Any;

	// (a build for a headless run, -D helder.headless: every window a
	// helder.os.headless.HeadlessWindow, the others' code not linked)
	static inline final HEADLESS = #if helder.headless true #else false #end;

	#if (!helder.os || helder.headless)
	inline function headless():helder.os.headless.HeadlessWindow
		return cast native;
	#end

	#if (!helder.os || helder.os == "ios") inline function ios():UIKitWindow return cast native; #end
	#if (!helder.os || helder.os == "macos") inline function mac():CocoaWindow return cast native; #end
	#if (!helder.os || helder.os == "windows") inline function win():Win32Window return cast native; #end
	#if (!helder.os || helder.os == "web") inline function web():CanvasWindow return cast native; #end
	#if (!helder.os || helder.os == "android") inline function android():AndroidWindow return cast native; #end
	#if (!helder.os || helder.os == "linux")
	inline function wayland():WaylandWindow
		return cast native;

	inline function x11():X11Window
		return cast native;
	#end

	// the system's title bar, or the content under it (TitleBar: "inset",
	// the window's buttons in the app's layout); given when it is made
	public final titlebar:TitleBar;

	@:typescript public function new(title:String, width:Int, height:Int, titlebar:TitleBar = Standard) {
		this.title = title;
		this.titlebar = titlebar;
		#if (!helder.os || helder.headless)
		if (HEADLESS) {
			native = new helder.os.headless.HeadlessWindow(this, width, height);
			surface = headless().surface;
			App.windows.push(this);
			return;
		}
		#end
		native =
			#if (!helder.os || helder.os == "ios") Platform.apple() >= 1 ? UIKitWindow.make(this, title, width, height) : #end
			#if (!helder.os || helder.os == "macos") Platform.os() == 1 ? CocoaWindow.make(this, title, width, height) : #end
			#if (!helder.os || helder.os == "windows") Platform.os() == 2 ? Win32Window.make(this, title, width, height) : #end
			#if (!helder.os || helder.os == "web") Platform.os() == 3 ? new CanvasWindow(this, title, width, height) : #end
			#if (!helder.os || helder.os == "android") Platform.target() >= 9 ? new AndroidWindow(this, title, width, height) : #end
			#if (!helder.os || helder.os == "linux") WaylandWindow.active() ? new WaylandWindow(this, title, width, height) : new X11Window(this, title, width, height) #else throw "unreachable" #end;
		surface =
			#if (!helder.os || helder.os == "ios") Platform.apple() >= 1 ? ios().surface : #end
			#if (!helder.os || helder.os == "macos") Platform.os() == 1 ? mac().surface : #end
			#if (!helder.os || helder.os == "windows") Platform.os() == 2 ? win().surface : #end
			#if (!helder.os || helder.os == "web") Platform.os() == 3 ? web().surface : #end
			#if (!helder.os || helder.os == "android") Platform.target() >= 9 ? android().surface : #end
			#if (!helder.os || helder.os == "linux") (Std.isOfType(native, WaylandWindow) ? wayland().surface : x11().surface) #else throw "unreachable" #end;
		App.windows.push(this);
	}

	// the surface's size in pixels
	@:typescript public var width(get, never):Int;
	@:typescript public var height(get, never):Int;

	inline function get_width()
		return surface.width;

	inline function get_height()
		return surface.height;

	// pixels per point (2 on a Retina display, the monitor's DPI / 96 on Windows,
	// the browser's devicePixelRatio; 1 on X11; iOS: the screen's native scale)
	@:typescript public var scale(get, never):Float;

	function get_scale():Float
		return
			#if (!helder.os || helder.headless) HEADLESS ? headless().scale : #end
			#if (!helder.os || helder.os == "ios") Platform.apple() >= 1 ? ios().scale : #end
			#if (!helder.os || helder.os == "macos") Platform.os() == 1 ? mac().scale : #end
			#if (!helder.os || helder.os == "windows") Platform.os() == 2 ? win().scale : #end
			#if (!helder.os || helder.os == "web") Platform.os() == 3 ? web().scale : #end
			#if (!helder.os || helder.os == "android") Platform.target() >= 9 ? android().scale : #end
			#if (!helder.os || helder.os == "linux") Std.isOfType(native, WaylandWindow) ? wayland().scale() : 1 #else 1 #end;

	// the safe area: the insets from each edge, in pixels, that the system's
	// bars, a notch, a display cutout or rounded corners leave clear, as
	// CSS's env(safe-area-inset-*) (iOS: the view's safeAreaInsets; Android:
	// the window's insets, its bars and cutout; 0 elsewhere); a Resize event
	// follows a change (a rotation, the bars hidden)
	public var safeTop(get, never):Int;
	public var safeLeft(get, never):Int;
	public var safeBottom(get, never):Int;
	public var safeRight(get, never):Int;

	function get_safeTop():Int
		return
			HEADLESS ? 0 :
			#if (!helder.os || helder.os == "ios") Platform.apple() >= 1 ? ios().safeTop : #end
			#if (!helder.os || helder.os == "android") Platform.target() >= 9 ? android().safeTop : #end
			0;

	function get_safeLeft():Int
		return
			HEADLESS ? 0 :
			#if (!helder.os || helder.os == "ios") Platform.apple() >= 1 ? ios().safeLeft : #end
			#if (!helder.os || helder.os == "android") Platform.target() >= 9 ? android().safeLeft : #end
			0;

	// (the keyboard up: the larger of the bottom inset and its height, so that
	// a layout clear of the safe area is clear of the keyboard)
	function get_safeBottom():Int {
		var b =
			HEADLESS ? 0 :
			#if (!helder.os || helder.os == "ios") Platform.apple() >= 1 ? ios().safeBottom : #end
			#if (!helder.os || helder.os == "android") Platform.target() >= 9 ? android().safeBottom : #end
			0;
		return Std.int(Math.max(b, Math.round(keyboardHeight.peek() * scale)));
	}

	// the soft keyboard's height over the window in points, 0 while it is
	// hidden (a signal): iOS's keyboard frame (UIKeyboardWillChangeFrame),
	// Android's IME insets, the browser's visual viewport against the
	// window; 0 on the desktop. A change comes with a Resize, the safe
	// area's bottom following it; keyboardDuration is its animation's
	// seconds where the system gives them (iOS's), else 0
	@:typescript public var keyboard(get, never):Read<Float>;
	public var keyboardDuration(default, null) = 0.0;

	final keyboardHeight:Signal<Float> = Graph.signal(0.0);

	function get_keyboard():Read<Float>
		return keyboardHeight;

	// (the platform's window: the keyboard's height now, in points)
	@:allow(helder.os) function keyboardChanged(points:Float, duration:Float) {
		if (points == keyboardHeight.peek()) return;
		keyboardDuration = duration;
		keyboardHeight(points);
	}

	function get_safeRight():Int
		return
			HEADLESS ? 0 :
			#if (!helder.os || helder.os == "ios") Platform.apple() >= 1 ? ios().safeRight : #end
			#if (!helder.os || helder.os == "android") Platform.target() >= 9 ? android().safeRight : #end
			0;

	// the system's bars hidden, the app on the whole screen (a game's): on
	// Android immersive (the status and navigation bars hidden, a swipe
	// shows them for a while; the window into a cutout's edges), on iOS the
	// status bar and the home indicator hidden (the indicator dims, a swipe
	// shows it); nothing elsewhere. The safe area follows (a Resize).
	// package.json's "helder": {"fullscreen": true} sets it from the start
	// (-D helder.fullscreen)
	public var immersive(get, set):Bool;

	function get_immersive():Bool
		return
			HEADLESS ? false :
			#if (!helder.os || helder.os == "ios") Platform.apple() >= 1 ? ios().immersive : #end
			#if (!helder.os || helder.os == "android") Platform.target() >= 9 ? android().immersive : #end
			false;

	function set_immersive(on:Bool):Bool {
		if (closed || on == immersive || HEADLESS) return on;
		#if (!helder.os || helder.os == "ios") if (Platform.apple() >= 1) ios().setImmersive(on) else #end
		#if (!helder.os || helder.os == "android") if (Platform.target() >= 9) AndroidWindow.setImmersive(cast native, on) else #end
		{};
		return on;
	}

	// whether a scroll at x, y (pixels) by dx, dy (as Scroll's deltas: a
	// drag's start and its direction, the content following the finger)
	// moves something of the program's: asked once per touch drag, at its
	// start, where the system would otherwise take the drag. In the
	// browser, a canvas whose touchAction pans (the page scrolls along
	// pan-y): true, the drag is the program's (its pointer's moves, the page
	// held still); false, or null (not asked), the page pans (the pointer
	// cancelled: PointerCancel). Elsewhere every drag is the program's
	public var scrollsAt:Null<(x:Int, y:Int, dx:Float, dy:Float) -> Bool> = null;

	// an inset title bar's answer for a press at x, y (pixels): a drag
	// region, one of the app's window buttons, or the content's (null: the
	// content's everywhere). Asked by the system's code at the press
	// (macOS: a drag then performWindowDragWithEvent:, a double click the
	// zoom; Wayland's and X11's moves), and on Windows for each
	// WM_NCHITTEST (HTCAPTION, HTMAXBUTTON for its snap layouts)
	public var titlebarAt:Null<(x:Int, y:Int) -> TitleHit> = null;

	// each input event as it is read, before the program gets it (helder.ui's
	// compositor: Event.routed set; where the main thread reads input while
	// the program is busy, on the main thread: OsThread)
	@:noCompletion public var route:Null<Event->Void> = null;

	// (e routed by its window's compositor, or the program's)
	@:noCompletion public static function routed(e:Event) {
		var w = e.window;
		if (w != null && w.route != null) w.route(e) else e.routed = e.gesture = 0;
	}

	// an inset title bar's area free of the window's buttons, in pixels (the
	// Window Controls Overlay's titlebar-area-*): macOS's right of its
	// buttons, elsewhere the top bar but the drawn buttons' width at the
	// right (TitleBars); null when not inset, or full screen
	public function titlebarArea():Null<{x:Int, y:Int, width:Int, height:Int}> {
		if (titlebar != Inset || closed || fullscreen) return null;
		var c = systemControls();
		if (c != null) {
			var h = Std.int(Math.max(c.y * 2 + c.height, Math.round(28 * scale)));
			return {x: c.x + c.width, y: 0, width: width - c.x - c.width, height: h};
		}
		if (Platform.apple() >= 1 || Platform.os() == 3 || Platform.target() >= 9) return null;
		var k = scale, linux = Platform.os() == 0;
		var b = Math.round(3 * TitleBars.button(linux) * k);
		return {x: 0, y: 0, width: width - b, height: Math.round(TitleBars.HEIGHT * k)};
	}

	// the system's own window buttons over an inset window's content, in
	// pixels (macOS's three, where they are now); null where the app draws
	// its own (TitleBars' sizes), or not inset. A headless run of a macOS
	// build has them where macOS puts them
	public function systemControls():Null<{x:Int, y:Int, width:Int, height:Int}> {
		if (titlebar != Inset || closed) return null;
		// (nested: only a constant condition drops the other targets' code)
		if (Platform.os() == 1) {
			if (Platform.apple() >= 1) return null;
			#if (!helder.os || helder.headless)
			if (HEADLESS) {
				var k = headless().scale;
				return {x: Math.round(headless().controlsX * k), y: Math.round(headless().controlsY * k), width: Math.round(54 * k), height: Math.round(16 * k)};
			}
			#end
			#if (!helder.os || helder.os == "macos") return mac().controls(); #end
		}
		return null;
	}

	// the system's buttons' top left moved to x, y (pixels: macOS's, again
	// after each resize; nothing elsewhere)
	public function placeControls(x:Int, y:Int) {
		if (titlebar != Inset || closed) return;
		if (Platform.os() == 1) {
			if (Platform.apple() >= 1) {} else
			#if (!helder.os || helder.headless)
			if (HEADLESS) {
				headless().controlsX = x / headless().scale;
				headless().controlsY = y / headless().scale;
			} else
			#end
			#if (!helder.os || helder.os == "macos") mac().placeControls(x, y); #else {} #end
		}
	}

	// minimised to the Dock or the task bar (Wayland: asked of the compositor)
	public function minimize() {
		if (closed || HEADLESS) return;
		if (Platform.apple() >= 1) {} else
		#if (!helder.os || helder.os == "macos") if (Platform.os() == 1) mac().minimize() else #end
		#if (!helder.os || helder.os == "windows") if (Platform.os() == 2) win().minimize() else #end
		if (Platform.os() == 3) {} else
		if (Platform.target() >= 9) {} else
		#if (!helder.os || helder.os == "linux") (Std.isOfType(native, WaylandWindow) ? wayland().minimize() : x11().minimize()); #else {} #end
	}

	// maximised (macOS: zoomed), or back
	public var maximized(get, set):Bool;

	function get_maximized():Bool
		return
			closed || HEADLESS ? false :
			Platform.apple() >= 1 ? false :
			#if (!helder.os || helder.os == "macos") Platform.os() == 1 ? mac().zoomed() : #end
			#if (!helder.os || helder.os == "windows") Platform.os() == 2 ? win().maximized() : #end
			Platform.os() == 3 ? false :
			Platform.target() >= 9 ? false :
			#if (!helder.os || helder.os == "linux") (Std.isOfType(native, WaylandWindow) ? wayland().maximized : x11().maximized) #else false #end;

	function set_maximized(on:Bool):Bool {
		if (closed || HEADLESS || on == maximized) return on;
		if (Platform.apple() >= 1) {} else
		#if (!helder.os || helder.os == "macos") if (Platform.os() == 1) mac().zoom() else #end
		#if (!helder.os || helder.os == "windows") if (Platform.os() == 2) win().maximize(on) else #end
		if (Platform.os() == 3) {} else
		if (Platform.target() >= 9) {} else
		#if (!helder.os || helder.os == "linux") (Std.isOfType(native, WaylandWindow) ? wayland().maximize(on) : x11().maximize(on)); #else {} #end
		return on;
	}

	// the pointer's shape over the window (Auto: Default)
	public var cursor(default, set):Cursor = Default;

	function set_cursor(c:Cursor):Cursor {
		if (c == Auto) c = Default;
		if (c == cursor || closed) return c;
		cursor = c;
		if (HEADLESS) {} else
		if (Platform.apple() >= 1) {} else
		#if (!helder.os || helder.os == "macos") if (Platform.os() == 1) mac().setCursor(c) else #end
		#if (!helder.os || helder.os == "windows") if (Platform.os() == 2) win().setCursor(c) else #end
		#if (!helder.os || helder.os == "web") if (Platform.os() == 3) web().setCursor(c) else #end
		if (Platform.target() >= 9) {} else
		#if (!helder.os || helder.os == "linux") (Std.isOfType(native, WaylandWindow) ? wayland().setCursor(c) : x11().setCursor(c)); #else {} #end
		return c;
	}

	// whether text is typed into it now (startTextInput until stopTextInput:
	// a text field focused, ui's UiWindow), when Escape is the field's, not App.onBack's
	public var typing(default, null) = false;

	// where text is typed now (a text field's caret: x, y, width, height in
	// pixels from the top left), until stopTextInput: an input method shows
	// its composition and candidates there. In the browser keys then reach an
	// input element of the page, on macOS through a text view (NSTextInputClient)
	// at the caret: their compositions as TextEditing events; on Windows
	// through TSF (helder.os.win32.Tsf: its document the field's,
	// textContext), the composition as TextEditing, the candidates below the
	// caret (where TSF is not there, the IME's own windows placed: imm32);
	// on Wayland through text-input-unstable-v3 (WaylandTextInput: the
	// caret's rectangle, the field's text, its compositions as TextEditing);
	// X11's input method keeps its own place;
	// Android shows the soft keyboard, its input method through a hidden
	// EditText (helder.os.android.TextInput, once enabled), compositions as
	// TextEditing; iOS its keyboard, the view's UIKeyInput (no compositions)
	public function startTextInput(x:Int, y:Int, width:Int, height:Int) {
		if (closed) return;
		typing = true;
		#if (!helder.os || helder.headless) if (HEADLESS) helder.headless.Headless.run.textInputAt(x, y, width, height) else #end
		#if (!helder.os || helder.os == "web") if (Platform.os() == 3) web().textInput(true, x, y, width, height) else #end
		#if (!helder.os || helder.os == "windows") if (Platform.os() == 2) win().textInputArea(x, y, width, height) else #end
		#if (!helder.os || helder.os == "ios") if (Platform.apple() >= 1) ios().textInput(true) else #end
		#if (!helder.os || helder.os == "macos") if (Platform.os() == 1) mac().textInput(true, x, y, width, height) else #end
		#if (!helder.os || helder.os == "android") if (Platform.target() >= 9) android().textInput(true, x, y, width, height) else #end
		#if (!helder.os || helder.os == "linux") if (Std.isOfType(native, WaylandWindow)) wayland().textInputOn(x, y, width, height); #else {} #end
	}

	// the text around where text is typed (a text field's text and its
	// selection, UTF-16 indices), what an input method reads and edits:
	// Windows' TSF document, Wayland's surrounding text (text-input-v3),
	// Android's InputConnection (helder.os.android.TextInput);
	// multiline (a text area) and secret (a password: no text given, input
	// methods told) its kind. Given after startTextInput, again whenever it
	// changes; the input method's edits of it come as TextReplace (and
	// TextInput, TextEditing, TextSelect). Nothing elsewhere
	public function textContext(text:String, start:Int, end:Int, multiline = false, secret = false) {
		if (closed || !typing || HEADLESS) return;
		#if (!helder.os || helder.os == "windows") if (Platform.os() == 2) win().textContext(secret ? "" : text, secret ? 0 : start, secret ? 0 : end) else #end
		#if (!helder.os || helder.os == "linux") if (Platform.os() == 0 && Platform.target() < 9 && Std.isOfType(native, WaylandWindow)) wayland().textContext(text, start, end, multiline, secret) else #end
		#if (!helder.os || helder.os == "android") if (Platform.os() == 0 && Platform.target() >= 9) android().textContext(text, start, end) else #end
		{};
	}

	// what the field typed into takes (TextKind: its keyboard, its Enter
	// key, capitalisation, corrections), given before startTextInput and
	// whenever it changes: iOS's keyboard (the view's UITextInputTraits) and
	// Android's EditorInfo for a drawn field; nothing elsewhere
	public function textKind(kind:TextKind) {
		if (closed || HEADLESS) return;
		#if (!helder.os || helder.os == "ios") if (Platform.apple() >= 1) ios().setKind(kind) else #end
		#if (!helder.os || helder.os == "android") if (Platform.os() == 0 && Platform.target() >= 9) android().textKind(kind) else #end
		{};
	}

	public function stopTextInput() {
		typing = false;
		if (closed || HEADLESS) return;
		#if (!helder.os || helder.os == "web") if (Platform.os() == 3) web().textInput(false, 0, 0, 0, 0) else #end
		#if (!helder.os || helder.os == "windows") if (Platform.os() == 2) win().stopTextInput() else #end
		#if (!helder.os || helder.os == "ios") if (Platform.apple() >= 1) ios().textInput(false) else #end
		#if (!helder.os || helder.os == "macos") if (Platform.os() == 1) mac().textInput(false, 0, 0, 0, 0) else #end
		#if (!helder.os || helder.os == "android") if (Platform.target() >= 9) android().textInput(false, 0, 0, 0, 0) else #end
		#if (!helder.os || helder.os == "linux") if (Std.isOfType(native, WaylandWindow)) wayland().textInputOff(); #else {} #end
	}

	function set_title(v:String):String {
		if (v == title) return v;
		title = v;
		if (native == null || closed || HEADLESS) return v;
		if (Platform.apple() >= 1) {} else
		#if (!helder.os || helder.os == "macos") if (Platform.os() == 1) mac().setTitle(v) else #end
		#if (!helder.os || helder.os == "windows") if (Platform.os() == 2) win().setTitle(v) else #end
		#if (!helder.os || helder.os == "web") if (Platform.os() == 3) web().setTitle(v) else #end
		if (Platform.target() >= 9) {} else
		#if (!helder.os || helder.os == "linux") (Std.isOfType(native, WaylandWindow) ? wayland().setTitle(v) : x11().setTitle(v)); #else {} #end
		return v;
	}

	// its content made width x height points (pixels on X11; the browser: the
	// canvas's CSS size); a Resize event follows
	public function resize(width:Int, height:Int) {
		if (closed) return;
		#if (!helder.os || helder.headless) if (HEADLESS) headless().resize(width, height) else #end
		if (Platform.apple() >= 1) {} else
		#if (!helder.os || helder.os == "macos") if (Platform.os() == 1) mac().resize(width, height) else #end
		#if (!helder.os || helder.os == "windows") if (Platform.os() == 2) win().resize(width, height) else #end
		#if (!helder.os || helder.os == "web") if (Platform.os() == 3) web().resize(width, height) else #end
		if (Platform.target() >= 9) {} else
		#if (!helder.os || helder.os == "linux") (Std.isOfType(native, WaylandWindow) ? wayland().resize(width, height) : x11().resize(width, height)); #else {} #end
	}

	// the smallest content the user may resize it to, in points (the browser: the canvas's CSS minimum)
	public function setMinSize(width:Int, height:Int) {
		if (closed || HEADLESS) return;
		if (Platform.apple() >= 1) {} else
		#if (!helder.os || helder.os == "macos") if (Platform.os() == 1) mac().setMinSize(width, height) else #end
		#if (!helder.os || helder.os == "windows") if (Platform.os() == 2) win().setMinSize(width, height) else #end
		#if (!helder.os || helder.os == "web") if (Platform.os() == 3) web().setMinSize(width, height) else #end
		if (Platform.target() >= 9) {} else
		#if (!helder.os || helder.os == "linux") (Std.isOfType(native, WaylandWindow) ? wayland().setMinSize(width, height) : x11().setMinSize(width, height)); #else {} #end
	}

	// the window on the whole screen, without its frame: X11's
	// _NET_WM_STATE_FULLSCREEN (asked of the window manager: a Resize when
	// it does), Windows' a borderless window over the monitor (its frame and
	// place given back after), macOS's full-screen space (toggleFullScreen:);
	// in the browser, on Android and iOS nothing (see immersive)
	public var fullscreen(get, set):Bool;

	function get_fullscreen():Bool
		return
			closed ? false :
			#if (!helder.os || helder.headless) HEADLESS ? headless().fullscreen : #end
			Platform.apple() >= 1 ? false :
			#if (!helder.os || helder.os == "macos") Platform.os() == 1 ? mac().isFullscreen() : #end
			#if (!helder.os || helder.os == "windows") Platform.os() == 2 ? win().fullscreen : #end
			Platform.os() == 3 ? false :
			Platform.target() >= 9 ? false :
			#if (!helder.os || helder.os == "linux") (Std.isOfType(native, WaylandWindow) ? wayland().fullscreen : x11().fullscreen) #else false #end;

	function set_fullscreen(on:Bool):Bool {
		if (closed || on == fullscreen) return on;
		#if (!helder.os || helder.headless) if (HEADLESS) headless().fullscreen = on else #end
		if (Platform.apple() >= 1) {} else
		#if (!helder.os || helder.os == "macos") if (Platform.os() == 1) mac().setFullscreen(on) else #end
		#if (!helder.os || helder.os == "windows") if (Platform.os() == 2) win().setFullscreen(on) else #end
		if (Platform.os() == 3) {} else
		if (Platform.target() >= 9) {} else
		#if (!helder.os || helder.os == "linux") (Std.isOfType(native, WaylandWindow) ? wayland().setFullscreen(on) : x11().setFullscreen(on)); #else {} #end
		return on;
	}

	// where its content's top left is on the screen, in points from the
	// screen's top left (pixels on X11; macOS: the main screen's); null where
	// a window has no place of its own (the browser, phones)
	public function position():Null<{x:Int, y:Int}>
		return
			closed ? null :
			#if (!helder.os || helder.headless) HEADLESS ? {x: headless().x, y: headless().y} : #end
			Platform.apple() >= 1 ? null :
			#if (!helder.os || helder.os == "macos") Platform.os() == 1 ? mac().position() : #end
			#if (!helder.os || helder.os == "windows") Platform.os() == 2 ? win().position() : #end
			Platform.os() == 3 ? null :
			Platform.target() >= 9 ? null :
			#if (!helder.os || helder.os == "linux") (Std.isOfType(native, WaylandWindow) ? wayland().position() : x11().position()) #else null #end;

	// its content's top left moved to x, y (as position: a place it had, kept
	// across runs)
	public function moveTo(x:Int, y:Int) {
		if (closed) return;
		#if (!helder.os || helder.headless)
		if (HEADLESS) {
			headless().x = x;
			headless().y = y;
		} else
		#end
		if (Platform.apple() >= 1) {} else
		#if (!helder.os || helder.os == "macos") if (Platform.os() == 1) mac().moveTo(x, y) else #end
		#if (!helder.os || helder.os == "windows") if (Platform.os() == 2) win().moveTo(x, y) else #end
		if (Platform.os() == 3) {} else
		if (Platform.target() >= 9) {} else
		#if (!helder.os || helder.os == "linux") (Std.isOfType(native, WaylandWindow) ? wayland().moveTo(x, y) : x11().moveTo(x, y)); #else {} #end
	}

	// brought to the front and given the focus (a second launch handing its
	// file to this one): X11's _NET_ACTIVE_WINDOW, Windows'
	// SetForegroundWindow, macOS's makeKeyAndOrderFront: and the app activated
	public function raise() {
		if (closed || HEADLESS) return;
		if (Platform.apple() >= 1) {} else
		#if (!helder.os || helder.os == "macos") if (Platform.os() == 1) mac().raise() else #end
		#if (!helder.os || helder.os == "windows") if (Platform.os() == 2) win().raise() else #end
		if (Platform.os() == 3) {} else
		if (Platform.target() >= 9) {} else
		#if (!helder.os || helder.os == "linux") (Std.isOfType(native, WaylandWindow) ? wayland().raise() : x11().raise()); #else {} #end
	}

	@:typescript public function close() {
		if (closed) return;
		closed = true;
		if (HEADLESS) {} else
		#if (!helder.os || helder.os == "ios") if (Platform.apple() >= 1) ios().destroy() else #end
		#if (!helder.os || helder.os == "macos") if (Platform.os() == 1) mac().destroy() else #end
		#if (!helder.os || helder.os == "windows") if (Platform.os() == 2) win().destroy() else #end
		#if (!helder.os || helder.os == "web") if (Platform.os() == 3) web().destroy() else #end
		#if (!helder.os || helder.os == "android") if (Platform.target() >= 9) android().destroy() else #end
		#if (!helder.os || helder.os == "linux") (Std.isOfType(native, WaylandWindow) ? wayland().destroy() : x11().destroy()); #else {} #end
		App.windows.remove(this);
	}
}
