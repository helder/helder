package helder.ui.box;

import helder.css.CssCascade;
import helder.dom.Dom;
import helder.test.Gen;
import helder.test.Test;

using StringTools;

// The box tree: displays, anonymous blocks around inline runs (white
// space alone dropped), inline boxes split around blocks, none and
// contents, generated content and counters, markers, replaced elements.
// Then properties: a block container's children are all block-level or
// all inline-level, and the text runs keep the document's text in order.
function tests() {
	describe("BoxTree", () -> {
		test("displays and anonymous blocks", () -> {
			equals(tree('<div>a<p>b</p> <span>c</span></div>'), [
				"Block html", "  Block body", "    Block div", "      Block", '        Text "a"', "      Block p", '        Text "b"', "      Block",
				'        Text " "', "        Inline span", '          Text "c"'
			].join("\n"));
			// (white space alone between blocks: no anonymous block)
			equals(tree('<div>\n  <p>a</p>\n  <p>b</p>\n</div>').split("\n").filter(l -> l.trim() == "Block").length, 0);
		});
		test("none and contents", () -> {
			equals(tree('<div style="display:none">x</div><div style="display:contents"><i>y</i></div>'), [
				"Block html", "  Block body", "    Inline i", '      Text "y"'
			].join("\n"));
		});
		test("an inline box split around a block", () -> {
			var t = build('<span id=s>a<div>b</div>c</span>');
			var body = t.root.first;
			var kids = body.children();
			equals(kids.length, 3);
			equals(kids[1].kind, Block);
			var first = kids[0].first, last = kids[2].first;
			equals(first.kind, Inline);
			equals(first.flags & (Box.NO_START | Box.NO_END), Box.NO_END);
			equals(last.flags & (Box.NO_START | Box.NO_END), Box.NO_START);
			equals(kids[1].first.kind, Text);
		});
		test("inline blocks, replaced elements, containers", () -> {
			var t = build('<span style="display:inline-block">a</span><img src=x.png><div style="display:flex">b</div><br>', url -> new helder.canvas.Bitmap(3, 4));
			var kinds = [for (b in t.root.first.children()) [for (c in b.children()) c.kind.toString()]];
			equals(Std.string(kinds), "[[InlineBlock,InlineReplaced],[Text],[Break]]");
			equals(t.root.first.children()[1].kind, Container);
			equals(t.root.first.first.last.image.height, 4);
			equals(t.pending.length, 1);
		});
		test("generated content: strings, attr(), counters, quotes", () -> {
			var t = build('<style>ol { counter-reset: n } li { counter-increment: n } li::before { content: counter(n, upper-roman) "." attr(id) } q::before { content: open-quote } q::after { content: close-quote }</style><ol><li id=a>x</li><li id=b>y</li></ol><q>z</q>');
			var texts = [];
			function walk(b:Box) {
				if (b.kind == Inline && b.pseudo == "before") texts.push([for (c in b.children()) c.text].join(""));
				for (c in b.children()) walk(c);
			}
			walk(t.root);
			equals(texts, ["I.a", "II.b", "“"]);
		});
		test("list markers", () -> {
			var t = build('<ol><li>a</li><li style="list-style-position:inside">b</li></ol><ul><li>c</li></ul>');
			var markers = [];
			function walk(b:Box) {
				if (b.pseudo == "marker" && b.kind == Inline) markers.push(b.first.text + (b.flags & Box.OUTSIDE != 0 ? " outside" : ""));
				for (c in b.children()) walk(c);
			}
			walk(t.root);
			equals(markers, ["1.  outside", "2. ", "•  outside"]);
		});
		test("boxes of one computed style share their BoxStyle and InlineStyle", () -> {
			var t = build('<p><a>x</a> <a>y</a> <a style="color:red">z</a></p>');
			var as = t.root.first.first.children().filter(b -> b.kind == Inline);
			equals(as.length, 3);
			assert(as[0].style == as[1].style);
			assert(as[0].style != as[2].style);
			assert(BoxInline.of(as[0], 100) == BoxInline.of(as[1], 100));
			assert(BoxInline.of(as[0], 100) != BoxInline.of(as[0], 200));
		});
		test("counter styles", () -> {
			equals(Counters.text("lower-roman", 14), "xiv");
			equals(Counters.text("upper-alpha", 28), "AB");
			equals(Counters.text("decimal-leading-zero", 7), "07");
			equals(Counters.marker("square", 1), "▪ ");
		});
		test("a block container's children are all block-level or all inline-level", () -> property(MARKUP, html -> {
			var t = build(html);
			function walk(b:Box) {
				var kids = b.children();
				if (b.container && kids.length > 0) {
					var blocks = kids.filter(k -> k.blockLevel).length;
					assert(blocks == 0 || blocks == kids.length, '$b: ${kids.length} children, $blocks blocks');
				}
				for (k in kids) walk(k);
			}
			walk(t.root);
		}, {cases: 200}));
		test("the text runs are the document's text, in order", () -> property(MARKUP, html -> {
			var doc = Dom.parse('<!doctype html><body>$html');
			var t = BoxTree.build(doc, CssCascade.styles(doc));
			var text = new StringBuf();
			function walk(b:Box) {
				if (b.kind == Text && b.pseudo == null) text.add(b.text);
				for (c in b.children()) walk(c);
			}
			walk(t.root);
			// (white space alone between blocks is dropped)
			equals(squash(text.toString()), squash(shown(doc.body)));
		}, {cases: 200}));
	});
}

// (the text of what is displayed: display: none's left out)
private function shown(n:helder.dom.Node):String {
	if (n.nodeType == helder.dom.Node.TEXT_NODE) return (cast n : helder.dom.Text).data;
	if (n.nodeType == helder.dom.Node.ELEMENT_NODE && ((cast n : helder.dom.Element).getAttribute("style") ?? "").indexOf("none") >= 0) return "";
	var out = "", c = n.firstChild;
	while (c != null) {
		out += shown(c);
		c = c.nextSibling;
	}
	return out;
}

private function squash(s:String):String
	return ~/\s+/g.replace(s, "");

private function build(body:String, ?image:String->Null<helder.canvas.Bitmap>):BoxTree {
	var doc = Dom.parse('<!doctype html><body>$body');
	return BoxTree.build(doc, CssCascade.styles(doc), {image: image});
}

private function tree(body:String):String
	return StringTools.trim(build(body).dump());

// (nested blocks, inlines, inline blocks, text and white space)
private final MARKUP:Gen<String> = c -> {
	function node(depth:Int):String {
		var kind = c.draw(int(0, depth > 3 ? 1 : 5));
		return switch kind {
			case 0: c.draw(pick(["a", "b c", " ", "\n  ", "x "]));
			case 1: "<br>";
			case _:
				var tag = c.draw(pick(["div", "span", "p", "b", "em"]));
				var style = c.draw(pick(["", " style=\"display:inline-block\"", " style=\"display:block\"", " style=\"display:contents\"", " style=\"display:none\""]));
				var n = c.draw(int(0, 3));
				'<$tag$style>' + [for (_ in 0...n) node(depth + 1)].join("") + '</$tag>';
		}
	}
	[for (_ in 0...c.draw(int(1, 4))) node(0)].join("");
};
