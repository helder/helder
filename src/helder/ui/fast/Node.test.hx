package helder.ui.fast;

import helder.css.CssCascade;
import helder.dom.Dom;
import helder.test.Test;
import helder.ui.box.Box;
import helder.ui.box.BoxTree;
import helder.ui.box.FontMatch;
import helder.ui.box.Fragments;
import helder.ui.flow.Space;

function tests() {
	describe("fast nodes", () -> {
		test("a style is interned, with() too", () -> {
			var a = Style.of({padding: 4, background: 0xFFFF0000});
			equals(Style.of({padding: 4, background: 0xFFFF0000}) == a, true);
			equals(a.with({padding: 8}) == Style.of({padding: 8, background: 0xFFFF0000}), true);
			equals(a == Style.of({padding: 5}), false);
			// (every field kept by with(): the text's too)
			var t = Style.of({cursor: Pointer, textDecoration: 2, textOverflow: Ellipsis, lineClamp: 2}).with({padding: 1}).props;
			equals(t.cursor, Pointer);
			equals(t.textDecoration, 2);
			equals(t.textOverflow, Ellipsis);
			equals(t.lineClamp, 2);
		});
		test("one resolution for a style in one state under one parent", () -> {
			var row = Style.of({padding: 4, hover: {background: 0xFF00FF00}});
			var list = new Node(), a = new Node(row), b = new Node(row);
			list.append(a);
			list.append(b);
			equals(a.box.style == b.box.style, true);
			a.state(Style.HOVER, true);
			equals(a.box.style == b.box.style, false);
			equals(a.box.style.backgroundColor, 0xFF00FF00);
			equals(b.box.style.backgroundColor, 0);
			// (a state it has no variant for: the same resolution)
			b.state(Style.SELECTED, true);
			equals(b.box.style == new Node(row).box.style, true);
			a.state(Style.HOVER, false);
			equals(a.box.style == b.box.style, true);
		});
		test("text inherits its parent's, a line height its multiple", () -> {
			var card = new Node(Style.of({color: 0xFF112233, fontSize: 20}));
			var t = new TextNode("Hi", Style.of({fontWeight: 600}));
			card.append(t);
			equals(t.box.style.text.colour, 0xFF112233);
			equals(t.box.style.text.size, 20);
			equals(t.box.style.text.height, 25);
			equals(t.box.style.text.weight, 600);
			// (nothing inherited said: the parent's text part itself)
			var plain = new Node(Style.of({padding: 2}));
			card.append(plain);
			equals(plain.box.style.text == card.box.style.text, true);
		});
		test("a token in its theme, light and dark", () -> {
			var app = new Theme(["surface" => [0xFFFFFFFF, 0xFF18181B]]);
			var root = new Node(), card = new Node(Style.of({background: Theme.token("surface"), borderColor: helder.ui.fast.Style.Tint.current, borderWidth: 1}));
			root.theme = app;
			root.append(card);
			equals(card.box.style.backgroundColor, 0xFFFFFFFF);
			root.theme = app.tone(true);
			equals(card.box.style.backgroundColor, 0xFF18181B);
			equals(@:privateAccess card.box.style.sideColors[0], 0xFF000000);
		});
		test("a group's states reach its descendants", () -> {
			var hint = Style.of({color: 0xFF777777, group: {hover: {color: 0xFF000000}}});
			var card = new Node(), inner = new Node(), t = new TextNode("Hint", hint);
			card.group = true;
			card.append(inner);
			inner.append(t);
			equals(t.box.style.text.colour, 0xFF777777);
			card.state(Style.HOVER, true);
			equals(t.box.style.text.colour, 0xFF000000);
			// (its own hover: not its group's)
			card.state(Style.HOVER, false);
			t.state(Style.HOVER, true);
			equals(t.box.style.text.colour, 0xFF777777);
		});
		test("display none: out of the box tree, back where it was", () -> {
			var list = new Node(), a = new TextNode("a"), b = new TextNode("b"), c = new TextNode("c");
			for (n in [a, b, c]) list.append(n);
			b.style = Style.of({display: None});
			equals(list.box.children().length, 2);
			b.style = Style.none;
			equals(list.box.children()[1] == b.box, true);
			b.remove();
			equals(list.children().length, 2);
			list.insert(b, a);
			equals(list.box.first == b.box, true);
		});
		test("in a window: hovered, pressed, its text laid out again", () -> {
			var ui = new helder.ui.Ui(null, 300, 200);
			var root = new Node(Style.of({padding: 10, fontFamily: "Ahem", fontSize: 10, lineHeight: 1}));
			var button = new Node(Style.of({padding: 5, background: 0xFF000001, hover: {background: 0xFF000002}, pressed: {background: 0xFF000003}}));
			var label = new TextNode("ab");
			var presses = 0;
			button.onPress = _ -> presses++;
			button.append(label);
			root.append(button);
			var tree = new Tree(root);
			tree.fonts.register(sys.io.File.getBytes("tests/flow/fixtures/Ahem.ttf"), "Ahem");
			tree.style.flexGrow = 1;
			ui.root.append(tree);
			ui.update();
			equals(tree.rectOf(label).join(","), "15,15,270,10");
			ui.pointerMove(20, 20);
			equals(button.box.style.backgroundColor, 0xFF000002);
			ui.pointerDown(20, 20, 0);
			equals(button.box.style.backgroundColor, 0xFF000003);
			ui.pointerUp(20, 20, 0);
			equals(presses, 1);
			equals(button.box.style.backgroundColor, 0xFF000002);
			ui.pointerMove(200, 150);
			equals(button.box.style.backgroundColor, 0xFF000001);
			// (a press let go off it: no press)
			ui.pointerDown(20, 20, 0);
			ui.pointerUp(200, 150, 0);
			equals(presses, 1);
			label.text = "ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab";
			ui.update();
			equals(tree.rectOf(label)[3] > 10, true);
		});
		test("a row laid out as the cascade's same row (app.css's)", () -> {
			var html = '<!doctype html><style>* { display: flex; flex-direction: column; position: relative; box-sizing: border-box; margin: 0;'
				+ ' flex: 0 1 auto } html, body { display: block } body { font: 10px/1 Ahem } #r { flex-direction: row; padding: 4px; column-gap: 6px;'
				+ ' width: 200px } p { display: block } #b { flex-grow: 1 }</style><div id=r><p>ab</p><p id=b>cde</p></div>';
			var doc = Dom.parse(html);
			var tree = BoxTree.build(doc, CssCascade.styles(doc), {contexts: helder.ui.flow.Contexts.all(), counters: s -> new helder.css.CssCounters(s)});
			var row:Null<Box> = null;
			var stack = [tree.root];
			while (stack.length > 0 && row == null) {
				var b = stack.pop();
				var n = BoxTree.nodeOf(b);
				if (n != null && n.nodeType == helder.dom.Node.ELEMENT_NODE && (cast n : helder.dom.Element).id == "r") row = b;
				var c = b.first;
				while (c != null) {
					stack.push(c);
					c = c.next;
				}
			}
			var fast = new Node(Style.of({fontFamily: "Ahem", fontSize: 10, lineHeight: 1}));
			var r = new Node(Style.of({flexDirection: Row, padding: 4, columnGap: 6, width: 200}));
			fast.append(r);
			r.append(new TextNode("ab"));
			r.append(new TextNode("cde", Style.of({flexGrow: 1})));
			var g = geometry(row);
			equals(g.split("\n").length >= 5, true);
			equals(geometry(r.box), g);
		});
	});
}

// (each box fragment's size and place under the row, laid out 300 wide)
private function geometry(row:Box):String {
	var fonts = new FontMatch();
	fonts.register(sys.io.File.getBytes("tests/flow/fixtures/Ahem.ttf"), "Ahem");
	var f = new Fragments(), all = helder.ui.flow.Contexts.all();
	var id = (row.context ?? all.flow).layout(row, new Space(f, fonts, 300, 200));
	var out = [];
	function walk(k:Int, x:Float, y:Float) {
		var ax = x + f.x(k), ay = y + f.y(k);
		if (f.kind(k) != Fragments.LINE) out.push('${f.kind(k)} $ax,$ay ${f.width(k)}x${f.height(k)}');
		var c = f.first(k);
		while (c >= 0) {
			walk(c, ax, ay);
			c = f.next(c);
		}
	}
	walk(id, -f.x(id), -f.y(id));
	return out.join("\n");
}
