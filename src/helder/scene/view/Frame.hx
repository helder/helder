package helder.scene.view;

import helder.scene.Stages.Stage;

// Per-frame work in a scene's markup (DESIGN-MARKUP.md 3.3): drei's
// useFrame, owned. Frame.on in a component's body runs f in a stage of the
// frame (Update by default: the frame's seconds; FixedUpdate's the step's)
// while the component is mounted, removed with it; its <Scene> draws every
// frame meanwhile. Motion belongs here, structure in markup (3.2): f writes
// the nodes directly, reads signals with peek (untracked), allocates
// nothing.
//
//   function Spinner(props:{speed:Float}):SceneView {
//     var spin = Node.NONE;
//     Frame.on(dt -> spin.rotation = spin.rotation * Quat.axisAngle(up, dt * props.speed));
//     return <node ref={n -> spin = n.node}><mesh shape="box"/></node>;
//   }
//
// The element's own: onFrame={f -> f.node.rotation = ...} (a FrameEvent).
class Frame {
	// f each frame of stage (Update: given the frame's seconds), while the
	// current owner lives; the function removing it sooner
	public static function on(f:Float->Void, ?stage:Stage):Void->Void {
		var s = (helder.view.graph.Graph.getOwner() == null ? null : helder.view.graph.Graph.use(SceneRenderer.SCOPE)) ?? @:privateAccess SceneRenderer.current;
		if (s == null) throw "helder.scene: Frame.on is in a <Scene>'s markup (or markup rendered into SceneRenderer.root)";
		return s.on(stage ?? Update, f);
	}
}

// what an element's onFrame is given: its node, its markup's element, the
// frame's seconds (one per element, refilled each frame)
class FrameEvent {
	public var node(default, null) = helder.scene.Node.NONE;
	public var element(default, null):Null<helder.scene.view.SceneRenderer.SceneNode> = null;
	// the frame's seconds
	public var dt(default, null) = 0.0;

	public function new() {}
}
