// title: Probes and area lights
// summary: A room lit by a grid of light probes (its spheres warmer by the red wall, greener by the green), a reflection probe of its box over a polished floor (the walls reflected where they are), and a window of a rect area light (linearly transformed cosines)
// tags: 3d, lights, probes, docs
// demo: canvas 640x400
import helder.gfx.*;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.os.*;
import helder.scene.*;
import helder.scene.math.*;
import helder.scene.render.*;

// Indirect light: the light a room's walls bounce. A ProbeGrid holds the
// diffuse light at points of a box (spherical harmonics, baked or made by
// code); each draw takes its centre's, blended on the CPU. A
// ReflectionProbe captures the room once (six faces, prefiltered by
// roughness into Probes' atlas) and reflects it parallax-corrected by its
// box. A rect area light is a window: shaded by linearly transformed
// cosines with AreaLights.
//
//   helder run docs/examples/scene-probes
class Room {
	static function main() {
		var window = new Window("Probes and area lights", 640, 400);
		var device = Device.create(window.surface);
		var renderer = new Renderer(device);
		renderer.clearColor = new Color(0.01, 0.01, 0.015);
		renderer.sunColor = new Vec3(0, 0, 0);
		renderer.sky = new Vec3(0.02, 0.02, 0.03);
		renderer.ground = new Vec3(0.01, 0.01, 0.01);
		var world = new World("probes");
		// a room of 8 x 4 x 6: a polished floor, a red wall and a green one
		function wall(x:Float, y:Float, z:Float, w:Float, h:Float, d:Float, m:Material) {
			var n = world.node();
			n.position = new Vec3(x, y, z);
			MeshRenderer.attach(n, Shapes.of(device, Geometry.box({width: w, height: h, depth: d}), m));
		}
		var white = Material.lambert({color: new Vec4(0.8, 0.8, 0.78, 1)});
		wall(0, -0.05, 0, 8, 0.1, 6, new Material("floor", new Vec4(0.9, 0.9, 0.92, 1), 1, 0.15));
		wall(-4.05, 2, 0, 0.1, 4, 6, Material.lambert({color: new Vec4(0.85, 0.12, 0.1, 1)}));
		wall(4.05, 2, 0, 0.1, 4, 6, Material.lambert({color: new Vec4(0.15, 0.75, 0.2, 1)}));
		wall(0, 2, -3.05, 8, 4, 0.1, white);
		wall(0, 4.05, 0, 8, 0.1, 6, white);
		var balls = [];
		for (k in 0...3) {
			var s = world.node();
			s.position = new Vec3(-2.5 + k * 2.5, 0.6, -0.5);
			MeshRenderer.attach(s, Shapes.sphere(device, new Material("ball", new Vec4(0.85, 0.85, 0.85, 1), k == 1 ? 1 : 0, k == 1 ? 0.2 : 0.6), 0.6, 32, 16));
			balls.push(s);
		}
		// #region probes
		// the diffuse light: a grid of probes, warm by the red wall, green by the green
		var grid = new ProbeGrid(new Vec3(8, 4, 6), 3, 2, 2);
		grid.fill(p -> {
			var t = p.x / 8 + 0.5;
			return Sh.ofHemisphere(new Vec3(0.12, 0.12, 0.12), new Vec3(0.03, 0.03, 0.03))
				.addDirectional(new Vec3(-1, 0, 0), new Vec3(1.2 * (1 - t), 0.1, 0.05))
				.addDirectional(new Vec3(1, 0, 0), new Vec3(0.05, t, 0.1));
		});
		var gi = world.node("gi");
		gi.position = new Vec3(0, 2, 0);
		ProbeGrid.attach(gi, grid);
		// the reflections: the room captured once, its box a little past its floor and walls
		var hall = world.node("hall");
		hall.position = new Vec3(0, 2, 0);
		ReflectionProbe.attach(hall, new ReflectionProbe(new Vec3(8.4, 4.8, 6.4), 0.2));
		renderer.use(new Probes(device));
		// a window in the back wall: a rect area light, its shape drawn unlit
		var pane = world.node("window");
		pane.position = new Vec3(0, 2.4, -2.98);
		Light.attach(pane, Light.rectArea(new Vec3(1, 0.85, 0.65), 5, 2.4, 1.2, 9));
		pane.rotation = Quat.axisAngle(new Vec3(0, 1, 0), Math.PI);
		MeshRenderer.attach(pane, Shapes.of(device, Geometry.plane({width: 2.4, height: 1.2}), Material.unlit({color: new Vec4(1, 0.85, 0.65, 1), doubleSided: true})));
		renderer.use(new AreaLights(device));
		// #endregion
		var eye = world.node("eye");
		var camera = Camera.attach(eye, Camera.perspective(0.9, 0.1, 50));
		var start = -1.0;
		App.run(() -> {
			if (start < 0) start = App.frame.time;
			var t = App.frame.time - start;
			// (the eye swinging, the middle ball rolling: probes per draw, light per frame)
			eye.position = new Vec3(Math.sin(t * 0.3) * 2.2, 2.2, 6.2);
			eye.lookAt(new Vec3(0, 1, -1));
			balls[1].position = new Vec3(Math.sin(t * 0.5) * 2.8, 0.6, -0.5);
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
