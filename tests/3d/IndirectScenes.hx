import helder.asset.Asset;
import helder.gfx.*;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.*;
import helder.scene.render.*;
import helder.scene.render.Lightmap.LightmapMode;

// Phase 5's frames (src/helder/scene/DESIGN-3D.md): indirect light (Scenes):
//   sh          the environment frame's spheres (mirror to rough, metal and
//               not) lit by the same panorama prefiltered by helder
//               (Environment.prefilter: an octahedral atlas, its irradiance
//               from the image's spherical harmonics; a dispatch where the
//               device has compute, a fragment pass elsewhere, one golden);
//               its probe checks the harmonics (brighter from the sky)
//   probes      a room (red and green walls, two lamps) lit by a grid of
//               light probes (its spheres: warmer by the red wall, greener
//               by the green) and a reflection probe of its box over a
//               polished floor (the walls reflected where they are, its
//               columns' blur by roughness); its probe checks one capture,
//               none the next frame
//   arealight   a rect light and a disc light (AreaLights: linearly
//               transformed cosines) over a rough floor and a polished one
//               and a sphere, their shapes drawn unlit; its probe checks
//               both are gathered as area lights
//   lightmap    two floor tiles with a baked lightmap (Lightmaps: an atlas of
//               two, each its rectangle, at their second uvs: a soft shadow
//               and a warm pool baked), the left Indirect (the sun added),
//               the right All (the lights baked: no sun added); the boxes
//               without one; its probe checks
//               the tiles are drawn apart, not instanced together
class IndirectScenes {
	public static final NAMES = ["sh", "probes", "arealight", "lightmap"];

	public static function make(name:String, device:Device):Encoder->Void {
		var world = new World();
		var eye = world.node("eye");
		var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
		return switch name {
			case "sh":
				Images.decode = Images.png;
				var env = Environment.prefilterImage(device, "image/png", Asset.embed("panorama.png"), {size: 64, levels: 6, samples: 64});
				var r = new Renderer(device).use(env);
				Scenes.renderer = r;
				for (k in 0...5) {
					var rough = 0.05 + k * 0.235;
					var metal = world.node("metal" + k), plastic = world.node("plastic" + k);
					metal.position = new Vec3(-2.4 + k * 1.2, 0.65, 0);
					plastic.position = new Vec3(-2.4 + k * 1.2, -0.65, 0);
					MeshRenderer.attach(metal, Shapes.sphere(device, new Material("metal", new Vec4(0.95, 0.93, 0.88, 1), 1, rough), 0.5, 32, 16));
					MeshRenderer.attach(plastic, Shapes.sphere(device, new Material("plastic", new Vec4(0.8, 0.2, 0.15, 1), 0, rough), 0.5, 32, 16));
				}
				var sun = world.node("sun");
				Light.attach(sun, Light.directional(new Vec3(1, 0.95, 0.85), 2));
				sun.lookAt(new Vec3(0.35, -0.45, 0.82));
				eye.position = new Vec3(0, 0.3, 5.5);
				eye.lookAt(new Vec3(0, 0, 0));
				Scenes.probe = () -> {
					var up = env.sh.irradiance(new Vec3(0, 1, 0)), down = env.sh.irradiance(new Vec3(0, -1, 0));
					up.x + up.y + up.z > down.x + down.y + down.z ? null : 'sh: the sky (${up}) no brighter than the ground (${down})';
				};
				blackCorner(device, r);
				enc -> r.draw(enc, world, camera);
			case "probes":
				var r = new Renderer(device);
				Scenes.renderer = r;
				r.clearColor = new Color(0.01, 0.01, 0.015);
				r.sunColor = new Vec3(0, 0, 0);
				r.sky = new Vec3(0.02, 0.02, 0.03);
				r.ground = new Vec3(0.01, 0.01, 0.01);
				var probes = new Probes(device, {size: 32, levels: 5, captureSize: 64});
				r.use(probes);
				var white = Material.lambert({color: new Vec4(0.8, 0.8, 0.78, 1)});
				function wall(x:Float, y:Float, z:Float, w:Float, h:Float, d:Float, m:Material) {
					var n = world.node();
					n.position = new Vec3(x, y, z);
					MeshRenderer.attach(n, Shapes.of(device, Geometry.box({width: w, height: h, depth: d}), m));
				}
				// (a room of 8 x 4 x 6: its floor polished, its left wall red, its right green)
				wall(0, -0.05, 0, 8, 0.1, 6, new Material("floor", new Vec4(0.9, 0.9, 0.92, 1), 1, 0.12));
				wall(-4.05, 2, 0, 0.1, 4, 6, Material.lambert({color: new Vec4(0.85, 0.12, 0.1, 1)}));
				wall(4.05, 2, 0, 0.1, 4, 6, Material.lambert({color: new Vec4(0.15, 0.75, 0.2, 1)}));
				wall(0, 2, -3.05, 8, 4, 0.1, white);
				wall(0, 4.05, 0, 8, 0.1, 6, white);
				for (k in 0...3) {
					var s = world.node();
					s.position = new Vec3(-2.5 + k * 2.5, 0.6, -0.5);
					MeshRenderer.attach(s, Shapes.sphere(device, new Material("ball", new Vec4(0.85, 0.85, 0.85, 1), 0, 0.6), 0.6, 32, 16));
				}
				for (x in [-2.0, 2.0]) {
					var lamp = world.node();
					lamp.position = new Vec3(x, 3.4, -1);
					Light.attach(lamp, Light.pointLight(new Vec3(1, 0.9, 0.75), 18, 9));
				}
				// (the grid: warm light from the red side, green from the green, a little from above)
				var grid = new ProbeGrid(new Vec3(8, 4, 6), 3, 2, 2);
				grid.fill(p -> {
					var t = p.x / 8 + 0.5;
					var sh = Sh.ofHemisphere(new Vec3(0.12, 0.12, 0.12), new Vec3(0.03, 0.03, 0.03));
					return sh.addDirectional(new Vec3(-1, 0, 0), new Vec3(1.2 * (1 - t), 0.1, 0.05)).addDirectional(new Vec3(1, 0, 0), new Vec3(0.05, 1 * t, 0.1));
				});
				var gi = world.node("gi");
				gi.position = new Vec3(0, 2, 0);
				ProbeGrid.attach(gi, grid);
				// (its box the room's, a little past its floor and walls: the floor inside it)
				var hall = world.node("hall");
				hall.position = new Vec3(0, 2, 0);
				ReflectionProbe.attach(hall, new ReflectionProbe(new Vec3(8.4, 4.8, 6.4), 0.2));
				eye.position = new Vec3(0, 2.4, 6.5);
				eye.lookAt(new Vec3(0, 1, -1));
				var frames = 0;
				Scenes.probe = () -> probes.captures == 1 ? null : 'probes: ${probes.captures} captures after ${frames} frames, not 1';
				enc -> {
					frames++;
					r.draw(enc, world, camera);
				};
			case "arealight":
				var r = new Renderer(device);
				Scenes.renderer = r;
				r.clearColor = new Color(0.01, 0.01, 0.015);
				r.sunColor = new Vec3(0, 0, 0);
				r.sky = new Vec3(0.015, 0.015, 0.02);
				r.ground = new Vec3(0.01, 0.01, 0.01);
				r.use(new AreaLights(device));
				// (two floors side by side: rough and polished)
				for (k in 0...2) {
					var f = world.node();
					f.position = new Vec3(k == 0 ? -2 : 2, 0, 0);
					f.rotation = helder.scene.math.Quat.axisAngle(new Vec3(1, 0, 0), -Math.PI / 2);
					MeshRenderer.attach(f, Shapes.of(device, Geometry.plane({width: 4, height: 6}), new Material("floor", new Vec4(0.5, 0.5, 0.52, 1), 0, k == 0 ? 0.7 : 0.15)));
				}
				var ball = world.node();
				ball.position = new Vec3(0, 0.5, 0.6);
				MeshRenderer.attach(ball, Shapes.sphere(device, new Material("ball", new Vec4(0.8, 0.8, 0.8, 1), 0, 0.4), 0.5, 32, 16));
				// (the lights, each its shape drawn unlit on its node)
				var rect = world.node("rect");
				rect.position = new Vec3(-1.4, 1.1, -1.6);
				rect.lookAt(new Vec3(-1.2, 0, 0.5));
				Light.attach(rect, Light.rectArea(new Vec3(1, 0.75, 0.5), 6, 1.8, 0.8, 8));
				MeshRenderer.attach(rect, Shapes.of(device, Geometry.plane({width: 1.8, height: 0.8}), Material.unlit({color: new Vec4(1, 0.75, 0.5, 1), doubleSided: true})));
				var disc = world.node("disc");
				disc.position = new Vec3(1.4, 1.6, -0.6);
				disc.lookAt(new Vec3(1.45, 0, -0.55));
				Light.attach(disc, Light.discArea(new Vec3(0.5, 0.7, 1), 8, 0.45, 8));
				MeshRenderer.attach(disc, Shapes.of(device, Geometry.circle({radius: 0.45}), Material.unlit({color: new Vec4(0.5, 0.7, 1, 1), doubleSided: true})));
				eye.position = new Vec3(0, 3.2, 5.2);
				eye.lookAt(new Vec3(0, 0.3, -0.4));
				Scenes.probe = () -> r.frameLights.areas == 2 ? null : 'arealight: ${r.frameLights.areas} area lights gathered, not 2';
				enc -> r.draw(enc, world, camera);
			case "lightmap":
				var r = new Renderer(device).use(new Lightmaps(device));
				Scenes.renderer = r;
				r.clearColor = new Color(0.02, 0.025, 0.04);
				r.sky = new Vec3(0.3, 0.32, 0.4);
				r.ground = new Vec3(0.3, 0.32, 0.4);
				var sun = world.node("sun");
				Light.attach(sun, Light.directional(new Vec3(1, 0.95, 0.85), 2));
				sun.lookAt(new Vec3(0.4, -0.8, -0.3));
				// (the atlas: two 64 x 64 bakes side by side, sRGB: a sky's light
				// darkened under where the box stands, a warm pool beside it)
				var w = 128, h = 64, px = haxe.io.Bytes.alloc(w * h * 4);
				for (y in 0...h)
					for (x in 0...w) {
						var u = (x % 64 + 0.5) / 64, v = (y + 0.5) / 64;
						var dx = u - 0.5, dy = v - 0.5;
						var shade = 0.25 + 0.75 * Math.min(1, Math.sqrt(dx * dx + dy * dy) / 0.3);
						var pool = Math.max(0, 1 - Math.sqrt((u - 0.75) * (u - 0.75) + (v - 0.3) * (v - 0.3)) / 0.25);
						var c = [0.45 * shade + 0.9 * pool, 0.48 * shade + 0.5 * pool, 0.55 * shade + 0.2 * pool];
						for (k in 0...3)
							px.set(4 * (y * w + x) + k, Math.round(Math.pow(Math.min(c[k], 1), 1 / 2.2) * 255));
						px.set(4 * (y * w + x) + 3, 255);
					}
				var baked = device.createTexture({width: w, height: h, data: px});
				var floor = Geometry.plane({width: 3, height: 3, widthSegments: 4, heightSegments: 4});
				// (the second uvs: the plane's own, each tile its rectangle)
				var uv1 = haxe.io.Bytes.alloc(floor.vertexCount * 8);
				for (k in 0...floor.vertexCount) {
					var t = floor.uv(k);
					uv1.setFloat(8 * k, t.x);
					uv1.setFloat(8 * k + 4, t.y);
				}
				var tile = Shapes.of(device, floor, new Material("tile", new Vec4(0.8, 0.8, 0.8, 1), 0, 0.8));
				tile.primitives[0].uv1 = device.createBuffer({size: uv1.length, usage: Vertex, data: uv1});
				var tiles = [];
				for (k in 0...2) {
					var n = world.node();
					n.position = new Vec3(k == 0 ? -1.6 : 1.6, 0, 0);
					n.rotation = helder.scene.math.Quat.axisAngle(new Vec3(1, 0, 0), -Math.PI / 2);
					MeshRenderer.attach(n, tile);
					var l = Lightmap.attach(n, new Lightmap(baked, new Vec4(k * 0.5, 0, 0.5, 1), true));
					l.mode = k == 0 ? Indirect : All;
					tiles.push(n);
				}
				for (x in [-1.6, 1.6]) {
					var box = world.node();
					box.position = new Vec3(x, 0.4, 0);
					MeshRenderer.attach(box, Shapes.of(device, Geometry.box({width: 0.8, height: 0.8, depth: 0.8}), new Material("box", new Vec4(0.7, 0.3, 0.2, 1), 0, 0.5)));
				}
				eye.position = new Vec3(0, 3.4, 4.2);
				eye.lookAt(new Vec3(0, 0, 0));
				Scenes.probe = () -> r.instanced == 0 ? null : 'lightmap: ${r.instanced} instanced: the lightmapped tiles drawn together';
				enc -> r.draw(enc, world, camera);
			case _: throw 'IndirectScenes: no scene $name';
		}
	}

	// (a bright background: a black mark in the corner, where the tests'
	// check that something was drawn looks for the clear colour)
	public static function blackCorner(device:Device, r:Renderer) {
		var ui = new helder.ui.draw.Renderer(device);
		var markPass:PassDesc = {colors: [{load: Load}]};
		r.inject(AfterPass, (enc, frame) -> {
			ui.begin(device.width, device.height);
			ui.rect(0, 0, 4, 4, 0, 0xFF000000, 0, 0);
			enc.beginPass(markPass);
			ui.end(enc);
			enc.endPass();
		});
	}
}
