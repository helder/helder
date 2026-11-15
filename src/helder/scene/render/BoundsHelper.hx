package helder.scene.render;

import helder.gfx.Encoder;
import helder.scene.Node;

// a node's mesh's (or instanced set's) box, in its frame: turned and scaled with it
class BoundsHelper extends Helper {
	public var color:Int;

	public function new(color = 0x40FF40) {
		super();
		this.color = color;
	}

	public static function attach(node:Node, color = 0x40FF40):BoundsHelper
		return Helper.add(node, new BoundsHelper(color));

	override public function draw(node:Node, enc:Encoder, frame:Renderer.FrameInfo, renderer:Renderer) {
		var mesh = MeshRenderer.of(node);
		if (mesh != null && !mesh.bounds.isEmpty()) DebugDraw.boxOf(node.worldMatrix(), mesh.bounds.min, mesh.bounds.max, color);
		var set = InstancedMesh.of(node);
		if (set != null && !set.bounds.isEmpty()) DebugDraw.aabb(set.bounds, color);
	}
}
