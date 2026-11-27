package helder.ui.box;

import haxe.io.Bytes;
import helder.canvas.Bitmap;
import helder.canvas.Canvas;
import helder.canvas.Painter;
import haxe.ds.ObjectMap;
import helder.css.CssCascade;
import helder.css.CssMedia;
import helder.css.CssProperty;
import helder.css.CssStyle;
import helder.css.CssStyles;
import helder.css.CssUrl;
import helder.dom.CharacterData;
import helder.dom.Document;
import helder.dom.Element;
import helder.dom.Node;
import helder.ui.flow.Contexts;
import helder.ui.flow.Space;

typedef DocumentViewOptions = {
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
	// what @media matches (default: a screen of the view's size)
	?media:CssMediaContext,
	// what vw and vh resolve against (default: the cascade's: on print, the
	// first page's area; else media's size); a paged host gives the page area
	?viewport:{width:Float, height:Float},
	// the canvas under the root's background (default white)
	?background:Int,
	// the user agent's sheet (default: HTML's; an app's, helder.css's ua/app.css)
	?userAgent:helder.css.CssSheet,
	// author sheets after the document's own
	?author:Array<helder.css.CssSheet>
}

// How a view's document is styled at a viewport: DocumentView.html (HTML's
// cascade: the user agent's sheet, <style>, <link>, style attributes,
// presentational hints, all parsed when the program runs) or an app's
// (CssCascade.themed with sheets compiled at build time: no parser linked).
typedef DocumentCascade = (document:Document, media:CssMediaContext, options:DocumentViewOptions) -> CssStyles;

// A helder.dom document styled, laid out and painted: the cascade (the
// caller's, so that a program links only the one it uses), the box tree,
// flow layout into fragments, paint in CSS 2.1 Appendix E's order, hit
// testing.
//
//   var view = DocumentView.render(doc, 800, canvas);   // HTML's cascade; canvas: a Painter, 800 wide
//   var app = new DocumentView(doc, (d, media, _) -> CssCascade.themed(d, [CssUserAgentTheme.app(), CssTheme.file("app.css")], {media: media}));
//   view.hit(10, 20);                                    // {node, offset}
//   view.selection({node: a, offset: 0}, {node: b, offset: 3});   // its rectangles
//   File.saveBytes("page.png", DocumentView.png(doc, 800, 600));
//
// Live (watch): the document's changes followed (DocumentChanges: helder.css's
// CssRestyle and what changed in its tree), and update() redoing only what
// they need, by the impact of each restyled element's properties
// (CssProperties.impact): its boxes' styles swapped and painted again, the
// paint order made again (opacity, transforms), the boxes' layout redone
// where it changed (their caches and their ancestors' let go, the rest
// reused), or the box tree made again.
class DocumentView {
	// what update redid, the most of it
	public static inline var NOTHING = 0;
	public static inline var PAINT = 1;
	public static inline var ORDER = 2;
	public static inline var LAYOUT = 3;
	public static inline var TREE = 4;

	public final document:Document;
	public final fragments = new Fragments();
	public final fonts:FontMatch;
	public var styles(default, null):Null<CssStyles> = null;
	public var tree(default, null):Null<BoxTree> = null;
	public var root(default, null) = -1;
	public var order(default, null):Null<PaintOrder> = null;

	final options:DocumentViewOptions;
	final cascade:DocumentCascade;
	final images = new Map<String, Null<Bitmap>>();
	final svgs = new Map<String, Null<helder.canvas.Svg>>();
	var viewWidth = 0.0;
	var viewHeight = 0.0;
	// (the document's changes followed, watch; each node's boxes, made as asked
	// for; the boxes with lines; the fragments a whole layout made)
	var changes:Null<DocumentChanges> = null;
	var owners:Null<ObjectMap<Node, Array<Box>>> = null;
	var lined:Null<Array<Box>> = null;
	var placed:Null<ObjectMap<Box, Int>> = null;
	var whole = 0;
	var sticky = false;

	public function new(document:Document, cascade:DocumentCascade, ?options:DocumentViewOptions) {
		this.document = document;
		this.cascade = cascade;
		this.options = options ?? {};
		fonts = this.options.fonts ?? new FontMatch();
	}

	// A document styled as HTML is: DocumentCascade's HTML cascade.
	public static function html(doc:Document, ?options:DocumentViewOptions):DocumentView
		return new DocumentView(doc, htmlCascade, options);

	public static function htmlCascade(document:Document, media:CssMediaContext, options:DocumentViewOptions):CssStyles
		return CssCascade.styles(document, {
			media: media,
			viewport: options.viewport,
			load: options.load,
			url: options.url,
			userAgent: options.userAgent,
			author: options.author,
			hints: true
		});

	public static function render(doc:Document, width:Int, painter:Painter, ?options:DocumentViewOptions):DocumentView {
		var v = html(doc, options);
		v.layout(width, painter.height);
		v.paint(painter);
		return v;
	}

	// The document drawn on the CPU at width by height, as a PNG.
	public static function png(doc:Document, width:Int, height:Int, ?options:DocumentViewOptions):Bytes {
		var c = new Canvas(width, height);
		render(doc, width, c, options);
		return c.toPng();
	}

	// Styles and boxes (once, or again at another size where a media query
	// or a viewport unit reads it), then layout in a viewport of width by
	// height, the boxes' layout cache reused: the root's fragment.
	public function layout(width:Float, height:Float):Int {
		var media = options.media ?? {type: "screen", width: width, height: height, resolution: 1, color: 8};
		if (styles == null || (width != viewWidth || height != viewHeight) && !styles.holds(media)) {
			styles = cascade(document, media, options);
			// (ex, ch, cap, ic and line-height: normal from the first available font, as styles compute)
			styles.metrics = fonts.metrics;
			if (options.font != null) fonts.fontFaces(styles.fontFaces, options.font);
			fonts.fontPalettes(styles.fontPaletteValues);
			build();
			if (changes != null) {
				changes.detach();
				changes = new DocumentChanges(document, styles);
			}
		}
		viewWidth = width;
		viewHeight = height;
		return lay();
	}

	// (the box tree made from the styles, nothing of the last one's layout kept)
	function build() {
		tree = BoxTree.build(document, styles, {contexts: options.contexts, image: image, svg: svg});
		fragments.clear();
		owners = null;
		// (whether any box sticks: Sticky.apply walks every fragment)
		sticky = false;
		if (tree.root != null) {
			var stack = [tree.root];
			while (stack.length > 0 && !sticky) {
				var b = stack.pop();
				if (b.kind != Text && b.style.position == "sticky") sticky = true;
				var c = b.first;
				while (c != null) {
					stack.push(c);
					c = c.next;
				}
			}
		}
	}

	// (laid out at the view's size from the cache; the fragments of the layouts
	// before it, kept for the cache, dropped once they are a few times a whole
	// layout's, and everything laid out afresh)
	function lay():Int {
		lined = null;
		placed = null;
		var r = tree.root;
		if (r == null) return root = -1;
		if (fragments.count > 3 * whole + 4096) {
			fragments.clear();
			forget(r);
		}
		var fresh = fragments.count == 0;
		var space = new Space(fragments, fonts, viewWidth, viewHeight);
		var f = (r.context ?? Contexts.all().flow).layout(r, space);
		var off = helder.ui.flow.BlockFlow.offset(r, viewWidth, viewHeight);
		fragments.moveTo(f, r.marginLeft + off.x, r.topPositive + r.topNegative + off.y);
		// (sticky boxes against their scrollport at a scroll of 0; printed pages have none: they stay)
		if (sticky && (options.media == null || options.media.type != "print")) helder.ui.flow.Sticky.apply(fragments, f, viewWidth, viewHeight);
		order = new PaintOrder(fragments, f);
		if (fresh) whole = fragments.count;
		return root = f;
	}

	// (every box's layout cache let go)
	static function forget(b:Box) {
		var stack = [b];
		while (stack.length > 0) {
			var x = stack.pop();
			x.uncache();
			x.cacheWidth = x.cacheHeight = x.minContent = x.maxContent = Math.NaN;
			var c = x.first;
			while (c != null) {
				stack.push(c);
				c = c.next;
			}
		}
	}

	// Follows the document's changes from now on (its observer): update()
	// redoes what they need. After the first layout (its styles' selectors).
	public function watch() {
		if (changes == null && styles != null) changes = new DocumentChanges(document, styles);
	}

	// The document's changes since the last update, made good: the elements
	// they may restyle styled again, and by what changed in them, their boxes'
	// styles swapped (PAINT), the paint order made again (ORDER), the boxes
	// laid out again where they changed (LAYOUT), or the box tree made again
	// (TREE: children inserted or removed, a display, float, position or
	// generated content changed). What it redid, the most of it.
	public function update():Int {
		var c = changes;
		if (c == null || styles == null || tree == null || !c.dirty()) return NOTHING;
		var redo = c.structure ? TREE : NOTHING;
		var marked = c.restyle.changed();
		var olds = new ObjectMap<Element, CssStyle>(), queued = new ObjectMap<Element, Bool>();
		for (el in marked) {
			var o = styles.cached(el);
			if (o != null) olds.set(el, o);
			queued.set(el, true);
		}
		styles.forget(marked);
		var swaps = new ObjectMap<BoxStyle, BoxStyle>();
		var k = 0;
		while (k < marked.length && redo < TREE) {
			var el = marked[k++], old = olds.get(el);
			// (an element never styled is under display: none, or new: an insertion's tree)
			if (old == null) continue;
			var now = styles.computed(el);
			if (now == old) continue;
			// (what its children inherit, or their blockification, changed: they are styled again too)
			if (old.passesDown(now)) {
				var ch = el.firstElementChild;
				while (ch != null) {
					var o = styles.cached(ch);
					if (o != null && !queued.exists(ch)) {
						olds.set(ch, o);
						queued.set(ch, true);
						styles.forget([ch]);
						marked.push(ch);
					}
					ch = ch.nextElementSibling;
				}
			}
			var impact:Int = cast old.impact(now);
			if (impact == (cast helder.css.CssProperties.CssImpact.None : Int)) continue;
			if (impact <= (cast helder.css.CssProperties.CssImpact.Text : Int) && structural(old, now)) {
				redo = TREE;
				break;
			}
			var level = impact <= (cast helder.css.CssProperties.CssImpact.Text : Int) ? LAYOUT : impact == (cast helder.css.CssProperties.CssImpact.Composite : Int) ? ORDER : PAINT;
			if (level == PAINT && reaches(old, now)) level = ORDER;
			var boxes = boxesOf(el);
			for (b in boxes) if (b.pseudo == null) swap(b, el, old, now, swaps, level == LAYOUT);
			// (its pseudo-elements' boxes: their styles made again, swapped the same way, or the tree made again)
			for (b in boxes) if (b.pseudo != null && redo < TREE) {
				var was = b.style.css, next = styles.computed(el, b.pseudo);
				if (next == was) continue;
				var i:Int = cast was.impact(next);
				if (i <= (cast helder.css.CssProperties.CssImpact.Text : Int) && structural(was, next)) redo = TREE else swap(b, el, was, next, swaps, i <= (cast helder.css.CssProperties.CssImpact.Text : Int));
			}
			if (level > redo) redo = level;
		}
		// (a text changed in place: its run's text, its blocks laid out again)
		if (redo < TREE) for (t in c.texts) {
			var boxes = boxesOf(t);
			if (boxes.length != 1 || boxes[0].offset != 0 || t.data.length == 0) {
				redo = TREE;
				break;
			}
			boxes[0].text = t.data;
			stale(boxes[0]);
			redo = LAYOUT;
		}
		c.clear();
		switch redo {
			case TREE:
				// (the elements under one whose display changed: blockified again)
				build();
				lay();
			case LAYOUT:
				lay();
			case ORDER:
				order = new PaintOrder(fragments, root);
			case _:
		}
		return redo;
	}

	// (a change of these remakes boxes: their kind, generated content, counters)
	static final STRUCTURAL:Array<CssProperty> = [Display, CssProperty.Float, Position, Content, ListStyleType, ListStyleImage, ListStylePosition, CounterReset,
		CounterIncrement, CounterSet, Quotes, StringSet];

	static function structural(a:CssStyle, b:CssStyle):Bool {
		for (p in STRUCTURAL) if (a.terms(p) != b.terms(p) && helder.css.CssIntern.key(a.terms(p)) != helder.css.CssIntern.key(b.terms(p))) return true;
		return a.display != b.display;
	}

	// (how far it paints past its box changed: an outline, a shadow; the paint order's bounds made again)
	static final REACH:Array<CssProperty> = [OutlineStyle, OutlineWidth, OutlineOffset, BoxShadow];

	static function reaches(a:CssStyle, b:CssStyle):Bool {
		for (p in REACH) if (a.terms(p) != b.terms(p) && helder.css.CssIntern.key(a.terms(p)) != helder.css.CssIntern.key(b.terms(p))) return true;
		return false;
	}

	// (an element's boxes and what they hold of it, its text runs and anonymous
	// boxes, given its new style; laid out again: their caches and their
	// ancestors' let go)
	function swap(b:Box, el:Element, old:CssStyle, now:CssStyle, swaps:ObjectMap<BoxStyle, BoxStyle>, relayout:Bool) {
		if (b.style.css == old) {
			var s = swaps.get(b.style);
			if (s == null) swaps.set(b.style, s = b.style.restyled(now));
			b.restyle(s);
			// (the lines it is in keep its old inline style: built again)
			var p:Null<Box> = b;
			while (p != null) {
				p.inlineCache = null;
				p = p.parent;
			}
			if (relayout) stale(b);
		}
		var c = b.first;
		while (c != null) {
			if (c.pseudo == null && (c.node == null || c.node == el || c.node.nodeType != Node.ELEMENT_NODE)) swap(c, el, old, now, swaps, relayout);
			c = c.next;
		}
	}

	// (a box and its ancestors laid out again)
	static function stale(b:Null<Box>) {
		while (b != null) {
			b.uncache();
			b.inlineCache = null;
			b.cacheWidth = b.minContent = b.maxContent = Math.NaN;
			b = b.parent;
		}
	}

	// A box's fragment in this layout (its first, in the fragments' tree
	// order: a box broken across lines has several); -1: none. (Fragments of
	// layouts before, kept for the cache, are not this one's.)
	public function fragmentOf(b:Box):Int {
		if (placed == null) {
			var m = new ObjectMap<Box, Int>();
			if (root >= 0) {
				// (in tree order: a fragment, then its children, then its next sibling)
				var stack = [root];
				while (stack.length > 0) {
					var id = stack.pop();
					var box = fragments.box(id);
					if (box != null && !m.exists(box)) m.set(box, id);
					if (id != root && fragments.next(id) >= 0) stack.push(fragments.next(id));
					if (fragments.first(id) >= 0) stack.push(fragments.first(id));
				}
			}
			placed = m;
		}
		return placed.get(b) ?? -1;
	}

	// A node's boxes: an element's (its parts, its pseudo-elements'), a text's runs.
	public function boxesOf(n:Node):Array<Box> {
		if (owners == null) {
			var m = new ObjectMap<Node, Array<Box>>();
			if (tree != null && tree.root != null) {
				var stack = [tree.root];
				while (stack.length > 0) {
					var b = stack.pop();
					if (b.node != null) {
						var list = m.get(b.node);
						if (list == null) m.set(b.node, list = []);
						list.push(b);
					}
					var c = b.first;
					while (c != null) {
						stack.push(c);
						c = c.next;
					}
				}
			}
			owners = m;
		}
		return owners.get(n) ?? [];
	}

	// Paints on p: all of it, or (area: x0, y0, x1, y1) what is seen of it
	// alone, as a window's view of a long document (the canvas's background
	// over that area, under everything).
	public function paint(p:Painter, ?area:Array<Float>) {
		p.clear(options.background ?? 0xFFFFFFFF);
		if (order == null) return;
		var bp = new BoxPainter(fragments, order, image, svg);
		bp.scrolls = scrolls;
		if (area != null) {
			bp.area = area;
			bp.canvasArea = [area[0], area[1], area[2] - area[0], area[3] - area[1]];
		}
		bp.paint(p);
	}

	// What is at (x, y): a text node and the offset there, or an element (offset -1).
	public function hit(x:Float, y:Float):Null<{node:Node, offset:Int}>
		return order == null ? null : HitTest.at(fragments, order, x, y, scrolls);

	// Scroll containers' offsets (x, y) by their element: what paint and hit testing move their content by.
	public final scrolls = new ObjectMap<Node, Array<Float>>();

	// The innermost scroll container at (x, y) that can scroll by dx, dy
	// scrolled (within its content's extent): the element; null: none can.
	public function scrollBy(x:Float, y:Float, dx:Float, dy:Float):Null<Element> {
		var h = hit(x, y);
		var n = h == null ? null : h.node;
		while (n != null) {
			if (n.nodeType == Node.ELEMENT_NODE) for (b in boxesOf(n)) if (b.pseudo == null && b.style.scrolls && b.parent != null && b.parent.parent != null) {
				var id = fragmentOf(b);
				if (id < 0) continue;
				var m = b.style.model();
				var cw = fragments.width(id) - m.border[1] - m.border[3], ch = fragments.height(id) - m.border[0] - m.border[2];
				// (its content's extent: its children's margin boxes' far edges, and its padding's at the end)
				var ew = 0.0, eh = 0.0, c = fragments.first(id);
				while (c >= 0) {
					ew = Math.max(ew, fragments.x(c) + fragments.width(c));
					eh = Math.max(eh, fragments.y(c) + fragments.height(c));
					c = fragments.next(c);
				}
				eh += helder.ui.box.Len.Lens.resolve(m.padding[2], cw, 0) - m.border[0];
				ew -= m.border[3];
				var o = scrolls.get(n) ?? [0.0, 0.0];
				var sx = Math.max(0, Math.min(o[0] + dx, ew - cw)), sy = Math.max(0, Math.min(o[1] + dy, eh - ch));
				if (sx == o[0] && sy == o[1]) continue;
				scrolls.set(n, [sx, sy]);
				return cast n;
			}
			n = n.parentNode;
		}
		return null;
	}

	// The text position nearest (x, y), as a selection's end follows the
	// pointer: from the lines of the innermost block whose fragment holds
	// the point, else of the block nearest it above or below; null: no text.
	// Transforms aside.
	public function position(x:Float, y:Float):Null<{node:Node, offset:Int}> {
		var best:Null<Box> = null, bestOrigin = null, far = Math.POSITIVE_INFINITY;
		for (b in texts()) {
			var id = b.lines.fragment, o = fragments.absolute(id);
			var dy = y < o.y ? o.y - y : y > o.y + fragments.height(id) ? y - o.y - fragments.height(id) : 0.0;
			var dx = x < o.x ? o.x - x : x > o.x + fragments.width(id) ? x - o.x - fragments.width(id) : 0.0;
			// (inside: the innermost, the last in the tree's order; else the nearest, down then across)
			var d = dy * 1e4 + dx;
			if (d <= far) {
				far = d;
				best = b;
				bestOrigin = o;
			}
		}
		return best == null ? null : best.lines.hit(x - bestOrigin.x, y - bestOrigin.y);
	}

	// The caret at a DOM position (a text node and an offset in it) in the
	// document, its line's height; null: not in any lines. Transforms aside.
	public function caret(node:Node, offset:Int):Null<{x:Float, y:Float, height:Float}> {
		for (b in texts()) {
			var u = b.lines.unitOf(node, offset);
			if (u < 0) continue;
			var c = b.lines.caret(u), o = fragments.absolute(b.lines.fragment);
			return {x: o.x + c.x, y: o.y + c.y, height: c.height};
		}
		return null;
	}

	// The rectangles a selection from one DOM position to another covers in
	// the document: each line's selected runs, the line's height, block by
	// block in the box tree's order. Transforms aside.
	public function selection(from:{node:Node, offset:Int}, to:{node:Node, offset:Int}):Array<{x:Float, y:Float, width:Float, height:Float}> {
		var blocks = texts();
		var b0 = -1, u0 = -1, b1 = -1, u1 = -1;
		for (k in 0...blocks.length) {
			if (b0 < 0 && (u0 = blocks[k].lines.unitOf(from.node, from.offset)) >= 0) b0 = k;
			if (b1 < 0 && (u1 = blocks[k].lines.unitOf(to.node, to.offset)) >= 0) b1 = k;
		}
		if (b0 < 0 || b1 < 0) return [];
		if (b1 < b0 || b1 == b0 && u1 < u0) {
			var t = b0, v = u0;
			b0 = b1;
			u0 = u1;
			b1 = t;
			u1 = v;
		}
		var out = [];
		for (k in b0...b1 + 1) {
			var l = blocks[k].lines, o = fragments.absolute(l.fragment);
			for (r in l.selection(k == b0 ? u0 : 0, k == b1 ? u1 : l.content.text.length))
				out.push({x: o.x + r.x, y: o.y + r.y, width: r.width, height: r.height});
		}
		return out;
	}

	// (the boxes with lines in this layout, in the tree's order)
	function texts():Array<Box> {
		if (lined != null) return lined;
		var out = lined = [];
		if (tree == null || tree.root == null || root < 0) return out;
		var stack = [tree.root];
		while (stack.length > 0) {
			var b = stack.pop();
			if (b.lines != null && b.lines.fragment < fragments.count && fragments.box(b.lines.fragment) == b) out.push(b);
			var at = stack.length, c = b.first;
			while (c != null) {
				stack.insert(at, c);
				c = c.next;
			}
		}
		return out;
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
