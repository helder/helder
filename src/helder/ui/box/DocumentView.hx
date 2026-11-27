package helder.ui.box;

import haxe.io.Bytes;
import helder.canvas.Bitmap;
import helder.canvas.Canvas;
import helder.canvas.Painter;
import haxe.ds.ObjectMap;
import helder.css.CssCascade;
import helder.css.CssMedia;
import helder.css.CssStyles;
import helder.css.CssUrl;
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

// A helder.dom document styled, laid out and painted: the cascade
// (helder.css, HTML's presentational hints on, as browsers have them),
// the box tree, flow layout into fragments, paint in CSS 2.1 Appendix E's
// order, hit testing.
//
//   var view = DocumentView.render(doc, 800, canvas);   // canvas: a Painter, 800 wide
//   view.hit(10, 20);                                    // {node, offset}
//   view.selection({node: a, offset: 0}, {node: b, offset: 3});   // its rectangles
//   File.saveBytes("page.png", DocumentView.png(doc, 800, 600));
class DocumentView {
	public final document:Document;
	public final fragments = new Fragments();
	public final fonts:FontMatch;
	public var styles(default, null):Null<CssStyles> = null;
	public var tree(default, null):Null<BoxTree> = null;
	public var root(default, null) = -1;
	public var order(default, null):Null<PaintOrder> = null;

	final options:DocumentViewOptions;
	final images = new Map<String, Null<Bitmap>>();
	final svgs = new Map<String, Null<helder.canvas.Svg>>();
	var viewWidth = 0.0;
	var viewHeight = 0.0;
	// (each node's boxes, made as asked for; the boxes with lines; each box's
	// fragment in this layout; the fragments a whole layout made)
	var owners:Null<ObjectMap<Node, Array<Box>>> = null;
	var lined:Null<Array<Box>> = null;
	var placed:Null<ObjectMap<Box, Int>> = null;
	var whole = 0;

	public function new(document:Document, ?options:DocumentViewOptions) {
		this.document = document;
		this.options = options ?? {};
		fonts = this.options.fonts ?? new FontMatch();
	}

	public static function render(doc:Document, width:Int, painter:Painter, ?options:DocumentViewOptions):DocumentView {
		var v = new DocumentView(doc, options);
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
			styles = CssCascade.styles(document, {
				media: media,
				viewport: options.viewport,
				load: options.load,
				url: options.url,
				userAgent: options.userAgent,
				author: options.author,
				hints: true
			});
			// (ex, ch, cap, ic and line-height: normal from the first available font, as styles compute)
			styles.metrics = fonts.metrics;
			if (options.font != null) fonts.fontFaces(styles.fontFaces, options.font);
			fonts.fontPalettes(styles.fontPaletteValues);
			build();
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
		if (options.media == null || options.media.type != "print") helder.ui.flow.Sticky.apply(fragments, f, viewWidth, viewHeight);
		order = new PaintOrder(fragments, f);
		if (fresh) whole = fragments.count;
		return root = f;
	}

	// (every box's layout cache let go)
	static function forget(b:Box) {
		var stack = [b];
		while (stack.length > 0) {
			var x = stack.pop();
			x.cacheFragment = -1;
			x.cacheWidth = x.cacheHeight = x.minContent = x.maxContent = Math.NaN;
			var c = x.first;
			while (c != null) {
				stack.push(c);
				c = c.next;
			}
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
