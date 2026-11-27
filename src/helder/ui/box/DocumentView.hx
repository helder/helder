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
import helder.ui.flow.Lazy;
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
// a block and where its top was: what a layout keeps in place (DocumentView.anchor)
typedef DocumentAnchor = {box:Box, y:Float};

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
	// (the glyph runs a window's paints placed: kept while the fragments are)
	final placedRuns = new BoxPainter.PlacedRuns();
	var sticky = false;
	// (a long document's window, what within gave, and its lazy layout's skipped blocks)
	var window:Null<Array<Float>> = null;
	var lazy:Null<Lazy> = null;
	final sizes = new ObjectMap<Box, {chars:Float, blocks:Int}>();
	// (the elements a resize restyles in blocks a lazy layout skipped, by block: styled again when it is laid out)
	final pending = new ObjectMap<Box, Array<Element>>();
	// (a document of this many boxes is laid out lazily where within gives a window)
	public static inline var LONG = 50000;

	public function new(document:Document, cascade:DocumentCascade, ?options:DocumentViewOptions) {
		this.document = document;
		this.cascade = cascade;
		this.options = options ?? {};
		if (this.options.contexts == null) throw "DocumentView: no formatting contexts (DocumentView.html's: every one; an app's: DocumentApp)";
		fonts = this.options.fonts ?? new FontMatch();
	}

	// A document styled as HTML is: DocumentCascade's HTML cascade, every formatting context.
	public static function html(doc:Document, ?options:DocumentViewOptions):DocumentView
		return new DocumentView(doc, htmlCascade, every(options));

	// (the options with every formatting context, unless they name theirs)
	public static function every(options:Null<DocumentViewOptions>):DocumentViewOptions {
		var o:DocumentViewOptions = options ?? {};
		if (o.contexts == null) o.contexts = Contexts.all();
		return o;
	}

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
		// (at another size where only viewport units read it: the elements they styled, styled again, the
		// boxes and their kept content stay)
		var resized = styles != null && (width != viewWidth || height != viewHeight) && !styles.holds(media);
		// (what a block a lazy layout skipped holds not matched now: the block styled again whole when laid out)
		var blocks = new ObjectMap<Element, Box>();
		if (resized && lazy != null) for (b in lazy.boxes) if (b.node != null && b.node.nodeType == Node.ELEMENT_NODE) blocks.set(cast b.node, b);
		var restyled = resized ? styles.resize(media, el -> {
			var b = blocks.get(el);
			if (b != null) unstyled.set(b, true);
			b != null;
		}) : null;
		if (styles == null || resized && restyled == null) {
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
		if (restyled != null) {
			var now = defer(restyled), redo = restyle(now, NOTHING);
			skipped = null;
			if (redo == TREE) {
				restyle(waiting(), NOTHING);
				build();
			}
			// (the rules in effect may be others now: the tracker's selectors made again)
			if (changes != null) {
				changes.detach();
				changes = new DocumentChanges(document, styles);
			}
		}
		return lay();
	}

	// (the box tree made from the styles, nothing of the last one's layout kept)
	function build() {
		// (the elements kept to style again: styled as the tree is made)
		var w = waiting();
		if (w.length > 0) styles.forget(w);
		tree = BoxTree.build(document, styles, {contexts: options.contexts, image: image, svg: svg});
		fonts.inlines.forget();
		fragments.clear();
		placedRuns.clear();
		owners = null;
		sizes.clear();
		sticky = false;
		if (tree.root != null) marks(tree.root);
	}

	// (whether any box sticks: Sticky.apply walks every fragment; the blocks with nothing reaching outside
	// them, floats or positioned boxes: what a lazy layout may skip, Box.LAZY; in top, and around it)
	function marks(top:Box) {
		var order = [], stack = [top];
		while (stack.length > 0) {
			var b = stack.pop();
			order.push(b);
			if (b.kind != Text && b.style.position == "sticky") sticky = true;
			var c = b.first;
			while (c != null) {
				stack.push(c);
				c = c.next;
			}
		}
		// (children before their parents, the reverse of a parent first order; then the boxes around it)
		var k = order.length;
		while (k-- > 0) mark(order[k]);
		var a = top.parent;
		while (a != null) {
			mark(a);
			a = a.parent;
		}
	}

	// (what in a box reaches outside it, from its children's: an absolutely positioned box whose containing
	// block is above it, a float whose formatting context is, a box that sticks or is fixed)
	static function mark(b:Box) {
		var open = 0;
		if (b.kind != Text && b.kind != Break) {
			if (b.floating) open |= FLOATS;
			var p = b.style.position;
			if (p == "fixed" || p == "sticky") open |= FIXED else if (b.absolute) open |= POSITIONED;
		}
		var holds = b.kind != Text && b.kind != Break && (b.style.positioned || b.style.containment.containingBlock);
		var root = b.kind != Text && b.kind != Break && helder.ui.flow.BlockFlow.formattingRoot(b);
		var c = b.first;
		while (c != null) {
			if (c.flags & POSITIONED != 0 && !holds) open |= POSITIONED;
			if (c.flags & FLOATS != 0 && !root) open |= FLOATS;
			open |= c.flags & FIXED;
			c = c.next;
		}
		b.flags &= ~(Box.LAZY | POSITIONED | FLOATS | FIXED);
		b.flags |= open;
		// (an absolutely positioned box in it not laid out either while it's skipped: content-visibility: auto's
		// containment)
		if ((b.kind == Block || b.kind == TableWrapper && b.blockLevel && !b.floating && !b.absolute) && b.parent != null && b.first != null
			&& open & (FLOATS | FIXED) == 0) b.flags |= Box.LAZY;
	}

	// (mark's, kept on the boxes: in it, a positioned box whose containing block is above it; a float whose
	// formatting context is)
	static inline var POSITIONED = 1 << 30;
	static inline var FLOATS = 1 << 29;
	// (and one fixed or sticky: what a scroll moves)
	static inline var FIXED = 1 << 28;

	// Lays out, where the document is long (LONG boxes), only what a window
	// of it shows (top...bottom, a scroll's, in its coordinates) and what
	// was laid out before: its other blocks skipped, their heights
	// estimated, until reveal lays them out. The layouts from the next on.
	public function within(top:Float, bottom:Float)
		window = [top, bottom];

	// Whether the last layout skipped a block in top...bottom: what a frame
	// showing it would show without its contents.
	public function unlaid(top:Float, bottom:Float):Bool
		return lazy != null && lazy.skipped(top, bottom);

	// whether the last layout skipped some of it
	public var partial(get, never):Bool;

	inline function get_partial():Bool
		return lazy != null && lazy.count > 0;

	// What a window shows that the last layout skipped, laid out (within's
	// window moved there): how far what was at anchor (a scroll's top) moved
	// in it, for the scroll to follow; null: nothing skipped there.
	public function reveal(top:Float, bottom:Float, anchor:Float):Null<Float> {
		window = [top, bottom];
		if (lazy == null || tree == null || !lazy.skipped(top, bottom)) return null;
		var a = this.anchor(anchor);
		lay();
		return a == null ? 0 : moved(a);
	}

	// What is at y, to keep in place across a layout (scroll anchoring): the
	// deepest block there, and its top.
	public function anchor(y:Float):Null<DocumentAnchor> {
		if (root < 0) return null;
		var f = root, x0 = 0.0, y0 = 0.0, out:Null<DocumentAnchor> = null;
		while (true) {
			var top = y0 + fragments.y(f);
			out = {box: fragments.box(f), y: top};
			var c = fragments.first(f), next = -1;
			while (c >= 0) {
				var cy = top + fragments.y(c);
				if (fragments.kind(c) == Fragments.BOX && cy <= y && cy + fragments.height(c) > y) {
					next = c;
					break;
				}
				c = fragments.next(c);
			}
			if (next < 0) return out;
			y0 = top;
			f = next;
		}
	}

	// How far an anchor's block moved since anchor gave it (0: it isn't laid out now).
	public function moved(a:DocumentAnchor):Float {
		// (down from the root through its ancestors' fragments: a frame's anchor without every fragment mapped)
		var path = [], b = a.box;
		while (b != null) {
			path.push(b);
			b = b.parent;
		}
		var f = root;
		if (f < 0 || fragments.box(f) != path[path.length - 1]) return 0;
		var y = fragments.y(f), k = path.length - 1;
		while (--k >= 0) {
			var c = fragments.first(f);
			while (c >= 0 && !(fragments.kind(c) == Fragments.BOX && fragments.box(c) == path[k])) c = fragments.next(c);
			if (c < 0) return 0;
			f = c;
			y += fragments.y(f);
		}
		return y - a.y;
	}

	// A box laid out where a lazy layout skipped it (a link's target): the
	// window moved to the blocks skipped around it, laid out, until it is.
	public function show(b:Box) {
		for (_ in 0...16) {
			if (fragmentOf(b) >= 0 || window == null) return;
			var a = b.parent;
			while (a != null && fragmentOf(a) < 0) a = a.parent;
			if (a == null) return;
			var y = fragments.absolute(fragmentOf(a)).y;
			window = [y - viewHeight, y + 2 * viewHeight];
			lay();
		}
	}

	// (a block's content height at a content width, its contents unlaid: its last layout's, the text reflowed
	// to the width; else its text's lines and its blocks, by its font size)
	function estimate(b:Box, width:Float):Float {
		if (b.laidWidth > 0 && width > 0) return b.laidHeight * Math.min(2, Math.max(0.5, b.laidWidth / width));
		var t = sizes.get(b);
		if (t == null) {
			var n = 0.0, blocks = 0, stack = [b];
			while (stack.length > 0) {
				var x = stack.pop();
				if (x.kind == Text) n += x.text.length else if (x.blockLevel) blocks++;
				var c = x.first;
				while (c != null) {
					stack.push(c);
					c = c.next;
				}
			}
			sizes.set(b, t = {chars: n, blocks: blocks});
		}
		var size = b.style.css.fontSize();
		return (Math.ceil(t.chars * size * 0.5 / Math.max(width, 1)) + t.blocks) * size * 1.3;
	}

	// (of the elements to style again, those in a block the last layout skipped, kept for when it is laid out:
	// the others)
	function defer(els:Array<Element>):Array<Element> {
		if (lazy == null || lazy.count == 0) return els;
		skipped = new ObjectMap<Box, Bool>();
		for (b in lazy.boxes) skipped.set(b, true);
		return [for (el in els) if (!kept(el)) el];
	}

	// (the blocks the last layout skipped, while a resize's restyle keeps what is in them for later)
	var skipped:Null<ObjectMap<Box, Bool>> = null;

	// (an element in a block skipped, kept to style again when it is laid out)
	function kept(el:Element):Bool {
		if (skipped == null) return false;
		var bs = boxesOf(el), b = bs.length > 0 ? bs[0] : null;
		while (b != null && !skipped.exists(b)) b = b.parent;
		if (b == null) return false;
		var list = pending.get(b);
		if (list == null) pending.set(b, list = []);
		list.push(el);
		return true;
	}

	// (every element kept to style again, let go of)
	function waiting():Array<Element> {
		var out = [];
		for (list in pending) for (el in list) out.push(el);
		pending.clear();
		for (b in unstyled.keys()) elementsOf(b, out);
		unstyled.clear();
		return out;
	}

	// (the elements of a block kept to style again whole, in tree order)
	static function elementsOf(b:Box, out:Array<Element>) {
		var el:Element = cast b.node, stack:Array<Node> = [el];
		while (stack.length > 0) {
			var n = stack.pop();
			if (n.nodeType != Node.ELEMENT_NODE) continue;
			out.push(cast n);
			var c = n.lastChild;
			while (c != null) {
				stack.push(c);
				c = c.previousSibling;
			}
		}
	}

	// (the blocks a resize's changed rules weren't matched in, while skipped: styled again whole when laid out)
	final unstyled = new ObjectMap<Box, Bool>();

	// (laid out at the view's size from the cache; the fragments of the layouts
	// before it, kept for the cache, dropped once they are a few times a whole
	// layout's, and everything laid out afresh; the elements kept to style
	// again in the blocks it will lay out styled first)
	function lay():Int {
		if ((pending.keys().hasNext() || unstyled.keys().hasNext()) && lazy != null && window != null) {
			var due = [];
			for (b in lazy.within(window[0], window[1])) {
				if (unstyled.exists(b)) {
					unstyled.remove(b);
					elementsOf(b, due);
				}
				var list = pending.get(b);
				if (list == null) continue;
				pending.remove(b);
				for (el in list) due.push(el);
			}
			if (window[0] == Math.NEGATIVE_INFINITY) for (el in waiting()) due.push(el);
			if (due.length > 0 && restyle(due, NOTHING) == TREE) {
				restyle(waiting(), NOTHING);
				build();
			}
		}
		lined = null;
		textIndex = null;
		placed = null;
		var r = tree.root;
		if (r == null) return root = -1;
		if (fragments.count > 3 * whole + 4096) {
			fragments.clear();
			placedRuns.clear();
			forget(r);
		}
		var fresh = fragments.count == 0;
		var space = new Space(fragments, fonts, viewWidth, viewHeight);
		if (window != null && tree.count > LONG) {
			lazy ??= new Lazy(estimate);
			lazy.top = window[0];
			lazy.bottom = window[1];
			lazy.reset();
			space.lazy = lazy;
		} else
			lazy = null;
		var f = (r.context ?? options.contexts.flow).layout(r, space);
		var off = helder.ui.flow.BlockFlow.offset(r, viewWidth, viewHeight);
		fragments.moveTo(f, r.marginLeft + off.x, r.topPositive + r.topNegative + off.y);
		// (sticky boxes against their scrollport at a scroll of 0; printed pages have none: they stay)
		if (sticky && (options.media == null || options.media.type != "print")) helder.ui.flow.Sticky.apply(fragments, f, viewWidth, viewHeight);
		order = new PaintOrder(fragments, f, null, order != null ? order.count + (order.count >> 3) : 0);
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
		// (what is in a block a lazy layout skipped styled again when it is laid out)
		var redo = restyle(defer(c.restyle.changed()), c.structure ? TREE : NOTHING);
		skipped = null;
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

	// (the elements marked styled again, those their changes reach too, their
	// boxes' styles swapped: what it takes, the most of it and redo)
	function restyle(marked:Array<Element>, redo:Int):Int {
		var olds = new ObjectMap<Element, CssStyle>(), queued = new ObjectMap<Element, Bool>();
		for (el in marked) {
			var o = styles.cached(el);
			if (o != null) olds.set(el, o);
			queued.set(el, true);
		}
		styles.forget(marked);
		var swaps = new ObjectMap<BoxStyle, BoxStyle>(), remade:Array<Element> = [];
		var levels = new ObjectMap<CssStyle, ObjectMap<CssStyle, Int>>();
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
					if (o != null && !queued.exists(ch) && !kept(ch)) {
						olds.set(ch, o);
						queued.set(ch, true);
						styles.forget([ch]);
						marked.push(ch);
					}
					ch = ch.nextElementSibling;
				}
			}
			// (what the change of one style to another takes, worked out once a pair: many elements share both)
			var pairs = levels.get(old);
			if (pairs == null) levels.set(old, pairs = new ObjectMap());
			var level = pairs.get(now);
			if (level == null) pairs.set(now, level = levelOf(old, now));
			if (level == NOTHING) continue;
			if (level == TREE) {
				remade.push(el);
				continue;
			}
			var boxes = boxesOf(el);
			for (b in boxes) if (b.pseudo == null) swap(b, el, old, now, swaps, level == LAYOUT);
			// (its pseudo-elements' boxes: their styles made again, swapped the same way, or the tree made again)
			for (b in boxes) if (b.pseudo != null && redo < TREE) {
				var was = b.style.css, next = styles.computed(el, b.pseudo);
				if (next == was) continue;
				var i:Int = cast was.impact(next);
				if (i <= (cast helder.css.CssProperties.CssImpact.Text : Int) && structural(was, next)) remade.push(el) else swap(b, el, was, next, swaps,
					i <= (cast helder.css.CssProperties.CssImpact.Text : Int));
			}
			if (level > redo) redo = level;
		}
		// (boxes of another kind: the nearest block around them that can be made again from its styles, or the tree)
		for (el in remade) {
			if (redo == TREE) break;
			// (it, else the nearest block around it that can be: a list item's marker counts on its list, say; one
			// in what was made again already is)
			var e = el, done = false;
			while (e != null && !done) {
				var bs = [for (b in boxesOf(e)) if (b.pseudo == null) b];
				if (bs.length > 0 && !attached(bs[0])) done = true;
				else if (bs.length == 1 && bs[0].parent != null && (e == el || bs[0].kind == Block || bs[0].kind == Container)) {
					var p = bs[0].parent, made = tree.rebuild(e, bs[0]);
					if (made != null) {
						stale(p);
						owned(e, made);
						for (b in made) marks(b);
						if (made.length == 0) marks(p);
						done = true;
					}
				}
				e = e.parentElement;
			}
			redo = done ? (redo > LAYOUT ? redo : LAYOUT) : TREE;
		}
		if (remade.length > 0 && redo < TREE) sizes.clear();
		return redo;
	}

	// (what a box's style changed from one to another takes: nothing, its paint, its paint order, its layout, its
	// boxes made again)
	static function levelOf(old:CssStyle, now:CssStyle):Int {
		var impact:Int = cast old.impact(now);
		if (impact == (cast helder.css.CssProperties.CssImpact.None : Int)) return NOTHING;
		if (impact <= (cast helder.css.CssProperties.CssImpact.Text : Int)) return structural(old, now) ? TREE : LAYOUT;
		if (impact == (cast helder.css.CssProperties.CssImpact.Composite : Int)) return ORDER;
		return reaches(old, now) ? ORDER : PAINT;
	}

	// (the boxes of el and what is in it, made again: those of its nodes)
	function owned(el:Element, made:Array<Box>) {
		if (owners == null) return;
		var stack:Array<Node> = [el];
		while (stack.length > 0) {
			var n = stack.pop();
			owners.remove(n);
			var c = n.firstChild;
			while (c != null) {
				stack.push(c);
				c = c.nextSibling;
			}
		}
		var boxes = made.copy();
		while (boxes.length > 0) {
			var b = boxes.pop();
			if (b.node != null) {
				var list = owners.get(b.node);
				if (list == null) owners.set(b.node, list = []);
				list.push(b);
			}
			var c = b.first;
			while (c != null) {
				boxes.push(c);
				c = c.next;
			}
		}
	}

	// (in the tree, not in a part of it made again)
	function attached(b:Box):Bool {
		while (b.parent != null) b = b.parent;
		return b == tree.root;
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
		if (area != null) {
			placedRuns.next();
			bp.placedRuns = placedRuns;
		}
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
		var blocks = texts(), ix = index();
		if (blocks.length == 0) return null;
		var best = -1, far = Math.POSITIVE_INFINITY;
		inline function consider(k:Int) {
			var dy = y < ix.y0[k] ? ix.y0[k] - y : y > ix.y1[k] ? y - ix.y1[k] : 0.0;
			var dx = x < ix.x0[k] ? ix.x0[k] - x : x > ix.x1[k] ? x - ix.x1[k] : 0.0;
			// (inside: the innermost, the last in the tree's order; else the nearest, down then across)
			var d = dy * 1e4 + dx;
			if (d < far || d == far && k > best) {
				far = d;
				best = k;
			}
		}
		// (the bucket the point is in, then rings of buckets around it until one beyond the nearest found)
		var at = Std.int(Math.max(0, Math.min(ix.buckets.length - 1, Math.floor(y / BUCKET)))), r = 0;
		while (r <= ix.buckets.length) {
			for (b in [at - r, at + r]) if (b >= 0 && b < ix.buckets.length && (r > 0 || b == at)) for (k in ix.buckets[b]) consider(k);
			if (best >= 0 && far / 1e4 < r * BUCKET) break;
			r++;
		}
		var o = blocks[best].lines;
		return o.hit(x - ix.x0[best], y - ix.y0[best]);
	}

	// (the text blocks' places, absolute: each block in the buckets of BUCKET px its lines cover; each text's block)
	static inline var BUCKET = 256;
	var textIndex:Null<TextIndex> = null;

	function index():TextIndex {
		if (textIndex != null) return textIndex;
		var blocks = texts(), ix = new TextIndex();
		var tall = 0.0;
		for (k in 0...blocks.length) {
			var id = blocks[k].lines.fragment, o = fragments.absolute(id);
			ix.x0.push(o.x);
			ix.y0.push(o.y);
			ix.x1.push(o.x + fragments.width(id));
			ix.y1.push(o.y + fragments.height(id));
			tall = Math.max(tall, o.y + fragments.height(id));
			ix.of.set(blocks[k], k);
		}
		var n = Std.int(Math.ceil(tall / BUCKET)) + 1;
		for (_ in 0...n) ix.buckets.push([]);
		for (k in 0...blocks.length) {
			var b0 = Std.int(Math.max(0, Math.floor(ix.y0[k] / BUCKET))), b1 = Std.int(Math.min(n - 1, Math.floor(ix.y1[k] / BUCKET)));
			for (b in b0...b1 + 1) ix.buckets[b].push(k);
		}
		return textIndex = ix;
	}

	// (the block whose lines hold a DOM text: up from its runs to the nearest block with lines; -1: none)
	function blockOf(node:Node):Int {
		var ix = index();
		for (b in boxesOf(node)) {
			var p:Null<Box> = b;
			while (p != null) {
				var k = ix.of.get(p);
				if (k != null) return k;
				p = p.parent;
			}
		}
		return -1;
	}

	// The caret at a DOM position (a text node and an offset in it) in the
	// document, its line's height; null: not in any lines. Transforms aside.
	public function caret(node:Node, offset:Int):Null<{x:Float, y:Float, height:Float}> {
		var k = blockOf(node);
		if (k < 0) return null;
		var b = texts()[k], u = b.lines.unitOf(node, offset);
		if (u < 0) return null;
		var c = b.lines.caret(u), ix = index();
		return {x: ix.x0[k] + c.x, y: ix.y0[k] + c.y, height: c.height};
	}

	// The rectangles a selection from one DOM position to another covers in
	// the document: each line's selected runs, the line's height, block by
	// block in the box tree's order. Transforms aside.
	public function selection(from:{node:Node, offset:Int}, to:{node:Node, offset:Int}, top = Math.NEGATIVE_INFINITY,
			bottom = Math.POSITIVE_INFINITY):Array<{x:Float, y:Float, width:Float, height:Float}> {
		var blocks = texts(), ix = index();
		var b0 = blockOf(from.node), b1 = blockOf(to.node);
		var u0 = b0 < 0 ? -1 : blocks[b0].lines.unitOf(from.node, from.offset), u1 = b1 < 0 ? -1 : blocks[b1].lines.unitOf(to.node, to.offset);
		if (b0 < 0 || b1 < 0 || u0 < 0 || u1 < 0) return [];
		if (b1 < b0 || b1 == b0 && u1 < u0) {
			var t = b0, v = u0;
			b0 = b1;
			u0 = u1;
			b1 = t;
			u1 = v;
		}
		var out = [];
		// (top...bottom: the blocks there alone, what is seen of a long selection)
		for (k in b0...b1 + 1) {
			if (ix.y1[k] < top || ix.y0[k] > bottom) continue;
			var l = blocks[k].lines;
			for (r in l.selection(k == b0 ? u0 : 0, k == b1 ? u1 : l.content.text.length))
				out.push({x: ix.x0[k] + r.x, y: ix.y0[k] + r.y, width: r.width, height: r.height});
		}
		return out;
	}

	// (the boxes with lines in this layout, in the tree's order)
	function texts():Array<Box> {
		if (lined != null) return lined;
		var out = lined = [];
		if (tree == null || tree.root == null || root < 0) return out;
		// (in tree order: a box, its children, then its next sibling; past a block a lazy layout left unlaid)
		var b:Null<Box> = tree.root, partly = lazy != null;
		while (b != null) {
			if (b.lines != null && b.lines.fragment < fragments.count && fragments.box(b.lines.fragment) == b) out.push(b);
			if (b.first != null && !(partly && b.flags & Box.LAZY != 0 && b.flags & Box.KEPT == 0)) b = b.first else {
				while (b != null && b.next == null) b = b.parent;
				b = b == null ? null : b.next;
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

// (DocumentView's text blocks' places: absolute bounds by block, the blocks in each bucket of rows, each block's number)
private class TextIndex {
	public final x0:Array<Float> = [];
	public final y0:Array<Float> = [];
	public final x1:Array<Float> = [];
	public final y1:Array<Float> = [];
	public final buckets:Array<Array<Int>> = [];
	public final of = new ObjectMap<Box, Int>();

	public function new() {}
}
