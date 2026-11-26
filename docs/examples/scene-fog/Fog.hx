// title: Fog
// summary: Exponential height fog over a colonnade at dusk: thick in the low ground, clear above, the sky covered as far as the camera's far plane, a sign the fog does not cover
// tags: 3d, fog, hdr, docs
// demo: canvas 640x400
import helder.gfx.*;
import helder.math.Vec3;
import helder.math.Vec4;
import helder.os.*;
import helder.scene.*;
import helder.scene.math.*;
import helder.scene.render.Fog as SceneFog;
import helder.scene.render.*;

// renderer.fog: exponential fog by distance (its colour in linear light, a
// density per metre), here with a height falloff (thinner upwards) and a
// clear start. It covers the standard material, the sky and particles; a
// material with fog = false is left clear (the sign). The scene is drawn
// in HDR and finished by a PostProcess, so the fog blooms with the rest.
//
//   helder run docs/examples/scene-fog
class Fog {
	static function main() {
		var window = new Window({title: "Fog", width: 640, height: 400});
		var device = Device.create(window.surface);
		var renderer = new Renderer(device, true, 1, true);   // offscreen, HDR
		renderer.sunDirection = new Vec3(1, 0.25, -0.4);
		renderer.sunColor = new Vec3(0.9, 0.7, 0.5);
		renderer.sky = new Vec3(0.05, 0.06, 0.1);
		renderer.ground = new Vec3(0.02, 0.02, 0.02);

		var fog = new SceneFog(new Vec3(0.012, 0.03, 0.07), 0.09);   // colour, density per metre
		fog.start = 2;        // metres clear before it
		fog.falloff = 0.35;   // thinner upwards
		renderer.fog = fog;

		var sky = new Sky(device);
		sky.zenith = new Vec3(0.004, 0.008, 0.03);
		sky.horizon = new Vec3(0.03, 0.018, 0.014);
		sky.ground = new Vec3(0.01, 0.01, 0.01);
		sky.sunColor = new Vec3(0.5, 0.35, 0.2);
		renderer.use(sky);
		var post = new PostProcess(device, RGBA8, true);   // into the frame
		post.bloom = 0.04;

		var world = new World("fog");
		var floor = world.node("floor");
		MeshRenderer.attach(floor, Shapes.plane(device, new Material("floor", new Vec4(0.3, 0.3, 0.3, 1), 0, 0.8), 120));
		var pillar = Shapes.box(device, new Material("stone", new Vec4(0.6, 0.55, 0.5, 1), 0, 0.7), 0.6, 4, 0.6);
		for (k in 0...12)
			for (side in [-1, 1]) {
				var n = world.node("pillar");
				n.position = new Vec3(side * 2.5, 2, -k * 5);
				MeshRenderer.attach(n, pillar);
			}
		var neon = new Material("sign", new Vec4(0, 0, 0, 1), 0, 1, new Vec3(6, 2, 0.5));
		neon.fog = false;   // not covered
		var sign = world.node("sign");
		sign.position = new Vec3(0, 1.5, -45);
		MeshRenderer.attach(sign, Shapes.box(device, neon, 3, 0.4, 0.2));

		var eye = world.node("eye");
		var camera = Camera.attach(eye, Camera.perspective(0.9, 0.1, 80));
		// (the HDR targets at the frame's size, made again when it changes)
		var w = device.width, h = device.height, start = -1.0;
		var light = device.createTexture({width: w, height: h, format: RGBA16F, renderTarget: true});
		var depth = device.createTexture({width: w, height: h, format: Depth32F});
		App.run(() -> {
			if (start < 0) start = App.frame.time;
			var t = App.frame.time - start;
			fog.height = Math.sin(t * 0.4) * 0.8;   // the fog's floor rising and falling
			eye.position = new Vec3(Math.sin(t * 0.2) * 0.8, 1.7, 6);
			eye.lookAt(new Vec3(0, 2, -20));
			if (w != device.width || h != device.height) {
				w = device.width;
				h = device.height;
				device.destroyTexture(light);
				device.destroyTexture(depth);
				light = device.createTexture({width: w, height: h, format: RGBA16F, renderTarget: true});
				depth = device.createTexture({width: w, height: h, format: Depth32F});
			}
			var enc = device.beginFrame();
			if (enc == null) return;
			renderer.drawInto(enc, world, camera, light, depth, w, h);
			post.run(enc, light, null, w, h, t);
			device.endFrame();
		}, e -> switch e.kind {
			case Close: window.close();
			case KeyDown if (e.key == 0xFF1B): window.close();
			case _:
		});
	}
}
