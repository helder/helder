package helder.scene.view;

import helder.gfx.shader.Mat4;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.Camera;
import helder.scene.Node;
import helder.scene.math.MathTools;
import helder.scene.math.Quat;
import helder.scene.render.Lines;
import helder.ui.gesture.Gesture;

// A transform gizmo over a <Scene>'s box (three.js's TransformControls,
// Babylon's gizmos): handles drawn at a node, a drag on one moving,
// turning or scaling the node along that axis. It competes in the box's
// gesture arena beside OrbitControls and the scene nodes' taps: a press on
// a handle is the gizmo's at once (its gesture accepts at the press), a
// press elsewhere is left to the others (a drag there orbits). Modes:
//
//   Translate  three arrows: the node moved along one (the pointer's ray's
//              nearest point on the axis), snap: steps of that length
//   Rotate     three rings: the node turned about one (the angle the
//              pointer turns through about the node, on the ring's plane),
//              rotationSnap: steps of that angle
//   Scale      three arms with squares: the node scaled along one (its
//              local axes: a scale is the node's own), scaleSnap: steps
//
// space World or Local: the axes the world's, or the node's own (Scale's
// always its own). A drag's step leaves the node's new position, rotation
// and scale (in its parent's frame) in position, rotation and scale,
// writes them to the node unless writesNode is off (markup binds a Signal
// so, from onChange), then calls onChange; dragging and axis say what it
// is doing. Its
// handles are Lines drawn over everything (LineRenderer: the box's
// renderer given one), size points long whatever the distance. Nothing is
// allocated per frame or per move.
//
//   var gizmo = new TransformGizmo(box, node);
//   gizmo.mode = Rotate;
//   gizmo.rotationSnap = Math.PI / 12;
//
// In markup: <TransformGizmo of={node} mode={Translate} snap={0.5}/> in a
// <Scene> (SceneTags), position={signal} to write a Signal<Vec3>.
class TransformGizmo implements SceneBox.SceneControl {
	public final box:SceneBox;
	// the node it moves (Node.NONE: none, nothing drawn)
	public var node(default, set):Node;
	public var mode(default, set):GizmoMode = Translate;
	public var space(default, set):GizmoSpace = World;
	// the steps a drag moves by (0: none): metres, radians, and of the scale
	public var snap = 0.0;
	public var rotationSnap = 0.0;
	public var scaleSnap = 0.0;
	// its arms' length on the screen (points), how near a press must be to one
	public var size = 80.0;
	public var reach = 10.0;
	public var enabled = true;
	// a drag's step's node transform (its parent's frame: the node's
	// position, rotation and scale as they were, one of them changed)
	public var position(default, null) = new Vec3(0, 0, 0);
	public var rotation(default, null) = Quat.identity();
	public var scale(default, null) = new Vec3(1, 1, 1);
	// whether a drag writes the node (off: position, rotation and scale
	// alone, for onChange to take: a Signal's)
	public var writesNode = true;
	// after each step of a drag
	public var onChange:Null<TransformGizmo->Void> = null;
	// whether a drag is under way, along which axis (0 x, 1 y, 2 z; -1 none)
	public var dragging(default, null) = false;
	public var axis(default, null) = -1;
	// its gesture in the box's arena
	public final gesture:GizmoGesture;
	// the handles' lines, on a node of their own
	public final lines:Lines;
	public final handles:Node;

	// (a drag's start: the node's world position and the axes' frame, the
	// pointer's place on the axis or the plane, the node's transform then)
	var origin = new Vec3(0, 0, 0);
	var direction = new Vec3(1, 0, 0);
	var start = 0.0;
	var startVector = new Vec3(1, 0, 0);
	var startPosition = new Vec3(0, 0, 0);
	var startRotation = Quat.identity();
	var startScale = new Vec3(1, 1, 1);
	var startWorldRotation = Quat.identity();
	// (the box's bounds and the view's ray, filled in place)
	final bounds = {x: 0.0, y: 0.0, width: 0.0, height: 0.0};
	final ray = new helder.scene.Camera.CameraRay();

	static inline var RING = 48;

	public function new(box:SceneBox, ?node:Node) {
		this.box = box;
		lines = new Lines(512, {segments: true, width: 3, onTop: true, toneMapped: false, cap: Round});
		handles = box.world.node("transform-gizmo");
		Lines.attach(handles, lines);
		box.withRenderer(r -> helder.scene.render.LineRenderer.of(r));
		gesture = new GizmoGesture(this);
		box.addGesture(gesture);
		box.controls.push(this);
		this.node = node ?? Node.NONE;
	}

	public function dispose() {
		box.removeGesture(gesture);
		box.controls.remove(this);
		Lines.detach(handles);
		if (handles.valid) handles.dispose();
	}

	function set_node(n:Node):Node {
		node = n;
		draw();
		return n;
	}

	function set_mode(m:GizmoMode):GizmoMode {
		mode = m;
		draw();
		return m;
	}

	function set_space(s:GizmoSpace):GizmoSpace {
		space = s;
		draw();
		return s;
	}

	// (a frame of the box's: its handles drawn again where the node is now)
	public function update(seconds:Float):Bool {
		draw();
		return false;
	}

	// ---- the handles

	// (whether it shows: a live node in its world's tree)
	inline function showing():Bool
		return enabled && !node.isNone && node.valid && node.world == box.world && box.world.inTree(node);

	// axis k of its frame in the world (unit length)
	function axisOf(k:Int):Vec3 {
		var a = k == 0 ? new Vec3(1, 0, 0) : k == 1 ? new Vec3(0, 1, 0) : new Vec3(0, 0, 1);
		if (space == World && mode != Scale) return a;
		var m = node.worldMatrix(), c = MathTools.col(m, k);
		var l = Math.sqrt(c.x * c.x + c.y * c.y + c.z * c.z);
		return l > 1e-12 ? new Vec3(c.x / l, c.y / l, c.z / l) : a;
	}

	// two unit vectors at right angles to a and to each other
	static function across(a:Vec3):Vec3 {
		var t = Math.abs(a.x) < 0.9 ? new Vec3(1, 0, 0) : new Vec3(0, 1, 0);
		var u = cross(a, t);
		return u / Math.sqrt(dot(u, u));
	}

	static inline function cross(a:Vec3, b:Vec3):Vec3
		return new Vec3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);

	static inline function dot(a:Vec3, b:Vec3):Float
		return a.x * b.x + a.y * b.y + a.z * b.z;

	// the arms' length in the world at the node (size points there)
	function length():Float {
		var c = box.view(), r = box.rectInto(bounds);
		var h = Math.max(1, r.height);
		if (!c.isPerspective) return size * c.height / h;
		var e = c.eye() - node.worldPosition();
		return size * 2 * Math.sqrt(dot(e, e)) * Math.tan(c.fovY / 2) / h;
	}

	// its handles into its lines: each axis's colour, the one dragged yellow
	function draw() {
		if (!showing()) {
			lines.visible = false;
			return;
		}
		lines.visible = true;
		var o = node.worldPosition(), l = length(), n = 0;
		for (k in 0...3) {
			var a = axisOf(k), u = across(a), v = cross(a, u);
			var r = k == 0 ? 0.9 : 0.15, g = k == 1 ? 0.8 : 0.15, b = k == 2 ? 0.95 : 0.2;
			if (k == axis) {
				r = 1;
				g = 0.85;
				b = 0.15;
			}
			switch mode {
				case Rotate:
					for (i in 0...RING) {
						var t0 = i / RING * Math.PI * 2, t1 = (i + 1) / RING * Math.PI * 2;
						n = segment(n, o + (u * Math.cos(t0) + v * Math.sin(t0)) * l, o + (u * Math.cos(t1) + v * Math.sin(t1)) * l, r, g, b);
					}
				case Translate:
					var tip = o + a * l, base = o + a * (l * 0.78), w = l * 0.07;
					n = segment(n, o, tip, r, g, b);
					n = segment(n, tip, base + u * w, r, g, b);
					n = segment(n, tip, base - u * w, r, g, b);
					n = segment(n, tip, base + v * w, r, g, b);
					n = segment(n, tip, base - v * w, r, g, b);
				case Scale:
					var tip = o + a * l, w = l * 0.06;
					n = segment(n, o, tip, r, g, b);
					n = segment(n, tip + (u + v) * w, tip + (u - v) * w, r, g, b);
					n = segment(n, tip + (u - v) * w, tip - (u + v) * w, r, g, b);
					n = segment(n, tip - (u + v) * w, tip - (u - v) * w, r, g, b);
					n = segment(n, tip - (u - v) * w, tip + (u + v) * w, r, g, b);
			}
		}
		lines.count = n;
	}

	inline function segment(n:Int, a:Vec3, b:Vec3, r:Float, g:Float, bl:Float):Int {
		lines.setPoint(n, a.x, a.y, a.z, r, g, bl, 1);
		lines.setPoint(n + 1, b.x, b.y, b.z, r, g, bl, 1);
		return n + 2;
	}

	// ---- picking and dragging (the box's points)

	// a point of the world on the box (its points); z the clip w (behind: <= 0)
	function onBox(p:Vec3):Vec3 {
		var r = box.rectInto(bounds);
		var c = box.view().viewProjection(r.width / Math.max(1, r.height)) * new Vec4(p.x, p.y, p.z, 1);
		if (c.w <= 1e-9) return new Vec3(0, 0, c.w);
		return new Vec3((c.x / c.w * 0.5 + 0.5) * r.width, (0.5 - c.y / c.w * 0.5) * r.height, c.w);
	}

	// how far (points) x, y is from the segment between a and b on the box
	function distanceTo(x:Float, y:Float, a:Vec3, b:Vec3):Float {
		var p = onBox(a), q = onBox(b);
		if (p.z <= 0 || q.z <= 0) return Math.POSITIVE_INFINITY;
		var dx = q.x - p.x, dy = q.y - p.y, l = dx * dx + dy * dy;
		var t = l > 0 ? Math.max(0, Math.min(1, ((x - p.x) * dx + (y - p.y) * dy) / l)) : 0;
		var ex = p.x + dx * t - x, ey = p.y + dy * t - y;
		return Math.sqrt(ex * ex + ey * ey);
	}

	// the handle under x, y (an axis; -1 none)
	public function handleAt(x:Float, y:Float):Int {
		if (!showing()) return -1;
		var o = node.worldPosition(), l = length(), best = -1, nearest = reach;
		for (k in 0...3) {
			var a = axisOf(k), d = Math.POSITIVE_INFINITY;
			if (mode == Rotate) {
				var u = across(a), v = cross(a, u);
				for (i in 0...RING) {
					var t0 = i / RING * Math.PI * 2, t1 = (i + 1) / RING * Math.PI * 2;
					d = Math.min(d, distanceTo(x, y, o + (u * Math.cos(t0) + v * Math.sin(t0)) * l, o + (u * Math.cos(t1) + v * Math.sin(t1)) * l));
				}
			} else
				d = distanceTo(x, y, o + a * (l * 0.15), o + a * l);
			if (d < nearest) {
				nearest = d;
				best = k;
			}
		}
		return best;
	}

	// (the view's ray through x, y of the box)
	function rayAt(x:Float, y:Float) {
		var r = box.rectInto(bounds);
		box.view().rayInto(x / Math.max(1, r.width) * 2 - 1, 1 - y / Math.max(1, r.height) * 2, r.width / Math.max(1, r.height), ray);
	}

	// the ray's nearest point on the line through origin along direction (its distance along)
	function alongAxis():Float {
		var w = origin - ray.origin, b = dot(direction, ray.dir), d = dot(direction, w), e = dot(ray.dir, w);
		var denom = 1 - b * b;
		return Math.abs(denom) < 1e-9 ? start : (b * e - d) / denom;
	}

	// whether the ray meets the plane through origin across direction:
	// where, from origin, into planePoint (a Null<Vec3> would be boxed)
	function onPlane():Bool {
		var den = dot(ray.dir, direction);
		if (Math.abs(den) < 1e-9) return false;
		var t = dot(origin - ray.origin, direction) / den;
		planePoint = ray.origin + ray.dir * t - origin;
		return true;
	}

	var planePoint = new Vec3(0, 0, 0);

	// a press at x, y: a drag begun when it is on a handle
	public function press(x:Float, y:Float):Bool {
		var k = handleAt(x, y);
		if (k < 0) return false;
		axis = k;
		dragging = true;
		origin = node.worldPosition();
		direction = axisOf(k);
		position = startPosition = node.position;
		rotation = startRotation = node.rotation;
		scale = startScale = node.scale;
		startWorldRotation = Quat.fromMat4(node.worldMatrix());
		rayAt(x, y);
		start = alongAxis();
		startVector = onPlane() ? planePoint : across(direction);
		draw();
		return true;
	}

	// the pointer at x, y in a drag: the node moved, turned or scaled
	public function drag(x:Float, y:Float) {
		if (!dragging || !showing()) return;
		rayAt(x, y);
		switch mode {
			case Translate:
				var d = alongAxis() - start;
				if (snap > 0) d = Math.round(d / snap) * snap;
				var local = parentInverse() * new Vec4(origin.x + direction.x * d, origin.y + direction.y * d, origin.z + direction.z * d, 1);
				position = new Vec3(local.x, local.y, local.z);
				if (writesNode) node.position = position;
			case Rotate:
				if (!onPlane()) return;
				var at = planePoint;
				var angle = Math.atan2(dot(cross(startVector, at), direction), dot(startVector, at));
				if (rotationSnap > 0) angle = Math.round(angle / rotationSnap) * rotationSnap;
				// (the turn about the world's axis, then into the parent's frame)
				var world = Quat.axisAngle(direction, angle) * startWorldRotation;
				rotation = (parentRotation().conjugate() * world).normalized();
				if (writesNode) node.rotation = rotation;
			case Scale:
				var f = start != 0 ? alongAxis() / start : 1.0;
				var s = (axis == 0 ? startScale.x : axis == 1 ? startScale.y : startScale.z) * Math.max(0.001, f);
				if (scaleSnap > 0) s = Math.max(scaleSnap, Math.round(s / scaleSnap) * scaleSnap);
				scale = axis == 0 ? new Vec3(s, startScale.y, startScale.z) : axis == 1 ? new Vec3(startScale.x, s, startScale.z) : new Vec3(startScale.x,
					startScale.y, s);
				if (writesNode) node.scale = scale;
		}
		draw();
		if (onChange != null) onChange(this);
		if (box.ui != null) box.ui.requestFrame();
	}

	// the drag ended
	public function release() {
		dragging = false;
		axis = -1;
		draw();
		if (box.ui != null) box.ui.requestFrame();
	}

	function parentInverse():Mat4 {
		var p = node.parent;
		return p.isNone ? Mat4.identity() : MathTools.inverse(p.worldMatrix());
	}

	function parentRotation():Quat {
		var p = node.parent;
		return p.isNone ? Quat.identity() : Quat.fromMat4(p.worldMatrix());
	}
}

// what a TransformGizmo does (its handles: arrows, rings, arms with squares)
enum abstract GizmoMode(Int) {
	var Translate;
	var Rotate;
	var Scale;
}

// its axes: the world's, or the node's own
enum abstract GizmoSpace(Int) {
	var World;
	var Local;
}

// a TransformGizmo's gesture: in the arena of a pointer pressed on its
// box, accepting at the press when it is on a handle (before the orbit's
// drag passes its slop), failing at once when it is not
class GizmoGesture extends Gesture {
	final gizmo:TransformGizmo;

	public function new(gizmo:TransformGizmo) {
		super();
		this.gizmo = gizmo;
	}

	// (one pointer: a finger, a pen, the mouse's main button)
	override function wants(type:helder.os.PointerType, button:Int):Bool
		return enabled && gizmo.enabled && pointers == 0 && button == 1;

	override function added() {
		if (active || pointers != 1 || node == null) return;
		if (gizmo.press(node.localX(fx, fy), node.localY(fx, fy)) && accept()) report(Began) else {
			if (gizmo.dragging) gizmo.release();
			fail();
		}
	}

	override function moved() {
		if (!active || node == null) return;
		gizmo.drag(node.localX(fx, fy), node.localY(fx, fy));
		report(Changed);
	}

	override function lifted(cancelled:Bool) {
		if (!active) return;
		gizmo.release();
		report(cancelled ? Cancelled : Ended);
	}

	override function lost() {
		if (!active) return;
		gizmo.release();
		report(Cancelled);
	}
}
