package viewer;

import helder.image.Image;
import viewer.Decode.Decoded;
import viewer.PageText;
import viewer.PdfLayout;

// A PDF shown as one continuous column of pages (PdfLayout), without a
// window: where it is scrolled, its zoom (PdfLayout.auto until zoomed
// otherwise, then about a point), the page the view is on, and the pages
// drawn: those in view first, then the one before and after, each at the
// size shown in device pixels (again when a zoom needs more, the one drawn
// smaller shown meantime), two at a time; those two pages or more out of
// view let go. Its PdfView is the window's.
class PdfDoc {
	// (drawn again when the size shown is this much more, or this much less, than the one drawn)
	static inline var SHARPER = 1.1;
	static inline var SMALLER = 2.5;
	// a line's scroll (Up, Down) and a screen's share (Page Up, Page Down)
	public static inline var LINE = 40.0;
	static inline var SCREEN = 0.9;

	public final path:String;
	public final layout:PdfLayout;
	public final fileSize:Int;
	// the page the view is on, the zoom, where the view is to scroll to (the
	// model's moves: a page gone to, a zoom about a point), the pages to make
	// and a render that landed (what the view follows)
	public final page = new Cell(0);
	public final zoom = new Cell(1.0);
	// (the layout laid out again: a zoom, a view's new size; what places the pages reads it)
	public final laid = new Cell(0);
	public final scroll = new Cell({x: 0.0, y: 0.0});
	public final shown:Cell<Array<Int>> = new Cell([]);
	public final rendered = new Cell(0);
	// (a page's text landed: its PdfText's)
	public final texted = new Cell(0);
	// device pixels a point (the window's scale)
	public var density = 1.0;
	// the page moved (the viewer's title)
	public var onPage:Null<Int->Void> = null;

	public var x(default, null) = 0.0;
	public var y(default, null) = 0.0;

	var fitted = true;
	var sized = false;
	var busy = 0;
	final decode:(key:String, side:Int, done:Decoded->Void) -> Void;
	final renders = new Map<Int, {side:Int, image:Image}>();
	final asked = new Map<Int, Int>();
	// (pages that could not be drawn: not asked again)
	final failed = new Map<Int, Bool>();
	// (each page's text as it lands with its drawing, its boxes while it is
	// near; every page's once a selection is begun (wanted), one at a time
	// after the drawings)
	final texts = new Map<Int, PageText>();
	var wanted = false;
	var reading = -1;

	public function new(path:String, sizes:Array<PageSize>, fileSize:Int, decode:(key:String, side:Int, done:Decoded->Void) -> Void) {
		this.path = path;
		this.fileSize = fileSize;
		this.decode = decode;
		layout = new PdfLayout(sizes);
	}

	public var pages(get, never):Int;

	function get_pages():Int
		return layout.sizes.length;

	// the view's size (its first: auto, at the top; again: the page point at
	// the view's top middle kept there, the column centred in the new width)
	public function view(width:Float, height:Float) {
		if (width <= 0 || height <= 0 || (sized && width == layout.viewWidth && height == layout.viewHeight)) return;
		var a = sized ? layout.anchor(x, y, layout.viewWidth / 2, 0) : null;
		sized = true;
		layout.setView(width, height);
		if (fitted) layout.setZoom(layout.auto());
		laid(laid.value + 1);
		var s = a == null ? {x: layout.clampX(0), y: layout.clampY(0)} : layout.placed(a, width / 2, 0);
		moved(s.x, s.y);
	}

	// the view scrolled there (its own: the wheel, a trackpad, its bars)
	public function scrolled(sx:Float, sy:Float) {
		x = sx;
		y = sy;
		update();
	}

	// --- zoom

	// to z with the view's point (vx, vy) kept over the same point of its page
	public function zoomTo(z:Float, vx:Float, vy:Float) {
		fitted = false;
		var s = layout.zoomAbout(z, x, y, vx, vy);
		moved(s.x, s.y);
	}

	public function zoomBy(k:Float, vx:Float, vy:Float)
		zoomTo(layout.zoom * k, vx, vy);

	// a step in or out about the view's middle (the keys)
	public function step(dir:Int)
		zoomBy(dir > 0 ? 1.25 : 0.8, layout.viewWidth / 2, layout.viewHeight / 2);

	// auto again (as it opened), the top of the view where it was in its page
	public function fit() {
		var s = layout.zoomAbout(layout.auto(), x, y, layout.viewWidth / 2, 0);
		fitted = true;
		moved(s.x, s.y);
	}

	public function actual()
		zoomTo(PdfLayout.ACTUAL, layout.viewWidth / 2, layout.viewHeight / 2);

	// the zoom of the actual size (96 dpi)
	public function percent():Int
		return Math.round(layout.zoom / PdfLayout.ACTUAL * 100);

	// --- moves

	// a page's top at the view's top
	public function goTo(i:Int) {
		if (pages == 0) return;
		i = i < 0 ? 0 : i >= pages ? pages - 1 : i;
		moved(layout.clampX(x), layout.scrollFor(i));
	}

	// by screens (Page Down: 1, Page Up: -1), or by lines
	public function screens(n:Float)
		moved(x, layout.clampY(y + n * layout.viewHeight * SCREEN));

	public function lines(n:Float)
		moved(x, layout.clampY(y + n * LINE));

	function moved(sx:Float, sy:Float) {
		x = sx;
		y = sy;
		zoom(layout.zoom);
		scroll({x: sx, y: sy});
		update();
	}

	// --- the pages drawn

	// a page's drawing, the largest there is (null: none yet)
	public function image(i:Int):Null<Image> {
		var r = renders.get(i);
		return r == null ? null : r.image;
	}

	// whether a page could not be drawn (its place stays blank)
	public function broken(i:Int):Bool
		return failed.exists(i);

	// what is drawn: its side in pixels (tests)
	public function drawn(i:Int):Int {
		var r = renders.get(i);
		return r == null ? 0 : r.side;
	}

	// a page's text (null: not read yet)
	public function text(i:Int):Null<PageText>
		return texts.get(i);

	// every page's text read, from the page the view is on out
	public function wantText() {
		if (wanted) return;
		wanted = true;
		update();
	}

	function update() {
		var p = layout.current(y);
		if (p != page.value) {
			page(p);
			if (onPage != null) onPage(p);
		}
		var vis = layout.visible(y);
		if (vis.length == 0) return;
		var first = vis[0], last = vis[vis.length - 1];
		var near = vis.copy();
		if (first > 0) near.unshift(first - 1);
		if (last + 1 < pages) near.push(last + 1);
		if (near.join(",") != shown.value.join(",")) shown(near);
		// (two pages or more out of view: let go)
		for (k in [for (k in renders.keys()) k])
			if (k < first - 2 || k > last + 2) {
				renders.remove(k);
				var t = texts.get(k);
				if (t != null && t.boxes.length > 0) texts.set(k, {text: t.text, boxes: []});
			}
		// (in view first, from the top; then the one after, the one before)
		var order = vis.concat([for (i in near) if (vis.indexOf(i) < 0) i]);
		for (i in order) {
			if (busy >= 2) return;

			var need = side(i), have = renders.get(i), was = asked.get(i);
			if (have != null && have.side >= need / SHARPER && have.side <= need * SMALLER) continue;
			if (was != null || failed.exists(i)) continue;
			asked.set(i, need);
			busy++;
			decode(Decode.key(path, i), need, d -> landed(i, need, d));
		}
		if (!wanted || busy > 0 || reading >= 0) return;
		var p = page.value;
		for (r in 0...pages) {
			for (i in [p - r, p + r]) {
				if (i < 0 || i >= pages || texts.exists(i) || failed.exists(i)) continue;
				reading = i;
				decode(Decode.key(path, i), PdfPages.TEXT, d -> read(i, d));
				return;
			}
		}
	}

	// (a page's text alone: kept without its boxes unless the page is near)
	function read(i:Int, d:Decoded) {
		reading = -1;
		Decode.release(d);
		var t = d.text ?? {text: "", boxes: []};
		if (!texts.exists(i)) {
			var near = shown.value.indexOf(i) >= 0;
			texts.set(i, near ? t : {text: t.text, boxes: []});
			texted(texted.value + 1);
		}
		update();
	}

	// (the larger side shown, in device pixels, at most PdfPages' largest)
	function side(i:Int):Int
		return Std.int(Math.min(PdfPages.MAX_SIDE, Math.ceil(Math.max(layout.pageWidth(i), layout.pageHeight(i)) * density)));

	function landed(i:Int, need:Int, d:Decoded) {
		busy--;
		asked.remove(i);
		var t = texts.get(i);
		if (d.text != null && (t == null || t.boxes.length == 0)) {
			texts.set(i, d.text);
			texted(texted.value + 1);
		}
		if (d.error == null && d.frames.length > 0) {
			// (the pixels the image's now: off the heap, freed when it goes)
			var img = Image.ofHeld(d.pixelsWidth, d.pixelsHeight, d.frames[0].pixels, false);
			d.frames = [];
			renders.set(i, {side: need, image: img});
			rendered(rendered.value + 1);
		} else {
			failed.set(i, true);
			Decode.release(d);
		}
		update();
	}
}
