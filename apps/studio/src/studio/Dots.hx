package studio;

import helder.gfx.Color;
import helder.ui.Canvas;
import helder.ui.Node;

// The watched canvas' ground: a dot every Theme.DOTS points, moving with
// the camera's pan (not its zoom: the grid stays a texture, not a ruler)
class Dots extends Node {
	final camera:Camera;
	final colour:Color;

	public function new(camera:Camera, colour:Color) {
		super("dots");
		this.camera = camera;
		this.colour = colour;
		style.pointerEvents = None;
	}

	// (the camera moved: drawn again)
	public function moved()
		paintChanged();

	@:noCompletion override public function hasContent():Bool
		return true;

	// (drawn from the camera, told when it moves: not each frame)
	override function paintsLive():Bool
		return false;

	@:noCompletion override public function paintContent(canvas:Canvas, x:Float, y:Float, width:Float, height:Float) {
		var w = rect().width;
		if (w <= 0) return;
		var px = width / w, step = Theme.DOTS * px;
		var ox = mod(camera.x * px, step), oy = mod(camera.y * px, step);
		var gy = y + oy;
		while (gy < y + height) {
			var gx = x + ox;
			while (gx < x + width) {
				canvas.rect(Math.round(gx), Math.round(gy), px, px, 0, colour, 0, Color.TRANSPARENT);
				gx += step;
			}
			gy += step;
		}
	}

	static function mod(a:Float, b:Float):Float
		return a - Math.floor(a / b) * b;
}
