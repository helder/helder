package helder.scene.view;

import helder.gfx.shader.Vec3;
import helder.scene.Node as SceneGraphNode;
import helder.ui.Event;

// what a scene node's listener gets: the node hit (the nearest whose mesh
// the pointer's ray met at its press: its bounds, or with <Scene
// pick="triangles"> its triangles), where, how far, the surface's normal
// there and its uvs (a triangle's: painting on a model, placing on a
// surface; picked by bounds, the ray's opposite and 0, 0), the ui's event
// (null for a gesture's: gesture, a recogniser of the box's); the node
// whose listener runs (current), stop() to go no further up. One per
// <Scene> box, refilled for each dispatch: copy what must outlive the call.
class SceneEvent {
	public var node(default, null):SceneGraphNode = SceneGraphNode.NONE;
	public var point(default, null):Vec3 = new Vec3(0, 0, 0);
	public var distance(default, null) = 0.0;
	public var normal(default, null):Vec3 = new Vec3(0, 0, 1);
	public var uv(default, null):helder.gfx.shader.Vec2 = new helder.gfx.shader.Vec2(0, 0);
	public var event(default, null):Null<Event> = null;
	public var gesture(default, null):Null<helder.ui.gesture.Gesture> = null;
	// the pointer's (event's or gesture's): 0 the mouse, else a finger's or a pen's slot
	public var pointerId(default, null) = 0;
	public var current(default, null):SceneGraphNode = SceneGraphNode.NONE;
	public var stopped(default, null) = false;

	public function new() {}

	public function stop()
		stopped = true;

	@:allow(helder.scene.view) function set(node:SceneGraphNode, hit:Null<helder.scene.render.Hit>, event:Null<Event>, gesture:Null<helder.ui.gesture.Gesture>,
			pointerId:Int):SceneEvent {
		this.node = current = node;
		if (hit != null) {
			point = hit.point;
			distance = hit.distance;
			normal = hit.normal;
			uv = hit.uv;
		} else {
			point = new Vec3(0, 0, 0);
			distance = 0;
		}
		this.event = event;
		this.gesture = gesture;
		this.pointerId = pointerId;
		stopped = false;
		return this;
	}
}
