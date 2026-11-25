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
// text: Ui.drawNode), the first blocks alone without a scroller; its text
// selected as one document (a drag across paragraphs, a list and a code
// block, copied; a table's cells; a word and a line in the code; a long
// document's rows let go and made again under it, all of it copied)
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
		// (where index i of a text is, in the window: its caret's middle)
		function point(n:Node, i:Int):{x:Float, y:Float} {
			var c = n.selectableCaret(i);
			return {x: c.x + 0.5, y: c.y + c.height / 2};
		}
		function all(n:Node, slot:String, out:Array<Node>):Array<Node> {
			if (n.slot == slot) out.push(n);
			for (c in n.children)
				all(c, slot, out);
			return out;
		}
		// (Mod: Command on a Mac, Control elsewhere)
		function mod():Int
			return helder.ui.actions.Keymap.mac ? helder.os.Mods.META : helder.os.Mods.CONTROL;
		function drag(ui:Ui, a:{x:Float, y:Float}, b:{x:Float, y:Float}) {
			ui.pointerDown(a.x, a.y, 1);
			ui.pointerMove(b.x, b.y);
			ui.pointerUp(b.x, b.y, 1);
		}
		test("a drag across paragraphs, a list and a code block: one selection, copied", () -> {
			var t = view("# Title\n\nFirst para.\n\n- one\n- two\n\n```\ncode line\n```\n\nLast one.\n");
			var ps = all(t.view, "markdown-p", []);
			drag(t.ui, point(ps[0], 0), point(ps[3], 2));
			equals(t.ui.selectedText(), "First para.\n\none\ntwo\n\ncode line\n\nLa");
			var code:CodeView = cast t.view.find("code-view");
			equals(t.ui.textSelection.rangeIn(code, code.model.length), {start: 0, end: 9});
			equals(code.model.primary.empty(), true);
			// (a marker is not in it, the cursor over text the text's)
			assert(t.ui.textSelection.rangeIn(t.view.find("markdown-marker"), 1) == null);
			t.ui.pointerMove(point(ps[0], 2).x, point(ps[0], 2).y);
			equals(t.ui.cursor(), helder.ui.Cursor.Text);
		});
		test("a table's cells: a tab between, a line after a row", () -> {
			var t = view("| a | b |\n|---|---|\n| 1 | 2 |\n\nafter\n");
			var c = all(t.view, "markdown-th", []);
			t.ui.pointerDown(point(c[0], 0).x, point(c[0], 0).y, 1);
			t.ui.pointerUp(point(c[0], 0).x, point(c[0], 0).y, 1);
			t.ui.keyDown("a".code, mod());
			equals(t.ui.selectedText(), "a\tb\n1\t2\n\nafter");
		});
		test("a link's click still follows it; a drag from it selects", () -> {
			var pressed = [];
			var t = view("go [elsewhere now](other.md)\n", {onLink: (h:String) -> pressed.push(h)});
			var p = t.view.find("markdown-p");
			drag(t.ui, point(p, 4), point(p, 9));
			equals(t.ui.selectedText(), "lsewh");
			equals(pressed, []);
			helder.ui.Ui.now = () -> 100.0;
			drag(t.ui, point(p, 5), point(p, 5));
			helder.ui.Ui.now = haxe.Timer.stamp;
			equals(pressed, ["other.md"]);
		});
		test("a long document: rows let go and made again under the selection, all of it copied", () -> {
			var text = [for (k in 0...1000) 'Paragraph $k.'].join("\n\n");
			var t = view(text);
			var list:VirtualScroll = cast t.view.scroller;
			list.keep = 0;
			var first = all(t.view, "markdown-p", [])[2];
			t.ui.pointerDown(point(first, 0).x, point(first, 0).y, 1);
			t.ui.pointerUp(point(first, 0).x, point(first, 0).y, 1);
			list.scrollToIndex(500, "start");
			t.ui.update();
			var far:Null<Node> = null;
			for (p in all(t.view, "markdown-p", []))
				if ((cast p : TextNode).allText() == "Paragraph 500.") far = p;
			@:privateAccess t.ui.mods = helder.os.Mods.SHIFT;
			t.ui.pointerDown(point(far, 4).x, point(far, 4).y, 1);
			t.ui.pointerUp(point(far, 4).x, point(far, 4).y, 1);
			@:privateAccess t.ui.mods = 0;
			var copied = t.ui.selectedText().split("\n\n");
			equals(copied.length, 499);
			equals(copied[0], "Paragraph 2.");
			equals(copied[1], "Paragraph 3.");
			equals(copied[498], "Para");
			assert(list.dropped > 0);
			list.scrollToIndex(0, "start");
			t.ui.update();
			var again = all(t.view, "markdown-p", [])[2];
			assert(again != first);
			equals(t.ui.textSelection.rangeIn(again, 13), {start: 0, end: 13});
			t.ui.keyDown("a".code, mod());
			var whole = t.ui.selectedText();
			assert(StringTools.startsWith(whole, "Paragraph 0.\n\nParagraph 1.\n\n"));
			assert(StringTools.endsWith(whole, "Paragraph 998.\n\nParagraph 999."));
		});
		test("a reply streamed: the blocks before the last kept, the last made again", () -> {
			var t = view("# Title\n\nFirst para.\n\nSec", {scroll: false});
			var h = t.view.find("markdown-h1"), first = all(t.view, "markdown-p", [])[0];
			drag(t.ui, point(first, 0), point(first, 5));
			t.view.update(Markdown.parse("# Title\n\nFirst para.\n\nSecond one.\n\nThird"));
			t.ui.update();
			var ps = all(t.view, "markdown-p", []);
			assert(t.view.find("markdown-h1") == h);
			assert(ps[0] == first);
			equals([for (p in ps) (cast p : TextNode).allText()], ["First para.", "Second one.", "Third"]);
			equals(t.ui.selectedText(), "First");
			equals(t.view.headings(), ["title"]);
		});
		test("in a scroller: kept the same, the scroll too", () -> {
			var t = view([for (k in 0...40) 'Paragraph $k.'].join("\n\n"));
			var first = all(t.view, "markdown-p", [])[0];
			t.view.scroller.scrollY = 120;
			t.view.update(Markdown.parse([for (k in 0...41) 'Paragraph $k.'].join("\n\n")));
			t.ui.update();
			assert(all(t.view, "markdown-p", [])[0] == first);
			equals(all(t.view, "markdown-p", []).length, 41);
			equals(t.view.scroller.scrollY, 120.0);
		});
		test("an open fence streamed, then closed", () -> {
			var t = view("Intro.\n\n```ts\nlet a", {scroll: false});
			var intro = t.view.find("markdown-p");
			var code:CodeView = cast t.view.find("code-view");
			equals(code.model.text(), "let a");
			t.view.update(Markdown.parse("Intro.\n\n```ts\nlet a = 1\n```\n\nAfter."));
			t.ui.update();
			code = cast t.view.find("code-view");
			equals(code.model.text(), "let a = 1");
			equals(code.model.language?.name(), "typescript");
			var ps = all(t.view, "markdown-p", []);
			assert(ps[0] == intro);
			equals((cast ps[1] : TextNode).allText(), "After.");
		});
		test("a list growing item by item", () -> {
			var t = view("Steps:\n\n- one", {scroll: false});
			var lead = t.view.find("markdown-p");
			for (text in ["Steps:\n\n- one\n- tw", "Steps:\n\n- one\n- two\n- three"])
				t.view.update(Markdown.parse(text));
			t.ui.update();
			assert(t.view.find("markdown-p") == lead);
			equals([for (i in all(t.view, "markdown-item", [])) (cast i.find("markdown-p") : TextNode).allText()], ["one", "two", "three"]);
			equals(all(t.view, "markdown-list", []).length, 1);
		});
		test("a link's slot by its href", () -> {
			var v = view("[Pond](studio:screen/Pond) and [web](https://x.y)\n", {linkSlot: (h:String) -> StringTools.startsWith(h, "studio:") ? "chip" : null}).view;
			equals(slots(v, []), ["markdown", "markdown-scroll", "markdown-p", "chip", "markdown-link"]);
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

	public function rect(x:Float, y:Float, w:Float, h:Float, radius:Float, fill:helder.gfx.Color, borderWidth:Float, border:helder.gfx.Color,
		?corners:helder.ui.Corners, ?sides:helder.ui.Edges, style:helder.ui.BorderStyle = Solid) {}

	public function shadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:helder.gfx.Color, blur:Float, ?corners:helder.ui.Corners,
		?offset:Array<Float>) {}

	public function insetShadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:helder.gfx.Color, blur:Float, dx:Float, dy:Float, spread:Float,
		?corners:helder.ui.Corners) {}

	public function path(p:helder.ui.Path, fill:Null<helder.ui.Paint>, ?stroke:helder.ui.Stroke) {}

	public function image(img:helder.image.Image, x:Float, y:Float, w:Float, h:Float, u0:Float, v0:Float, u1:Float, v1:Float, radius:Float,
		?corners:helder.ui.Corners) {}

	public function text(p:helder.ui.Paragraph, x:Float, y:Float, width:Float, align:helder.ui.TextAlign, color:helder.gfx.Color, ?colors:Array<helder.gfx.Color>)
		count++;

	public function textShadow(p:helder.ui.Paragraph, x:Float, y:Float, width:Float, align:helder.ui.TextAlign, color:helder.gfx.Color, blur:Float,
		?colors:Array<helder.gfx.Color>) {}
}
