package helder.ui.box;

import helder.canvas.Path;
import helder.dom.Dom;
import helder.dom.Element;
import helder.dom.ElementState;
import helder.dom.Text;
import helder.test.Test;

// A live document (DocumentView.watch, update): what each change redoes by
// its properties' impact (a colour repainted, a width laid out again, a
// display the box tree made again, a text changed in place), a resize laid
// out from the layout cache as a fresh layout lays it out; UiPainter's
// shapes (a rectangle, a rounded one, a ring) told from other paths.
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
		test("a resize lays out from the cache as afresh", () -> {
			var html = '<style>body { font: 10px/1.2 Ahem } .f { display: flex; gap: 4px } .f > div { flex: 1 }</style><p>one two three four five six seven</p><div class=f><div>a b c</div><div>d e f g h</div></div><table border=1><tr><td>x y</td><td>zz</td></tr></table>';
			var v = live(html);
			v.layout(180, 200);
			v.layout(260, 200);
			v.layout(180, 200);
			var fresh = new DocumentView(Dom.parse('<!doctype html>' + html), {fonts: ahem()});
			fresh.layout(180, 200);
			equals(geometry(v), geometry(fresh));
		});
		test("media queries restyle on a resize, others not", () -> {
			var v = live('<style>@media (min-width: 250px) { p { color: #f00 } }</style><p id=p>x</p>');
			var s = v.styles;
			v.layout(320, 200);
			equals(v.styles == s, true);
			v.layout(200, 200);
			equals(v.styles == s, false);
			var w = live('<style>p { width: 50vw }</style><p>x</p>');
			var ws = w.styles;
			w.layout(320, 200);
			equals(w.styles == ws, false);
		});
		test("a scroll container scrolls its content, painted and hit", () -> {
			var v = live('<style>body { margin: 0; font: 10px/1 Ahem } #s { overflow: auto; height: 20px; width: 50px } p { margin: 0; height: 10px }</style><div id=s><p id=a style="background:#f00">a</p><p id=b style="background:#0f0">b</p><p id=c style="background:#00f">c</p></div>');
			equals(v.scrollBy(5, 5, 0, 15), el(v, "s"));
			// (no further than its content's end)
			equals(v.scrolls.get(el(v, "s")), [0.0, 10]);
			equals(v.scrollBy(5, 5, 0, 15), null);
			equals(v.hit(5, 5).node, el(v, "b").firstChild);
			var c = new helder.canvas.Canvas(50, 30);
			v.paint(c);
			equals([px(c, 40, 5), px(c, 40, 15), px(c, 40, 25)], [0x00FF00FF, 0x0000FFFF, 0xFFFFFFFF]);
		});
		test("UiPainter's shapes", () -> {
			var c = new Recording();
			var p = new UiPainter(c, 100, 100);
			p.begin(c, 100, 100, 1, 0, 0, 100, 100);
			var r = new Path();
			r.rect(1, 2, 30, 40);
			p.fill(r, helder.canvas.Paint.solid(0xFF112233));
			var rr = new Path();
			rr.roundRect(0, 0, 20, 10, 4);
			p.fill(rr, helder.canvas.Paint.solid(0xFF112233));
			var ring = new Path();
			ring.rect(0, 0, 20, 20);
			ring.rect(2, 1, 16, 16);
			p.fill(ring, helder.canvas.Paint.solid(0xFF112233), true);
			var tri = new Path();
			tri.moveTo(0, 0);
			tri.lineTo(10, 0);
			tri.lineTo(0, 10);
			tri.close();
			p.fill(tri, helder.canvas.Paint.solid(0xFF112233));
			p.end();
			equals(c.calls, ["rect 1 2 30 40 r0", "rect 0 0 20 10 r4", "ring 0 0 20 20 1,2,3,2", "image"]);
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

// (a canvas writing down its rectangles and images)
private class Recording implements helder.ui.Canvas {
	public final calls:Array<String> = [];

	public function new() {}

	public function translate(dx:Float, dy:Float) {}

	public function pushClip(x:Float, y:Float, w:Float, h:Float, radius:Float, ?corners:helder.ui.Corners) {}

	public function popClip() {}

	public function pushOpacity(alpha:Float) {}

	public function pushGroup(alpha:Float, x:Float, y:Float, w:Float, h:Float) {}

	public function popOpacity() {}

	public function pushTransform(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float) {}

	public function popTransform() {}

	public function rect(x:Float, y:Float, w:Float, h:Float, radius:Float, fill:helder.gfx.Color, borderWidth:Float, border:helder.gfx.Color,
			?corners:helder.ui.Corners, ?sides:helder.os.Edges, style:helder.ui.BorderStyle = Solid) {
		if (sides != null) calls.push('ring $x $y $w $h ${sides.top},${sides.right},${sides.bottom},${sides.left}');
		else calls.push('rect $x $y $w $h r$radius');
	}

	public function shadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:helder.gfx.Color, blur:Float, ?corners:helder.ui.Corners,
		?offset:Array<Float>) {}

	public function insetShadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:helder.gfx.Color, blur:Float, dx:Float, dy:Float, spread:Float,
		?corners:helder.ui.Corners) {}

	public function path(p:helder.ui.Path, fill:Null<helder.ui.Paint>, ?stroke:helder.ui.Stroke) {}

	public function image(img:helder.image.Image, x:Float, y:Float, w:Float, h:Float, u0:Float, v0:Float, u1:Float, v1:Float, radius:Float,
			?corners:helder.ui.Corners)
		calls.push("image");

	public function text(p:helder.ui.Paragraph, x:Float, y:Float, width:Float, align:helder.ui.TextAlign, color:helder.gfx.Color,
		?colors:Array<helder.gfx.Color>) {}

	public function textShadow(p:helder.ui.Paragraph, x:Float, y:Float, width:Float, align:helder.ui.TextAlign, color:helder.gfx.Color, blur:Float,
		?colors:Array<helder.gfx.Color>) {}
}

private function px(c:helder.canvas.Canvas, x:Int, y:Int):Int {
	var b = haxe.io.Bytes.alloc(4);
	c.readPixels(b, x, y, 1, 1);
	return (b.get(0) << 24) | (b.get(1) << 16) | (b.get(2) << 8) | b.get(3);
}
