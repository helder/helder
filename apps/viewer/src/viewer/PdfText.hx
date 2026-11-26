package viewer;

import helder.ui.Canvas;
import helder.ui.Event;
import helder.ui.Node;
import helder.view.graph.Graph.renderEffect;
import viewer.PageText;

// A PDF page's text over its drawing, for helder.ui's text selection: a
// box as large as the page, its text its PageText's (none until a decode
// brings it), a point turned to the nearest character by the glyphs' boxes,
// hit (an I-beam, a press selecting) only over a glyph, so that a press
// elsewhere is the page's; the selection drawn over the drawing in the
// selection's colour. The pages' boxes are one selectable layer (layer):
// one for every page, in their order, so a selection's points are pages
// and indices in them, the same at any zoom and scroll.
class PdfText extends Node {
	public var text(default, set):Null<PageText> = null;

	@:allow(viewer) final points:Float;
	final doc:PdfDoc;

	function new(doc:PdfDoc, points:Float) {
		super("page-text");
		this.doc = doc;
		this.points = points;
		style.position = Absolute;
		style.pointerEvents = Auto;
		style.cursor = Text;
	}

	// the selectable layer of doc's pages, over them in its PdfView's column
	public static function layer(doc:PdfDoc):Node {
		var n = new Node("pdf-text");
		n.selectable = true;
		n.style.position = Absolute;
		n.style.left = n.style.top = 0;
		n.style.zIndex = 1;
		n.style.pointerEvents = None;
		var pages = [for (i in 0...doc.pages) new PdfText(doc, doc.layout.sizes[i].width)];
		for (p in pages)
			n.append(p);
		renderEffect(() -> {
			doc.zoom();
			doc.laid();
		}, _ -> {
			var l = doc.layout;
			n.style.width = l.width();
			n.style.height = l.height();
			for (i => p in pages) {
				p.style.left = l.left(i);
				p.style.top = l.top(i);
				p.style.width = l.pageWidth(i);
				p.style.height = l.pageHeight(i);
			}
		});
		renderEffect(() -> doc.texted(), _ -> for (i => p in pages) p.text = doc.text(i));
		return n;
	}

	// (a right press: the PDF's context menu, Copy the selection's)
	public static function menu(e:Event) {
		if (e.button != 3 || e.target.ui == null) return;
		e.preventDefault();
		helder.ui.menu.Menus.popup(e.target.ui, ViewerActions.pdf, e.x, e.y, e.target);
	}

	function set_text(t:Null<PageText>):Null<PageText> {
		if (t == text) return t;
		text = t;
		layerChanged();
		return t;
	}

	inline function scale():Float
		return points > 0 ? width / points : 1;

	@:noCompletion override public function hasContent():Bool
		return true;

	// (drawn again when the selection, its text or its size changes: not each frame)
	@:allow(helder.ui) override function paintsLive():Bool
		return false;

	@:noCompletion override public function selectableText():Null<String>
		return text == null ? "" : text.text;

	@:noCompletion override public function selectableIndex(px:Float, py:Float, under = false):Int {
		// (a selection begun: the other pages' text read, for a copy of them all)
		doc.wantText();
		if (text == null) return 0;
		var k = scale();
		return PageTexts.index(text, localX(px, py) / k, localY(px, py) / k, under);
	}

	@:noCompletion override public function selectableCaret(i:Int):Null<{x:Float, y:Float, height:Float}> {
		var c = text == null ? null : PageTexts.caret(text, i);
		if (c == null) return null;
		var b = windowBounds(), k = scale();
		return {x: b.x + c.x * k, y: b.y + c.y * k, height: c.height * k};
	}

	override public function hitTest(px:Float, py:Float):Null<Node> {
		var n = super.hitTest(px, py);
		if (n != this) return n;
		var k = scale();
		return text != null && PageTexts.over(text, (px - absX) / k, (py - absY) / k) >= 0 ? this : null;
	}

	@:noCompletion override public function paintContent(canvas:Canvas, x:Float, y:Float, width:Float, height:Float) {
		var ui = this.ui, t = text;
		if (ui == null || t == null) return;
		var sel = ui.textSelection, range = sel == null ? null : sel.rangeIn(this, t.text.length);
		if (range == null) return;
		var k = scale(), color = ui.selectionColor;
		for (q in PageTexts.spans(t, range.start, range.end)) {
			var ox = x + q[0] * k, oy = y + q[1] * k, ax = q[2] * k, ay = q[3] * k, ux = q[4] * k, uy = q[5] * k;
			if (Math.abs(ay) < 1e-3 && Math.abs(ux) < 1e-3) {
				canvas.rect(Math.min(ox, ox + ax), Math.min(oy, oy + uy), Math.abs(ax), Math.abs(uy), 0, color, 0, 0);
				continue;
			}
			// (turned: a rect in the line's own frame)
			var w = Math.sqrt(ax * ax + ay * ay), c = ax / w, s = ay / w, h = uy * c - ux * s;
			canvas.pushTransform(c, s, -s, c, ox, oy);
			canvas.rect(0, Math.min(0, h), w, Math.abs(h), 0, color, 0, 0);
			canvas.popTransform();
		}
	}
}
