// title: Lights and shadows
// summary: A low sun casting soft shadows (Shadows.soft: sharp where they meet their casters, wider farther away), two coloured point lights circling and a spot light, under a sky
// tags: 3d, lights, shadows, docs
// demo: canvas 640x400
import helder.math.Quat;
import helder.gfx.*;
import helder.math.Vec3;
import helder.math.Vec4;
import helder.os.*;
import helder.scene.*;
import helder.scene.math.*;
import helder.scene.render.*;

// Lights are attached to nodes: the world's first directional light is
// the sun (its node's -z the way it shines), point and spot lights add to
// it (each draw lit by the eight that reach it most). Shadows are opted in with renderer.use: one shadow map
// for the sun, fitted to the casters, here with soft edges (PCSS). Sky
// draws a sky behind the scene.
//
//   helder run docs/examples/scene-lights
class Lights {
	static function main() {
		var window = new Window({title: "Lights and shadows", width: 640, height: 400});
		var device = Device.create(window.surface);
		var shadows = new Shadows(device, 2048).soft(0.25, 16, 0.08);
		var renderer = new Renderer(device).use(shadows).use(new Sky(device));
		renderer.sky = new Vec3(0.12, 0.15, 0.22);
		renderer.ground = new Vec3(0.05, 0.045, 0.04);

		var world = new World("lights");
		var floor = world.node("floor");
		MeshRenderer.attach(floor, Shapes.plane(device, new Material("floor", new Vec4(0.6, 0.6, 0.62, 1), 0, 0.8), 14));
		var stone = new Material("stone", new Vec4(0.8, 0.78, 0.74, 1), 0, 0.7);
		var pillar = Shapes.box(device, stone, 0.35, 1.6, 0.35);
		for (k in 0...6) {
			var n = world.node("pillar" + k);
			var a = k / 6 * Math.PI * 2;
			n.position = new Vec3(Math.cos(a) * 2, 0.8, Math.sin(a) * 2);
			MeshRenderer.attach(n, pillar);
		}
		var ball = world.node("ball");
		ball.position = new Vec3(0, 0.5, 0);
		MeshRenderer.attach(ball, Shapes.sphere(device, new Material("ball", new Vec4(0.9, 0.9, 0.9, 1), 0, 0.35), 0.5));

		// the sun: a directional light, shining along its node's -z
		var sun = world.node("sun");
		Light.attach(sun, Light.directional(new Vec3(1, 0.85, 0.7), 1.2));
		sun.lookAt(new Vec3(-0.6, -0.5, -0.4));
		// point lights: a colour, an intensity and a range (metres)
		var lamps = world.node("lamps");
		var colors = [new Vec3(1, 0.3, 0.1), new Vec3(0.2, 0.5, 1)];
		for (k in 0...2) {
			var n = world.node("lamp" + k, lamps);
			n.position = new Vec3(k == 0 ? 1.2 : -1.2, 0.4, 0);
			Light.attach(n, Light.pointLight(colors[k], 3, 4));
			MeshRenderer.attach(n, Shapes.sphere(device, new Material("bulb", new Vec4(0, 0, 0, 1), 0, 1, colors[k] * 3), 0.06));
		}
		// a spot: full inside the inner cone, fading out to the outer (radians)
		var spot = world.node("spot");
		spot.position = new Vec3(2.6, 3, 2.6);
		spot.lookAt(new Vec3(0, 0, 0));
		Light.attach(spot, Light.spot(new Vec3(1, 0.95, 0.8), 6, 10, 0.15, 0.3));

		var eye = world.node("eye");
		var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
		eye.position = new Vec3(0, 3.4, 6);
		eye.lookAt(new Vec3(0, 0.4, 0));
		var start = -1.0;
		App.run(() -> {
			if (start < 0) start = App.frame.time;
			lamps.rotation = Quat.axisAngle(new Vec3(0, 1, 0), (App.frame.time - start) * 0.8);
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
