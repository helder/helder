package helder.markdown;

import helder.gfx.Color;
import helder.markdown.Doc;
import helder.ui.Node;
import helder.ui.Style;
import helder.ui.TextNode;
import helder.ui.VirtualScroll;
import helder.ui.access.Role;
import helder.ui.access.Semantics;
import helder.ui.code.CodeLanguage.CodeLanguages;
import helder.ui.code.CodeModel;
import helder.ui.code.CodeView;
import helder.ui.controls.Look;

using Lambda;
using StringTools;

typedef MarkdownProps = {
	doc:Doc,
	// a link pressed (its href as written: "#usage", "other.md", "https://...")
	?onLink:(href:String) -> Void,
	// an image's node for its src (an ImageNode, its image set once decoded);
	// null, or no image function: its alt text in its place
	?image:(src:String, alt:String) -> Null<Node>,
	// in a scroller of its own (true, the default), else as tall as its blocks
	?scroll:Bool,
	// the first blocks alone (a preview's first screen; all by default)
	?blocks:Int,
	// code blocks' font (a monospace family: CodeView's JetBrains Mono by default) and size
	?codeFont:String,
	// a link's part by its href (an app's chips: null, or no function: markdown-link)
	?linkPart:(href:String) -> Null<String>,
	?codeSize:Float
}

// A Markdown document (Markdown.parse's Doc) as nodes: each node's tag is
// its part, its style the plain look's here (GitHub's proportions) with the
// look's part of that name over it (Look.with's parts: the look in scope
// when it is made). The top-level blocks are each in a row ("markdown-row":
// the column's width and the space between blocks), in a scroller
// ("markdown-scroll"), a VirtualScroll past VIRTUAL blocks (only the rows
// in view made). Parts: markdown-h1 to -h6, -p, -quote, -list,
// -list-tight (over a tight list's -list), -item, -marker, -task (checked
// by data-state), -task-mark, -item-body,
// -code (a box around a read-only CodeView: the fence's language by its
// info string, CodeLanguages; plain text otherwise), -table, -th, -td,
// -rule, -html (raw HTML, as text), -image (over an image's own style),
// -image-alt; in text -p-text, -em, -strong, -del, -code-span, -link.
// Links call onLink; images ask image for a node.
// It is one selectable scope (Node.selectable): a selection runs across
// its blocks, a long document's rows out of view too, copied with a blank
// line between blocks and a line between list items (markers not in it).
// Spacing between nested blocks is their container's row-gap (a quote's,
// an item body's, a list's). update(doc) shows another doc (a reply as it
// streams in): the rows of the blocks it shares with the last kept.
class MarkdownView extends Node {
	public static inline var VIRTUAL = 300;

	public var doc(default, null):Doc;
	// the scroller (a VirtualScroll past VIRTUAL blocks; null with scroll false)
	public final scroller:Null<Node>;

	final options:MarkdownProps;
	final look:Look<Dynamic>;
	final parts = new Map<String, Style>();
	var shown:Array<Block>;
	final virtual:Null<VirtualScroll>;
	final rows:Array<Node> = [];
	// (a heading's id: the top-level block it is in)
	final anchors = new Map<String, Int>();
	final ids:Array<String> = [];
	var listDepth = 0;
	// (a row made for its text alone: no image asked for)
	var textOnly = false;

	public function new(props:MarkdownProps) {
		super("markdown");
		options = props;
		look = Look.current();
		doc = props.doc;
		selectable = true;
		shown = props.blocks == null ? doc.blocks : doc.blocks.slice(0, props.blocks);
		for (i in 0...shown.length)
			collectAnchors(shown[i], i);
		style = part("markdown").with({minHeight: 0, minWidth: 0});
		if (props.scroll == false) {
			virtual = null;
			scroller = null;
			for (b in shown) {
				var r = row(b);
				rows.push(r);
				append(r);
			}
			return;
		}
		style = style.with({flexGrow: 1, overflow: Hidden});
		if (shown.length > VIRTUAL) {
			var v = new VirtualScroll("markdown-scroll", 80);
			v.rowRole = null;
			v.focusableRows = false;
			v.semantics = null;
			// (a document's keys: the window's scrolling, not a list's focus moving)
			v.onKeyDown = null;
			v.onMakeRow = (i, r) -> {
				r.style = r.style.with(part("markdown-row"));
				textOnly = r.parent == null;
				r.append(block(shown[i]));
				textOnly = false;
				return null;
			};
			v.onDropRow = (r, _) -> r.removeChildren();
			virtual = v;
			scroller = v;
		} else {
			virtual = null;
			var s = new Node("markdown-scroll");
			s.style = Style.of({overflow: Scroll});
			for (b in shown) {
				var r = row(b);
				rows.push(r);
				s.append(r);
			}
			scroller = s;
		}
		scroller.style = scroller.style.with(part("markdown-scroll")).with({flexGrow: 1, minHeight: 0, alignItems: Center});
		append(scroller);
		if (virtual != null) virtual.reset(shown.length);
	}

	// another doc shown (the same text grown: a reply streamed): the rows of
	// the first blocks equal to the last doc's kept (their nodes, a selection
	// in them, the scroll), the rest made again; a long document's
	// (VirtualScroll) made again whole
	public function update(next:Doc) {
		doc = next;
		var old = shown;
		shown = options.blocks == null ? next.blocks : next.blocks.slice(0, options.blocks);
		anchors.clear();
		ids.resize(0);
		for (i in 0...shown.length)
			collectAnchors(shown[i], i);
		if (virtual != null) {
			virtual.reset(shown.length);
			return;
		}
		var k = 0;
		while (k < old.length && k < shown.length && same(old[k], shown[k]))
			k++;
		var holder = scroller ?? this;
		while (rows.length > k)
			holder.remove(rows.pop());
		for (i in k...shown.length) {
			var r = row(shown[i]);
			rows.push(r);
			holder.append(r);
		}
	}

	// (blocks and inlines alike: enums, arrays, a list item's fields, values)
	static function same(a:Dynamic, b:Dynamic):Bool {
		if (a == null || b == null) return a == b;
		if (Std.isOfType(a, String)) return Std.isOfType(b, String) && (a : String) == (b : String);
		if (Std.isOfType(a, Bool)) return Std.isOfType(b, Bool) && (a : Bool) == (b : Bool);
		if (Std.isOfType(a, Float)) return Std.isOfType(b, Float) && (a : Float) == (b : Float);
		if (Reflect.isEnumValue(a)) {
			if (!Reflect.isEnumValue(b) || Type.enumIndex(a) != Type.enumIndex(b)) return false;
			var pa = Type.enumParameters(a), pb = Type.enumParameters(b);
			for (i in 0...pa.length)
				if (!same(pa[i], pb[i])) return false;
			return true;
		}
		if (Std.isOfType(a, Array)) {
			var xa:Array<Dynamic> = a, xb:Array<Dynamic> = b;
			if (!Std.isOfType(b, Array) || xa.length != xb.length) return false;
			for (i in 0...xa.length)
				if (!same(xa[i], xb[i])) return false;
			return true;
		}
		var item:ListItem = a, other:ListItem = b;
		return same(item.task, other.task) && same(item.blocks, other.blocks);
	}

	// the heading with this id (a link's "#id", Markdown.slug's) brought to the view's top; false: none
	public function scrollToHeading(id:String):Bool {
		var i = anchors.get(id);
		if (i == null || scroller == null) return false;
		if (virtual != null) {
			virtual.scrollToIndex(i, "start");
			return true;
		}
		var r = rows[i];
		scroller.scrollY = Math.max(0, scroller.scrollY + r.rect().y - scroller.rect().y - scroller.used.paddingEdges.top);
		return true;
	}

	// the headings' ids, in order
	public function headings():Array<String>
		return ids.copy();

	function collectAnchors(b:Block, i:Int)
		switch b {
			case Heading(_, id, _):
				anchors.set(id, i);
				ids.push(id);
			case Quote(bs): for (c in bs) collectAnchors(c, i);
			case List(_, _, _, items): for (it in items) for (c in it.blocks) collectAnchors(c, i);
			case _:
		}

	function row(b:Block):Node {
		var r = node("markdown-row");
		r.append(block(b));
		return r;
	}

	// (a part's style: the plain look's, the look's part over it)
	function part(name:String):Style {
		var s = parts.get(name);
		if (s == null) parts.set(name, s = (BASE.get(name) ?? Style.none).with(look.part(name)));
		return s;
	}

	// (a node in the style of its part, its tag)
	function dress<T:Node>(n:T):T {
		n.style = n.style.with(part(n.tag));
		return n;
	}

	function node(part:String):Node
		return dress(new Node(part));

	// --- blocks

	function block(b:Block):Node
		return switch b {
			case Heading(level, _, content):
				var t = text(content, "markdown-h" + level);
				t.semantics = ({role: Heading, level: level} : Semantics);
				t;
			case Paragraph(content): paragraph(content);
			case List(ordered, start, tight, items): list(ordered, start, tight, items);
			case Quote(blocks): container("markdown-quote", blocks);
			case Code(info, text): code(info, text);
			case Table(align, head, rows): table(align, head, rows);
			case Rule:
				var n = node("markdown-rule");
				n.semantics = ({role: Separator} : Semantics);
				n;
			case Html(text): dress(new TextNode(text, "markdown-html"));
		}

	function container(part:String, blocks:Array<Block>):Node {
		var n = node(part);
		for (b in blocks)
			n.append(block(b));
		return n;
	}

	function list(ordered:Bool, start:Int, tight:Bool, items:Array<ListItem>):Node {
		var l = node("markdown-list");
		l.semantics = ({role: List} : Semantics);
		if (tight) l.style = l.style.with(part("markdown-list-tight"));
		listDepth++;
		for (k in 0...items.length) {
			var it = items[k];
			var item = node("markdown-item");
			item.style = item.style.with({flexDirection: Row});
			item.semantics = ({role: ListItem} : Semantics);
			if (it.task != null) {
				var box = node("markdown-task");
				box.setAttr("data-state", it.task ? "checked" : "unchecked");
				box.semantics = ({role: CheckBox, checked: it.task} : Semantics);
				box.style = box.style.with({flexShrink: 0, alignItems: Center, justifyContent: Center, userSelect: None});
				if (it.task) box.append(dress(new TextNode("✓", "markdown-task-mark")));
				item.append(box);
			} else {
				var marker = dress(new TextNode(ordered ? '${start + k}.' : BULLETS[(listDepth - 1) % BULLETS.length], "markdown-marker"));
				marker.style = marker.style.with({flexShrink: 0, userSelect: None});
				item.append(marker);
			}
			var body = container("markdown-item-body", it.blocks);
			body.style = body.style.with({flexGrow: 1, minWidth: 0});
			item.append(body);
			l.append(item);
		}
		listDepth--;
		return l;
	}

	static final BULLETS = ["•", "◦", "▪"];

	function code(info:String, text:String):Node {
		var box = node("markdown-code");
		var body = text.endsWith("\n") ? text.substr(0, text.length - 1) : text;
		var model = new CodeModel(body);
		model.readOnly = true;
		var lang = info.split(" ")[0].split("\t")[0].toLowerCase();
		if (lang != "") model.language = CodeLanguages.forPath("x." + (ALIASES.get(lang) ?? lang));
		var v = new CodeView(model);
		v.lineNumbers = false;
		v.indentGuides = false;
		v.currentLine = false;
		v.background = false;
		// (its text the document's selection's: no focus, no selection of its own)
		v.focusable = false;
		if (options.codeFont != null) v.fontFamily = options.codeFont;
		var size = options.codeSize ?? 13;
		v.fontSize = size;
		v.lineHeight = Math.round(size * 1.5);
		v.style = v.style.with({flexGrow: 0, height: model.lineCount * v.lineHeight});
		v.semantics = ({role: MultilineTextInput, label: lang == "" ? "Code" : lang} : Semantics);
		box.append(v);
		return box;
	}

	// (fence info words CodeLanguages knows by another name)
	static final ALIASES = ["haxe" => "hx", "typescript" => "ts", "javascript" => "js"];

	function table(align:Array<TableAlign>, head:Array<Array<Inline>>, rows:Array<Array<Array<Inline>>>):Node {
		// (wider than the column: scrolled sideways)
		var wrap = node("markdown-table-scroll");
		wrap.style = wrap.style.with({overflow: Scroll, alignItems: Start});
		var t = node("markdown-table");
		t.semantics = ({role: Table} : Semantics);
		t.style = t.style.with({display: Grid, gridTemplateColumns: [for (_ in 0...head.length) "auto"].join(" ")});
		function cell(content:Array<Inline>, part:String, k:Int) {
			var c = text(content, part);
			c.semantics = ({role: Cell} : Semantics);
			switch align[k] {
				case Left: c.style = c.style.with({textAlign: Left});
				case Center: c.style = c.style.with({textAlign: Center});
				case Right: c.style = c.style.with({textAlign: Right});
				case Auto:
			}
			t.append(c);
		}
		for (k in 0...head.length)
			cell(head[k], "markdown-th", k);
		for (r in rows)
			for (k in 0...r.length)
				cell(r[k], "markdown-td", k);
		wrap.append(t);
		return wrap;
	}

	// --- inlines

	// a paragraph: its text, or with images a wrapping row of its texts and images
	function paragraph(content:Array<Inline>):Node {
		if (!content.exists(hasImage)) return text(content, "markdown-p");
		var p = node("markdown-p");
		p.style = p.style.with({flexDirection: Row, flexWrap: true, alignItems: End});
		var run:Array<Inline> = [];
		function flush() {
			if (run.length > 0 && Markdown.plain(run).trim() != "") p.append(text(run, "markdown-p-text"));
			run = [];
		}
		for (i in content)
			switch i {
				case Image(src, alt, _):
					flush();
					p.append(image(src, alt, null));
				case Link(href, _, c) if (c.exists(hasImage)):
					flush();
					for (x in c)
						switch x {
							case Image(src, alt, _): p.append(image(src, alt, href));
							case _:
						}
				case _: run.push(i);
			}
		flush();
		return p;
	}

	static function hasImage(i:Inline):Bool
		return switch i {
			case Image(_, _, _): true;
			case Link(_, _, c): c.exists(hasImage);
			case _: false;
		}

	function image(src:String, alt:String, href:Null<String>):Node {
		if (textOnly && options.image != null) return new Node("markdown-image");
		var n = options.image == null ? null : options.image(src, alt);
		if (n == null) n = dress(new TextNode(alt == "" ? src : alt, "markdown-image-alt")) else n.style = n.style.with(part("markdown-image"));
		if (n.semantics == null) n.semantics = ({role: Image, label: alt} : Semantics);
		if (href != null) link(n, href);
		return n;
	}

	function link(n:Node, href:String) {
		n.style = n.style.with({cursor: Pointer});
		n.onClick = e -> if (options.onLink != null) options.onLink(href);
	}

	// a text node of inlines, its spans in their parts
	function text(content:Array<Inline>, part:String):TextNode {
		var t = dress(new TextNode("", part));
		spans(content, t);
		if (t.children.length == 0) t.text = "";
		return t;
	}

	function spans(content:Array<Inline>, into:Node)
		for (i in content) switch i {
			case Text(s): into.append(new TextNode(s));
			case SoftBreak: into.append(new TextNode(" "));
			case HardBreak: into.append(new TextNode("\n"));
			case Emphasis(c):
				var s = span(into, "markdown-em", c);
				s.style = s.style.with({fontStyle: Italic});
			case Strong(c):
				var s = span(into, "markdown-strong", c);
				s.style = s.style.with({fontWeight: 700});
			case Strike(c):
				var s = span(into, "markdown-del", c);
				s.style = s.style.with({textDecoration: helder.ui.TextDecoration.LineThrough});
			case CodeSpan(code): into.append(dress(new TextNode(code, "markdown-code-span")));
			case Link(href, _, c): link(span(into, linkPart(href), c), href);
			case Autolink(href, shown):
				var s = dress(new TextNode(shown, linkPart(href)));
				link(s, href);
				into.append(s);
			case Image(_, alt, _): into.append(dress(new TextNode(alt, "markdown-image-alt")));
			case Html(s): into.append(dress(new TextNode(s, "markdown-html")));
		}

	function linkPart(href:String):String
		return (options.linkPart == null ? null : options.linkPart(href)) ?? "markdown-link";

	function span(into:Node, part:String, content:Array<Inline>):TextNode {
		var s = dress(new TextNode("", part));
		spans(content, s);
		into.append(s);
		return s;
	}

	// (the plain look: a document in GitHub's proportions)
	static final BASE = [
		"markdown-scroll" => Style.of({padding: [24, 0]}),
		"markdown-row" => Style.of({width: "100%", maxWidth: 760, padding: [0, 24, 16, 24]}),
		"markdown-h1" => Style.of({fontSize: 30, fontWeight: 600, margin: [8, 0, 0, 0]}),
		"markdown-h2" => Style.of({fontSize: 23, fontWeight: 600, margin: [8, 0, 0, 0]}),
		"markdown-h3" => Style.of({fontSize: 19, fontWeight: 600, margin: [4, 0, 0, 0]}),
		"markdown-h4" => Style.of({fontSize: 16, fontWeight: 600}),
		"markdown-h5" => Style.of({fontSize: 14, fontWeight: 600}),
		"markdown-h6" => Style.of({fontSize: 13, fontWeight: 600, color: Color.rgb(0x59636E)}),
		"markdown-p" => Style.of({lineHeight: 1.5}),
		"markdown-quote" => Style.of({rowGap: 12, padding: [0, 0, 0, 14], borderWidth: [0, 0, 0, 3], borderColor: Color.rgb(0xD1D9E0), color: Color.rgb(0x59636E)}),
		"markdown-list" => Style.of({rowGap: 8}),
		"markdown-list-tight" => Style.of({rowGap: 2}),
		"markdown-item-body" => Style.of({rowGap: 8}),
		"markdown-marker" => Style.of({minWidth: 22, padding: [0, 6, 0, 0], lineHeight: 1.5}),
		"markdown-task" => Style.of({
			width: 14,
			height: 14,
			margin: [4, 8, 0, 0],
			borderRadius: 3,
			borderWidth: 1,
			borderColor: Color.rgb(0x818B98),
			fontSize: 10,
			checked: {background: Color.rgb(0x0969DA), borderColor: Color.rgb(0x0969DA), color: Color.rgb(0xFFFFFF)}
		}),
		"markdown-code" => Style.of({padding: [12, 12, 12, 0], borderRadius: 6, background: Color.rgb(0xF6F8FA)}),
		"markdown-code-span" => Style.of({fontFamily: "JetBrains Mono", fontSize: 13, background: Color.rgba(0x818B98, 0.15)}),
		"markdown-link" => Style.of({color: Color.rgb(0x0969DA), textDecoration: 1}),
		"markdown-table" => Style.of({borderWidth: [1, 0, 0, 1], borderColor: Color.rgb(0xD1D9E0)}),
		"markdown-th" => Style.of({fontWeight: 600, padding: [6, 12], borderWidth: [0, 1, 1, 0], borderColor: Color.rgb(0xD1D9E0)}),
		"markdown-td" => Style.of({padding: [6, 12], borderWidth: [0, 1, 1, 0], borderColor: Color.rgb(0xD1D9E0)}),
		"markdown-rule" => Style.of({height: 2, background: Color.rgb(0xD1D9E0)}),
		"markdown-html" => Style.of({fontFamily: "JetBrains Mono", fontSize: 13, color: Color.rgb(0x59636E)}),
		"markdown-image-alt" => Style.of({color: Color.rgb(0x59636E), fontStyle: Italic})
	];
}
