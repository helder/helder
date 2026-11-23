package helder.ui;

import helder.ui.platform.*;
import helder.ui.draw.Damage;
import helder.ui.draw.DisplayList;
import helder.ui.draw.Layer;
import helder.ui.draw.TextureCanvas;
import helder.ui.draw.Walk;
import helder.os.PointerType;
import helder.ui.Event;
import helder.ui.gesture.Gesture;
import helder.ui.gesture.Tap;
import helder.ui.gesture.TouchScroll;

// The host of a UI tree: its viewport, its TextEngine, layout (update),
// drawing (paint) and input. A window's loop (helder.ui.draw.Window, or a
// test) feeds it pointer, wheel, key and text events in window pixels and
// calls update and paint when needsFrame. Pointer events go to the topmost
// node under the pointer (Node.hitTest), or while a button is down to the
// node it went down on; key and text events to the focused node; all
// bubble to the ancestors. Clicking a focusable node (or a descendant of
// one) focuses it, Tab and Shift+Tab move the focus through the focusable
// nodes in tree order, the wheel scrolls the nearest Overflow Scroll
// ancestor. A node that scrolls shows a scrollbar's thumb over its content
// on each axis it overflows, dragged to scroll (a click on its track pages);
// the focus moved by the keyboard shows a ring around the focused node (as
// CSS's :focus-visible: a click hides it). Popups (open, close) are
// layers over the tree: children of overlay, a second root laid out,
// drawn and hit after it. The scrolling is Scrolling's, the popups'
// opening, placing and dismissing Popups'.
//
// Fingers and pens (helder.os's pointers but the mouse: their slots as
// ids, 1 to POINTERS - 1) are pointers of their own, each captured by the
// node it went down on (Node.capture moves it, releaseCapture lets it go;
// a node leaving the tree gets PointerCancel), with pointerId,
// pointerType, pressure and isPrimary on their events. Each pointer has
// an arena (helder.ui.gesture.Gesture): the recognisers on the nodes it
// went down in compete for it, the innermost first, and for the first
// finger a drag that scrolls what is under where it started (TouchScroll:
// Wheel events, a glide), last; a recogniser
// that wins it other than a Tap takes the click, and the scroll cancels
// the press (PointerCancel). A press released within the slop of where it
// went down (or twice that, on the node it went down on) clicks. The mouse's presses feed the arena too, its
// clicks as before.
class Ui {
	public final root:Node;
	// the layers above the tree (Popup nodes, the last on top)
	public final overlay:Node;
	// the page's body: the node of slot "body", whose text properties the layers inherit (as a page's popups its body's)
	public var body(default, null):Null<Node> = null;
	public var text:TextEngine;
	public var width(default, null):Float;
	public var height(default, null):Float;
	public var focus(default, null):Null<Node>;
	public var hover(default, null):Null<Node>;
	// the node a button went down on (gets the pointer until it is up)
	public var capture(default, null):Null<Node>;
	public var needsFrame(default, null) = true;
	// the modifier keys held (Key.MOD_*: from the key events), which pointer events carry too
	public var mods(default, null) = 0;
	// the last pointer position
	public var pointerX(default, null) = 0.0;
	public var pointerY(default, null) = 0.0;
	// the focus was moved by the keyboard: its ring shows
	public var focusVisible(default, set) = false;
	// the window's theme (StyleSheet: its rules for the nodes with a slot,
	// its colours; a subtree's own wins, Node.theme), and whether the dark
	// colours and the rules for "dark" apply
	public var theme(default, set):Null<StyleSheet> = null;
	public var dark(default, set) = false;

	function set_focusVisible(v:Bool):Bool {
		if (v == focusVisible) return v;
		focusVisible = v;
		// (the focused node's rules for focus-visible, its ring)
		if (focus != null) {
			focus.layerChanged();
			@:privateAccess focus.restyleLater();
			focus.statesChanged();
		}
		return v;
	}

	// (the nodes whose rules apply again at the next update: Node.restyleLater)
	var restyles:Array<Node> = [];

	// applies the rules of the nodes waiting for it (update does, before layout)
	public function flushRestyles() {
		while (restyles.length > 0) {
			var list = restyles;
			restyles = [];
			for (n in list) {
				@:privateAccess n.restylePending = false;
				Rules.restyle(n);
			}
		}
	}

	function set_theme(v:Null<StyleSheet>):Null<StyleSheet> {
		if (v == theme) return v;
		theme = v;
		Rules.restyleTree(root);
		requestFrame();
		return v;
	}

	function set_dark(v:Bool):Bool {
		if (v == dark) return v;
		dark = v;
		Rules.restyleTree(root);
		requestFrame();
		return v;
	}
	// where widgets copy and paste text (UiWindow: the system's)
	// the window's pixels to the UI's (a Retina display's 2): what drawings are rasterized at
	public var scale = 1.0;
	// the safe area: the insets from each edge, in UI pixels, that a phone's
	// bars, notch or cutout leave clear (UiWindow: the window's, each frame;
	// 0 elsewhere). Markup's env(safe-area-inset-*) reads the main window's
	// (SafeArea); a layout of its own reads this
	public var safeArea:Edges = Edges.ZERO;
	// the soft keyboard's height over the window, in UI pixels (UiWindow:
	// helder.os.Window.keyboard; 0 while hidden, and on the desktop), and its
	// animation's seconds (0: not given). While it is up the focused field
	// is kept in view above it (KEYBOARD_MARGIN clear), its nearest scroller
	// scrolled, with the keyboard's animation
	public var keyboard = 0.0;
	public var keyboardDuration = 0.0;
	public static inline var KEYBOARD_MARGIN = 16.0;
	// (the focus and the keyboard's height last kept in view)
	var revealed:Null<Node> = null;
	var revealedAt = 0.0;
	// the platform's own views where a window has them (PlatformViews), and
	// which kinds of widget are native where the tree leaves it Auto (Host):
	// "text-field", "text-area", "context-menu", "menubar" (defaultPolicy:
	// text drawn on the desktop, native in a browser and on phones; menus native)
	public var platform:Null<PlatformViews> = null;
	public var policy:Map<String, Host> = defaultPolicy();
	public var clipboard:ClipboardHost = new ClipboardHost.MemoryClipboard();
	// the window it is drawn in (UiWindow's: WindowControls' buttons; null: none)
	public var window:Null<WindowHost> = null;
	// where the system's window buttons go (WindowControls' box: UiWindow
	// places them at its top left after each layout; null: where they are)
	public var controlsAt:Null<Node> = null;
	public var focusRingColor:Color = 0xFF3B82F6;
	public var focusRingWidth = 2.0;
	// the ring's gap outside the node
	public var focusRingOffset = 2.0;
	public var scrollbarColor:Color = 0x59000000;
	// the scrollbars shown only while their scroller moves, over the content
	// (macOS's overlay scrollers: UiWindow follows the system's setting):
	// shown as it moves, faded out half a second after it stops, over a
	// quarter (AppKit's, as Chromium has them); a press finds them only while shown
	public var overlayBars = false;
	// how the scrollbars look (ScrollbarLook; UiWindow: macOS's on macOS)
	public var scrollbarLook:ScrollbarLook = Plain;
	// the platform's own scrollbars drawn for that look (null: helder's drawing of it)
	public var scrollbarArt:Null<ScrollbarArt> = null;
	// (each scroller's offsets at the last paint, and when they last changed)
	final barMoved = new Map<Node, Array<Float>>();

	static inline var BAR_SHOWN = 0.5;
	static inline var BAR_FADE = 0.25;

	var barHover:Null<Node> = null;

	// whether the pointer is over n's scrollbar on axis x (its track's width, along its length)
	function overBar(n:Node, x:Bool):Bool {
		if (Scrolling.thumb(n, x) == null) return false;
		var tr = Scrolling.track(n, x), g = Scrolling.gutter(n), px = pointerX + Scrolling.scrolled(n, true), py = pointerY + Scrolling.scrolled(n, false);
		var along = x ? px : py, across = x ? py : px, edge = tr[2] + Scrolling.barSize(n) + Scrolling.barInset(n);
		return along >= tr[0] && along <= tr[0] + tr[1] && across >= edge - g && across <= edge;
	}

	// how far n's overlay scrollbars show (0 to 1), its last moves noted; a frame asked for while they fade
	function barShown(n:Node):Float {
		var m = barMoved.get(n), t = now();
		if (m == null) {
			barMoved.set(n, [n.scrollX, n.scrollY, -1e9]);
			return 0;
		}
		// (shown as it moves, while dragged, and while the pointer is over a bar of it)
		if (m[0] != n.scrollX || m[1] != n.scrollY || drag == n || overBar(n, false) || overBar(n, true)) {
			m[0] = n.scrollX;
			m[1] = n.scrollY;
			m[2] = t;
		}
		var age = t - m[2];
		if (age >= BAR_SHOWN + BAR_FADE) return 0;
		needsFrame = true;
		return age <= BAR_SHOWN ? 1 : 1 - (age - BAR_SHOWN) / BAR_FADE;
	}
	public var scrollbarActiveColor:Color = 0x8C000000;

	// --- the pointers other than the mouse (fingers, pens: helder.os's slots)
	public static inline var POINTERS = 16;

	// per pointer: down; its events' target (the node it went down on, or
	// the one that captured it; null: what is under it); its type; where
	// it went down and is; whether its press is still the nodes' (not
	// cancelled: a scroll took it) and its release may click; the first one
	final pDown:Array<Bool> = [for (_ in 0...POINTERS) false];
	final pTarget:Array<Null<Node>> = [for (_ in 0...POINTERS) null];
	final pType:Array<PointerType> = [for (_ in 0...POINTERS) Touch];
	final pStartX:Array<Float> = [for (_ in 0...POINTERS) 0.0];
	final pStartY:Array<Float> = [for (_ in 0...POINTERS) 0.0];
	final pLive:Array<Bool> = [for (_ in 0...POINTERS) false];
	final pClick:Array<Bool> = [for (_ in 0...POINTERS) false];
	final pPrimary:Array<Bool> = [for (_ in 0...POINTERS) false];
	// (whether a node captured it, Node.capture, as its press went down:
	// the drag is that node's, the first finger's scroll left out)
	final pCaptured:Array<Bool> = [for (_ in 0...POINTERS) false];
	// the arenas (the mouse's 0): the recognisers competing for each
	// pointer, the innermost first; the one that won it
	final arenas:Array<Array<Gesture>> = [for (_ in 0...POINTERS) []];
	final winners:Array<Null<Gesture>> = [for (_ in 0...POINTERS) null];
	final scratch:Array<Array<Gesture>> = [for (_ in 0...POINTERS) []];
	// the first finger's drag (a scroller's)
	final touchScroll:TouchScroll;
	// the pointer whose event is being dispatched (Node.capture's)
	var dispatching = -1;

	// the thumb being dragged: its node, axis, the pointer and scroll it started at
	var drag:Null<Node> = null;
	// drag and drop: the node a press may drag (its dragData), where it went down; the drag, its target that accepts
	var dragSource:Null<Node> = null;
	var dragFromX = 0.0;
	var dragFromY = 0.0;
	// what is being dragged and where (null: nothing)
	public var dragging(default, null):Null<{source:Node, data:Dynamic, x:Float, y:Float}> = null;
	var dropTarget:Null<Node> = null;
	var dragX = false;
	var dragFrom = 0.0;
	var dragScroll = 0.0;

	// a scrollbar's thickness and its inset from the node's border
	public static inline var SCROLLBAR = 6.0;
	public static inline var SCROLLBAR_INSET = 2.0;
	public static inline var MIN_THUMB = 20.0;

	// the screen it is part of (helder.ui.ScreenContext: the program's main
	// one, or a story host's screen's): its clock's what animates in it
	public final context:ScreenContext;

	public function new(text:TextEngine, width:Float, height:Float) {
		context = ScreenContext.current;
		this.text = text;
		this.width = width;
		this.height = height;
		root = new Node("root");
		root.attach(this);
		overlay = new Node("overlay");
		overlay.attach(this);
		touchScroll = @:privateAccess new TouchScroll(this);
		walker = new UiWalk(this);
		trackpad = @:privateAccess new Trackpad(this);
		stretcher = @:privateAccess new Stretch(this);
		// (Copy: the selected text, while there is some)
		on(helder.ui.actions.Actions.StandardAction, a -> switch a {
			case Copy if (selectedText() != ""):
				clipboard.write(selectedText());
				true;
			case _: false;
		}, a -> a == Copy && selectedText() != "" ? Enabled : Unhandled);
		#if hxmc.dev
		DevTree.add(this);
		#end
	}

	public function resize(width:Float, height:Float) {
		if (width == this.width && height == this.height) return;
		var was = breakpoint(this.width);
		this.width = width;
		this.height = height;
		root.markDirty();
		overlay.markDirty();
		// (across a breakpoint: the rules for sm, md... hold or not)
		if (breakpoint(width) != was) {
			Rules.restyleTree(root);
			Rules.restyleTree(overlay);
		}
	}

	// Tailwind's breakpoints (sm, md, lg, xl, 2xl: the window at least so wide, in pixels)
	public static final BREAKPOINTS = ["sm" => 640.0, "md" => 768.0, "lg" => 1024.0, "xl" => 1280.0, "2xl" => 1536.0];

	// (their widths: iterated without the map's iterator)
	static final WIDTHS = [for (b in BREAKPOINTS) b];

	// (how many of them a width reaches)
	static function breakpoint(w:Float):Int {
		var k = 0;
		for (b in WIDTHS)
			if (w >= b) k++;
		return k;
	}

	public function requestFrame() {
		needsFrame = true;
		requests++;
	}

	// (the frames asked for so far: one asked for while a node records is what it reads changing)
	var requests = 0;

	// lays the tree out if it changed (a tree that did not: nothing done);
	// the platform's views' events first, their nodes kept in step after
	// bumped by each key, press, release, focus change and action (what a menu's states may follow)
	public var inputEpoch(default, null) = 0;

	// run first in each update (a menu bar's states checked: helder.ui.menu.MenuBar)
	public final beforeUpdate:Array<Void->Void> = [];

	public function update() {
		helder.ui.motion.Motions.updating = true;
		for (f in beforeUpdate.copy())
			f();
		if (platform != null) platform.poll();
		// (the frame: what was written since lands first, helder.view.graph)
		helder.view.graph.Graph.flush();
		// (a touch's scroll let go moving: its glide's since the last)
		if (touchScroll.gliding) @:privateAccess touchScroll.glide(now() * 1000);
		flushRestyles();
		// (a font replaced: every text laid out again)
		var g = text == null ? 0 : text.generation();
		if (g != fontGeneration) {
			fontGeneration = g;
			dirtyAll(root);
			dirtyAll(overlay);
		}
		Layout.run(root, width, height, text, rounded);
		// (the nodes placing what they show by its laid out sizes: laid out again while one changes it)
		var settled = 0;
		while (settlers.length > 0 && settled++ < SETTLES && settle()) {
			helder.view.graph.Graph.flush();
			flushRestyles();
			Layout.run(root, width, height, text, rounded);
		}
		if (root.inkStale) refreshInk(root);
		if (overlay.children.length > 0) {
			Layout.run(overlay, width, height, text, rounded);
			// (placed from their sizes: laid out again when one moved)
			if (Popups.place(this)) Layout.run(overlay, width, height, text, rounded);
			if (overlay.inkStale) refreshInk(overlay);
		}
		tellResized();
		// (the scrollers whose extents may have changed)
		for (n in rounded)
			if (!@:privateAccess trackpad.holds(n)) Scrolling.clamp(n);
		rounded.resize(0);
		changes.resize(0);
		reveal();
		for (n in natives.copy())
			n.syncNative();
		helder.ui.motion.Motions.updating = false;
		if (helder.ui.motion.Motions.on) helder.ui.motion.Motions.updated();
	}

	var fontGeneration = 0;

	// (the keyboard up: a field newly focused, or the keyboard's height
	// changed, kept in view above it)
	function reveal() {
		var f = focus;
		if (keyboard <= 0 || f == null || f.textKind() == null) {
			revealed = null;
			revealedAt = 0;
			return;
		}
		if (f == revealed && keyboard == revealedAt) return;
		revealed = f;
		revealedAt = keyboard;
		Scrolling.reveal(this, f, KEYBOARD_MARGIN, height - keyboard, keyboardDuration);
	}

	static function dirtyAll(n:Node) {
		if (n is TextNode) (cast n : TextNode).forgetLayout();
		n.markDirty();
		for (c in n.children)
			dirtyAll(c);
	}

	// the nodes that may be native (EditableText: they join while in the tree)
	var natives:Array<Node> = [];

	// the nodes settled after each layout (VirtualScroll: they join while in
	// the tree), the tree laid out again while one changes it, SETTLES times at most
	@:allow(helder.ui) final settlers:Array<Node> = [];
	static inline var SETTLES = 8;

	function settle():Bool {
		var any = false;
		for (i in 0...settlers.length)
			if (@:privateAccess settlers[i].settle()) any = true;
		return any;
	}

	// the nodes laid out at a size their onResize was not told (Node.setLayout)
	final resized:Array<Node> = [];

	// (onResize: each told once, after the layout and its bounds)
	function tellResized() {
		if (resized.length == 0) return;
		var told = resized.copy();
		resized.resize(0);
		for (n in told) {
			var h = @:privateAccess n.handlers;
			if (h == null || h.onResize == null || (n.width == h.toldWidth && n.height == h.toldHeight)) continue;
			h.toldWidth = n.width;
			h.toldHeight = n.height;
			h.onResize(Event.of(Resize, n, n.absX, n.absY).at(n));
		}
	}

	// whether this program runs on a desktop (Windows, macOS, Linux; not a
	// browser, Android or iOS; nor Eval and JavaScript, as a browser's)
	public static function desktop():Bool {
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		return hxmc.Platform.apple() == 0 && hxmc.Platform.target() < 9 && hxmc.Platform.os() != 3;
		#else
		return false;
		#end
	}

	// a window's policy to begin with: on the desktop text fields and areas
	// drawn (helder's own editor: it composes with popups, scrolling and
	// clipping, and keeps screenshots the same; TSF, text-input-v3 and the
	// platform's spellchecker give what the platform's editor would), the
	// platform's where they are its strength (a browser's input and
	// textarea, a phone's keyboard, autocorrect and selection handles); the
	// menus the platform's wherever it has them. host="native" on a node, or
	// policy["text-field"] = Native, asks for the platform's editor still
	public static function defaultPolicy():Map<String, Host> {
		var text:Host = desktop() ? Drawn : Native;
		return ["text-field" => text, "text-area" => text, "context-menu" => Native, "menubar" => Native];
	}

	// what draws n, a widget of that kind (Ui.policy's names): its own host,
	// else its nearest ancestor's not Auto, else the policy's; Native only
	// where the window has the platform's views
	public function hostOf(n:Node, kind:String):Host {
		var h:Host = Auto, p = n;
		while (p != null && h == Auto) {
			h = p.host;
			p = p.parent;
		}
		if (h == Auto) h = policy.exists(kind) ? policy[kind] : Drawn;
		return h == Native && platform != null ? Native : Drawn;
	}

	// the ink bounds that a transform's change left stale, measured again
	static function refreshInk(n:Node) {
		if (!n.inkStale) return;
		for (c in n.children)
			refreshInk(c);
		n.measureInk();
	}

	// draws the tree (after update): subtrees whose ink misses what can be
	// seen (the window, the scrollers' padding boxes) left out. Painted into
	// layers (Layer: the root, each scroller's content, a node whose
	// transform or opacity moves), each a display list kept while nothing it
	// paints changes, then walked onto canvas (Walk), each layer where it
	// is now: the calls a direct paint gives canvas, in its order. The walk
	// records the layers that changed as it reaches them (what did not
	// change in them copied from their last recording: paintNode) and
	// marks what is reached (Node.drawnAt, a first paint's, the matched
	// elements flying); under motion one walk onto nothing does that first,
	// again while a first paint changes what is painted (an entering
	// motion), then one draws. A canvas that draws a layer from tiles of its
	// own (TextureCanvas.layerTiles: a window's Renderer) is given those in
	// its place. One that keeps its frame (TextureCanvas.keeps: a window's)
	// is drawn only what changed (damage: what each layer recorded again
	// changed, where layers and scrollbars moved, GPU textures; all of it
	// past what can be told), the walk onto nothing finding it, then one
	// walk for each of its rectangles, culled to it
	public function paint(canvas:Canvas) {
		if (direct) return paintTree(canvas);
		needsFrame = touchScroll.gliding;
		paintFrame++;
		painting = this;
		walking = true;
		target = canvas;
		var global = globalsChanged();
		if (global) paintKey++;
		prune();
		var g = Std.downcast(canvas, TextureCanvas), keep = g != null && g.keeps();
		if (keep) {
			damage.clear();
			if (global) damage.everything();
			tracking = true;
		}
		// (under motion, a first paint may set off an entering motion, which
		// changes what is painted: a walk onto nothing first, again until none does)
		if (helder.ui.motion.Motions.on || keep) {
			var tries = 0;
			do {
				again = false;
				flights.resize(0);
				flightAt.resize(0);
				walkRoot(nowhere, true, false);
			} while (again && helder.ui.motion.Motions.on && ++tries < 8);
			if (keep) {
				tracking = false;
				nowhere.found = null;
				// (matched elements flying: drawn live over everything)
				if (flights.length > 0 || flown) damage.everything();
				flown = flights.length > 0;
				g.damage(damage);
				for (i in 0...damage.count) {
					g.redraw(i);
					walkRoot(canvas, false, true, damage.x0(i), damage.y0(i), damage.x1(i), damage.y1(i));
				}
				g.redraw(-1);
			} else walkRoot(canvas, false, true);
		} else walkRoot(canvas, true, true);
		flights.resize(0);
		flightAt.resize(0);
		walking = false;
		target = null;
		painting = null;
	}

	// whether paint draws straight onto its canvas, not through the layers (a test comparing the two)
	@:noCompletion public var direct = false;
	// the layers recorded so far (a test's: a frame that only scrolls records none); the nodes copied as they were
	@:noCompletion public var recorded(default, null) = 0;
	@:noCompletion public var copied(default, null) = 0;
	// what the last paint onto a canvas keeping its frame found changed (a test's)
	@:noCompletion public final damage = new Damage();

	// (the root's layer, the others; the walk's state, its host, nothing to draw onto: the first walk's canvas)
	final rootLayer = new Layer(null, false);
	final layers:Array<Layer> = [];
	final walk = new Walk();
	final walker:UiWalk;
	static final nowhere = new Nowhere();
	// (in a layered paint; the canvas it draws onto, every list's target: Renderer.of)
	var walking = false;
	var target:Null<Canvas> = null;
	// (the list and layer being recorded: paintNode records its cull entries too)
	var recording:Null<DisplayList> = null;
	var recordingLayer:Null<Layer> = null;
	// (whether the nodes reached are marked: the walk's; one's first paint changed what it paints)
	var marking = true;
	var again = false;
	// (bumped as what every layer paints changes: the scale, the focus ring, the selection's colour)
	var paintKey = 0;
	// (bumped as each layer is recorded: Node.layerChanged stamps a node and
	// its ancestors with it; the layer's last record, its nodes' entries
	// compared with (diffing) and copied from (-1: none); inside a node
	// whose change its descendants inherit, none copied (fresh); what nodes
	// did as they recorded beyond their canvas (effects: their entries not copied))
	var ticks = 1;
	var lastTick = -1;
	var copyFrom = -1;
	var fresh = 0;
	var effects = 0;
	var diffing = false;
	// (a paint finding damage; what a layer's record changed, in its
	// coordinates; whether the last paint drew matched elements flying)
	var tracking = false;
	final local = new Damage();
	var flown = false;
	// (the scrollbars painted as the damage is found, against those drawn last; their bounds)
	var barsList = new DisplayList();
	final extent:Array<Float> = [0, 0, 0, 0];
	final painted:Array<Float> = [for (_ in 0...7) Math.NaN];

	function globalsChanged():Bool {
		var p = painted;
		inline function same(i:Int, v:Float):Bool {
			var was = p[i];
			p[i] = v;
			return was == v;
		}
		// (each compared and kept, none skipped)
		var a = same(0, scale), b = same(1, focusRingColor), c = same(2, focusRingWidth), d = same(3, focusRingOffset);
		var e = same(4, shadowReach), f = same(5, selectionColor), g = same(6, dark ? 1 : 0);
		return !(a && b && c && d && e && f && g);
	}

	// (the layers whose node left the tree or stopped scrolling let go; a node's that has not moved for IDLE paints given back to its parent's)
	static inline var IDLE = 60;

	function prune() {
		var i = layers.length;
		while (--i >= 0) {
			var l = layers[i], n = l.node;
			var gone = n.ui != this || (l.scroll ? n.style.overflow != Scroll || n.contentLayer != l : n.paintLayer != l || paintFrame - l.movedAt > IDLE);
			if (!gone) continue;
			layers.splice(i, 1);
			if (l.scroll && n.contentLayer == l) n.contentLayer = null;
			if (!l.scroll && n.paintLayer == l) {
				n.paintLayer = null;
				n.layerChanged();
			}
		}
	}

	// (what is seen: the window, or a rectangle of it, a damaged one's)
	function walkRoot(canvas:Canvas, mark:Bool, draw:Bool, x0 = 0.0, y0 = 0.0, x1 = -1.0, y1 = -1.0) {
		var w = walk;
		w.set(x0, y0, x1 < 0 ? width : x1, y1 < 0 ? height : y1);
		w.ptx = w.pty = 0;
		w.mark = mark;
		w.draw = draw;
		w.frame = paintFrame;
		w.host = walker;
		marking = mark;
		if (canvas == nowhere) nowhere.reset(width, height, tracking ? damage : null);
		if (mark) {
			ensure(rootLayer, 0, 0, width, height);
			if (tracking) damaged(0, 0, width, height);
		}
		rootLayer.list.replay(canvas, w);
		marking = true;
	}

	// (l recorded again if what it paints changed, over what it was recorded
	// over while that covers what is seen (x0, y0, x1, y1), so that the
	// entries of what did not change are copied (paintNode), else over
	// what is seen and a quarter of a viewport each way, as what changes may
	// change again; or if it was recorded over less than what is seen, as
	// it scrolls, and the first time, over a viewport each way)
	function ensure(l:Layer, x0:Float, y0:Float, x1:Float, y1:Float) {
		var stale = l.list.stale();
		if (l.dirty || l.volatile || l.key != paintKey || l.hidden != l.hiddenIn || stuckMoved(l) || stale) {
			l.content++;
			if (l.recordedAt >= 0 && l.covers(x0, y0, x1, y1)) record(l, l.x0, l.y0, l.x1, l.y1, 0, true, !stale);
			else record(l, x0, y0, x1, y1, l.recordedAt < 0 ? 1 : 0.25, true, !stale);
		} else if (!l.covers(x0, y0, x1, y1)) record(l, x0, y0, x1, y1, 1, false, true);
	}

	// (what recording a layer changed (local, in its coordinates; all: x0,
	// y0, x1, y1, what is seen of it) where it is drawn now: the walk's
	// canvas, nowhere's)
	function damaged(x0:Float, y0:Float, x1:Float, y1:Float) {
		var d = local;
		if (d.all) nowhere.add(x0, y0, x1, y1) else for (i in 0...d.count)
			nowhere.add(d.x0(i), d.y0(i), d.x1(i), d.y1(i));
		d.clear();
	}

	// (where l is drawn now (nowhere's: the walk's canvas), its box x0, y0,
	// x1, y1 there, against where it was: both damaged where they differ;
	// and as it comes to rest, its tiles drawn where they fall while it
	// moved replaced by its list's drawing: Renderer.layerTiles)
	function layerMoved(l:Layer, x0:Float, y0:Float, x1:Float, y1:Float) {
		var o = nowhere, d = l.drawn, moving = paintFrame - l.movedAt < 3 ? 1 : 0;
		o.bound(x0, y0, x1, y1);
		if (d.length == 12 && d[0] == o.a && d[1] == o.b && d[2] == o.c && d[3] == o.d && d[4] == o.e && d[5] == o.f && d[6] == o.alpha && d[7] == o.bx0
			&& d[8] == o.by0 && d[9] == o.bx1 && d[10] == o.by1 && d[11] == moving)
			return;
		if (d.length == 12) damage.add(d[7], d[8], d[9], d[10]);
		damage.add(o.bx0, o.by0, o.bx1, o.by1);
		d.resize(0);
		for (v in [o.a, o.b, o.c, o.d, o.e, o.f, o.alpha, o.bx0, o.by0, o.bx1, o.by1, moving])
			d.push(v);
	}

	// (its sticky nodes' scrollers scrolled since it was recorded)
	function stuckMoved(l:Layer):Bool {
		for (i in 0...l.sticky.length) {
			var sc = l.sticky[i];
			if (sc.scrollX != l.stuck[2 * i] || sc.scrollY != l.stuck[2 * i + 1]) return true;
		}
		return false;
	}

	// (l's subtree painted into its list over x0, y0, x1, y1 and margin
	// viewports each way, the paint's state put back after; what it paints
	// asking for frames, it is recorded again each frame. Changed: what it
	// paints, not only what it is recorded over (then what changed found,
	// local); copies: what did not change copied from its last record)
	function record(l:Layer, x0:Float, y0:Float, x1:Float, y1:Float, margin:Float, changed:Bool, copies:Bool) {
		var n = l.node;
		if (n != null && x1 - x0 < 1e8 && y1 - y0 < 1e8) {
			var mw = Math.max(0, x1 - x0) * margin, mh = Math.max(0, y1 - y0) * margin;
			var rx0 = x0 - mw, rx1 = x1 + mw, ry0 = y0 - mh, ry1 = y1 + mh;
			// (a scroller's: no farther than its scroll reaches, what is seen now kept)
			if (l.scroll) {
				var be = n.style.borderEdges;
				var sx = Scrolling.scrollStart(n, true), sy = Scrolling.scrollStart(n, false);
				rx0 = Math.max(rx0, Math.min(x0, n.absX + be.left + sx));
				ry0 = Math.max(ry0, Math.min(y0, n.absY + be.top + sy));
				rx1 = Math.min(rx1, Math.max(x1, n.absX + n.width - be.right + sx + Scrolling.maxScroll(n, true)));
				ry1 = Math.min(ry1, Math.max(y1, n.absY + n.height - be.bottom + sy + Scrolling.maxScroll(n, false)));
			}
			x0 = rx0;
			x1 = rx1;
			y0 = ry0;
			y1 = ry1;
		}
		var w = walk, wx0 = w.x0, wy0 = w.y0, wx1 = w.x1, wy1 = w.y1, wpx = w.ptx, wpy = w.pty;
		var wasList = recording, wasLayer = recordingLayer, wasHidden = hidden, wasFrame = needsFrame;
		w.set(x0, y0, x1, y1);
		var tick = ++ticks, first = l.tick < 0;
		lastTick = l.tick;
		copyFrom = copies && !first && l.key == paintKey ? l.tick : -1;
		diffing = tracking && changed && !first && l.hidden == l.hiddenIn;
		local.clear();
		if (tracking && changed && !diffing) local.everything();
		l.list.begin();
		l.list.target = target;
		l.volatile = false;
		l.sticky.resize(0);
		l.stuck.resize(0);
		recording = l.list;
		recordingLayer = l;
		hidden = l.hiddenIn;
		needsFrame = false;
		if (n == null) {
			paintNode(root, l.list);
			if (overlay.children.length > 0) paintNode(overlay, l.list);
			l.list.flights();
		} else if (l.scroll) {
			var st = n.style, bg = st.background, inset = false, sh = st.paintedShadows();
			if (sh != null)
				for (x in sh)
					if (x.inset) inset = true;
			l.backdrop = bg.a == 255 && st.backgroundImage == null && !inset && !l.hiddenIn ? (bg : Int) : 0;
			paintScrolled(n, l.list);
		}
		else {
			var p = n.present, nw = p == null ? n.width : p.width(), nh = p == null ? n.height : p.height();
			var e = focusRingOffset + focusRingWidth + shadowReach + 8 + n.style.outlineOffset + n.style.outlineWidth;
			l.bx0 = n.absX - e;
			l.by0 = n.absY - e;
			l.bx1 = n.absX + nw + e;
			l.by1 = n.absY + nh + e;
			if (n.style.overflow == Visible)
				for (c in n.children) {
					l.bx0 = Math.min(l.bx0, c.inkX0 - e);
					l.by0 = Math.min(l.by0, c.inkY0 - e);
					l.bx1 = Math.max(l.bx1, c.inkX1 + e);
					l.by1 = Math.max(l.by1, c.inkY1 + e);
				}
			paintBody(n, l.list, p, nw, nh);
		}
		if (diffing) l.list.diff(-1, -1, local, tick, false);
		l.list.done();
		l.tick = tick;
		copyFrom = lastTick = -1;
		diffing = false;
		if (needsFrame) l.volatile = true;
		needsFrame = wasFrame || needsFrame;
		recording = wasList;
		recordingLayer = wasLayer;
		hidden = wasHidden;
		w.set(wx0, wy0, wx1, wy1);
		w.ptx = wpx;
		w.pty = wpy;
		l.x0 = x0;
		l.y0 = y0;
		l.x1 = x1;
		l.y1 = y1;
		l.key = paintKey;
		l.hidden = l.hiddenIn;
		l.dirty = false;
		l.recordedAt = paintFrame;
		l.bump();
		recorded++;
	}

	// (a scroller's content walked: moved by its scroll as it is now)
	function walkLayer(l:Layer, c:Canvas, w:Walk) {
		if (!l.scroll) {
			paintNode(l.node, c);
			return;
		}
		var n = l.node, sx = n.scrollX, sy = n.scrollY, scroll = sx != 0 || sy != 0;
		if (w.mark && (sx != l.lastX || sy != l.lastY)) {
			l.lastX = sx;
			l.lastY = sy;
			l.movedAt = paintFrame;
		}
		if (scroll) {
			c.translate(-sx, -sy);
			w.shift(-sx, -sy);
		}
		if (w.mark) {
			ensure(l, w.x0, w.y0, w.x1, w.y1);
			if (tracking) {
				damaged(w.x0, w.y0, w.x1, w.y1);
				layerMoved(l, w.x0, w.y0, w.x1, w.y1);
			}
		}
		drawLayer(l, c, w);
		if (scroll) {
			c.translate(sx, sy);
			w.ptx += sx;
			w.pty += sy;
		}
	}

	// (a layer's list replayed, or its tiles drawn where the canvas has them:
	// not in the paint that recorded it, as what changed may change again)
	function drawLayer(l:Layer, c:Canvas, w:Walk) {
		if (w.draw && l.recordedAt != paintFrame && l.tiled()) {
			var g = Std.downcast(c, TextureCanvas);
			if (g != null) {
				l.moving = paintFrame - l.movedAt < 3;
				// (what it holds marked as it is reached, then its tiles)
				if (w.mark) l.list.replay(nowhere, w);
				if (g.layerTiles(l)) return;
				if (w.mark) {
					w.mark = false;
					l.list.replay(c, w);
					w.mark = true;
					return;
				}
			}
		}
		l.list.replay(c, w);
	}

	// (a node reached for the first time, in the walk that marks: what its first paint sets off)
	function firstPaint(n:Node, entering:Bool) @:privateAccess {
		var s = n.style;
		if (s.drawn) return;
		s.drawn = true;
		if (s.starting) n.restyleLater();
		if (entering && n.entering) {
			helder.ui.motion.Motions.enter(n);
			n.layerChanged(true);
			again = true;
		}
	}

	// (the scrollbars of a scroller recorded in a layer: drawn live, as they fade and follow the pointer)
	function walkBars(n:Node, nw:Float, nh:Float, c:Canvas, w:Walk) {
		if (w.draw && !(nativeScroll && nativeBars)) paintBars(n, c, nw, nh);
		else if (tracking && w.mark) barsMoved(n, nw, nh);
	}

	// (a scroller's scrollbars painted as they would be drawn, against those
	// drawn last (its layer's): where they differ, damaged)
	function barsMoved(n:Node, nw:Float, nh:Float) {
		var now = barsList, l = n.contentLayer, was = l == null ? null : l.bars;
		now.clear();
		if (!(nativeScroll && nativeBars)) paintBars(n, now, nw, nh);
		if (was != null && was.same(now)) return;
		for (list in [now, was])
			if (list != null) {
				if (list.extent(extent)) nowhere.add(extent[0], extent[1], extent[2], extent[3]);
				else nowhere.add(n.absX, n.absY, n.absX + nw, n.absY + nh);
			}
		if (l == null) return;
		l.bars = now;
		barsList = was ?? new DisplayList();
	}

	function walkFlights(c:Canvas, w:Walk) {
		if (!w.draw || flights.length == 0) return;
		var was = marking;
		marking = true;
		paintFlights(c);
		marking = was;
	}

	function paintTree(canvas:Canvas) {
		// (a glide's next step: another frame)
		needsFrame = touchScroll.gliding;
		paintFrame++;
		walk.set(0, 0, width, height);
		painting = this;
		walk.ptx = walk.pty = 0;
		paintNode(root, canvas);
		if (overlay.children.length > 0) paintNode(overlay, canvas);
		if (flights.length > 0) paintFlights(canvas);
		painting = null;
	}

	// (matched elements flying: over everything, outside their ancestors' opacity and clips)
	function paintFlights(canvas:Canvas) {
		var w = walk;
		flying = true;
		for (i in 0...flights.length) {
			var fx = flightAt[2 * i], fy = flightAt[2 * i + 1];
			w.set(-fx, -fy, width - fx, height - fy);
			w.ptx = fx;
			w.pty = fy;
			canvas.translate(fx, fy);
			paintNode(flights[i], canvas);
			canvas.translate(-fx, -fy);
		}
		flying = false;
		flights.resize(0);
		flightAt.resize(0);
	}

	// the Ui painting now (a leaving node's content drawn out of its tree: helder.ui.motion)
	public static var painting(default, null):Null<Ui> = null;
	// (the matched elements flying, drawn last, where they were met (Walk.ptx: the
	// translation motion and scrolling put the node being drawn at, from the window's))
	final flights:Array<Node> = [];
	final flightAt:Array<Float> = [];
	var flying = false;
	// (inside a leaving node: no layers there)
	var ghosts = 0;

	// (the paints so far: a node drawn in the last one has its number, Node.drawnAt)
	var paintFrame = 0;

	// the farthest any shadow drawn reaches outside its box (Style.shadow)
	public static var shadowReach = 0.0;
	// (the node being drawn is hidden: Style.visibility, inherited)
	var hidden = false;

	// (a node painted. Recording a layer, what it recorded the last time
	// copied where nothing in it changed since (Node.changedAt, innerAt),
	// nothing it inherits did (deepAt), it was recorded under the same rect
	// seen and visibility, and what it did then was only to record
	// (effects: it set the layer recorded each frame, a sticky node, a
	// frame asked for, a pass or a GPU texture: NOCOPY); else painted, its
	// entry compared with its last (diffing: what changed, local))
	function paintNode(n:Node, canvas:Canvas) {
		var dl = recording;
		if (dl == null) return drawNode(n, canvas);
		var w = walk, last = lastTick, old = last >= 0 && n.paintedAt == last ? n.entry : -1, from = copyFrom;
		if (old >= 0 && from >= 0 && fresh == 0 && !flying && ghosts == 0 && n.changedAt < from && n.innerAt < from && n.paintLayer == null
			&& dl.copy(old, w.x0, w.y0, w.x1, w.y1, hidden, ticks, recordingLayer)) {
			copied++;
			return;
		}
		var deep = from >= 0 && n.deepAt >= from, start = dl.mark(), e = effects + requests + dl.live;
		if (deep) fresh++;
		drawNode(n, canvas);
		if (deep) fresh--;
		var at = dl.entry(start, n);
		if (at < 0) {
			n.paintedAt = -1;
			return;
		}
		if (effects + requests + dl.live != e) dl.flag(at, DisplayList.NOCOPY);
		if (n.style.position == Sticky) dl.flag(at, DisplayList.LOOSE);
		n.paintedAt = ticks;
		n.entry = at;
		if (diffing) dl.diff(at, old, local, ticks, n.paintsLive());
	}

	// (what is seen is the walk's: in the coordinates of the node being drawn.
	// Recording a layer, what changes it is recorded too, and what a paint
	// sets off (a first paint's, Node.drawnAt, a flight) left to the walk)
	function drawNode(n:Node, canvas:Canvas) {
		var s = n.style;
		if (s.display == None || n.width <= 0 && n.height <= 0 && n.children.length == 0) return;
		var dl = recording, w = walk;
		// (a moving node's own layer: drawn by the walk, with its transform and opacity then)
		if (dl != null && n.paintLayer != null && !flying && ghosts == 0) {
			n.paintLayer.parent = recordingLayer;
			dl.layer(n.paintLayer, hidden);
			return;
		}
		// (its entry: at once where its first paint sets something off, else once it is seen to be drawn)
		var at = -1;
		if (dl != null) {
			if (!s.drawn)
				at = dl.node(n, DisplayList.FIRST | (@:privateAccess n.entering ? DisplayList.ENTERING : 0) | (hidden ? DisplayList.HIDDEN : 0), w.x0, w.y0, w.x1,
					w.y1);
		} else if (!s.drawn && marking) @:privateAccess {
			s.drawn = true;
			if (s.starting) n.restyleLater();
			if (n.entering) helder.ui.motion.Motions.enter(n);
		}
		// (motion: where its tracks draw it, helder.ui.motion.Present)
		var p = n.present;
		if (p != null && p.away) return none(dl, at);
		if (p != null && p.flying && !flying) {
			if (dl != null) {
				if (at >= 0) none(dl, at);
				dl.flight(n);
				effects++;
			} else if (marking) {
				flights.push(n);
				flightAt.push(w.ptx);
				flightAt.push(w.pty);
			}
			return;
		}
		var opacity = p == null ? s.opacity : s.opacity * p.presenceOpacity();
		if (opacity <= 0) return none(dl, at);
		var dx = 0.0, dy = 0.0, nw = n.width, nh = n.height;
		if (p != null) {
			dx = p.dx();
			dy = p.dy();
			nw = p.width();
			nh = p.height();
		}
		var m = n.transformMatrix();
		if (dl != null && s.position == Sticky) stick(n);
		// (its ink, widened by what rings, shadows and glyphs' overhang add, out of sight: left out)
		if (!n.inkAll) {
			var e = focusRingOffset + focusRingWidth + shadowReach + 8 + Math.abs(nw - n.width) + Math.abs(nh - n.height);
			var ax1 = n.inkX1 + dx + e, ax0 = n.inkX0 + dx - e, ay1 = n.inkY1 + dy + e, ay0 = n.inkY0 + dy - e;
			var culled = w.culls(ax1, ax0, ay1, ay0);
			if (dl != null && (at >= 0 || !culled)) {
				if (at < 0) at = dl.node(n, hidden ? DisplayList.HIDDEN : 0, w.x0, w.y0, w.x1, w.y1);
				dl.test(at, ax1, ax0, ay1, ay0);
			}
			if (culled) {
				if (at >= 0) dl.end(at);
				return;
			}
		}
		if (dl != null && at < 0) at = dl.node(n, hidden ? DisplayList.HIDDEN : 0, w.x0, w.y0, w.x1, w.y1);
		if (dl == null && marking) @:privateAccess n.drawnAt = paintFrame;
		var c0 = w.x0, c1 = w.y0, c2 = w.x1, c3 = w.y1;
		if (dl != null) dl.cullSave();
		var moved = dx != 0 || dy != 0;
		if (moved) {
			canvas.translate(dx, dy);
			w.shift(dx, dy);
			if (dl != null) dl.cullShift(dx, dy);
		}
		if (m != null) {
			canvas.pushTransform(m.a, m.b, m.c, m.d, m.e, m.f);
			// (under a transform: everything drawn)
			w.all();
			if (dl != null) dl.cullAll();
		}
		// (a group where more than one thing of it is drawn: its children, its
		// content over its box; its ink's bounds, else the clip's)
		if (opacity < 1) {
			if (n.children.length > 0 || n.exits != null || n.hasContent() && (s.background.a > 0 || s.borderWidth > 0 || s.backgroundImage != null)) {
				var e = focusRingOffset + focusRingWidth + shadowReach + 8 + Math.abs(nw - n.width) + Math.abs(nh - n.height);
				if (n.inkAll || m != null) canvas.pushGroup(opacity, -1e6, -1e6, 2e6, 2e6);
				else canvas.pushGroup(opacity, n.inkX0 - e, n.inkY0 - e, n.inkX1 - n.inkX0 + 2 * e, n.inkY1 - n.inkY0 + 2 * e);
			} else canvas.pushOpacity(opacity);
		}
		// (its own layer, walked: recorded where what it paints changed, drawn)
		var l = n.paintLayer;
		if (walking && dl == null && l != null && !flying && ghosts == 0) {
			if (w.mark) {
				ensure(l, w.x0, w.y0, w.x1, w.y1);
				if (tracking) {
					damaged(Math.max(w.x0, l.bx0), Math.max(w.y0, l.by0), Math.min(w.x1, l.bx1), Math.min(w.y1, l.by1));
					layerMoved(l, l.bx0, l.by0, l.bx1, l.by1);
				}
			}
			drawLayer(l, canvas, w);
		} else paintBody(n, canvas, p, nw, nh);
		w.set(c0, c1, c2, c3);
		if (dl != null) dl.cullRestore();
		if (opacity < 1) canvas.popOpacity();
		if (m != null) canvas.popTransform();
		if (moved) {
			canvas.translate(-dx, -dy);
			w.ptx -= dx;
			w.pty -= dy;
			if (dl != null) dl.shiftPoint(-dx, -dy);
		}
		if (dl != null) dl.end(at);
	}

	// (a node that draws nothing: its entry, if it has one, ended)
	inline function none(dl:Null<DisplayList>, at:Int) {
		if (dl == null || at < 0) return;
		dl.flag(at, DisplayList.NONE);
		dl.end(at);
	}

	// (a sticky node recorded: its layer recorded again as its scroller scrolls)
	function stick(n:Node) {
		var sc = n.parent;
		while (sc != null && sc.style.overflow != Scroll)
			sc = sc.parent;
		var l = recordingLayer;
		effects++;
		if (sc == null || l.sticky.indexOf(sc) >= 0) return;
		l.sticky.push(sc);
		l.stuck.push(sc.scrollX);
		l.stuck.push(sc.scrollY);
	}

	// (what a node paints at its place, its transform and opacity pushed: its
	// box, its content, its children clipped and scrolled, its scrollbars, its
	// outline and focus ring)
	function paintBody(n:Node, canvas:Canvas, p:Null<helder.ui.motion.Present>, nw:Float, nh:Float) {
		var s = n.style, dl = recording, w = walk;
		var wasHidden = hidden;
		if (s.visibility != null) hidden = s.visibility == Hidden;
		// (each corner's radius and each side's border, when the style gives them)
		var cs = s.corners != null ? s.cornerRadii() : null, sides = s.borders != null ? s.borderEdges : null;
		var be = s.borderEdges, bordered = be.top + be.right + be.bottom + be.left > 0 && s.borderColor.a > 0;
		var borderStyle:BorderStyle = s.borderStyle ?? Solid;
		// (the padding box's corners: each less the wider side meeting there)
		var padR = Math.max(0, s.radius - s.borderWidth), padC:Null<Corners> = null;
		if (cs != null || sides != null) {
			var c = s.cornerRadii();
			padC = new Corners(Math.max(0, c.topLeft - Math.max(be.left, be.top)), Math.max(0, c.topRight - Math.max(be.top, be.right)),
				Math.max(0, c.bottomRight - Math.max(be.right, be.bottom)), Math.max(0, c.bottomLeft - Math.max(be.bottom, be.left)));
		}
		// (the shadows outside: the last one first, under the others; not
		// under the box, as CSS clips them, unless its background hides them)
		var shadows = hidden ? null : s.paintedShadows();
		var opaque = s.background.a == 255 && s.backgroundImage == null;
		if (shadows != null)
			for (sh in shadows) {
				if (sh.inset) continue;
				var o = sh.spread;
				canvas.shadow(n.absX + sh.x - o, n.absY + sh.y - o, nw + 2 * o, nh + 2 * o, s.radius > 0 ? Math.max(0, s.radius + o) : 0, sh.color,
					sh.blur, cs == null ? null : new Corners(cs.topLeft > 0 ? Math.max(0, cs.topLeft + o) : 0, cs.topRight > 0 ? Math.max(0, cs.topRight + o) : 0,
						cs.bottomRight > 0 ? Math.max(0, cs.bottomRight + o) : 0, cs.bottomLeft > 0 ? Math.max(0, cs.bottomLeft + o) : 0), opaque ? null : [sh.x, sh.y, o]);
			}
		if (hidden) {
			// (nothing of its own)
		} else if (s.backgroundImage != null && nw > 0 && nh > 0) {
			// (the colour, the gradient over it, then the border over both)
			if (s.background.a > 0) canvas.rect(n.absX, n.absY, nw, nh, s.radius, s.background, 0, 0, cs);
			canvas.image(n.backgroundImage(scale), n.absX, n.absY, nw, nh, 0, 0, 1, 1, s.radius, cs);
			if (bordered) canvas.rect(n.absX, n.absY, nw, nh, s.radius, Color.TRANSPARENT, s.borderWidth, s.borderColor, cs, sides, borderStyle);
		} else if (s.background.a > 0 && s.borderColor.a < 255 && be.top + be.right + be.bottom + be.left > 0) {
			// (the background under the border too, as CSS's background-clip: border-box, seen through a translucent one)
			canvas.rect(n.absX, n.absY, nw, nh, s.radius, s.background, 0, 0, cs);
			if (bordered) canvas.rect(n.absX, n.absY, nw, nh, s.radius, Color.TRANSPARENT, s.borderWidth, s.borderColor, cs, sides, borderStyle);
		} else if (s.background.a > 0 || bordered)
			canvas.rect(n.absX, n.absY, nw, nh, s.radius, s.background, s.borderWidth, s.borderColor, cs, sides, borderStyle);
		// (the shadows inside: in the padding box, over the background)
		if (shadows != null)
			for (sh in shadows)
				if (sh.inset)
					canvas.insetShadow(n.absX + be.left, n.absY + be.top, nw - be.horizontal, nh - be.vertical, padR, sh.color, sh.blur, sh.x, sh.y,
						sh.spread, padC);
		// (a matched element flying: its content as laid out, scaled to cover its frame, clipped to it)
		var cover = p != null && p.flying && n.width > 0 && n.height > 0;
		if (cover) {
			var k = Math.max(nw / n.width, nh / n.height);
			canvas.pushClip(n.absX, n.absY, nw, nh, s.radius, cs);
			canvas.pushTransform(k, 0, 0, k, n.absX + nw / 2 - k * (n.absX + n.width / 2), n.absY + nh / 2 - k * (n.absY + n.height / 2));
			w.all();
			if (dl != null) dl.cullAll();
			nw = n.width;
			nh = n.height;
		}
		var pad = s.padding;
		// (its content as laid out: a size moving does not lay its text out again;
		// a node of its own drawing, recorded, recorded again each frame)
		if (n.hasContent() && !hidden) {
			if (dl != null && n.paintsLive()) {
				recordingLayer.volatile = true;
				effects++;
			}
			n.paintContent(canvas, n.absX + be.left + pad.left, n.absY + be.top + pad.top, Math.max(0, n.width - be.left - be.right - pad.left - pad.right),
				Math.max(0, n.height - be.top - be.bottom - pad.top - pad.bottom));
		}
		var clip = s.overflow != Visible;
		// (the padding box: its corners' radii less the wider side meeting there)
		if (clip) {
			canvas.pushClip(n.absX + be.left, n.absY + be.top, nw - be.horizontal, nh - be.vertical, padR, padC);
			w.clip(n.absX + be.left, n.absY + be.top, n.absX + nw - be.right, n.absY + nh - be.bottom);
			if (dl != null) dl.cullClip(n.absX + be.left, n.absY + be.top, n.absX + nw - be.right, n.absY + nh - be.bottom);
		}
		// (stretched past an end, Android's: a scale along its axis, anchored at that end)
		var stretched = s.overflow == Scroll && @:privateAccess stretcher.node == n ? @:privateAccess stretcher.amount : 0.0;
		if (stretched != 0) {
			var k = 1 + Math.abs(stretched), sx = @:privateAccess stretcher.alongX;
			var anchor = sx ? (stretched < 0 ? n.absX + be.left : n.absX + nw - be.right) : (stretched < 0 ? n.absY + be.top : n.absY + nh - be.bottom);
			if (sx) canvas.pushTransform(k, 0, 0, 1, anchor * (1 - k), 0) else canvas.pushTransform(1, 0, 0, k, 0, anchor * (1 - k));
			// (scaled: what was out of sight may come in, everything drawn while it lasts)
			w.all();
			if (dl != null) {
				dl.cullAll();
				recordingLayer.volatile = true;
				effects++;
			}
		}
		// (a scroller's content: its own layer, recorded, moved by the scroll as it is walked)
		if (s.overflow == Scroll && dl != null && !flying && ghosts == 0) {
			var l = n.contentLayer;
			if (l == null) {
				l = n.contentLayer = new Layer(n, true);
				layers.push(l);
			}
			l.parent = recordingLayer;
			dl.layer(l, hidden);
		} else {
			var sx = n.scrollX, sy = n.scrollY, scroll = s.overflow == Scroll && (sx != 0 || sy != 0);
			if (scroll) {
				canvas.translate(-sx, -sy);
				w.shift(-sx, -sy);
				if (dl != null) dl.cullShift(-sx, -sy);
			}
			paintScrolled(n, canvas);
			if (scroll) {
				canvas.translate(sx, sy);
				w.ptx += sx;
				w.pty += sy;
				if (dl != null) dl.shiftPoint(sx, sy);
			}
		}
		if (stretched != 0) canvas.popTransform();
		if (clip) canvas.popClip();
		if (cover) {
			canvas.popTransform();
			canvas.popClip();
			nw = p.width();
			nh = p.height();
		}
		if (s.overflow == Scroll && !hidden) {
			if (dl != null) dl.bars(n, nw, nh) else if (!(nativeScroll && nativeBars)) paintBars(n, canvas, nw, nh);
		}
		// (its outline over its content, the focus ring over that)
		if (s.outlineWidth > 0 && !hidden && s.outlineStyle != None) {
			var o = s.outlineOffset + s.outlineWidth;
			canvas.rect(n.absX - o, n.absY - o, nw + 2 * o, nh + 2 * o, s.radius > 0 ? Math.max(0, s.radius + o) : 0, Color.TRANSPARENT,
				s.outlineWidth, s.outlineColor ?? n.textColor(), cs == null ? null : new Corners(cs.topLeft > 0 ? Math.max(0, cs.topLeft + o) : 0,
					cs.topRight > 0 ? Math.max(0, cs.topRight + o) : 0, cs.bottomRight > 0 ? Math.max(0, cs.bottomRight + o) : 0,
					cs.bottomLeft > 0 ? Math.max(0, cs.bottomLeft + o) : 0), null, s.outlineStyle == Dashed ? Dashed : s.outlineStyle == Dotted ? Dotted : Solid);
		}
		if (n == focus && focusVisible && focusRingWidth > 0 && !hidden && (s.outlineStyle == null || s.outlineStyle == Auto)) {
			var o = focusRingOffset + focusRingWidth;
			canvas.rect(n.absX - o, n.absY - o, nw + 2 * o, nh + 2 * o, s.radius > 0 ? s.radius + o : 0, Color.TRANSPARENT, focusRingWidth,
				focusRingColor, cs == null ? null : new Corners(cs.topLeft > 0 ? cs.topLeft + o : 0, cs.topRight > 0 ? cs.topRight + o : 0,
					cs.bottomRight > 0 ? cs.bottomRight + o : 0, cs.bottomLeft > 0 ? cs.bottomLeft + o : 0));
		}
		hidden = wasHidden;
	}

	// (a scroller's content, or any node's children: absolute and sticky ones
	// over the others, in their order, as CSS paints positioned boxes; its
	// children leaving drawn where they were, over the others, until their exits settle)
	function paintScrolled(n:Node, canvas:Canvas) {
		var dl = recording, w = walk;
		var order = n.paintOrder();
		if (order != null) for (c in order) paintNode(c, canvas) else {
			var positioned = false;
			for (c in n.children)
				if (c.style.position != Relative) positioned = true else paintNode(c, canvas);
			if (positioned)
				for (c in n.children)
					if (c.style.position != Relative) paintNode(c, canvas);
		}
		if (n.exits == null) return;
		if (dl != null) {
			recordingLayer.volatile = true;
			effects++;
		}
		for (g in n.exits) {
			var gp = g.present, gdx = n.absX + gp.gx - g.absX, gdy = n.absY + gp.gy - g.absY;
			canvas.translate(gdx, gdy);
			w.shift(gdx, gdy);
			if (dl != null) dl.cullShift(gdx, gdy);
			ghosts++;
			paintNode(g, canvas);
			ghosts--;
			canvas.translate(-gdx, -gdy);
			w.shift(-gdx, -gdy);
			if (dl != null) dl.cullShift(-gdx, -gdy);
		}
	}

	// (a scroller's scrollbars, over its content)
	function paintBars(n:Node, canvas:Canvas, nw:Float, nh:Float) {
		var s = n.style;
		var shown = overlayBars ? barShown(n) : 1.0;
		if (shown > 0) for (x in [false, true]) {
				var t = Scrolling.thumb(n, x);
				if (t == null) continue;
				var b = Scrolling.barSize(n), track = Scrolling.inheritedBar(n, true), own = Scrolling.inheritedBar(n, false);
				// (the platform's own, where it draws them and no colours are given)
				if (scrollbarArt != null && scrollbarLook != ScrollbarLook.Plain && track == null && own == null) {
					var g = Scrolling.gutter(n), be = s.borderEdges, rtl = n.rtl(), overlay = scrollbarLook == ScrollbarLook.MacOverlay;
					var corner = Scrolling.maxScroll(n, !x) > 0 && !overlay ? g : 0;
					var strip:Null<Array<Float>> = overlay ? null : x ? [n.absX + be.left + (rtl ? corner : 0), n.absY + nh - be.bottom - g, nw - be.horizontal - corner, g] : [
						rtl ? n.absX + be.left : n.absX + nw - be.right - g, n.absY + be.top, g, nh - be.vertical - corner];
					scrollbarArt.paint(canvas, !x, overlay, dark, scale, strip, t, drag == n && dragX == x || overBar(n, x), shown);
					continue;
				}
				// (macOS's always-shown scroller: its track, a 1-point border on the content's side; the corner too)
				if (scrollbarLook == ScrollbarLook.MacLegacy && track == null) {
					var g = Scrolling.gutter(n), be = s.borderEdges, rtl = n.rtl(), bg:Color = dark ? 0xFF2C2C2C : 0xFFFAFAFA, line:Color = dark ? 0xFF3D3D3D : 0xFFE8E8E8;
					var corner = Scrolling.maxScroll(n, !x) > 0 ? g : 0;
					if (x) {
						var tx = n.absX + be.left + (rtl ? corner : 0), ty = n.absY + nh - be.bottom - g, tw = nw - be.horizontal - corner;
						canvas.rect(tx, ty, tw, g, 0, bg, 0, 0);
						canvas.rect(tx, ty, tw, 1, 0, line, 0, 0);
					} else {
						var tx = rtl ? n.absX + be.left : n.absX + nw - be.right - g, ty = n.absY + be.top, th = nh - be.vertical - corner;
						canvas.rect(tx, ty, g, th, 0, bg, 0, 0);
						canvas.rect(rtl ? tx + g - 1 : tx, ty, 1, th, 0, line, 0, 0);
						if (corner > 0) canvas.rect(tx, ty + th, g, g, 0, bg, 0, 0);
					}
				}
				if (track != null && track.a > 0) {
					var tr = Scrolling.track(n, x);
					if (x) canvas.rect(tr[0], tr[2], tr[1], b, b / 2, track, 0, 0) else canvas.rect(tr[2], tr[0], b, tr[1], b / 2, track, 0, 0);
				}
				var active = drag == n && dragX == x;
				var c:Color = own != null ? own : switch scrollbarLook {
					case MacOverlay: dark ? 0x80FFFFFF : 0x80000000;
					case MacLegacy: active ? (dark ? 0xFF939393 : 0x80000000) : (dark ? 0xFF6B6B6B : 0x3A000000);
					case _: active ? scrollbarActiveColor : scrollbarColor;
				};
				if (shown < 1) c = (Math.round(c.a * shown) << 24) | ((c : Int) & 0xFFFFFF);
				canvas.rect(t[0], t[1], t[2], t[3], b / 2, c, 0, 0);
			}
	}

	// --- pointer ---

	// the mouse moved (id 0), or a finger or a pen (id: its slot) to x, y
	// (an event: the graph's writes in it land at its end, helder.view.graph)
	// (at: when it happened, on this clock (eventTime: an event's own time); the gestures' velocities
	// are from those, so a slow frame between a flick's last move and its lift is not a pause)
	public function pointerMove(x:Float, y:Float, id = 0, pressure = 1.0, at = -1.0) {
		eventAt = at;
		pointerMoveNow(x, y, id, pressure);
		eventAt = -1;
		// (the platform's scrollbars: a frame as the pointer goes over one or leaves it, which darkens or shows it)
		if (id == 0 && scrollbarLook != ScrollbarLook.Plain) {
			var over:Null<Node> = null, n = hit(x, y);
			while (n != null && over == null) {
				if (n.style.overflow == Scroll && (overBar(n, false) || overBar(n, true))) over = n;
				n = n.parent;
			}
			if (over != barHover) {
				barHover = over;
				requestFrame();
			}
		}
		helder.view.graph.Graph.flush();
	}

	function pointerMoveNow(x:Float, y:Float, id = 0, pressure = 1.0) {
		if (id != 0) return touchMove(id, x, y, pressure);
		pointerX = x;
		pointerY = y;
		if (selecting && textSelection != null) {
			var c = textSelection.node.textIndexAt(x, y);
			if (c != textSelection.caret) {
				textSelection.caret = c;
				textSelection.node.layerChanged();
				requestFrame();
			}
		}
		if (drag != null) {
			var n = drag, t = Scrolling.track(n, dragX), view = Scrolling.viewSize(n, dragX), content = dragX ? n.contentWidth : n.contentHeight;
			var len = Scrolling.thumbLength(t[1], view, content), max = Scrolling.maxScroll(n, dragX);
			var v = dragScroll + ((dragX ? x : y) - dragFrom) * (t[1] > len ? max / (t[1] - len) : 0);
			Scrolling.setScroll(this, n, dragX, v);
			return;
		}
		// (a press on a draggable moved past 4 pixels: its drag starts)
		if (dragging == null && dragSource != null && capture != null && Math.abs(x - dragFromX) + Math.abs(y - dragFromY) > 4) {
			var s = dragSource;
			dragSource = null;
			var e = Event.of(DragStart, s, x, y);
			e.data = s.dragData;
			bubble(e);
			if (!e.defaultPrevented) {
				setPressed(capture, false);
				capture = null;
				closeArena(0, true);
				dragging = {source: s, data: s.dragData, x: x, y: y};
			}
		}
		var target = hit(x, y);
		setHover(target);
		if (dragging != null) {
			dragging.x = x;
			dragging.y = y;
			dragOver(target, x, y);
			requestFrame();
			return;
		}
		var to = capture != null ? capture : target;
		if (to != null) dispatch(Event.of(PointerMove, to, x, y), 0);
		if (capture != null) moveArena(0, x, y);
	}

	// the drag over target: from it up, the first that accepts (DragOver
	// with preventDefault) is the drop target; the one before it hears DragLeave
	function dragOver(target:Null<Node>, x:Float, y:Float) {
		// (left first: the pointer no longer inside the target that accepted, as HTML orders it)
		if (dropTarget != null && (target == null || !contains(dropTarget, target))) {
			leaveDrop(x, y);
			dropTarget = null;
		}
		var accepted:Null<Node> = null;
		var n = target;
		while (n != null && accepted == null) {
			if (n.onDragOver != null) {
				var e = Event.of(DragOver, target, x, y);
				e.data = dragging.data;
				n.onDragOver(e.at(n));
				if (e.defaultPrevented) accepted = n;
			}
			n = n.parent;
		}
		if (dropTarget != null && dropTarget != accepted) leaveDrop(x, y);
		dropTarget = accepted;
	}

	function leaveDrop(x:Float, y:Float) {
		var t = dropTarget;
		if (t == null || t.onDragLeave == null) return;
		var e = Event.of(DragLeave, t, x, y);
		e.data = dragging.data;
		t.onDragLeave(e.at(t));
	}

	// the drag ended: dropped on its target (Drop) or not, the source told (DragEnd)
	function endDrag(drop:Bool, x:Float, y:Float) {
		var d = dragging, t = dropTarget;
		dragging = null;
		dropTarget = null;
		if (t != null && !drop && t.onDragLeave != null) {
			var e = Event.of(DragLeave, t, x, y);
			e.data = d.data;
			t.onDragLeave(e.at(t));
		}
		var dropped = drop && t != null;
		if (dropped && t.onDrop != null) {
			var e = Event.of(Drop, t, x, y);
			e.data = d.data;
			t.onDrop(e.at(t));
		}
		var e = Event.of(DragEnd, d.source, x, y);
		e.data = d.data;
		e.dropped = dropped;
		bubble(e);
		requestFrame();
	}

	// a press of the mouse (id 0: button 1 left, 2 middle, 3 right), or a
	// finger or a pen down (id: its slot; button 1): whether a node took it,
	// one that is the ui's own (Node.ownsPointer: not the root, the body, nor
	// a box drawing a world under the ui), so that the game's controls leave
	// it alone (helder.os's Pointer.owner, UiWindow's)
	// (an event: the graph's writes in it land at its end, helder.view.graph)
	public function pointerDown(x:Float, y:Float, button:Int, id = 0, type:PointerType = Mouse, pressure = 1.0, at = -1.0):Bool {
		inputEpoch++;
		eventAt = at;
		var r = pointerDownNow(x, y, button, id, type, pressure);
		eventAt = -1;
		helder.view.graph.Graph.flush();
		return r;
	}

	function pointerDownNow(x:Float, y:Float, button:Int, id = 0, type:PointerType = Mouse, pressure = 1.0):Bool {
		if (id != 0) return touchDown(id, type, x, y, pressure);
		pointerX = x;
		pointerY = y;
		var target = hit(x, y);
		Popups.dismissOutside(this, target);
		// (a press focuses without the ring: hidden before the focus moves)
		if (focusVisible) {
			focusVisible = false;
			requestFrame();
		}
		selectAt(target, x, y, button);
		setHover(target);
		if (target == null) {
			setFocus(null);
			return false;
		}
		if (Scrolling.scrollbarDown(this, target, x, y)) return true;
		capture = target;
		dragSource = target;
		while (dragSource != null && dragSource.dragData == null)
			dragSource = dragSource.parent;
		dragFromX = x;
		dragFromY = y;
		setPressed(target, true);
		var e = Event.of(PointerDown, target, x, y);
		e.button = button;
		e.mods = mods;
		e.pressure = 0.5;
		dispatch(e, 0);
		if (!e.defaultPrevented) {
			var f = target;
			while (f != null && !f.focusable)
				f = f.parent;
			setFocus(f, false);
		}
		if (capture != null) openArena(0, target, Mouse, button, x, y, false);
		return owns(target);
	}

	// the mouse's button released (id 0), or a finger or a pen lifted
	// (an event: the graph's writes in it land at its end, helder.view.graph)
	public function pointerUp(x:Float, y:Float, button:Int, id = 0, at = -1.0) {
		inputEpoch++;
		eventAt = at;
		pointerUpNow(x, y, button, id);
		eventAt = -1;
		helder.view.graph.Graph.flush();
	}

	function pointerUpNow(x:Float, y:Float, button:Int, id = 0) {
		if (id != 0) return touchUp(id, x, y);
		pointerX = x;
		pointerY = y;
		selecting = false;
		if (drag != null) {
			drag = null;
			requestFrame();
			setHover(hit(x, y));
			return;
		}
		dragSource = null;
		if (dragging != null) {
			endDrag(true, x, y);
			setHover(hit(x, y));
			return;
		}
		var target = hit(x, y);
		var pressed = capture;
		capture = null;
		var to = pressed != null ? pressed : target;
		if (to == null) return;
		if (pressed != null) setPressed(pressed, false);
		var e = Event.of(PointerUp, to, x, y);
		e.button = button;
		e.mods = mods;
		dispatch(e, 0);
		if (arenas[0].length > 0) {
			moveArena(0, x, y);
			closeArena(0, false);
		}
		if (pressed != null) lose(pressed, 0, x, y);
		// a click: released over the node it went down on (or inside it)
		if (pressed != null && target != null && contains(pressed, target)) {
			var c = Event.of(Click, pressed, x, y);
			c.button = button;
			c.mods = mods;
			bubble(c);
		}
		setHover(target);
	}

	// a finger or a pen cancelled (the system took it: no click; id 0: the
	// mouse's press let go of the same way)
	// (an event: the graph's writes in it land at its end, helder.view.graph)
	public function pointerCancel(id:Int) {
		pointerCancelNow(id);
		helder.view.graph.Graph.flush();
	}

	function pointerCancelNow(id:Int) {
		if (id == 0) {
			var pressed = capture;
			capture = null;
			closeArena(0, true);
			if (pressed == null) return;
			setPressed(pressed, false);
			dispatch(Event.of(PointerCancel, pressed, pointerX, pointerY), 0);
			lose(pressed, 0, pointerX, pointerY);
			return;
		}
		if (id < 0 || id >= POINTERS || !pDown[id]) return;
		pDown[id] = false;
		cancelPress(id);
		closeArena(id, true);
	}

	// the node pointer id's events go to now (the mouse's: capture; null: what is under it)
	public function captureOf(id:Int):Null<Node>
		return id == 0 ? capture : id > 0 && id < POINTERS && pDown[id] ? pTarget[id] : null;

	function touchDown(id:Int, type:PointerType, x:Float, y:Float, pressure:Float):Bool {
		if (id < 0 || id >= POINTERS) return false;
		if (pDown[id]) pointerCancel(id);
		var primary = true;
		for (i in 1...POINTERS)
			if (pDown[i]) primary = false;
		// (a new touch stops a glide: the platform's too, and then clicks nothing)
		@:privateAccess touchScroll.stop();
		var halted = nativeScroll && nativeHalt != null && nativeHalt();
		var target = hit(x, y);
		Popups.dismissOutside(this, target);
		if (focusVisible) {
			focusVisible = false;
			requestFrame();
		}
		// (a press elsewhere drops a selection; a finger's drag scrolls, it selects nothing)
		if (primary) {
			selectAt(target, x, y, 1);
			selecting = false;
		}
		if (target == null) {
			if (primary) setFocus(null);
			return false;
		}
		pDown[id] = pLive[id] = pClick[id] = true;
		pPrimary[id] = primary;
		pCaptured[id] = false;
		pTarget[id] = target;
		pType[id] = type;
		pStartX[id] = x;
		pStartY[id] = y;
		setPressed(target, true);
		var e = touchEvent(PointerDown, target, id, x, y, pressure);
		e.button = 1;
		dispatch(e, id);
		if (!e.defaultPrevented && primary) {
			var f = target;
			while (f != null && !f.focusable)
				f = f.parent;
			setFocus(f, false);
		}
		if (halted) pClick[id] = false;
		if (pDown[id]) openArena(id, target, type, 1, x, y, primary && type != Mouse && !pCaptured[id] && !(nativeScroll && Scrolling.nativeAt(this, target)));
		return owns(target);
	}

	function touchMove(id:Int, x:Float, y:Float, pressure:Float) {
		if (id < 0 || id >= POINTERS || !pDown[id]) return;
		if (pLive[id]) {
			var to = pTarget[id] ?? hit(x, y);
			if (to != null) dispatch(touchEvent(PointerMove, to, id, x, y, pressure), id);
		}
		moveArena(id, x, y);
	}

	function touchUp(id:Int, x:Float, y:Float) {
		if (id < 0 || id >= POINTERS || !pDown[id]) return;
		pDown[id] = false;
		var target = hit(x, y), pressed = pTarget[id], live = pLive[id];
		pLive[id] = false;
		pTarget[id] = null;
		if (live) {
			if (pressed != null) setPressed(pressed, false);
			var to = pressed ?? target;
			if (to != null) {
				var e = touchEvent(PointerUp, to, id, x, y, 0);
				e.button = 1;
				dispatch(e, id);
			}
		}
		moveArena(id, x, y);
		var won = winners[id];
		closeArena(id, false);
		if (!live) return;
		if (pressed != null) lose(pressed, id, x, y);
		// a click: a press no other gesture won, released within the slop of
		// where it went down (wherever that is: a finger drifts a few points,
		// and a pressed control shrinks under it, its edge leaving the finger)
		// or within twice that on the node it went down on (a drag is no click)
		var dx = x - pStartX[id], dy = y - pStartY[id], d = Math.sqrt(dx * dx + dy * dy);
		if (pClick[id] && pressed != null && (won == null || Std.isOfType(won, Tap))
			&& (d <= Gesture.SLOP || (d <= 2 * Gesture.SLOP && target != null && contains(pressed, target)))) {
			var c = touchEvent(Click, pressed, id, x, y, 0);
			c.button = 1;
			dispatch(c, id);
		}
	}

	// a touch's press taken from its node: PointerCancel, the capture lost
	function cancelPress(id:Int) {
		var pressed = pTarget[id], live = pLive[id];
		pLive[id] = pClick[id] = false;
		pTarget[id] = null;
		if (!live || pressed == null) return;
		setPressed(pressed, false);
		dispatch(touchEvent(PointerCancel, pressed, id, pStartX[id], pStartY[id], 0), id);
		lose(pressed, id, pStartX[id], pStartY[id]);
	}

	function touchEvent(type:EventType, target:Node, id:Int, x:Float, y:Float, pressure:Float):Event {
		var e = Event.of(type, target, x, y);
		e.pointerId = id;
		e.pointerType = pType[id];
		e.pressure = pressure;
		e.isPrimary = pPrimary[id];
		e.mods = mods;
		return e;
	}

	// e bubbled, as pointer id's (Node.capture's)
	function dispatch(e:Event, id:Int) {
		var was = dispatching;
		dispatching = id;
		bubble(e);
		dispatching = was;
	}

	// (n no longer has pointer id: LostPointerCapture)
	function lose(n:Node, id:Int, x:Float, y:Float) {
		if (n.onLostPointerCapture == null) return;
		var e = id == 0 ? Event.of(LostPointerCapture, n, x, y) : touchEvent(LostPointerCapture, n, id, x, y, 0);
		n.onLostPointerCapture(e.at(n));
	}

	// (Node.capture: the pointer being dispatched, n's from now on)
	function captureBy(n:Node) {
		var id = dispatching;
		if (id <= 0) {
			// (the mouse: while pressed)
			if (capture != null) capture = n;
			return;
		}
		if (id >= POINTERS || !pDown[id] || !pLive[id]) return;
		var old = pTarget[id];
		pTarget[id] = n;
		pCaptured[id] = true;
		if (old != null && old != n) lose(old, id, pStartX[id], pStartY[id]);
	}

	// (Node.releaseCapture: its pointers go to what is under them)
	function releaseBy(n:Node) {
		if (capture == n) capture = null;
		for (id in 1...POINTERS)
			if (pDown[id] && pTarget[id] == n) {
				pTarget[id] = null;
				lose(n, id, pStartX[id], pStartY[id]);
			}
	}

	// whether target is the ui's own (pointerDown's answer)
	function owns(target:Null<Node>):Bool
		return target != null && target != root && target != body && target != overlay && target.ownsPointer();

	// --- the arenas (helder.ui.gesture.Gesture)

	// pointer id's arena opened at its press on target: the recognisers from
	// it up (innermost first), then the first finger's scroll
	function openArena(id:Int, target:Node, type:PointerType, button:Int, x:Float, y:Float, scroll:Bool) {
		var a = arenas[id];
		if (a.length > 0) closeArena(id, true);
		winners[id] = null;
		var n = target;
		while (n != null) {
			var gs = n.gestures;
			if (gs != null)
				for (g in gs)
					if (@:privateAccess g.join(id, type, button)) a.push(g);
			n = n.parent;
		}
		if (scroll && @:privateAccess touchScroll.join(id, type, button)) a.push(touchScroll);
		if (a.length == 0) return;
		var t = eventAt >= 0 ? eventAt : now(), list = snapshot(id);
		for (g in list)
			if (a.indexOf(g) >= 0) @:privateAccess g.down(id, x, y, t);
	}

	function moveArena(id:Int, x:Float, y:Float) {
		var a = arenas[id];
		if (a.length == 0) return;
		var t = eventAt >= 0 ? eventAt : now(), list = snapshot(id);
		for (g in list)
			if (a.indexOf(g) >= 0) @:privateAccess g.move(id, x, y, t);
	}

	// its pointer lifted (or cancelled): each recogniser told, the arena emptied
	function closeArena(id:Int, cancelled:Bool) {
		var a = arenas[id];
		if (a.length == 0) {
			winners[id] = null;
			return;
		}
		var t = eventAt >= 0 ? eventAt : now(), list = snapshot(id);
		for (g in list)
			if (a.indexOf(g) >= 0) @:privateAccess g.up(id, t, cancelled);
		a.resize(0);
		winners[id] = null;
	}

	// (an arena's recognisers as they are: callbacks may change it)
	function snapshot(id:Int):Array<Gesture> {
		var list = scratch[id];
		list.resize(0);
		for (g in arenas[id])
			list.push(g);
		return list;
	}

	// (Gesture.accept: g takes every pointer it follows, the others lose
	// them; whether it has them all)
	@:allow(helder.ui.gesture) function acceptGesture(g:Gesture):Bool {
		var all = true;
		for (id in 0...POINTERS) {
			if (!@:privateAccess g.follows(id)) continue;
			var w = winners[id];
			if (w == g) continue;
			if (w != null) {
				all = false;
				continue;
			}
			winners[id] = g;
			// (backwards, without the snapshot: a move's loop holds it)
			var a = arenas[id], i = a.length;
			while (--i >= 0) {
				if (i >= a.length) continue;
				var m = a[i];
				if (m != g && a.remove(m)) @:privateAccess m.lose(id);
			}
			if (!Std.isOfType(g, Tap)) pClick[id] = false;
			// (the scroll takes the press from the nodes)
			if (g == touchScroll && id > 0) cancelPress(id);
		}
		return all;
	}

	// (Gesture.cancel: g out of every arena, its pointers left to the others)
	@:allow(helder.ui.gesture) function leaveGesture(g:Gesture) {
		for (id in 0...POINTERS) {
			if (!arenas[id].remove(g)) continue;
			if (winners[id] == g) winners[id] = null;
		}
	}

	// (an event: the graph's writes in it land at its end, helder.view.graph)
	// (eased: a mouse's notches, the scroll gliding to them)
	// mods: the scroll's own modifiers (Key.MOD_*), else (-1) the keys' last
	// (a trackpad's pinch is a wheel with Control that no key event carries)
	// phase, momentum: a trackpad's gesture's and its momentum's
	// (helder.os.ScrollPhase; 0: a wheel's), time its event's (Ui.now's
	// clock): with elastic, Trackpad's
	public function wheel(x:Float, y:Float, deltaX:Float, deltaY:Float, eased = false, mods = -1, phase = 0, momentum = 0, time = -1.0) {
		wheelNow(x, y, deltaX, deltaY, eased, mods, phase, momentum, time < 0 ? now() : time);
		helder.view.graph.Graph.flush();
	}

	// a trackpad's scrolls as macOS's own views take them (Trackpad: one
	// scroller a gesture, stretching past its ends and springing back, the
	// system's momentum replayed at the frames' times): UiWindow's on macOS
	// (false: each scroll as a wheel's)
	public var elastic = false;
	// a touchpad's scrolls as GTK's kinetic scrolling takes them (Trackpad:
	// one scroller a gesture, our glide once the fingers lift, a bounce at an
	// end): UiWindow's on Linux's Wayland, whose touchpads say when they lift
	public var kinetic = false;
	final trackpad:Trackpad;
	// (the scroller a wheel latched to and its last scroll's time: Chromium's half a second)
	var wheelLatch:Null<Node> = null;
	var wheelAt = -1e9;
	static inline var WHEEL_LATCH = 0.5;

	// a touch's drag past a scroller's end stretches it, as Android 12's
	// (Stretch: UiWindow's on Android)
	public var stretch = false;
	final stretcher:Stretch;
	// (the last wheel's scroller and what it could not scroll, past its end: Stretch's)
	var overNode:Null<Node> = null;
	var overX = 0.0;
	var overY = 0.0;

	function wheelNow(x:Float, y:Float, deltaX:Float, deltaY:Float, eased:Bool, mods = -1, phase = 0, momentum = 0, time = 0.0) {
		overNode = null;
		overX = overY = 0;
		var phased = (elastic || kinetic) && (phase != 0 || momentum != 0) && (mods >= 0 ? mods : this.mods) & Key.MOD_CONTROL == 0;
		var target = hit(x, y);
		if (phased) {
			// (the tree hears the moves, the momentum's too, and may keep them: no scroll then)
			if (target != null && (deltaX != 0 || deltaY != 0)) {
				var e = Event.of(Wheel, target, x, y);
				e.mods = mods >= 0 ? mods : this.mods;
				e.deltaX = deltaX;
				e.deltaY = deltaY;
				bubble(e);
				if (e.defaultPrevented) return;
			}
			@:privateAccess trackpad.scroll(x, y, deltaX, deltaY, phase, momentum, time);
			return;
		}
		if (target == null) return;
		var e = Event.of(Wheel, target, x, y);
		e.mods = mods >= 0 ? mods : this.mods;
		e.deltaX = deltaX;
		e.deltaY = deltaY;
		e.eased = eased;
		bubble(e);
		if (e.defaultPrevented) return;
		// (a wheel's scrolls latched to the scroller it moved until it rests half a second, as Chromium's: not
		// into one it passes over, nor out of it at its end)
		var latched = wheelLatch != null && now() - wheelAt < WHEEL_LATCH && contains(root, wheelLatch) ? wheelLatch : null;
		wheelAt = now();
		if (latched != null) {
			if (Scrolling.canScroll(latched, deltaX, true) || Scrolling.canScroll(latched, deltaY, false))
				Scrolling.wheel(this, latched, deltaX, deltaY, eased);
			else {
				// (at its end: all of it past that end, Stretch's)
				overNode = latched;
				overX = deltaX;
				overY = deltaY;
			}
			return;
		}
		Scrolling.wheel(this, target, deltaX, deltaY, eased);
		wheelLatch = Scrolling.wheelNode;
	}

	// whether a wheel at x, y by deltaX, deltaY would scroll something: a
	// scroller under the point (the innermost first) not at its end that
	// way (a touch drag's question, helder.os's Window.scrollsAt: UiWindow).
	// A node there, or around it, that follows the pointer's moves
	// (onPointerMove: a slider, a timeline, a field things are dragged
	// over) takes the drag too: in a browser whose canvas pans the page,
	// the page would take it from it otherwise (the pointer cancelled)
	public function scrollsAt(x:Float, y:Float, deltaX:Float, deltaY:Float):Bool {
		var n = hit(x, y);
		// (the platform's scroll views scroll the scrollers: only a node following the pointer takes the drag)
		if (!nativeScroll && Scrolling.scrollsAt(this, n, deltaX, deltaY)) return true;
		while (n != null) {
			if (n.onPointerMove != null) return true;
			n = n.parent;
		}
		return false;
	}

	// --- keyboard ---

	// the text selected in a selectable TextNode (null: none), anchor to
	// caret (UTF-16 indices of its whole text); a press elsewhere drops it
	public var textSelection(default, null):Null<{node:TextNode, anchor:Int, caret:Int}> = null;
	// what a selection is painted with
	public var selectionColor:Color = Color.rgba(0x3b82f6, 0.3);
	// (a drag selecting; the clicks in a row and the last one's time and place)
	var selecting = false;
	var selClicks = 0;
	var selAt = -1e9;
	var selX = 0.0;
	var selY = 0.0;
	// the time (seconds; tests replace it)
	public static var now:Void->Float = haxe.Timer.stamp;

	// the event being handled's time on now's clock (pointerDown's, pointerMove's, pointerUp's at;
	// < 0: now's)
	var eventAt = -1.0;
	// (the least lag seen from an event's own clock to now's, between gestures: the two clocks' offset)
	var eventLag = 1e18;

	// an event's own time (ms, the system's clock: helder.os.Pointer.time) on now's clock, spaced as
	// the system spaced them (0: none known, now). The offset is the least lag seen while no finger
	// or pen is down; a gesture's events keep the one it started with, so one read sooner after it
	// happened than those before it (a lift read at once after moves a slow frame held back) is not
	// moved nearer to them: a flick's last interval, its speed, is the system's (with the least lag
	// taken as it came, Android's swipe on CI's emulator, its down and moves read a frame late and
	// its lift at once, had its lift a millisecond after its last move and glided to the end of the
	// list). Such a time may be after now, by as much as its lag is less.
	public function eventTime(ms:Float):Float {
		if (ms <= 0) return now();
		var lag = now() - ms / 1000;
		// (anew when the event's clock went back or jumped: a second off is none)
		if (Math.abs(lag - eventLag) > 1 || (lag < eventLag && !pressing())) eventLag = lag;
		return ms / 1000 + eventLag;
	}

	// whether a finger or a pen is down
	function pressing():Bool {
		for (d in pDown) if (d) return true;
		return false;
	}

	// the selected text (empty: none)
	public function selectedText():String {
		var s = textSelection;
		if (s == null || s.anchor == s.caret) return "";
		return s.node.allText().substring(Std.int(Math.min(s.anchor, s.caret)), Std.int(Math.max(s.anchor, s.caret)));
	}

	// a press on a selectable text (or a span of one): the selection starts,
	// a word on a double click, all of it on a triple; elsewhere it is dropped
	function selectAt(target:Null<Node>, x:Float, y:Float, button:Int) {
		var t:Null<TextNode> = null, n = target;
		// (a text selectable by its own flag, or by user-select text or all; none: not)
		while (n != null) {
			if (Std.isOfType(n, TextNode)) {
				var u = n.userSelect();
				if (u == Text || u == All || (cast n : TextNode).selectable && n.style.userSelect != None) t = cast n;
			}
			n = n.parent;
		}
		if (textSelection != null) textSelection.node.layerChanged();
		if (t == null || button != 1) {
			if (textSelection != null) {
				textSelection = null;
				requestFrame();
			}
			return;
		}
		var i = t.textIndexAt(x, y), time = now();
		selClicks = time - selAt < 0.45 && Math.abs(x - selX) < 5 && Math.abs(y - selY) < 5 ? selClicks + 1 : 1;
		selAt = time;
		selX = x;
		selY = y;
		var text = t.allText();
		if (selClicks == 2) {
			// (a word: letters, digits and marks around the index; else the one character)
			inline function word(c:Int):Bool
				return c == "_".code || (c >= "0".code && c <= "9".code) || (c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code) || c > 0x7F
					&& c != 0xA0 && c != 0x3000;
			var a = i, b = i;
			while (a > 0 && word(StringTools.fastCodeAt(text, a - 1)))
				a--;
			while (b < text.length && word(StringTools.fastCodeAt(text, b)))
				b++;
			if (a == b && b < text.length) b++;
			textSelection = {node: t, anchor: a, caret: b};
		} else if (selClicks >= 3 || t.userSelect() == All) textSelection = {node: t, anchor: 0, caret: text.length};
		else textSelection = {node: t, anchor: i, caret: i};
		selecting = selClicks == 1 && t.userSelect() != All;
		t.layerChanged();
		requestFrame();
	}

	// --- actions (helder.ui.actions) ---

	// the bindings its keys are matched against (default: the app's)
	public var keymap:helder.ui.actions.Keymap = helder.ui.actions.Keymap.global;
	// the window's handlers: after the tree's, before the app's
	public final actionHandlers:Array<helder.ui.actions.Actions.ActionHandler> = [];
	// the chord typed so far (a binding's first keystrokes: waiting for the
	// next, Keymap.timeout), what its keys alone run when it times out
	public final pendingKeys:Array<{key:Int, mods:Int}> = [];
	var pendingAction:Null<helder.ui.actions.Actions.Action> = null;
	var pendingFrom:Null<Node> = null;
	var pendingSerial = 0;

	// a window's handler of e's actions (Node.on's)
	public function on<T>(type:helder.ui.actions.Actions.ActionType<T>, handle:T->Bool, ?state:T->helder.ui.actions.Actions.ActionState):Void->Void {
		var h = helder.ui.actions.Actions.ActionHandler.of(type, handle, state);
		actionHandlers.push(h);
		return () -> actionHandlers.remove(h);
	}

	// a node's parent on the dispatch path: a popup's, the node it is
	// anchored to (else where the focus was when it opened)
	public static function parentOf(n:Node):Null<Node> {
		if (n.parent != null && Std.isOfType(n, Popup) && n.parent.parent == null) {
			var p:Popup = cast n;
			return p.anchor != null ? p.anchor : p.returnFocus;
		}
		return n.parent;
	}

	// the key contexts from the root to from (default: the focus), outermost first
	public function contextStack(?from:Node):Array<helder.ui.actions.KeyContext> {
		var out = [];
		var n = from != null ? from : focus != null ? focus : root;
		while (n != null) {
			if (n.keyContext != null) out.unshift(n.keyContext);
			n = parentOf(n);
		}
		return out;
	}

	// the handler that would take an action from (default: the focus), the
	// tree's up to the root, the window's, the app's (null: none)
	function handlerOf(a:helder.ui.actions.Actions.Action, from:Null<Node>):Null<helder.ui.actions.Actions.ActionHandler> {
		var n = from != null ? from : focus != null ? focus : root;
		while (n != null) {
			if (n.actionHandlers != null)
				for (h in n.actionHandlers)
					if (h.takes(a) && h.state(a) != Unhandled) return h;
			n = parentOf(n);
		}
		for (h in actionHandlers)
			if (h.takes(a) && h.state(a) != Unhandled) return h;
		for (h in helder.ui.actions.Actions.app)
			if (h.takes(a) && h.state(a) != Unhandled) return h;
		return null;
	}

	// what a menu shows an action as, from (default: the focus): the state
	// of the first handler on the path that takes it
	public function actionState(a:helder.ui.actions.Actions.Action, ?from:Node):helder.ui.actions.Actions.ActionState {
		var h = handlerOf(a, from);
		return h == null ? Unhandled : h.state(a);
	}

	// dispatches an action from (default: the focus) up the tree, then to
	// the window's and the app's handlers, until one takes it (true); a
	// disabled one's is not run
	public function dispatchAction(a:helder.ui.actions.Actions.Action, ?from:Node):Bool {
		inputEpoch++;
		var n = from != null ? from : focus != null ? focus : root;
		inline function tryAll(hs:Array<helder.ui.actions.Actions.ActionHandler>):Bool {
			var taken = false;
			for (h in hs.copy())
				if (h.takes(a)) {
					var st = h.state(a);
					if (st == Unhandled) continue;
					if (!st.enabled) {
						taken = true;
						break;
					}
					if (h.run(a)) {
						taken = true;
						break;
					}
				}
			return taken;
		}
		var done = false;
		while (n != null && !done) {
			if (n.actionHandlers != null && tryAll(n.actionHandlers)) done = true;
			n = parentOf(n);
		}
		if (!done && tryAll(actionHandlers)) done = true;
		if (!done && tryAll(helder.ui.actions.Actions.app)) done = true;
		if (done) {
			requestFrame();
			helder.view.graph.Graph.flush();
		}
		return done;
	}

	// a key through the keymap (true: taken: an action run, or a chord begun or continued)
	function runKeymap(key:Int, mods:Int):Bool {
		if (modOf(key) != 0) return false;
		var typing = focus != null && focus.takesText();
		var stack = contextStack();
		var typed = pendingKeys.copy();
		typed.push({key: key, mods: mods});
		var m = keymap.match(typed, stack);
		// (no binding goes on from the chord: it is dropped, the key tried alone)
		if (m.exact.length == 0 && !m.longer && pendingKeys.length > 0) {
			clearPending();
			typed = [{key: key, mods: mods}];
			m = keymap.match(typed, stack);
		}
		if (typed.length == 1 && typing && mods & (Key.MOD_CONTROL | Key.MOD_ALT | Key.MOD_META) == 0 && key < 0xFF00) return false;
		// (the best binding whose action some handler takes; an unbound one stops the search)
		var best:Null<helder.ui.actions.Actions.Action> = null, bestDepth = -1;
		for (b in m.exact) {
			if (b.action == null) break;
			if (handlerOf(b.action, null) != null) {
				best = b.action;
				bestDepth = b.depth(stack);
				break;
			}
		}
		if (m.longer && m.longerDepth >= bestDepth) {
			pendingKeys.resize(0);
			for (t in typed)
				pendingKeys.push(t);
			pendingAction = best;
			pendingFrom = focus;
			var serial = ++pendingSerial, start = -1.0;
			Clock.addTo(context, t -> {
				if (serial != pendingSerial) return false;
				if (start < 0) start = t;
				if (t - start < helder.ui.actions.Keymap.timeout) return true;
				var a = pendingAction, from = pendingFrom;
				clearPending();
				if (a != null) dispatchAction(a, from != null && from.ui == this ? from : null);
				return false;
			});
			requestFrame();
			return true;
		}
		clearPending();
		if (best == null) return false;
		dispatchAction(best);
		return true;
	}

	function clearPending() {
		pendingKeys.resize(0);
		pendingAction = null;
		pendingFrom = null;
		pendingSerial++;
	}

	// (an event: the graph's writes in it land at its end, helder.view.graph)
	public function keyDown(key:Int, mods:Int) {
		inputEpoch++;
		keyDownNow(key, mods);
		helder.view.graph.Graph.flush();
	}

	function keyDownNow(key:Int, mods:Int) {
		this.mods = mods | modOf(key);
		// (Escape during a drag: it ends, not dropped)
		if (dragging != null && key == Key.ESCAPE) {
			endDrag(false, pointerX, pointerY);
			return;
		}
		var e = Event.of(KeyDown, focus != null ? focus : root, pointerX, pointerY);
		e.key = key;
		e.mods = mods;
		bubble(e);
		if (!e.defaultPrevented && key == Key.ESCAPE) {
			// the topmost popup that can be dismissed
			var i = overlay.children.length;
			while (--i >= 0) {
				var p = Popups.at(this, i);
				if (p != null && p.onDismiss != null) {
					p.onDismiss();
					return;
				}
			}
		}
		if (!e.defaultPrevented && !e.stopped && runKeymap(key, mods)) return;
		if (!e.defaultPrevented && !e.stopped && Scrolling.keyScroll(this, key, mods)) return;
		// (Control or Command and C: the selected text copied, when the focus took no such key)
		if (!e.defaultPrevented && !e.stopped && (key == "c".code || key == "C".code) && mods & (Key.MOD_CONTROL | Key.MOD_META) != 0 && selectedText() != "") {
			clipboard.write(selectedText());
			return;
		}
		if (!e.defaultPrevented && key == Key.TAB) {
			// (shown before the focus moves: its handlers see it)
			focusVisible = true;
			moveFocus(mods & Key.MOD_SHIFT != 0 ? -1 : 1);
			focusVisible = focus != null;
			requestFrame();
		}
	}

	// how long a scroll by the keys eases (seconds; 0: at once)
	public var scrollDuration = 0.15;
	// (the scrollers' glides: a wheel's notches, the keys' scrolls)
	final glides = new Map<Node, ScrollGlide>();
	// the scrollers rounded by the last layouts, clamped after them
	final rounded:Array<Node> = [];

	// the platform's own scroll views drive the scrollers (UiWindow: iOS's
	// UIScrollView, the browser's elements): their physics, edges and
	// indicators; a finger's drag over one is theirs to take (nativeBegins),
	// what they scroll to the scrollers' (nativeScrolled), and TouchScroll,
	// helder's own, takes only the touches elsewhere. Off: helder's own
	// everywhere (a Surface's scrolling="helder")
	public var nativeScroll = false;
	// (the platform draws the scrollbars: the thumbs not drawn)
	public var nativeBars = false;
	// (a touch going down: the platform's scroll views stopped where one
	// glides, whether one did; the touch then clicks nothing, as on iOS)
	public var nativeHalt:Null<Void->Bool> = null;
	final scrollList:Array<ScrollView> = [];
	final scrollKept = new Map<Node, ScrollView>();
	var scrollPass = 0;

	// the scrollers the platform's scroll views mirror, after update (Scrolling.views)
	public function scrollViews():Array<ScrollView>
		return Scrolling.views(this);

	// whether a platform's drag at x, y moving the content's scroll by dx,
	// dy is n's (Scrolling.begins)
	public function nativeBegins(n:Node, x:Float, y:Float, dx:Float, dy:Float):Bool
		return Scrolling.begins(this, n, x, y, dx, dy);

	// a platform's scroll view moved n to its offsets x, y from its start
	// (an event: the graph's writes in it land at its end)
	public function nativeScrolled(n:Node, x:Float, y:Float) {
		Scrolling.moved(this, n, x, y);
		helder.view.graph.Graph.flush();
	}

	// (a pointer a recogniser of the tree won, but a Tap: its drag is the tree's)
	function gestureHeld():Bool {
		for (id in 0...POINTERS) {
			var w = winners[id];
			if (w != null && w != touchScroll && !Std.isOfType(w, Tap)) return true;
		}
		return false;
	}

	// the nodes changed since the last update, as far as layout goes (Node.markDirty;
	// more than Layout.CHANGES: all laid out again from the root)
	@:allow(helder.ui.Layout) final changes:Array<Node> = [];

	@:allow(helder.ui.Node) function changed(n:Node)
		if (changes.length <= @:privateAccess Layout.CHANGES) changes.push(n);

	// scrolls by dx, dy eased over scrollDuration (a scroll easing already: from where it is, to its end moved on)
	public function scrollBy(n:Node, dx:Float, dy:Float)
		Scrolling.scrollBy(this, n, dx, dy);

	// (an event: the graph's writes in it land at its end, helder.view.graph)
	public function keyUp(key:Int, mods:Int) {
		keyUpNow(key, mods);
		helder.view.graph.Graph.flush();
	}

	function keyUpNow(key:Int, mods:Int) {
		this.mods = mods & ~modOf(key);
		var e = Event.of(KeyUp, focus != null ? focus : root, pointerX, pointerY);
		e.key = key;
		e.mods = mods;
		bubble(e);
	}

	// (an event: the graph's writes in it land at its end, helder.view.graph)
	public function textInput(text:String) {
		textInputNow(text);
		helder.view.graph.Graph.flush();
	}

	function textInputNow(text:String) {
		if (text.length == 0) return;
		var e = Event.of(TextInput, focus != null ? focus : root, pointerX, pointerY);
		e.text = text;
		bubble(e);
	}

	// an input method's composition (empty: it ended), caret in it: to the focus
	// (an event: the graph's writes in it land at its end, helder.view.graph)
	public function composition(text:String, caret:Int) {
		compositionNow(text, caret);
		helder.view.graph.Graph.flush();
	}

	function compositionNow(text:String, caret:Int) {
		var e = Event.of(Composition, focus != null ? focus : root, pointerX, pointerY);
		e.text = text;
		e.caret = caret;
		bubble(e);
	}

	// an input method's edit of the text around the caret (the focus's
	// textContext): start...end replaced by text
	// (an event: the graph's writes in it land at its end, helder.view.graph)
	public function replaceText(start:Int, end:Int, text:String) {
		if (focus != null) focus.replaceText(start, end, text) else textInputNow(text);
		helder.view.graph.Graph.flush();
	}

	// the focus's text around its caret, for the input method (null: none)
	public function textContext():Null<{text:String, start:Int, end:Int, multiline:Bool, secret:Bool}>
		return focus == null ? null : focus.textContext();

	// what the focus takes for the system's keyboard (null: it takes no text)
	public function textKind():Null<helder.os.TextKind>
		return focus == null ? null : focus.textKind();

	// where text is typed now (the focused node's caret, window pixels): the
	// input method's place; null: the focus takes no text
	public function textInputArea():Null<{x:Float, y:Float, width:Float, height:Float}>
		return focus == null ? null : focus.textInputArea();

	// the modifier a modifier key is (0: none)
	static function modOf(key:Int):Int
		return switch key {
			case Key.SHIFT | 0xFFE2: Key.MOD_SHIFT;
			case Key.CONTROL | 0xFFE4: Key.MOD_CONTROL;
			case Key.ALT | 0xFFEA: Key.MOD_ALT;
			case Key.META | 0xFFE8 | 0xFFEB | 0xFFEC: Key.MOD_META;
			case _: 0;
		}

	// --- focus ---

	// the focus moved to n (null: none); scroll: n brought into view in its
	// scrolling ancestors (not when a press focused it)
	public function setFocus(n:Null<Node>, scroll = true) {
		inputEpoch++;
		if (n == focus) return;
		accessEpoch++;
		if (scroll && n != null) scrollIntoView(n);
		var old = focus;
		focus = n;
		// (the focus ring drawn around it)
		if (old != null) old.layerChanged();
		if (n != null) n.layerChanged();
		if (old != null) {
			@:privateAccess old.setState(old.hovered, old.pressed, false);
			if (old.onBlur != null) old.onBlur(Event.of(Blur, old, pointerX, pointerY));
			bubble(Event.of(FocusOut, old, pointerX, pointerY));
		}
		if (n != null) {
			@:privateAccess n.setState(n.hovered, n.pressed, true);
			if (n.onFocus != null) n.onFocus(Event.of(Focus, n, pointerX, pointerY));
			bubble(Event.of(FocusIn, n, pointerX, pointerY));
		}
		// (the handles on either path: focused, within)
		var p = old;
		while (p != null) {
			if (p.focusHandle != null) {
				p.focusHandle.focused(false);
				p.focusHandle.within(false);
			}
			p = parentOf(p);
		}
		p = n;
		while (p != null) {
			if (p.focusHandle != null) {
				p.focusHandle.focused(p == n);
				p.focusHandle.within(true);
			}
			p = parentOf(p);
		}
	}

	// the next (1) or previous (-1) focusable node in tree order, wrapping
	// (only: of those, the ones it says)
	public function moveFocus(dir:Int, ?only:Node->Bool) {
		var all:Array<Node> = [];
		function collect(n:Node) {
			if (n.style.display == None) return;
			if (n.focusable && n.visible() && (only == null || n == focus || only(n))) all.push(n);
			for (c in n.children)
				collect(c);
		}
		// (in the topmost modal popup only; else the tree, then the popups)
		var m = Popups.modal(this);
		if (m != null) collect(m) else {
			collect(root);
			collect(overlay);
		}
		// (tabIndex: above 0 first in its order, then 0's in tree order; below 0 left out)
		var ordered = [for (n in all) if (n.tabIndex > 0) n];
		haxe.ds.ArraySort.sort(ordered, (a, b) -> a.tabIndex - b.tabIndex);
		for (n in all)
			if (n.tabIndex == 0) ordered.push(n);
		if (focus != null && focus.tabIndex < 0 && all.contains(focus)) {
			// (from a node Tab passes over: on from its place in the tree)
			var at = all.indexOf(focus), next:Null<Node> = null;
			var k = at;
			for (_ in 1...all.length) {
				k = (k + dir + all.length) % all.length;
				if (all[k].tabIndex >= 0) {
					next = all[k];
					break;
				}
			}
			if (next != null) setFocus(next);
			return;
		}
		all = ordered;
		if (all.length == 0) return;
		var i = focus == null ? (dir > 0 ? -1 : 0) : all.indexOf(focus);
		setFocus(all[(i + dir + all.length) % all.length]);
	}

	// --- popups (Popups) ---

	// shows a popup over the tree, above those open; a modal one covers the
	// window (its content centred) and takes the focus (its first focusable node)
	public function open(p:Popup)
		Popups.open(this, p);

	// removes a popup; the focus, if it was inside, goes back to where it was when it opened
	public function close(p:Popup)
		Popups.close(this, p);

	// what a press at x, y is to an inset title bar (helder.os's
	// Window.titlebarAt): the nearest of the node there and its ancestors
	// with an answer of its own (drag-region, WindowControls' buttons),
	// unless something that takes presses comes first (a button in a drag
	// region stays a button)
	public function titleHit(x:Float, y:Float):helder.os.TitleBar.TitleHit {
		var n = hit(x, y);
		while (n != null) {
			if (n.titleHit != helder.os.TitleBar.TitleHit.Content) return n.titleHit;
			if (n.focusable || n.onClick != null || n.onActivate != null || n.onPointerDown != null || n.onDragStart != null) return helder.os.TitleBar.TitleHit.Content;
			n = n.parent;
		}
		return helder.os.TitleBar.TitleHit.Content;
	}

	// the topmost node under a point: in the popups (a modal one stops the
	// search: what is under it is covered), then the tree
	function hit(x:Float, y:Float):Null<Node> {
		var i = overlay.children.length;
		while (--i >= 0) {
			var c = overlay.children[i];
			var h = c.hitTest(x, y);
			if (h != null) return h;
			if (Std.isOfType(c, Popup) && (cast c : Popup).modal) return null;
		}
		return root.hitTest(x, y);
	}

	// --- internals ---

	function bubble(e:Event) {
		var n = e.target;
		while (n != null && !e.stopped) {
			var h = switch e.type {
				case PointerDown: n.onPointerDown;
				case PointerUp: n.onPointerUp;
				case PointerMove: n.onPointerMove;
				case PointerCancel: n.onPointerCancel;
				case Click: n.onClick;
				case Wheel: n.onWheel;
				case KeyDown: n.onKeyDown;
				case KeyUp: n.onKeyUp;
				case TextInput: n.onTextInput;
				case Composition: n.onComposition;
				case DragStart: n.onDragStart;
				case DragEnd: n.onDragEnd;
				case FocusIn: n.onFocusIn;
				case FocusOut: n.onFocusOut;
				case _: null;
			}
			if (h != null) h(e.at(n));
			// (a press: after the click, or Enter or Space the key handlers left; a link's Enter only, as a browser's)
			var press = n.onActivate;
			if (press != null && !e.stopped && (e.type == Click || e.type == KeyDown && !e.defaultPrevented
				&& (e.key == Key.ENTER || e.key == Key.SPACE && (n.semantics == null || n.semantics.role != helder.ui.access.Role.Link)))) {
				if (e.type == KeyDown) e.preventDefault();
				press(e.at(n));
			}
			n = n.parent;
		}
	}

	function setHover(target:Null<Node>) {
		if (target == hover) return;
		// leave the old path up to the common ancestor, enter the new one
		var old:Array<Node> = [], now:Array<Node> = [];
		var n = hover;
		while (n != null) {
			old.push(n);
			n = n.parent;
		}
		n = target;
		while (n != null) {
			now.push(n);
			n = n.parent;
		}
		hover = target;
		for (o in old)
			if (!now.contains(o)) {
				@:privateAccess o.setState(false, o.pressed, o.focused);
				if (o.onPointerLeave != null) o.onPointerLeave(Event.of(PointerLeave, o, pointerX, pointerY));
			}
		var i = now.length;
		while (--i >= 0) {
			var o = now[i];
			if (!old.contains(o)) {
				@:privateAccess o.setState(true, o.pressed, o.focused);
				if (o.onPointerEnter != null) o.onPointerEnter(Event.of(PointerEnter, o, pointerX, pointerY));
			}
		}
	}

	function setPressed(target:Node, on:Bool) {
		var n = target;
		while (n != null) {
			@:privateAccess n.setState(n.hovered, on, n.focused);
			n = n.parent;
		}
	}

	static function contains(ancestor:Node, n:Node):Bool {
		while (n != null) {
			if (n == ancestor) return true;
			n = n.parent;
		}
		return false;
	}

	// the pointer's shape: the style of the node under it (or that has it
	// captured), Auto taking the parent's; Default over a scrollbar's drag
	public function cursor():Cursor {
		if (drag != null) return Default;
		var n = capture != null ? capture : hover;
		while (n != null) {
			if (n.style.cursor != Auto) return n.style.cursor;
			n = n.parent;
		}
		return Default;
	}

	// --- accessibility ---

	var lastAccess:Null<helder.ui.access.AccessTree>;

	// the accessibility tree now (after update): what accessAction acts in
	// (built again only when something it reads changed: accessEpoch)
	public function accessTree():helder.ui.access.AccessTree {
		if (lastAccess != null && accessBuilt == accessEpoch) return lastAccess;
		accessBuilt = accessEpoch;
		return lastAccess = helder.ui.access.AccessTree.build(this);
	}

	// bumped by every change an accessibility tree reads (layout, scrolling,
	// the focus, semantics, focusability, transforms, opacity to 0 and back)
	public static var accessEpoch = 0;
	var accessBuilt = -1;

	// assistive technology's request on a node of the last accessTree():
	// false when the node is gone or does not take it
	// (an event: the graph's writes in it land at its end, helder.view.graph)
	public function accessAction(id:Int, action:helder.ui.access.AccessAction, ?value:String):Bool {
		var r = accessActionNow(id, action, value);
		helder.view.graph.Graph.flush();
		// (a frame: what it changed drawn, the adapters told)
		if (r) requestFrame();
		return r;
	}

	function accessActionNow(id:Int, action:helder.ui.access.AccessAction, ?value:String):Bool {
		var n = lastAccess == null ? null : lastAccess.node(id);
		if (n == null || n.ui != this) return false;
		switch action {
			case Click:
				var x = n.absX + n.width / 2, y = n.absY + n.height / 2;
				bubble(Event.of(Click, n, x, y));
			case Focus:
				if (!n.focusable) return false;
				focusVisible = true;
				setFocus(n);
				requestFrame();
			case Increment | Decrement:
				if (n.focusable) setFocus(n);
				keyDown(action == Increment ? Key.RIGHT : Key.LEFT, 0);
			case SetValue:
				if (value == null) return false;
				// (a range's: stepped toward it as its keys step it, until there or past it)
				var sem = n.semantics;
				if (n.accessText() == null && sem != null && sem.valueNow != null) {
					var target = Std.parseFloat(value);
					if (Math.isNaN(target) || sem.role == helder.ui.access.Role.ProgressIndicator) return false;
					if (n.focusable) setFocus(n);
					for (_ in 0...1000) {
						var now:Null<Float> = sem.valueNow;
						if (now == null || Math.abs(now - target) < 1e-9) break;
						var up = target > now;
						keyDown(up ? Key.RIGHT : Key.LEFT, 0);
						helder.view.graph.Graph.flush();
						var after:Null<Float> = sem.valueNow;
						if (after == null || after == now || (up ? after >= target : after <= target)) break;
					}
					return true;
				}
				if (!n.accessSetValue(value)) return false;
			// (the node's state now: another action may have changed it since the tree)
			case Expand | Collapse:
				var e = n.semantics == null ? null : n.semantics.expanded;
				if (e == null) return false;
				if (e != (action == Expand)) {
					var x = n.absX + n.width / 2, y = n.absY + n.height / 2;
					bubble(Event.of(Click, n, x, y));
				}
			case Select:
				var sel = n.semantics == null ? null : n.semantics.selected;
				if (sel == null) return false;
				if (!sel) bubble(Event.of(Click, n, n.absX + n.width / 2, n.absY + n.height / 2));
			case ScrollIntoView:
				scrollIntoView(n);
				requestFrame();
			case SetSelection:
				var t = n.accessText(), parts = value == null ? [] : value.split(",");
				if (t == null || parts.length != 2) return false;
				var s = Std.parseInt(parts[0]), e = Std.parseInt(parts[1]);
				if (s == null || e == null) return false;
				if (n.focusable && focus != n) setFocus(n);
				n.select(s, e);
		}
		return true;
	}

	// scrolls n's scrolling ancestors, nearest first, as little as brings it
	// into each one's view (its far edge at the view's, unless it is larger)
	public function scrollIntoView(n:Node)
		Scrolling.scrollIntoView(this, n);

	// --- scrollbars (Scrolling) ---

	// scrolls n (an overflow: scroll node) to x, y (clamped to what it can scroll)
	public function scrollTo(n:Node, x:Float, y:Float) {
		Scrolling.stopGlide(this, n);
		Scrolling.setScroll(this, n, true, x);
		Scrolling.setScroll(this, n, false, y);
	}

	// a node left the tree: it no longer hovers, captures or has the focus
	@:allow(helder.ui.Node) function setBody(n:Node) {
		body = n;
		@:privateAccess overlay.inheritedChanged();
	}

	@:allow(helder.ui.Node) function detached(n:Node) {
		if (n == body) {
			body = null;
			@:privateAccess overlay.inheritedChanged();
		}
		if (hover != null && contains(n, hover)) hover = null;
		if (capture != null && contains(n, capture)) capture = null;
		// (its pointers' presses cancelled, its recognisers out of the arenas)
		for (id in 1...POINTERS)
			if (pDown[id] && pTarget[id] != null && contains(n, pTarget[id])) cancelPress(id);
		for (id in 0...POINTERS) {
			if (arenas[id].length == 0) continue;
			for (g in arenas[id].copy())
				if (g.node != null && contains(n, g.node)) g.cancel();
		}
		if (drag != null && contains(n, drag)) drag = null;
		if (focus != null && contains(n, focus)) focus = null;
		if (@:privateAccess trackpad.node != null && contains(n, @:privateAccess trackpad.node)) @:privateAccess trackpad.reset();
		if (@:privateAccess stretcher.node != null && contains(n, @:privateAccess stretcher.node)) @:privateAccess stretcher.reset();
		for (g in [for (k in glides.keys()) if (contains(n, k)) k])
			glides.remove(g);
	}
}

// (a Ui's walks' host: what a layer's list leaves to the Ui that recorded it)
private class UiWalk implements helder.ui.draw.Walk.WalkHost {
	final ui:Ui;

	public function new(ui:Ui)
		this.ui = ui;

	public function layer(l:Layer, c:Canvas, w:Walk)
		@:privateAccess ui.walkLayer(l, c, w);

	public function bars(n:Node, nw:Float, nh:Float, c:Canvas, w:Walk)
		@:privateAccess ui.walkBars(n, nw, nh, c, w);

	public function first(n:Node, entering:Bool)
		@:privateAccess ui.firstPaint(n, entering);

	public function flight(n:Node, x:Float, y:Float) {
		@:privateAccess ui.flights.push(n);
		@:privateAccess ui.flightAt.push(x);
		@:privateAccess ui.flightAt.push(y);
	}

	public function flights(c:Canvas, w:Walk)
		@:privateAccess ui.walkFlights(c, w);
}

// (what the first walk draws onto: nothing; where what it would draw
// lands in the window followed (its translations and transforms, the
// bounds of its clips, its opacity), so that the damage a window keeping
// its frame draws is found there: what it is told (add), GPU textures)
private class Nowhere implements TextureCanvas {
	public var a = 1.0;
	public var b = 0.0;
	public var c = 0.0;
	public var d = 1.0;
	public var e = 0.0;
	public var f = 0.0;
	public var alpha = 1.0;
	public var found:Null<Damage> = null;
	// (the last bounds found: bound)
	public var bx0 = 0.0;
	public var by0 = 0.0;
	public var bx1 = 0.0;
	public var by1 = 0.0;
	var cx0 = 0.0;
	var cy0 = 0.0;
	var cx1 = 0.0;
	var cy1 = 0.0;
	final matrices:Array<Float> = [];
	final clips:Array<Float> = [];
	final alphas:Array<Float> = [];

	public function new() {}

	public function reset(w:Float, h:Float, damage:Null<Damage>) {
		a = d = alpha = 1;
		b = c = e = f = cx0 = cy0 = 0;
		cx1 = w;
		cy1 = h;
		matrices.resize(0);
		clips.resize(0);
		alphas.resize(0);
		found = damage;
	}

	// (a box's bounds in the window, within the clip: bx0, by0, bx1, by1)
	public function bound(x0:Float, y0:Float, x1:Float, y1:Float) {
		var ax = a * x0 + c * y0, bx = a * x1 + c * y0, cx = a * x0 + c * y1, dx = a * x1 + c * y1;
		var ay = b * x0 + d * y0, by = b * x1 + d * y0, cy = b * x0 + d * y1, dy = b * x1 + d * y1;
		bx0 = Math.max(cx0, Math.min(Math.min(ax, bx), Math.min(cx, dx)) + e);
		by0 = Math.max(cy0, Math.min(Math.min(ay, by), Math.min(cy, dy)) + f);
		bx1 = Math.min(cx1, Math.max(Math.max(ax, bx), Math.max(cx, dx)) + e);
		by1 = Math.min(cy1, Math.max(Math.max(ay, by), Math.max(cy, dy)) + f);
	}

	public function add(x0:Float, y0:Float, x1:Float, y1:Float) {
		if (found == null) return;
		bound(x0, y0, x1, y1);
		found.add(bx0, by0, bx1, by1);
	}

	public function translate(dx:Float, dy:Float) {
		e += a * dx + c * dy;
		f += b * dx + d * dy;
	}

	public function pushClip(x:Float, y:Float, w:Float, h:Float, radius:Float, ?corners:Corners) {
		clips.push(cx0);
		clips.push(cy0);
		clips.push(cx1);
		clips.push(cy1);
		bound(x, y, x + w, y + h);
		cx0 = bx0;
		cy0 = by0;
		cx1 = bx1;
		cy1 = by1;
	}

	public function popClip() {
		var k = clips.length - 4;
		if (k < 0) return;
		cx0 = clips[k];
		cy0 = clips[k + 1];
		cx1 = clips[k + 2];
		cy1 = clips[k + 3];
		clips.resize(k);
	}

	public function pushOpacity(alpha:Float) {
		alphas.push(this.alpha);
		this.alpha *= alpha;
	}

	public function pushGroup(alpha:Float, x:Float, y:Float, w:Float, h:Float)
		pushOpacity(alpha);

	public function popOpacity()
		if (alphas.length > 0) alpha = alphas.pop();

	public function pushTransform(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float) {
		var m = matrices;
		m.push(this.a);
		m.push(this.b);
		m.push(this.c);
		m.push(this.d);
		m.push(this.e);
		m.push(this.f);
		var na = this.a * a + this.c * b, nb = this.b * a + this.d * b, nc = this.a * c + this.c * d, nd = this.b * c + this.d * d;
		this.e += this.a * e + this.c * f;
		this.f += this.b * e + this.d * f;
		this.a = na;
		this.b = nb;
		this.c = nc;
		this.d = nd;
	}

	public function popTransform() {
		var m = matrices, k = m.length - 6;
		if (k < 0) return;
		a = m[k];
		b = m[k + 1];
		c = m[k + 2];
		d = m[k + 3];
		e = m[k + 4];
		f = m[k + 5];
		m.resize(k);
	}

	public function rect(x:Float, y:Float, w:Float, h:Float, radius:Float, fill:Color, borderWidth:Float, border:Color, ?corners:Corners, ?sides:Edges,
		style:BorderStyle = Solid) {}

	public function shadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float, ?corners:Corners, ?offset:Array<Float>) {}

	public function insetShadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float, dx:Float, dy:Float, spread:Float,
		?corners:Corners) {}

	public function path(p:Path, fill:Null<Paint>, ?stroke:Stroke) {}

	public function image(img:helder.image.Image, x:Float, y:Float, w:Float, h:Float, u0:Float, v0:Float, u1:Float, v1:Float, radius:Float,
		?corners:Corners) {}

	public function text(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, ?colors:Array<Color>) {}

	public function textShadow(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, blur:Float, ?colors:Array<Color>) {}

	// (drawn anew each frame: a <Scene>'s, a sprite box's)
	public function gpuTexture(t:helder.gfx.Texture, id:Int, x:Float, y:Float, w:Float, h:Float, radius:Float = 0.0, ?corners:Corners)
		add(x, y, x + w, y + h);

	public function pass(f:Any) {}

	public function layerTiles(l:Layer):Bool
		return false;

	public function keeps():Bool
		return false;

	public function damage(d:Damage) {}

	public function redraw(i:Int) {}
}
