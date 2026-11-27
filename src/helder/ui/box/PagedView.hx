package helder.ui.box;

import haxe.io.Bytes;
import helder.canvas.Bitmap;
import helder.canvas.Painter;
import helder.canvas.doc.Document as PdfDocument;
import helder.canvas.doc.PdfWriter;
import helder.css.CssCascade;
import helder.css.CssItems;
import helder.css.CssProperty;
import helder.css.CssRunning;
import helder.css.CssTerm;
import helder.css.CssMedia;
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
	// what @media matches (default: print, an A4 page, CssMedia.PRINT: not
	// what the document's @page rules make of it, as browsers have it);
	// viewport units are the first page's page area
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
	root:Int,
	// its page counter (counter(page)'s), its margin boxes' fragments (in the page box)
	number:Int,
	boxes:Array<Int>
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
		// (viewport units: the first page's area, its @page size less its margins; the cascade again when
		// that isn't what the cascade first took)
		var viewport:Null<{width:Float, height:Float}> = null;
		for (pass in 0...2) {
			styles = CssCascade.styles(document, {
				media: options.media ?? CssMedia.PRINT,
				viewport: viewport,
				load: options.load,
				url: options.url,
				user: options.user,
				hints: true
			});
			var area = styles.pageStyle(0, null, false, false).area(), seen = styles.viewport();
			if (area.width == seen.width && area.height == seen.height) break;
			viewport = area;
		}
		if (options.font != null) fonts.fontFaces(styles.fontFaces, options.font);
		tree = BoxTree.build(document, styles, {contexts: options.contexts, image: image, paged: true});
		paginate();
		// (cross-references to the pages their targets are on: the pages again when one's text changed)
		if (tree.targets.length > 0 && tree.resolve(pageWith)) {
			afresh(tree.root);
			pages.resize(0);
			fragments.clear();
			paginate();
		}
		margins();
		return pages.length;
	}

	// (the content flowed into pages, page after page from the break before)
	function paginate() {
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
	}

	// (the page, from 1, an element's first box is on; 0: none)
	function pageWith(el:helder.dom.Element):Int {
		for (page in pages) if (page.root >= 0 && holds(page.root, el)) return page.index + 1;
		return 0;
	}

	function holds(id:Int, el:helder.dom.Element):Bool {
		if (fragments.box(id).node == el) return true;
		var c = fragments.first(id);
		while (c >= 0) {
			if (holds(c, el)) return true;
			c = fragments.next(c);
		}
		return false;
	}

	static function afresh(b:Null<Box>) {
		if (b == null) return;
		b.cacheFragment = -1;
		b.minContent = b.maxContent = Math.NaN;
		var c = b.first;
		while (c != null) {
			afresh(c);
			c = c.next;
		}
	}

	// (each page's margin boxes, once the pages are counted: the page counter
	// its, counter(pages) theirs, string() and element() as each page has them)
	function margins() {
		var strings = new CssRunning<String>(), running = new CssRunning<Box>();
		var assigned = new haxe.ds.ObjectMap<helder.dom.Element, Bool>();
		var flow = Contexts.all().flow;
		var number = 0;
		for (page in pages) {
			strings.page();
			running.page();
			// (an inline-level running element has no place of its own: the first page's)
			if (page.index == 0) for (r in tree.running) if (r.holder == null) running.assign(r.name, r.box, true);
			if (page.root >= 0) assign(page.root, strings, running, assigned, {shown: false});
			number = counter(page, number);
			page.number = number;
			var boxes = new Map<String, Box>();
			for (name in PageMargins.NAMES) {
				var b = marginBox(page, name, strings, running, number);
				if (b != null) boxes.set(name, b);
			}
			var space = new Space(fragments, fonts, page.width, page.height);
			page.boxes = PageMargins.layout(boxes, page.width, page.height, page.margins, space, flow);
		}
	}

	// (the page counter on a page: incremented, or as its @page's counter-reset, -set and -increment say)
	function counter(page:Page, before:Int):Int {
		var css = page.style.style, value = before, incremented = false;
		for (c in CssItems.counters(css.terms(CounterReset))) if (c.name == "page") value = c.value ?? 0;
		for (c in CssItems.counters(css.terms(CounterIncrement))) if (c.name == "page") {
			value += c.value ?? 1;
			incremented = true;
		}
		if (!incremented) value++;
		for (c in CssItems.counters(css.terms(CounterSet))) if (c.name == "page") value = c.value ?? 0;
		return value;
	}

	// (string-set's and running elements' assignments on a page, in its fragments' order; at its start
	// while nothing shown comes before)
	function assign(id:Int, strings:CssRunning<String>, running:CssRunning<Box>, assigned:haxe.ds.ObjectMap<helder.dom.Element, Bool>,
			at:{shown:Bool}) {
		var kind = fragments.kind(id), b = fragments.box(id);
		if (kind == Fragments.TEXT || b.kind == BlockReplaced || b.kind == InlineReplaced) at.shown = true;
		if (kind == Fragments.BOX || kind == Fragments.SPAN) {
			if (b.flags & Box.RUNNING != 0) for (r in tree.running) if (r.holder == b) running.assign(r.name, r.box, !at.shown);
			var el = b.node != null && b.node.nodeType == helder.dom.Node.ELEMENT_NODE ? (cast b.node : helder.dom.Element) : null;
			var set = el == null || assigned.exists(el) ? null : tree.strings.get(el);
			if (set != null) {
				assigned.set(el, true);
				for (v in set) strings.assign(v.name, v.value, !at.shown);
			}
		}
		var c = fragments.first(id);
		while (c >= 0) {
			assign(c, strings, running, assigned, at);
			c = fragments.next(c);
		}
	}

	// (a margin box with content, null without: its text, counter(page) and counter(pages), string() and
	// element() as the page has them, images; text beside a running element's blocks in blocks of its own)
	function marginBox(page:Page, name:String, strings:CssRunning<String>, running:CssRunning<Box>, number:Int):Null<Box> {
		var css = styles.marginBoxStyle(page.index, null, page.left, page.blank, name);
		var items = css == null ? null : CssItems.content(css.terms(Content));
		if (items == null) return null;
		var s = new BoxStyle(css);
		var kids:Array<Box> = [], text = new StringBuf();
		function flush() {
			if (text.length == 0) return;
			var t = new Box(Text, s);
			t.text = text.toString();
			kids.push(t);
			text = new StringBuf();
		}
		for (item in items) switch item {
			case Text(t): text.add(t);
			case Counter("page", style): text.add(tree.counters.formats.format(number, style));
			case Counter("pages", style): text.add(tree.counters.formats.format(pages.length, style));
			case StringValue(n, which): text.add(strings.value(n, which) ?? "");
			case RunningElement(n, which):
				var b = running.value(n, which);
				if (b != null) {
					flush();
					kids.push(b);
				}
			case Image(Url(url, _)):
				flush();
				var b = new Box(InlineReplaced, s);
				b.image = image(url);
				kids.push(b);
			case _:
		}
		flush();
		var root = new Box(Block, s);
		var blocks = Lambda.exists(kids, k -> k.blockLevel);
		for (k in kids) if (blocks && !k.blockLevel) {
			var a = new Box(Block, s.anonymousChild());
			a.append(k);
			root.append(a);
		} else root.append(k);
		return root;
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
			root: -1,
			number: 0,
			boxes: []
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
		if (page.root >= 0) contentOf(i, p, snap);
		marginsOf(page, p, b, snap);
	}

	// (its content in its page area)
	function contentOf(i:Int, p:Painter, snap:Bool) {
		var page = pages[i];
		var b = page.bleed;
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

	// (its margin boxes, over its content, from the bleed box's top left)
	function marginsOf(page:Page, p:Painter, bleed:Float, snap:Bool) {
		if (page.boxes.length == 0) return;
		p.save();
		p.translate(bleed, bleed);
		for (f in page.boxes) {
			var painter = new BoxPainter(fragments, new PaintOrder(fragments, f), image);
			painter.snap = snap;
			painter.propagate = false;
			painter.paint(p);
		}
		p.restore();
	}

	// The pages as a PDF (real text: its glyphs and their characters).
	public function pdf():Bytes {
		if (pages.length == 0) layout();
		var doc = new PdfDocument();
		// (page labels: the page counter, a range each time it doesn't go on by one)
		var last = -1;
		for (page in pages) {
			if (page.number != last + 1) doc.label(page.index, "D", "", page.number);
			last = page.number;
		}
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
