package helder.ui.box;

import haxe.io.Bytes;
import helder.canvas.Canvas;
import helder.dom.Dom;
import helder.test.Test;

// SVG in documents: an <img>'s, a background's and inline <svg>, sized by
// their natural width, height and ratio, drawn as paths (a PDF's vectors),
// an inline one's paint the cascade's (sheets over presentation attributes,
// currentcolor the element's color).
function tests() {
	describe("SVG in documents", () -> {
		test("inline svg: its size, a sheet's fill over a presentation attribute, currentcolor", () -> {
			var c = draw('<style>.a { fill: rgb(0, 0, 255) }</style><div style="color: rgb(0, 128, 0)"><svg width="40" height="20">'
				+ '<rect class="a" fill="red" width="20" height="20"/><rect x="20" fill="currentColor" width="20" height="20"/></svg></div>');
			equals([at(c, 10, 10), at(c, 30, 10), at(c, 45, 10)], [0x0000FFFF, 0x008000FF, 0xFFFFFFFF]);
		});
		test("an img of a data: URL's SVG at its natural size, its own colours", () -> {
			var c = draw('<img src="data:image/svg+xml,' + StringTools.urlEncode('<svg xmlns="http://www.w3.org/2000/svg" width="30" height="10"><rect width="30" height="10" fill="currentColor"/></svg>') + '" style="display: block">');
			equals([at(c, 25, 5), at(c, 35, 5), at(c, 5, 15)], [0x000000FF, 0xFFFFFFFF, 0xFFFFFFFF]);
		});
		test("a ratio alone: the available width, the height by the ratio", () -> {
			var v = view('<div style="width: 40px"><img id=i style="display: block" src="data:image/svg+xml,' + StringTools.urlEncode('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 2 1"/>') + '"></div>');
			equals(size(v, "i"), [40.0, 20]);
		});
		test("a background's SVG tiled", () -> {
			var svg = StringTools.urlEncode('<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="5" height="10" fill="#f00"/></svg>');
			var c = draw('<div style="width: 40px; height: 10px; background: url(&quot;data:image/svg+xml,$svg&quot;)"></div>');
			equals([at(c, 2, 5), at(c, 7, 5), at(c, 12, 5), at(c, 17, 5)], [0xFF0000FF, 0xFFFFFFFF, 0xFF0000FF, 0xFFFFFFFF]);
		});
		test("in a PDF: paths, no image", () -> {
			var pdf = PagedView.toPdf('<!doctype html><style>@page { size: 40px 40px; margin: 0 } body { margin: 0 }</style><svg width="40" height="40"><circle cx="20" cy="20" r="20" fill="red"/></svg>');
			equals(pdf.toString().indexOf("/Subtype /Image") < 0, true);
			// (the page read back at 96 dpi: the circle's middle red, its corner not)
			var b = helder.pdf.Pdf.render(helder.pdf.Pdf.open(pdf), 0, 4 / 3), px = b.straight();
			inline function rgba(x:Int, y:Int):Int
				return px.getInt32((y * b.width + x) * 4);
			equals([rgba(20, 20) & 0xFFFFFF, rgba(1, 1) & 0xFFFFFF], [0x0000FF, 0xFFFFFF]);
		});
	});
}

private function view(body:String):DocumentView {
	var v = DocumentView.html(Dom.parse('<!doctype html><style>body { margin: 0 }</style>' + body));
	v.layout(50, 50);
	return v;
}

private function size(v:DocumentView, id:String):Array<Float> {
	var el = v.document.getElementById(id), f = v.fragments;
	for (k in 0...f.count) if (f.kind(k) == Fragments.BOX && BoxTree.nodeOf(f.box(k)) == el) return [f.width(k), f.height(k)];
	return [];
}

private function draw(body:String):Canvas {
	var c = new Canvas(50, 50);
	DocumentView.render(Dom.parse('<!doctype html><style>body { margin: 0 }</style>' + body), 50, c);
	return c;
}

// (a pixel as 0xRRGGBBAA)
private function at(c:Canvas, x:Int, y:Int):Int {
	var b = Bytes.alloc(4);
	c.readPixels(b, x, y, 1, 1);
	return (b.get(0) << 24) | (b.get(1) << 16) | (b.get(2) << 8) | b.get(3);
}
