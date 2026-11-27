package helder.ui.box;

import haxe.io.Bytes;
import helder.canvas.Bitmap;
import helder.canvas.Matrix;
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
import helder.dom.Dom;
import helder.ui.box.Len.Lens;
import helder.ui.flow.BlockFlow;
import helder.ui.flow.BreakToken;
import helder.ui.flow.Breaks;
import helder.ui.flow.Repeated;
import helder.ui.flow.Contexts;
import helder.ui.flow.Fragmentation.Deferred;
import helder.ui.flow.Positioned;
import helder.ui.flow.Space;

using StringTools;

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
	// its counters and generated content (default CssCounters: pages have their numbers)
	?counters:helder.css.CssStyles->helder.css.CssCounting,
	// the user's style sheets (defaults under the author's: a page size)
	?user:Array<CssSheet>,
	// what @media matches (default: print, an A4 page, CssMedia.PRINT: not
	// what the document's @page rules make of it, as browsers have it);
	// viewport units are the first page's page area
	?media:CssMediaContext,
	// the most pages (10,000): a layout that makes no progress stops there
	?limit:Int
}

// A page: its output size (bleed around it), its margins and area in
// layout coordinates, whether it is a left page and a blank one, its
// @page style, and its content's root fragment (-1: none).
typedef Page = {
	index:Int,
	// its page type's name (the page property; null: none)
	name:Null<String>,
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
// PDF with real text (its pages in points: A4 595 by 842).
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
	final svgs = new Map<String, Null<helder.canvas.Svg>>();

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
		tree = BoxTree.build(document, styles, {contexts: options.contexts ?? Contexts.all(), counters: options.counters ?? s -> new helder.css.CssCounters(s), image: image, svg: svg, paged: true});
		fixed = null;
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
		var deferred:Array<{d:Deferred, page:Int}> = [];
		do {
			// (the first page a right one left to right, a left one right to left)
			var left = (i % 2 == 1) != rtl;
			// (its name: the page property of what it starts with, a blank page's the next one's)
			var name = token != null ? token.name : root != null ? Breaks.first(root) : null;
			if (token != null && token.side != null && (token.side == "left") != left) {
				pages.push(pageOf(i++, left, true, name));
				continue;
			}
			var page = pageOf(i++, left, false, name);
			if (root != null) {
				var w = page.area[2], h = page.area[3];
				var breaks = new Breaks(h, token);
				var f = content(root, breaks, w, h, token == null);
				if (breaks.decide()) f = content(root, breaks, w, h, token == null);
				page.root = f;
				token = breaks.token();
				for (d in breaks.deferred) deferred.push({d: d, page: pages.length});
			}
			pages.push(page);
		} while (token != null && i < (options.limit ?? LIMIT));
		if (root != null) positioned(deferred);
	}

	// (the absolutely positioned boxes deferred: each in its containing block stitched across the pages (its
	// fragments' padding boxes one after the other, as the pages' areas are; the initial containing block the
	// first page's area at the flow's start), then laid out from the page its top is on and broken across the
	// pages after as it needs, pages added for it; the boxes deferred in its layout after it)
	function positioned(queue:Array<{d:Deferred, page:Int}>) {
		if (queue.length == 0) return;
		var flow:BlockFlow = cast (options.contexts ?? Contexts.all()).flow;
		var k = 0;
		while (k < queue.length && k < (options.limit ?? LIMIT)) {
			var e = queue[k++], d = e.d;
			var cb = containing(d, e.page);
			if (cb == null) continue;
			var space = spaceFor(cb.w, cb.h);
			// (its fixed descendants: on every page already)
			space.fixed = new Positioned();
			var at = flow.positionedBox(d.box, space, cb.sx, cb.sy, cb.w, cb.h, d.align);
			var x = cb.x + at.x, height = fragments.height(at.fragment);
			var p = pageAt(cb.top + at.y);
			var o = cb.top + at.y - top(p);
			if (o + height <= pages[p].area[3] + 0.01) {
				adopt(p, at.fragment, x, o);
				continue;
			}
			// (broken: its height as set or stretched kept, its content's otherwise)
			var st = d.box.style, fixedHeight = !Lens.isAuto(st.model().height) || !Lens.isAuto(st.inset(0)) && !Lens.isAuto(st.inset(2));
			var token:Null<BreakToken> = null, first = true;
			while (true) {
				var breaks = new Breaks(pages[p].area[3], token);
				function lay():Int {
					var cs = spaceFor(cb.w, cb.h);
					cs.fixed = new Positioned();
					cs.fixedWidth = fragments.width(at.fragment);
					if (fixedHeight) cs.fixedHeight = height;
					cs.fragmentation = breaks;
					cs.pageTop = first ? o : 0;
					d.box.uncache();
					return flow.child(d.box, cs);
				}
				var f = lay();
				if (breaks.decide()) f = lay();
				adopt(p, f, x, first ? o : 0);
				for (n in breaks.deferred) queue.push({d: n, page: p});
				token = breaks.token();
				if (token == null || p + 1 >= (options.limit ?? LIMIT)) break;
				p = pageAt(top(p) + pages[p].area[3] + 0.5);
				first = false;
			}
		}
	}

	// (a deferred box's containing block in the flow: its left and top, width and height; the box's static place in it)
	function containing(d:Deferred, page:Int):Null<{x:Float, top:Float, w:Float, h:Float, sx:Float, sy:Float}> {
		if (d.owner == tree.root) return {x: 0, top: 0, w: pages[0].area[2], h: pages[0].area[3], sx: d.x, sy: top(page) + d.y};
		var found:Array<{page:Int, f:Int}> = [];
		for (q in pages) if (q.root >= 0 && !q.blank) {
			var f = fragmentOf(q.root, d.owner);
			if (f >= 0) found.push({page: q.index, f: f});
		}
		if (found.length == 0) return null;
		var here = found[0];
		for (h in found) if (h.page == page) here = h;
		var ah = fragments.absolute(here.f);
		if (found.length == 1) return {x: ah.x + d.cbx, top: top(here.page) + ah.y + d.cby, w: d.cbw, h: d.cbh, sx: d.x, sy: d.y};
		// (broken: its padding boxes stitched, its border where it isn't sliced)
		var s = d.owner.style.model(), a = found[0], z = found[found.length - 1];
		var a0 = fragments.absolute(a.f), az = fragments.absolute(z.f);
		var x = a0.x + s.border[3];
		var y0 = top(a.page) + a0.y + (fragments.start(a.f) == Box.NO_START ? 0 : s.border[0]);
		var y1 = top(z.page) + az.y + fragments.height(z.f) - (fragments.end(z.f) == Box.NO_END ? 0 : s.border[2]);
		return {
			x: x,
			top: y0,
			w: fragments.width(a.f) - s.border[1] - s.border[3],
			h: Math.max(0, y1 - y0),
			sx: ah.x + d.cbx + d.x - x,
			sy: top(page) + ah.y + d.cby + d.y - y0
		};
	}

	function fragmentOf(k:Int, box:Box):Int {
		if (fragments.kind(k) == Fragments.BOX && fragments.box(k) == box) return k;
		var c = fragments.first(k);
		while (c >= 0) {
			var f = fragmentOf(c, box);
			if (f >= 0) return f;
			c = fragments.next(c);
		}
		return -1;
	}

	// (where a page's area starts in the flow: the areas of the pages with content before it one after the other)
	function top(p:Int):Float {
		var t = 0.0;
		for (q in pages) if (q.index < p && !q.blank) t += q.area[3];
		return t;
	}

	// (the page with content a flow offset is on; pages added past the last for it)
	function pageAt(y:Float):Int {
		var t = 0.0, last = -1;
		for (q in pages) if (!q.blank) {
			if (y < t + q.area[3]) return q.index;
			t += q.area[3];
			last = q.index;
		}
		var rtl = tree.root.style.rtl;
		while (pages.length < (options.limit ?? LIMIT)) {
			var i = pages.length, prev = pages[pages.length - 1];
			var page = pageOf(i, (i % 2 == 1) != rtl, false, prev.name);
			page.root = fragments.add(Fragments.BOX, tree.root, page.area[2], 0);
			pages.push(page);
			repeat(i);
			if (y < t + page.area[3]) return i;
			t += page.area[3];
		}
		return pages.length - 1;
	}

	// (the fixed boxes on a page added for absolutely positioned ones: as every page has them)
	function repeat(p:Int) {
		if (fixed == null) return;
		var flow:BlockFlow = cast (options.contexts ?? Contexts.all()).flow;
		for (b in fixed.boxes) {
			var at = fixed.places.get(b) ?? {x: 0.0, y: 0.0};
			var space = spaceFor(fixed.width, fixed.height);
			space.fixed = new Positioned();
			var f = flow.positionedBox(b, space, at.x, at.y, fixed.width, fixed.height);
			adopt(p, f.fragment, f.x, f.y);
		}
	}

	// (a fragment on a page at x, y in its area)
	function adopt(p:Int, f:Int, x:Float, y:Float) {
		var r = pages[p].root;
		fragments.adopt(r, f, x - fragments.x(r), y - fragments.y(r));
	}

	// (the document's fixed boxes, repeated on every page: those not in another, nor running)
	var fixed:Null<Repeated> = null;

	static function fixedOf(b:Box, out:Array<Box>):Array<Box> {
		if (b.flags & Box.RUNNING != 0) return out;
		if (b.parent != null && b.style.position == "fixed") {
			out.push(b);
			return out;
		}
		var c = b.first;
		while (c != null) {
			fixedOf(c, out);
			c = c.next;
		}
		return out;
	}

	// (the page, from 1, an element's first box is on; 0: none)
	function pageWith(el:helder.dom.Element):Int {
		for (page in pages) if (page.root >= 0 && holds(page.root, el)) return page.index + 1;
		return 0;
	}

	function holds(id:Int, el:helder.dom.Element):Bool {
		if (BoxTree.nodeOf(fragments.box(id)) == el) return true;
		var c = fragments.first(id);
		while (c >= 0) {
			if (holds(c, el)) return true;
			c = fragments.next(c);
		}
		return false;
	}

	static function afresh(b:Null<Box>) {
		if (b == null) return;
		b.uncache();
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
			var w = page.style.width, h = page.style.height;
			var space = spaceFor(w, h);
			page.boxes = PageMargins.layout(boxes, w, h, page.margins, space, flow);
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
			var el = BoxTree.nodeOf(b) != null && BoxTree.nodeOf(b).nodeType == helder.dom.Node.ELEMENT_NODE ? (cast BoxTree.nodeOf(b) : helder.dom.Element) : null;
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
		var css = styles.marginBoxStyle(page.index, page.name, page.left, page.blank, name);
		var items = css == null ? null : CssItems.content(css.terms(Content));
		if (items == null) return null;
		var s = new CssBoxStyle(css);
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
			case Counter("page", style): text.add(tree.counters.format(number, style));
			case Counter("pages", style): text.add(tree.counters.format(pages.length, style));
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
		var space = spaceFor(w, h);
		space.fragmentation = breaks;
		space.repeated = fixed ??= new Repeated(fixedOf(root, []), w, h);
		var mt = first ? BlockFlow.auto(root.style.model().margin[0], w) : 0.0;
		space.pageTop = Math.isNaN(mt) ? 0 : mt;
		var f = (root.context ?? Contexts.all().flow).layout(root, space);
		var off = BlockFlow.offset(root, w, h);
		fragments.moveTo(f, root.marginLeft + off.x, root.topPositive + root.topNegative + off.y);
		return f;
	}

	// (a page's style, size, margins and page area: auto margins none, percentages of the page's width and height)
	function pageOf(index:Int, left:Bool, blank:Bool, ?name:String):Page {
		var style = styles.pageStyle(index, name, left, blank);
		var m = new CssBoxStyle(style.style).model();
		var margins = [for (k in 0...4) BlockFlow.auto(m.margin[k], k % 2 == 0 ? style.height : style.width)];
		margins = [for (v in margins) Math.isNaN(v) ? 0.0 : v];
		var inset = [for (k in 0...4) margins[k] + m.border[k] + BlockFlow.res(m.padding[k], k % 2 == 0 ? style.height : style.width)];
		var turned = style.orientation != "upright";
		return {
			index: index,
			name: name,
			width: turned ? style.height : style.width,
			height: turned ? style.width : style.height,
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
		var w = page.style.width, h = page.style.height;
		var turn = rotation(page);
		if (turn != null) {
			p.save();
			p.transform(turn.a, turn.b, turn.c, turn.d, turn.e, turn.f);
		}
		var style = new CssBoxStyle(page.style.style);
		Backgrounds.paint(p, style, 0, 0, w + 2 * b, h + 2 * b, image, null, false, false, false, false, svg);
		Borders.paint(p, style, b + m[3], b + m[0], w - m[1] - m[3], h - m[0] - m[2]);
		if (page.root >= 0) contentOf(i, p, snap);
		marginsOf(page, p, b, snap);
		if (turn != null) p.restore();
	}

	// (page-orientation rotates the bleed box after layout, CSS Paged Media 3 §7.1.2)
	static function rotation(page:Page):Null<Matrix>
		return switch page.style.orientation {
			case "rotate-left": new Matrix(0, -1, 1, 0, 0, page.style.width + 2 * page.bleed);
			case "rotate-right": new Matrix(0, 1, -1, 0, page.style.height + 2 * page.bleed, 0);
			case _: null;
		}

	// (its content in its page area)
	function contentOf(i:Int, p:Painter, snap:Bool) {
		var page = pages[i];
		var b = page.bleed;
		p.save();
		p.translate(b + page.area[0], b + page.area[1]);
		var painter = new BoxPainter(fragments, new PaintOrder(fragments, page.root, [0.0, 0.0, page.area[2], page.area[3]]), image, svg);
		painter.snap = snap;
		painter.shapes = false;
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
			var painter = new BoxPainter(fragments, new PaintOrder(fragments, f), image, svg);
			painter.snap = snap;
			painter.shapes = false;
			painter.propagate = false;
			painter.paint(p);
		}
		p.restore();
	}

	// An HTML document's text laid out on pages and written as a PDF, in one
	// call: `PagedView.toPdf(html, {url: ..., load: ...})`.
	public static function toPdf(html:String, ?options:PagedViewOptions):Bytes
		return new PagedView(Dom.parse(html), options).pdf();

	// The pages as a PDF (real text: its glyphs and their characters).
	public function pdf():Bytes {
		if (pages.length == 0) layout();
		var doc = new PdfDocument();
		// (page labels: the page counter, a range each time it doesn't go on by one)
		var last = -1;
		for (page in pages) {
			if (page.number != last + 1) doc.label(page.index, "decimal", "", page.number);
			last = page.number;
		}
		// (pages in points, PDF's unit, drawn in CSS pixels: 96 of them an inch, 72 points)
		for (i in 0...pages.length) {
			var page = pages[i];
			var p = doc.newPage(Math.round((page.width + 2 * page.bleed) * PT), Math.round((page.height + 2 * page.bleed) * PT));
			p.scale(PT, PT);
			paint(i, p, false);
		}
		outline(doc);
		var w = new PdfWriter();
		// (what is rasterised at the resolution it had in pixels)
		w.fallbackScale /= PT;
		return w.document(doc);
	}

	static inline var PT = 0.75;

	// (the PDF's outline from the bookmarks, its links from <a href> (to a URI, or to an element's id, an
	// anchor there): at their elements' first boxes, in points)
	function outline(doc:PdfDocument) {
		var first = new haxe.ds.ObjectMap<helder.dom.Element, {page:Int, x:Float, y:Float}>();
		var links:Array<{el:helder.dom.Element, page:Int, x:Float, y:Float, w:Float, h:Float}> = [];
		for (page in pages) {
			if (page.root < 0) continue;
			var ox = page.bleed + page.area[0], oy = page.bleed + page.area[1];
			var turn = rotation(page);
			function walk(k:Int) {
				var kind = fragments.kind(k), node = BoxTree.nodeOf(fragments.box(k));
				if ((kind == Fragments.BOX || kind == Fragments.SPAN) && node != null && node.nodeType == helder.dom.Node.ELEMENT_NODE) {
					var el:helder.dom.Element = cast node;
					var at = fragments.absolute(k);
					var x = ox + at.x, y = oy + at.y;
					var px = turn == null ? x : turn.mapX(x, y), py = turn == null ? y : turn.mapY(x, y);
					if (!first.exists(el)) first.set(el, {page: page.index, x: px, y: py});
					if (el.localName == "a" && el.hasAttribute("href")) {
						var w = fragments.width(k), h = fragments.height(k);
						if (turn == null) links.push({el: el, page: page.index, x: x, y: y, w: w, h: h}) else {
							var qx = turn.mapX(x + w, y + h), qy = turn.mapY(x + w, y + h);
							links.push({el: el, page: page.index, x: Math.min(px, qx), y: Math.min(py, qy), w: Math.abs(px - qx), h: Math.abs(py - qy)});
						}
					}
				}
				var c = fragments.first(k);
				while (c >= 0) {
					walk(c);
					c = fragments.next(c);
				}
			}
			walk(page.root);
		}
		for (b in tree.bookmarks) {
			var at = first.get(b.element);
			if (at != null) doc.bookmark(b.bookmark.label, b.bookmark.level, at.page, at.y * PT);
		}
		var targets = new Map<String, Bool>();
		for (l in links) {
			var href = l.el.getAttribute("href");
			if (href.startsWith("#")) {
				var name = StringTools.urlDecode(href.substr(1));
				doc.linkTo(l.page, l.x * PT, l.y * PT, l.w * PT, l.h * PT, name);
				targets.set(name, true);
			} else
				doc.link(l.page, l.x * PT, l.y * PT, l.w * PT, l.h * PT, CssUrl.resolve(options.url, href));
		}
		for (name in targets.keys()) {
			var el = document.getElementById(name);
			var at = el == null ? null : first.get(el);
			if (at != null) doc.anchor(name, at.page, at.x * PT, at.y * PT);
		}
	}

	// (a layout's space on a page: print's, no pixel grid)
	function spaceFor(w:Float, h:Float):Space {
		var s = new Space(fragments, fonts, w, h);
		s.exact = true;
		return s;
	}

	function image(url:String):Null<Bitmap> {
		var abs = CssUrl.resolve(options.url, url);
		if (images.exists(abs)) return images.get(abs);
		// (a data: URL decoded here; a host's loader for the rest)
		var b = BoxImages.data(abs) != null ? BoxImages.raster(abs) : options.image == null ? null : try options.image(abs) catch (_:Dynamic) null;
		images.set(abs, b);
		return b;
	}

	// (an SVG image: a data: URL's, or a .svg file read as text)
	function svg(url:String):Null<helder.canvas.Svg> {
		var abs = CssUrl.resolve(options.url, url);
		if (svgs.exists(abs)) return svgs.get(abs);
		var v = BoxImages.svg(abs, options.load);
		svgs.set(abs, v);
		return v;
	}
}
