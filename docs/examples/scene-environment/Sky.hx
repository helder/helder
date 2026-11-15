// title: An environment prefiltered by helder
// summary: An HDR sky made in code (a gradient and a bright sun) prefiltered at load into an octahedral atlas (a compute dispatch where the device has compute, else a fragment pass) lighting spheres from mirror to rough, metal and not
// tags: 3d, lights, environment, docs
// demo: canvas 640x400
import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.os.*;
import helder.scene.*;
import helder.scene.render.*;

// Environment.prefilter takes an equirectangular image (RGBA8, or linear
// RGBA16F or RGBA32F: HDR) and filters it once, at the first frame, into
// rows of light by roughness (GGX) and the irradiance from its spherical
// harmonics: the light a surface reflects at any roughness.
//
//   helder run docs/examples/scene-environment
class Sky {
	static function main() {
		var window = new Window("An environment prefiltered by helder", 640, 400);
		var device = Device.create(window.surface);
		var renderer = new Renderer(device);
		var world = new World("environment");
		// #region environment
		// a sky of 256 x 128 linear floats: a gradient over a dark ground, a sun 40 times as bright
		var w = 256, h = 128, sky = Bytes.alloc(w * h * 16);
		for (y in 0...h)
			for (x in 0...w) {
				var theta = (y + 0.5) / h * Math.PI, phi = ((x + 0.5) / w - 0.5) * 2 * Math.PI;
				var d = new Vec3(Math.sin(theta) * Math.sin(phi), Math.cos(theta), -Math.sin(theta) * Math.cos(phi));
				var c = d.y > 0 ? new Vec3(0.35 + 0.4 * (1 - d.y), 0.5 + 0.35 * (1 - d.y), 0.9) : new Vec3(0.12, 0.1, 0.08);
				var sun = d.x * 0.5 + d.y * 0.6 + d.z * -0.62;
				if (sun > 0.995) c = new Vec3(40, 36, 30);
				var p = 16 * (y * w + x);
				sky.setFloat(p, c.x);
				sky.setFloat(p + 4, c.y);
				sky.setFloat(p + 8, c.z);
				sky.setFloat(p + 12, 1);
			}
		var environment = Environment.prefilter(device, w, h, sky, RGBA32F);
		renderer.use(environment);
		// #endregion
		renderer.sunColor = new Vec3(0, 0, 0);
		for (k in 0...5) {
			var rough = 0.05 + k * 0.235;
			for (row in 0...2) {
				var n = world.node();
				n.position = new Vec3(-2.4 + k * 1.2, row == 0 ? 0.65 : -0.65, 0);
				MeshRenderer.attach(n, Shapes.sphere(device, new Material("ball", row == 0 ? new Vec4(0.95, 0.93, 0.88, 1) : new Vec4(0.8, 0.2, 0.15, 1), row == 0 ? 1 : 0, rough), 0.5, 32, 16));
			}
		}
		var eye = world.node("eye");
		var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
		var start = -1.0;
		App.run(() -> {
			if (start < 0) start = App.frame.time;
			var t = App.frame.time - start;
			eye.position = new Vec3(Math.sin(t * 0.2) * 5.5, 0.4, Math.cos(t * 0.2) * 5.5);
			eye.lookAt(new Vec3(0, 0, 0));
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
