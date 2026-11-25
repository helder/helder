package helder.ui.draw;

import helder.ui.Canvas;
import helder.gfx.Color;

// What a node drawn on the GPU (a part's shader, a <Scene>, a sprite box)
// draws on a canvas with no GPU behind it (the CPU's, soft.SoftCanvas): a
// grey box in its place, so that a screenshot shows where it is. Any other
// canvas without a Renderer (a test's recording) is given nothing.
class GpuPlaceholder {
	public static inline var COLOR:Color = 0xFF808080;

	public static function draw(c:Canvas, x:Float, y:Float, w:Float, h:Float) {
		var at = c;
		while (true) {
			var l = Std.downcast(at, DisplayList);
			if (l == null || l.target == null) break;
			at = l.target;
		}
		if (Std.isOfType(at, Gpuless)) c.rect(x, y, w, h, 0, COLOR, 0, 0);
		// (a frame written as data: its box, a placeholder's when read, and the writer told)
		else if (Std.isOfType(at, FrameWriter)) {
			var fw:FrameWriter = cast at;
			// (recorded for it: the box in the list, the pass counted now)
			if (c == at) fw.placeholder(x, y, w, h) else {
				fw.passed();
				c.rect(x, y, w, h, 0, COLOR, 0, 0);
			}
		}
	}
}

// a canvas with no GPU behind it
interface Gpuless {}
