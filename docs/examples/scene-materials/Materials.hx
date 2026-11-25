// title: Materials
// summary: The standard material's parameters side by side: metal and plastic from smooth to rough, a clear coat, transmission, an alpha cutoff and emission, lit by an environment map
// tags: 3d, pbr, docs
// demo: canvas 640x400
import helder.asset.Asset;
import helder.gfx.*;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.os.*;
import helder.scene.*;
import helder.scene.math.*;
import helder.scene.render.*;

// helder.scene's standard material is glTF's metallic-roughness model: a
// base colour, metallic (0 a dielectric, 1 a metal) and roughness (0 a
// mirror, 1 matte), with emission, a clear coat, transmission and an alpha
// cutoff on top. The top row is metal, the middle plastic, both from
// smooth (left) to rough; the bottom row the extensions. An environment
// image lights them (Environment: image-based ambient and reflections).
//
//   helder run docs/examples/scene-materials
class Materials {
	static function main() {
		var window = new Window("Materials", 640, 400);
		var device = Device.create(window.surface);
		Images.decode = Images.png;
		var renderer = new Renderer(device);
		var env = Environment.fromImage(device, "image/png", Asset.embed("examples/showroom/panorama.png"));
		if (env != null) renderer.use(env);

		var world = new World("materials");
		for (k in 0...5) {
			var rough = k / 4;
			var metal = world.node("metal" + k);
			metal.position = new Vec3((k - 2) * 1.1, 1.1, 0);
			MeshRenderer.attach(metal, Shapes.sphere(device, new Material("metal", new Vec4(1, 0.78, 0.34, 1), 1, rough), 0.45));
			var plastic = world.node("plastic" + k);
			plastic.position = new Vec3((k - 2) * 1.1, 0, 0);
			MeshRenderer.attach(plastic, Shapes.sphere(device, new Material("plastic", new Vec4(0.75, 0.12, 0.1, 1), 0, rough), 0.45));
		}

		// a clear coat: a polished layer over a rough base (car paint)
		var paint = new Material("paint", new Vec4(0.1, 0.25, 0.7, 1), 0.3, 0.6);
		paint.clearcoat = 1;
		paint.clearcoatRoughness = 0.05;
		// transmission: a thin see-through surface (what is behind times its colour)
		var glass = new Material("glass", new Vec4(0.85, 1, 0.9, 1), 0, 0.05);
		glass.transmission = 1;
		// blend: alpha blended, drawn after the opaque, farthest first
		var tinted = new Material("tinted", new Vec4(0.9, 0.3, 0.8, 0.4), 0, 0.3);
		tinted.blend = Alpha;
		// emission: light of its own (no light needed)
		var lamp = new Material("lamp", new Vec4(0.05, 0.05, 0.05, 1), 0, 0.5, new Vec3(2.5, 1.6, 0.5));
		var floor = new Material("floor", new Vec4(0.3, 0.3, 0.32, 1), 0, 0.8);
		var row = [paint, glass, tinted, lamp];
		for (k in 0...row.length) {
			var n = world.node(row[k].name);
			n.position = new Vec3((k - 1.5) * 1.1, -1.1, 0);
			MeshRenderer.attach(n, Shapes.sphere(device, row[k], 0.45));
		}
		var ground = world.node("floor");
		ground.position = new Vec3(0, -1.6, 0);
		MeshRenderer.attach(ground, Shapes.plane(device, floor, 12));

		var rig = world.node("rig");
		var eye = world.node("eye", rig);
		eye.position = new Vec3(0, 0.6, 6.2);
		eye.lookAt(new Vec3(0, 0, 0));
		var camera = Camera.attach(eye, Camera.perspective(0.75, 0.1, 100));
		var start = -1.0;
		App.run(() -> {
			if (start < 0) start = App.frame.time;
			rig.rotation = Quat.axisAngle(new Vec3(0, 1, 0), Math.sin((App.frame.time - start) * 0.3) * 0.35);
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
