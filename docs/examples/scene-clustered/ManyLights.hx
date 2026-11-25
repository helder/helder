// title: Many lights
// summary: 160 coloured lights drifting over a floor between pillars, each pixel lit by the lights of its cell of the view (ClusteredLights: the cells assigned on the GPU where the device has compute, on the CPU on WebGL2)
// tags: 3d, lights, docs
// demo: canvas 640x400
import helder.gfx.*;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.os.*;
import helder.scene.*;
import helder.scene.render.*;

// Without it, each draw is lit by the eight lights that reach it most
// (FrameLights: a frame's 64 most important): enough for objects among a
// few lamps, not for one floor under a hundred. ClusteredLights cuts the
// view into cells (16 x 9 tiles, 24 slices of depth) and lists the lights
// reaching each, so each pixel loops over its own cell's: here 160 lights,
// a few a pixel. The lists are made by a compute pass where the device has
// one, else on the CPU (the same lists); the standard material reads them
// as a branch, no other shader.
//
//   helder run docs/examples/scene-clustered
class ManyLights {
	static inline var LIGHTS = 160;

	static function main() {
		var window = new Window("Many lights", 640, 400);
		var device = Device.create(window.surface);
		var renderer = new Renderer(device);
		renderer.clearColor = new Vec4(0.02, 0.02, 0.035, 1);
		renderer.sky = new Vec3(0.03, 0.035, 0.05);
		renderer.ground = new Vec3(0.02, 0.02, 0.02);
		// #region clustered
		var clustered = new ClusteredLights(device, {maxLights: 256});
		renderer.use(clustered);
		// #endregion

		var world = new World("lights");
		var stone = Material.lambert({color: new Vec4(0.6, 0.6, 0.62, 1)});
		MeshRenderer.attach(world.node("floor"), Shapes.of(device, Geometry.plane({width: 24, height: 24}).rotated(-Math.PI / 2, 0, 0), stone));
		var pillar = Shapes.of(device, Geometry.cylinder({radiusTop: 0.3, radiusBottom: 0.35, height: 3, radialSegments: 20}), stone);
		for (i in 0...5)
			for (j in 0...5) {
				var n = world.node();
				n.position = new Vec3(-8 + i * 4, 1.5, -8 + j * 4);
				MeshRenderer.attach(n, pillar);
			}
		// (each light a node, its colour a hue, drifting on a circle of its own)
		var lights = [];
		for (k in 0...LIGHTS) {
			var n = world.node();
			var h = k * 0.618;
			Light.attach(n, Light.pointLight(hue(h), 1.6, 1.8));
			lights.push(n);
		}
		var eye = world.node("eye");
		var camera = Camera.attach(eye, Camera.perspective(0.9, 0.1, 60));
		eye.position = new Vec3(0, 9, 13);
		eye.lookAt(new Vec3(0, 0, -1));
		var start = -1.0;
		App.run(() -> {
			if (start < 0) start = App.frame.time;
			var t = App.frame.time - start;
			for (k in 0...LIGHTS) {
				var a = k * 2.399 + t * (0.2 + (k % 7) * 0.05), r = 1.5 + (k % 11) * 0.95;
				lights[k].position = new Vec3(Math.cos(a) * r, 0.3 + (k % 3) * 0.3, Math.sin(a) * r);
			}
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

	// a hue's colour, full saturation
	static function hue(h:Float):Vec3 {
		h = h - Math.floor(h);
		var r = Math.abs(h * 6 - 3) - 1, g = 2 - Math.abs(h * 6 - 2), b = 2 - Math.abs(h * 6 - 4);
		return new Vec3(Math.min(Math.max(r, 0), 1), Math.min(Math.max(g, 0), 1), Math.min(Math.max(b, 0), 1));
	}
}
