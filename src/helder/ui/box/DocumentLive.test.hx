package helder.ui.box;

import helder.dom.Dom;
import helder.dom.Element;
import helder.dom.ElementState;
import helder.dom.Text;
import helder.test.Test;

// A live document (DocumentView.watch, update): what each change redoes by
// its properties' impact (a colour repainted, a width laid out again, a
// display the box tree made again, a text changed in place, children
// inserted the tree made again).
function tests() {
	describe("DocumentView live", () -> {
		test("a hover's colour repaints", () -> {
			var v = live('<style>a:hover { color: #f00 } a { color: #00f }</style><a id=a href=x>link</a> after');
			var a = el(v, "a");
			a.setState(ElementState.HOVER, true);
			equals(v.update(), DocumentView.PAINT);
			equals(v.boxesOf(a)[0].style.color("color"), 0xFFFF0000);
			// (its text's run: the element's style)
			equals(v.boxesOf(a.firstChild)[0].style.color("color"), 0xFFFF0000);
			a.setState(ElementState.HOVER, false);
			equals(v.update(), DocumentView.PAINT);
			equals(v.boxesOf(a.firstChild)[0].style.color("color"), 0xFF0000FF);
			equals(v.update(), DocumentView.NOTHING);
		});
		test("an inherited colour reaches the children", () -> {
			var v = live('<style>div:hover { color: #0f0 }</style><div id=d><p id=p>x</p></div>');
			el(v, "d").setState(ElementState.HOVER, true);
			equals(v.update(), DocumentView.PAINT);
			equals(v.boxesOf(el(v, "p"))[0].style.color("color"), 0xFF00FF00);
		});
		test("a width lays out again as a fresh layout does", () -> {
			var html = '<style>body { margin: 0; font: 10px/1 Ahem } .w { width: 50px } #b:hover { width: 120px }</style><div id=a class=w>aa aa</div><div id=b class=w>bb bb bb</div><p>after</p>';
			var v = live(html);
			el(v, "b").setState(ElementState.HOVER, true);
			equals(v.update(), DocumentView.LAYOUT);
			var fresh = new DocumentView(Dom.parse('<!doctype html>' + html.split("#b:hover").join("#b")), {fonts: ahem()});
			fresh.layout(300, 200);
			equals(geometry(v), geometry(fresh));
		});
		test("a display remakes the box tree", () -> {
			var v = live('<style>#a:hover { display: none }</style><div id=a>x</div><div id=b>y</div>');
			el(v, "a").setState(ElementState.HOVER, true);
			equals(v.update(), DocumentView.TREE);
			equals(v.boxesOf(el(v, "a")).length, 0);
		});
		test("a text changed in place", () -> {
			var v = live('<style>body { margin: 0; font: 10px/1 Ahem }</style><div id=a style="width:40px">ab</div><div id=b>z</div>');
			var t:Text = cast el(v, "a").firstChild;
			t.data = "ab cd ef";
			equals(v.update(), DocumentView.LAYOUT);
			equals(top(v, "b"), 30.0);
		});
		test("children inserted remake the tree", () -> {
			var v = live('<ul id=u><li>a</li></ul>');
			var u = el(v, "u");
			var li = v.document.createElement("li");
			li.append(v.document.createTextNode("b"));
			u.append(li);
			equals(v.update(), DocumentView.TREE);
			equals(v.boxesOf(li).length > 0, true);
		});
	});
}

private function live(body:String):DocumentView {
	var v = new DocumentView(Dom.parse('<!doctype html>' + body), {fonts: ahem()});
	v.layout(300, 200);
	v.watch();
	return v;
}

private function el(v:DocumentView, id:String):Element
	return v.document.getElementById(id);

// (every box fragment's place and size, in the tree's order of its fragments)
private function geometry(v:DocumentView):String {
	var f = v.fragments, out = [];
	function walk(id:Int, x:Float, y:Float) {
		var ax = x + f.x(id), ay = y + f.y(id);
		var b = f.box(id);
		if (f.kind(id) != Fragments.LINE) out.push('${b.node == null ? "-" : b.node.nodeName} $ax,$ay ${f.width(id)}x${f.height(id)}');
		var c = f.first(id);
		while (c >= 0) {
			walk(c, ax, ay);
			c = f.next(c);
		}
	}
	walk(v.root, 0, 0);
	return out.join("\n");
}

private function top(v:DocumentView, id:String):Float {
	var e = v.document.getElementById(id), f = v.fragments;
	for (k in 0...f.count) if (f.kind(k) == Fragments.BOX && f.box(k).node == e && f.box(k).lines != null) return f.absolute(k).y;
	return Math.NaN;
}

private function ahem():FontMatch {
	var f = new FontMatch();
	f.register(sys.io.File.getBytes("tests/flow/fixtures/Ahem.ttf"), "Ahem");
	return f;
}
