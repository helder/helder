package helder.ui.box;

import haxe.io.Bytes;
import helder.canvas.Bitmap;
import helder.canvas.Painter;
import helder.canvas.doc.Document as PdfDocument;
import helder.canvas.doc.PdfWriter;
import helder.css.CssCascade;
import helder.css.CssMedia.CssMediaContext;
import helder.css.CssPages.CssPage;
import helder.css.CssSheet;
import helder.css.CssStyles;
import helder.css.CssUrl;
import helder.dom.Document;
import helder.ui.flow.BlockFlow;
import helder.ui.flow.BreakToken;
import helder.ui.flow.Breaks;
import helder.ui.flow.Contexts;
import helder.ui.flow.Space;

typedef PagedViewOptions = {
	// the document's URL: what links, images and fonts resolve against
	?url:String,
	// a stylesheet's text by its absolute URL (<link>, @import)
	?load:(url:String) -> Null<String>,
	// an image by its absolute URL
	?image:(url:String) -> Null<Bitmap>,
	// a font file by its absolute URL (@font-face's src)
	?font:(url:String) -> Null<Bytes>,
	?fonts:FontMatch,
	?contexts:Contexts,
	// the user's style sheets (defaults under the author's: a page size)
	?user:Array<CssSheet>,
	// what @media matches and viewport units are of (default: print, the
	// first page's page area)
	?media:CssMediaContext,
	// the most pages (10,000): a layout that makes no progress stops there
	?limit:Int
}

// A page: its page box's size (bleed around it), its margins (top,
// right, bottom, left), its page area (x, y, width, height in the page
// box: inside its margins, border and padding), whether it is a left page
// and a blank one, its @page style, and its content's root fragment (-1:
// none).
typedef Page = {
	index:Int,
	width:Float,
	height:Float,
	bleed:Float,
	margins:Array<Float>,
	area:Array<Float>,
	left:Bool,
	blank:Bool,
	style:CssPage,
	root:Int
}

// A helder.dom document laid out on pages (CSS Paged Media 3, CSS
// Fragmentation 3): each page's @page style (size, margins, bleed; first,
// left and right, blank pages), its content flowed into the page area as
// a fragmentainer (Breaks: break opportunities, forced breaks, avoid,
// orphans and widows; BreakToken: where the next page resumes), each
// page painted on its own (its background, its content), all of them a
// PDF with real text.
//
//   var view = new PagedView(doc);
//   var count = view.layout();
//   File.saveBytes("doc.pdf", view.pdf());
class PagedView {
	public final document:Document;
	public final fragments = new Fragments();
	public final fonts:FontMatch;
	public final pages:Array<Page> = [];
	public var styles(default, null):Null<CssStyles> = null;
	public var tree(default, null):Null<BoxTree> = null;

	final options:PagedViewOptions;
	final images = new Map<String, Null<Bitmap>>();

	public function new(document:Document, ?options:PagedViewOptions) {
		this.document = document;
		this.options = options ?? {};
		fonts = this.options.fonts ?? new FontMatch();
	}

	// Styles, boxes, and the pages: how many.
	public function layout():Int {
		pages.resize(0);
		fragments.clear();
		// (the first page's page area: the cascade again when its @page says another size than it was given)
		var media = options.media ?? {type: "print", width: 794 - 150, height: 1123 - 150, resolution: 1, color: 8};
		for (pass in 0...2) {
			styles = CssCascade.styles(document, {
				media: media,
				load: options.load,
				url: options.url,
				user: options.user,
				hints: true
			});
			if (options.media != null) break;
			var first = pageOf(0, false, false);
			if (first.area[2] == media.width && first.area[3] == media.height) break;
			media = {type: "print", width: first.area[2], height: first.area[3], resolution: 1, color: 8};
		}
		if (options.font != null) fonts.fontFaces(styles.fontFaces, options.font);
		tree = BoxTree.build(document, styles, {contexts: options.contexts, image: image});
		var root = tree.root;
		var rtl = root != null && root.style.rtl;
		var token:Null<BreakToken> = null;
		var i = 0;
		do {
			// (the first page a right one left to right, a left one right to left)
			var left = (i % 2 == 1) != rtl;
			if (token != null && token.side != null && (token.side == "left") != left) {
				pages.push(pageOf(i++, left, true));
				continue;
			}
			var page = pageOf(i++, left, false);
			if (root != null) {
				var w = page.area[2], h = page.area[3];
				var breaks = new Breaks(h, token);
				var f = content(root, breaks, w, h, token == null);
				if (breaks.decide()) f = content(root, breaks, w, h, token == null);
				page.root = f;
				token = breaks.token();
			}
			pages.push(page);
		} while (token != null && i < (options.limit ?? LIMIT));
		return pages.length;
	}

	static inline var LIMIT = 10000;

	// (the root laid out in a page area of w by h, resuming where breaks' token says)
	function content(root:Box, breaks:Breaks, w:Float, h:Float, first:Bool):Int {
		var space = new Space(fragments, fonts, w, h);
		space.fragmentation = breaks;
		var mt = first ? BlockFlow.auto(root.style.model().margin[0], w) : 0.0;
		space.pageTop = Math.isNaN(mt) ? 0 : mt;
		var f = (root.context ?? Contexts.all().flow).layout(root, space);
		var off = BlockFlow.offset(root, w, h);
		fragments.moveTo(f, root.marginLeft + off.x, root.topPositive + root.topNegative + off.y);
		return f;
	}

	// (a page's style, size, margins and page area: auto margins none, percentages of the page's width and height)
	function pageOf(index:Int, left:Bool, blank:Bool):Page {
		var style = styles.pageStyle(index, null, left, blank);
		var m = new BoxStyle(style.style).model();
		var margins = [for (k in 0...4) BlockFlow.auto(m.margin[k], k % 2 == 0 ? style.height : style.width)];
		margins = [for (v in margins) Math.isNaN(v) ? 0.0 : v];
		var inset = [for (k in 0...4) margins[k] + m.border[k] + BlockFlow.res(m.padding[k], k % 2 == 0 ? style.height : style.width)];
		return {
			index: index,
			width: style.width,
			height: style.height,
			bleed: style.bleed,
			margins: margins,
			area: [inset[3], inset[0], Math.max(0, style.width - inset[1] - inset[3]), Math.max(0, style.height - inset[0] - inset[2])],
			left: left,
			blank: blank,
			style: style,
			root: -1
		};
	}

	// Page i painted from its bleed box's top left: its background over
	// the page box and bleed, its border inside its margins, its content
	// in its page area (the root's background, the canvas's, over the page
	// area, positioned in the root's box over all the pages). Snap: glyphs
	// on pixels as a raster's (BoxPainter.snap); a PDF's text keeps layout's
	// places.
	public function paint(i:Int, p:Painter, snap = true) {
		var page = pages[i];
		var b = page.bleed, m = page.margins;
		var style = new BoxStyle(page.style.style);
		Backgrounds.paint(p, style, 0, 0, page.width + 2 * b, page.height + 2 * b, image);
		Borders.paint(p, style, b + m[3], b + m[0], page.width - m[1] - m[3], page.height - m[0] - m[2]);
		if (page.root < 0) return;
		p.save();
		p.translate(b + page.area[0], b + page.area[1]);
		var painter = new BoxPainter(fragments, new PaintOrder(fragments, page.root), image);
		painter.snap = snap;
		painter.canvasArea = [0.0, 0.0, page.area[2], page.area[3]];
		// (the root's box: its fragments on the pages before above this one's, all of them its height)
		var before = 0.0, all = 0.0;
		for (q in pages) if (q.root >= 0) {
			if (q.index < i) before += fragments.height(q.root);
			all += fragments.height(q.root);
		}
		var r = page.root;
		painter.canvasBox = [fragments.x(r), fragments.y(r) - before, fragments.width(r), all];
		painter.paint(p);
		p.restore();
	}

	// The pages as a PDF (real text: its glyphs and their characters).
	public function pdf():Bytes {
		if (pages.length == 0) layout();
		var doc = new PdfDocument();
		for (i in 0...pages.length) {
			var page = pages[i];
			paint(i, doc.newPage(Math.round(page.width + 2 * page.bleed), Math.round(page.height + 2 * page.bleed)), false);
		}
		return PdfWriter.write(doc);
	}

	function image(url:String):Null<Bitmap> {
		if (options.image == null) return null;
		var abs = CssUrl.resolve(options.url, url);
		if (images.exists(abs)) return images.get(abs);
		var b = try options.image(abs) catch (_:Dynamic) null;
		images.set(abs, b);
		return b;
	}
}
