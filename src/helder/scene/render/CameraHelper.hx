package helder.scene.render;

import helder.gfx.Encoder;
import helder.scene.Node;

// a node's camera's view volume, at the frame's aspect (or its own, above 0)
class CameraHelper extends Helper {
	public var color:Int;
	public var aspect:Float;

	public function new(color = 0xFFC040, aspect = 0.0) {
		super();
		this.color = color;
		this.aspect = aspect;
	}

	public static function attach(node:Node, color = 0xFFC040, aspect = 0.0):CameraHelper
		return Helper.add(node, new CameraHelper(color, aspect));

	override public function draw(node:Node, enc:Encoder, frame:Renderer.FrameInfo, renderer:Renderer) {
		var c = helder.scene.Camera.of(node);
		// (the camera drawing the frame shows none of its own)
		if (c != null && c != frame.camera) DebugDraw.frustum(c, aspect > 0 ? aspect : frame.aspect, color);
	}
}
