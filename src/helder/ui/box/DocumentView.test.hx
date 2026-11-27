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
		test("a line's plain text: its glyphs made when asked for, as the line placed them", () -> {
			var html = '<!doctype html><style>body { margin: 0; font: 10px/1 Ahem } .j { text-align: justify } pre { tab-size: 4 }</style>'
				+ '<p>aa bb cc dd ee ff gg hh ii jj kk ll mm nn oo pp qq rr ss tt uu vv ww xx yy zz</p><p class=j>aaa b cc dddd e ff ggg h ii jjjj</p>'
				+ '<pre>a\tbb\tccc</pre><p>x <b>yy</b> <i>zzz</i>&shy;w</p>';
			var was = helder.ui.flow.BlockLines.check, checked = helder.ui.flow.BlockLines.checked, differed = helder.ui.flow.BlockLines.differed;
			helder.ui.flow.BlockLines.check = true;
			var v = DocumentView.html(Dom.parse(html), {fonts: ahem()});
			v.layout(120, 200);
			helder.ui.flow.BlockLines.check = was;
			assert(helder.ui.flow.BlockLines.checked > checked);
			equals(helder.ui.flow.BlockLines.differed, differed);
			// (laid out lazily: each text fragment's run there when asked for)
			var w = DocumentView.html(Dom.parse(html), {fonts: ahem()});
			w.layout(120, 200);
			var f = w.fragments, texts = 0;
			for (k in 0...f.count) if (f.kind(k) == Fragments.TEXT) {
				texts++;
				assert(f.glyphs(k) != null && f.glyphs(k).count > 0);
			}
			assert(texts > 10);
		});
		test("backgrounds and borders", () -> {
			var c = draw('<div style="width:10px;height:10px;background:#f00;border:2px solid #00f"></div>');
			equals(at(c, 1, 1), 0x0000FFFF);
			equals(at(c, 5, 5), 0xFF0000FF);
			equals(at(c, 20, 20), 0xFFFFFFFF);
			var d = draw('<div style="margin:2px;width:4px;height:4px;border:1px solid #000;border-top-color:#0f0"></div>');
			equals(at(d, 3, 2), 0x00FF00FF);
			equals(at(d, 3, 7), 0x000000FF);
		});
		test("a font named like a generic family isn't the generic family", () -> {
			// (bundled fonts alone: Inter is the generic family's face where the system has none, as on wasm)
			var fonts = new FontMatch(new helder.text.SystemFonts());
			fonts.register(sys.io.File.getBytes("tests/flow/fixtures/Ahem.ttf"), "serif");
			fonts.register(sys.io.File.getBytes("src/helder/text/fonts/Inter.ttf"));
			var doc = Dom.parse('<!doctype html><p id=a style=\'font-family: "serif"\'>a</p><p id=b style="font-family: serif">b</p>');
			var styles = helder.css.CssCascade.styles(doc);
			function face(id:String)
				return fonts.face(new BoxStyle(styles.computed(doc.getElementById(id)))).family;
			equals(face("a"), "Ahem");
			equals(face("b") == "Ahem", false);
		});
		test("links in LinkText, system colours as a light page's", () -> {
			var c = draw('<a href="x" style="display:block;width:4px;height:4px;border:3px solid"></a><a style="display:block;width:4px;height:4px;border:3px solid"></a><div style="width:4px;height:4px;background:VisitedText"></div>');
			equals(at(c, 1, 1), 0x0000EEFF);
			equals(at(c, 1, 11), 0x000000FF);
			equals(at(c, 1, 21), 0x551A8BFF);
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
		test("sticky positioning against the viewport and a scrolling ancestor", () -> {
			// (a: below the viewport, stuck to its bottom; b: in a scroller, above its top, stuck 5px under it)
			var doc = Dom.parse('<!doctype html><style>body { margin: 0 }</style><div style="height:300px"><div style="height:200px"></div><div id=a style="position:sticky;bottom:0;height:10px"></div></div>'
				+ '<div style="position:absolute;top:0;left:0;width:50px;overflow:hidden;height:40px"><div style="height:100px;padding-top:30px"><div id=b style="position:sticky;top:35px;height:10px"></div></div></div>');
			var v = DocumentView.html(doc);
			v.layout(50, 50);
			equals(top(v, "a"), 40.0);
			equals(top(v, "b"), 35.0);
			// (on a printed page: where flow put it)
			var p = DocumentView.html(doc, {media: {type: "print", width: 50, height: 50}});
			p.layout(50, 50);
			equals(top(p, "a"), 200.0);
		});
		test("text positions through the lines: hit beside a float, a caret, a selection", () -> {
			var doc = Dom.parse('<!doctype html><style>body { margin: 0; font: 10px/1 Ahem }</style><p id=q><span style="float:left;width:30px;height:10px"></span>abc def</p>');
			var v = DocumentView.html(doc, {fonts: ahem()});
			v.layout(60, 100);
			var t = (doc.getElementById("q") : Element).lastChild;
			var h = v.hit(46, 15);
			equals([h.node == t ? 1 : 0, h.offset], [1, 2]);
			var c = v.caret(t, 4);
			equals([c.x, c.y, c.height], [0.0, 20.0, 10.0]);
			var r = [for (r in v.selection({node: t, offset: 1}, {node: t, offset: 5})) [r.x, r.y, r.width, r.height]];
			equals(r, [[40.0, 10.0, 20.0, 10.0], [0.0, 20.0, 10.0, 10.0]]);
		});
		test("ex, ch, cap and line-height: normal from the first available font (Ahem's: 0.8em, 1em, 0.8em, 1em)", () -> {
			var doc = Dom.parse('<!doctype html><style>body { margin: 0; font: 20px Ahem } div { height: 0 }</style><body>'
				+ '<div id=a style="margin-left: 2ch"></div><div id=b style="margin-left: 2ex"></div><div id=c style="margin-left: 1cap"></div>'
				+ '<div id=d style="margin-left: 1lh"></div><p id=p style="margin: 0">x</p><div id=e></div>');
			var v = DocumentView.html(doc, {fonts: ahem()});
			v.layout(200, 100);
			equals([left(v, "a"), left(v, "b"), left(v, "c"), left(v, "d")], [40.0, 32, 16, 20]);
			// (a line of normal height: ascent and descent)
			equals(top(v, "e") - top(v, "p"), 20.0);
		});
		test("positioned boxes of z-index auto paint in tree order, an absolute one's fragment wherever it is", () -> {
			var c = draw('<div style="position: relative; width: 40px; height: 40px"><div style="position: absolute; inset: 0; background: rgb(255, 0, 0)"></div>'
				+ '<div style="position: relative; height: 40px; background: rgb(0, 128, 0)"></div></div>');
			equals(at(c, 20, 20), 0x008000FF);
		});
		test("shrink-to-fit: an absolutely positioned child no part of its parent's width", () -> {
			var doc = Dom.parse('<!doctype html><style>body { margin: 0 }</style><div id=a style="position: absolute"> <span style="position: absolute; display: inline-block; width: 300px">x</span> <div style="width: 100px; height: 10px"></div></div>');
			var v = DocumentView.html(doc, {fonts: ahem()});
			v.layout(400, 100);
			var f = v.fragments, w = -1.0;
			for (k in 0...f.count) if (f.kind(k) == Fragments.BOX && f.box(k).node == doc.getElementById("a")) w = f.width(k);
			equals(w, 100.0);
		});
		test("hit testing", () -> {
			var doc = Dom.parse('<!doctype html><style>body { margin: 0; font: 10px/1 Ahem } span { position: relative; left: 100px }</style><body><p id=p>abcd</p><div id=d style="height:20px"></div><div><span id=s>x</span></div>');
			var v = DocumentView.html(doc, {fonts: ahem()});
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

// (an element's box's left edge on the canvas, its margin's end)
private function left(v:DocumentView, id:String):Float {
	var el = v.document.getElementById(id);
	var f = v.fragments;
	for (k in 0...f.count) if (f.kind(k) == Fragments.BOX && f.box(k).node == el) return f.absolute(k).x;
	return Math.NaN;
}

// (an element's box's top on the canvas)
private function top(v:DocumentView, id:String):Float {
	var el = v.document.getElementById(id);
	var f = v.fragments;
	for (k in 0...f.count) if (f.kind(k) == Fragments.BOX && f.box(k).node == el) return f.absolute(k).y;
	return Math.NaN;
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
