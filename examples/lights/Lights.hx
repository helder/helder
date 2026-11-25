// title: Lights at night
// summary: A cloister at night lit by 200 lights: candles along its walks and fireflies over its garden, each pixel lit by its cell's lights (ClusteredLights), four lanterns, two of them casting shadows all round from one atlas (Shadows), its columns at three levels of detail (Lod)
// tags: 3d, lights, shadows, lod
// demo: canvas 800x480
import helder.gfx.*;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.os.*;
import helder.scene.*;
import helder.scene.math.*;
import helder.scene.render.*;
import helder.scene.render.Lod.LodLevel;

// the lighting paths together (src/helder/scene/README.md, "Lights and
// shadows", "Levels of detail"): 200 point lights, each pixel lit by the
// few of its cell of the view (ClusteredLights: its cells made by a
// compute pass where the device has one, on the CPU on WebGL2); two
// lanterns that cast (Light.castShadows: six tiles each of Shadows' atlas,
// kept while nothing near them moves; twelve tiles a frame at most); the columns' meshes picked by how
// much of the view they cover (Lod). The frame's counts are --stats'.
//
//   helder run examples/lights
class Lights {
	static inline var CANDLES = 120;
	static inline var FIREFLIES = 76;

	static function main() {
		var window = new Window("Lights at night", 800, 480);
		var device = Device.create(window.surface);
		var shadows = new Shadows(device, 1024).local({atlas: 1024, maxLocal: 2});
		var renderer = new Renderer(device).use(shadows).use(new ClusteredLights(device, {maxLights: 256}));
		renderer.clearColor = new Color(0.01, 0.012, 0.025);
		renderer.sky = new Vec3(0.025, 0.03, 0.05);
		renderer.ground = new Vec3(0.01, 0.01, 0.012);

		var world = new World("cloister");
		var stone = Material.lambert({color: new Vec4(0.62, 0.58, 0.52, 1)});
		var grass = Material.lambert({color: new Vec4(0.22, 0.32, 0.16, 1)});
		MeshRenderer.attach(world.node("floor"), Shapes.of(device, Geometry.plane({width: 30, height: 30}).rotated(-Math.PI / 2, 0, 0), stone));
		var garden = world.node("garden");
		garden.position = new Vec3(0, 0.01, 0);
		MeshRenderer.attach(garden, Shapes.of(device, Geometry.plane({width: 14, height: 14}).rotated(-Math.PI / 2, 0, 0), grass));
		// (the walls round it, and its walks' roofs)
		for (k in 0...4) {
			var a = k * Math.PI / 2;
			var wall = world.node();
			wall.position = new Vec3(Math.sin(a) * 12, 2.5, Math.cos(a) * 12);
			wall.rotation = Quat.axisAngle(new Vec3(0, 1, 0), a);
			MeshRenderer.attach(wall, Shapes.of(device, Geometry.box({width: 24.6, height: 5, depth: 0.6}), stone));
			var roof = world.node();
			roof.position = new Vec3(Math.sin(a) * 9.5, 4.6, Math.cos(a) * 9.5);
			roof.rotation = Quat.axisAngle(new Vec3(0, 1, 0), a);
			MeshRenderer.attach(roof, Shapes.of(device, Geometry.box({width: 19.6, height: 0.4, depth: 5}), stone));
		}
		// #region columns
		// the columns: three levels by the share of the view they cover
		var levels:Array<LodLevel> = [
			{mesh: column(device, stone, 32, 8), until: 0.25},
			{mesh: column(device, stone, 12, 3), until: 0.08},
			{mesh: column(device, stone, 6, 1)}
		];
		for (k in 0...28) {
			var side = Std.int(k / 7), i = k % 7;
			var a = side * Math.PI / 2, along = -7.2 + i * 2.4;
			var n = world.node();
			n.position = new Vec3(Math.sin(a) * 7.4 + Math.cos(a) * along, 0, Math.cos(a) * 7.4 - Math.sin(a) * along);
			Lod.attach(n, levels);
		}
		// #endregion
		// #region lights
		// candles along the walks, fireflies over the garden: 196 lights
		for (k in 0...CANDLES) {
			var side = k % 4, i = Std.int(k / 4);
			var a = side * Math.PI / 2, along = -11 + i * 22 / (CANDLES / 4);
			var n = world.node();
			n.position = new Vec3(Math.sin(a) * 11.4 + Math.cos(a) * along, 0.3, Math.cos(a) * 11.4 - Math.sin(a) * along);
			Light.attach(n, Light.pointLight(new Vec3(1, 0.62, 0.3), 0.9, 1.6));
		}
		var flies = [];
		for (k in 0...FIREFLIES) {
			var n = world.node();
			Light.attach(n, Light.pointLight(k % 3 == 0 ? new Vec3(0.6, 1, 0.4) : new Vec3(0.9, 1, 0.5), 0.5, 1.4));
			flies.push(n);
		}
		// four lanterns, two casting shadows all round
		var lanterns = [];
		for (k in 0...4) {
			var a = k * Math.PI / 2 + Math.PI / 4;
			var n = world.node();
			n.position = new Vec3(Math.sin(a) * 9.6, 3.4, Math.cos(a) * 9.6);
			var l = Light.attach(n, Light.pointLight(new Vec3(1, 0.7, 0.4), 14, 9));
			l.castShadows = k % 2 == 0;
			l.shadow = {size: 256};
			lanterns.push(n);
		}
		// #endregion
		var eye = world.node("eye");
		var camera = Camera.attach(eye, Camera.perspective(0.9, 0.1, 80));
		var start = -1.0;
		App.run(() -> {
			if (start < 0) start = App.frame.time;
			var t = App.frame.time - start;
			for (k in 0...FIREFLIES) {
				var a = k * 2.399 + t * 0.3 * (1 + k % 3), r = 1 + (k % 9) * 0.7;
				flies[k].position = new Vec3(Math.cos(a) * r, 0.6 + Math.sin(t * 1.3 + k) * 0.35, Math.sin(a) * r);
			}
			var turn = t * 0.12;
			eye.position = new Vec3(Math.sin(turn) * 10.5, 1.8 + Math.sin(t * 0.2) * 0.6, Math.cos(turn) * 10.5);
			eye.lookAt(new Vec3(0, 1, 0));
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

	// a column of a cylinder's segments, its base and capital boxes
	static function column(device:Device, stone:Material, segments:Int, rings:Int):Mesh {
		var shaft = Geometry.cylinder({radiusTop: 0.22, radiusBottom: 0.26, height: 3.8, radialSegments: segments, heightSegments: rings}).translated(0, 2.3, 0);
		var base = Geometry.box({width: 0.7, height: 0.4, depth: 0.7}).translated(0, 0.2, 0);
		var capital = Geometry.box({width: 0.7, height: 0.3, depth: 0.7}).translated(0, 4.35, 0);
		var mesh = new Mesh();
		for (g in [shaft, base, capital])
			mesh.addData(device, g, stone);
		return mesh;
	}
}
