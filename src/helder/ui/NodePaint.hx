package helder.ui;

import helder.ui.box.Backgrounds;
import helder.ui.box.Borders;
import helder.ui.box.BoxStyle;
import helder.ui.box.UiPainter;

// A node's box painted by the engine's painter (Borders, Backgrounds: what
// BoxPainter paints a document's boxes with) from its resolved style, onto
// the Ui's canvas: its shadows outside, its background, its shadows inside
// and its border; its outline over its content. What a motion moves of it
// (Present's background, border colour and radius) is drawn from a style of
// its own, copied from the resolved one once and written over each frame.
class NodePaint {
	static final painter = new UiPainter(null, 0, 0);

	// (the painter on canvas: no clip of its own, the canvas's)
	static inline function on(canvas:Canvas, scale:Float):UiPainter {
		painter.begin(canvas, 0, 0, scale, -1e9, -1e9, 1e9, 1e9);
		return painter;
	}

	// its shadows outside, background, shadows inside and border
	public static function box(canvas:Canvas, s:BoxStyle, x:Float, y:Float, w:Float, h:Float, scale:Float) {
		if (s.backgroundColor >>> 24 == 0 && s.background == null && s.shadows == null && s.borderPx(0) + s.borderPx(1) + s.borderPx(2) + s.borderPx(3) == 0)
			return;
		var p = on(canvas, scale);
		Borders.shadows(p, s, x, y, w, h, false);
		Backgrounds.paint(p, s, x, y, w, h, _ -> null, null, false, false, false, false);
		Borders.shadows(p, s, x, y, w, h, true);
		Borders.paint(p, s, x, y, w, h, false, false, false, false);
	}

	// its outline, over its content
	public static function outline(canvas:Canvas, s:BoxStyle, x:Float, y:Float, w:Float, h:Float, scale:Float) {
		if (s.outlineWidth <= 0 || s.outlineStyle == "none" || s.outlineStyle == "") return;
		Borders.outline(on(canvas, scale), s, x, y, w, h);
	}

	// The style it paints: its resolved one, else, while a track moves its background, border colour or radius,
	// its own copy with the tracks' values.
	public static function styleOf(n:Node):BoxStyle {
		var s = n.used, p = n.present;
		if (p == null) return s;
		var bg = p.background != null && p.background.moving(), bd = p.border != null && p.border.moving(), r = p.radius != null && p.radius.moving();
		if (!bg && !bd && !r) return s;
		return @:privateAccess n.scratch = s.paintInto(@:privateAccess n.scratch, bg ? (p.background.value() : Int) : s.backgroundColor,
			bd ? (p.border.value() : Int) : s.borderColor(0), r ? p.radius.value() : Math.NaN);
	}

	// its corners' radii (each corner's horizontal one) for a box of w by h, less d (a padding box's: its widest
	// side there) or more (an outline's offset); null where it has none
	public static function corners(s:BoxStyle, w:Float, h:Float, d:Float):Null<Corners> {
		var r = Borders.radii(s, w, h);
		if (r == null) return null;
		inline function at(k:Int):Float
			return r[2 * k] > 0 ? Math.max(0, r[2 * k] - d) : 0;
		return new Corners(at(0), at(1), at(2), at(3));
	}
}
