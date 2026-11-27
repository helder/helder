package helder.ui.box;

import haxe.Timer;
import helder.dom.Document;
import helder.dom.Element;
import helder.dom.ElementState;
import helder.dom.Node as DomNode;
import helder.ui.Canvas;
import helder.ui.Event;
import helder.ui.Size;
import helder.ui.TextEngine;
import helder.ui.box.DocumentView.DocumentViewOptions;

// A helder.dom document shown live in a helder.ui tree: styled, laid out at
// the node's width (its height the document's) and painted by the engine
// (DocumentView: helder.css, helder.ui.box and flow), its fragments in view
// drawn through UiPainter into what Ui.paint records. Put in a scroller,
// the compositor scrolls it: a scroll restyles and lays out nothing, and
// paints only as the scroller's layer is recorded over more of it. The
// pointer sets its elements' state (hover on the element under it and its
// ancestors, active while pressed: Element.state), the restyle tracker
// marks what may match differently and the next frame restyles those and
// redoes only what their changes need (DocumentView.update: a colour a
// repaint, a size a layout of what it touches). Dragging selects text; a
// click on an <a href> calls onLink; Tab moves the focus between links and
// controls (:focus-visible), Enter follows a focused link.
//
//   var page = DocumentNode.html(Dom.parse(html), {url: url});   // HTML's cascade
//   var app = new DocumentNode(doc, (d, media, _) -> CssCascade.themed(d, sheets, {media: media}));   // compiled sheets: no parser linked
//   page.onLink = (url, a) -> trace(url);
//   scroller.append(page);
@:access(helder.ui.Ui)
class DocumentNode extends helder.ui.Node {
	public final view:DocumentView;
	// an <a href> followed: its URL resolved against the document's, the element
	public var onLink:Null<(url:String, a:Element) -> Void> = null;
	// the text selected, from one DOM position to another (null: none)
	public var selection(default, null):Null<{from:DomPosition, to:DomPosition}> = null;
	// the engine's own work (ms, all told and the last of each): the
	// restyles and their updates, layouts, paints recorded
	public final stats = new DocumentStats();

	final painter = new UiPainter(null, 0, 0);
	final options:DocumentViewOptions;
	var laidWidth = Math.NaN;
	var laidHeight = Math.NaN;
	var docHeight = 0.0;
	var hoverChain:Array<Element> = [];
	var pressedElement:Null<Element> = null;
	var focusedElement:Null<Element> = null;
	var anchor:Null<DomPosition> = null;
	var dragged = false;
	var hooked:Null<helder.ui.Ui> = null;
	// (the scroll's top where it was last laid out; how many times this frame's settles asked)
	var lastTop = 0.0;
	var rounds = 0;

	// cascade: how the document is styled (DocumentView's), the program's choice so that it links only that one
	public function new(document:Document, cascade:DocumentView.DocumentCascade, ?options:DocumentViewOptions) {
		super("document");
		this.options = options ?? {};
		view = new DocumentView(document, cascade, this.options);
		focusable = true;
		onPointerMove = moved;
		onPointerLeave = _ -> hover(null);
		onPointerDown = down;
		onPointerUp = up;
		onKeyDown = key;
		onWheel = wheeled;
		onBlur = _ -> focusOn(null, false);
	}

	// A document styled as HTML is (DocumentView.html's cascade).
	public static function html(document:Document, ?options:DocumentViewOptions):DocumentNode
		return new DocumentNode(document, DocumentView.htmlCascade, options);

	public var document(get, never):Document;

	inline function get_document():Document
		return view.document;

	// The document changed outside the pointer (its tree, attributes,
	// texts, states): what it needs redone in the next frame. (Each frame
	// asks the view as it begins: a change from anywhere is found.)
	public function changed() {
		hook();
		if (ui != null) ui.requestFrame();
	}

	// (each frame's update first asks the view what changed: restyled, laid out, painted again)
	function hook() {
		if (ui == null || hooked == ui) return;
		var u = hooked = ui;
		u.beforeUpdate.push(() -> if (ui == u) flush());
	}

	function flush() {
		rounds = 0;
		if (view.styles == null) return;
		view.watch();
		var t0 = Timer.stamp();
		var redo = view.update();
		if (redo != DocumentView.NOTHING) {
			stats.restyled(Timer.stamp() - t0, redo);
			if (redo >= DocumentView.LAYOUT) {
				docHeight = heightOf();
				markDirty();
			} else {
				layerChanged();
				ui.requestFrame();
			}
		}
	}

	// (Ui.update's, after its layout, the input of the frame read and the scroll where it shows it: what it
	// brings into view laid out before the frame is drawn, a drag's or a live resize's as any)
	@:allow(helder.ui.Ui) override function settle():Bool
		return uncover();

	override function attach(u:Null<helder.ui.Ui>) {
		if (ui != null && ui != u) ui.settlers.remove(this);
		super.attach(u);
		if (u != null && u.settlers.indexOf(this) < 0) u.settlers.push(this);
	}

	// (a long document laid out lazily: what the scroll brings near that it skipped, laid out, what was at the
	// scroll's top kept there)
	function uncover():Bool {
		if (!view.partial) return false;
		var w = scrolled();
		if (w == null) return false;
		// (a frame's settles after its first: only what is seen itself, where it isn't laid out yet)
		if (rounds++ > 0 && !view.unlaid(w.top, w.top + w.height)) return false;
		var t0 = Timer.stamp(), b0 = DocumentStats.bytes();
		// (a screen around what is seen; what is seen alone where the scroll leaps, a thumb's drag: what it
		// passes isn't seen again. Before the frame is drawn: no box seen without its contents)
		var leaps = Math.abs(w.top - lastTop) > 2 * w.height;
		lastTop = w.top;
		var moved = view.reveal(w.top - (leaps ? 0 : w.height), w.top + w.height + (leaps ? 0 : w.height), w.top);
		if (moved == null) return false;
		stats.laid(Timer.stamp() - t0, DocumentStats.bytes() - b0);
		docHeight = heightOf();
		markDirty();
		keep(w.scroller, moved);
		return true;
	}

	// (the scroller around it, and the part of the document it shows: its top and height; the top as the
	// clamp after the settles leaves it, the document shorter for what was laid out at its end)
	function scrolled():Null<{scroller:Node, top:Float, height:Float}> {
		var sc = parent;
		while (sc != null && sc.style.overflow != Scroll) sc = sc.parent;
		if (sc == null) return null;
		var y = Math.max(0, Math.min(sc.scrollY, @:privateAccess helder.ui.Scrolling.maxScroll(sc, false)));
		return {scroller: sc, top: y - (absY - sc.absY), height: sc.height};
	}

	// (the scroll moved with what it shows: a glide or a drag goes on)
	function keep(sc:Node, by:Float)
		if (by != 0 && ui != null) @:privateAccess helder.ui.Scrolling.setScroll(ui, sc, false, Math.max(0, sc.scrollY + by));

	// ---- layout

	@:noCompletion override public function hasContent():Bool
		return true;

	// (drawn from the document, which tells it changed: not each frame)
	@:allow(helder.ui) override function paintsLive():Bool
		return false;

	@:noCompletion override public function measureContent(text:TextEngine, knownWidth:Float, knownHeight:Float, availWidth:Float, availHeight:Float):Size {
		hook();
		var w = !Math.isNaN(knownWidth) ? knownWidth : Math.isFinite(availWidth) ? availWidth : 800;
		// (the viewport's height: the window's, what vh and the initial containing block's height are)
		var h = ui != null ? ui.height : Math.isFinite(availHeight) ? availHeight : 600;
		if (w != laidWidth || h != laidHeight || view.styles == null) {
			var t0 = Timer.stamp();
			// (a long document laid out where it is seen, what was at the scroll's top kept there)
			var at = scrolled(), anchor = at != null && view.styles != null ? view.anchor(at.top) : null;
			if (at != null) view.within(at.top - h, at.top + at.height + h);
			view.layout(w, h);
			if (anchor != null) keep(at.scroller, view.moved(anchor));
			view.watch();
			stats.laid(Timer.stamp() - t0);
			laidWidth = w;
			laidHeight = h;
			docHeight = heightOf();
			}
		return new Size(w, Math.isNaN(knownHeight) ? Math.max(docHeight, h) : knownHeight);
	}

	// (the root's margin box's bottom, or what overflows it, as far as anything untransformed paints: html { height: 100% })
	function heightOf():Float {
		var f = view.fragments, r = view.root;
		if (r < 0) return 0;
		var b = view.tree.root;
		var h = f.y(r) + f.height(r) + Math.max(0, b.bottomPositive + b.bottomNegative);
		var runs = view.order.chunks(), k = 3;
		while (k < runs.length) {
			if (runs[k] > h && runs[k] < Math.POSITIVE_INFINITY) h = runs[k];
			k += 4;
		}
		return h;
	}

	// ---- paint

	@:noCompletion override public function paintContent(canvas:Canvas, x:Float, y:Float, width:Float, height:Float) {
		if (view.order == null || ui == null) return;
		// (what is seen: the walk's, a scroller's layer recorded over more than the window)
		var w = ui.walk;
		var x0 = Math.max(w.x0, x), y0 = Math.max(w.y0, y), x1 = Math.min(w.x1, x + width), y1 = Math.min(w.y1, y + height);
		if (x1 <= x0 || y1 <= y0) return;
		var t0 = Timer.stamp(), b0 = DocumentStats.bytes();
		canvas.translate(x, y);
		painter.begin(canvas, Math.ceil(width), Math.ceil(height), ui.scale, x0 - x, y0 - y, x1 - x, y1 - y);
		view.paint(painter, [x0 - x, y0 - y, x1 - x, y1 - y]);
		painter.end();
		if (selection != null) {
			// (the selection's rectangles where it is seen alone: a long one's lines elsewhere not asked for)
			var c = ui.selectionColor;
			for (r in view.selection(selection.from, selection.to, y0 - y, y1 - y)) canvas.rect(r.x, r.y, r.width, r.height, 0, c, 0, 0);
		}
		canvas.translate(-x, -y);
		stats.painted(Timer.stamp() - t0, painter.rasters, DocumentStats.bytes() - b0);
	}

	// ---- input

	// (what is under a point of the node: a text position, or an element)
	function at(e:Event):Null<{node:DomNode, offset:Int}>
		return view.hit(e.localX, e.localY);

	static function elementOf(n:Null<DomNode>):Null<Element> {
		while (n != null && n.nodeType != DomNode.ELEMENT_NODE) n = n.parentNode;
		return cast n;
	}

	function moved(e:Event) {
		var h = at(e);
		var el = elementOf(h?.node);
		hover(el);
		if (anchor != null) {
			var to = view.position(e.localX, e.localY);
			if (to != null && (to.node != anchor.node || to.offset != anchor.offset)) {
				dragged = true;
				setSelection(anchor, to);
			}
		}
	}

	// (the element under the pointer and its ancestors hovered, the others not; the cursor its)
	function hover(el:Null<Element>) {
		var chain = [];
		var n = el;
		while (n != null) {
			chain.push(n);
			n = n.parentElement;
		}
		if (chain.length == hoverChain.length && (chain.length == 0 || chain[0] == hoverChain[0])) return;
		for (h in hoverChain) if (chain.indexOf(h) < 0) h.setState(ElementState.HOVER, false);
		for (h in chain) h.setState(ElementState.HOVER, true);
		hoverChain = chain;
		style.cursor = cursorOf(el);
		changed();
	}

	function cursorOf(el:Null<Element>):helder.ui.Cursor {
		if (el == null || view.styles == null) return Auto;
		var c = view.styles.computed(el).keyword(helder.css.CssProperty.Cursor);
		return switch c {
			case "pointer": Pointer;
			case "text": Text;
			case "auto": link(el) != null ? Pointer : Auto;
			case "default": Default;
			case "move": Move;
			case "crosshair": Crosshair;
			case "not-allowed": NotAllowed;
			case "grab": Grab;
			case "grabbing": Grabbing;
			case _: Auto;
		}
	}

	// (a scroll container in the document scrolled: the event kept from the scrollers around the node)
	function wheeled(e:Event) {
		if (view.scrollBy(e.localX, e.localY, e.deltaX, e.deltaY) == null) return;
		layerChanged();
		ui.requestFrame();
		e.preventDefault();
		e.stop();
	}

	function down(e:Event) {
		// (the primary button: 1, a script's 0; not the middle's or the secondary's)
		if (e.button > 1) return;
		var h = at(e);
		var el = elementOf(h?.node);
		pressedElement = el;
		var n = el;
		while (n != null) {
			n.setState(ElementState.ACTIVE, true);
			n = n.parentElement;
		}
		anchor = h != null && h.offset >= 0 ? {node: h.node, offset: h.offset} : view.position(e.localX, e.localY);
		dragged = false;
		if (selection != null) setSelection(null, null);
		focusOn(focusTarget(el), false);
		capture();
		changed();
	}

	function up(e:Event) {
		var el = pressedElement;
		pressedElement = null;
		var n = el;
		while (n != null) {
			n.setState(ElementState.ACTIVE, false);
			n = n.parentElement;
		}
		anchor = null;
		if (!dragged && el != null) {
			var a = link(el);
			if (a != null && elementOf(at(e)?.node) != null && link(elementOf(at(e).node)) == a) follow(a);
		}
		changed();
	}

	// (the selection from one position to another, painted again; null: none)
	function setSelection(from:Null<DomPosition>, to:Null<DomPosition>) {
		selection = from == null || to == null ? null : {from: from, to: to};
		layerChanged();
		if (ui != null) ui.requestFrame();
	}

	// the text selected, as it reads in the DOM (each text node's part in tree order)
	public function selectedText():String {
		var s = selection;
		if (s == null) return "";
		var from = s.from, to = s.to;
		if (from.node.compareDocumentPosition(to.node) & DomNode.DOCUMENT_POSITION_PRECEDING != 0
			|| from.node == to.node && to.offset < from.offset) {
			var t = from;
			from = to;
			to = t;
		}
		var out = new StringBuf(), n:Null<DomNode> = from.node;
		while (n != null) {
			if (n.nodeType == DomNode.TEXT_NODE) {
				var d:String = (cast n : helder.dom.Text).data;
				var a = n == from.node ? from.offset : 0, b = n == to.node ? to.offset : d.length;
				if (b > a) out.add(d.substring(a, b));
			}
			if (n == to.node) break;
			n = next(n);
		}
		return out.toString();
	}

	static function next(n:DomNode):Null<DomNode> {
		if (n.firstChild != null) return n.firstChild;
		while (n != null) {
			if (n.nextSibling != null) return n.nextSibling;
			n = n.parentNode;
		}
		return null;
	}

	// (the <a href> it is in)
	static function link(el:Null<Element>):Null<Element> {
		while (el != null) {
			if (el.localName == "a" && el.hasAttribute("href")) return el;
			el = el.parentElement;
		}
		return null;
	}

	function follow(a:Element)
		if (onLink != null) onLink(helder.css.CssUrl.resolve(options.url, a.getAttribute("href")), a);

	// ---- the keyboard's focus

	static function takesFocus(el:Element):Bool {
		if (el.hasAttribute("tabindex")) return Std.parseInt(el.getAttribute("tabindex")) >= 0;
		return switch el.localName {
			case "a": el.hasAttribute("href");
			case "button" | "select" | "textarea": !el.hasAttribute("disabled");
			case "input": el.getAttribute("type") != "hidden" && !el.hasAttribute("disabled");
			case _: false;
		}
	}

	static function focusTarget(el:Null<Element>):Null<Element> {
		while (el != null && !takesFocus(el)) el = el.parentElement;
		return el;
	}

	// (the focus on el, :focus-visible as a key moved it, :focus-within up from it)
	function focusOn(el:Null<Element>, visible:Bool) {
		var was = focusedElement;
		if (was == el) return;
		if (was != null) {
			was.setState(ElementState.FOCUS | ElementState.FOCUS_VISIBLE, false);
			var n = was;
			while (n != null) {
				n.setState(ElementState.FOCUS_WITHIN, false);
				n = n.parentElement;
			}
		}
		focusedElement = el;
		if (el != null) {
			el.setState(ElementState.FOCUS | (visible ? ElementState.FOCUS_VISIBLE : 0), true);
			var n = el;
			while (n != null) {
				n.setState(ElementState.FOCUS_WITHIN, true);
				n = n.parentElement;
			}
		}
		changed();
	}

	function key(e:Event) {
		if (e.key == helder.ui.Key.TAB) {
			var back = e.mods.has(Shift);
			var all = [], n:Null<DomNode> = document.documentElement;
			while (n != null) {
				if (n.nodeType == DomNode.ELEMENT_NODE && takesFocus(cast n) && view.boxesOf(n).length > 0) all.push((cast n : Element));
				n = next(n);
			}
			if (all.length == 0) return;
			var i = focusedElement == null ? -1 : all.indexOf(focusedElement);
			var j = back ? (i <= 0 ? all.length - 1 : i - 1) : (i + 1) % all.length;
			focusOn(all[j], true);
			reveal(all[j]);
			e.preventDefault();
		} else if (e.key == helder.ui.Key.ENTER && focusedElement != null) {
			var a = link(focusedElement);
			if (a != null) follow(a);
		}
	}

	// An element scrolled to the top of the scroller around the node (a link to "#id")
	public function scrollTo(el:Element)
		reveal(el, true);

	// (an element's first box scrolled into view in the scroller around it: to its top, or a third down when out of view)
	function reveal(el:Element, top = false) {
		var f = view.fragments, boxes = view.boxesOf(el);
		if (boxes.length == 0 || ui == null) return;
		if (view.partial) {
			view.show(boxes[0]);
			docHeight = heightOf();
			markDirty();
		}
		var id = view.fragmentOf(boxes[0]);
		if (id < 0) return;
		var p = f.absolute(id), sc = parent;
		while (sc != null && sc.style.overflow != Scroll) sc = sc.parent;
		if (sc == null) return;
		var at = absY - sc.absY + p.y - sc.scrollY, h = f.height(id);
		if (top) ui.scrollTo(sc, sc.scrollX, Math.max(0, sc.scrollY + at));
		else if (at < 0 || at + h > sc.height) ui.scrollTo(sc, sc.scrollX, Math.max(0, sc.scrollY + at - sc.height / 3));
	}
}

// a place in the document: a text node and an offset in it
typedef DomPosition = {node:DomNode, offset:Int};

// The engine's work for a DocumentNode, in ms: all told, the last, how many
class DocumentStats {
	public var restyles(default, null) = 0;
	public var restyleMs(default, null) = 0.0;
	public var lastRestyle(default, null) = 0.0;
	// what the last update redid (DocumentView.PAINT, ORDER, LAYOUT, TREE)
	public var lastRedo(default, null) = 0;
	public var layouts(default, null) = 0;
	public var layoutMs(default, null) = 0.0;
	// (what the layouts and the paints allocated, in bytes: where a garbage collector knows; else 0)
	public var layoutBytes(default, null) = 0.0;
	public var paintBytes(default, null) = 0.0;
	public var lastLayout(default, null) = 0.0;
	public var paints(default, null) = 0;
	public var paintMs(default, null) = 0.0;
	public var lastPaint(default, null) = 0.0;
	// the paints' drawings made on the CPU (gradients, odd shapes)
	public var rasters(default, null) = 0;

	public function new() {}

	public function reset() {
		restyles = layouts = paints = rasters = 0;
		restyleMs = layoutMs = paintMs = lastRestyle = lastLayout = lastPaint = layoutBytes = paintBytes = 0;
	}

	@:allow(helder.ui.box.DocumentNode) function restyled(s:Float, redo:Int) {
		restyles++;
		restyleMs += lastRestyle = s * 1000;
		lastRedo = redo;
	}

	@:allow(helder.ui.box.DocumentNode) function laid(s:Float, bytes = 0.0) {
		layouts++;
		layoutMs += lastLayout = s * 1000;
		layoutBytes += bytes;
	}

	@:allow(helder.ui.box.DocumentNode) function painted(s:Float, r:Int, bytes = 0.0) {
		paints++;
		paintMs += lastPaint = s * 1000;
		rasters += r;
		paintBytes += bytes;
	}

	@:allow(helder.ui.box.DocumentNode) static inline function bytes():Float
		return #if (target.name == "hxmc") hxmc.GcStats.bytesAllocated() #else 0 #end;
}
