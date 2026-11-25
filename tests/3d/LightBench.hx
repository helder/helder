import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.os.*;
import helder.scene.*;
import helder.scene.render.*;
import helder.scene.render.Lod.LodLevel;

// What the lighting features cost a frame,
// measured headless as EffectBench measures post's effects (Linux: Mesa's
// llvmpipe, Windows: D3D11's WARP), at a phone's render size (810 x 1800),
// each configuration drawn FRAMES times after WARM frames, each frame read
// back, its median; with the CPU's share (the frame's draw call to the
// end of its recording, before the GPU's wait):
//
//   lights      a floor and nine pillars under no local light ("dark"),
//               128 point lights the draws' eight each ("lists"), the same
//               clustered (cells on the GPU where it can: "clustered", on
//               the CPU: "clustered-cpu"), and every light at every pixel
//               ("brute": one cell)
//   shadows     two spot lights and a point light over posts: unshadowed,
//               casting (eight tiles drawn a frame: "cast"), and the same
//               with their tiles kept while nothing moves ("kept")
//   culling     a field of 20000 instances of three levels: drawn whole
//               ("whole"), culled and levelled on the GPU ("culled"), on
//               the CPU ("culled-cpu")
//
// A CPU's rasterizer is not a phone's GPU: the ratios are what carry over.
//
//   LightBench [width height]
class LightBench {
	static inline var WARM = 4;
	static inline var FRAMES = 15;

	static function main() {
		var args = Sys.args();
		var w = args.length > 1 ? Std.parseInt(args[0]) : 810, h = args.length > 1 ? Std.parseInt(args[1]) : 1800;
		var device = Device.create(Surface.headless(w, h));
		var pixels = Bytes.alloc(w * h * 4);
		Sys.println('LightBench: ${w}x$h, the median of $FRAMES frames (each read back), compute ${device.has(Compute) ? "on" : "off"}');
		var base = 0.0;
		for (name in ["dark", "lists", "clustered", "clustered-cpu", "brute", "unshadowed", "cast", "kept", "whole", "culled", "culled-cpu"]) {
			var made = make(name, device, w / h);
			var times = [], cpu = [];
			for (k in 0...WARM + FRAMES) {
				var t0 = haxe.Timer.stamp();
				var enc = device.beginFrame();
				made.draw(enc);
				var t1 = haxe.Timer.stamp();
				device.readPixels(pixels);
				device.endFrame();
				if (k >= WARM) {
					times.push((haxe.Timer.stamp() - t0) * 1000);
					cpu.push((t1 - t0) * 1000);
				}
			}
			times.sort(Reflect.compare);
			cpu.sort(Reflect.compare);
			var ms = times[times.length >> 1];
			if (name == "dark" || name == "unshadowed" || name == "whole") base = ms;
			var r = made.renderer;
			Sys.println('LightBench: $name: ${Math.round(ms * 10) / 10} ms (${Math.round(ms / base * 100) / 100}x ${name == "dark" || name == "lists" || StringTools.startsWith(name, "clustered") || name == "brute" ? "dark" : name == "unshadowed" || name == "cast" || name == "kept" ? "unshadowed" : "whole"}), its recording ${Math.round(cpu[cpu.length >> 1] * 100) / 100} ms; draws: main ${r.draws}, shadows ${r.shadowDraws}; ${made.note()}');
			r.dispose();
		}
	}

	static function make(name:String, device:Device, aspect:Float):{renderer:Renderer, draw:Encoder->Void, note:Void->String} {
		var r = new Renderer(device);
		r.clearColor = new Color(0.02, 0.025, 0.04);
		r.sky = new Vec3(0.05, 0.055, 0.07);
		r.ground = new Vec3(0.03, 0.03, 0.03);
		var world = new World();
		var eye = world.node("eye");
		var camera = Camera.attach(eye, Camera.perspective(0.9, 0.1, 80));
		var stone = Material.lambert({color: new Vec4(0.62, 0.62, 0.64, 1)});
		var note = () -> "";
		switch name {
			case "dark" | "lists" | "clustered" | "clustered-cpu" | "brute":
				eye.position = new Vec3(0, 9, 7);
				eye.lookAt(new Vec3(0, 0, -1));
				MeshRenderer.attach(world.node("floor"), Shapes.of(device, Geometry.plane({width: 16, height: 16}).rotated(-Math.PI / 2, 0, 0), stone));
				var post = Shapes.of(device, Geometry.cylinder({radiusTop: 0.25, radiusBottom: 0.25, height: 1.8, radialSegments: 16}), stone);
				for (k in 0...9) {
					var n = world.node();
					n.position = new Vec3(-4.8 + (k % 3) * 4.8, 0.9, -4.8 + Std.int(k / 3) * 4.8);
					MeshRenderer.attach(n, post);
				}
				if (name != "dark")
					for (i in 0...16)
						for (j in 0...8) {
							var n = world.node();
							n.position = new Vec3(-7.2 + i * 0.96, 0.3 + (i + j) % 3 * 0.35, -6.6 + j * 1.75);
							Light.attach(n, Light.pointLight(new Vec3(1, 0.8, 0.6), 1.4, 1.5));
						}
				if (name == "clustered" || name == "clustered-cpu") {
					var c = new ClusteredLights(device, {maxLights: 128, gpu: name == "clustered"});
					r.use(c);
					note = () -> c.gpu ? "cells on the GPU" : 'cells on the CPU, ${Math.round(c.assignMs * 1000) / 1000} ms';
				}
				if (name == "brute") r.use(new ClusteredLights(device, {maxLights: 128, grid: {x: 1, y: 1, z: 1}, maxPerCell: 128}));
			case "unshadowed" | "cast" | "kept":
				eye.position = new Vec3(0, 5, 7.5);
				eye.lookAt(new Vec3(0, 0.3, 0));
				var shadows = new Shadows(device, 1024).local();
				shadows.locals.cached = name == "kept";
				r.use(shadows);
				MeshRenderer.attach(world.node("floor"), Shapes.of(device, Geometry.plane({width: 14, height: 14}).rotated(-Math.PI / 2, 0, 0), stone));
				var post = Shapes.of(device, Geometry.box({width: 0.25, height: 1.4, depth: 0.25}), stone);
				for (i in 0...5)
					for (j in 0...5) {
						var n = world.node();
						n.position = new Vec3(-4 + i * 2, 0.7, -4 + j * 2);
						MeshRenderer.attach(n, post);
					}
				for (k in 0...3) {
					var n = world.node();
					n.position = k == 2 ? new Vec3(0, 1.6, 0) : new Vec3(k == 0 ? -4 : 4, 3.5, 3);
					var l = Light.attach(n, k == 2 ? Light.pointLight(new Vec3(1, 0.8, 0.6), 12, 8) : Light.spot(new Vec3(0.8, 0.9, 1), 26, 12, 0.35, 0.55));
					if (k < 2) n.lookAt(new Vec3(0, 0, -1));
					l.castShadows = name != "unshadowed";
				}
				note = () -> 'tiles drawn ${shadows.locals.tilesDrawn}, kept ${shadows.locals.tilesKept}';
			case _:
				eye.position = new Vec3(0, 2, 6);
				eye.lookAt(new Vec3(0, 0.5, -30));
				var sun = world.node("sun");
				Light.attach(sun, Light.directional(new Vec3(1, 0.97, 0.92), 2));
				sun.lookAt(new Vec3(-0.4, -0.8, -0.3));
				MeshRenderer.attach(world.node("floor"), Shapes.of(device, Geometry.plane({width: 300, height: 300}).rotated(-Math.PI / 2, 0, 0), stone));
				var levels:Array<LodLevel> = [
					{mesh: Shapes.of(device, Geometry.sphere({radius: 0.5, widthSegments: 32, heightSegments: 16}), stone), until: 0.08},
					{mesh: Shapes.of(device, Geometry.sphere({radius: 0.5, widthSegments: 12, heightSegments: 6}), stone), until: 0.02},
					{mesh: Shapes.of(device, Geometry.sphere({radius: 0.5, widthSegments: 5, heightSegments: 3}), stone)}
				];
				var field = new InstancedMesh(levels[0].mesh, 20000);
				for (i in 0...20000)
					field.setTransform(i, (i % 200) * 1.5 - 150, 0.5, -Std.int(i / 200) * 1.5, 0, 0, 0, 1, 1);
				InstancedMesh.attach(world.node("field"), field);
				if (name != "whole") {
					field.levels = levels;
					var c = new InstanceCulling(device, name == "culled");
					r.use(c);
					note = () -> c.gpu ? 'on the GPU, ${c.dispatches} dispatch' : 'on the CPU: ${c.kept} kept, ${c.culled} culled';
				}
		}
		return {renderer: r, draw: enc -> r.draw(enc, world, camera, aspect), note: note};
	}
}
