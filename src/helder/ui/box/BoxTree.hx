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
	?image:(url:String) -> Null<Bitmap>,
	// an SVG image by its URL as written, where image has none
	?svg:(url:String) -> Null<helder.canvas.Svg>,
	// for pages (GCPM 3): running elements out of the flow, string-set's values kept
	?paged:Bool
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
	final svg:Null<String->Null<helder.canvas.Svg>>;
	// (one BoxStyle a computed style: helder.css shares styles between like elements)
	final cache = new haxe.ds.ObjectMap<helder.css.CssStyle, BoxStyle>();
	public final counters:CssCounters;
	// paged: each running element (its name, its boxes, where it was: a RUNNING holder, null when inline-level)
	public final running:Array<{name:String, box:Box, holder:Null<Box>}> = [];
	// paged: each element's string-set values, evaluated where the walk meets it
	public final strings = new haxe.ds.ObjectMap<Element, Array<{name:String, value:String}>>();
	// paged: the elements with bookmarks (bookmark-level, -label, -state), in document order
	public final bookmarks:Array<{element:Element, bookmark:helder.css.CssCounters.CssBookmark}> = [];
	// each cross-reference's text box (target-counter(), target-counters(), target-text()), resolveTargets' to fill
	public final targets:Array<{box:Box, target:helder.css.CssCounters.CssTarget}> = [];
	final paged:Bool;

	public static function build(doc:Document, styles:CssStyles, ?options:BoxTreeOptions):BoxTree
		return new BoxTree(doc, styles, options ?? {});

	function new(doc:Document, styles:CssStyles, options:BoxTreeOptions) {
		this.styles = styles;
		contexts = options.contexts ?? Contexts.all();
		image = options.image;
		svg = options.svg;
		paged = options.paged ?? false;
		counters = new CssCounters(styles);
		var out = [];
		var el = doc.documentElement;
		if (el != null) generate(el, out);
		root = out.length > 0 ? out[0] : null;
		// (cross-references to what the walk passed; a page counter's: 0 until the pages are known)
		resolve(_ -> 0);
	}

	// Cross-references' texts, the pages they are on by pageOf: whether one changed.
	public function resolve(pageOf:Element->Int):Bool {
		counters.resolveTargets(pageOf);
		var changed = false;
		for (t in targets) {
			var text = t.target.text ?? "";
			if (t.box.text != text) {
				t.box.text = text;
				changed = true;
			}
		}
		return changed;
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
		return b;
	}

	// ---- elements

	// (its boxes, its counters entered before and left after: helder.css's CssCounters, in tree order)
	function generate(el:Element, out:Array<Box>) {
		var s = style(el);
		if (s.none) return;
		counters.enter(el);
		if (paged) {
			var set = counters.strings(el);
			if (set.length > 0) strings.set(el, set);
			var mark = counters.bookmark(el);
			if (mark != null) bookmarks.push({element: el, bookmark: mark});
		}
		// (a running element: its boxes kept apart for the margin boxes, a holder where it was when block-level)
		var name = paged ? s.css.running() : null;
		if (name != null) {
			var kids = [];
			boxes(el, s, kids);
			var holder = s.outer == BoxStyle.INLINE ? null : make(Block, s.anonymousChild(), el);
			if (holder != null) {
				holder.flags |= Box.RUNNING;
				out.push(holder);
			}
			for (k in kids) running.push({name: name, box: k, holder: holder});
		} else
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
				if (el.namespaceURI == SVG) b.svg = BoxImages.of(el, styles) else source(b, el.getAttribute(el.localName == "object" ? "data" : "src"));
				if (b.image == null && b.svg == null && el.localName == "object") {
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
				firstLetter(el, b);
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
			case "object" if (el.hasAttribute("data") && (load(el.getAttribute("data")) != null || vector(el.getAttribute("data")) != null)):
				return inlineLevel ? InlineReplaced : BlockReplaced;
			case _:
		}
		// (an svg element in HTML, outermost: a replaced element, SVG 2 §5.1)
		if (el.namespaceURI == SVG && el.localName == "svg" && (el.parentElement == null || el.parentElement.namespaceURI != SVG))
			return inlineLevel ? InlineReplaced : BlockReplaced;
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
			if (!inFlowBlock(k)) {
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
		// (a flex or grid container's items: each in-flow block, each run of inline content in an anonymous
		// block, a run of white space alone none, Flexbox §4, Grid §6)
		var inner = b.style.inner;
		if (inner == BoxStyle.FLEX || inner == BoxStyle.GRID) {
			var run = [];
			function wrap() {
				if (run.length > 0 && !Lambda.foreach(run, blank)) {
					var anon = make(Block, b.style.anonymousChild());
					for (k in run) anon.append(k);
					b.append(anon);
				}
				run = [];
			}
			for (k in kids) if (inFlowBlock(k) || outOfFlow(k)) {
				wrap();
				b.append(k);
			} else run.push(k);
			wrap();
			return;
		}
		if (!Lambda.exists(kids, inFlowBlock)) {
			for (k in kids) b.append(k);
			return;
		}
		var run = [];
		function flush() {
			if (run.length == 0) return;
			// (floats and absolutely positioned boxes alone between blocks stay blocks' siblings)
			if (Lambda.foreach(run, k -> blank(k) || outOfFlow(k))) {
				for (k in run) if (!blank(k)) b.append(k);
			} else {
				var anon = make(Block, b.style.anonymousChild());
				for (k in run) anon.append(k);
				b.append(anon);
			}
			run = [];
		}
		for (k in kids) {
			if (inFlowBlock(k)) {
				flush();
				b.append(k);
			} else
				run.push(k);
		}
		flush();
	}

	static inline function outOfFlow(b:Box):Bool
		return b.floating || b.absolute;

	// (block-level and in flow: what puts the inline content around it in anonymous blocks)
	static inline function inFlowBlock(b:Box):Bool
		return b.blockLevel && !outOfFlow(b);

	// ---- ::first-letter (CSS 2.1 §5.12.2, Pseudo-Elements 4 §2.3)

	// The first letter of a block container's first formatted line, with the punctuation before and
	// after it, in a box of the element's ::first-letter style (an inline box, or a float when it floats).
	function firstLetter(el:Element, b:Box) {
		if (!styles.hasPseudo(el, "first-letter")) return;
		var t = firstText(b);
		if (t == null) return;
		var text = t.text, n = text.length, i = 0;
		while (i < n && white(StringTools.fastCodeAt(text, i))) i++;
		var start = i;
		while (i < n && Punctuation.is(code(text, i))) i += width(text, i);
		if (i >= n || white(StringTools.fastCodeAt(text, i))) return;
		i += width(text, i);
		// (its combining marks: a letter is its grapheme cluster)
		while (i < n && mark(code(text, i))) i += width(text, i);
		while (i < n && Punctuation.is(code(text, i))) i += width(text, i);
		var s = new BoxStyle(styles.computed(el, "first-letter"));
		var box = make(s.floating ? Block : Inline, s, el, "first-letter");
		var letter = make(Text, s, t.node);
		letter.text = text.substring(start, i);
		letter.offset = t.offset + start;
		box.append(letter);
		var parts = [];
		if (start > 0) {
			var before = make(Text, t.style, t.node);
			before.text = text.substring(0, start);
			before.offset = t.offset;
			parts.push(before);
		}
		parts.push(box);
		if (i < n) {
			var after = make(Text, t.style, t.node);
			after.text = text.substring(i);
			after.offset = t.offset + i;
			parts.push(after);
		}
		replace(t, parts);
	}

	// (the text run the first line starts with: through inline boxes and first in-flow blocks;
	// none past an atomic inline, a replaced element or a forced break, which come first)
	static function firstText(b:Box):Null<Box> {
		var c = b.first;
		while (c != null) {
			switch c.kind {
				case Text:
					if (!~/^[ \t\n\r\x0C]*$/.match(c.text)) return c;
				case Inline if (c.flags & Box.OUTSIDE != 0 || c.pseudo == "first-letter"):
					if (c.pseudo == "first-letter") return null;
				case Inline:
					var t = firstText(c);
					if (t != null) return t;
					if (c.first != null && !allBlank(c)) return null;
				case Block | Container if (c.floating || c.absolute):
				case Block if (c.blockLevel):
					return firstText(c);
				case _:
					return null;
			}
			c = c.next;
		}
		return null;
	}

	static function allBlank(b:Box):Bool {
		var c = b.first;
		while (c != null) {
			if (c.kind != Text || !~/^[ \t\n\r\x0C]*$/.match(c.text)) return false;
			c = c.next;
		}
		return true;
	}

	// (a box in its parent's children replaced by others)
	static function replace(old:Box, with:Array<Box>)
		@:privateAccess {
			var p = old.parent;
			var prev:Null<Box> = null, k = p.first;
			while (k != null && k != old) {
				prev = k;
				k = k.next;
			}
			var next = old.next;
			for (w in with) w.parent = p;
			for (j in 0...with.length - 1) with[j].next = with[j + 1];
			with[with.length - 1].next = next;
			if (prev == null) p.first = with[0] else prev.next = with[0];
			if (p.last == old) p.last = with[with.length - 1];
		}

	static inline function white(c:Int):Bool
		return c == 32 || c == 9 || c == 10 || c == 13 || c == 12;

	static function code(s:String, i:Int):Int {
		var c = StringTools.fastCodeAt(s, i);
		if (c < 0xD800 || c >= 0xDC00 || i + 1 >= s.length) return c;
		var d = StringTools.fastCodeAt(s, i + 1);
		return d >= 0xDC00 && d < 0xE000 ? ((c - 0xD800) << 10) + (d - 0xDC00) + 0x10000 : c;
	}

	static inline function width(s:String, i:Int):Int
		return code(s, i) > 0xFFFF ? 2 : 1;

	// (combining marks: the common blocks)
	static inline function mark(c:Int):Bool
		return c >= 0x300 && c <= 0x36F || c >= 0x1AB0 && c <= 0x1AFF || c >= 0x1DC0 && c <= 0x1DFF || c >= 0x20D0 && c <= 0x20FF || c >= 0xFE20 && c <= 0xFE2F;

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
				if (b.node != null && b.pseudo == null) firstLetter(cast b.node, b);
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
				source(b, url);
				out.push(b);
			// (a cross-reference: its text once the targets are resolved; a leader: its fill, repeated by the lines)
			case Target(target):
				var b = make(Text, s, null, which);
				b.text = target.text ?? "";
				targets.push({box: b, target: target});
				out.push(b);
			case Leader(fill) if (fill != ""):
				// (a style of its own: its text found in the lines by it)
				var b = make(Text, s.anonymousChild(), null, which);
				b.text = b.fill = fill;
				b.flags |= Box.LEADER;
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
		if (kids.length == 1 && kids[0].kind == InlineReplaced && kids[0].image == null && kids[0].svg == null) {
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

	function vector(url:Null<String>):Null<helder.canvas.Svg>
		return url == null || url == "" || svg == null ? null : svg(url);

	// (a replaced box's image: a raster, else an SVG)
	function source(b:Box, url:Null<String>) {
		b.image = load(url);
		if (b.image == null) b.svg = vector(url);
	}

	static inline var SVG = "http://www.w3.org/2000/svg";

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
