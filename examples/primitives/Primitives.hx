// title: Primitives
// summary: Geometry's shapes made in code, each row in another shading model: standard, Lambert, Blinn-Phong, toon, unlit, matcap and normals, side by side
// tags: 3d, geometry, materials, shading
// demo: canvas 800x560
import helder.math.*;
import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.*;
import helder.os.*;
import helder.scene.*;
import helder.scene.math.*;
import helder.scene.render.*;

// Shapes and shading models, side by side.
//
// Each column is one of Geometry's generators (three.js's shapes, with its
// parameter names: Geometry.cylinder({radiusTop, radiusBottom, height})),
// made on the CPU as a VertexData and uploaded by Shapes.of. Each row is
// one of Material's factories (three.js's materials by name): the lit ones
// keep the sun's shadow, the point light and the sky, only how light
// reaches the surface differs; the unlit ones read no light at all.
//
//   helder dev examples/primitives                 this machine
//   helder dev examples/primitives --target web    a page
class Primitives {
	final world = new World("primitives");
	final renderer:Renderer;
	final camera:Camera;
	// (the shapes' nodes, turned a little each frame)
	final spinning:Array<Node> = [];

	public function new(device:Device) {
		// a shadow map for the sun, its edges softened (Shadows.soft)
		var shadows = new Shadows(device, 2048);
		shadows.soft(0.06, 12, 0.04);
		renderer = new Renderer(device).use(shadows);
		renderer.clearColor = new Vec4(0.06, 0.07, 0.09, 1);

		// the shapes: each generator at sizes that fit a cell, with three's
		// parameter names (each optional: three's defaults otherwise)
		var shapes = [
			Geometry.box({width: 0.55, height: 0.55, depth: 0.55}),
			Geometry.sphere({radius: 0.34}),
			Geometry.cylinder({radiusTop: 0.22, radiusBottom: 0.3, height: 0.62}),
			Geometry.cone({radius: 0.32, height: 0.66}),
			Geometry.capsule({radius: 0.2, height: 0.32, capSegments: 6, radialSegments: 16}),
			Geometry.torus({radius: 0.24, tube: 0.1, radialSegments: 16, tubularSegments: 48}),
			Geometry.torusKnot({radius: 0.2, tube: 0.065, tubularSegments: 96, radialSegments: 10}),
			// a vase turned about y from its profile (x the radius, y the height)
			Geometry.lathe([
				new Vec2(0.01, -0.32), new Vec2(0.24, -0.3), new Vec2(0.32, -0.08), new Vec2(0.18, 0.14), new Vec2(0.14, 0.26), new Vec2(0.24, 0.34)
			], {segments: 32}),
			// a tube along a curve (Curve3: by length, its rings on frames that do not flip)
			Geometry.tube(Curve3.catmullRom([for (k in 0...9) new Vec3(Math.cos(k * 1.4) * 0.22, -0.3 + k * 0.075, Math.sin(k * 1.4) * 0.22)]),
				{tubularSegments: 96, radius: 0.06, radialSegments: 10})
		];

		// the shading models, one a row (each factory links its own shader alone)
		var orange = new Vec4(0.9, 0.35, 0.1, 1);
		var models = [
			// glTF's metallic-roughness (three's MeshStandardMaterial): the default
			Material.standard({color: orange, roughness: 0.35}),
			// a light's diffuse alone, no highlight: the cheap lit one for phones
			Material.lambert({color: orange}),
			// Blinn-Phong's highlight, three's shininess
			Material.phong({color: orange, shininess: 60}),
			// each light in bands of n.l, its shadow banded too; the shade away from it
			Material.toon({color: orange, steps: 3, shade: new Vec3(0.2, 0.15, 0.35)}),
			// no light: the colour as it is (signs, halos, a flat style)
			Material.unlit({color: orange}),
			// a lit sphere's picture read by the normal as the eye sees it
			Material.matcap({matcap: matcapImage(device)}),
			// the normal in view space as a colour: a debug view
			Material.normals()
		];

		// the grid: a column per shape, a row per model; one upload of each
		// shape per model (Shapes.of), the nodes drawing it
		for (row in 0...models.length)
			for (col in 0...shapes.length) {
				var n = world.node();
				n.position = new Vec3((col - (shapes.length - 1) / 2) * 0.9, 0.42 + (models.length - 1 - row) * 0.85, -row * 0.3);
				MeshRenderer.attach(n, Shapes.of(device, shapes[col], models[row]));
				spinning.push(n);
			}

		// a floor under them, lit by Lambert's
		var floor = world.node("floor");
		MeshRenderer.attach(floor, Shapes.of(device, Geometry.plane({width: 14, height: 8}).rotated(-Math.PI / 2, 0, 0),
			Material.lambert({color: new Vec4(0.32, 0.34, 0.38, 1)})));
		floor.position = new Vec3(0, 0, -1.5);

		// the lights: a sun (shadowed), a warm point light, and the sky's
		// light from above and the ground's from below (three's HemisphereLight)
		var sun = world.node("sun");
		Light.attach(sun, Light.directional(new Vec3(1, 0.96, 0.9), 2.4));
		sun.rotation = Quat.fromEuler(-0.9, 0.5, 0);
		var lamp = world.node("lamp");
		lamp.position = new Vec3(2.6, 2.8, 1.8);
		Light.attach(lamp, Light.pointLight(new Vec3(1, 0.7, 0.4), 6, 6));
		Light.attach(world.node("sky"), Light.hemisphere(new Vec3(0.32, 0.38, 0.5), new Vec3(0.12, 0.1, 0.08)));

		var eye = world.node("eye");
		camera = Camera.attach(eye, Camera.perspective(0.75, 0.1, 100));
		eye.position = new Vec3(0, 4.2, 9.5);
		eye.lookAt(new Vec3(0, 2.6, -1));
	}

	// the shapes turned to time t (seconds): nothing allocated (Quat is a value)
	public function at(t:Float) {
		var turn = Quat.fromEuler(0.3, t * 0.6, 0);
		for (n in spinning)
			n.rotation = turn;
	}

	public function draw(enc:Encoder)
		renderer.draw(enc, world, camera);

	// a matcap drawn in code: a sphere lit by a warm key light from the upper
	// left, a cool rim and a highlight (64 x 64, sRGB)
	static function matcapImage(device:Device):Texture {
		var size = 64, px = Bytes.alloc(size * size * 4);
		for (y in 0...size)
			for (x in 0...size) {
				var u = (x + 0.5) / size * 2 - 1, v = 1 - (y + 0.5) / size * 2;
				var z = Math.sqrt(Math.max(0, 1 - u * u - v * v));
				var key = Math.max(0, -0.5 * u + 0.6 * v + 0.62 * z), rim = Math.pow(1 - z, 3), spec = Math.pow(key, 24);
				var o = (y * size + x) * 4;
				var channel = [0.85, 0.8, 0.75], cool = [0.15, 0.35, 0.7];
				for (k in 0...3)
					px.set(o + k, Std.int(Math.min(255, Math.pow(Math.min(1, channel[k] * (0.12 + 0.9 * key) + cool[k] * rim + spec), 1 / 2.2) * 255)));
				px.set(o + 3, 255);
			}
		return device.createTexture({width: size, height: size, data: px});
	}

	static function main() {
		var window = new Window("Primitives", 800, 560);
		var device = Device.create(window.surface);
		var scene = new Primitives(device);
		// (the frames' clock: the display's, or a headless run's virtual one)
		var start = -1.0;
		App.run(() -> {
			if (start < 0) start = App.frame.time;
			scene.at(App.frame.time - start);
			var enc = device.beginFrame();
			if (enc == null) return;
			scene.draw(enc);
			device.endFrame();
		}, e -> switch e.kind {
			case Close: window.close();
			case KeyDown if (e.key == 0xFF1B): window.close();
			case _:
		});
	}
}
