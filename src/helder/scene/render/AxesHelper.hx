package helder.scene.render;

import helder.gfx.Encoder;
import helder.scene.Node;

// a node's axes, size long: x red, y green, z blue
class AxesHelper extends Helper {
	public var size:Float;

	public function new(size = 1.0) {
		super();
		this.size = size;
	}

	public static function attach(node:Node, size = 1.0):AxesHelper
		return Helper.add(node, new AxesHelper(size));

	override public function draw(node:Node, enc:Encoder, frame:Renderer.FrameInfo, renderer:Renderer)
		DebugDraw.axes(node.worldMatrix(), size);
}
