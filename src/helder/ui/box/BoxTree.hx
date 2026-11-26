package helder.ui.box;

import helder.canvas.Bitmap;
import helder.css.CssCounters;
import helder.css.CssStyles;
import helder.css.CssTerm;
import helder.dom.Document;
import helder.dom.Element;
import helder.dom.Node;
import helder.dom.Text;
import helder.ui.flow.Contexts;

using StringTools;

typedef BoxTreeOptions = {
	// the formatting contexts a program lays out with (Contexts.all(): every one)
	?contexts:Contexts,
	// an image by its URL as written (an <img>'s src, content's url()); null: none
	?image:(url:String) -> Null<Bitmap>
}

// The box tree of a document (CSS 2.1 §9.2, Display 3 §2): each element's
// boxes by its display, none and contents skipped, text runs, replaced
// elements, ::before, ::after and ::marker with their content (helder.css's
// CssCounters: strings, attr(), counters in their styles, quotes, images),
// and anonymous boxes: inline-level runs beside
// blocks wrapped in anonymous blocks (white space alone dropped), an
// inline box holding a block split around it (§9.2.1.1).
class BoxTree {
	public final root:Null<Box>;
	// what this slice lays out in another way than its spec says, once each ("flex: ...")
	public final pending:Array<String> = [];
	public var count(default, null) = 0;

	final styles:CssStyles;
	final contexts:Contexts;
	final image:Null<String->Null<Bitmap>>;
	// (one BoxStyle a computed style: helder.css shares styles between like elements)
	final cache = new haxe.ds.ObjectMap<helder.css.CssStyle, BoxStyle>();
	final counters:CssCounters;

	public static function build(doc:Document, styles:CssStyles, ?options:BoxTreeOptions):BoxTree
		return new BoxTree(doc, styles, options ?? {});

	function new(doc:Document, styles:CssStyles, options:BoxTreeOptions) {
		this.styles = styles;
		contexts = options.contexts ?? Contexts.all();
		image = options.image;
		counters = new CssCounters(styles);
		var out = [];
		var el = doc.documentElement;
		if (el != null) generate(el, out);
		root = out.length > 0 ? out[0] : null;
	}

	function style(el:Element):BoxStyle {
		var css = styles.computed(el);
		var s = cache.get(css);
		if (s == null) cache.set(css, s = new BoxStyle(css));
		return s;
	}

	function note(what:String)
		if (!pending.contains(what)) pending.push(what);

	function make(kind:BoxKind, s:BoxStyle, ?node:Node, ?pseudo:String):Box {
		count++;
		var b = new Box(kind, s, node, pseudo);
		if (b.container || kind == TableWrapper) b.context = contexts.of(kind == TableWrapper ? BoxStyle.TABLE : s.inner, note);
		if (s.floating) note("floats: laid out in flow");
		if (s.absolute) note("positioning: absolute and fixed laid out in flow");
		return b;
	}

	// ---- elements

	// (its boxes, its counters entered before and left after: helder.css's CssCounters, in tree order)
	function generate(el:Element, out:Array<Box>) {
		var s = style(el);
		if (s.none) return;
		counters.enter(el);
		boxes(el, s, out);
		counters.exit(el);
	}

	function boxes(el:Element, s:BoxStyle, out:Array<Box>) {
		if (s.contents) {
			contents(el, s, out);
			return;
		}
		var kind = kindOf(el, s);
		switch kind {
			case Break:
				out.push(make(Break, s, el));
			case InlineReplaced | BlockReplaced:
				var b = make(kind, s, el);
				b.image = load(el.getAttribute(el.localName == "object" ? "data" : "src"));
				if (b.image == null && el.localName == "object") {
					contents(el, s, out);
					return;
				}
				out.push(b);
			case Inline:
				var kids = [];
				contents(el, s, kids);
				split(el, s, orphans(kids, s, true), out);
			case Container if (s.inner == BoxStyle.TABLE):
				var kids = [];
				contents(el, s, kids);
				out.push(table(s, el, kids));
			case Container if (s.inner == BoxStyle.TABLE_PART):
				var b = make(Container, s, el);
				var kids = [];
				contents(el, s, kids);
				part(b, kids);
				out.push(b);
			case _:
				var b = make(kind, s, el);
				var kids = [];
				var marker = s.listItem ? marker(el) : null;
				if (marker != null && marker.flags & Box.OUTSIDE == 0) kids.push(marker);
				contents(el, s, kids);
				fill(b, orphans(kids, s, false));
				if (marker != null && marker.flags & Box.OUTSIDE != 0) placeOutside(b, marker);
				out.push(b);
		}
	}

	function kindOf(el:Element, s:BoxStyle):BoxKind {
		var html = el.namespaceURI == "http://www.w3.org/1999/xhtml";
		var inlineLevel = s.outer == BoxStyle.INLINE;
		if (html) switch el.localName {
			case "br": return Break;
			case "img": return inlineLevel ? InlineReplaced : BlockReplaced;
			case "object" if (el.hasAttribute("data") && load(el.getAttribute("data")) != null): return inlineLevel ? InlineReplaced : BlockReplaced;
			case _:
		}
		return switch s.inner {
			case BoxStyle.TABLE | BoxStyle.FLEX | BoxStyle.GRID | BoxStyle.TABLE_PART: Container;
			case BoxStyle.FLOW_ROOT if (inlineLevel): InlineBlock;
			case _ if (inlineLevel): Inline;
			case _: Block;
		}
	}

	// el's children's boxes, ::before and ::after around them
	function contents(el:Element, s:BoxStyle, out:Array<Box>) {
		pseudo(el, "before", out);
		var n = el.firstChild;
		while (n != null) {
			switch n.nodeType {
				case Node.ELEMENT_NODE: generate(cast n, out);
				case Node.TEXT_NODE | Node.CDATA_SECTION_NODE:
					var t:Text = cast n;
					if (t.data.length > 0) {
						var b = make(Text, s, t);
						b.text = t.data;
						out.push(b);
					}
				case _:
			}
			n = n.nextSibling;
		}
		pseudo(el, "after", out);
	}

	// An inline box's parts: itself when it holds no block, else one part
	// between each block it holds (CSS 2.1 §9.2.1.1), each part's edges
	// only where the box starts and ends.
	function split(el:Element, s:BoxStyle, kids:Array<Box>, out:Array<Box>) {
		var part = make(Inline, s, el);
		var parts = [part];
		for (k in kids) {
			if (!k.blockLevel) {
				part.append(k);
				continue;
			}
			part.flags |= Box.NO_END;
			out.push(part);
			out.push(k);
			part = make(Inline, s, el);
			part.flags |= Box.NO_START;
			parts.push(part);
		}
		out.push(part);
	}

	// A block container's children: inline-level runs beside blocks in
	// anonymous blocks, a run of collapsible white space alone dropped.
	function fill(b:Box, kids:Array<Box>) {
		if (!Lambda.exists(kids, k -> k.blockLevel)) {
			for (k in kids) b.append(k);
			return;
		}
		var run:Array<Box> = [];
		function flush() {
			if (run.length == 0) return;
			if (!Lambda.foreach(run, blank)) {
				var anon = make(Block, b.style.anonymousChild());
				for (k in run) anon.append(k);
				b.append(anon);
			}
			run = [];
		}
		for (k in kids) {
			if (k.blockLevel) {
				flush();
				b.append(k);
			} else
				run.push(k);
		}
		flush();
	}

	// ---- tables (CSS 2.1 §17.2.1: anonymous table objects)

	static inline function isPart(b:Box):Bool
		return b.kind == Container && b.style.inner == BoxStyle.TABLE_PART;

	static inline function partOf(b:Box):Int
		return isPart(b) ? b.style.part : 0;

	// A table: its wrapper box (its captions above or below, CSS 2.1 §17.4) around the table box.
	function table(s:BoxStyle, el:Null<Element>, kids:Array<Box>, ?pseudo:String):Box {
		var wrapper = make(TableWrapper, s, el, pseudo);
		var t = make(Container, s, el, pseudo);
		var above = [], below = [], rest = [];
		for (k in kids)
			if (partOf(k) == BoxStyle.CAPTION) (k.style.keyword("caption-side") == "bottom" ? below : above).push(k) else rest.push(k);
		runs(t, rest, k -> switch partOf(k) {
			case BoxStyle.ROW_GROUP | BoxStyle.HEADER_GROUP | BoxStyle.FOOTER_GROUP | BoxStyle.ROW | BoxStyle.COLUMN_GROUP | BoxStyle.COLUMN: true;
			case _: false;
		}, run -> row(t.style, run));
		for (c in above) wrapper.append(c);
		wrapper.append(t);
		for (c in below) wrapper.append(c);
		return wrapper;
	}

	// A table part's children: a row group's rows, a row's cells, a column group's columns,
	// anonymous ones around what else is there; a cell's and a caption's as a block's.
	function part(b:Box, kids:Array<Box>)
		switch b.style.part {
			case BoxStyle.ROW_GROUP | BoxStyle.HEADER_GROUP | BoxStyle.FOOTER_GROUP:
				runs(b, kids, k -> partOf(k) == BoxStyle.ROW, run -> row(b.style, run));
			case BoxStyle.ROW:
				runs(b, kids, k -> partOf(k) == BoxStyle.CELL, run -> cell(b.style, run));
			case BoxStyle.COLUMN_GROUP:
				for (k in kids) if (partOf(k) == BoxStyle.COLUMN) b.append(k);
			case BoxStyle.COLUMN:
			case _:
				fill(b, orphans(kids, b.style, false));
		}

	function row(parent:BoxStyle, kids:Array<Box>):Box {
		var r = make(Container, parent.anonymousTable(BoxStyle.TABLE_PART, BoxStyle.ROW));
		part(r, kids);
		return r;
	}

	function cell(parent:BoxStyle, kids:Array<Box>):Box {
		var c = make(Container, parent.anonymousTable(BoxStyle.TABLE_PART, BoxStyle.CELL));
		fill(c, orphans(kids, c.style, false));
		return c;
	}

	// (a part's proper children kept, each run of others in one made by wrap; white space alone dropped)
	static function runs(b:Box, kids:Array<Box>, proper:Box->Bool, wrap:Array<Box>->Box) {
		var run = [];
		function flush() {
			if (run.length > 0 && !Lambda.foreach(run, blank)) b.append(wrap(run));
			run = [];
		}
		for (k in kids) {
			if (proper(k)) {
				flush();
				b.append(k);
			} else
				run.push(k);
		}
		flush();
	}

	// (runs of table parts out of a table: an anonymous table around each, §17.2.1's third rule;
	// white space between them in it, around them not)
	function orphans(kids:Array<Box>, s:BoxStyle, inlineParent:Bool):Array<Box> {
		if (!Lambda.exists(kids, isPart)) return kids;
		var out = [], run:Array<Box> = [];
		function flush() {
			var tail = [];
			while (run.length > 0 && !isPart(run[run.length - 1])) tail.unshift(run.pop());
			if (run.length > 0) out.push(table(s.anonymousTable(BoxStyle.TABLE, 0, inlineParent ? BoxStyle.INLINE : BoxStyle.BLOCK), null, run));
			for (t in tail) out.push(t);
			run = [];
		}
		for (k in kids) {
			if (isPart(k) || run.length > 0 && blank(k)) run.push(k) else {
				flush();
				out.push(k);
			}
		}
		flush();
		return out;
	}

	static function blank(b:Box):Bool
		return b.kind == Text && b.style.collapse && ~/^[ \t\n\r\x0C]*$/.match(b.text);

	// ---- generated content

	function pseudo(el:Element, which:String, out:Array<Box>) {
		var css = styles.computed(el, which);
		if (css.generated() == null) return;
		var s = new BoxStyle(css);
		if (s.none) return;
		counters.enter(el, which);
		var kids = parts(el, s, which, counters.content(el, which));
		counters.exit(el, which);
		kids = orphans(kids, s, s.outer == BoxStyle.INLINE);
		var kind:BoxKind = s.contents ? Inline : kindOf(el, s);
		if (kind == Break || kind == InlineReplaced || kind == BlockReplaced) kind = s.outer == BoxStyle.INLINE ? Inline : Block;
		if (kind == Inline) {
			var b = make(Inline, s, el, which);
			for (k in kids) b.append(k);
			out.push(b);
		} else if (kind == Container && s.inner == BoxStyle.TABLE) {
			out.push(table(s, el, kids, which));
		} else if (kind == Container && s.inner == BoxStyle.TABLE_PART) {
			var b = make(Container, s, el, which);
			part(b, kids);
			out.push(b);
		} else {
			var b = make(kind, s, el, which);
			fill(b, kids);
			out.push(b);
		}
	}

	// (generated content's parts, resolved by CssCounters: text runs and images)
	function parts(el:Element, s:BoxStyle, which:String, list:Null<Array<CssGeneratedPart>>):Array<Box> {
		var out = [];
		if (list != null) for (p in list) switch p {
			case Text(text) if (text != ""):
				var b = make(Text, s, null, which);
				b.text = text;
				out.push(b);
			case Image(Url(url, _)):
				var b = make(InlineReplaced, s, el, which);
				b.image = load(url);
				out.push(b);
			case _:
		}
		return out;
	}

	// A list item's ::marker (CssCounters': its content, else list-style-image, else
	// list-style-type's text for its list-item counter).
	function marker(el:Element):Null<Box> {
		var s = new BoxStyle(styles.computed(el, "marker"));
		counters.enter(el, "marker");
		var kids = parts(el, s, "marker", counters.marker(el));
		// (a list-style-image that doesn't load: list-style-type's marker, Lists 3 §3.2)
		if (kids.length == 1 && kids[0].kind == InlineReplaced && kids[0].image == null) {
			var type = s.keyword("list-style-type");
			kids = type == "none" || type == "" ? [] : parts(el, s, "marker", [Text(counters.formats.marker(counters.value("list-item"), type))]);
		}
		counters.exit(el, "marker");
		if (kids.length == 0) return null;
		var b = make(Inline, s, el, "marker");
		for (k in kids) b.append(k);
		if (style(el).keyword("list-style-position") != "inside") b.flags |= Box.OUTSIDE;
		return b;
	}

	// (an outside marker goes in the first line: the first descendant block of inline content)
	function placeOutside(b:Box, marker:Box) {
		var at = b;
		while (at.first != null && at.first.kind == Block) at = at.first;
		if (at.first != null && at.first.blockLevel) return;
		@:privateAccess {
			marker.parent = at;
			marker.next = at.first;
			at.first = marker;
			if (at.last == null) at.last = marker;
		}
	}

	function load(url:Null<String>):Null<Bitmap>
		return url == null || url == "" || image == null ? null : image(url);

	// The tree, a box a line, indented (tests and the dev tool).
	public function dump():String {
		var out = new StringBuf();
		function walk(b:Box, depth:Int) {
			out.add("".lpad(" ", depth * 2) + b.toString() + "\n");
			var c = b.first;
			while (c != null) {
				walk(c, depth + 1);
				c = c.next;
			}
		}
		if (root != null) walk(root, 0);
		return out.toString();
	}
}
