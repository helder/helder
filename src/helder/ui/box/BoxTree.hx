package helder.ui.box;

import helder.canvas.Bitmap;
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
// elements, ::before, ::after and ::marker with their content (strings,
// attr(), counters, quotes), and anonymous boxes: inline-level runs beside
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
	final cache = new Map<Element, BoxStyle>();
	final counters = new Map<String, Array<Int>>();
	var quotes = 0;

	public static function build(doc:Document, styles:CssStyles, ?options:BoxTreeOptions):BoxTree
		return new BoxTree(doc, styles, options ?? {});

	function new(doc:Document, styles:CssStyles, options:BoxTreeOptions) {
		this.styles = styles;
		contexts = options.contexts ?? Contexts.all();
		image = options.image;
		var out = [];
		var el = doc.documentElement;
		if (el != null) generate(el, out);
		root = out.length > 0 ? out[0] : null;
	}

	function style(el:Element):BoxStyle {
		var s = cache.get(el);
		if (s == null) cache.set(el, s = new BoxStyle(styles.computed(el)));
		return s;
	}

	function note(what:String)
		if (!pending.contains(what)) pending.push(what);

	function make(kind:BoxKind, s:BoxStyle, ?node:Node, ?pseudo:String):Box {
		count++;
		var b = new Box(kind, s, node, pseudo);
		if (b.container) b.context = contexts.of(s.inner, note);
		if (s.floating) note("floats: laid out in flow");
		if (s.absolute) note("positioning: absolute and fixed laid out in flow");
		return b;
	}

	// ---- elements

	function generate(el:Element, out:Array<Box>) {
		var s = style(el);
		if (s.none) return;
		applyCounters(s, s.listItem);
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
				split(el, s, kids, out);
			case _:
				var b = make(kind, s, el);
				var kids = [];
				var marker = s.listItem ? marker(el) : null;
				if (marker != null && marker.flags & Box.OUTSIDE == 0) kids.push(marker);
				contents(el, s, kids);
				fill(b, kids);
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
		var saved = scope();
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
		restore(saved);
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

	static function blank(b:Box):Bool
		return b.kind == Text && b.style.collapse && ~/^[ \t\n\r\x0C]*$/.match(b.text);

	// ---- generated content

	function pseudo(el:Element, which:String, out:Array<Box>) {
		var css = styles.computed(el, which);
		var content = css.get("content");
		if (content.length == 0 || content[0].match(Keyword("none" | "normal"))) return;
		var s = new BoxStyle(css);
		if (s.none) return;
		applyCounters(s, false);
		var kids = [];
		for (t in content) generated(el, s, t, which, kids);
		var kind:BoxKind = s.contents ? Inline : kindOf(el, s);
		if (kind == Break || kind == InlineReplaced || kind == BlockReplaced) kind = s.outer == BoxStyle.INLINE ? Inline : Block;
		if (kind == Inline) {
			var b = make(Inline, s, el, which);
			for (k in kids) b.append(k);
			out.push(b);
		} else {
			var b = make(kind, s, el, which);
			fill(b, kids);
			out.push(b);
		}
	}

	// (one part of content: text, or an image)
	function generated(el:Element, s:BoxStyle, t:CssTerm, which:String, out:Array<Box>) {
		var text:Null<String> = switch t {
			case Str(v): v;
			case Func("attr", [Ident(name)]) | Func("attr", [Ident(name), _]): el.getAttribute(name) ?? "";
			case Func("counter", args): counterText(args, false);
			case Func("counters", args): counterText(args, true);
			case Keyword("open-quote"): quotes++ < 1 ? "“" : "‘";
			case Keyword("close-quote"): --quotes < 1 ? (quotes = quotes < 0 ? 0 : quotes) == 0 ? "”" : "’" : "’";
			case Keyword("no-open-quote"):
				quotes++;
				"";
			case Keyword("no-close-quote"):
				if (quotes > 0) quotes--;
				"";
			case Url(url, _):
				var b = make(InlineReplaced, s, el, which);
				b.image = load(url);
				out.push(b);
				null;
			case _: null;
		}
		if (text == null || text == "") return;
		var b = make(Text, s, null, which);
		b.text = text;
		out.push(b);
	}

	// A list item's ::marker: its content, else its list-style-type's
	// symbol or number.
	function marker(el:Element):Null<Box> {
		var css = styles.computed(el, "marker");
		var s = new BoxStyle(css);
		var text = switch css.get("content") {
			case [Keyword("normal")] | []: switch css.get("list-style-type") {
					case [Str(v)]: v;
					case [Keyword("none")] | [Ident("none")]: null;
					case [Ident(name)] | [Keyword(name)]: Counters.marker(name, top("list-item"));
					case _: null;
				}
			case [Keyword("none")]: null;
			case terms:
				var kids = [];
				for (t in terms) generated(el, s, t, "marker", kids);
				[for (k in kids) k.text].join("");
		}
		if (text == null || text == "") return null;
		var b = make(Inline, s, el, "marker");
		var t = make(Text, s, null, "marker");
		t.text = text;
		b.append(t);
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

	// ---- counters (Lists 3 §4, simplified: an instance lasts until its parent element ends)

	function scope():Map<String, Int>
		return [for (k => v in counters) k => v.length];

	function restore(saved:Map<String, Int>)
		for (k => v in counters) {
			var n = saved.exists(k) ? saved.get(k) : 0;
			if (v.length > n) v.resize(n);
		}

	function applyCounters(s:BoxStyle, listItem:Bool) {
		var incremented = false;
		each(s.terms("counter-reset"), 0, (name, v) -> {
			var c = counters.get(name);
			if (c == null) counters.set(name, c = []);
			c.push(v);
		});
		each(s.terms("counter-increment"), 1, (name, v) -> {
			if (name == "list-item") incremented = true;
			var c = counters.get(name);
			if (c == null || c.length == 0) counters.set(name, c = [0]);
			c[c.length - 1] += v;
		});
		each(s.terms("counter-set"), 0, (name, v) -> {
			var c = counters.get(name);
			if (c == null || c.length == 0) counters.set(name, c = [0]);
			c[c.length - 1] = v;
		});
		if (listItem && !incremented) {
			var c = counters.get("list-item");
			if (c == null || c.length == 0) counters.set("list-item", c = [0]);
			c[c.length - 1]++;
		}
	}

	static function each(terms:Array<CssTerm>, by:Int, f:(String, Int) -> Void) {
		var i = 0;
		while (i < terms.length) {
			switch terms[i] {
				case Ident(name) | Func(_, [Ident(name)]):
					var v = by;
					switch terms[i + 1] {
						case Number(n, _):
							v = Std.int(n);
							i++;
						case _:
					}
					f(name, v);
				case _:
			}
			i++;
		}
	}

	function top(name:String):Int {
		var c = counters.get(name);
		return c == null || c.length == 0 ? 0 : c[c.length - 1];
	}

	function counterText(args:Array<CssTerm>, all:Bool):String {
		var name = switch args[0] {
			case Ident(n): n;
			case _: return "";
		}
		var sep = "", styleName = "decimal";
		for (a in args.slice(1)) switch a {
			case Str(v): sep = v;
			case Ident(v) | Keyword(v): styleName = v;
			case _:
		}
		var c = counters.get(name);
		if (c == null || c.length == 0) c = [0];
		return all ? [for (v in c) Counters.text(styleName, v)].join(sep) : Counters.text(styleName, c[c.length - 1]);
	}

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
