import helder.gfx.*;
import helder.math.Vec3;
import helder.math.Vec4;
import helder.scene.*;
import helder.math.Quat;
import helder.scene.render.*;
import helder.scene.render.LightKind;
import helder.scene.render.Lod.LodLevel;

// Lighting reference frames: lights at scale and
// their shadows, levels of detail (Scenes):
//   lights8     32 point lights over a floor of 64 tiles (one primitive: its
//               runs cut where their tiles' lists differ) round a pillar that
//               twelve reach (its eight brightest light it); its probe checks
//               the frame's lights, the pillar's list and the runs
//   clustered   128 point lights over one floor plane and its pillars
//               (ClusteredLights: each pixel its cell's lights); its twin the
//               brute force (a grid of one cell listing them all), the same
//               frame; its probe checks a frame allocates nothing; drawn by
//               the compute path where the device has one (the 3d lane, WebGPU)
//               and by the CPU's (HELDER_NO_COMPUTE=1, WebGL2), one golden
//   spotshadow  two spot lights casting (Shadows' tiles): a 3x3 filter, a disc
//   pointshadow a point light casting all round (six tiles) between pillars,
//               onto the floor and two walls
//   shadowatlas six casting local lights and the sun's two cascades in one
//               atlas, maxLocal 3: the three that matter most cast; its probe
//               checks them, that a second frame keeps their tiles (cached)
//               and that a moved caster draws its light's tiles again
//   lod         spheres of three levels (red, green, blue) along the view
//               (Lod), and a set of them in a field (InstanceCulling: culled
//               and their levels picked an instance at a time, on the GPU
//               where it can); its probe checks the levels and allocations
class LightScenes {
	public static final NAMES = ["lights8", "clustered", "spotshadow", "pointshadow", "shadowatlas", "lod"];

	public static function make(name:String, device:Device):Encoder->Void {
		var r = new Renderer(device);
		Scenes.renderer = r;
		r.clearColor = new Vec4(0.02, 0.025, 0.04, 1);
		r.sky = new Vec3(0.05, 0.055, 0.07);
		r.ground = new Vec3(0.03, 0.03, 0.03);
		var world = new World();
		var eye = world.node("eye");
		var camera = Camera.attach(eye, Camera.perspective(0.9, 0.1, 60));
		var stone = Material.lambert({color: new Vec4(0.62, 0.62, 0.64, 1)});
		return switch name {
			case "lights8":
				eye.position = new Vec3(0, 7, 8.5);
				eye.lookAt(new Vec3(0, 0.4, 0));
				var tile = Shapes.of(device, Geometry.box({width: 1.5, height: 0.1, depth: 1.5}), stone);
				for (x in 0...8)
					for (z in 0...8) {
						var n = world.node();
						n.position = new Vec3(-5.25 + x * 1.5, -0.05, -5.25 + z * 1.5);
						MeshRenderer.attach(n, tile);
					}
				var pillar = world.node("pillar");
				pillar.position = new Vec3(0, 1.25, 0);
				MeshRenderer.attach(pillar, Shapes.of(device, Geometry.box({width: 1, height: 2.5, depth: 1}), new Material("pillar", new Vec4(0.8, 0.8, 0.8, 1), 0, 0.5)));
				for (k in 0...20) {
					var a = k / 20 * Math.PI * 2;
					light(world, new Vec3(Math.cos(a) * 4.6, 0.5, Math.sin(a) * 4.6), hue(k / 20), 2.2, 2.6);
				}
				for (k in 0...12) {
					var a = (k + 0.5) / 12 * Math.PI * 2;
					light(world, new Vec3(Math.cos(a) * 1.15, 0.4 + (k % 3) * 0.8, Math.sin(a) * 1.15), hue(k / 12 + 0.5), 1.2, 1.6);
				}
				Scenes.probe = () -> {
					var l = r.frameLights;
					if (l.count != 32) return 'lights8: ${l.count} lights gathered, not 32';
					// (the pillar's list: eight, its own, by row)
					var d:Null<Renderer.DrawItem> = null;
					for (i in 0...@:privateAccess r.count)
						if (@:privateAccess r.list[i].node == pillar) d = @:privateAccess r.list[i];
					if (d == null) return "lights8: no pillar drawn";
					for (i in 0...8) {
						if (d.lights[i] < 0) return 'lights8: the pillar lit by $i lights, not 8';
						if (i > 0 && d.lights[i] <= d.lights[i - 1]) return 'lights8: the pillar\'s list not by row: ${d.lights}';
					}
					// (the floor's tiles: their runs cut by their lists, every tile's its own here)
					if (r.draws < 4 || r.draws > 65) return 'lights8: ${r.draws} draws';
					null;
				};
				enc -> r.draw(enc, world, camera, 256 / 192);
			case "clustered":
				eye.position = new Vec3(0, 6.5, 9.5);
				eye.lookAt(new Vec3(0, 0, -0.5));
				MeshRenderer.attach(world.node("floor"), Shapes.of(device, Geometry.plane({width: 16, height: 16}).rotated(-Math.PI / 2, 0, 0), stone));
				var post = Shapes.of(device, Geometry.cylinder({radiusTop: 0.25, radiusBottom: 0.25, height: 1.8, radialSegments: 16}),
					new Material("post", new Vec4(0.75, 0.72, 0.7, 1), 0, 0.45));
				for (k in 0...9) {
					var n = world.node();
					n.position = new Vec3(-4.8 + (k % 3) * 4.8, 0.9, -4.8 + Std.int(k / 3) * 4.8);
					MeshRenderer.attach(n, post);
				}
				for (i in 0...16)
					for (j in 0...8)
						light(world, new Vec3(-7.2 + i * 0.96, 0.3 + (i + j) % 3 * 0.35, -6.6 + j * 1.75), hue((i * 8 + j) * 0.618), 1.4, 1.5);
				var cl = new ClusteredLights(device, {maxLights: 128});
				r.use(cl);
				// (the brute force: one cell, every light in it)
				var brute = new Renderer(device);
				brute.clearColor = r.clearColor;
				brute.sky = r.sky;
				brute.ground = r.ground;
				brute.use(new ClusteredLights(device, {maxLights: 128, grid: {x: 1, y: 1, z: 1}, maxPerCell: 128}));
				Scenes.twin = enc -> brute.draw(enc, world, camera, 256 / 192);
				var draw = (enc:Encoder) -> r.draw(enc, world, camera, 256 / 192);
				Scenes.probe = () -> {
					// (those whose reach meets the view: all but a few past its sides)
					if (r.frameLights.count < 110 || r.frameLights.dropped > 0) return 'clustered: ${r.frameLights.count} lights, ${r.frameLights.dropped} dropped';
					if (!cl.gpu && cl.overflow > 0) return 'clustered: ${cl.overflow} lights left out of full cells';
					Sys.println('LightScenes: clustered: ' + (cl.gpu ? "on the GPU" : 'on the CPU, ${Math.round(cl.assignMs * 1000) / 1000} ms'));
					allocated(device, draw, "clustered");
				};
				draw;
			case "spotshadow":
				eye.position = new Vec3(0, 5, 7.5);
				eye.lookAt(new Vec3(0, 0.3, 0));
				var shadows = new Shadows(device, 512).local();
				r.use(shadows);
				floorAndThings(device, world, stone);
				var warm = light(world, new Vec3(-3.4, 2.2, 1.8), new Vec3(1, 0.8, 0.55), 22, 10, Spot);
				warm.innerCone = 0.45;
				warm.outerCone = 0.65;
				warm.castShadows = true;
				aim(world, warm, new Vec3(0.2, 0, -0.8));
				var cool = light(world, new Vec3(3.2, 2.8, 0.6), new Vec3(0.55, 0.7, 1), 22, 10, Spot);
				cool.innerCone = 0.4;
				cool.outerCone = 0.6;
				cool.castShadows = true;
				cool.shadow = {size: 256, radius: 2.5};
				aim(world, cool, new Vec3(-0.6, 0, -1.2));
				Scenes.probe = () -> shadows.locals.lights == 2 && shadows.locals.tilesDrawn == 2 ? null : 'spotshadow: ${shadows.locals.lights} lights, ${shadows.locals.tilesDrawn} tiles';
				enc -> r.draw(enc, world, camera, 256 / 192);
			case "pointshadow":
				eye.position = new Vec3(0.5, 5.5, 7);
				eye.lookAt(new Vec3(0, 0.6, -0.5));
				var shadows = new Shadows(device, 512).local();
				r.use(shadows);
				MeshRenderer.attach(world.node("floor"), Shapes.of(device, Geometry.plane({width: 12, height: 12}).rotated(-Math.PI / 2, 0, 0), stone));
				var wall = Shapes.of(device, Geometry.box({width: 8, height: 3, depth: 0.2}), stone);
				var back = world.node("back");
				back.position = new Vec3(0, 1.5, -3.2);
				MeshRenderer.attach(back, wall);
				var side = world.node("side");
				side.position = new Vec3(-3.4, 1.5, 0);
				side.rotation = Quat.axisAngle(new Vec3(0, 1, 0), Math.PI / 2);
				MeshRenderer.attach(side, wall);
				var pillar = Shapes.of(device, Geometry.box({width: 0.3, height: 1.6, depth: 0.3}), new Material("pillar", new Vec4(0.85, 0.6, 0.4, 1), 0, 0.6));
				for (k in 0...6) {
					var a = k / 6 * Math.PI * 2 + 0.3;
					var n = world.node();
					n.position = new Vec3(Math.cos(a) * 1.4, 0.8, Math.sin(a) * 1.4 - 0.4);
					MeshRenderer.attach(n, pillar);
				}
				var ball = world.node("ball");
				ball.position = new Vec3(0.4, 2.6, -0.6);
				MeshRenderer.attach(ball, Shapes.of(device, Geometry.sphere({radius: 0.3}), new Material("ball", new Vec4(0.5, 0.7, 0.9, 1), 0, 0.4)));
				var bulb = light(world, new Vec3(0, 1.4, -0.4), new Vec3(1, 0.85, 0.6), 22, 9);
				bulb.castShadows = true;
				Scenes.probe = () -> shadows.locals.lights == 1 && shadows.locals.tilesDrawn == 6 ? null : 'pointshadow: ${shadows.locals.lights} lights, ${shadows.locals.tilesDrawn} tiles';
				enc -> r.draw(enc, world, camera, 256 / 192);
			case "shadowatlas":
				eye.position = new Vec3(0, 6, 9);
				eye.lookAt(new Vec3(0, 0.3, 0));
				var shadows = Shadows.cascaded(device, 512, 8).local({atlas: 1024, maxLocal: 3});
				r.use(shadows);
				var things = floorAndThings(device, world, stone);
				var sun = world.node("sun");
				Light.attach(sun, Light.directional(new Vec3(0.9, 0.9, 1), 0.5));
				sun.rotation = Quat.fromEuler(-1.0, 0.6, 0);
				// (six casting lights, the nearest the camera first in its order)
				var lights:Array<Light> = [];
				for (k in 0...6) {
					var a = k / 6 * Math.PI * 2;
					var p = new Vec3(Math.cos(a) * 3, 2.4, Math.sin(a) * 3);
					var l = light(world, p, hue(k / 6), 14, 7, k % 2 == 0 ? Spot : Point);
					l.castShadows = true;
					l.shadow = {size: 256};
					if (l.kind == Spot) {
						l.innerCone = 0.4;
						l.outerCone = 0.7;
						aim(world, l, new Vec3(0, 0, 0));
					}
					lights.push(l);
				}
				var draw = (enc:Encoder) -> r.draw(enc, world, camera, 256 / 192);
				Scenes.probe = () -> {
					if (shadows.locals.lights != 3) return 'shadowatlas: ${shadows.locals.lights} lights cast, not 3';
					// (the three the frame ranks first)
					var fl = r.frameLights;
					for (k in 0...fl.count)
						if ((fl.tile(k) >= 0) != (k < 3)) return 'shadowatlas: light $k of the frame\'s ${fl.tile(k) >= 0 ? "casts" : "does not cast"}';
					var tiles = shadows.locals.tilesDrawn;
					frame(device, draw);
					if (shadows.locals.tilesKept != tiles || shadows.locals.tilesDrawn != 0) return 'shadowatlas: a second frame kept ${shadows.locals.tilesKept} tiles, drew ${shadows.locals.tilesDrawn}';
					// (a caster moved: the tiles that see it drawn again, the others kept)
					things.position = things.position + new Vec3(0.3, 0, 0);
					frame(device, draw);
					if (shadows.locals.tilesDrawn == 0) return 'shadowatlas: a moved caster drew no tile again';
					things.position = things.position - new Vec3(0.3, 0, 0);
					frame(device, draw);
					null;
				};
				draw;
			case "lod":
				eye.position = new Vec3(0, 1.6, 4);
				eye.lookAt(new Vec3(0, 0.6, -20));
				camera.far = 200;
				var sun = world.node("sun");
				Light.attach(sun, Light.directional(new Vec3(1, 0.97, 0.92), 2));
				sun.rotation = Quat.fromEuler(-0.8, 0.4, 0);
				r.sky = new Vec3(0.3, 0.33, 0.4);
				MeshRenderer.attach(world.node("floor"), Shapes.of(device, Geometry.plane({width: 40, height: 400}).rotated(-Math.PI / 2, 0, 0), stone));
				var levels:Array<LodLevel> = [
					{mesh: Shapes.of(device, Geometry.sphere({radius: 0.5, widthSegments: 32, heightSegments: 16}), Material.lambert({color: new Vec4(0.9, 0.2, 0.15, 1)})), until: 0.12},
					{mesh: Shapes.of(device, Geometry.sphere({radius: 0.5, widthSegments: 12, heightSegments: 6}), Material.lambert({color: new Vec4(0.2, 0.8, 0.25, 1)})), until: 0.05},
					{mesh: Shapes.of(device, Geometry.sphere({radius: 0.5, widthSegments: 5, heightSegments: 3}), Material.lambert({color: new Vec4(0.2, 0.35, 0.9, 1)})), until: 0.015}
				];
				// (along the view, two of each level, then one past the last: the
				// spheres' bounds' sphere 0.87 m, covering 1.8 m over their depth
				// of the view's height; the thresholds 15, 36 and 120 m off)
				var nodes = [];
				var at = [4.0, 8, 20, 28, 50, 80, 160];
				for (k in 0...at.length) {
					var n = world.node();
					n.position = new Vec3(k % 2 == 0 ? -1.4 : 1.4, 0.5, 4 - at[k]);
					Lod.attach(n, levels);
					nodes.push(n);
				}
				// (a field of them, one set: culled and levelled an instance at a time)
				var field = new InstancedMesh(levels[0].mesh, 20 * 24);
				field.levels = levels;
				for (i in 0...20)
					for (j in 0...24)
						field.setTransform(i * 24 + j, (i < 10 ? -22 : 4) + i % 10 * 2, 0.5, -2 - j * 2.6 * (1 + j * 0.04), 0, 0, 0, 1, 1);
				InstancedMesh.attach(world.node("field"), field);
				var culling = new InstanceCulling(device);
				r.use(culling);
				var draw = (enc:Encoder) -> r.draw(enc, world, camera, 256 / 192);
				Scenes.probe = () -> {
					var want = [0, 0, 1, 1, 2, 2, 3];
					for (k in 0...nodes.length)
						if (Lod.of(nodes[k]).level != want[k]) return 'lod: the sphere ${at[k]} m off at level ${Lod.of(nodes[k]).level}, not ${want[k]}';
					if (!culling.gpu && (culling.kept == 0 || culling.culled == 0)) return 'lod: the field kept ${culling.kept}, culled ${culling.culled}';
					Sys.println('LightScenes: lod: the field ' + (culling.gpu ? 'on the GPU, ${culling.dispatches} dispatch' : 'on the CPU, ${culling.kept} kept, ${culling.culled} culled'));
					allocated(device, draw, "lod");
				};
				draw;
			case _:
				throw 'LightScenes: no scene $name';
		}
	}

	// (a light at p: kind Point or Spot, its colour, intensity, range)
	static function light(world:World, p:Vec3, color:Vec3, intensity:Float, range:Float, kind = LightKind.Point):Light {
		var n = world.node();
		n.position = p;
		return Light.attach(n, kind == Spot ? Light.spot(color, intensity, range, 0.3, 0.5) : Light.pointLight(color, intensity, range));
	}

	// (a spot light's node turned to look at target)
	static function aim(world:World, l:Light, target:Vec3) {
		var store = world.store(Light.KIND);
		for (k in 0...store.length)
			if (store.valueAt(k) == l) store.nodeAt(k).lookAt(target);
	}

	// (a floor, a sphere, a box and a ring of posts; the posts' parent returned)
	static function floorAndThings(device:Device, world:World, stone:Material):Node {
		MeshRenderer.attach(world.node("floor"), Shapes.of(device, Geometry.plane({width: 14, height: 14}).rotated(-Math.PI / 2, 0, 0), stone));
		var ball = world.node("ball");
		ball.position = new Vec3(-0.6, 0.6, -0.2);
		MeshRenderer.attach(ball, Shapes.of(device, Geometry.sphere({radius: 0.6}), new Material("ball", new Vec4(0.85, 0.85, 0.85, 1), 0, 0.35)));
		var box = world.node("box");
		box.position = new Vec3(0.9, 0.45, -0.7);
		box.rotation = Quat.axisAngle(new Vec3(0, 1, 0), 0.5);
		MeshRenderer.attach(box, Shapes.of(device, Geometry.box({width: 0.9, height: 0.9, depth: 0.9}), new Material("box", new Vec4(0.8, 0.55, 0.35, 1), 0, 0.6)));
		var posts = world.node("posts");
		var post = Shapes.of(device, Geometry.box({width: 0.18, height: 1.1, depth: 0.18}), new Material("post", new Vec4(0.7, 0.75, 0.8, 1), 0, 0.5));
		for (k in 0...8) {
			var a = k / 8 * Math.PI * 2;
			var n = world.node();
			n.position = new Vec3(Math.cos(a) * 2.2, 0.55, Math.sin(a) * 2.2 - 0.3);
			posts.add(n);
			MeshRenderer.attach(n, post);
		}
		return posts;
	}

	// (a hue's colour, full saturation)
	static function hue(h:Float):Vec3 {
		h = h - Math.floor(h);
		var r = Math.abs(h * 6 - 3) - 1, g = 2 - Math.abs(h * 6 - 2), b = 2 - Math.abs(h * 6 - 4);
		return new Vec3(Math.min(Math.max(r, 0), 1), Math.min(Math.max(g, 0), 1), Math.min(Math.max(b, 0), 1));
	}

	// (a frame drawn and finished)
	static function frame(device:Device, draw:Encoder->Void) {
		var enc = device.beginFrame();
		draw(enc);
		device.endFrame();
	}

	// (the frame drawn again: once warm, nothing allocated by a frame)
	static function allocated(device:Device, draw:Encoder->Void, name:String):Null<String> {
		for (_ in 0...3)
			frame(device, draw);
		#if (target.name == "hxmc")
		var before = hxmc.GcStats.bytesAllocated();
		for (_ in 0...4)
			frame(device, draw);
		var bytes = hxmc.GcStats.bytesAllocated() - before;
		Sys.println('LightScenes: $name: $bytes bytes allocated by 4 frames');
		if (bytes != 0) return '$name: $bytes bytes allocated by 4 frames (none expected)';
		#end
		return null;
	}
}
