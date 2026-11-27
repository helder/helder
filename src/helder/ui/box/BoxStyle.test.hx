package helder.ui.box;

import helder.css.CssCascade;
import helder.dom.Dom;
import helder.test.Test;
import helder.ui.flow.Space;

// A box's style made from code, no computed style behind it: what its
// fields aren't set to CSS's initial values, laid out as the cascade's
// style of the same declarations is.
function tests() {
	describe("BoxStyle", () -> {
		test("made from code, a flex row laid out as the cascade's same row", () -> {
			var html = '<!doctype html><style>body { margin: 0; font: 10px/1 Ahem } #r { display: flex; padding: 4px; column-gap: 6px; width: 200px }'
				+ ' p { margin: 0 } #b { flex-grow: 1 }</style><div id=r><p>ab</p><p id=b>cde</p></div>';
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
			var made = code();
			equals(made.style.css == null, true);
			var g = geometry(row);
			equals(g.split("\n").length >= 5, true);
			equals(geometry(made), g);
		});
		test("z-index at a 32-bit integer's least: a value, not auto", () -> {
			var doc = Dom.parse('<!doctype html><div style="position: absolute; z-index: -2147483649"></div>');
			var tree = BoxTree.build(doc, CssCascade.styles(doc), {contexts: helder.ui.flow.Contexts.all(), counters: s -> new helder.css.CssCounters(s)});
			var div = tree.root.first.first;
			equals(div.style.zIndex(), -2147483648);
			equals(div.style.stacking(), true);
		});
	});
}

// (the row of the HTML above made from code: a flex container's style, its items' and their text's)
private function code():Box {
	var text = new helder.ui.flow.InlineBasicStyle();
	text.families = ["Ahem"];
	text.size = 10;
	text.height = 10;
	function style(inner:Int):BoxStyle {
		var s = new BoxStyle();
		s.displayRead = true;
		s.displayInner = inner;
		s.textPart = text;
		return s;
	}
	var r = style(BoxStyle.FLEX);
	for (_ in 0...4) {
		r.margin.push(Px(0));
		r.padding.push(Px(4));
		r.border.push(0);
	}
	r.width = Px(200);
	r.columnGapValue = Px(6);
	var row = made(r);
	for (t in ["ab", "cde"]) {
		var s = style(BoxStyle.FLOW);
		if (t == "cde") s.growValue = 1;
		var p = made(s), run = made(s, Text);
		run.text = t;
		p.append(run);
		row.append(p);
	}
	return row;
}

private function made(s:BoxStyle, kind:BoxKind = Block):Box {
	var b = new Box(kind == Block && s.inner == BoxStyle.FLEX ? Container : kind, s);
	b.flags |= Box.MADE;
	if (b.container) b.context = helder.ui.flow.Contexts.all().of(s.inner, _ -> {});
	return b;
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
