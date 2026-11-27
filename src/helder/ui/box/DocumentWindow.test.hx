package helder.ui.box;

import helder.canvas.Path;
import helder.dom.Dom;
import helder.dom.Element;
import helder.test.Test;

// A document in a window: a resize laid out from the layout cache as a
// fresh layout lays it out, styles kept unless a media query or a viewport
// unit reads the size, scroll containers' content moved at paint and hit
// testing; UiPainter's shapes (a rectangle, a rounded one, a ring) told
// from other paths.
function tests() {
	describe("DocumentView in a window", () -> {
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
