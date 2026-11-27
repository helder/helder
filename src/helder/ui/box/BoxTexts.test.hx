package helder.ui.box;

import helder.css.CssCascade;
import helder.dom.Dom;
import helder.test.Test;
import helder.ui.box.BoxTexts.BoxPosition;
import helder.ui.flow.Space;

// One box tree's text by position: boxes made from code and a document's
// boxes (an island) in the same tree, a selection running across them
// either way, its text and its rectangles; a point's position back.
function tests() {
	describe("BoxTexts", () -> {
		test("a selection from boxes made from code into a document's boxes and back", () -> {
			var t = mixed();
			var fastBefore = textOf(t.root.first), island = textOf(t.root.first.next), fastAfter = textOf(t.root.last);
			equals([fastBefore.text, island.text, fastAfter.text], ["fast before", "island text", "fast after"]);
			// (into the island, then out of it: either way round)
			var a:BoxPosition = {box: fastBefore, offset: 5}, b:BoxPosition = {box: island, offset: 6};
			equals(BoxTexts.text(a, b), "beforeisland");
			equals(BoxTexts.text(b, a), "beforeisland");
			var c:BoxPosition = {box: island, offset: 7}, d:BoxPosition = {box: fastAfter, offset: 4};
			equals(BoxTexts.text(c, d), "textfast");
			equals(BoxTexts.text(a, d), "beforeisland textfast");
			// (the lines of each block it crosses: the fast block's, the island's paragraph's, the fast one after)
			var texts = new BoxTexts(t.fragments, t.root);
			equals(texts.blocks.length, 3);
			equals(texts.rects(a, d).length, 3);
			equals(texts.rects(d, a).length, 3);
			// (a point back to its position, in each tree's boxes)
			for (p in [a, b, d]) {
				var at = texts.caret(p);
				var back = texts.position(at.x + 0.5, at.y + at.height / 2);
				equals([back.box == p.box, back.offset == p.offset], [true, true]);
			}
		});
	});
}

// (blocks made from code around a document's boxes: html's box appended as a block among them)
private function mixed():{root:Box, fragments:Fragments} {
	var doc = Dom.parse('<!doctype html><style>html, body, p { margin: 0; font: 10px/1 Ahem }</style><p>island text</p>');
	var tree = BoxTree.build(doc, CssCascade.styles(doc), {contexts: helder.ui.flow.Contexts.all(), counters: s -> new helder.css.CssCounters(s)});
	var s = tree.root.style;
	function made(kind:BoxKind, ?text:String):Box {
		var b = new Box(kind, s);
		b.flags |= Box.MADE;
		if (text != null) b.text = text;
		return b;
	}
	function block(text:String):Box {
		var b = made(Block);
		b.append(made(Text, text));
		return b;
	}
	var root = made(Block);
	root.append(block("fast before"));
	root.append(tree.root);
	root.append(block("fast after"));
	var fonts = new FontMatch();
	fonts.register(sys.io.File.getBytes("tests/flow/fixtures/Ahem.ttf"), "Ahem");
	var f = new Fragments();
	var id = helder.ui.flow.Contexts.all().flow.layout(root, new Space(f, fonts, 300, 200));
	f.moveTo(id, 0, 0);
	return {root: root, fragments: f};
}

// (the first text box in a box)
private function textOf(b:Box):Box {
	var stack = [b];
	while (stack.length > 0) {
		var x = stack.shift();
		if (x.kind == Text) return x;
		var c = x.first;
		while (c != null) {
			stack.push(c);
			c = c.next;
		}
	}
	throw "no text";
}
