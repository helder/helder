// title: glTF material extensions
// summary: Sheen, a clear coat, a thin film, a specular colour, brushed metal and refracting glass: the glTF material extensions on materials made in code, drawn by Physical, the glass through Transmission
// tags: 3d, pbr, gltf, docs
// demo: canvas 640x400
import helder.asset.Asset;
import helder.gfx.*;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.os.*;
import helder.scene.*;
import helder.scene.math.*;
import helder.scene.render.*;

// The glTF material extensions (KHR_materials_sheen, _clearcoat,
// _iridescence, _specular and _ior, _anisotropy, _transmission and
// _volume) are fields of Material, with glTF's names. A material made in
// code that uses one is drawn by Physical's shader (every extension's
// variants, opted in); a model of Model.of's needs none: its sets are
// compiled when compiling. The scene is drawn in HDR into a texture, so
// that Transmission can copy the opaque frame behind the glass, then tone
// mapped into the window (PostProcess).
//
//   helder run docs/examples/scene-physical
class Extensions {
	static function main() {
		var window = new Window("glTF material extensions", 640, 400);
		var device = Device.create(window.surface);
		Images.decode = Images.png;
		// #region features
		var renderer = new Renderer(device, true, 1, true);
		renderer.use(new NormalMaps(device)); // (tangents: anisotropy's direction)
		renderer.use(new Physical());
		renderer.use(new Transmission(device));
		// #endregion
		var env = Environment.fromImage(device, "image/png", Asset.embed("examples/showroom/panorama.png"));
		if (env != null) renderer.use(env);
		var post = new PostProcess(device, RGBA8, true);
		renderer.post = post;
		var world = new World("extensions");

		// #region materials
		var velvet = new Material("velvet", new Vec4(0.05, 0.02, 0.06, 1), 0, 0.8);
		velvet.sheenColor = new Vec3(0.9, 0.3, 0.6); // KHR_materials_sheen
		velvet.sheenRoughness = 0.4;
		var paint = new Material("paint", new Vec4(0.7, 0.05, 0.05, 1), 1, 0.6);
		paint.clearcoat = 1; // KHR_materials_clearcoat
		paint.clearcoatRoughness = 0.05;
		var bubble = new Material("film", new Vec4(0.02, 0.02, 0.03, 1), 0, 0.15);
		bubble.iridescence = 1; // KHR_materials_iridescence
		bubble.iridescenceIor = 1.6;
		bubble.iridescenceThicknessMaximum = 450;
		var tinted = new Material("tinted", new Vec4(0.05, 0.05, 0.1, 1), 0, 0.25);
		tinted.ior = 1.8; // KHR_materials_ior and _specular
		tinted.specularColor = new Vec3(1, 0.85, 0.1);
		var brushed = new Material("brushed", new Vec4(0.95, 0.6, 0.45, 1), 1, 0.45);
		brushed.anisotropy = 0.9; // KHR_materials_anisotropy
		var glass = new Material("glass", new Vec4(1, 1, 1, 1), 0, 0.05);
		glass.transmission = 1; // KHR_materials_transmission
		glass.thickness = 0.9; // KHR_materials_volume: refracted through it
		glass.attenuationColor = new Vec3(0.3, 0.8, 0.5);
		glass.attenuationDistance = 0.6;
		glass.blend = true;
		glass.blending = Premultiplied;
		glass.castShadows = false;
		// #endregion

		var sphere = Geometry.sphere({radius: 0.45, widthSegments: 48, heightSegments: 24, tangents: true});
		var row = [velvet, paint, bubble, tinted, brushed, glass];
		for (k in 0...row.length) {
			var n = world.node(row[k].name);
			n.position = new Vec3((k % 3 - 1) * 1.2, k < 3 ? 0.6 : -0.6, 0);
			MeshRenderer.attach(n, Shapes.of(device, sphere, row[k]));
		}
		var wall = world.node("wall");
		wall.position = new Vec3(0, 0, -1.5);
		MeshRenderer.attach(wall, Shapes.of(device, Geometry.plane({width: 12, height: 8}), new Material("wall", new Vec4(0.5, 0.5, 0.55, 1), 0, 0.8)));

		var rig = world.node("rig");
		var eye = world.node("eye", rig);
		eye.position = new Vec3(0, 0.2, 4.6);
		eye.lookAt(new Vec3(0, 0, 0));
		var camera = Camera.attach(eye, Camera.perspective(0.75, 0.1, 100));
		var w = 0, h = 0;
		var light:Null<Texture> = null, depth:Null<Texture> = null;
		var start = -1.0;
		App.run(() -> {
			if (start < 0) start = App.frame.time;
			rig.rotation = Quat.axisAngle(new Vec3(0, 1, 0), Math.sin((App.frame.time - start) * 0.3) * 0.35);
			var enc = device.beginFrame();
			if (enc == null) return;
			if (w != device.width || h != device.height) {
				if (light != null) device.destroyTexture(light);
				if (depth != null) device.destroyTexture(depth);
				w = device.width;
				h = device.height;
				light = device.createTexture({width: w, height: h, format: RGBA16F, renderTarget: true});
				depth = device.createTexture({width: w, height: h, format: Depth32F});
			}
			renderer.drawInto(enc, world, camera, light, depth, w, h);
			post.run(enc, light, null, w, h);
			device.endFrame();
		}, e -> switch e.kind {
			case Close: window.close();
			case KeyDown if (e.key == 0xFF1B): window.close();
			case _:
		});
	}
}
