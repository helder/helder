package helder.ui.box;

import haxe.Timer;
import helder.dom.Document;
import helder.dom.Element;
import helder.ui.Canvas;
import helder.ui.Event;
import helder.ui.Size;
import helder.ui.TextEngine;
import helder.ui.box.DocumentView.DocumentViewOptions;

// A helder.dom document shown in a helder.ui tree: styled, laid out at the
// node's width (its height the document's) and painted by the engine
// (DocumentView: helder.css, helder.ui.box and flow), its fragments in view
// drawn through UiPainter into what Ui.paint records. Put in a scroller,
// the compositor scrolls it: a scroll restyles and lays out nothing, and
// paints only as the scroller's layer is recorded over more of it. The
// wheel scrolls a scroll container in the document first.
//
//   var page = new DocumentNode(Dom.parse(html), {url: url});
//   scroller.append(page);
@:access(helder.ui.Ui)
class DocumentNode extends helder.ui.Node {
	public final view:DocumentView;
	// the engine's own work (ms, all told and the last of each): layouts, paints recorded
	public final stats = new DocumentStats();

	final painter = new UiPainter(null, 0, 0);
	var laidWidth = Math.NaN;
	var laidHeight = Math.NaN;
	var docHeight = 0.0;

	public function new(document:Document, ?options:DocumentViewOptions) {
		super("document");
		view = new DocumentView(document, options);
		onWheel = wheeled;
	}

	public var document(get, never):Document;

	inline function get_document():Document
		return view.document;

	// ---- layout

	@:noCompletion override public function hasContent():Bool
		return true;

	// (drawn from the document, which tells it changed: not each frame)
	@:allow(helder.ui) override function paintsLive():Bool
		return false;

	@:noCompletion override public function measureContent(text:TextEngine, knownWidth:Float, knownHeight:Float, availWidth:Float, availHeight:Float):Size {
		var w = !Math.isNaN(knownWidth) ? knownWidth : Math.isFinite(availWidth) ? availWidth : 800;
		// (the viewport's height: the window's, what vh and the initial containing block's height are)
		var h = ui != null ? ui.height : Math.isFinite(availHeight) ? availHeight : 600;
		if (w != laidWidth || h != laidHeight || view.styles == null) {
			var t0 = Timer.stamp();
			view.layout(w, h);
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
		var t0 = Timer.stamp();
		canvas.translate(x, y);
		painter.begin(canvas, Math.ceil(width), Math.ceil(height), ui.scale, x0 - x, y0 - y, x1 - x, y1 - y);
		view.paint(painter, [x0 - x, y0 - y, x1 - x, y1 - y]);
		painter.end();
		canvas.translate(-x, -y);
		stats.painted(Timer.stamp() - t0, painter.rasters);
	}

	// ---- scrolling

	// (a scroll container in the document scrolled: the event kept from the scrollers around the node)
	function wheeled(e:Event) {
		if (view.scrollBy(e.localX, e.localY, e.deltaX, e.deltaY) == null) return;
		layerChanged();
		ui.requestFrame();
		e.preventDefault();
		e.stop();
	}

	// An element scrolled to the top of the scroller around the node (a link to "#id")
	public function scrollTo(el:Element)
		reveal(el, true);

	// (an element's first box scrolled into view in the scroller around it: to its top, or a third down when out of view)
	function reveal(el:Element, top = false) {
		var f = view.fragments, boxes = view.boxesOf(el);
		if (boxes.length == 0 || ui == null) return;
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

// The engine's work for a DocumentNode, in ms: all told, the last, how many
class DocumentStats {
	public var layouts(default, null) = 0;
	public var layoutMs(default, null) = 0.0;
	public var lastLayout(default, null) = 0.0;
	public var paints(default, null) = 0;
	public var paintMs(default, null) = 0.0;
	public var lastPaint(default, null) = 0.0;
	// the paints' drawings made on the CPU (gradients, odd shapes)
	public var rasters(default, null) = 0;

	public function new() {}

	public function reset() {
		layouts = paints = rasters = 0;
		layoutMs = paintMs = lastLayout = lastPaint = 0;
	}

	@:allow(helder.ui.box.DocumentNode) function laid(s:Float) {
		layouts++;
		layoutMs += lastLayout = s * 1000;
	}

	@:allow(helder.ui.box.DocumentNode) function painted(s:Float, r:Int) {
		paints++;
		paintMs += lastPaint = s * 1000;
		rasters += r;
	}
}
