package helder.ui.flow;

import helder.ui.box.Box;

// A box's preferred aspect ratio (CSS Sizing 4 §5): aspect-ratio's, or a
// replaced element's natural one where it says auto. Sizes go through it
// as content sizes; the ratio is the border box's when box-sizing says so,
// unless it is the natural one, which is always the content box's.
class Ratio {
	// (NaN: none)
	public static function of(box:Box):Float {
		var s = box.style.model();
		var n = natural(box);
		return s.ratioAuto && !Math.isNaN(n) ? n : s.ratio;
	}

	// A content height from a content width (NaN: no ratio, or no width).
	public static function height(box:Box, w:Float, bpx:Float, bpy:Float):Float {
		var r = of(box);
		if (Math.isNaN(r) || Math.isNaN(w)) return Math.NaN;
		return border(box) ? Math.max(0, (w + bpx) / r - bpy) : w / r;
	}

	// A content width from a content height.
	public static function width(box:Box, h:Float, bpx:Float, bpy:Float):Float {
		var r = of(box);
		if (Math.isNaN(r) || Math.isNaN(h)) return Math.NaN;
		return border(box) ? Math.max(0, (h + bpy) * r - bpx) : h * r;
	}

	static function natural(box:Box):Float {
		if (box.kind != BlockReplaced && box.kind != InlineReplaced || box.image == null) return Math.NaN;
		var w = box.image.width, h = box.image.height;
		return w > 0 && h > 0 ? w / h : Math.NaN;
	}

	static function border(box:Box):Bool {
		var s = box.style.model();
		return s.borderBox && !(s.ratioAuto && !Math.isNaN(natural(box)));
	}
}
