package viewer;

import helder.ui.HeightIndex;

typedef PageSize = {width:Float, height:Float};

// A PDF's pages laid out as a browser shows one (pdf.js's default):
// stacked down one column, each centred, GAP apart, MARGIN around them,
// at a zoom (view points a PDF point; ACTUAL: 100%, 96 dpi). The
// pages' offsets are a HeightIndex's (each row a page and the gap after
// it), so a page at a scroll and a scroll for a page are lookups. Pure:
// what the view shows, the tests read.
class PdfLayout {
	public static inline var GAP = 12.0;
	public static inline var MARGIN = 16.0;
	public static inline var MIN_ZOOM = 0.1;
	public static inline var MAX_ZOOM = 8.0;
	// a page at its actual size: its points at 96 dpi (pdf.js's 100%)
	public static inline var ACTUAL = 96 / 72;
	// (auto's largest, of the actual size: pdf.js's MAX_AUTO_SCALE is 1.25; a
	// little narrower here, an A4 page some 873 points wide)
	static inline var MAX_AUTO = 1.1;

	public final sizes:Array<PageSize>;
	public var zoom(default, null) = 1.0;
	public var viewWidth(default, null) = 0.0;
	public var viewHeight(default, null) = 0.0;

	final rows:HeightIndex;
	final widest:Float;

	public function new(sizes:Array<PageSize>) {
		this.sizes = sizes;
		var w = 1.0;
		for (s in sizes)
			if (s.width > w) w = s.width;
		widest = w;
		rows = new HeightIndex(0, sizes.length);
		setZoom(1);
	}

	public function setView(width:Float, height:Float) {
		viewWidth = width;
		viewHeight = height;
	}

	// the zoom where the widest page fills the view's width less the margins
	public function fitWidth():Float
		return clamp((viewWidth - 2 * MARGIN) / widest);

	// pdf.js's "auto": fitted to the width, at most 110% of the actual
	// size (a wide window's column not as wide as it); a landscape document
	// (its first page) fitted whole, its height too
	public function auto():Float {
		var z = Math.min(fitWidth(), MAX_AUTO * ACTUAL), first = sizes.length > 0 ? sizes[0] : null;
		if (first != null && first.width > first.height) z = Math.min(z, (viewHeight - 2 * MARGIN) / first.height);
		return clamp(z);
	}

	public function setZoom(z:Float) {
		zoom = clamp(z);
		for (i in 0...sizes.length)
			rows.set(i, sizes[i].height * zoom + GAP);
	}

	static function clamp(z:Float):Float
		return z < MIN_ZOOM ? MIN_ZOOM : z > MAX_ZOOM ? MAX_ZOOM : z;

	// the content's size: the pages and their margins, at least the view's
	public function width():Float
		return Math.max(viewWidth, widest * zoom + 2 * MARGIN);

	public function height():Float
		return Math.max(viewHeight, 2 * MARGIN + rows.offsetOf(sizes.length) - (sizes.length > 0 ? GAP : 0));

	// a page's box in the content
	public function left(i:Int):Float
		return (width() - sizes[i].width * zoom) / 2;

	public function top(i:Int):Float
		return MARGIN + rows.offsetOf(i);

	public function pageWidth(i:Int):Float
		return sizes[i].width * zoom;

	public function pageHeight(i:Int):Float
		return sizes[i].height * zoom;

	// the page at a height of the content (a gap: the page above it)
	public function pageAt(y:Float):Int
		return sizes.length == 0 ? -1 : rows.rowAt(y - MARGIN);

	// the pages a view scrolled to y shows, top to bottom
	public function visible(y:Float):Array<Int> {
		if (sizes.length == 0) return [];
		var a = pageAt(y), b = pageAt(y + viewHeight);
		// (a gap at an edge: the page past it left out)
		if (a < b && top(a) + pageHeight(a) <= y) a++;
		if (b > a && top(b) >= y + viewHeight) b--;
		return [for (i in a...b + 1) i];
	}

	// the page the view is on: the one at a third of its height (as a reader's eye)
	public function current(y:Float):Int
		return pageAt(y + viewHeight / 3);

	// where to scroll for a page: its top, a gap above it
	public function scrollFor(i:Int):Float
		return clampY(top(i) - GAP);

	public function clampX(x:Float):Float
		return Math.max(0, Math.min(x, width() - viewWidth));

	public function clampY(y:Float):Float
		return Math.max(0, Math.min(y, height() - viewHeight));

	// the zoom changed to z with the point (vx, vy) of the view, scrolled
	// to (x, y), staying over the same point of its page: the new scroll
	public function zoomAbout(z:Float, x:Float, y:Float, vx:Float, vy:Float):{x:Float, y:Float} {
		var a = anchor(x, y, vx, vy);
		setZoom(z);
		return placed(a, vx, vy);
	}

	// the page and its point (in points) at the view's point (vx, vy), scrolled to (x, y)
	public function anchor(x:Float, y:Float, vx:Float, vy:Float):{page:Int, x:Float, y:Float} {
		if (sizes.length == 0) return {page: -1, x: 0, y: 0};
		var cx = x + vx, cy = y + vy, p = pageAt(cy);
		return {page: p, x: (cx - left(p)) / zoom, y: (cy - top(p)) / zoom};
	}

	// the scroll that puts an anchor's page point at the view's point (vx, vy), as the layout is now
	public function placed(a:{page:Int, x:Float, y:Float}, vx:Float, vy:Float):{x:Float, y:Float} {
		if (a.page < 0) return {x: 0, y: 0};
		return {x: clampX(left(a.page) + a.x * zoom - vx), y: clampY(top(a.page) + a.y * zoom - vy)};
	}
}
