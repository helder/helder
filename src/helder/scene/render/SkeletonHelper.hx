package helder.scene.render;

import helder.gfx.Encoder;
import helder.scene.Node;

// a node's skin's bones (its Skin's joints, each to its parent)
class SkeletonHelper extends Helper {
	public var color:Int;

	public function new(color = 0xFFA0FF) {
		super();
		this.color = color;
	}

	public static function attach(node:Node, color = 0xFFA0FF):SkeletonHelper
		return Helper.add(node, new SkeletonHelper(color));

	override public function draw(node:Node, enc:Encoder, frame:Renderer.FrameInfo, renderer:Renderer) {
		var s = Skin.of(node);
		if (s != null) DebugDraw.skeleton(s, color);
	}
}
