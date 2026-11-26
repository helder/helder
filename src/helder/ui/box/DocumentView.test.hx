package helder.ui.box;

import haxe.io.Bytes;
import helder.canvas.Canvas;
import helder.dom.Dom;
import helder.dom.Element;
import helder.dom.Text;
import helder.test.Test;

// Paint and hit testing: backgrounds, borders, the canvas's background,
// Appendix E's order (positioned boxes over blocks, z-index), opacity,
// overflow clips, transforms; a point to an element, or to a text node
// and an offset (Ahem: each glyph a square of the font size).
function tests() {
	describe("DocumentView", () -> {
		test("backgrounds and borders", () -> {
			var c = draw('<div style="width:10px;height:10px;background:#f00;border:2px solid #00f"></div>');
			equals(at(c, 1, 1), 0x0000FFFF);
			equals(at(c, 5, 5), 0xFF0000FF);
			equals(at(c, 20, 20), 0xFFFFFFFF);
			var d = draw('<div style="margin:2px;width:4px;height:4px;border:1px solid #000;border-top-color:#0f0"></div>');
			equals(at(d, 3, 2), 0x00FF00FF);
			equals(at(d, 3, 7), 0x000000FF);
		});
		test("a document styled through a CSS module", () -> {
			final view = helder.css.CssModule.load("helder/css/test-modules/view.module.css");
			var c = draw('<div class="${view.box}"></div><div class="${view.wide}"></div>');
			// (the first 20 by 10, the second its composed box's and 40 wide)
			equals([at(c, 5, 5), at(c, 25, 5), at(c, 5, 15), at(c, 35, 15), at(c, 45, 15)], [0x008000ff, 0xffffffff, 0x008000ff, 0x008000ff, 0xffffffff]);
		});
		test("the canvas takes the root's background, else body's", () -> {
			equals(at(draw('<style>html { background: #0f0 }</style>', false), 30, 30), 0x00FF00FF);
			equals(at(draw('<style>body { background: #00f; height: 1px }</style>', false), 30, 30), 0x0000FFFF);
		});
		test("Appendix E's order", () -> {
			// (a positioned box over a later block, a negative z-index under it, z-index order)
			var c = draw('<div style="position:relative;height:10px;background:#0f0"></div><div style="margin-top:-10px;height:10px;background:#f00"></div>');
			equals(at(c, 5, 5), 0x00FF00FF);
			var d = draw('<div style="position:relative;z-index:-1;height:10px;background:#f00"></div><div style="margin-top:-10px;height:10px;background:#0f0"></div>');
			equals(at(d, 5, 5), 0x00FF00FF);
			var e = draw('<div style="position:relative;z-index:2;height:10px;background:#0f0"></div><div style="position:relative;z-index:1;margin-top:-10px;height:10px;background:#f00"></div>');
			equals(at(e, 5, 5), 0x00FF00FF);
		});
		test("opacity, overflow clip, transforms", () -> {
			var c = draw('<div style="opacity:0.5;height:10px;background:#000"></div>');
			var grey = at(c, 5, 5) >>> 24;
			assert(grey >= 127 && grey <= 128, 'grey $grey');
			var d = draw('<div style="overflow:hidden;height:10px"><div style="height:30px;background:#f00"></div></div>');
			equals(at(d, 5, 5), 0xFF0000FF);
			equals(at(d, 5, 20), 0xFFFFFFFF);
			var e = draw('<div style="width:10px;height:10px;background:#00f;transform:translate(20px, 5px)"></div>');
			equals(at(e, 25, 10), 0x0000FFFF);
			equals(at(e, 5, 5), 0xFFFFFFFF);
		});
		test("hit testing", () -> {
			var doc = Dom.parse('<!doctype html><style>body { margin: 0; font: 10px/1 Ahem } span { position: relative; left: 100px }</style><body><p id=p>abcd</p><div id=d style="height:20px"></div><div><span id=s>x</span></div>');
			var v = new DocumentView(doc, {fonts: ahem()});
			v.layout(200, 100);
			var p:Element = doc.getElementById("p");
			var h = v.hit(22, 15);
			equals(h.node, p.firstChild);
			equals(h.offset, 2);
			equals(v.hit(150, 15).node, p);
			equals(v.hit(5, 40).node, doc.getElementById("d"));
			var s:Element = doc.getElementById("s");
			equals(v.hit(105, 55).node, s.firstChild);
			equals(v.hit(5, 55).node.nodeName, "DIV");
		});
	});
}

private function ahem():FontMatch {
	var f = new FontMatch();
	f.register(sys.io.File.getBytes("tests/flow/fixtures/Ahem.ttf"), "Ahem");
	return f;
}

private function draw(body:String, plain = true):Canvas {
	var doc = Dom.parse('<!doctype html>' + (plain ? '<style>body { margin: 0 }</style>' : '') + body);
	var c = new Canvas(50, 50);
	DocumentView.render(doc, 50, c);
	return c;
}

// (a pixel as 0xRRGGBBAA)
private function at(c:Canvas, x:Int, y:Int):Int {
	var b = Bytes.alloc(4);
	c.readPixels(b, x, y, 1, 1);
	return (b.get(0) << 24) | (b.get(1) << 16) | (b.get(2) << 8) | b.get(3);
}
