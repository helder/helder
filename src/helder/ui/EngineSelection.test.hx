package helder.ui;

import helder.os.Mods;
import helder.test.Test;

// Text selection headless, on the CSS engine's text (EngineText; TextSelection.test.hx: DrawText's): in a
// paragraph (a span's hit on a centred line, a double click on a space, a
// drag past the text, a drag from a link), and across a selectable view's
// texts (a drag, Shift, a double and a triple click, Mod+A and whose
// focus it takes, Shift and the arrows, a scroller stepped past its edge)
function tests() {
	var time = 0.0;
	beforeEach(() -> {
		time += 10;
		Ui.now = () -> time;
		helder.ui.actions.Keymap.mac = false;
	});
	afterEach(() -> Ui.now = haxe.Timer.stamp);
	function window(w = 400.0, h = 300.0):Ui {
		var ui = new Ui(new EngineText(), w, h);
		ui.root.style.alignItems = Start;
		return ui;
	}
	function para(texts:Array<String>):TextNode {
		var t = new TextNode();
		for (s in texts)
			t.append(new TextNode(s));
		return t;
	}
	// (where character i of a paragraph is drawn: its run's x, the middle of its line; f: how far into it)
	function at(t:TextNode, i:Int, f = 0.5):{x:Float, y:Float} {
		var p = t.laidOut(), b = t.windowBounds(), r = p.selection(i, i + 1)[0], c = p.caret(i);
		var lx = t.textAlign() == Center ? (t.width - p.lineWidth(r.y)) / 2 : 0.0;
		return {x: b.x + lx + r.x + r.width * f, y: b.y + c.y + c.height / 2};
	}
	function drag(ui:Ui, from:{x:Float, y:Float}, to:{x:Float, y:Float}, mods = 0) {
		@:privateAccess ui.mods = mods;
		ui.pointerDown(from.x, from.y, 1);
		ui.pointerMove(to.x, to.y);
		ui.pointerUp(to.x, to.y, 1);
		@:privateAccess ui.mods = 0;
	}
	function click(ui:Ui, p:{x:Float, y:Float}, mods = 0)
		drag(ui, p, p, mods);

	describe("in a paragraph", () -> {
		test("a span's hit on a centred line", () -> {
			var ui = window();
			var t = para(["left ", "link"]), pressed = 0;
			t.selectable = true;
			t.style.width = 300;
			t.style.textAlign = Center;
			t.children[1].onClick = _ -> pressed++;
			ui.root.append(t);
			ui.update();
			var last = at(t, 8, 0.75), before = at(t, 4, 0.75);
			assert(t.hitTest(last.x, last.y) == t.children[1]);
			assert(t.hitTest(before.x, before.y) == t.children[0]);
			click(ui, last);
			equals(pressed, 1);
		});
		test("a double click on a space, the space", () -> {
			var ui = window();
			var t = new TextNode("hello world");
			t.selectable = true;
			ui.root.append(t);
			ui.update();
			var space = at(t, 5, 0.75);
			click(ui, space);
			time += 0.2;
			click(ui, space);
			equals(ui.selectedText(), " ");
		});
		test("a drag below the text, to its end; above it, to its start", () -> {
			var ui = window();
			ui.root.style.padding = 40;
			var t = new TextNode("hello world");
			t.selectable = true;
			ui.root.append(t);
			ui.update();
			var b = t.windowBounds(), mid = at(t, 5, 0);
			drag(ui, mid, {x: b.x + 1, y: b.y + b.height + 20});
			equals(ui.selectedText(), " world");
			time += 1;
			drag(ui, mid, {x: b.x + b.width - 1, y: b.y - 20});
			equals(ui.selectedText(), "hello");
		});
		test("a drag from a link selects its text, not following it", () -> {
			var ui = window();
			var t = para(["see ", "the link here"]), pressed = 0;
			t.selectable = true;
			t.children[1].onClick = _ -> pressed++;
			ui.root.append(t);
			ui.update();
			drag(ui, at(t, 4, 0), at(t, 11, 0));
			equals(ui.selectedText(), "the lin");
			equals(pressed, 0);
			click(ui, at(t, 6));
			equals(pressed, 1);
		});
	});

	describe("across a selectable view", () -> {
		// (a column of texts in a selectable view)
		function doc(ui:Ui, texts:Array<String>):{view:Node, texts:Array<TextNode>} {
			var v = new Node("doc");
			v.selectable = true;
			v.style.rowGap = 10;
			var ts = [for (s in texts) new TextNode(s)];
			for (t in ts)
				v.append(t);
			ui.root.append(v);
			ui.update();
			return {view: v, texts: ts};
		}
		test("a drag from one text into the next: both drawn with it, copied with a blank line", () -> {
			var ui = window();
			var d = doc(ui, ["hello world", "foo bar", "baz"]);
			drag(ui, at(d.texts[0], 6, 0), at(d.texts[1], 3, 0));
			equals(ui.selectedText(), "world\n\nfoo");
			var s = ui.textSelection;
			equals(s.rangeIn(d.texts[0], 11), {start: 6, end: 11});
			equals(s.rangeIn(d.texts[1], 7), {start: 0, end: 3});
			equals(s.rangeIn(d.texts[2], 3), null);
			ui.keyDown("c".code, Mods.CONTROL);
			var copied = "";
			ui.clipboard.read(t -> copied = t);
			equals(copied, "world\n\nfoo");
			// (back up past the anchor: from the first's start)
			drag(ui, at(d.texts[1], 3, 0), {x: 1, y: 1});
			equals(ui.selectedText(), "hello world\n\nfoo");
		});
		test("a press between texts: at the nearest; past the last, its end", () -> {
			var ui = window();
			var d = doc(ui, ["hello world", "foo bar"]);
			var a = d.texts[0].windowBounds(), b = d.texts[1].windowBounds();
			// (the gap between them: the end of the one above)
			drag(ui, at(d.texts[0], 6, 0), {x: b.x + 2, y: (a.y + a.height + b.y) / 2});
			equals(ui.selectedText(), "world");
			time += 1;
			drag(ui, at(d.texts[0], 6, 0), {x: b.x + 2, y: 280});
			equals(ui.selectedText(), "world\n\nfoo bar");
		});
		test("Shift extends it, a double click selects a word and a drag after it words", () -> {
			var ui = window();
			var d = doc(ui, ["hello world", "foo bar baz"]);
			click(ui, at(d.texts[0], 2, 0));
			time += 1;
			click(ui, at(d.texts[1], 5, 0), Mods.SHIFT);
			equals(ui.selectedText(), "llo world\n\nfoo b");
			time += 1;
			var w = at(d.texts[1], 5);
			ui.pointerDown(w.x, w.y, 1);
			ui.pointerUp(w.x, w.y, 1);
			time += 0.2;
			ui.pointerDown(w.x, w.y, 1);
			equals(ui.selectedText(), "bar");
			var to = at(d.texts[1], 9);
			ui.pointerMove(to.x, to.y);
			ui.pointerUp(to.x, to.y, 1);
			equals(ui.selectedText(), "bar baz");
			time += 0.2;
			click(ui, w);
			equals(ui.selectedText(), "foo bar baz");
		});
		test("Mod+A: all of the scope its press left the focus in, not where the focus moved", () -> {
			var ui = window();
			var d = doc(ui, ["one", "two"]);
			var field = new Node("field");
			field.focusable = true;
			field.style.set({width: 40, height: 20});
			ui.root.append(field);
			ui.update();
			ui.keyDown("a".code, Mods.CONTROL);
			equals(ui.textSelection, null);
			click(ui, at(d.texts[0], 1));
			ui.keyDown("a".code, Mods.CONTROL);
			equals(ui.selectedText(), "one\n\ntwo");
			field.focus();
			ui.keyDown("a".code, Mods.CONTROL);
			equals(ui.selectedText(), "one\n\ntwo");
			ui.selectText(null);
			ui.keyDown("a".code, Mods.CONTROL);
			equals(ui.textSelection, null);
		});
		test("a press on a control in it, a button's label or a field, selects nothing", () -> {
			var ui = window();
			var d = doc(ui, ["hello world"]);
			var button = new Node("button"), pressed = 0;
			button.focusable = true;
			button.onClick = _ -> pressed++;
			var label = new TextNode("Press");
			button.append(label);
			var field = new helder.ui.controls.TextField();
			field.style.width = 100;
			field.text = "typed";
			d.view.append(button);
			d.view.append(field);
			ui.update();
			drag(ui, at(label, 0, 0), at(label, 4, 0));
			equals(ui.textSelection, null);
			equals(pressed, 1);
			var b = field.windowBounds();
			drag(ui, {x: b.x + 2, y: b.y + b.height / 2}, {x: b.x + 30, y: b.y + b.height / 2});
			equals(ui.textSelection, null);
			ui.keyDown("a".code, Mods.CONTROL);
			equals(ui.selectedText(), "");
			assert(field.selectionEnd > field.selectionStart);
		});
		test("Shift and the arrows: a character, on into the next text, a line", () -> {
			var ui = window();
			var d = doc(ui, ["ab", "ab"]);
			click(ui, at(d.texts[0], 1, 0));
			ui.keyDown(Key.RIGHT, Mods.SHIFT);
			equals(ui.selectedText(), "b");
			ui.keyDown(Key.RIGHT, Mods.SHIFT);
			ui.keyDown(Key.RIGHT, Mods.SHIFT);
			equals(ui.selectedText(), "b\n\na");
			ui.keyDown(Key.LEFT, Mods.SHIFT);
			ui.keyDown(Key.LEFT, Mods.SHIFT);
			equals(ui.selectedText(), "b");
			ui.keyDown(Key.DOWN, Mods.SHIFT);
			equals(ui.selectedText(), "b\n\nab");
			ui.keyDown(Key.UP, Mods.SHIFT);
			equals(ui.selectedText(), "b");
		});
		test("a drag past a scroller's edge scrolls it, the selection with it", () -> {
			var ui = window(400, 200);
			var s = new Node("scroller");
			s.style.set({height: 100, width: 300});
			s.style.overflow = Scroll;
			var v = new Node("doc");
			v.selectable = true;
			v.style.flexShrink = 0;
			var ts = [for (k in 0...20) new TextNode('line $k')];
			for (t in ts)
				v.append(t);
			s.append(v);
			ui.root.append(s);
			ui.update();
			var from = at(ts[0], 0, 0);
			ui.pointerDown(from.x, from.y, 1);
			ui.pointerMove(from.x, 150);
			var t = Clock.now;
			for (k in 1...30) {
				Clock.tick(t + k / 60);
				ui.update();
			}
			assert(s.scrollY > 50);
			ui.pointerUp(from.x, 150, 1);
			var text = ui.selectedText();
			assert(StringTools.startsWith(text, "line 0\n\nline 1\n\n"));
			assert(text.split("\n\n").length > 5);
			var y = s.scrollY;
			Clock.tick(t + 1);
			equals(s.scrollY, y);
		});
	});
}
