// title: World and nodes
// summary: A scene graph: a planet orbiting its sun and a moon orbiting the planet, each a node turned under its parent, the camera a node too
// tags: 3d, docs
// demo: canvas 640x400
import helder.math.Quat;
import helder.gfx.*;
import helder.math.Vec3;
import helder.math.Vec4;
import helder.os.*;
import helder.scene.*;
import helder.scene.math.*;
import helder.scene.render.*;

// A World is a tree of nodes. A node's transform (position, rotation,
// scale) is relative to its parent's, so turning a pivot turns everything
// under it: the planet's orbit is a pivot at the sun, the moon's a pivot
// under the planet. What a node draws, lights or sees is attached to it
// (MeshRenderer, Light, Camera). The simulation runs at a fixed rate
// (FixedStep), whatever the display's.
//
//   helder run docs/examples/scene-nodes
class Nodes {
	static function main() {
		var window = new Window("World and nodes", 640, 400);
		var device = Device.create(window.surface);
		var renderer = new Renderer(device);
		renderer.sky = new Vec3(0.05, 0.06, 0.1);
		renderer.ground = new Vec3(0.02, 0.02, 0.03);
		renderer.clearColor = new Vec4(0.02, 0.02, 0.04, 1);

		var world = new World("nodes");
		var sun = world.node("sun");
		MeshRenderer.attach(sun, Shapes.sphere(device, new Material("sun", new Vec4(1, 0.8, 0.4, 1), 0, 1, new Vec3(1.6, 1.1, 0.4)), 0.6));
		Light.attach(sun, Light.pointLight(new Vec3(1, 0.85, 0.6), 30, 20));

		var orbit = world.node("orbit", sun);             // a pivot: turns, draws nothing
		var planet = world.node("planet", orbit);
		planet.position = new Vec3(2.6, 0, 0);            // relative to the orbit
		MeshRenderer.attach(planet, Shapes.sphere(device, new Material("planet", new Vec4(0.2, 0.45, 0.9, 1), 0, 0.6), 0.32));

		var moonOrbit = world.node("moonOrbit", planet);
		var moon = world.node("moon", moonOrbit);
		moon.position = new Vec3(0.7, 0, 0);
		MeshRenderer.attach(moon, Shapes.sphere(device, new Material("moon", new Vec4(0.7, 0.7, 0.68, 1), 0, 0.9), 0.1));

		var eye = world.node("eye");
		var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
		eye.position = new Vec3(0, 3.2, 6.4);
		eye.lookAt(new Vec3(0, 0, 0));

		var clock = new FixedStep(1 / 60);
		var last = -1.0;
		App.run(() -> {
			var now = App.frame.time;
			clock.advance(last < 0 ? 0 : Math.min(now - last, 0.25), dt -> {
				orbit.rotation = Quat.axisAngle(new Vec3(0, 1, 0), clock.time * 0.5);
				planet.rotation = Quat.axisAngle(new Vec3(0, 1, 0), clock.time * 2);   // its spin turns the moon's pivot too
				moonOrbit.rotation = Quat.axisAngle(new Vec3(0.2, 1, 0), clock.time * 1.5);
			});
			last = now;
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
