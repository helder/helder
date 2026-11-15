package helder.scene.render;

import helder.gfx.Encoder;
import helder.scene.Node;

// a node's light (DebugDraw.light: its direction, range or cone), in its
// colour unless one is given (-1)
class LightHelper extends Helper {
	public var color:Int;

	public function new(color = -1) {
		super();
		this.color = color;
	}

	public static function attach(node:Node, color = -1):LightHelper
		return Helper.add(node, new LightHelper(color));

	override public function draw(node:Node, enc:Encoder, frame:Renderer.FrameInfo, renderer:Renderer)
		DebugDraw.light(node, color);
}
