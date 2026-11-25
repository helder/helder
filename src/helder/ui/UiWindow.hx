package helder.ui;

import helder.os.DragOperation;
#if (hxmc.target == "wasm32-wasi")
// (the browser's: the program's frames on the page's layers alone)
import helder.ui.layers.web.Compositor as Compositor;
#else
import helder.ui.layers.Compositor;
#end
import helder.ui.platform.*;
import helder.gfx.*;
import helder.ui.Color;
import helder.os.App;
import helder.os.Event as OsEvent;
import helder.os.TitleBar;
import helder.ui.*;
import hxmc.Platform;
import hxmc.unsafe.*;
import helder.ui.view.UiView;
import helder.view.graph.Graph;
import helder.view.Render;
import helder.view.RootView;

// <Surface>'s props (UiWindow.Surface)
typedef SurfaceProps = {
	// the window's title, its size in points (on the web without a size: the
	// page filled, or the canvas the page gives, at the size its styles make;
	// natively 800 x 600), the ui's theme and background: values or reactive
	// (a signal, a memo, a hole that reads: Read), followed
	?title:helder.view.graph.Read<String>,
	?width:helder.view.graph.Read<Int>,
	?height:helder.view.graph.Read<Int>,
	?theme:helder.view.graph.Read<Dynamic>,
	// (a first value not opaque, "transparent" or a colour's alpha: a
	// transparent window, what is behind it seen through: Window's)
	?background:helder.view.graph.Read<Dynamic>,
	// the system's material behind the window ("blur", "mica", "glass":
	// helder.os's Backdrop, where the system has it), seen through a clear or
	// half-clear background; one makes the window transparent
	?backdrop:helder.view.graph.Read<String>,
	// a transparent window's clicks passing through what it doesn't draw
	// (default true: UiWindow.clickThrough; pointer-events="none" on a
	// node lets them through it too); false: it takes them everywhere
	?clickThrough:Bool,
	// dark or light (default: the system's appearance, UiWindow.dark)
	?dark:helder.view.graph.Read<Bool>,
	// the window closed by its user (default: closed)
	?onClose:Void->Void,
	// files dropped on the window (helder.os's Drop: their paths, where, in points)
	?onDrop:(files:Array<String>, x:Float, y:Float) -> Void,
	// the UiWindow, once made
	?ref:UiWindow->Void,
	// its frames multisampled, 4 samples a pixel (default true; false: one)
	?antialias:Bool,
	// "inset": the content under the title bar (helder.os's TitleBar), the
	// window's buttons in its layout (WindowControls), dragged by its
	// drag-region nodes, env(titlebar-area-*) its free area; "none": no
	// title bar nor frame (its drag regions still move it); default the system's
	?titlebar:String,
	// over every other window (helder.os's Window.onTop)
	?onTop:helder.view.graph.Read<Bool>,
	// false: out of the task bar and the window switcher (Window.taskbar)
	?taskbar:helder.view.graph.Read<Bool>,
	// helder.text's own engine's font smoothing in this window: "on" (as
	// macOS draws by default) or "off" ("antialiased", as CSS's
	// -webkit-font-smoothing); default the app's (helder.text.Shaping.smoothing)
	?fontSmoothing:helder.view.graph.Read<String>,
	// "native": the platform's own scrolling drives the scrollers where it
	// has it (iOS's UIScrollView, the browser's: their physics, bounce,
	// indicators; Android's fling, VelocityTracker and OverScroller; macOS's
	// trackpad gestures and momentum, stretching at the ends, its overlay
	// scrollbars);
	// "helder": helder's own scrolling everywhere; default UiWindow.scrolling's
	?scrolling:String,
	// macOS's scrollbars: "system" (default: System Settings' Show scroll
	// bars), "overlay" (shown while scrolling, over the content) or "always"
	?scrollbars:String,
	?children:UiView
};

// A window showing a UI tree drawn with the GPU: an helder.os Window, its
// gfx Device, a helder.ui.draw.Renderer and the Ui (root: the tree's root node, in the
// window's points). The window's events become the Ui's (pointer, wheel,
// keys, text); a frame lays the tree out and draws it, when there is
// something new to draw (needsFrame: the Ui asked for one, the window was
// resized or lost its pixels). run() is the app loop for every UiWindow
// open, which sleeps while none has a frame to draw. In the browser each
// frame's accessibility tree goes to the mirror in the canvas (helder.ui.access.web.Access:
// load src/helder/ui/imports.mjs), on macOS to NSAccessibility (helder.ui.access.apple.MacAccess), on
// iOS to UIAccessibility (helder.ui.access.apple.IosAccess), on Android to its AccessibilityNodeProvider (helder.ui.access.android.Access),
// on Windows to UI Automation (helder.ui.access.windows.Access), on Linux to AT-SPI (helder.ui.access.linux.Access),
// and the actions asked for come back.
//
// In markup (helder.view) <Surface> is the root ui draws into: a UiWindow,
// its children ui's markup rendered into its root; several make several
// windows; run(content) opens them (Render.open) and runs the loop:
//
//   UiWindow.run(<Surface title="Todo" width={480} height={560} theme={sheet}>
//     <Todo/>
//   </Surface>);
//
// In a page's markup (helder.web's DOM or static renderer) a <Surface> is
// helder.web's: a canvas running a wasm program whose root is this one.
@:hxmc.unsafe(gc)
class UiWindow {
	public final window:helder.os.Window;
	// (null in a headless run drawn on the CPU: soft; none in a -D helder.soft
	// build, whose GPU code is not linked)
	#if !helder.soft
	public var device(default, null):Device;
	public var renderer(default, null):helder.ui.draw.Renderer;
	#end
	#if (helder.headless || helder.soft)
	// the CPU's canvas where it draws a headless run or a -D helder.soft
	// window (helder.ui.draw.soft: no GPU linked; HELDER_SOFT=1; or no GPU
	// device to be made), else null
	@:noCompletion public var soft(default, null):Null<helder.ui.draw.soft.SoftCanvas> = null;
	#end
	// its pixels a point (the renderer's scale), from its first frame
	public var scale(default, null) = 1.0;
	public final ui:Ui;
	public var background:Color = Color.rgb(0xF4F4F5);
	public var onClose:Null<Void->Void>;
	// files dropped on the window: their paths, where (points)
	public var onDrop:Null<(files:Array<String>, x:Float, y:Float) -> Void>;
	// after each frame is drawn and presented
	public var onFrame:Null<Void->Void>;
	// when set, the next frame's pixels are read into it before they are
	// presented (RGBA8, rows top to bottom: tests and screenshots)
	@:noCompletion public var capture:Null<haxe.io.Bytes>;

	// how long the loop sleeps at most with nothing to draw (seconds): what
	// changes the UI from outside its events shows within it
	@:noCompletion public static var idleWait = 0.1;
	// whether the system's appearance is dark (App.prefersDark), asked again
	// every second while the loop runs; each window's Ui.dark follows it
	@:typescript public static final dark:helder.view.graph.Signal<Bool> = Graph.signalOf(App.prefersDark(), {ownedWrite: true});
	static var darkAsked = 0.0;

	static final open:Array<UiWindow> = [];
	// the last frame drawn: its size and scale (a change needs a frame)
	var redraw = true;
	var drawnW = 0;
	var drawnH = 0;
	var drawnScale = 0.0;
	// the tree sent to the browser's mirror last
	var access:Null<helder.ui.access.AccessTree>;
	// macOS's adapter (a helder.ui.access.apple.MacAccess; Any: the other targets never reach its type)
	var macAccess:Any = null;
	// Windows' (a helder.ui.access.windows.Access)
	var winAccess:Any = null;
	// Linux's (a helder.ui.access.linux.Access)
	var linuxAccess:Any = null;
	// iOS's (an helder.ui.access.apple.IosAccess)
	var iosAccess:Any = null;
	// Android's (an helder.ui.access.android.Access)
	var androidAccess:Any = null;
	// iOS's scroll views (an helder.ui.platform.apple.IosScroll), the browser's (a helder.ui.platform.web.Scroll)
	var iosScroll:Any = null;
	var webScroll:Any = null;
	// the platform's scroll views drive the scrollers of the windows made
	// (Ui.nativeScroll, where the platform has them: iOS, the browser; Android's
	// fling and stretch, helder.os.android.Fling and Stretch); false: helder's
	// own scrolling (a Surface's scrolling prop sets a window's)
	public static var scrolling = true;
	// macOS's scrollbars: "system" (System Settings' Show scroll bars:
	// overlay ones that show while scrolling, unless set to always or, by
	// default, while a mouse is connected), "overlay" or "always" (a Surface's
	// scrollbars prop sets a window's)
	public static var scrollbars = "system";
	var bars = scrollbars;
	// the text input area last given to the window ("": off)
	var typing = "";
	final pass:PassDesc = {colors: [{load: Clear, clear: new helder.gfx.Color(1, 1, 1)}]};
	var buttons = 0;
	// (whether its layers are drawn from tiles: helder.ui.draw.Renderer.tiles, but for a frame read back)
	var tiled = false;
	// (HELDER_DAMAGE: "full" draws each frame whole, "flash" shows what each frame drew: helder.ui.draw.Renderer.keep)
	static final damage = Sys.getEnv("HELDER_DAMAGE") ?? "";

	// (antialias: the device's frames multisampled, 4 samples a pixel, where
	// the GPU has them; transparent: helder.os's, the background's alpha
	// showing what is behind the window)
	public function new(title:String, width:Int, height:Int, ?text:TextEngine, antialias = true, titlebar:helder.os.TitleBar = Standard,
			transparent = false) {
		window = new helder.os.Window(title, width, height, titlebar, transparent);
		// (Android: text fields get the soft keyboard and the input method)
		#if (!helder.os || helder.os == "android") if (Platform.target() >= 9) helder.os.android.TextInput.enable(); #end
		#if (helder.headless || helder.soft)
		if (helder.ui.draw.soft.SoftCanvas.wanted() #if !helder.soft || (device = gpu(window.surface, antialias)) == null #end) {
			soft = new helder.ui.draw.soft.SoftCanvas();
			soft.groups = true;
			soft.steps = true;
			// (a window's frame kept, what changed drawn and shown: helder.os.Blit)
			#if !helder.headless
			soft.keep = true;
			#end
		} else
		#end
		{
			#if !helder.soft
			// (Windows: the swap chain made for DirectComposition where the window's layers will be the system's)
			#if ((!helder.os || helder.os == "windows") && !helder.headless && hxmc.target != "wasm32-wasi")
			if (Platform.os() == 2) helder.gfx.d3d11.D3D11Backend.compose = helder.ui.layers.windows.Layers.asked();
			#end
			// (the browser's layers: the window's canvas of premultiplied alpha, its layers' pixels read from it)
			#if ((!helder.os || helder.os == "web") && !helder.headless)
			if (Platform.os() == 3 && helder.ui.layers.web.Layers.wanted()) helder.ui.layers.web.Layers.transparent(window.surface.handle.toI64().toInt());
			#end
			#if !helder.headless device = Device.create(window.surface, {antialias: antialias, thread: true}); #end
			renderer = new helder.ui.draw.Renderer(device);
			renderer.groups = true;
			renderer.steps = true;
			#end
		}
		if (open.length == 0 && helder.os.App.trims.indexOf(trimAll) < 0) helder.os.App.trims.push(trimAll);
		// (its layers from their tiles where it is a window of its own: not
		// headless, nor X11's, nor a browser's canvas, whose frames are
		// screenshots and golden images, drawn as the reference draws them)
		#if !helder.headless
		var k = window.surface.kind;
		tiled = k != helder.os.Surface.SurfaceKind.Headless && k != helder.os.Surface.SurfaceKind.X11 && k != helder.os.Surface.SurfaceKind.Canvas;
		#end
		ui = new Ui(text == null ? new helder.ui.draw.DrawText() : text, width, height);
		ui.clipboard = new SystemClipboard(window);
		ui.window = new OsWindow(this);
		// (an inset title bar: a press's answer the ui's, its drag regions and window buttons)
		if (titlebar != Standard) window.titlebarAt = (x, y) -> ui.titleHit(x / scale, y / scale);
		ui.dark = dark.peek();
		nativeScroll(scrolling);
		// (a touch drag the program's where it scrolls something: the page's otherwise)
		window.scrollsAt = (x, y, dx, dy) -> ui.scrollsAt(x / scale, y / scale, dx / scale, dy / scale);
		// (headless: no window to put a system's views over, its menus and fields drawn)
		#if !helder.headless
		// (the browser's own views: native text editors over the canvas; Windows':
		// EDIT controls over the window; iOS's: UITextFields and UITextViews over
		// the view; macOS': NSTextFields over the window)
		#if (!helder.os || helder.os == "web") if (Platform.os() == 3) ui.platform = WebMirror.views(window.surface.handle.toI64().toInt()) else #end
		#if (!helder.os || helder.os == "windows") if (Platform.os() == 2) ui.platform = new helder.ui.platform.windows.Views(window.surface.handle, ui, () -> scale) else #end
		#if (!helder.os || helder.os == "ios") if (Platform.apple() >= 1) ui.platform = new helder.ui.platform.apple.IosViews(window.surface.handle, ui) else #end
		#if (!helder.os || helder.os == "macos") if (Platform.os() == 1) ui.platform = new helder.ui.platform.apple.MacViews(window.surface.handle, ui) else #end
		{};
		#end
		open.push(this);
		// (the size class is the first window's: a second one, an inspector's, leaves it)
		if (open[0] != this) open[0].ui.claim();
		#if helder.headless
		// (a headless run: the ui's events and clock the run's virtual time, the first window's nodes its tree)
		Ui.now = () -> helder.async.Time.now;
		var run = helder.os.headless.Headless.run;
		Clock.reducedMotion = run.reducedMotion;
		if (run.inspector == null) run.inspector = new helder.ui.draw.UiInspector(ui);
		#end
		// (the window's standard actions: closed as by its close button, fullscreen; Quit: every window asked)
		ui.on(helder.ui.actions.Actions.StandardAction, a -> switch a {
			case CloseWindow:
				handle(closeEvent());
				true;
			case ToggleFullscreen:
				window.fullscreen = !window.fullscreen;
				true;
			case Quit:
				for (w in open.copy())
					w.handle(closeEvent());
				true;
			case _: false;
		}, a -> switch a {
			case CloseWindow | Quit: Enabled;
			case ToggleFullscreen: window.fullscreen ? Checked : Unchecked;
			case _: Unhandled;
		});
		#if hxmc.dev_host
		// (helder dev's host, at a hand-over: what the system keeps of this build's code given back)
		helder.dev.Hot.onDispose(handOver);
		#end
		// (the browser as the compositor: the window's layers canvases of the page, its scrollers' content in their scroll views)
		#if ((!helder.os || helder.os == "web") && !helder.headless && !helder.soft)
		if (Platform.os() == 3 && helder.ui.layers.web.Layers.wanted() && ui.nativeScroll) {
			var c = new Compositor(device);
			if (c.layers != null) {
				compositor = c;
				ui.layered = helder.ui.layers.LayerSplit.slots();
				(cast c.layers : helder.ui.layers.web.Layers).viewOf = n -> webScroll == null ? null : (cast webScroll : helder.ui.platform.web.Scroll).viewOf(n);
			}
		}
		#end
		#if (!helder.headless && !helder.soft && hxmc.target != "wasm32-wasi")
		// (the compositor: scrolling at the display's rate while the program is busy)
		// (iOS's own scroll views: their offsets to it as they move, helder.ui.platform.apple.IosScroll)
		if (Compositor.wanted(device) && (!ui.nativeScroll || Platform.apple() >= 1)) {
			var c = new Compositor(device);
			if (c.start()) {
				compositor = c;
				#if (!helder.os || helder.os == "macos" || helder.os == "ios" || helder.os == "android" || helder.os == "windows" || helder.os == "linux")
				ui.layered = c.layers != null && helder.ui.layers.LayerSplit.slots();
				#end
				window.route = c.route;
				ui.onAnswer = c.answer;
				if (helder.os.App.beforeEvents.indexOf(drainAll) < 0) helder.os.App.beforeEvents.push(drainAll);
			}
		}
		#end
	}

	#if (!helder.headless && !helder.soft)
	// the window's compositor (null: none, scrolling the program's alone)
	@:noCompletion public var compositor(default, null):Null<Compositor> = null;

	// (at each turn's start, a window's last frame presented: until its
	// next is taken without queueing (Device.waitFrame), then what the
	// compositors scrolled taken, the input after it the frame's)
	static function drainAll()
		for (w in open) {
			if (w.presents) {
				w.presents = false;
				w.device.waitFrame();
			}
			if (w.compositor != null) w.compositor.drain(w.ui);
		}

	var presents = false;
	#end

	#if hxmc.dev_host
	// (handed over: the window the host's, not closed with its <Surface>'s owner after it)
	var handedOver = false;

	// the native views and the accessibility adapters released (the window
	// and the GPU device stay, the host's): their callbacks are this build's
	// code, which the host unloads; the next build makes its own
	function handOver() {
		handedOver = true;
		#if (!helder.os || helder.os == "ios")
		if (Platform.apple() >= 1) {
			if (iosAccess != null) (cast iosAccess : helder.ui.access.apple.IosAccess).dispose();
			if (iosScroll != null) (cast iosScroll : helder.ui.platform.apple.IosScroll).dispose();
			if (ui.platform != null) (cast ui.platform : helder.ui.platform.apple.IosViews).dispose();
		}
		#end
		#if (!helder.os || helder.os == "macos")
		if (Platform.os() == 1 && Platform.apple() < 1) {
			if (macAccess != null) (cast macAccess : helder.ui.access.apple.MacAccess).dispose();
			if (ui.platform != null) (cast ui.platform : helder.ui.platform.apple.MacViews).dispose();
		}
		#end
		#if (!helder.os || helder.os == "windows")
		if (Platform.os() == 2) {
			if (winAccess != null) (cast winAccess : helder.ui.access.windows.Access).dispose();
			if (ui.platform != null) (cast ui.platform : helder.ui.platform.windows.Views).dispose();
		}
		#end
		macAccess = winAccess = iosAccess = iosScroll = null;
	}
	#end

	// the platform's scroll views on or off for this window (where it has them)
	@:noCompletion public function nativeScroll(on:Bool) {
		#if !helder.headless
		ui.nativeScroll = on && (Platform.apple() >= 1 || Platform.os() == 3);
		// (macOS: no scroll views under the tree; its trackpad's gestures and momentum taken as its own views take them, Trackpad's, and its overlay scrollbars)
		// (Linux's touchpads, Wayland's: GTK's kinetic glide)
		if (Platform.os() == 0) {
			if (Platform.target() < 9) ui.kinetic = on;
		}
		// (nested: only a constant condition drops the branch, its AppKit calls with it)
		#if (!helder.os || helder.os == "macos")
		if (Platform.os() == 1) {
			if (Platform.apple() < 1) {
				ui.elastic = on;
				ui.overlayBars = on && (bars == "overlay" || bars == "system" && App.overlayScrollbars());
				ui.scrollbarLook = !on ? Plain : ui.overlayBars ? MacOverlay : MacLegacy;
				// (macOS's scrollers drawn by AppKit, for every appearance and macOS)
				if (on && ui.scrollbarArt == null) ui.scrollbarArt = new helder.ui.platform.apple.MacScrollbarArt();
			}
		}
		#end
		// (Android: no scroll views under the tree; helder's drag, Android's fling and its stretch at the ends)
		#if (!helder.os || helder.os == "android")
		if (Platform.target() >= 9) {
			@:privateAccess ui.touchScroll.g = on ? new helder.os.android.Fling() : new helder.os.Glide();
			ui.stretch = on;
		}
		#end
		ui.requestFrame();
		#end
	}

	// the scrollers' platform views kept in step (after a frame)
	function syncScroll() {
		#if (!helder.os || helder.os == "web")
		if (Platform.os() == 3) {
			if (webScroll == null) {
				if (!ui.nativeScroll) return;
				webScroll = new helder.ui.platform.web.Scroll(window.surface.handle.toI64().toInt(), ui);
			}
			(cast webScroll : helder.ui.platform.web.Scroll).update();
		}
		#end
		#if (!helder.os || helder.os == "ios")
		if (Platform.apple() >= 1) {
			if (iosScroll == null) {
				if (!ui.nativeScroll) return;
				iosScroll = new helder.ui.platform.apple.IosScroll(window, ui);
				#if (!helder.headless && !helder.soft)
				(cast iosScroll : helder.ui.platform.apple.IosScroll).compositor = compositor;
				#end
			}
			(cast iosScroll : helder.ui.platform.apple.IosScroll).update();
		}
		#end
	}

	// macOS's scrollbars for this window: "system", "overlay" or "always" (UiWindow.scrollbars)
	@:noCompletion public function scrollbarStyle(style:String) {
		bars = style;
		nativeScroll(ui.nativeScroll || ui.elastic);
	}

	public var root(get, never):Node;

	inline function get_root()
		return ui.root;

	// there is something new to draw
	public function needsFrame():Bool
		return redraw || ui.needsFrame || Clock.active || ScreenContext.main.nextTimer() <= #if helder.headless helder.async.Time.now #else haxe.Timer.stamp() #end || capture != null || window.width != drawnW || window.height != drawnH || window.scale != drawnScale
			|| (Ui.accessEpoch != accessSent && accessListening()) || accessPending() || mirrorMoves();

	// (the compositor's glides and springs: the program's frames follow them, as they would its own)
	inline function mirrorMoves():Bool {
		#if (!helder.headless && !helder.soft)
		return compositor != null && compositor.moving();
		#else
		return false;
		#end
	}

	// (a test's clock, Ui.now's too: frames of the same steps the same in two runs)
	@:noCompletion public static var clock:Null<Void->Float> = null;

	// draws a frame (the loop calls it when needsFrame): the clock ticked
	// first (now: what the frame's events started, Ui.now's, is not after
	// it, as the vsync's time App.frame.time may be)
	public function frame() {
		Clock.tick(clock != null ? clock() : #if helder.headless helder.async.Time.now #else haxe.Timer.stamp() #end);
		// (laid out at the surface's size: the device's follows it only at
		// beginFrame, so that a single resize, a maximise's, laid out at the
		// last size would be drawn into the new one and stay so)
		var s = window.scale, w = window.width, h = window.height;
		scale = w / Math.max(1, Math.round(w / s));
		#if !helder.soft if (renderer != null) renderer.scale = scale; #end
		ui.resize(w / scale, h / scale);
		ui.scale = scale;
		keyboard();
		safeArea();
		titlebarArea();
		ui.update();
		var at = ui.controlsAt;
		if (at != null && at.ui == ui) ui.window.placeControls(at.absX, at.absY);
		// (the system's layers turned off: the window's own frame, now)
		#if (!helder.headless && !helder.soft)
		if (compositor != null && compositor.layers != null && compositor.layers.redraw) redraw = true;
		#end
		// (the clock ticked, nothing changed: the last frame stands, as drawn;
		// an animation off screen, a timer's wait)
		if (!redraw && !ui.needsFrame && capture == null && w == drawnW && h == drawnH && s == drawnScale) {
			updateTextInput();
			// (what assistive technology reads changed, nothing drawn: a semantics' state)
			if ((Ui.accessEpoch != accessSent && accessListening()) || accessPending()) sendAccess();
			return;
		}
		// (the system's layers drawn from the compositor's state after the frame, but for a frame read back)
		#if (helder.headless || helder.soft)
		if (soft != null) return softFrame(w, h, s);
		#end
		#if !helder.soft
		var planes = false;
		#if (!helder.headless && !helder.soft)
		if (compositor != null) {
			planes = compositor.planes() && capture == null;
			compositor.quiet(planes);
		}
		#end
		var enc = device.beginFrame();
		if (enc == null) return;
		redraw = false;
		drawnW = w;
		drawnH = h;
		drawnScale = s;
		// (premultiplied, as every pixel drawn; opaque where the window is)
		var c = pass.colors[0].clear, bg = shown();
		@:privateAccess {
			var a = bg.a / 255;
			c.r = bg.r / 255 * a;
			c.g = bg.g / 255 * a;
			c.b = bg.b / 255 * a;
			c.a = a;
		}
		// (painted first: the passes a texture drawn needs, a <Scene>'s, recorded before the frame's)
		renderer.tiles = tiled && capture == null;
		// (a see-through background drawn whole each frame: a damaged
		// rectangle is cleared by its background drawn over what was there)
		renderer.keep = renderer.tiles && damage != "full" && !planes && bg.a == 255;
		renderer.flash = damage == "flash";
		renderer.background = bg;
		renderer.begin(device.width, device.height);
		#if (!helder.headless && !helder.soft)
		var c = capture == null ? compositor : null;
		if (c != null) c.begin(renderer);
		#end
		ui.paint(renderer);
		if (window.transparent && clickThrough) inputs();
		renderer.prepare(enc);
		if (planes) renderer.upload() else {
			enc.beginPass(pass);
			renderer.end(enc);
			enc.endPass();
		}
		// (glyphs drawn at a step's size while a scale moved: drawn at theirs next)
		if (renderer.again) redraw = true;
		if (capture != null) {
			device.readPixels(capture);
			capture = null;
		}
		// (what the frame kept changed, told the system: none, a pixel's worth; all of it after the compositor's)
		var whole = renderer.drawn >= device.width * device.height;
		#if (!helder.headless && !helder.soft)
		if (compositor != null && compositor.drewSince) whole = true;
		if (c != null) c.end(ui, renderer);
		#end
		if (renderer.keep) device.damaged(whole ? null : renderer.regions.length > 0 ? renderer.regions : [0, 0, 1, 1]);
		device.endFrame();
		#if (!helder.headless && !helder.soft)
		presents = !planes;
		if (compositor != null && capture == null) compositor.present(planes);
		#end
		updateTextInput();
		sendAccess();
		syncScroll();
		// (presented first: what it asks of the window comes after the frame,
		// as a Wayland compositor must see the commit of the size it
		// configured before a fullscreen left)
		if (onFrame != null) {
			device.settle();
			onFrame();
		}
		#end
	}

	// a transparent window's clicks pass through what it doesn't draw: it
	// takes the pointer over the nodes that draw something (a background,
	// a border, a shadow, text, an image, a control) and that the pointer
	// finds (pointer-events not none), elsewhere what is behind it gets
	// them (helder.os's Window.input, given when they change); false: the
	// window's input left as it is
	public var clickThrough = true;
	var taken = "";

	function inputs() {
		var out:Array<Int> = [];
		boxes(ui.root, 0, 0, out);
		boxes(ui.overlay, 0, 0, out);
		// (many: one box around them all)
		if (out.length > 4 * 128) {
			var x0 = 1 << 30, y0 = 1 << 30, x1 = -x0, y1 = -y0, i = 0;
			while (i < out.length) {
				x0 = Std.int(Math.min(x0, out[i]));
				y0 = Std.int(Math.min(y0, out[i + 1]));
				x1 = Std.int(Math.max(x1, out[i] + out[i + 2]));
				y1 = Std.int(Math.max(y1, out[i + 1] + out[i + 3]));
				i += 4;
			}
			out = [x0, y0, x1 - x0, y1 - y0];
		}
		var key = out.join(" ");
		if (key == taken) return;
		taken = key;
		window.input(out);
	}

	// (n's box where it draws and the pointer finds it, else its children's;
	// dx, dy: the scrolls it is under, in points)
	function boxes(n:Node, dx:Float, dy:Float, out:Array<Int>) {
		if (n.style.display == None || !n.visible()) return;
		var st = n.style;
		var draws = Type.getClass(n) != Node || st.background.a > 0 || st.background.isToken || st.borderWidth > 0 || st.backgroundImage != null
			|| st.shadow != null;
		if (draws && n.hittable()) {
			var k = scale, x0 = Math.floor((n.absX - dx) * k), y0 = Math.floor((n.absY - dy) * k);
			out.push(x0);
			out.push(y0);
			out.push(Math.ceil((n.absX - dx + n.width) * k) - x0);
			out.push(Math.ceil((n.absY - dy + n.height) * k) - y0);
			return;
		}
		if (st.overflow == Scroll) {
			dx += n.scrollX;
			dy += n.scrollY;
		}
		for (c in n.children)
			boxes(c, dx, dy, out);
	}

	// (the background drawn: its alpha where the window is transparent)
	function shown():Color
		return window.transparent ? background : Color.rgb((background : Int) & 0xFFFFFF);

	// (the glyph atlas it draws with: the renderer's, the CPU's canvas')
	function atlas():helder.text.GlyphAtlas {
		#if (helder.headless || helder.soft)
		if (soft != null) return soft.atlas;
		#end
		#if helder.soft
		throw "UiWindow: no canvas";
		#else
		return renderer.atlas;
		#end
	}

	#if (helder.headless || helder.soft)
	// (a device, where one can be made: none, the CPU's canvas draws)
	#if !helder.soft
	static function gpu(surface:helder.os.Surface, antialias:Bool):Null<Device>
		return try Device.create(surface, {antialias: antialias, thread: true}) catch (e:Dynamic) {
			Sys.println('helder: no GPU device ($e): drawn on the CPU');
			null;
		}
	#end

	// (frame's on the CPU: the Ui painted into the soft canvas, its pixels the headless run's)
	function softFrame(w:Int, h:Int, s:Float) {
		redraw = false;
		drawnW = w;
		drawnH = h;
		drawnScale = s;
		var c = soft;
		c.scale = scale;
		c.begin(w, h, shown());
		ui.paint(c);
		if (window.transparent && clickThrough) inputs();
		if (c.again) redraw = true;
		if (capture != null) {
			c.readPixels(capture);
			capture = null;
		}
		#if helder.headless
		helder.os.headless.Headless.run.present(window.surface, w, h, c.readPixels);
		#else
		c.present(window.surface);
		#end
		updateTextInput();
		sendAccess();
		syncScroll();
		if (onFrame != null) onFrame();
	}
	#end

	// the window's safe area in UI pixels: the Ui's, and markup's
	// env(safe-area-inset-*) from the first window's (SafeArea), when it changed
	function safeArea() {
		var k = scale, s = ui.safeArea;
		var t = window.safeTop / k, r = window.safeRight / k, b = window.safeBottom / k, l = window.safeLeft / k;
		if (s.top != t || s.right != r || s.bottom != b || s.left != l) {
			ui.safeArea = new helder.ui.Edges(t, r, b, l);
			ui.requestFrame();
		}
		if (open[0] == this) helder.ui.SafeArea.set(t, r, b, l);
	}

	// the soft keyboard's height over the window in UI pixels, and its animation's seconds
	function keyboard() {
		var h = window.keyboard.peek() * window.scale / scale;
		if (open[0] == this && helder.ui.SafeArea.keyboard.peek() != h) helder.ui.SafeArea.keyboard(h);
		if (h == ui.keyboard) return;
		ui.keyboard = h;
		ui.keyboardDuration = window.keyboardDuration;
		ui.requestFrame();
	}

	// an inset title bar's free area in UI pixels (env(titlebar-area-*), the first window's), when it changed
	var titlebarShown:Null<helder.ui.TitlebarArea> = null;

	function titlebarArea() {
		if (open[0] != this || window.titlebar != Inset) return;
		var a = window.titlebarArea(), k = scale;
		// (a headless run standing in for the web page, helder.run's screenshot: no title bar, as a browser has it)
		#if helder.headless if (Sys.getEnv("HELDER_CONTROLS") == "none") a = null; #end
		var t = a == null ? null : new helder.ui.TitlebarArea(a.x / k, a.y / k, a.width / k, a.height / k);
		if (helder.ui.TitlebarArea.same(t, titlebarShown)) return;
		titlebarShown = t;
		helder.ui.SafeArea.setTitlebar(t);
		ui.requestFrame();
	}

	// the window's text input: on at the focus's caret while it takes text
	// (the input method's place), else off; told when it changes
	function updateTextInput() {
		var a = ui.textInputArea(), k = scale;
		var x = 0, y = 0, w = 0, h = 0;
		if (a != null) {
			x = Math.round(a.x * k);
			y = Math.round(a.y * k);
			w = Math.round(Math.max(1, a.width * k));
			h = Math.round(a.height * k);
		}
		var now = a == null ? "" : '$x,$y,$w,$h';
		if (now == typing) {
			sendTextContext();
			return;
		}
		if (a != null) {
			var k = ui.textKind() ?? helder.os.TextKind.PLAIN;
			if (!k.equals(kind)) window.textKind(kind = k);
		}
		if (a == null) {
			window.stopTextInput();
			// (which takes the keyboard's focus back from a native editor that just took it)
			if (ui.focus != null) @:privateAccess ui.focus.refocusNative();
		} else window.startTextInput(x, y, w, h);
		typing = now;
		contextText = null;
		sendTextContext();
	}

	// the text kind last given to the window
	var kind:Null<helder.os.TextKind> = null;
	// the text context last given to the window (null: none since text input began)
	var contextText:Null<String> = null;
	var contextStart = 0;
	var contextEnd = 0;
	var contextKind = 0;

	// the focus's text and selection to the window's input method, when they changed
	function sendTextContext() {
		if (typing == "") return;
		var c = ui.textContext();
		if (c == null) return;
		var kind = (c.multiline ? 1 : 0) | (c.secret ? 2 : 0);
		if (c.text == contextText && c.start == contextStart && c.end == contextEnd && kind == contextKind) return;
		contextText = c.text;
		contextStart = c.start;
		contextEnd = c.end;
		contextKind = kind;
		window.textContext(c.text, c.start, c.end, c.multiline, c.secret);
	}

	// the accessibility tree's epoch last sent (Ui.accessEpoch): a change since is a frame's
	var accessSent = -1;

	// whether an adapter has a client: what it reads changing is then worth a frame
	function accessListening():Bool {
		if (Platform.os() == 3) return access != null;
		#if (!helder.os || helder.os == "ios") if (Platform.apple() >= 1) return iosAccess != null && (cast iosAccess : helder.ui.access.apple.IosAccess).listening(); #end
		#if (!helder.os || helder.os == "macos") if (Platform.os() == 1) return macAccess != null && (cast macAccess : helder.ui.access.apple.MacAccess).listening(); #end
		#if (!helder.os || helder.os == "windows") if (Platform.os() == 2) return winAccess != null && (cast winAccess : helder.ui.access.windows.Access).listening(); #end
		#if ((!helder.os || helder.os == "linux") && !helder.soft) if (Platform.os() == 0 && Platform.target() < 9) return linuxAccess != null && helder.ui.access.linux.Access.listening(); #end
		#if (!helder.os || helder.os == "android") if (Platform.target() >= 9) return androidAccess != null && (cast androidAccess : helder.ui.access.android.Access).listening(); #end
		return false;
	}

	// whether an adapter was asked for a tree it has not had (Android's: its
	// provider answers on another thread, from what the last frame published)
	function accessPending():Bool {
		#if (!helder.os || helder.os == "android") if (Platform.target() >= 9) return androidAccess != null && helder.ui.access.android.Access.pending; #end
		return false;
	}

	// the tree's changes to the browser's mirror or to macOS (the guards inside: an
	// instance method is compiled whether called or not, and the browser's
	// imports must stay out of the other targets)
	function sendAccess() {
		accessSent = Ui.accessEpoch;
		#if (!helder.os || helder.os == "web")
		if (Platform.os() == 3) {
			var t = ui.accessTree();
			var json = t.changesJson(access);
			access = t;
			if (json != null) WebMirror.send(window.surface.handle.toI64().toInt(), json);
		}
		#end
		#if (!helder.os || helder.os == "ios")
		if (Platform.apple() >= 1) {
			if (iosAccess == null) iosAccess = new helder.ui.access.apple.IosAccess(window, ui);
			(cast iosAccess : helder.ui.access.apple.IosAccess).update();
		}
		#end
		#if (!helder.os || helder.os == "macos")
		if (Platform.os() == 1 && Platform.apple() < 1) {
			if (macAccess == null) macAccess = new helder.ui.access.apple.MacAccess(window, ui);
			(cast macAccess : helder.ui.access.apple.MacAccess).update();
		}
		#end
		#if (!helder.os || helder.os == "windows")
		if (Platform.os() == 2) {
			if (winAccess == null) winAccess = new helder.ui.access.windows.Access(window, ui);
			(cast winAccess : helder.ui.access.windows.Access).update();
		}
		#end
		// (not Android's: AT-SPI is the Linux desktop's)
		#if ((!helder.os || helder.os == "linux") && !helder.soft)
		if (Platform.os() == 0 && Platform.target() < 9) {
			if (linuxAccess == null) linuxAccess = new helder.ui.access.linux.Access(window, ui);
			(cast linuxAccess : helder.ui.access.linux.Access).update();
		}
		#end
		#if (!helder.os || helder.os == "android")
		if (Platform.target() >= 9) {
			if (androidAccess == null) androidAccess = new helder.ui.access.android.Access(window, ui);
			(cast androidAccess : helder.ui.access.android.Access).update();
		}
		#end
	}

	// the actions assistive technology asked for (the browser's), done
	function pollAccess() {
		#if (!helder.os || helder.os == "web")
		if (Platform.os() == 3) {
			if (access != null) WebMirror.poll(ui);
			if (webScroll != null) (cast webScroll : helder.ui.platform.web.Scroll).poll();
		}
		#end
		#if ((!helder.os || helder.os == "linux") && !helder.soft) if (Platform.os() == 0 && Platform.target() < 9 && linuxAccess != null) helder.ui.access.linux.Access.dispatch(); #end
		#if (!helder.os || helder.os == "android") if (Platform.target() >= 9 && androidAccess != null) helder.ui.access.android.Access.dispatch(); #end
	}

	// the window's cursor: the Ui's
	function updateCursor()
		window.cursor = ui.cursor();

	// one of the window's events
	public function handle(e:OsEvent) {
		var k = scale;
		switch e.kind {
			case Close:
				if (onClose != null) onClose() else close();
			case Resize | Redraw:
				redraw = true;
			case Drop:
				if (onDrop != null) {
					onDrop(e.files.copy(), e.x / k, e.y / k);
					Graph.flush();
				}
			case _:
				UiEvents.deliver(ui, e, k);
		}
		updateCursor();
	}

	static function closeEvent():OsEvent {
		var e = new OsEvent();
		e.kind = Close;
		return e;
	}

	// (the system wants memory back: every window's)
	static function trimAll() {
		#if !helder.soft
		for (w in open)
			if (w.renderer != null) w.renderer.trim();
		#end
	}

	// (once: a <Surface>'s owner closes it too)
	@:typescript public function close() {
		if (open.indexOf(this) < 0) return;
		#if hxmc.dev_host
		if (handedOver) return;
		#end
		// (nested: only a constant condition drops the branch)
		#if (!helder.os || helder.os == "ios")
		if (Platform.apple() >= 1) {
			if (iosAccess != null) (cast iosAccess : helder.ui.access.apple.IosAccess).dispose();
			if (iosScroll != null) (cast iosScroll : helder.ui.platform.apple.IosScroll).dispose();
		}
		#end
		#if (!helder.os || helder.os == "macos") if (Platform.os() == 1 && Platform.apple() < 1 && macAccess != null) (cast macAccess : helder.ui.access.apple.MacAccess).dispose(); #end
		#if (!helder.os || helder.os == "windows") if (Platform.os() == 2 && winAccess != null) (cast winAccess : helder.ui.access.windows.Access).dispose(); #end
		#if ((!helder.os || helder.os == "linux") && !helder.soft) if (Platform.os() == 0 && Platform.target() < 9 && linuxAccess != null) (cast linuxAccess : helder.ui.access.linux.Access).dispose(); #end
		#if (!helder.os || helder.os == "android") if (Platform.target() >= 9 && androidAccess != null) (cast androidAccess : helder.ui.access.android.Access).dispose(); #end
		#if (!helder.headless && !helder.soft)
		if (compositor != null) compositor.dispose();
		compositor = null;
		#end
		// (the device drained first: the render thread done with the window's surface before it goes)
		#if !helder.soft if (device != null) device.dispose(); #end
		window.close();
		open.remove(this);
	}

	// the app loop: every UiWindow's frames and events until the last closes
	// (on the web it returns, the frames going on); content, when given, opened first
	@:typescript public static function run(?content:RootView) {
		if (content != null) Render.open(content);
		App.run(() -> {
			var now = #if helder.headless helder.async.Time.now #else haxe.Timer.stamp() #end;
			if (now - darkAsked > 1) {
				darkAsked = now;
				// (the user's keymap file, read again when it changed: the menus' labels too)
				if (helder.ui.actions.Keymap.global.poll()) for (w in open)
					w.ui.requestFrame();
				// (macOS's "Show scroll bars": overlay or always)
				var overlay = App.overlayScrollbars();
				for (w in open)
					if (w.ui.elastic && w.bars == "system" && w.ui.overlayBars != overlay) {
						w.ui.overlayBars = overlay;
						w.ui.scrollbarLook = overlay ? MacOverlay : MacLegacy;
						w.ui.requestFrame();
					}
				var d = App.prefersDark();
				if (d != dark.peek()) {
					dark(d);
					for (w in open)
						w.ui.dark = d;
				}
			}
			var drew = false;
			for (w in open.copy())
				w.pollAccess();
			for (w in open.copy())
				if (w.needsFrame()) {
					w.frame();
					drew = true;
				}
			// (the frames presented before the next events are taken: their
			// encoding, a window's and the next one's work overlapped, no frame
			// more of latency)
			#if !helder.soft
			for (w in open)
				if (w.device != null) w.device.settle();
			#end
			if (!drew) {
				#if (!helder.headless && !helder.soft)
				for (w in open)
					if (w.compositor != null) w.compositor.rest();
				#end
				App.wait(idleWait);
			}
		}, e -> for (w in open.copy()) if (w.window == e.window) w.handle(e));
	}

	// (a background as Surface takes it: a Color, or a string Color.parse
	// reads, markup's background="#333333", which taken as the Int it is not
	// was 0: transparent black)
	@:allow(helder.ui) static function colour(v:Dynamic):Color
		return Std.isOfType(v, String) ? Color.parse((v : String)) : (cast v : Color);

	// <Surface>: a window (a canvas on the web), its children rendered into its ui's root; closed with its owner
	@:typescript public static function Surface(props:SurfaceProps):RootView {
		var web = Platform.os() == 3;
		var width:Null<Int> = Render.read(props.width), height:Null<Int> = Render.read(props.height);
		var title:Null<String> = Render.read(props.title);
		var bg:Dynamic = Render.read(props.background), backdrop:Null<String> = Render.read(props.backdrop);
		var w = new UiWindow(title ?? "helder", width ?? (web ? 0 : 800), height ?? (web ? 0 : 600), null, props.antialias != false,
			props.titlebar == "inset" ? Inset : props.titlebar == "none" ? helder.os.TitleBar.None : Standard, (bg != null && colour(bg).a < 255) || (backdrop != null && backdrop != "none"));
		// (a backdrop seen through a clear background, unless one is given)
		if (bg == null && backdrop != null && backdrop != "none") w.background = Color.TRANSPARENT;
		if (props.backdrop != null) Graph.renderEffect(() -> (Render.read(props.backdrop) : String), v -> w.window.backdrop = cast v);
		// (each reactive prop followed after its first value)
		follow(props.title, (v:String) -> w.window.title = v);
		follow(props.width, (_:Int) -> resize(w, props));
		follow(props.height, (_:Int) -> resize(w, props));
		if (props.theme != null) Graph.renderEffect(() -> Render.read(props.theme), v -> w.ui.theme = v);
		if (props.background != null) Graph.renderEffect(() -> Render.read(props.background), (v:Dynamic) -> {
			w.background = colour(v);
			w.ui.requestFrame();
		});
		if (props.dark != null) Graph.renderEffect(() -> Render.read(props.dark), v -> w.ui.dark = v);
		if (props.fontSmoothing != null) Graph.renderEffect(() -> (Render.read(props.fontSmoothing) : String), v -> {
			w.atlas().smoothing = helder.text.FontSmoothing.parse(v);
			w.ui.requestFrame();
		});
		if (props.scrolling != null) w.nativeScroll(props.scrolling != "helder");
		if (props.scrollbars != null) w.scrollbarStyle(props.scrollbars);
		if (props.clickThrough == false) w.clickThrough = false;
		if (props.onTop != null) Graph.renderEffect(() -> (Render.read(props.onTop) : Bool), v -> w.window.onTop = v);
		if (props.taskbar != null) Graph.renderEffect(() -> (Render.read(props.taskbar) : Bool), v -> w.window.taskbar = v);
		if (props.onClose != null) w.onClose = props.onClose;
		if (props.onDrop != null) w.onDrop = props.onDrop;
		// (in this owner: what is above the root, contexts, seen inside)
		Render.insert(props.children, w.root, null);
		Graph.onCleanup(w.close);
		if (props.ref != null) props.ref(w);
		return null;
	}

	static function follow<T>(v:Dynamic, set:T->Void) {
		if (!Render.isReactive(v)) return;
		var first = true;
		Graph.renderEffect(() -> (Render.read(v) : T), (x:T) -> {
			if (!first) set(x);
			first = false;
		});
	}

	static function resize(w:UiWindow, props:SurfaceProps) {
		var width:Null<Int> = Render.read(props.width), height:Null<Int> = Render.read(props.height);
		if (width != null && height != null) w.window.resize(width, height);
	}
}

// the window for its Ui's WindowControls (WindowHost)
@:noCompletion
class OsWindow implements WindowHost {
	final w:UiWindow;

	public function new(w:UiWindow)
		this.w = w;

	public function controls():String {
		var win = w.window;
		if (win.titlebar != Inset || win.fullscreen || Platform.os() == 3 || Platform.apple() >= 1 || Platform.target() >= 9) return "none";
		if (Platform.os() == 1) return "system";
		return Platform.os() == 2 ? "windows" : "linux";
	}

	public function systemControls():Null<Bounds> {
		var c = w.window.systemControls(), k = w.scale;
		if (c == null) return null;
		var b = new Bounds();
		b.x = c.x / k;
		b.y = c.y / k;
		b.width = c.width / k;
		b.height = c.height / k;
		return b;
	}

	public function placeControls(x:Float, y:Float)
		w.window.placeControls(Math.round(x * w.scale), Math.round(y * w.scale));

	public function minimize()
		w.window.minimize();

	public function maximized():Bool
		return w.window.maximized;

	public function maximize(on:Bool)
		w.window.maximized = on;

	public function close()
		w.handle(@:privateAccess UiWindow.closeEvent());

	public function dragFiles(paths:Array<String>, image:Null<helder.image.Image>, offsetX:Float, offsetY:Float, allowed:Array<DragOperation>,
		done:DragOperation->Void):Bool
		return w.window.dragFiles(paths, image, offsetX, offsetY, allowed, done);
}

// the system's clipboard (helder.os.Clipboard) for a window's Ui
@:noCompletion
class SystemClipboard implements ClipboardHost {
	final window:helder.os.Window;

	public function new(window:helder.os.Window)
		this.window = window;

	public function write(text:String)
		helder.os.Clipboard.write(window, text);

	public function read(callback:Null<String>->Void)
		helder.os.Clipboard.read(window, callback);
}

// the browser's accessibility mirror (helder.ui.access.web.Access), apart: its imports are
// reached only from the browser's branches
#if (!helder.os || helder.os == "web")
@:hxmc.unsafe(gc)
@:noCompletion
class WebMirror {
	public static function views(canvas:Int):PlatformViews
		return new WebViews(canvas);

	public static function send(canvas:Int, json:String)
		Arena.scoped(a -> helder.ui.access.web.Access.access_update(canvas, a.cstring(json)));

	public static function poll(ui:Ui)
		Arena.scoped(a -> {
			var p:Ptr<Int32> = a.alloc(8);
			while (helder.ui.access.web.Access.access_action(p) != 0)
				ui.accessAction(p[0], p[1]);
		});
}
#end
