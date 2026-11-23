package helder.ui.draw;

import helder.gfx.Texture;
import helder.ui.Canvas;
import helder.ui.Corners;
import helder.ui.Node;

// A Canvas that draws GPU textures (a <Scene>'s box, a sprite box, a part's
// shader): the Renderer, or a DisplayList replayed onto one
interface TextureCanvas extends Canvas {
	// a GPU texture at x, y, w x h (Renderer.gpuTexture)
	function gpuTexture(t:Texture, id:Int, x:Float, y:Float, w:Float, h:Float, radius:Float = 0.0, ?corners:Corners):Void;
	// a pass recorded before the frame's (Renderer.beforePass's f, an Encoder->Void)
	function pass(f:Any):Void;
	// a layer drawn here from its tiles, where it can be (Renderer's); false: replay it
	function layerTiles(l:Layer):Bool;
	// whether it keeps its frame from frame to frame, drawn into only where
	// it changed (a window's Renderer: Renderer.keep; Ui.paint's damage)
	function keeps():Bool;
	// what changed (d, in the UI's pixels), taken: rounded out to its own
	// pixels, all of it where what it kept is gone
	function damage(d:Damage):Void;
	// d's rectangle i drawn into next (Ui.paint walks it), -1: done; -2
	// the compositor's frame (composites), -3 its end
	function redraw(i:Int):Void;
	// whether Ui.paint walks the tree once more for the compositor's frame
	// (Renderer.composite); in that walk, what is drawn until leave is
	// scroller n's content (kind 0), its thumb along x (1) or y (2) (an
	// overlay one's alpha as drawn shown in kind >> 2, 256: an opacity of its
	// own), or what helder.ui.Mover m moves (mover): false outside it
	function composites():Bool;
	function enter(n:Node, kind:Int):Bool;
	function mover(m:helder.ui.Mover):Bool;
	function leave():Void;
}
