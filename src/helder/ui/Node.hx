package helder.ui;

import helder.os.Rect;
import helder.gfx.Color;
import helder.ui.Event;
import helder.canvas.Matrix;

// A node of the UI tree: a box laid out by its parent's flexbox (Layout),
// drawn by a renderer (Canvas) and receiving events (Ui). Its children are
// in drawing order (the last on top). x, y, width and height are the
// layout's result in pixels, relative to the parent's border box (rounded
// to whole pixels: absX, absY are the window's), valid after Ui.update. A
// change to the tree or to a layout property of the style marks the node
// and its ancestors for layout; a paint property asks only for a frame.
// Subclasses with content (TextNode) measure it (measureContent) and draw it
// (paintContent).
// (helder.view's markup: its renderer, NodeRenderer)
@:rendered(helder.ui.view.NodeRenderer)
class Node implements Part #if ((hxmc.dev || helder.headless) && !macro) implements helder.view.Source.Located #end { #if ((hxmc.dev || helder.headless) && !macro) public var source:Null<helder.view.Source> = null; public var sourceComponent:Null<helder.view.Source.SourceComponent> = null; #end
	// its style (markup's style={...}; its style attributes over it: styleAttr): one Style, immutable, shared
	public var style(default, set):Style = Style.none;
	// its style resolved in its states, its theme and what it inherits from its parent: what layout, paint and
	// the rest of helder.ui read (the engine's typed style)
	public var used(default, null):helder.ui.box.BoxStyle;
	public var parent(default, null):Null<Node>;
	// (a leaf's: one empty array shared by all, replaced by its own when a child comes)
	public var children(default, null):Array<Node> = NO_CHILDREN;

	static final NO_CHILDREN:Array<Node> = [];
	// a name for debugging and markup (the element's name)
	public var tag:String;
	// the Ui this node's tree is attached to (null: detached)
	@:noCompletion public var ui(default, null):Null<Ui>;

	// the layout's result (Layout): relative to the parent, then absolute; rounded
	public var x(default, null) = 0.0;
	public var y(default, null) = 0.0;
	public var width(default, null) = 0.0;
	public var height(default, null) = 0.0;
	public var absX(default, null) = 0.0;
	public var absY(default, null) = 0.0;
	// the extent of the children past the padding box's origin (scrolling;
	// right to left: from its right edge, what overflows on the left)
	public var contentWidth(default, null) = 0.0;
	public var contentHeight(default, null) = 0.0;
	// Overflow Scroll: the children's offset (clamped by Ui to the content;
	// right to left, scrollX from 0 down: Ui.scrollStart)
	public var scrollX(default, set) = 0.0;
	public var scrollY(default, set) = 0.0;

	// events (Ui dispatches them; Event.stop() ends bubbling to the ancestors;
	// kept in a Handlers made when the first is set: most nodes have none)
	public var onPointerDown(get, set):Null<Event->Void>;
	public var onPointerUp(get, set):Null<Event->Void>;
	public var onPointerMove(get, set):Null<Event->Void>;
	public var onPointerEnter(get, set):Null<Event->Void>;
	public var onPointerLeave(get, set):Null<Event->Void>;
	// a pointer's press taken from it: the system cancelled it (a call, the
	// browser panning the page), its node left the tree, or a gesture took
	// it over (a scroller's drag): no click follows
	public var onPointerCancel(get, set):Null<Event->Void>;
	// it no longer has a pointer it had captured (the pointer's release or
	// cancel, releaseCapture, another node's capture)
	public var onLostPointerCapture(get, set):Null<Event->Void>;
	public var onClick(get, set):Null<Event->Void>;
	// a press: a click, or Enter or Space while it has the focus (after onKeyDown, unless it
	// prevented the default), as a DOM button's click (a link's: Enter, not Space, as a DOM link's)
	public var onPress(get, set):Null<Event->Void>;
	public var onWheel(get, set):Null<Event->Void>;
	public var onKeyDown(get, set):Null<Event->Void>;
	public var onKeyUp(get, set):Null<Event->Void>;
	public var onTextInput(get, set):Null<Event->Void>;
	// a text field's text changed by its user (Event.text: its text; the DOM's input)
	public var onInput(get, set):Null<Event->Void>;
	// Overflow Scroll: its scrollX or scrollY changed (the wheel, a thumb, clamping)
	public var onScroll(get, set):Null<Void->Void>;
	public var onComposition(get, set):Null<Event->Void>;
	public var onFocus(get, set):Null<Event->Void>;
	public var onBlur(get, set):Null<Event->Void>;
	// (bubbling: the focus coming into this node or one under it, or leaving)
	public var onFocusIn(get, set):Null<Event->Void>;
	public var onFocusOut(get, set):Null<Event->Void>;
	// its laid-out size changed, and when it was first laid out: after the
	// layout, the size its width and height (a 3D camera fitted to its box)
	public var onResize(get, set):Null<Event->Void>;
	// drag and drop: dragData makes it draggable (what its drag carries);
	// the handlers of a source (start, end) and of a target (over: call
	// preventDefault to accept; leave; drop)
	public var dragData(get, set):Dynamic;
	public var onDragStart(get, set):Null<Event->Void>;
	public var onDragOver(get, set):Null<Event->Void>;
	public var onDragLeave(get, set):Null<Event->Void>;
	public var onDrop(get, set):Null<Event->Void>;
	public var onDragEnd(get, set):Null<Event->Void>;
	// takes the keyboard focus when clicked or tabbed to
	public var focusable(default, set) = false;
	// takes the focus when it comes into a window (a dialog's first button, a
	// menu's first item: as the DOM's autofocus, wherever it is inserted)
	public var autofocus(default, set) = false;
	// whether its text can be selected (Ui.textSelection: a drag, a double
	// click a word, a triple a line, Shift extending; Mod+C copies it, Mod+A
	// selects all of it): a TextNode's with its spans; any other node's
	// texts all in one selection, as a document's (TextSelection: its scope,
	// the outermost such node)
	public var selectable(default, set) = false;
	// what it is to assistive technology (helder.ui.access.AccessTree)
	public var semantics(default, set):Null<helder.ui.access.Semantics> = null;
	// its id in the accessibility tree (0: none yet)
	@:allow(helder.ui.access) var accessId = 0;
	// the pointer is over it (or a descendant), the button is down on it, it has the focus
	public var hovered(default, null) = false;
	public var pressed(default, null) = false;
	public var focused(default, null) = false;
	// a legend (a page's legend element): its parent's first, as a fieldset's
	// rendered legend, no flex item (Layout: no gap after it in a column)
	public var legend = false;
	// the page's body: the node whose text the window's layers inherit, as a page's popups its body's (Ui.body)
	public var body(default, set) = false;

	function set_body(v:Bool):Bool {
		if (v == body) return v;
		body = v;
		if (v && ui != null) ui.setBody(this);
		return v;
	}

	// its subtree's theme: its tokens' values (null: its parent's, else the window's, Ui.theme)
	public var theme(default, set):Null<Theme> = null;
	// its states are its descendants' group states (a style's group: {...})
	public var group(default, set) = false;
	// what draws the controls of this subtree (Host: Auto, the parent's; Ui.hostOf)
	@:noCompletion public var host:Host = Auto;
	// what it is to the keymap (helder.ui.actions: "Editor mode=full"; markup's key-context)
	public var keyContext:Null<helder.ui.actions.KeyContext> = null;
	// its handlers of actions dispatched through it (on; markup's actions)
	@:noCompletion public var actionHandlers:Null<Array<helder.ui.actions.Actions.ActionHandler>> = null;
	// Tab's order among the focusable (as the DOM's tabindex): those above 0
	// first, in its order, then 0's in tree order; below 0: focusable by a
	// click or focus(), passed over by Tab
	public var tabIndex = 0;
	// the language of its text, inherited (null: the parent's; as HTML's lang,
	// a BCP 47 tag: "nl", "en-GB"): its words' hyphenation (Style.hyphens)
	public var lang(default, set):Null<String> = null;

	function set_lang(v:Null<String>):Null<String> {
		if (v == lang) return v;
		lang = v;
		inheritedChanged();
		return v;
	}
	// motion (helder.ui.motion.Motions): what it declares for itself and its
	// subtree (markup's motion="snappy"); the id a matched counterpart flies
	// from or to (matched="tile-3"); its subtree's changes without motion
	// (instant); kept against its parent's trailing edges while the parent's
	// size moves (ride: 1 across, 2 down, 3 both; markup's ride="trailing")
	public var motion(default, set):Null<helder.ui.motion.MotionSpec> = null;
	@:noCompletion public var matched(default, set):Null<String> = null;
	public var instant = false;
	// what a press on it is to an inset title bar (markup's drag-region: Drag;
	// WindowControls' buttons theirs), its ancestors' when Content (Ui.titleHit)
	@:noCompletion public var titleHit:helder.os.TitleBar.TitleHit = helder.os.TitleBar.TitleHit.Content;
	@:noCompletion public var ride(default, set) = 0;
	// its presented state: the tracks of what moves of it (made when first needed)
	@:noCompletion public var present(default, null):Null<helder.ui.motion.Present> = null;
	// its children that left and are still drawn until their exits settle (Motions), and a leaving node's old parent
	@:noCompletion public var exits(default, null):Null<Array<Node>> = null;
	@:noCompletion public var leftFrom(default, null):Null<Node> = null;
	// (inserted into a drawn parent: it enters as it is first drawn, Motions.enter)
	var entering = false;

	function set_motion(v:Null<helder.ui.motion.MotionSpec>):Null<helder.ui.motion.MotionSpec> {
		if (v != null) helder.ui.motion.Motions.enable();
		return motion = v;
	}

	function set_matched(v:Null<String>):Null<String> {
		if (v != null) helder.ui.motion.Motions.enable();
		if ((v == null) != (matched == null)) helder.ui.motion.Motions.matchedCount += v == null ? -1 : 1;
		return matched = v;
	}

	function set_ride(v:Int):Int {
		if (v != 0) helder.ui.motion.Motions.enable();
		return ride = v;
	}
	// (its FocusHandle, kept by the Ui)
	@:allow(helder.ui) var focusHandle:Null<FocusHandle> = null;
	var attrs:Null<Map<String, String>> = null;
	// (markup's style attributes, name and value in turn (parsed once for all the nodes given the same,
	// Attrs.styled); its style with them over it, what is resolved)
	var styleAttrs:Null<Array<Dynamic>> = null;
	var styled:Null<Style> = null;
	// (its states, Style.HOVER...; what it was resolved under: its parent's text, the theme passed down, its
	// group's states and what it inherits besides)
	var states = 0;
	var under:Null<helder.ui.flow.InlineBasicStyle> = null;
	var passed:Null<Theme> = null;
	var groupStates = 0;
	// (drawn since it came into a window: its entrance played then, Motions)
	@:allow(helder.ui) var drawn = false;
	// its background gradient (its style's backgroundImage) drawn at its size in the window's pixels, at most
	// GRADIENT_PIXELS of them (a large box's at a lower resolution, stretched over it: a gradient is smooth); null:
	// none
	@:noCompletion public function backgroundImage(scale:Float):Null<helder.image.Image> {
		var g = props().backgroundImage;
		if (g == null) return null;
		var area = width * height * scale * scale, k = area > GRADIENT_PIXELS ? scale * Math.sqrt(GRADIENT_PIXELS / area) : scale;
		var w = Std.int(Math.max(1, Math.round(width * k))), h = Std.int(Math.max(1, Math.round(height * k)));
		if (gradientImage == null || gradientOf != g || gradientW != w || gradientH != h) {
			gradientImage = g.render(w, h, k);
			gradientOf = g;
			gradientW = w;
			gradientH = h;
		}
		return gradientImage;
	}

	static inline var GRADIENT_PIXELS = 262144.0;

	var gradientImage:Null<helder.image.Image> = null;
	var gradientOf:Null<Gradient> = null;
	var gradientW = 0;
	var gradientH = 0;

	// (its style as painted while a motion moves its background, border colour or radius: NodePaint's)
	var scratch:Null<helder.ui.box.BoxStyle> = null;

	// layout state (Layout): unrounded results, the measure cache, dirty
	@:allow(helder.ui.Layout) var lx = 0.0;
	@:allow(helder.ui.Layout) var ly = 0.0;
	@:allow(helder.ui.Layout) var lw = 0.0;
	@:allow(helder.ui.Layout) var lh = 0.0;
	// (made when first stored to)
	@:allow(helder.ui.Layout) var cache:Null<haxe.ds.Vector<Float>> = null;
	@:allow(helder.ui.Layout) var dirty = true;
	// (laid out since its edges were last rounded; the unrounded box they were rounded from)
	@:allow(helder.ui.Layout) var relaid = true;
	@:allow(helder.ui.Layout) var rawX = 0.0;
	@:allow(helder.ui.Layout) var rawY = 0.0;
	@:allow(helder.ui.Layout) var rawW = 0.0;
	@:allow(helder.ui.Layout) var rawH = 0.0;
	// the bounds of what it and its subtree draw (measureInk), stale after a transform changed
	@:allow(helder.ui) var inkX0 = 0.0;
	@:allow(helder.ui) var inkY0 = 0.0;
	@:allow(helder.ui) var inkX1 = 0.0;
	@:allow(helder.ui) var inkY1 = 0.0;
	@:allow(helder.ui) var inkAll = false;
	@:allow(helder.ui) var inkStale = false;
	@:allow(helder.ui.Layout) var minContent = Math.NaN;
	// (what its last layout was given, to be laid out again in place: Layout.inPlace)
	@:allow(helder.ui.Layout) var performed = false;
	@:allow(helder.ui.Layout) var pKW = 0.0;
	@:allow(helder.ui.Layout) var pKH = 0.0;
	@:allow(helder.ui.Layout) var pPW = 0.0;
	@:allow(helder.ui.Layout) var pPH = 0.0;
	@:allow(helder.ui.Layout) var pAW = 0.0;
	@:allow(helder.ui.Layout) var pAH = 0.0;
	@:allow(helder.ui.Layout) var pLoose = false;
	// (its measures as they were when it changed: the cache's length then, -1
	// not all of them (some dropped or never kept, or measured again since);
	// its min-content; lossy: some measure since not in the cache)
	@:allow(helder.ui.Layout) var cacheWas = -1;
	@:allow(helder.ui.Layout) var minContentWas = Math.NaN;
	@:allow(helder.ui.Layout) var lossy = false;
	// (a row's items' baseline, those aligned on it, below its top; NaN: none)
	@:allow(helder.ui.Layout) var lb = Math.NaN;

	public function new(?tag:String) {
		this.tag = tag == null ? "view" : tag;
		used = Resolve.of(Style.none, 0, Resolve.root, Theme.base, kind());
	}

	// --- style ---

	// (how it resolves: a view, a text (TextNode's))
	function kind():Int
		return Resolve.VIEW;

	function set_style(v:Style):Style {
		if (v == style) return v;
		style = v;
		styleChanged();
		return v;
	}

	// A style attribute (markup's: padding={8}, color="#3b82f6"), over its style; false: no such attribute.
	public function styleAttr(name:String, value:Dynamic):Bool {
		if (!Attrs.styles(name)) return false;
		var a = styleAttrs ??= [], i = 0;
		while (i < a.length && a[i] != name) i += 2;
		if (i < a.length) {
			if (a[i + 1] == value) return true;
			a[i + 1] = value;
		} else {
			a.push(name);
			a.push(value);
		}
		styleChanged();
		return true;
	}

	// (its style and attributes, interned: resolved again where they changed)
	function styleChanged() {
		var next = styleAttrs == null ? style : Attrs.styled(style, styleAttrs);
		if (next == styled) return;
		styled = next;
		resolve(under ?? Resolve.root, passed ?? Theme.base, groupStates);
	}

	// what its style says now, its states' variants over it (what helder.ui reads that the engine's style has not)
	public function props():Style.Props
		return (styled ??= styleAttrs == null ? style : Attrs.styled(style, styleAttrs)).at(states | groupStates << Style.GROUP, scope().dark);

	// A state on or off: Style.HOVER, PRESSED, FOCUS, DISABLED, SELECTED, CHECKED, PLACEHOLDER.
	public function state(bit:Int, on:Bool) {
		var next = on ? states | bit : states & ~bit;
		if (next == states) return;
		states = next;
		resolve(under ?? Resolve.root, passed ?? Theme.base, groupStates);
	}

	public inline function has(bit:Int):Bool
		return states & bit != 0;

	function set_theme(t:Null<Theme>):Null<Theme> {
		if (t == theme) return t;
		theme = t;
		resolve(under ?? Resolve.root, passed ?? Theme.base, groupStates);
		return t;
	}

	function set_group(g:Bool):Bool {
		if (g == group) return g;
		group = g;
		resolve(under ?? Resolve.root, passed ?? Theme.base, groupStates);
		return g;
	}

	// its subtree's theme: its own (in the window's tone, dark or light: the one passed down's), else the one passed down
	public inline function scope():Theme
		return theme == null ? passed ?? Theme.base : theme.tone((passed ?? Theme.base).dark);

	// (what its children inherit with its group's states: whether the pointer passes through it)
	inline function groupBelow():Int
		return (group ? states : groupStates & ~(Style.PASS | Style.HIDE)) | (used.rare.pointerEvents == "none" ? Style.PASS : 0)
			| (used.visible ? 0 : Style.HIDE);

	// (its style resolved under what it inherits, then its children's where what they inherit changed)
	@:allow(helder.ui) function resolve(text:helder.ui.flow.InlineBasicStyle, theme:Theme, group:Int) {
		under = text;
		passed = theme;
		groupStates = group;
		styled ??= styleAttrs == null ? style : Attrs.styled(style, styleAttrs);
		var s = Resolve.of(styled, states | group << Style.GROUP, text, scope(), kind()), was = used;
		if (s != was) restyled(was, s);
		var t = s.text, th = scope(), below = groupBelow();
		for (c in children) if (c.under != t || c.passed != th || c.groupStates != below) c.resolve(t, th, below);
		if (ui != null && this == ui.body && ui.overlay.under != t) ui.overlay.resolve(t, th, ui.overlay.groupStates);
	}

	// (another resolved style: what the change takes, by Resolve.level)
	function restyled(was:helder.ui.box.BoxStyle, now:helder.ui.box.BoxStyle) {
		used = now;
		// (what eases, from where it is drawn: Motions' tracks)
		if (helder.ui.motion.Motions.on) helder.ui.motion.Motions.restyled(this, was, now);
		else if (props().transition != null) {
			helder.ui.motion.Motions.enable();
			helder.ui.motion.Motions.restyled(this, was, now);
		}
		var level = Resolve.level(was, now);
		if (was.text != now.text) {
			fontCache = null;
			textBits = -1;
		}
		if (level == Resolve.LAYOUT) {
			markDirty();
			// (its parent's layout reads its style: margins, flex, position...)
		} else if (level != Resolve.NOTHING) paintChanged();
		if (was.none != now.none && parent != null) parent.markDirty();
	}


	// --- the tree ---

	public function append(child:Node):Node
		return insert(child, children.length);

	// child at index (moved if it is already a child of this node)
	public function insert(child:Node, index:Int):Node {
		if (child == this) throw "Node: a node is not its own child";
		var p:Node = this;
		while (p != null) {
			if (p == child) throw "Node: a node is not inside itself";
			p = p.parent;
		}
		var first = children.length > 0 ? children[0] : null, last = children.length > 0 ? children[children.length - 1] : null;
		var motions = helder.ui.motion.Motions.on;
		if (child.parent == this) {
			var i = indexOf(child);
			children.splice(i, 1);
			if (i < index) index--;
		} else if (child.parent != null) {
			child.parent.take(child, false);
			// (laid out in another parent: no motion from where it was there)
			if (motions) child.drawnAt = -1;
		}
		if (index < 0 || index > children.length) index = children.length;
		if (children == NO_CHILDREN) children = [];
		children.insert(index, child);
		var moved = child.parent != this;
		child.parent = this;
		child.attach(ui);
		// (under another parent: what it inherits may differ)
		if (moved) child.resolve(used.text, scope(), groupBelow());
		// (entering, or revived while it was leaving)
		if (motions && moved) helder.ui.motion.Motions.inserted(this, child);
		markDirty();
		return child;
	}

	// the index of a child (-1: not one), looked for from the end, where
	// anchors and new children usually are
	public function indexOf(child:Node):Int {
		if (child.parent != this) return -1;
		var i = children.length;
		while (--i >= 0)
			if (children[i] == child) return i;
		return -1;
	}

	// puts nodes, all children of this node and as many as the children from
	// start, in that order from start (a keyed list's rows, reordered at once)
	public function reorder(start:Int, nodes:Array<Node>) {
		if (start < 0 || start + nodes.length > children.length) throw "Node.reorder: out of range";
		var changed = false;
		for (k in 0...nodes.length) {
			var n = nodes[k];
			if (n.parent != this) throw "Node.reorder: not a child";
			if (children[start + k] != n) {
				children[start + k] = n;
				changed = true;
			}
		}
		if (changed) markDirty();
	}

	public function remove(child:Node)
		take(child, true);

	// (child taken out; leave: as it leaves the tree, its exit played (Motions), not moved to another parent)
	function take(child:Node, leave:Bool) {
		if (child.parent != this) return;
		var ghost = false;
		if (leave && helder.ui.motion.Motions.on) {
			// (inside a node leaving: kept as it was drawn)
			if (helder.ui.motion.Motions.inGhost(this)) return;
			ghost = helder.ui.motion.Motions.removing(this, child);
			if (!ghost) child.drawnAt = -1;
		}
		var first = children[0], last = children[children.length - 1], i = indexOf(child);
		children.splice(i, 1);
		child.parent = null;
		child.attach(null);
		markDirty();
	}

	public function removeChildren() {
		for (c in children) {
			c.parent = null;
			c.attach(null);
		}
		children.resize(0);
		markDirty();
	}

	@:allow(helder.ui.Ui) function attach(u:Null<Ui>) {
		if (ui == u) return;
		if (glassGroup != null) glassGroup.attach(u);
		if (ui != null) ui.detached(this);
		ui = u;
		// (what it recorded before not copied: it may have changed while out)
		paintedAt = -1;
		if (u != null && autofocus) u.setFocus(this, false);
		if (u != null && body) u.setBody(this);
		// (out of a window: drawn anew when back)
		if (u == null) drawn = false;
		for (c in children)
			c.attach(u);
		if (glassGroup != null) glassGroup.attached(u);
	}

	// --- changes ---

	// (what the accessibility tree reads: a change builds it again; a frame
	// asked for, as nothing else may: once the overlay bars faded, a program
	// setting its offset was never drawn, the compositor's mirror kept the last)
	// (a detached node's, the compositor's copies' (ScrollMirror) on its thread: none)
	function set_scrollX(v:Float):Float {
		if (v != scrollX && ui != null) {
			Ui.accessEpoch++;
			ui.requestFrame();
		}
		return scrollX = v;
	}

	function set_scrollY(v:Float):Float {
		if (v != scrollY && ui != null) {
			Ui.accessEpoch++;
			ui.requestFrame();
		}
		return scrollY = v;
	}

	function set_autofocus(v:Bool):Bool {
		if (v && !autofocus && ui != null) ui.setFocus(this, false);
		return autofocus = v;
	}

	function set_focusable(v:Bool):Bool {
		if (v != focusable) Ui.accessEpoch++;
		return focusable = v;
	}

	// handles e's actions dispatched through it (Ui.dispatchAction: from the focus
	// up): handle true takes one, false lets it bubble; state what a menu
	// shows it as (default: Enabled). Returns what removes it.
	public function on<T>(type:helder.ui.actions.Actions.ActionType<T>, handle:T->Bool, ?state:T->helder.ui.actions.ActionState):Void->Void {
		var h = helder.ui.actions.Actions.ActionHandler.of(type, handle, state);
		if (actionHandlers == null) actionHandlers = [];
		actionHandlers.push(h);
		return () -> actionHandlers.remove(h);
	}

	// it or a descendant has the focus (CSS's :focus-within)
	public function focusWithin():Bool {
		if (ui == null || ui.focus == null) return false;
		var n = ui.focus;
		while (n != null) {
			if (n == this) return true;
			n = n.parent;
		}
		return false;
	}

	function set_semantics(v:Null<helder.ui.access.Semantics>):Null<helder.ui.access.Semantics> {
		if (v != semantics) Ui.accessEpoch++;
		return semantics = v;
	}

	// --- the handlers ---

	var handlers:Null<Handlers> = null;

	inline function get_onPointerDown():Null<Event->Void>
		return handlers == null ? null : handlers.onPointerDown;

	function set_onPointerDown(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onPointerDown = v;
	}

	inline function get_onPointerUp():Null<Event->Void>
		return handlers == null ? null : handlers.onPointerUp;

	function set_onPointerUp(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onPointerUp = v;
	}

	inline function get_onPointerMove():Null<Event->Void>
		return handlers == null ? null : handlers.onPointerMove;

	function set_onPointerMove(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onPointerMove = v;
	}

	inline function get_onPointerEnter():Null<Event->Void>
		return handlers == null ? null : handlers.onPointerEnter;

	function set_onPointerEnter(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onPointerEnter = v;
	}

	inline function get_onPointerLeave():Null<Event->Void>
		return handlers == null ? null : handlers.onPointerLeave;

	function set_onPointerLeave(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onPointerLeave = v;
	}

	inline function get_onPointerCancel():Null<Event->Void>
		return handlers == null ? null : handlers.onPointerCancel;

	function set_onPointerCancel(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onPointerCancel = v;
	}

	inline function get_onLostPointerCapture():Null<Event->Void>
		return handlers == null ? null : handlers.onLostPointerCapture;

	function set_onLostPointerCapture(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onLostPointerCapture = v;
	}

	// its gesture recognisers (helder.ui.gesture: Tap, Pan, Scale), in the
	// order added; each joins the arena of a pointer pressed on it or inside it
	public var gestures(get, never):Null<Array<helder.ui.gesture.Gesture>>;

	inline function get_gestures():Null<Array<helder.ui.gesture.Gesture>>
		return handlers == null ? null : handlers.gestures;

	public function addGesture<T:helder.ui.gesture.Gesture>(g:T):T {
		if (handlers == null) handlers = new Handlers();
		if (handlers.gestures == null) handlers.gestures = [];
		@:privateAccess g.attachTo(this);
		handlers.gestures.push(g);
		return g;
	}

	public function removeGesture(g:helder.ui.gesture.Gesture) {
		if (handlers == null || handlers.gestures == null || !handlers.gestures.remove(g)) return;
		g.cancel();
		@:privateAccess g.attachTo(null);
	}

	// its first gesture of that class (null: none)
	public function gesture<T:helder.ui.gesture.Gesture>(c:Class<T>):Null<T> {
		var gs = gestures;
		if (gs != null)
			for (g in gs)
				if (Std.isOfType(g, c)) return cast g;
		return null;
	}

	// whether a pointer pressed on it is ui's (helder.os's Pointer.owner: a
	// game's controls leave it alone): a node drawing a world under the ui
	// (a <Scene>'s box) says no
	public function ownsPointer():Bool
		return true;

	inline function get_onClick():Null<Event->Void>
		return handlers == null ? null : handlers.onClick;

	function set_onClick(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onClick = v;
	}

	inline function get_onPress():Null<Event->Void>
		return handlers == null ? null : handlers.onPress;

	function set_onPress(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onPress = v;
	}

	inline function get_onWheel():Null<Event->Void>
		return handlers == null ? null : handlers.onWheel;

	function set_onWheel(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onWheel = v;
	}

	inline function get_onKeyDown():Null<Event->Void>
		return handlers == null ? null : handlers.onKeyDown;

	function set_onKeyDown(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onKeyDown = v;
	}

	inline function get_onKeyUp():Null<Event->Void>
		return handlers == null ? null : handlers.onKeyUp;

	function set_onKeyUp(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onKeyUp = v;
	}

	inline function get_onTextInput():Null<Event->Void>
		return handlers == null ? null : handlers.onTextInput;

	function set_onTextInput(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onTextInput = v;
	}

	inline function get_onInput():Null<Event->Void>
		return handlers == null ? null : handlers.onInput;

	function set_onInput(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onInput = v;
	}

	inline function get_onScroll():Null<Void->Void>
		return handlers == null ? null : handlers.onScroll;

	function set_onScroll(v:Null<Void->Void>):Null<Void->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onScroll = v;
	}

	inline function get_onComposition():Null<Event->Void>
		return handlers == null ? null : handlers.onComposition;

	function set_onComposition(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onComposition = v;
	}

	inline function get_onFocus():Null<Event->Void>
		return handlers == null ? null : handlers.onFocus;

	function set_onFocus(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onFocus = v;
	}

	inline function get_onBlur():Null<Event->Void>
		return handlers == null ? null : handlers.onBlur;

	inline function get_onFocusIn():Null<Event->Void>
		return handlers == null ? null : handlers.onFocusIn;

	function set_onFocusIn(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onFocusIn = v;
	}

	inline function get_onFocusOut():Null<Event->Void>
		return handlers == null ? null : handlers.onFocusOut;

	function set_onFocusOut(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onFocusOut = v;
	}

	inline function get_onResize():Null<Event->Void>
		return handlers == null ? null : handlers.onResize;

	function set_onResize(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		// (told again, at the next layout)
		handlers.toldWidth = -1;
		if (v != null && ui != null) ui.requestFrame();
		return handlers.onResize = v;
	}

	function set_onBlur(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onBlur = v;
	}

	inline function get_dragData():Dynamic
		return handlers == null ? null : handlers.dragData;

	function set_dragData(v:Dynamic):Dynamic {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.dragData = v;
	}

	inline function get_onDragStart():Null<Event->Void>
		return handlers == null ? null : handlers.onDragStart;

	function set_onDragStart(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onDragStart = v;
	}

	inline function get_onDragOver():Null<Event->Void>
		return handlers == null ? null : handlers.onDragOver;

	function set_onDragOver(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onDragOver = v;
	}

	inline function get_onDragLeave():Null<Event->Void>
		return handlers == null ? null : handlers.onDragLeave;

	function set_onDragLeave(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onDragLeave = v;
	}

	inline function get_onDrop():Null<Event->Void>
		return handlers == null ? null : handlers.onDrop;

	function set_onDrop(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onDrop = v;
	}

	inline function get_onDragEnd():Null<Event->Void>
		return handlers == null ? null : handlers.onDragEnd;

	function set_onDragEnd(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onDragEnd = v;
	}

	// (Ui.update's, after the layout, for the nodes that joined Ui.natives: a platform's view kept in step)
	@:allow(helder.ui.Ui) function syncNative()
		if (glassGroup != null) glassGroup.sync();

	// (its glass merged: GlassGroup.of's, markup's glassSpacing)
	@:allow(helder.ui) var glassGroup:Null<GlassGrouping> = null;

	// the glass inside it drawn together, nearer than this many points
	// merged (null: not a group; markup's glassSpacing, any view's; GlassGroup.of sets it)
	public var glassSpacing(get, never):Null<Float>;

	function get_glassSpacing():Null<Float>
		return glassGroup == null ? null : glassGroup.spacing;

	// an attribute of its own (another package's element's: a video's
	// autoPlay), set by markup's renderer: false where it has none
	@:noCompletion public function setOwn(name:String, v:Dynamic):Bool
		return false;

	// an event of its own (a video's onEnded), its handler h: false where it has none
	@:noCompletion public function listenOwn(name:String, h:Dynamic):Bool
		return false;

	// (where syncNative last placed its view: x, y, width, height, shown (1,
	// else 0), in the window's points; null: none placed)
	@:allow(helder.ui) var placed:Null<Array<Float>> = null;

	// (a system layer of its own between what is drawn: LayerSlot)
	@:allow(helder) var systemLayer:Null<LayerSlot> = null;

	// (its view placed again, at once, on the main thread: the compositor
	// moving it with a scroll the program has not drawn yet)
	@:allow(helder.ui) function placeNative(x:Float, y:Float, width:Float, height:Float, shown:Bool) {}

	// (Ui.update's, after each layout, for the nodes that joined Ui.settlers (a
	// VirtualScroll: its rows measured, its window moved): whether it changed
	// the tree, laid out again then)
	@:allow(helder.ui.Ui) function settle():Bool
		return false;

	// (the window took the keyboard's focus from its platform view: given back)
	function refocusNative() {}

	// the layout of this node (and so of its ancestors) must be redone
	@:noCompletion public function markDirty() {
		Ui.accessEpoch++;
		fontCache = null;
		textBits = -1;
		var n = this;
		while (n != null && !(n.dirty && (n.cache == null || n.cache[0] == 0) && Math.isNaN(n.minContent))) {
			if (!n.dirty) {
				n.cacheWas = n.lossy ? -1 : n.cache == null ? 0 : Std.int(n.cache[0]);
				n.minContentWas = n.minContent;
				n.lossy = false;
			}
			n.dirty = true;
			if (n.cache != null) n.cache[0] = 0;
			n.minContent = Math.NaN;
			n = n.parent;
		}
		if (ui != null) {
			ui.requestFrame();
			layerChanged();
		}
	}

	// (the paint it was drawn in last: Ui.paintFrame then)
	var drawnAt = -1;
	// (its own layer, while its transform or opacity moves; its content's, a scroller's: Ui.paint)
	@:allow(helder.ui) var paintLayer:Null<helder.ui.draw.Layer> = null;
	@:allow(helder.ui) var contentLayer:Null<helder.ui.draw.Layer> = null;
	// (the record (Ui.ticks) it was last painted into and its entry there
	// (-1: none), copied from while nothing changed since: the ticks it,
	// something inside it, and what it passes down last changed in)
	@:allow(helder.ui) var paintedAt = -1;
	@:allow(helder.ui) var entry = -1;
	@:allow(helder.ui) var changedAt = 0;
	@:allow(helder.ui) var innerAt = 0;
	@:allow(helder.ui) var deepAt = 0;
	// (the paint after which its transform or opacity last changed)
	var compositeAt = -10;

	// (what it paints changed: the layer it is painted in recorded again, and
	// its own and its content's, a scroller's (a child added or taken out, a
	// style its children inherit), and its parent's, which draws its own or
	// not (displayed or not); deep: the layers inside it too, as what they
	// inherit from it changed)
	@:allow(helder.ui) function layerChanged(deep = false) {
		var u = ui;
		if (u == null) return;
		var t = @:privateAccess u.ticks, p = parent;
		changedAt = t;
		if (deep) deepAt = t;
		while (p != null && p.innerAt != t) {
			p.innerAt = t;
			p = p.parent;
		}
		if (contentLayer != null) contentLayer.dirty = true;
		if (paintLayer != null) paintLayer.dirty = true;
		var l:Null<helder.ui.draw.Layer> = null, n = parent;
		while (l == null && n != null) {
			l = n.contentLayer ?? n.paintLayer;
			n = n.parent;
		}
		if (l == null) l = @:privateAccess u.rootLayer;
		l.dirty = true;
		if (!deep) return;
		for (k in @:privateAccess u.layers)
			if (!k.dirty && @:privateAccess Ui.contains(this, k.node)) k.dirty = true;
	}

	// (its transform or opacity changed: only where its own layer is drawn,
	// once it has one; it gets one as they change in paints one after another)
	@:allow(helder.ui) function compositeChanged() {
		var u = ui;
		if (u == null) return;
		var f = @:privateAccess u.paintFrame;
		if (paintLayer != null) paintLayer.movedAt = f;
		else {
			layerChanged(true);
			if (f - compositeAt <= 1) {
				paintLayer = new helder.ui.draw.Layer(this, false);
				paintLayer.movedAt = f;
				@:privateAccess u.layers.push(paintLayer);
			}
			compositeAt = f;
		}
		if (drawnAt == f || shows()) u.requestFrame();
	}

	// (its transform or opacity set to move (a transition, a motion's
	// track): its own layer at once, so that the frame declaring it hands
	// it to the compositor running, the program free to block after it)
	@:allow(helder.ui) function willMove() {
		var u = ui;
		if (u == null) return;
		var f = @:privateAccess u.paintFrame;
		if (paintLayer == null) {
			layerChanged(true);
			paintLayer = new helder.ui.draw.Layer(this, false);
			@:privateAccess u.layers.push(paintLayer);
		}
		paintLayer.movedAt = f;
		compositeAt = f;
	}

	// whether its content (paintContent) is drawn anew each frame: what it
	// draws read from more than its style and what tells it changed (a
	// subclass's own drawing, unless it says otherwise): a layer holding it is recorded again each frame
	@:allow(helder.ui) function paintsLive():Bool
		return hasContent();

	// what it paints changed (a colour, its opacity, its transform): a frame
	// asked for when that shows, or showed in the last frame; one hidden
	// (display none) or out of the window's view asks for none (an
	// animation scrolled away), and is drawn as it is when it comes back
	// into view (a scroll or a layout asks for that frame)
	@:allow(helder.ui) function paintChanged() {
		if (ui == null) return;
		layerChanged(true);
		if (drawnAt == @:privateAccess ui.paintFrame || shows()) ui.requestFrame();
	}

	// whether it can be seen: it and its ancestors displayed, its box where
	// it is drawn (windowBounds) over the window, give or take a shadow's reach
	function shows():Bool {
		var n = this;
		while (n != null) {
			if (n.used.none) return false;
			n = n.parent;
		}
		var b = windowBounds(), e = Ui.shadowReach + 16;
		return b.x + b.width + e > 0 && b.y + b.height + e > 0 && b.x - e < ui.width && b.y - e < ui.height;
	}

	// (the direction changed above: the descendants laid out again)
	function dirChanged() {
		for (c in children) {
			c.markDirty();
			c.dirChanged();
		}
		if (ui != null && this == ui.body) ui.overlay.dirChanged();
	}

	function inheritedChanged() {
		fontCache = null;
		textBits = -1;
		if (hasContent()) markDirty();
		for (c in children)
			c.inheritedChanged();
		if (ui != null && this == ui.body) ui.overlay.inheritedChanged();
	}

	// --- inherited text properties ---

	// (what it inherits from: its parent; the overlay's, the page's body (Ui.body), as a popup in a page's
	// body inherits the body's text, not its trigger's)
	inline function inheritsFrom():Null<Node>
		return ui != null && this == ui.overlay && ui.body != null ? ui.body : parent != null ? parent : leftFrom;

	// its text's font, as its resolved style has it (its family, size, weight, line height, spacing, breaking,
	// features) in its language
	@:noCompletion public function font():Font {
		if (fontCache != null) return fontCache;
		var t = used.text;
		var features = t.features == null ? "" : [for (f in t.features) "'" + f.tag + "' " + f.value].join(", ");
		var lg = langHere();
		return fontCache = new Font(t.families.length > 0 ? t.families[0] : "sans-serif", t.size, t.weight, t.style == Italic, t.size > 0
			&& t.height == t.height ? t.height / t.size : 1.25, t.letters, t.words, switch t.overflow {
				case Normal: OverflowWrap.Normal;
				case Anywhere: OverflowWrap.Anywhere;
				case _: OverflowWrap.BreakWord;
			}, switch t.breakWord {
				case BreakAll: WordBreak.BreakAll;
				case KeepAll: WordBreak.KeepAll;
				case _: WordBreak.Normal;
			}, features, switch t.hyphen {
				case None: Hyphens.None;
				case Auto: Hyphens.Auto;
				case _: Hyphens.Manual;
			}, lg == null || lg == "" ? null : lg);
	}

	// (its language: its own or the nearest ancestor's)
	function langHere():Null<String> {
		var n = this;
		while (n != null) {
			if (n.lang != null) return n.lang;
			n = n.inheritsFrom();
		}
		return null;
	}

	// (the font, until what it inherits or its style changes)
	var fontCache:Null<Font> = null;

	// the text shadows its text casts (its style's, else its nearest ancestor's; null: none)
	@:noCompletion public function textShadow():Null<Array<Style.ShadowLayer>> {
		var n = this;
		while (n != null) {
			var sh = n.props().textShadow;
			if (sh != null) return sh.length == 0 ? null : sh;
			n = n.inheritsFrom();
		}
		return null;
	}

	// a paragraph's text shadows (textShadow()), the last first, under where
	// it is drawn at x, y in color (or its spans' colors)
	function paintTextShadows(canvas:Canvas, p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, ?colors:Array<Color>) {
		var shadows = textShadow();
		if (shadows == null) return;
		var k = shadows.length;
		while (--k >= 0) {
			var sh = shadows[k], current = (sh.color : Style.TintValue).match(Current);
			var c:Color = current ? color : @:privateAccess Resolve.tint(sh.color, scope(), color);
			canvas.textShadow(p, x + sh.x, y + sh.y, width, align, c, sh.blur ?? 0, current ? colors : null);
		}
	}

	public function textColor():Color {
		// (a text colour moving: where it is, Motions)
		var n = this;
		while (n != null) {
			var p = n.present;
			if (p != null && p.color != null && p.color.moving()) return p.color.value();
			n = n.inheritsFrom();
		}
		return used.text.colour;
	}

	// whether it is seen: its visibility (inherited)
	public inline function visible():Bool
		return used.visible;

	// whether the pointer finds it: seen, and its pointerEvents (inherited) not None
	public inline function hittable():Bool
		return used.visible && used.rare.pointerEvents != "none";

	// whether its text wraps (inherited)
	public inline function wraps():Bool
		return used.text.wrap != NoWrap;

	// how its text wraps (inherited): Balance as its style says
	public function textWrap():TextWrap {
		if (used.text.wrap == NoWrap) return NoWrap;
		var n = this;
		while (n != null) {
			var w = n.props().textWrap;
			if (w != null) return w == Balance ? Balance : Wrap;
			n = n.inheritsFrom();
		}
		return Wrap;
	}

	// how its text's letters are shown (inherited)
	public function textTransform():TextTransform
		return switch used.text.transform {
			case Uppercase: TextTransform.Uppercase;
			case Lowercase: TextTransform.Lowercase;
			case Capitalize: TextTransform.Capitalize;
			case _: TextTransform.None;
		}

	// (cleared with fontCache)
	var textBits = -1;

	public function textAlign():TextAlign
		return switch used.text.align {
			case Center: Center;
			case Right: Right;
			case Justify: Justify;
			case Left: Left;
			case End: rtl() ? Left : Right;
			case _: rtl() ? Right : Left;
		}

	// its text's user-select as set on it or an ancestor (Auto: none set)
	public function userSelect():UserSelect {
		var n = this;
		while (n != null) {
			var u = n.props().userSelect;
			if (u != null && u != Auto) return u;
			n = n.inheritsFrom();
		}
		return Auto;
	}

	public inline function rtl():Bool
		return used.text.dir == Rtl;

	// its direction as set on it or an ancestor (null: none set, a paragraph's its text's)
	public function dir():Null<Dir> {
		var n = this;
		while (n != null) {
			var d = n.props().direction;
			if (d != null) return d;
			n = n.inheritsFrom();
		}
		return null;
	}

	// a window position in this node's coordinates (from its border box's
	// top left), its ancestors' scrolling and transforms (its own too) taken
	// into account
	public function localX(windowX:Float, windowY:Float):Float
		return toLocal(windowX, windowY, true);

	public function localY(windowX:Float, windowY:Float):Float
		return toLocal(windowX, windowY, false);

	function toLocal(px:Float, py:Float, x:Bool):Float {
		var chain = [], n = this;
		while (n != null) {
			chain.push(n);
			n = n.parent;
		}
		var i = chain.length;
		while (--i >= 0) {
			var a = chain[i], m = a.transformMatrix();
			if (m != null) {
				var inv = new Matrix();
				if (m.invertInto(inv)) {
					var tx = inv.mapX(px, py);
					py = inv.mapY(px, py);
					px = tx;
				}
			}
			if (i > 0 && a.used.scrolls) {
				px += a.scrollX;
				py += a.scrollY;
			}
		}
		return x ? px - absX : py - absY;
	}

	// --- a part (Part: what a neutral element's ref gets) ---

	public function focus(visible:Bool = true) {
		if (ui == null) return;
		if (visible) ui.focusVisible = true;
		ui.setFocus(this);
	}

	public function rect():Rect
		return windowBounds();

	// rect, written into out (returned): nothing made (windowBoundsInto)
	@:noCompletion public inline function rectInto(out:Rect):Rect
		return windowBoundsInto(out);

	public function scrollIntoView()
		if (ui != null) ui.scrollIntoView(this);

	// (a press's pointer: the pressed node's until released (Ui.capture), this one's now;
	// in a pointer event's handler, that pointer: a finger's, a pen's)
	public function capture()
		if (ui != null) @:privateAccess ui.captureBy(this);

	// lets go of the pointers it captured: their moves go to what is under them again
	public function releaseCapture()
		if (ui != null) @:privateAccess ui.releaseBy(this);

	// (a text field's: EditableText's)
	public function select(start:Int, end:Int) {}

	function set_selectable(v:Bool):Bool
		return selectable = v;

	// the scope its text is selected in: its outermost selectable ancestor
	// (itself too; user-select none: not one), else null
	public function selectionScope():Null<Node> {
		var n:Null<Node> = this, scope:Null<Node> = null;
		while (n != null) {
			if (n.selectable && n.props().userSelect != None) scope = n;
			n = n.parent;
		}
		return scope;
	}

	// (a text selection's text of it: null, none of its own, as a TextNode's span)
	@:noCompletion public function selectableText():Null<String>
		return null;

	// (the index in that text nearest to a point of the window; under: the
	// character's under it)
	@:noCompletion public function selectableIndex(px:Float, py:Float, under = false):Int
		return 0;

	// (index i's caret in the window: x, its line's top and height; null: not laid out)
	@:noCompletion public function selectableCaret(i:Int):Null<{x:Float, y:Float, height:Float}>
		return null;

	// (kept wherever nodes are laid out: a Part's, which a component calls opaquely in a page too)
	@:ifFeature("helder.ui.Node.markDirty") public function editable():Bool
		return takesText();

	public function contains(p:Part):Bool {
		var n:Null<Node> = Std.downcast(p, Node);
		while (n != null && n != this)
			n = n.parent;
		return n != null;
	}

	// the border box where it is drawn, in window pixels: its ancestors'
	// scrolling taken off, through the transforms (its own too; the bounds
	// of the box they turn)
	public function windowBounds():Rect {
		return windowBoundsInto({x: 0.0, y: 0.0, width: 0.0, height: 0.0});
	}

	// windowBounds, written into out (returned): its corners in locals, no
	// array or box made (a transformed ancestor's matrix still is: transformMatrix)
	public function windowBoundsInto(out:Rect):Rect {
		var w = width, h = height;
		if (present != null) {
			w = present.width();
			h = present.height();
		}
		var x0 = absX, y0 = absY, x1 = absX + w, y1 = absY, x2 = absX, y2 = absY + h, x3 = absX + w, y3 = absY + h;
		var a = this;
		while (a != null) {
			if (a != this && a.used.scrolls) {
				x0 -= a.scrollX;
				x1 -= a.scrollX;
				x2 -= a.scrollX;
				x3 -= a.scrollX;
				y0 -= a.scrollY;
				y1 -= a.scrollY;
				y2 -= a.scrollY;
				y3 -= a.scrollY;
			}
			var m = a.transformMatrix();
			if (m != null) {
				var x = x0;
				x0 = m.mapX(x, y0);
				y0 = m.mapY(x, y0);
				x = x1;
				x1 = m.mapX(x, y1);
				y1 = m.mapY(x, y1);
				x = x2;
				x2 = m.mapX(x, y2);
				y2 = m.mapY(x, y2);
				x = x3;
				x3 = m.mapX(x, y3);
				y3 = m.mapY(x, y3);
			}
			// (where motion draws it: its own edges' move, a leaving node's place in its old parent)
			var p = a.present;
			if (p != null) {
				var dx = p.exiting && a.leftFrom != null ? a.leftFrom.absX + p.gx - a.absX : p.dx();
				var dy = p.exiting && a.leftFrom != null ? a.leftFrom.absY + p.gy - a.absY : p.dy();
				x0 += dx;
				x1 += dx;
				x2 += dx;
				x3 += dx;
				y0 += dy;
				y1 += dy;
				y2 += dy;
				y3 += dy;
			}
			a = a.parent ?? a.leftFrom;
		}
		var lx = Math.min(Math.min(x0, x1), Math.min(x2, x3)), ly = Math.min(Math.min(y0, y1), Math.min(y2, y3));
		var hx = Math.max(Math.max(x0, x1), Math.max(x2, x3)), hy = Math.max(Math.max(y0, y1), Math.max(y2, y3));
		out.x = lx;
		out.y = ly;
		out.width = hx - lx;
		out.height = hy - ly;
		return out;
	}

	// the transform (Style.transform about Style.transformOrigin) in window
	// pixels, as Canvas.pushTransform takes it; null: none
	public function transformMatrix():Null<Matrix> {
		var pr = props(), t = pr.transform;
		// (Sticky: moved where it sticks, then transformed there)
		var sx = 0.0, sy = 0.0;
		if (used.position == "sticky") {
			var s = stickyOffset();
			sx = s[0];
			sy = s[1];
		}
		// (motion: its presence's scale and slide, its transform's lanes, about its presented box)
		var p = present;
		if (p != null && p.transforms()) {
			var w = p.width(), h = p.height(), o = pr.transformOrigin;
			var ox = o == null ? Math.NaN : o[0].resolve(w), oy = o == null ? Math.NaN : o[1].resolve(h);
			return p.matrix(t == null || t.isIdentity() ? null : t.toMatrix(w, h), absX + (Math.isNaN(ox) ? w / 2 : ox), absY + (Math.isNaN(oy) ? h / 2 : oy), sx, sy);
		}
		if (t == null || t.isIdentity()) return sx == 0 && sy == 0 ? null : new Matrix(1, 0, 0, 1, sx, sy);
		var o = pr.transformOrigin;
		var w = p != null ? p.width() : width, h = p != null ? p.height() : height;
		var ox = o == null ? Math.NaN : o[0].resolve(w), oy = o == null ? Math.NaN : o[1].resolve(h);
		ox = absX + (Math.isNaN(ox) ? w / 2 : ox);
		oy = absY + (Math.isNaN(oy) ? h / 2 : oy);
		var m = t.toMatrix(w, h);
		// (about the origin: moved there, transformed, moved back)
		m.e += ox - (m.a * ox + m.c * oy) + sx;
		m.f += oy - (m.b * ox + m.d * oy) + sy;
		return m;
	}

	// a Sticky node's move from where it was laid out: kept its insets
	// (left, top, right, bottom: those given) inside the content box of the
	// nearest scrolling ancestor as it scrolls, as far as its parent's
	// content box lets it go (its margins inside), as CSS sticks it
	function stickyOffset():Array<Float> {
		var p = parent, sc = parent;
		while (sc != null && !sc.used.scrolls)
			sc = sc.parent;
		if (p == null) return [0, 0];
		var out = [0.0, 0.0], s = used;
		for (axis in 0...2) {
			var x = axis == 0;
			var pos = x ? absX : absY, size = x ? width : height;
			// (the view: the scroller's content box, scrolled; else the window's)
			var v0 = 0.0, v1 = ui == null ? 1e9 : x ? ui.width : ui.height;
			if (sc != null) {
				var ss = sc.used, be = ss.borderEdges, pad = ss.paddingEdges;
				v0 = (x ? sc.absX + be.left + pad.left + sc.scrollX : sc.absY + be.top + pad.top + sc.scrollY);
				v1 = (x ? sc.absX + sc.width - be.right - pad.right + sc.scrollX : sc.absY + sc.height - be.bottom - pad.bottom + sc.scrollY);
			}
			// (the parent's content box, its margins inside)
			var ps = p.used, pbe = ps.borderEdges, ppad = ps.paddingEdges;
			// (an auto margin: 0)
			var m0 = helder.ui.box.Len.Lens.resolve(s.margin[x ? 3 : 0], Math.NaN, 0), m1 = helder.ui.box.Len.Lens.resolve(s.margin[x ? 1 : 2], Math.NaN, 0);
			var c0 = (x ? p.absX + pbe.left + ppad.left : p.absY + pbe.top + ppad.top) + m0;
			var c1 = (x ? p.absX + p.width - pbe.right - ppad.right : p.absY + p.height - pbe.bottom - ppad.bottom) - m1;
			var start = helder.ui.box.Len.Lens.resolve(s.inset(x ? 3 : 0), v1 - v0, Math.NaN), end = helder.ui.box.Len.Lens.resolve(s.inset(x ? 1 : 2), v1 - v0, Math.NaN);
			var d = 0.0;
			if (!Math.isNaN(start) && pos + d < v0 + start) d = Math.min(v0 + start - pos, Math.max(0, c1 - (pos + size)));
			if (!Math.isNaN(end) && pos + d + size > v1 - end) d = Math.max(v1 - end - (pos + size), Math.min(0, c0 - pos));
			out[axis] = d;
		}
		return out;
	}

	// --- content (subclasses) ---

	public function hasContent():Bool
		return glassGroup != null;

	// the content's size for the given content-box constraints (NaN: unknown
	// or unbounded)
	@:noCompletion public function measureContent(text:TextEngine, knownWidth:Float, knownHeight:Float, availWidth:Float, availHeight:Float):Size
		return Size.ZERO;

	// assistive technology sets its value (a text input's text): false when it has none
	@:noCompletion public function accessSetValue(value:String):Bool
		return false;

	// What it holds that is no Node, for assistive technology (a fast tree's
	// nodes): their nodes in tree order, each id from AccessTree.newId,
	// those no other lists as a child its own children; null: none.
	@:noCompletion public function accessParts():Null<Array<helder.ui.access.AccessNode>>
		return null;

	// the id of what in it has the focus when it has (one of its parts'), else its own
	@:noCompletion public function accessFocus():Int
		return accessId;

	// assistive technology acts on one of its parts: false when it can't
	@:noCompletion public function accessPartAction(id:Int, action:helder.ui.access.AccessAction, value:Null<String>):Bool
		return false;

	// a text input's value for assistive technology when it is not a
	// TextNode's text (a code editor's document); null: none
	public function accessValue():Null<String>
		return null;

	// a text input's selection and caret (UTF-16 indices) and whether it is
	// read only, for assistive technology; null: it edits no text
	public function accessText():Null<{start:Int, end:Int, caret:Int, readOnly:Bool}>
		return null;

	// where text is typed into it (its caret, window pixels, after a paint):
	// an input method's place; null: it takes no text
	public function textInputArea():Null<Rect>
		return null;

	// the text around its caret, for an input method (Window.textContext:
	// its text, the selection in UTF-16 indices, its kind); null: none to give
	public function textContext():Null<{text:String, start:Int, end:Int, multiline:Bool, secret:Bool}>
		return null;

	// what it takes for the system's keyboard (helder.os.TextKind: its
	// keys, Enter key, capitalisation); null: it takes no text
	public function textKind():Null<helder.os.TextKind>
		return null;

	// an input method's edit of that text: start...end replaced by s, the
	// caret after it (a node with no text context: s typed)
	public function replaceText(start:Int, end:Int, s:String)
		if (ui != null && s != "") @:privateAccess ui.textInputNow(s);

	// whether it takes typed text while focused (a text field): keys that type are its, not shortcuts
	public function takesText():Bool
		return false;

	// whether its children are part of its content (a TextNode's spans), not boxes laid out
	@:noCompletion public function contentOwnsChildren():Bool
		return false;

	// the content's min-content width (its widest unbreakable part)
	@:noCompletion public function minContentWidth(text:TextEngine):Float
		return measureContent(text, Math.NaN, Math.NaN, 0, Math.NaN).width;

	// draws the content in its content box at (x, y), in window pixels
	public function paintContent(canvas:Canvas, x:Float, y:Float, width:Float, height:Float)
		if (glassGroup != null) glassGroup.paint(canvas);

	// its children in their layout order (Style.order: lower first, ties in
	// the tree's order): the children themselves when none has an order
	@:allow(helder.ui) function inOrder():Array<Node> {
		var any = false;
		for (c in children)
			if (c.used.order != 0) {
				any = true;
				break;
			}
		return any ? sorted((a, b) -> a.used.order - b.used.order) : children;
	}

	// its children in the order they paint (Style.zIndex; then positioned ones
	// over those in the flow; then Style.order), hit the other way round; null
	// when that is the tree's order with positioned ones last (the usual case)
	@:allow(helder.ui) function paintOrder():Null<Array<Node>> {
		var any = false;
		for (c in children)
			if ((c.used.zIndex() ?? 0) != 0 || c.used.order != 0) {
				any = true;
				break;
			}
		if (!any) return null;
		inline function tier(n:Node):Int
			return n.used.position != "relative" ? 1 : 0;
		return sorted((a, b) -> (a.used.zIndex() ?? 0) != (b.used.zIndex() ?? 0) ? (a.used.zIndex() ?? 0) - (b.used.zIndex() ?? 0) : tier(a) != tier(b) ? tier(a) - tier(b) : a.used.order - b.used.order);
	}

	// (a stable sort of the children: insertion, children being few)
	function sorted(cmp:(Node, Node) -> Int):Array<Node> {
		var a = children.copy();
		for (i in 1...a.length) {
			var x = a[i], j = i - 1;
			while (j >= 0 && cmp(a[j], x) > 0) {
				a[j + 1] = a[j];
				j--;
			}
			a[j + 1] = x;
		}
		return a;
	}

	// --- queries ---

	// the topmost node under (px, py) in window pixels, among this subtree
	// (clipped by Overflow, through the transforms), or null
	public function hitTest(px:Float, py:Float):Null<Node> {
		if (used.none) return null;
		// (nothing of it there)
		if (!inkAll && (px < inkX0 || px >= inkX1 || py < inkY0 || py >= inkY1)) return null;
		var m = transformMatrix();
		if (m != null) {
			var inv = new Matrix();
			if (!m.invertInto(inv)) return null;
			var tx = inv.mapX(px, py);
			py = inv.mapY(px, py);
			px = tx;
		}
		var inside = px >= absX && py >= absY && px < absX + width && py < absY + height;
		if (!inside && used.clips) return null;
		// (absolute and sticky children first: they are drawn over the others)
		var sx = px + (used.scrolls ? scrollX : 0), sy = py + (used.scrolls ? scrollY : 0);
		var order = paintOrder();
		if (order != null) {
			var i = order.length;
			while (--i >= 0) {
				var c = order[i].hitTest(sx, sy);
				if (c != null) return c;
			}
			return inside && hittable() ? this : null;
		}
		for (pass in 0...2) {
			var i = children.length;
			while (--i >= 0) {
				if ((children[i].used.position != "relative") != (pass == 0)) continue;
				var c = children[i].hitTest(sx, sy);
				if (c != null) return c;
			}
		}
		return inside && hittable() ? this : null;
	}

	// the bounds of what it and its subtree draw, from its layout (window
	// pixels before scrolling, in its parent's coordinates: through its
	// transform; its children's too unless it clips them; unbounded when it
	// or a child sticks): paint and hit tests leave out subtrees whose bounds
	// miss them (paint after widening them by what shadows and rings add:
	// Ui.inkMargin)
	@:allow(helder.ui) function measureInk() {
		// (a child's transform changed while this was laid out again: the
		// child is not, and its bounds would stay as they were)
		for (k in children)
			if (k.inkStale) k.measureInk();
		var s = used, was0 = inkX0, was1 = inkY0, was2 = inkX1, was3 = inkY1, wasAll = inkAll;
		inkAll = s.position == "sticky";
		inkX0 = absX;
		inkY0 = absY;
		inkX1 = absX + width;
		inkY1 = absY + height;
		// (content wider or higher than its box: past it on either side, as aligned)
		var c = contentInk();
		if (!Math.isNaN(c.width)) {
			var ex = c.width - (width - s.edgesAcross(true)), ey = c.height - (height - s.edgesAcross(false));
			if (ex > 0) {
				inkX0 -= ex;
				inkX1 += ex;
			}
			if (ey > 0) inkY1 += ey;
		}
		if (!s.clips)
			for (k in children) {
				if (k.used.none) continue;
				if (k.inkAll) inkAll = true;
				if (k.inkX0 < inkX0) inkX0 = k.inkX0;
				if (k.inkY0 < inkY0) inkY0 = k.inkY0;
				if (k.inkX1 > inkX1) inkX1 = k.inkX1;
				if (k.inkY1 > inkY1) inkY1 = k.inkY1;
			}
		// (transformed: the box around its bounds' corners where they are drawn)
		var m = inkAll ? null : transformMatrix();
		if (m != null) {
			var xs = [inkX0, inkX1, inkX0, inkX1], ys = [inkY0, inkY0, inkY1, inkY1];
			inkX0 = inkY0 = Math.POSITIVE_INFINITY;
			inkX1 = inkY1 = Math.NEGATIVE_INFINITY;
			for (k in 0...4) {
				var x = m.mapX(xs[k], ys[k]), y = m.mapY(xs[k], ys[k]);
				if (x < inkX0) inkX0 = x;
				if (x > inkX1) inkX1 = x;
				if (y < inkY0) inkY0 = y;
				if (y > inkY1) inkY1 = y;
			}
		}
		inkStale = false;
		// (its bounds tested where it is recorded: that layer recorded again; a
		// layer's own node is tested as it is walked)
		if (paintLayer == null && (was0 != inkX0 || was1 != inkY0 || was2 != inkX1 || was3 != inkY1 || wasAll != inkAll)) layerChanged();
	}

	// (a transform or sticking changed: its bounds and its ancestors' measured
	// again at the next update; composite: only how it is drawn, its transform)
	@:allow(helder.ui) function inkChanged(composite = false) {
		var n = this;
		while (n != null && !n.inkStale) {
			n.inkStale = true;
			n = n.parent;
		}
		if (composite) compositeChanged() else paintChanged();
	}

	// what its content draws, from its content box's top left, when it may reach past the box (a text's paragraph)
	// its first baseline below its border box's top, once laid out: a text's
	// first line's, a row's items aligned on theirs, else its first item's
	// (one without any: its bottom edge, as CSS's flexbox synthesizes it);
	// NaN: none (no text, no items)
	public function firstBaseline():Float {
		if (!Math.isNaN(lb)) return lb;
		// (a reversed column's: its last item's, the first from the top, as Chromium)
		var items = inOrder();
		if (used.inner != helder.ui.box.BoxStyle.GRID && used.flexDirection == "column-reverse") {
			items = items.copy();
			items.reverse();
		}
		for (c in items) {
			var cs = c.used;
			if (cs.none || cs.position == "absolute") continue;
			var b = c.firstBaseline();
			return c.ly + (Math.isNaN(b) ? c.lh : b);
		}
		return Math.NaN;
	}

	// its content's size where it may draw past its content box (Size.NONE: none)
	@:noCompletion public function contentInk():Size
		return Size.NONE;

	// the first descendant (or this) with the tag, depth first
	public function find(tag:String):Null<Node> {
		if (this.tag == tag) return this;
		for (c in children) {
			var f = c.find(tag);
			if (f != null) return f;
		}
		return null;
	}

	public function toString():String
		return '$tag(${x},${y} ${width}x${height})';

	// --- set by Layout and Ui ---

	#if !helder.layout
	// (its box in the CSS engine's tree: NodeBoxes')
	@:allow(helder.ui) var laidBox:Null<helder.ui.box.Box> = null;
	// (the fragment it was last told its place from: the same one, nothing in it moved)
	@:allow(helder.ui) var laidFragment = -1;
	// (a root's: the engine's state its tree is laid out with)
	@:allow(helder.ui) var laidBy:Null<NodeBoxes> = null;
	#end

	@:allow(helder.ui.Layout) function setLayout(x:Float, y:Float, w:Float, h:Float, ax:Float, ay:Float, cw:Float, ch:Float) {
		// (onResize: told after the layout, Ui.update)
		if (handlers != null && handlers.onResize != null && ui != null && (w != handlers.toldWidth || h != handlers.toldHeight))
			@:privateAccess ui.resized.push(this);
		// (under motion: its edges move from where they are drawn, Motions)
		if (helder.ui.motion.Motions.on && (x != this.x || y != this.y || w != width || h != height)) helder.ui.motion.Motions.relaid(this, x, y, w, h);
		if (x != this.x || y != this.y || w != width || h != height || ax != absX || ay != absY || cw != contentWidth || ch != contentHeight) layerChanged();
		this.x = x;
		this.y = y;
		width = w;
		height = h;
		absX = ax;
		absY = ay;
		contentWidth = cw;
		contentHeight = ch;
	}

	@:allow(helder.ui.Ui) function setState(hovered:Bool, pressed:Bool, focused:Bool) {
		var changed = hovered != this.hovered || pressed != this.pressed || focused != this.focused;
		this.hovered = hovered;
		this.pressed = pressed;
		this.focused = focused;
		if (!changed) return;
		pointerStates();
		if (ui != null) ui.requestFrame();
		statesChanged();
	}

	// (its hover, press and focus as its style's states: the focus while it is shown, the keyboard's, as CSS's
	// :focus-visible)
	@:allow(helder.ui.Ui) function pointerStates() {
		var bits = (hovered ? Style.HOVER : 0) | (pressed ? Style.PRESSED : 0) | (focused && ui != null && ui.focusVisible ? Style.FOCUS : 0);
		var next = states & ~(Style.HOVER | Style.PRESSED | Style.FOCUS) | bits;
		if (next == states) return;
		states = next;
		resolve(under ?? Resolve.root, passed ?? Theme.base, groupStates);
	}

	// called when its states (hover, press, focus, the focus ring's
	// visibility) or attributes change: helder.ui.view.States' signals
	public var onStates:Null<Void->Void> = null;
	// (its States, once made: helder.ui.view's)
	@:allow(helder.ui.view) var statesOf:Any = null;

	@:allow(helder.ui.Ui) function statesChanged() {
		if (onStates != null) onStates();
	}

	// --- attributes ---

	// an attribute (null: not set; "" when it is present without a value)
	public function attr(name:String):Null<String>
		return attrs == null ? null : attrs.get(name);

	// sets an attribute (null: removes it); data-state's checked and selected, data-disabled, its states
	public function setAttr(name:String, value:Null<String>) {
		if (attr(name) == value) return;
		if (value == null) attrs.remove(name) else {
			if (attrs == null) attrs = new Map();
			attrs.set(name, value);
		}
		var d = attr("data-state"), bits = (d == "checked" ? Style.CHECKED : 0) | (d == "selected" ? Style.SELECTED : 0)
			| (d == "mixed" || d == "indeterminate" ? Style.MIXED : 0) | (attr("data-disabled") != null ? Style.DISABLED : 0);
		var next = states & ~(Style.CHECKED | Style.SELECTED | Style.MIXED | Style.DISABLED) | bits;
		if (next != states) {
			states = next;
			resolve(under ?? Resolve.root, passed ?? Theme.base, groupStates);
		}
		statesChanged();
	}
}

// a node's event handlers (Node.onClick...)
private class Handlers {
	public var onPointerDown:Null<Event->Void> = null;
	public var onPointerUp:Null<Event->Void> = null;
	public var onPointerMove:Null<Event->Void> = null;
	public var onPointerEnter:Null<Event->Void> = null;
	public var onPointerLeave:Null<Event->Void> = null;
	public var onPointerCancel:Null<Event->Void> = null;
	public var onLostPointerCapture:Null<Event->Void> = null;
	public var gestures:Null<Array<helder.ui.gesture.Gesture>> = null;
	public var onClick:Null<Event->Void> = null;
	public var onPress:Null<Event->Void> = null;
	public var onWheel:Null<Event->Void> = null;
	public var onKeyDown:Null<Event->Void> = null;
	public var onKeyUp:Null<Event->Void> = null;
	public var onTextInput:Null<Event->Void> = null;
	public var onInput:Null<Event->Void> = null;
	public var onScroll:Null<Void->Void> = null;
	public var onComposition:Null<Event->Void> = null;
	public var onFocus:Null<Event->Void> = null;
	public var onBlur:Null<Event->Void> = null;
	public var onFocusIn:Null<Event->Void> = null;
	public var onFocusOut:Null<Event->Void> = null;
	public var dragData:Dynamic = null;
	public var onDragStart:Null<Event->Void> = null;
	public var onDragOver:Null<Event->Void> = null;
	public var onDragLeave:Null<Event->Void> = null;
	public var onDrop:Null<Event->Void> = null;
	public var onDragEnd:Null<Event->Void> = null;
	public var onResize:Null<Event->Void> = null;
	// the size onResize was last told (-1: not yet)
	public var toldWidth = -1.0;
	public var toldHeight = -1.0;

	public function new() {}
}

// (Node's source and sourceComponent, on its first line: where markup wrote
// it and the component mounting it, in dev builds and headless runs,
// helder.view.Source; there so that no line below moves: a release build's
// positions, and so its bytes, stay the same)
