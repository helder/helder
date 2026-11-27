package helder.ui.box;

import haxe.io.Bytes;
import helder.canvas.Bitmap;
import helder.canvas.Canvas;
import helder.canvas.Painter;
import helder.css.CssCascade;
import helder.css.CssMedia;
import helder.css.CssStyles;
import helder.css.CssUrl;
import helder.dom.Document;
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
	?background:Int
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
	var viewWidth = 0.0;
	var viewHeight = 0.0;

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

	// Styles and boxes (once, or again at another size: media queries), then layout in a viewport
	// of width by height: the root's fragment.
	public function layout(width:Float, height:Float):Int {
		if (styles == null || width != viewWidth || height != viewHeight) {
			styles = CssCascade.styles(document, {
				media: options.media ?? {type: "screen", width: width, height: height, resolution: 1, color: 8},
				viewport: options.viewport,
				load: options.load,
				url: options.url,
				hints: true
			});
			// (ex, ch, cap, ic and line-height: normal from the first available font, as styles compute)
			styles.metrics = fonts.metrics;
			if (options.font != null) fonts.fontFaces(styles.fontFaces, options.font);
			tree = BoxTree.build(document, styles, {contexts: options.contexts, image: image});
			fragments.clear();
		}
		viewWidth = width;
		viewHeight = height;
		var r = tree.root;
		if (r == null) return root = -1;
		var space = new Space(fragments, fonts, width, height);
		var f = (r.context ?? Contexts.all().flow).layout(r, space);
		var off = helder.ui.flow.BlockFlow.offset(r, width, height);
		fragments.moveTo(f, r.marginLeft + off.x, r.topPositive + r.topNegative + off.y);
		// (sticky boxes against their scrollport at a scroll of 0; printed pages have none: they stay)
		if (options.media == null || options.media.type != "print") helder.ui.flow.Sticky.apply(fragments, f, width, height);
		order = new PaintOrder(fragments, f);
		return root = f;
	}

	public function paint(p:Painter) {
		p.clear(options.background ?? 0xFFFFFFFF);
		if (order == null) return;
		new BoxPainter(fragments, order, image).paint(p);
	}

	// What is at (x, y): a text node and the offset there, or an element (offset -1).
	public function hit(x:Float, y:Float):Null<{node:Node, offset:Int}>
		return order == null ? null : HitTest.at(fragments, order, x, y);

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
		var out = [];
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
		if (options.image == null) return null;
		var abs = CssUrl.resolve(options.url, url);
		if (images.exists(abs)) return images.get(abs);
		var b = try options.image(abs) catch (_:Dynamic) null;
		images.set(abs, b);
		return b;
	}
}
