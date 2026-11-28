package helder.ui;

import helder.gfx.Color;
import helder.test.Test;
import helder.ui.box.Len;

// A node's style: interned, resolved (Node.used) in its states, its
// group's, its theme's tokens, under what it inherits, once for each of
// those; markup's attributes over it.
function tests() {
	describe("Style", () -> {
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
		test("with(): a variant merged, nested ones too", () -> {
			var s = Style.of({hover: {background: 0xFF000001}, selected: {hover: {color: 0xFF000002}}});
			var w = s.with({hover: {opacity: 0.5}, selected: {padding: 2}});
			equals(w.props.hover.background, s.props.hover.background);
			equals(w.props.hover.opacity, 0.5);
			equals(w.props.selected.padding, Style.of({padding: 2}).props.padding);
			equals(w.props.selected.hover.color, s.props.selected.hover.color);
		});
		test("paint fields resolved: corners, a dashed border, shadows first on top, an outline", () -> {
			var line = new Token<Color>("line"), theme = new Theme(["line" => 0xFF101010], ["line" => 0xFF202020]);
			var n = node(Style.of({
				borderWidth: 1,
				borderStyle: Dashed,
				borderRadius: [1, 2, 3, 4],
				shadows: [{x: 1, y: 2, color: 0xFF0000FF}, {x: 0, y: 0, spread: 1, color: line, inset: true}],
				outline: {width: 2, color: 0xFF00FF00, offset: 3}
			}));
			n.theme = theme;
			var s = n.used;
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
		test("markup's attributes: corners as CSS writes them, a border style's word, flex, inset, auto margins", () -> {
			var p = new Style.Props();
			Attrs.set(p, "borderRadius", "4 0");
			Attrs.set(p, "borderStyle", "dotted");
			Attrs.set(p, "flex", "2 0 40px");
			Attrs.set(p, "inset", "1 2");
			Attrs.set(p, "margin", "0 auto");
			equals((p.borderRadius : Array<Float>).join(","), "4,0,4,0");
			equals(p.borderStyle, Dotted);
			equals([p.flexGrow, p.flexShrink], [2.0, 0.0]);
			equals([(p.top : Len), p.right, p.bottom, p.left], [Px(1), Px(2), Px(1), Px(2)]);
			equals(Math.isNaN((p.margin : Array<Float>)[1]), true);
			// (over a node's style, the style itself kept)
			var n = node(Style.of({padding: 3}));
			equals(n.styleAttr("opacity", 0.5), true);
			equals(n.styleAttr("nothing", 1), false);
			equals(n.used.opacity, 0.5);
			equals(n.used.paddingPx(0), 3.0);
			equals(n.style == Style.of({padding: 3}), true);
		});
		test("pointerEvents inherited: None through its descendants, an Auto one found again", () -> {
			var a = node(Style.of({pointerEvents: None})), b = new Node(), c = node(Style.of({pointerEvents: Auto}));
			a.append(b);
			b.append(c);
			equals(a.used.rare.pointerEvents, "none");
			equals(b.used.rare.pointerEvents, "none");
			equals(c.used.rare.pointerEvents, "auto");
			a.style = Style.none;
			equals(b.used.rare.pointerEvents, "auto");
		});
		test("direction, figures' forms (inherited), an aspect ratio", () -> {
			var a = node(Style.of({direction: Rtl, fontVariantNumeric: "tabular-nums slashed-zero"})), b = node(Style.of({aspectRatio: 2}));
			a.append(b);
			equals(a.used.rtl, true);
			equals(b.used.rtl, true);
			equals([for (f in b.used.text.features) f.tag].join(","), "tnum,zero");
			equals(b.used.model().ratio, 2.0);
			var p = new Style.Props();
			Attrs.set(p, "aspectRatio", "16 / 8");
			equals(p.aspectRatio, 2.0);
		});
		test("styles made of ever new values: interning and resolutions bounded", () -> {
			for (i in 0...Style.BOUND * 2 + 10) node(Style.ofProps({width: i}));
			equals(@:privateAccess Style.internedCount <= Style.BOUND, true);
			equals(@:privateAccess Resolve.cached <= Style.BOUND, true);
			// (a style made again after a clear: equal, and resolved alike)
			var a = Style.of({padding: 3});
			for (i in 0...Style.BOUND) Style.ofProps({width: i + 0.5});
			equals(Style.of({padding: 3}).props.padding, a.props.padding);
		});
		test("one resolution for a style in one state under one parent", () -> {
			var row = Style.of({padding: 4, hover: {background: 0xFF00FF00}});
			var list = new Node(), a = node(row), b = node(row);
			list.append(a);
			list.append(b);
			equals(a.used == b.used, true);
			a.state(Style.HOVER, true);
			equals(a.used == b.used, false);
			equals(a.used.backgroundColor, 0xFF00FF00);
			equals(b.used.backgroundColor, 0);
			// (a state it has no variant for: the same resolution)
			b.state(Style.SELECTED, true);
			equals(b.used == node(row).used, true);
			a.state(Style.HOVER, false);
			equals(a.used == b.used, true);
		});
		test("a variant in a variant: selected, then hovered while selected", () -> {
			var n = node(Style.of({background: 0xFF000001, selected: {background: 0xFF000002, hover: {background: 0xFF000003}}}));
			n.state(Style.HOVER, true);
			equals(n.used.backgroundColor, 0xFF000001);
			n.state(Style.SELECTED, true);
			equals(n.used.backgroundColor, 0xFF000003);
			n.state(Style.HOVER, false);
			equals(n.used.backgroundColor, 0xFF000002);
		});
		test("text inherits its parent's, a line height its multiple", () -> {
			var card = node(Style.of({color: 0xFF112233, fontSize: 20}));
			var t = new TextNode("Hi");
			t.style = Style.of({fontWeight: 600});
			card.append(t);
			equals(t.used.text.colour, 0xFF112233);
			equals(t.used.text.size, 20);
			equals(t.used.text.height, 25);
			equals(t.used.text.weight, 600);
			// (nothing inherited said: the parent's text part itself)
			var plain = node(Style.of({padding: 2}));
			card.append(plain);
			equals(plain.used.text == card.used.text, true);
		});
		test("a token in its theme, light and dark", () -> {
			var surface = new Token<Color>("surface"), app = new Theme(["surface" => 0xFFFFFFFF], ["surface" => 0xFF18181B]);
			var root = new Node(), card = node(Style.of({background: surface, borderColor: Style.Tint.current, borderWidth: 1}));
			root.theme = app;
			root.append(card);
			equals(card.used.backgroundColor, 0xFFFFFFFF);
			root.theme = app.tone(true);
			equals(card.used.backgroundColor, 0xFF18181B);
			equals(card.used.borderColor(0), 0xFF000000);
		});
		test("length tokens: a box's padding, gap, radius and font size in its theme", () -> {
			var pad = new Token<Token.Length>("pad"), size = new Token<Token.Length>("size");
			var app = new Theme(["pad" => 8, "size" => 13], new Map());
			var root = new Node(), card = node(Style.of({padding: pad, rowGap: pad, borderRadius: pad, fontSize: size}));
			root.theme = app;
			root.append(card);
			equals(card.used.model().padding[0], Px(8));
			equals(card.used.text.size, 13.0);
			var before = card.used;
			root.theme = app.with(pad, 12);
			equals(card.used.model().padding[0], Px(12));
			equals(Resolve.level(before, card.used), Resolve.LAYOUT);
			// (in a list's literal, beside px)
			equals((Style.of({padding: [4, pad]}).props.padding : Array<Float>)[0], 4.0);
		});
		test("a theme changed: a style that reads no token keeps its resolution", () -> {
			var surface = new Token<Color>("surface"), app = new Theme(["surface" => 0xFFFFFFFF], ["surface" => 0xFF18181B]);
			var root = new Node(), plain = node(Style.of({padding: 3})), card = node(Style.of({background: surface}));
			root.append(plain);
			root.append(card);
			var p = plain.used, c = card.used;
			root.theme = app.tone(true);
			equals(plain.used == p, true);
			equals(card.used == c, false);
			equals(Style.of({padding: 3}).themed, false);
			equals(Style.of({background: surface}).themed, true);
			equals(Style.of({dark: {padding: 1}}).themed, true);
		});
		test("a group's states reach its descendants", () -> {
			var card = new Node(), inner = new Node(), t = new TextNode("Hint");
			t.style = Style.of({color: 0xFF777777, group: {hover: {color: 0xFF000000}}});
			card.group = true;
			card.append(inner);
			inner.append(t);
			equals(t.used.text.colour, 0xFF777777);
			card.state(Style.HOVER, true);
			equals(t.used.text.colour, 0xFF000000);
			// (its own hover: not its group's)
			card.state(Style.HOVER, false);
			t.state(Style.HOVER, true);
			equals(t.used.text.colour, 0xFF777777);
		});
		test("a group in a group's variant: checked, then hovered while checked", () -> {
			var root = new Node(), knob = node(Style.of({background: 0xFF000001, group: {checked: {background: 0xFF000002, group: {hover: {background: 0xFF000003}}}}}));
			root.group = true;
			root.append(knob);
			root.state(Style.HOVER, true);
			equals(knob.used.backgroundColor, 0xFF000001);
			root.state(Style.CHECKED, true);
			equals(knob.used.backgroundColor, 0xFF000003);
			root.state(Style.HOVER, false);
			equals(knob.used.backgroundColor, 0xFF000002);
		});
		test("display none: no place in the layout, back where it was", () -> {
			var ui = new Ui(null, 200, 200);
			var a = node(Style.of({height: 10})), b = node(Style.of({height: 20})), c = node(Style.of({height: 30}));
			for (n in [a, b, c]) ui.root.append(n);
			b.style = b.style.with({display: None});
			ui.update();
			equals(b.used.none, true);
			equals(c.y, 10.0);
			b.style = Style.of({height: 20});
			ui.update();
			equals(c.y, 30.0);
		});
		test("in a window: hovered, pressed", () -> {
			var ui = new Ui(null, 300, 200);
			var button = node(Style.of({width: 50, height: 20, background: 0xFF000001, hover: {background: 0xFF000002}, pressed: {background: 0xFF000003}}));
			var presses = 0;
			button.onPress = _ -> presses++;
			ui.root.append(button);
			ui.update();
			ui.pointerMove(10, 10);
			equals(button.used.backgroundColor, 0xFF000002);
			ui.pointerDown(10, 10, 0);
			equals(button.used.backgroundColor, 0xFF000003);
			ui.pointerUp(10, 10, 0);
			equals(presses, 1);
			equals(button.used.backgroundColor, 0xFF000002);
			ui.pointerMove(200, 150);
			equals(button.used.backgroundColor, 0xFF000001);
		});
	});
}

private function node(s:Style):Node {
	var n = new Node();
	n.style = s;
	return n;
}
