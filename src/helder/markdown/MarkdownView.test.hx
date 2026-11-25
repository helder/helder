package helder.markdown;

import helder.test.Test;
import helder.ui.ImageNode;
import helder.ui.Node;
import helder.ui.TextNode;
import helder.ui.Ui;
import helder.ui.VirtualScroll;
import helder.ui.code.CodeView;
import helder.markdown.MarkdownView.MarkdownProps;

// MarkdownView headless: each block in its slot, a link's press, images
// asked for and their alt text without one, a long document's rows made in
// part and a heading scrolled to, spans in spans drawn once (by their
// text: Ui.drawNode), the first blocks alone without a scroller
function tests() {
	function slots(n:Node, out:Array<String>):Array<String> {
		if (n.slot != null && n.slot != "markdown-row") out.push(n.slot);
		for (c in n.children)
			slots(c, out);
		return out;
	}
	function view(text:String, ?props:Dynamic):{ui:Ui, view:MarkdownView} {
		var ui = new Ui(new helder.ui.draw.DrawText(), 600, 400);
		var p:MarkdownProps = {doc: Markdown.parse(text)};
		if (props != null) for (f in Reflect.fields(props)) Reflect.setField(p, f, Reflect.field(props, f));
		var v = new MarkdownView(p);
		ui.root.append(v);
		ui.update();
		return {ui: ui, view: v};
	}
	describe("MarkdownView", () -> {
		test("blocks in their slots", () -> {
			var v = view("# Title\n\nSome *text* and `code`.\n\n- [x] one\n- two\n\n> quoted\n\n```ts\nlet a = 1\n```\n\n| a | b |\n|---|--:|\n| 1 | 2 |\n\n---\n").view;
			equals(slots(v, []), [
				"markdown", "markdown-scroll", "markdown-h1", "markdown-p", "markdown-em", "markdown-code-span", "markdown-list", "markdown-item", "markdown-task",
				"markdown-item-body", "markdown-p", "markdown-item", "markdown-marker", "markdown-item-body", "markdown-p", "markdown-quote", "markdown-p",
				"markdown-code", "markdown-table-scroll", "markdown-table", "markdown-th", "markdown-th", "markdown-td", "markdown-td", "markdown-rule"
			]);
			var code:CodeView = cast v.find("code-view");
			equals(code.model.text(), "let a = 1");
			equals(code.model.language?.name(), "typescript");
			assert(code.model.readOnly);
			equals(v.headings(), ["title"]);
		});
		test("a link's press", () -> {
			var pressed = [];
			var t = view("[elsewhere](other.md)\n", {onLink: (h:String) -> pressed.push(h)});
			var p = t.view.find("markdown-p");
			var r = p.rect();
			t.ui.pointerDown(r.x + 4, r.y + 4, 1);
			t.ui.pointerUp(r.x + 4, r.y + 4, 1);
			equals(pressed, ["other.md"]);
		});
		test("images asked for, their alt text without one", () -> {
			var asked = [];
			var v = view("![a cat](cat.png) ![a dog](dog.png)\n", {
				image: (src:String, alt:String) -> {
					asked.push(src);
					src == "cat.png" ? new ImageNode() : null;
				}
			}).view;
			equals(asked, ["cat.png", "dog.png"]);
			equals(v.find("markdown-image")?.slot, null);
			equals(slots(v, []), ["markdown", "markdown-scroll", "markdown-p", "markdown-image", "markdown-image-alt"]);
			equals((cast v.find("markdown-image-alt") : TextNode).text, "a dog");
		});
		test("a long document: its rows made in part, a heading scrolled to", () -> {
			var text = [for (k in 0...1000) k == 800 ? "## Far down" : 'Paragraph $k.'].join("\n\n");
			var t = view(text);
			var list:VirtualScroll = cast t.view.scroller;
			equals(list.count, 1000);
			assert(list.end - list.first < 100);
			assert(t.view.scrollToHeading("far-down"));
			t.ui.update();
			assert(list.first <= 800 && list.end > 800);
			assert(!t.view.scrollToHeading("missing"));
		});
		test("nested spans drawn once, by their text", () -> {
			var t = view("a **b [c *d*](x)** e\n");
			var texts = new Texts();
			t.ui.paint(texts);
			equals(texts.count, 1);
		});
		test("the first blocks alone, without a scroller", () -> {
			var v = view("# A\n\nb\n\nc\n\nd\n", {scroll: false, blocks: 2}).view;
			equals(v.scroller, null);
			equals(slots(v, []), ["markdown", "markdown-h1", "markdown-p"]);
		});
	});
}

// (a canvas counting the texts drawn)
private class Texts implements helder.ui.Canvas {
	public var count = 0;

	public function new() {}

	public function translate(dx:Float, dy:Float) {}

	public function pushClip(x:Float, y:Float, w:Float, h:Float, radius:Float, ?corners:helder.ui.Corners) {}

	public function popClip() {}

	public function pushOpacity(alpha:Float) {}

	public function pushGroup(a:Float, x:Float, y:Float, w:Float, h:Float) {}

	public function popOpacity() {}

	public function pushTransform(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float) {}

	public function popTransform() {}

	public function rect(x:Float, y:Float, w:Float, h:Float, radius:Float, fill:helder.ui.Color, borderWidth:Float, border:helder.ui.Color,
		?corners:helder.ui.Corners, ?sides:helder.ui.Edges, style:helder.ui.BorderStyle = Solid) {}

	public function shadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:helder.ui.Color, blur:Float, ?corners:helder.ui.Corners,
		?offset:Array<Float>) {}

	public function insetShadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:helder.ui.Color, blur:Float, dx:Float, dy:Float, spread:Float,
		?corners:helder.ui.Corners) {}

	public function path(p:helder.ui.Path, fill:Null<helder.ui.Paint>, ?stroke:helder.ui.Stroke) {}

	public function image(img:helder.image.Image, x:Float, y:Float, w:Float, h:Float, u0:Float, v0:Float, u1:Float, v1:Float, radius:Float,
		?corners:helder.ui.Corners) {}

	public function text(p:helder.ui.Paragraph, x:Float, y:Float, width:Float, align:helder.ui.TextAlign, color:helder.ui.Color, ?colors:Array<helder.ui.Color>)
		count++;

	public function textShadow(p:helder.ui.Paragraph, x:Float, y:Float, width:Float, align:helder.ui.TextAlign, color:helder.ui.Color, blur:Float,
		?colors:Array<helder.ui.Color>) {}
}
