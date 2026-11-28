package helder.ui.fast;

import helder.css.CssCascade;
import helder.css.CssTerm;
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
		test("paint fields resolved: corners, a dashed border, shadows first on top, an outline", () -> {
			var line = new Token<helder.gfx.Color>("line"), theme = new Theme(["line" => 0xFF101010], ["line" => 0xFF202020]);
			var n = new Node(Style.of({
				borderWidth: 1,
				borderStyle: Dashed,
				borderRadius: [1, 2, 3, 4],
				shadows: [{x: 1, y: 2, color: 0xFF0000FF}, {x: 0, y: 0, spread: 1, color: line, inset: true}],
				outline: {width: 2, color: 0xFF00FF00, offset: 3}
			}));
			n.theme = theme;
			var s = n.box.style;
			equals(s.borderStyle(0), "dashed");
			equals([for (t in s.radii) switch t {
				case Dimension(v, _): v;
				case _: -1.0;
			}].join(","), "1,1,2,2,3,3,4,4");
			equals(s.shadows.length, 2);
			equals(s.shadows[0].color, 0xFF0000FF);
			equals(s.shadows[0].lengths.join(","), "1,2,0,0");
			equals(s.shadows[1].inset, true);
			equals(s.shadows[1].color, 0xFF101010);
			equals(s.outlineStyle, "solid");
			equals(s.outlineWidth, 2.0);
			equals(s.outlineOffset, 3.0);
			equals(s.outlineColor, 0xFF00FF00);
		});
		test("markup's paint attributes: corners as CSS writes them, a border style's word", () -> {
			var p = new Style.Props();
			Attrs.set(p, "borderRadius", "4 0");
			Attrs.set(p, "borderStyle", "dotted");
			equals((p.borderRadius : Array<Float>).join(","), "4,0,4,0");
			equals(p.borderStyle, Dotted);
		});
		test("pointerEvents inherited: None through its descendants, an Auto one found again", () -> {
			var a = new Node(Style.of({pointerEvents: None})), b = new Node(), c = new Node(Style.of({pointerEvents: Auto}));
			a.append(b);
			b.append(c);
			equals(a.box.style.rare.pointerEvents, "none");
			equals(b.box.style.rare.pointerEvents, "none");
			equals(c.box.style.rare.pointerEvents, "auto");
			a.style = Style.none;
			equals(b.box.style.rare.pointerEvents, "auto");
		});
		test("direction, figures' forms (inherited), an aspect ratio", () -> {
			var a = new Node(Style.of({direction: Rtl, fontVariantNumeric: "tabular-nums slashed-zero"})), b = new Node(Style.of({aspectRatio: 2}));
			a.append(b);
			equals(a.box.style.rtl, true);
			equals(b.box.style.rtl, true);
			equals([for (f in b.box.style.text.features) f.tag].join(","), "tnum,zero");
			equals(b.box.style.model().ratio, 2.0);
			var p = new Style.Props();
			Attrs.set(p, "aspectRatio", "16 / 8");
			equals(p.aspectRatio, 2.0);
		});
		test("styles made of ever new values: interning and resolutions bounded", () -> {
			for (i in 0...Style.BOUND * 2 + 10) new Node(Style.ofProps({width: i}));
			equals(@:privateAccess Style.internedCount <= Style.BOUND, true);
			equals(@:privateAccess Resolve.cached <= Style.BOUND, true);
			// (a style made again after a clear: equal, and resolved alike)
			var a = Style.of({padding: 3});
			for (i in 0...Style.BOUND) Style.ofProps({width: i + 0.5});
			equals(Style.of({padding: 3}).props.padding, a.props.padding);
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
			var surface = new Token<helder.gfx.Color>("surface"), app = new Theme(["surface" => 0xFFFFFFFF], ["surface" => 0xFF18181B]);
			var root = new Node(), card = new Node(Style.of({background: surface, borderColor: helder.ui.fast.Style.Tint.current, borderWidth: 1}));
			root.theme = app;
			root.append(card);
			equals(card.box.style.backgroundColor, 0xFFFFFFFF);
			root.theme = app.tone(true);
			equals(card.box.style.backgroundColor, 0xFF18181B);
			equals(@:privateAccess card.box.style.sideColors[0], 0xFF000000);
		});
		test("length tokens: a box's padding, gap, radius and font size in its theme, laid out again where they change", () -> {
			var pad = new Token<Token.Length>("pad"), size = new Token<Token.Length>("size");
			var app = new Theme(["pad" => 8, "size" => 13], new Map());
			var root = new Node(), card = new Node(Style.of({padding: pad, rowGap: pad, borderRadius: pad, fontSize: size}));
			root.theme = app;
			root.append(card);
			var s = card.box.style.model();
			equals(s.padding[0], (Px(8) : helder.ui.box.Len));
			equals(card.box.style.text.size, 13.0);
			var before = card.box.style;
			root.theme = app.with(pad, 12);
			equals(card.box.style.model().padding[0], (Px(12) : helder.ui.box.Len));
			equals(Resolve.level(before, card.box.style), Resolve.LAYOUT);
			// (in a list's literal, beside px)
			equals((Style.of({padding: [4, pad]}).props.padding : Array<Float>)[0], 4.0);
		});
		test("a theme changed: a style that reads no token keeps its resolution", () -> {
			var surface = new Token<helder.gfx.Color>("surface"), app = new Theme(["surface" => 0xFFFFFFFF], ["surface" => 0xFF18181B]);
			var root = new Node(), plain = new Node(Style.of({padding: 3})), card = new Node(Style.of({background: surface}));
			root.append(plain);
			root.append(card);
			var p = plain.box.style, c = card.box.style;
			root.theme = app.tone(true);
			equals(plain.box.style == p, true);
			equals(card.box.style == c, false);
			equals(Style.of({padding: 3}).themed, false);
			equals(Style.of({background: surface}).themed, true);
			equals(Style.of({dark: {padding: 1}}).themed, true);
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
