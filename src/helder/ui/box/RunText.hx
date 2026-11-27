package helder.ui.box;

import helder.canvas.Paint;
import helder.canvas.ShapedRun;

// A painter that draws a text fragment's glyph run where it is placed (x,
// the baseline; snapped: x to a quarter pixel, y to a pixel) from the run
// itself, nothing copied first (UiPainter: its paragraph made once and kept
// while it is drawn); false: drawn as a run placed (GlyphText)
interface RunText {
	function runText(run:ShapedRun, x:Float, baseline:Float, snap:Bool, paint:Paint):Bool;
}
