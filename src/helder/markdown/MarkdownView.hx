package helder.markdown;

import helder.markdown.Doc;
import helder.ui.Node;
import helder.ui.Rules;
import helder.ui.TextNode;
import helder.ui.VirtualScroll;
import helder.ui.access.Role;
import helder.ui.access.Semantics;
import helder.ui.code.CodeLanguage.CodeLanguages;
import helder.ui.code.CodeModel;
import helder.ui.code.CodeView;

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
	?codeSize:Float
}

// A Markdown document (Markdown.parse's Doc) as nodes, unstyled: each part
// has a slot that the app's look styles (a Look's parts, a StyleSheet's
// rules; without a sheet the base rules here give a plain default). The
// top-level blocks are each in a row ("markdown-row": the column's width
// and the space between blocks), in a scroller ("markdown-scroll"), a
// VirtualScroll past VIRTUAL blocks (only the rows in view made). Slots:
// markdown-h1 to -h6, -p, -quote, -list (data-tight when tight),
// -item, -marker, -task (data-state checked or unchecked), -item-body,
// -code (a box around a read-only CodeView: the fence's language by its
// info string, CodeLanguages; plain text otherwise), -table, -th, -td,
// -rule, -html (raw HTML, as text), -image-alt; in text -em, -strong,
// -del, -code-span, -link. Links call onLink; images ask image for a node.
// It is one selectable scope (Node.selectable): a selection runs across
// its blocks, a long document's rows out of view too, copied with a blank
// line between blocks and a line between list items (markers not in it).
// Spacing between nested blocks is their container's row-gap (a quote's,
// an item body's, a list's).
class MarkdownView extends Node {
	public static inline var VIRTUAL = 300;

	public final doc:Doc;
	// the scroller (a VirtualScroll past VIRTUAL blocks; null with scroll false)
	public final scroller:Null<Node>;

	final props:MarkdownProps;
	final shown:Array<Block>;
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
		this.props = props;
		doc = props.doc;
		slot = "markdown";
		selectable = true;
		Rules.addBase("markdown", BASE);
		shown = props.blocks == null ? doc.blocks : doc.blocks.slice(0, props.blocks);
		for (i in 0...shown.length)
			collectAnchors(shown[i], i);
		style.minHeight = 0;
		style.minWidth = 0;
		if (props.scroll == false) {
			virtual = null;
			scroller = null;
			for (b in shown)
				append(row(b));
			return;
		}
		style.grow = 1;
		style.overflow = Hidden;
		if (shown.length > VIRTUAL) {
			var v = new VirtualScroll("markdown-scroll", 80);
			v.rowRole = null;
			v.focusableRows = false;
			v.semantics = null;
			// (a document's keys: the window's scrolling, not a list's focus moving)
			v.onKeyDown = null;
			v.onMakeRow = (i, r) -> {
				r.slot = "markdown-row";
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
			s.style.overflow = Scroll;
			for (b in shown) {
				var r = row(b);
				rows.push(r);
				s.append(r);
			}
			scroller = s;
		}
		scroller.slot = "markdown-scroll";
		scroller.style.grow = 1;
		scroller.style.minHeight = 0;
		scroller.style.alignItems = Center;
		append(scroller);
		if (virtual != null) virtual.reset(shown.length);
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
		scroller.scrollY = Math.max(0, scroller.scrollY + r.rect().y - scroller.rect().y - scroller.style.padding.top);
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
		var r = new Node("markdown-row");
		r.slot = "markdown-row";
		r.append(block(b));
		return r;
	}

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
			case Html(text):
				var t = new TextNode(text, "markdown-html");
				t.slot = "markdown-html";
				t;
		}

	function container(slot:String, blocks:Array<Block>):Node {
		var n = node(slot);
		for (b in blocks)
			n.append(block(b));
		return n;
	}

	static function node(slot:String):Node {
		var n = new Node(slot);
		n.slot = slot;
		return n;
	}

	function list(ordered:Bool, start:Int, tight:Bool, items:Array<ListItem>):Node {
		var l = node("markdown-list");
		l.semantics = ({role: List} : Semantics);
		if (tight) l.setAttr("data-tight", "");
		listDepth++;
		for (k in 0...items.length) {
			var it = items[k];
			var item = node("markdown-item");
			item.style.direction = Row;
			item.semantics = ({role: ListItem} : Semantics);
			if (it.task != null) {
				var box = node("markdown-task");
				box.setAttr("data-state", it.task ? "checked" : "unchecked");
				box.semantics = ({role: CheckBox, checked: it.task} : Semantics);
				box.style.shrink = 0;
				box.style.alignItems = Center;
				box.style.justify = Center;
				box.style.userSelect = None;
				if (it.task) box.append(new TextNode("✓", "markdown-task-mark"));
				item.append(box);
			} else {
				var marker = new TextNode(ordered ? '${start + k}.' : BULLETS[(listDepth - 1) % BULLETS.length], "markdown-marker");
				marker.slot = "markdown-marker";
				marker.style.shrink = 0;
				marker.style.userSelect = None;
				item.append(marker);
			}
			var body = container("markdown-item-body", it.blocks);
			body.style.grow = 1;
			body.style.minWidth = 0;
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
		if (props.codeFont != null) v.fontFamily = props.codeFont;
		var size = props.codeSize ?? 13;
		v.fontSize = size;
		v.lineHeight = Math.round(size * 1.5);
		v.style.grow = 0;
		v.style.height = model.lineCount * v.lineHeight;
		v.semantics = ({role: MultilineTextInput, label: lang == "" ? "Code" : lang} : Semantics);
		box.append(v);
		return box;
	}

	// (fence info words CodeLanguages knows by another name)
	static final ALIASES = ["haxe" => "hx", "typescript" => "ts", "javascript" => "js"];

	function table(align:Array<TableAlign>, head:Array<Array<Inline>>, rows:Array<Array<Array<Inline>>>):Node {
		// (wider than the column: scrolled sideways)
		var wrap = node("markdown-table-scroll");
		wrap.style.overflowX = Scroll;
		wrap.style.alignItems = Start;
		var t = node("markdown-table");
		t.semantics = ({role: Table} : Semantics);
		t.style.display = Grid;
		t.style.gridTemplateColumns = [for (_ in 0...head.length) helder.ui.Grid.Track.AUTO];
		function cell(content:Array<Inline>, slot:String, k:Int) {
			var c = text(content, slot);
			c.semantics = ({role: Cell} : Semantics);
			switch align[k] {
				case Left: c.style.textAlign = Left;
				case Center: c.style.textAlign = Center;
				case Right: c.style.textAlign = Right;
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
		p.style.direction = Row;
		p.style.wrap = true;
		p.style.alignItems = End;
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
		if (textOnly && props.image != null) return new Node("markdown-image");
		var n = props.image == null ? null : props.image(src, alt);
		if (n == null) {
			var t = new TextNode(alt == "" ? src : alt, "markdown-image-alt");
			t.slot = "markdown-image-alt";
			n = t;
		} else if (n.slot == null) n.slot = "markdown-image";
		if (n.semantics == null) n.semantics = ({role: Image, label: alt} : Semantics);
		if (href != null) link(n, href);
		return n;
	}

	function link(n:Node, href:String) {
		n.style.cursor = Pointer;
		n.onClick = e -> if (props.onLink != null) props.onLink(href);
	}

	// a text node of inlines, its spans in their slots
	function text(content:Array<Inline>, slot:String):TextNode {
		var t = new TextNode("", slot);
		t.slot = slot;
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
				s.style.italic = true;
			case Strong(c):
				var s = span(into, "markdown-strong", c);
				s.style.fontWeight = 700;
			case Strike(c):
				var s = span(into, "markdown-del", c);
				s.style.textDecoration = helder.ui.TextDecoration.LineThrough;
			case CodeSpan(code):
				var s = new TextNode(code, "markdown-code-span");
				s.slot = "markdown-code-span";
				into.append(s);
			case Link(href, _, c): link(span(into, "markdown-link", c), href);
			case Autolink(href, shown):
				var s = new TextNode(shown, "markdown-link");
				s.slot = "markdown-link";
				link(s, href);
				into.append(s);
			case Image(_, alt, _):
				var s = new TextNode(alt, "markdown-image-alt");
				s.slot = "markdown-image-alt";
				into.append(s);
			case Html(s):
				var h = new TextNode(s, "markdown-html");
				h.slot = "markdown-html";
				into.append(h);
		}

	function span(into:Node, slot:String, content:Array<Inline>):TextNode {
		var s = new TextNode("", slot);
		s.slot = slot;
		spans(content, s);
		into.append(s);
		return s;
	}

	// (the look without a sheet: a plain document, GitHub's proportions)
	static final BASE:Array<helder.ui.Rule> = [
		{slot: "markdown-scroll", style: {padding: [24, 0]}},
		{slot: "markdown-row", style: {width: "100%", maxWidth: 760, padding: [0, 24, 16, 24]}},
		{slot: "markdown-h1", style: {fontSize: 30, fontWeight: 600, marginTop: 8}},
		{slot: "markdown-h2", style: {fontSize: 23, fontWeight: 600, marginTop: 8}},
		{slot: "markdown-h3", style: {fontSize: 19, fontWeight: 600, marginTop: 4}},
		{slot: "markdown-h4", style: {fontSize: 16, fontWeight: 600}},
		{slot: "markdown-h5", style: {fontSize: 14, fontWeight: 600}},
		{slot: "markdown-h6", style: {fontSize: 13, fontWeight: 600, color: helder.ui.Color.rgb(0x59636E)}},
		{slot: "markdown-p", style: {lineHeight: 1.5}},
		{slot: "markdown-quote", style: {rowGap: 12, padding: [0, 0, 0, 14], borders: [0, 0, 0, 3], borderColor: helder.ui.Color.rgb(0xD1D9E0),
			color: helder.ui.Color.rgb(0x59636E)}},
		{slot: "markdown-list", style: {rowGap: 8}},
		{slot: "markdown-list", when: ["data-tight"], style: {rowGap: 2}},
		{slot: "markdown-item-body", style: {rowGap: 8}},
		{slot: "markdown-marker", style: {minWidth: 22, paddingRight: 6, lineHeight: 1.5}},
		{slot: "markdown-task", style: {width: 14, height: 14, margin: [4, 8, 0, 0], radius: 3, borderWidth: 1, borderColor: helder.ui.Color.rgb(0x818B98),
			fontSize: 10}},
		{slot: "markdown-task", when: ["data-state=checked"], style: {background: helder.ui.Color.rgb(0x0969DA), borderColor: helder.ui.Color.rgb(0x0969DA),
			color: helder.ui.Color.rgb(0xFFFFFF)}},
		{slot: "markdown-code", style: {padding: [12, 12, 12, 0], radius: 6, background: helder.ui.Color.rgb(0xF6F8FA)}},
		{slot: "markdown-code-span", style: {fontFamily: "JetBrains Mono", fontSize: 13, background: helder.ui.Color.rgba(0x818B98, 0.15)}},
		{slot: "markdown-link", style: {color: helder.ui.Color.rgb(0x0969DA), textDecoration: 1}},
		{slot: "markdown-table", style: {borders: [1, 0, 0, 1], borderColor: helder.ui.Color.rgb(0xD1D9E0)}},
		{slot: "markdown-th", style: {fontWeight: 600, padding: [6, 12], borders: [0, 1, 1, 0], borderColor: helder.ui.Color.rgb(0xD1D9E0)}},
		{slot: "markdown-td", style: {padding: [6, 12], borders: [0, 1, 1, 0], borderColor: helder.ui.Color.rgb(0xD1D9E0)}},
		{slot: "markdown-rule", style: {height: 2, background: helder.ui.Color.rgb(0xD1D9E0)}},
		{slot: "markdown-html", style: {fontFamily: "JetBrains Mono", fontSize: 13, color: helder.ui.Color.rgb(0x59636E)}},
		{slot: "markdown-image-alt", style: {color: helder.ui.Color.rgb(0x59636E), italic: true}}
	];
}
