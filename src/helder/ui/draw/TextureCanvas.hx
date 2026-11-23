package helder.ui.draw;

import helder.gfx.Texture;
import helder.ui.Canvas;
import helder.ui.Corners;

// A Canvas that draws GPU textures (a <Scene>'s box, a sprite box, a part's
// shader): the Renderer, or a DisplayList replayed onto one
interface TextureCanvas extends Canvas {
	// a GPU texture at x, y, w x h (Renderer.gpuTexture)
	function gpuTexture(t:Texture, id:Int, x:Float, y:Float, w:Float, h:Float, radius:Float = 0.0, ?corners:Corners):Void;
	// a pass recorded before the frame's (Renderer.beforePass's f, an Encoder->Void)
	function pass(f:Any):Void;
	// a layer drawn here from its tiles, where it can be (Renderer's); false: replay it
	function layerTiles(l:Layer):Bool;
}
