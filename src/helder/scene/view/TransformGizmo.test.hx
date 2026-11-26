package helder.scene.view;

import helder.math.Vec3;
import helder.scene.Camera;
import helder.scene.Node;
import helder.scene.World;
import helder.math.Quat;
import helder.test.Test;
import helder.ui.Ui;

// TransformGizmo on a <Scene>'s box without a GPU (ui's pointers fed as
// UiWindow does; natively and as wasm32-wasi), beside OrbitControls in the
// box's arena: a press on an arm is the gizmo's (the node moved along it,
// the camera not), a press elsewhere the orbit's; rings turn the node about
// their axis, arms scale it, snaps step; a node under a turned parent is
// moved along the world's axis all the same; with writesNode off the
// value is onChange's, the node left; a frame's handles and a drag's steps allocate
// nothing. (Its drag through a real window: tests/3d-ui/SurfaceCheck.hx.)
function tests() {
	describe("TransformGizmo", () -> {
		var t = 0.0;
		var ui:Ui = null, box:SceneBox = null, orbit:OrbitControls = null, camera:Camera = null, world:World = null;
		var node = Node.NONE, gizmo:TransformGizmo = null;
		// (at distance 10, fov 1, 200 points high: the world's units a point)
		var per = 2 * 10 * Math.tan(0.5) / 200;
		beforeEach(() -> {
			t = 0;
			Ui.now = () -> t;
			ui = new Ui(null, 200, 200);
			if (world != null) world.dispose();
			world = new World("gizmo");
			var eye = world.node("eye");
			eye.position = new Vec3(0, 0, 10);
			eye.lookAt(new Vec3(0, 0, 0));
			camera = Camera.attach(eye, Camera.perspective(1, 0.1, 100));
			box = new SceneBox(world, camera);
			box.style.width = 200;
			box.style.height = 200;
			ui.root.append(box);
			ui.update();
			orbit = new OrbitControls(box, camera);
			orbit.damping = 0;
			node = world.node("moved");
			gizmo = new TransformGizmo(box, node);
		});
		afterAll(() -> {
			if (world != null) world.dispose();
			world = null;
		});
		function drag(x0:Float, y0:Float, x1:Float, y1:Float) {
			ui.pointerDown(x0, y0, 1, 1, Touch);
			for (k in 1...5) {
				t += 0.016;
				ui.pointerMove(x0 + (x1 - x0) * k / 4, y0 + (y1 - y0) * k / 4, 1);
			}
			ui.pointerUp(x1, y1, 1, 1);
		}
		test("its handles drawn: three arrows, five segments each", () -> {
			equals(gizmo.lines.count, 3 * 5 * 2);
			equals(gizmo.lines.visible, true);
			equals(gizmo.handleAt(150, 100), 0, "the x arm, right of the node");
			equals(gizmo.handleAt(100, 50), 1, "the y arm, above it");
			equals(gizmo.handleAt(30, 30), -1, "nothing");
		});
		test("a drag on the x arm moves the node along x, the camera not", () -> {
			var changes = 0;
			gizmo.onChange = g -> changes++;
			drag(150, 100, 180, 100);
			approx(node.position.x, 30 * per, 1e-6);
			approx(node.position.y, 0, 1e-9, "along its axis alone");
			approx(orbit.yaw, 0, 1e-12, "not the orbit's");
			equals(changes, 4);
			equals(gizmo.dragging, false);
		});
		test("a drag elsewhere orbits", () -> {
			drag(40, 40, 80, 40);
			approx(node.position.x, 0, 1e-12);
			assert(orbit.yaw != 0, "the orbit's");
		});
		test("snap: steps of its length", () -> {
			gizmo.snap = 0.25;
			drag(150, 100, 150 + 0.37 / per, 100);
			approx(node.position.x, 0.25, 1e-9);
		});
		test("a ring turns the node about its axis", () -> {
			gizmo.mode = Rotate;
			equals(gizmo.lines.count, 3 * 48 * 2);
			// (the z ring faces the camera: from 45 degrees round to 135, a quarter turn anticlockwise)
			var r = 80 * Math.sqrt(0.5);
			drag(100 + r, 100 - r, 100 - r, 100 - r);
			var q = node.rotation, want = Quat.axisAngle(new Vec3(0, 0, 1), Math.PI / 2);
			approx(Math.abs(q.x * want.x + q.y * want.y + q.z * want.z + q.w * want.w), 1, 1e-6);
		});
		test("rotationSnap: steps of its angle", () -> {
			gizmo.mode = Rotate;
			gizmo.rotationSnap = Math.PI / 4;
			// (a turn of about 30 degrees: 45)
			var a = Math.PI / 4, b = a + 0.52;
			drag(100 + 80 * Math.cos(a), 100 - 80 * Math.sin(a), 100 + 80 * Math.cos(b), 100 - 80 * Math.sin(b));
			var q = node.rotation;
			approx(2 * Math.acos(Math.min(1, Math.abs(q.w))), Math.PI / 4, 1e-6);
		});
		test("an arm scales the node along it", () -> {
			gizmo.mode = Scale;
			drag(140, 100, 180, 100);
			approx(node.scale.x, 2, 1e-6);
			approx(node.scale.y, 1, 1e-12);
		});
		test("under a turned parent: along the world's axis, in the parent's frame", () -> {
			var parent = world.node("parent");
			parent.rotation = Quat.axisAngle(new Vec3(0, 0, 1), Math.PI / 2);
			parent.add(node);
			gizmo.node = node;
			drag(150, 100, 180, 100);
			var w = node.worldPosition();
			approx(w.x, 30 * per, 1e-6);
			approx(w.y, 0, 1e-6);
			approx(node.position.y, -30 * per, 1e-6, "the parent's -y is the world's x");
		});
		test("writesNode off: the value for onChange, the node left", () -> {
			var got = 0.0;
			gizmo.writesNode = false;
			gizmo.onChange = g -> got = g.position.x;
			drag(150, 100, 180, 100);
			approx(got, 30 * per, 1e-6);
			approx(node.position.x, 0, 1e-12);
		});
		test("no node: nothing drawn, nothing taken", () -> {
			gizmo.node = Node.NONE;
			equals(gizmo.lines.visible, false);
			drag(150, 100, 180, 100);
			assert(orbit.yaw != 0, "the orbit's");
		});
		test("a frame's handles and a drag's steps allocate nothing", () -> {
			gizmo.mode = Rotate;
			gizmo.update(0.016);
			var r = 80 * Math.sqrt(0.5);
			gizmo.press(100 + r, 100 - r);
			gizmo.drag(170, 90);
			var before = hxmc.GcStats.bytesAllocated();
			for (k in 0...200) {
				gizmo.update(0.016);
				gizmo.drag(170 - k * 0.1, 90 - k * 0.1);
			}
			gizmo.release();
			equals(hxmc.GcStats.bytesAllocated() - before, 0.0);
		});
	});
}
