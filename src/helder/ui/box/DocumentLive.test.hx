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
			var fresh = DocumentView.html(Dom.parse('<!doctype html>' + html.split("#b:hover").join("#b")), {fonts: ahem()});
			fresh.layout(300, 200);
			equals(geometry(v), geometry(fresh));
		});
		test("a display remakes its boxes alone", () -> {
			var v = live('<style>#a:hover { display: none }</style><div id=a>x</div><div id=b>y</div>');
			var b = v.boxesOf(el(v, "b"))[0];
			el(v, "a").setState(ElementState.HOVER, true);
			equals(v.update(), DocumentView.LAYOUT);
			equals(v.boxesOf(el(v, "b"))[0] == b, true);
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
		test("a viewport unit at another width restyles, the boxes kept", () -> {
			var v = live('<style>body { margin: 0 } #a { width: 50vw; height: 10px }</style><div id=a></div><div id=b>y</div>');
			var a = v.boxesOf(el(v, "a"))[0];
			v.layout(400, 200);
			equals(v.boxesOf(el(v, "a"))[0] == a, true);
			equals(v.fragments.width(v.fragmentOf(a)), 200.0);
		});
		test("a media query that changes restyles what it matches", () -> {
			var v = live('<style>@media (max-width: 250px) { #a { color: #f00 } }</style><p id=a>x</p><p id=b>y</p>');
			var b = v.boxesOf(el(v, "b"))[0];
			v.layout(200, 200);
			equals(v.boxesOf(el(v, "b"))[0] == b, true);
			equals(v.boxesOf(el(v, "a"))[0].style.color("color"), 0xFFFF0000);
		});
		test("a display a query changes remakes its block alone", () -> {
			var html = '<style>body { margin: 0; font: 10px/1 Ahem } @media (max-width: 250px) { span { display: block } }</style><div id=a>w <span>x</span> y</div><div id=b>z</div>';
			var v = live(html);
			var b = v.boxesOf(el(v, "b"))[0];
			v.layout(200, 200);
			equals(v.boxesOf(el(v, "b"))[0] == b, true);
			var fresh = DocumentView.html(Dom.parse('<!doctype html>' + html), {fonts: ahem()});
			fresh.layout(200, 200);
			equals(geometry(v), geometry(fresh));
		});
		test("a block after floats laid out again as a fresh layout does", () -> {
			var html = '<style>body { margin: 0; font: 10px/1 Ahem } .f { float: left; width: 50px; height: 25px }</style><div class=f></div><p>aa aa aa aa</p><p>bb bb bb bb bb</p>';
			var v = live(html);
			v.layout(100, 200);
			v.layout(300, 200);
			var fresh = DocumentView.html(Dom.parse('<!doctype html>' + html), {fonts: ahem()});
			fresh.layout(300, 200);
			equals(geometry(v), geometry(fresh));
		});
		test("a paint order made from the last one's contexts is the one made afresh", () -> {
			var rows = [for (i in 0...40) '<div class=r style="z-index: ${i % 3}"><span id=t$i>row $i</span><b style="opacity: 0.5">x</b></div>'].join("");
			var v = live('<style>body { margin: 0; font: 10px/1 Ahem } .r { position: relative; display: flex; gap: 4px }</style>' + rows);
			v.order;
			(cast el(v, "t7").firstChild : Text).data = "row seven, longer";
			equals(v.update(), DocumentView.LAYOUT);
			var made = v.order, fresh = new PaintOrder(v.fragments, v.root);
			equals(made.count, fresh.count);
			equals([for (k in 0...made.count) '${made.steps[k]} ${made.fragments[k]} ${made.xs[k]},${made.ys[k]} ${made.kinds[made.stateOf[k]]}'].join("\n"),
				[for (k in 0...fresh.count) '${fresh.steps[k]} ${fresh.fragments[k]} ${fresh.xs[k]},${fresh.ys[k]} ${fresh.kinds[fresh.stateOf[k]]}'].join("\n"));
			equals(made.parents.length, fresh.parents.length);
			equals(made.reused > 30, true);
		});
		test("a long document laid out to a cut, exactly, then on to its end as a fresh layout", () -> {
			var html = '<style>body { margin: 0; font: 10px/1 Ahem } section { margin: 4px 0 } @media (max-width: 110px) { p { margin: 2px 0 } em { display: block } }</style>'
				+ [for (i in 0...3000) '<section id=s$i><p>a$i bb <em>cc</em></p><p>dd ee ff gg hh</p><p>ii</p><p>jj kk</p><p>ll</p><p>mm nn oo</p><p>pp</p><p>qq rr</p></section>'].join("");
			var v = DocumentView.html(Dom.parse('<!doctype html>' + html), {fonts: ahem()});
			v.upTo(200);
			v.layout(120, 200);
			// (across the query: what is laid out styled again now, what is past the cut when it gets there)
			v.layout(100, 200);
			equals(v.partial, true);
			equals(laid(v) < 400, true);
			var a = v.anchor(50), at = v.laidTo();
			equals(v.extend(30000), true);
			equals(v.laidTo() >= 30000 && v.laidTo() > at, true);
			// (what is above the cut stays where it was)
			equals(v.moved(a), 0.0);
			var far = v.boxesOf(el(v, "s2900"))[0];
			v.show(far);
			equals(v.fragmentOf(far) >= 0, true);
			v.finish();
			equals(v.partial, false);
			v.layout(120, 200);
			v.layout(100, 200);
			var fresh = DocumentView.html(Dom.parse('<!doctype html>' + html), {fonts: ahem()});
			fresh.layout(100, 200);
			equals(geometry(v), geometry(fresh));
		});
		test("a long document in a block of its own, a flex row's item, laid out to a cut too", () -> {
			var html = '<style>body { margin: 0; font: 10px/1 Ahem; display: flex } #menu { position: fixed; width: 20px } #spec { overflow: hidden; flex-grow: 1; flex-basis: 0 } section { margin: 4px 0 } @media (max-width: 110px) { body { display: block } #spec { line-height: 1.5 } p { margin: 2px 0 } }</style><div id=menu>m</div><div id=spec>'
				+ [for (i in 0...3000) '<section id=s$i><p>a$i bb cc</p><p>dd ee ff gg hh</p><p>ii</p><p>jj kk</p><p>ll</p><p>mm nn oo</p><p>pp</p><p>qq rr</p></section>'].join("") + '</div>';
			var v = DocumentView.html(Dom.parse('<!doctype html>' + html), {fonts: ahem()});
			v.upTo(200);
			v.layout(120, 200);
			equals(v.partial, true);
			equals(laid(v) < 400, true);
			// (across the query: the body a block, the cut in the block of its own; what is past it styled as the tree
			// is made, by what the query's rules match there and what they inherit)
			v.layout(100, 200);
			equals(v.partial, true);
			equals(laid(v) < 400, true);
			v.finish();
			var fresh = DocumentView.html(Dom.parse('<!doctype html>' + html), {fonts: ahem()});
			fresh.layout(100, 200);
			equals(geometry(v), geometry(fresh));
			v.upTo(200);
			v.layout(120, 200);
			equals(v.partial, true);
			v.finish();
			fresh.layout(120, 200);
			equals(geometry(v), geometry(fresh));
		});
	});
}

private function live(body:String):DocumentView {
	var v = DocumentView.html(Dom.parse('<!doctype html>' + body), {fonts: ahem()});
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

// (the fragments of its last layout)
private function laid(v:DocumentView):Int {
	var f = v.fragments, n = 0, stack = [v.root];
	while (stack.length > 0) {
		var id = stack.pop();
		n++;
		var c = f.first(id);
		while (c >= 0) {
			stack.push(c);
			c = f.next(c);
		}
	}
	return n;
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
