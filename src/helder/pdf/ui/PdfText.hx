package helder.pdf.ui;

import helder.pdf.PageText;
import helder.ui.Canvas;
import helder.ui.Node;
import helder.ui.Style;

// A PDF page's text over its drawing, for helder.ui's text selection: a
// node placed and sized as the page is shown, its text a PageText (none
// until one is given), a point turned to the nearest character by the
// glyphs' boxes, hit (an I-beam, a press selecting) only over a glyph, so
// that a press elsewhere is the page's; the selection drawn over the drawing
// in the selection's colour. Pages' nodes in one selectable parent (in
// their order) make one selection across them, its points a page and an
// index in it, the same at any zoom. A package apart from helder.pdf: a
// program that only reads PDFs links no helder.ui.
class PdfText extends Node {
	public var text(default, set):Null<PageText> = null;
	// the page's width in points (the node's width over it: the scale shown)
	public final points:Float;
	// called when a point is turned to a character (a selection begun or moved: the viewer reads the
	// other pages' text then, for a copy of them all)
	public var onSelect:Null<() -> Void> = null;

	public function new(points:Float) {
		super("page-text");
		this.points = points;
		style = Style.of({position: Absolute, pointerEvents: Auto, cursor: Text});
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
		if (onSelect != null) onSelect();
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
