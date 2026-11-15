package helder.scene.render;

import helder.gfx.Encoder;
import helder.scene.Node;

// A debug view of a node (three's helpers: AxesHelper, Box3Helper,
// CameraHelper, the light helpers, SkeletonHelper), a component drawn each
// frame by the renderer's DebugDraw (renderer.use(new DebugDraw())):
// the same calls as DebugDraw's, for its node, so a helper is what a
// program could write itself. A node may have several (attach adds one).
//
//   AxesHelper.attach(node, 0.5);        // its axes: x red, y green, z blue
//   BoundsHelper.attach(node);           // its mesh's box, turned with it
//   LightHelper.attach(lamp);            // a light's direction, range or cone
//   CameraHelper.attach(eye);            // a camera's view volume
//   SkeletonHelper.attach(character);    // a skin's bones
//   GridHelper.attach(floor, {size: 10, divisions: 10});   // an infinite grid (a shader)
//
// Unlike DebugDraw's calls, helpers are not compiled out of a release build:
// a program attaching one wants it.
class Helper {
	public static final KIND = new StoreKind<Helper>("helper");

	// whether it is drawn
	public var visible = true;
	// drawn for its node's parent, not its node (markup's helper tags: a
	// <BoundsHelper/> in a mesh shows the mesh's)
	public var ofParent = false;
	// (the node's next helper)
	@:allow(helder.scene.render) var next:Null<Helper> = null;

	function new() {}

	// h added to node's helpers
	public static function add<T:Helper>(node:Node, h:T):T {
		var store = node.world.store(KIND);
		var first = store.get(node);
		if (first == null) store.set(node, h) else {
			while (first.next != null)
				first = first.next;
			first.next = h;
		}
		return h;
	}

	// node's helpers removed
	public static function clear(node:Node)
		node.world.store(KIND).remove(node);

	// (its calls for node, each frame DebugDraw draws; enc, frame and the
	// renderer for one drawing on its own: GridHelper)
	public function draw(node:Node, enc:Encoder, frame:Renderer.FrameInfo, renderer:Renderer) {}
}
