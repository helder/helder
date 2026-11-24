package helder.ui.draw;

import helder.gfx.Texture;

// What was drawn under a rectangle before a node that reads it (helder.ui.Glass):
// handed to its canvas (TextureCanvas.pass) where it paints, captured where
// that is drawn (a display list replayed): the Renderer draws the quads
// drawn so far that meet it into a texture of its own (Renderer.pass), the
// CPU's canvas copies its pixels (SoftCanvas.pass)
class Backdrop {
	// the rectangle, in the canvas's coordinates as painted
	public var x = 0.0;
	public var y = 0.0;
	public var width = 0.0;
	public var height = 0.0;
	// as captured: its texture (null: none), the frame's pixel its texel 0, 0
	// is (px, py), the part of it that holds the frame (pw x ph), its size
	// (tw x th); the frame's pixel x, y fell on (fx, fy), its pixels a point
	public var texture:Null<Texture> = null;
	public var px = 0;
	public var py = 0;
	public var pw = 0;
	public var ph = 0;
	public var tw = 0;
	public var th = 0;
	public var fx = 0.0;
	public var fy = 0.0;
	public var scale = 1.0;
	// (the host's own: the Renderer's render target, its quads)
	@:allow(helder.ui.draw) var held:Any = null;

	public function new() {}

	public function set(x:Float, y:Float, width:Float, height:Float) {
		this.x = x;
		this.y = y;
		this.width = width;
		this.height = height;
	}
}
