package viewer;

import helder.test.Test;
import viewer.Decode.Decoded;

// A PDF's pages in one column: where each page is at a zoom, which pages
// a scroll shows and which are drawn (at the size shown, sharper after a
// zoom), the page the view is on, go to page, a zoom kept about its point;
// the zoom it opens at (pdf.js's auto) and the zoom from there
function tests() {
	describe("PDF column", () -> {
		// (pages of 600 by 800 points, the third landscape)
		var sizes = [{width: 600.0, height: 800.0}, {width: 600.0, height: 800.0}, {width: 800.0, height: 600.0}, {width: 600.0, height: 800.0}];
		test("the pages stacked, centred, a gap apart, at a zoom", () -> {
			var l = new PdfLayout(sizes);
			l.setView(1000, 700);
			l.setZoom(0.5);
			equals([l.top(0), l.top(1), l.top(2), l.top(3)], [16.0, 428.0, 840.0, 1152.0]);
			equals([l.left(0), l.left(2)], [350.0, 300.0]);
			equals(l.height(), 16 + 400 + 12 + 400 + 12 + 300 + 12 + 400 + 16.0);
			// (fitted to the width: the widest page the view less its margins)
			equals(l.fitWidth(), (1000 - 32) / 800);
			equals(l.width(), 1000.0);
			l.setZoom(2);
			equals(l.width(), 800 * 2 + 32.0);
		});
		test("auto: fitted to the width, at most 110% of the actual size; a landscape document fitted whole", () -> {
			// (A4, upright and landscape; the column of a 1200- and a 2400-point window)
			var a4 = {width: 595.28, height: 841.89}, cap = 1.1 * 96 / 72;
			var upright = new PdfLayout([a4, a4]), landscape = new PdfLayout([{width: a4.height, height: a4.width}]);
			function width(l:PdfLayout, w:Float, h:Float):Int {
				l.setView(w, h);
				l.setZoom(l.auto());
				return Math.round(l.pageWidth(0));
			}
			equals(width(upright, 1200, 800), Math.round(a4.width * cap));
			equals(width(upright, 2400, 1300), 873);
			// (its height: 800 less the margins)
			equals(width(landscape, 1200, 800), Math.round(a4.height * (800 - 32) / a4.width));
			equals(width(landscape, 2400, 1300), Math.round(a4.height * cap));
			// (a phone's: the width, below the cap)
			equals(width(upright, 390, 760), 390 - 32);
			// (centred, the canvas around it)
			upright.setView(2400, 1300);
			upright.setZoom(upright.auto());
			equals(upright.left(0), (2400 - upright.pageWidth(0)) / 2);
		});
		test("the zoom from auto: Fit back to it, Actual Size 96 dpi, the keys a step", () -> {
			var doc = new PdfDoc("doc.pdf", [{width: 595.28, height: 841.89}], 1000, (_, side, done) -> done(fake(side)));
			doc.view(2400, 1300);
			var auto = 1.1 * PdfLayout.ACTUAL;
			equals(doc.layout.zoom, auto);
			equals(doc.percent(), 110);
			doc.step(1);
			equals(doc.layout.zoom, auto * 1.25);
			doc.actual();
			equals(doc.percent(), 100);
			equals(doc.layout.zoom, 96 / 72);
			doc.fit();
			equals(doc.layout.zoom, auto);
			// (auto kept as the window is resized: there under the cap, the width; a zoom is kept)
			doc.view(800, 700);
			equals(doc.layout.zoom, (800 - 32) / 595.28);
			doc.step(-1);
			doc.view(2400, 1300);
			equals(doc.layout.zoom, (800 - 32) / 595.28 * 0.8);
		});
		test("the window resized: laid out again, the page point at the view's top middle kept", () -> {
			var doc = new PdfDoc("doc.pdf", sizes, 1000, (_, side, done) -> done(fake(side)));
			doc.view(1000, 700);
			doc.goTo(2);
			doc.lines(3);
			for (z in [1.0, 3.0]) {
				// (auto, the pages narrower than the view; then zoomed past its width, scrolled across)
				if (z > 1) {
					doc.zoomBy(z, 500, 0);
					doc.scrolled(doc.layout.clampX(doc.x + 200), doc.y);
				}
				var l = doc.layout, before = l.anchor(doc.x, doc.y, l.viewWidth / 2, 0), laid = doc.laid.value;
				doc.view(1600, 900);
				// (what places the pages told: PdfView's boxes follow laid, the zoom unchanged or not)
				equals(doc.laid.value, laid + 1);
				var after = l.anchor(doc.x, doc.y, 800, 0);
				equals(after.page, before.page);
				assert(Math.abs(after.x - before.x) < 1e-6 && Math.abs(after.y - before.y) < 1e-6, '$before, then $after');
				doc.view(1000, 700);
			}
		});
		test("the pages a scroll shows; the page the view is on", () -> {
			var l = new PdfLayout(sizes);
			l.setView(1000, 700);
			l.setZoom(0.5);
			equals(l.visible(0), [0, 1]);
			equals(l.visible(400), [0, 1, 2]);
			// (the view's top in the gap after page 0: page 0 left out)
			equals(l.visible(420), [1, 2]);
			equals(l.current(0), 0);
			equals(l.current(300), 1);
			equals(l.pageAt(1200), 3);
		});
		test("go to a page: its top a gap below the view's; the last within the content", () -> {
			var l = new PdfLayout(sizes);
			l.setView(1000, 700);
			l.setZoom(0.5);
			equals(l.scrollFor(1), 428 - 12.0);
			equals(l.scrollFor(3), l.height() - 700);
			equals(l.scrollFor(0), 4.0);
		});
		test("a zoom about a point keeps it over the same point of its page", () -> {
			var l = new PdfLayout(sizes);
			l.setView(1000, 700);
			l.setZoom(0.5);
			// (the view scrolled to 400: its point (500, 300) is page 1's (300 - 216... in points)
			var x = 0.0, y = 400.0, vx = 500.0, vy = 300.0;
			var p = l.pageAt(y + vy), fx = (x + vx - l.left(p)) / 0.5, fy = (y + vy - l.top(p)) / 0.5;
			var s = l.zoomAbout(1, x, y, vx, vy);
			equals(l.zoom, 1.0);
			equals([s.x + vx - l.left(p), s.y + vy - l.top(p)], [fx * 1, fy * 1]);
		});
		test("the pages drawn: those in view first, the next and previous, at the size shown; sharper after a zoom", () -> {
			var asked = [];
			var doc = new PdfDoc("doc.pdf", sizes, 1000, (key, side, done) -> {
				asked.push(Decode.parseKey(key).page + "@" + side);
				done(fake(side));
			});
			doc.density = 2;
			doc.view(1000, 700);
			// (auto: fitted to the width, 968 / 800 a point, under its cap; page 0's long side 800 points, at 2 pixels a point)
			equals(doc.layout.zoom, 968 / 800);
			equals(doc.shown.value, [0, 1]);
			equals(asked, ["0@1936", "1@1936"]);
			equals(doc.page.value, 0);
			// (scrolled to page 2: it, the one before and after drawn; page 0 let go two pages on)
			doc.goTo(2);
			equals(doc.page.value, 2);
			equals(doc.shown.value, [1, 2, 3]);
			assert(doc.image(2) != null && doc.image(3) != null, "pages 2 and 3 drawn");
			// (a zoom in about the view's middle: drawn again larger)
			asked.resize(0);
			doc.zoomBy(2, 500, 350);
			assert(asked.length > 0 && Lambda.foreach(asked, a -> Std.parseInt(a.split("@")[1]) > 1936), asked.join(" "));
			equals(doc.percent(), Math.round(968 / 800 * 2 / PdfLayout.ACTUAL * 100));
			// (Page Down: a screen on)
			var y = doc.y;
			doc.screens(1);
			equals(doc.y, Math.min(y + 700 * 0.9, doc.layout.height() - 700));
		});
		test("a page that cannot be drawn is not asked for again", () -> {
			var n = 0;
			var doc = new PdfDoc("doc.pdf", sizes, 1000, (key, side, done) -> {
				n++;
				done({width: 0, height: 0, pixelsWidth: 0, pixelsHeight: 0, frames: [], repetitions: 0, format: "PDF", fileSize: 0, page: 0, pages: 0,
					error: "A damaged PDF", errorKind: "corrupt"});
			});
			doc.view(1000, 700);
			doc.scrolled(0, 10);
			doc.scrolled(0, 20);
			equals(n, 2);
			assert(doc.broken(0), "page 1 broken");
		});
	});
}

// (a page drawn: a gray square of side pixels)
private function fake(side:Int):Decoded
	return {
		width: side,
		height: side,
		pixelsWidth: side,
		pixelsHeight: side,
		frames: [{pixels: new hxmc.Buffer(side * side * 4), delay: 0.0}],
		repetitions: 0,
		format: "PDF",
		fileSize: 0,
		page: 0,
		pages: 4,
		error: null,
		errorKind: ""
	};
