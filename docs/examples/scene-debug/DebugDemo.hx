// title: Debug drawing
// summary: Immediate-mode debug lines from anywhere (rays, boxes, spheres, a velocity's arrow, a path) and the helpers on nodes: an infinite grid, axes, bounds, a light's cone, a camera's frustum
// tags: 3d, debug, docs
// demo: canvas 640x400
import helder.gfx.*;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.os.*;
import helder.scene.*;
import helder.scene.math.*;
import helder.scene.render.*;

// DebugDraw's calls draw lines for one frame, from anywhere: nothing to
// keep or remove, nothing allocated. Debug's are the same calls compiled
// out of a release build (helder build: their arguments too, unless -D
// helder.debugdraw); this page's build is a release, so it calls
// DebugDraw's own. The helpers are components of a node that make the same
// calls each frame: an infinite grid (a shader), axes, a mesh's bounds, a
// light, a camera. The DebugDraw feature draws both.
//
//   helder run docs/examples/scene-debug
class DebugDemo {
	static function main() {
		var window = new Window("Debug drawing", 640, 400);
		var device = Device.create(window.surface);
		var renderer = new Renderer(device);
		renderer.clearColor = new Color(0.05, 0.06, 0.08);
		// #region helpers
		renderer.use(new DebugDraw());
		var world = new World("debug");
		GridHelper.attach(world.node("grid"), {size: 10, divisions: 10});
		var knot = world.node("knot");
		knot.position = new Vec3(-1.2, 0.8, 0);
		MeshRenderer.attach(knot, Shapes.of(device, Geometry.torusKnot({radius: 0.45, tube: 0.15}), Material.lambert({color: new Vec4(0.85, 0.5, 0.3, 1)})));
		BoundsHelper.attach(knot);
		AxesHelper.attach(knot, 0.8);
		var lamp = world.node("lamp");
		lamp.position = new Vec3(1.6, 2.2, -0.6);
		lamp.rotation = Quat.fromEuler(-1.3, 0, 0.2);
		Light.attach(lamp, Light.spot(new Vec3(1, 0.85, 0.5), 6, 3, 0.25, 0.45));
		LightHelper.attach(lamp);
		var other = world.node("other");
		Camera.attach(other, Camera.perspective(0.7, 0.3, 2.5));
		other.position = new Vec3(2.6, 1, 1.6);
		other.lookAt(new Vec3(1, 0.4, -1));
		CameraHelper.attach(other, 0xFFC040, 1.5);
		// #endregion
		var sun = world.node("sun");
		sun.rotation = Quat.fromEuler(-0.9, 0.4, 0);
		Light.attach(sun, Light.directional(new Vec3(1, 0.95, 0.9), 1.2));
		var ball = world.node("ball");
		MeshRenderer.attach(ball, Shapes.of(device, Geometry.sphere({radius: 0.25}), Material.lambert({color: new Vec4(0.35, 0.65, 0.95, 1)})));
		var path = Curve3.catmullRom([new Vec3(-3, 0.3, 1.5), new Vec3(-1.5, 1.4, 2.2), new Vec3(0, 0.4, 1.8), new Vec3(1.2, 1.2, 2.4), new Vec3(2.6, 0.3, 1.6)]);
		var eye = world.node("eye");
		eye.position = new Vec3(-0.4, 3.2, 6.8);
		eye.lookAt(new Vec3(0, 0.5, 0));
		var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
		App.run(() -> {
			var t = App.frame.time;
			knot.rotation = Quat.fromEuler(t * 0.3, t * 0.5, 0);
			// #region calls
			// (a ball along the path: where it is, where it goes, how fast)
			var s = (Math.sin(t * 0.6) + 1) / 2, p = path.point(s), v = path.tangent(s);
			ball.position = p;
			DebugDraw.path(path, 48);
			DebugDraw.arrow(p, p + v * 0.6, 0x40FFC0);
			DebugDraw.sphere(p, 0.35, 0x4080FF);
			// (a ray from the ball down to the floor, where it lands marked over everything)
			DebugDraw.ray(p, new Vec3(0, -1, 0), p.y);
			DebugDraw.onTop = true;
			DebugDraw.cross3(new Vec3(p.x, 0, p.z), 0.3, 0xFFFFFF);
			DebugDraw.onTop = false;
			// #endregion
			var enc = device.beginFrame();
			if (enc == null) return;
			renderer.draw(enc, world, camera);
			device.endFrame();
		}, e -> switch e.kind {
			case Close: window.close();
			case KeyDown if (e.key == 0xFF1B): window.close();
			case _:
		});
	}
}
