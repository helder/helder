import helder.gfx.*;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.*;
import helder.scene.render.*;
import helder.scene.render.PostProcess;
import helder.scene.render.PostEffects;
import StageShaders;

// High-end rendering reference frames (Scenes),
// each drawn in HDR through a PostProcess into the frame:
//   ssr         screen-space reflections (Ssr): a dark polished floor and a
//               mirror of metal reflecting coloured blocks, a sphere and
//               the back wall
//   taa         temporal antialiasing (post.taa: Taa): thin bars and
//               a fence, one sample a pixel, a still after 8 frames (each
//               jittered, gathered with its history), drawn again from a
//               cut each time (PostProcess.resetHistory): the same pixels
//               whatever the frames before
//   smaa        SMAA (post.smaa: Smaa) on turned boxes and spheres
//   motionblur  motion blur by objects (MotionBlur, objects: the view
//               buffers' motion): the camera panning, a box flying across
//               and a wheel turning; two frames drawn, the second's shown
//   godrays     god rays (GodRays): a low sun in a sky (Sky) behind a row
//               of pillars and a wall with windows
//   occlusion   occlusion culling (Occlusion): a wall before a crowd of
//               boxes, those behind it culled once their queries answer (a
//               frame or more late); the frame the same as without, the
//               culled counted (Renderer.occluded, --stats' occluded)
// Each frame's probe checks what it drew (its passes, its draws) and that
// a frame, once warm, allocates nothing (hxmc.GcStats).
class HighEndScenes {
	public static final NAMES = ["ssr", "taa", "smaa", "motionblur", "godrays", "occlusion"];

	public static function make(name:String, device:Device):Encoder->Void {
		var r = new Renderer(device, true, 1, true);
		Scenes.renderer = r;
		r.clearColor = new Color(0.02, 0.03, 0.06, 1);
		r.sunColor = new Vec3(1.6, 1.5, 1.35);
		r.sunDirection = new Vec3(-0.5, 0.9, 0.35);
		r.sky = new Vec3(0.45, 0.52, 0.66);
		r.ground = new Vec3(0.2, 0.18, 0.16);
		var post = new PostProcess(device, RGBA8, true);
		post.bloom = 0;
		r.post = post;
		var world = new World();
		var eye = world.node("eye");
		var camera = Camera.attach(eye, Camera.perspective(0.85, 0.1, 60));
		var w = device.width, h = device.height;
		var light = device.createTexture({width: w, height: h, format: RGBA16F, renderTarget: true});
		var depth = device.createTexture({width: w, height: h, format: Depth32F});
		var frame = (enc:Encoder) -> {
			r.drawInto(enc, world, camera, light, depth, w, h);
			post.run(enc, light, null, w, h);
			// (debugging: HXMC_SHOW=edges, weights (SMAA's), motion (the view buffers'), rays: a texture over the frame)
			var show = Sys.getEnv("HXMC_SHOW");
			if (show != null) Show.texture(device, enc, switch show {
				case "edges": @:privateAccess cast(cast(@:privateAccess post.fx, PostFx).smaaPass, SmaaPass).edges;
				case "weights": @:privateAccess cast(cast(@:privateAccess post.fx, PostFx).smaaPass, SmaaPass).weights;
				case "motion": ViewBuffers.of(r).motion;
				case "rays": post.godRays.texture;
				case "prep" | "tiles" | "neighbours": @:privateAccess cast(cast(@:privateAccess post.fx, PostFx).blurPass, MotionBlurPass).targets[show == "prep" ? 0 : show == "tiles" ? 1 : 2];
				case _: null;
			});
		};
		switch name {
			case "ssr":
				reflections(world, device);
				eye.position = new Vec3(0.4, 1.5, 5.6);
				eye.lookAt(new Vec3(0, 0.5, 0));
				post.ssr = new Ssr({maxDistance: 10, thickness: 0.3, steps: 40});
				Scenes.probe = () -> post.draws >= 3 && post.ssr.texture != null ? allocated(device, frame) : 'ssr: ${post.draws} post draws';
				return frame;
			case "taa" | "smaa":
				if (name == "taa") bars(world, device) else shapes(world, device);
				eye.position = new Vec3(0.3, 1.4, 5.2);
				eye.lookAt(new Vec3(0, 1, 0));
				if (name == "smaa") {
					// (HXMC_AA=none: the same without, to compare)
					if (Sys.getEnv("HXMC_AA") != "none") post.smaa = new Smaa();
					Scenes.probe = () -> post.draws == 3 ? allocated(device, frame) : 'smaa: ${post.draws} post draws (the edges, the weights, the composite)';
					return frame;
				}
				post.taa = new Taa();
				// (8 frames from a cut, the jitter's whole cycle: a still, the same each time drawn)
				var still = (enc:Encoder) -> {
					post.resetHistory();
					for (_ in 0...8)
						frame(enc);
				};
				Scenes.probe = () -> {
					var v = ViewBuffers.of(r);
					v.velocity == false && v.motion != null && r.jitter.x != 0 ? allocated(device, still) : 'taa: no motion or jitter';
				};
				return still;
			case "motionblur":
				var moving = motion(world, device);
				post.motionBlur = new MotionBlur({strength: 0.8, samples: 16, max: 0.08, objects: true});
				// (two frames a draw: the second's motion is from the first's places)
				function place(t:Float) {
					// (the camera turned, not moved: what is near and far moves alike)
					eye.position = new Vec3(0, 1.6, 6);
					eye.lookAt(new Vec3(-0.08 + t * 0.16, 0.8, 0));
					moving.box.position = new Vec3(-1.6 + t * 1.2, 1.23 + t * 0.1, 0.6);
					moving.wheel.rotation = helder.scene.math.Quat.axisAngle(new Vec3(0, 0, 1), t * 0.9);
				}
				var moved = (enc:Encoder) -> {
					place(0);
					frame(enc);
					place(1);
					frame(enc);
				};
				Scenes.probe = () -> ViewBuffers.of(r).motionDraws > 0 && post.draws >= 5 ? allocated(device, moved) : 'motionblur: no motion pass';
				return moved;
			case "godrays":
				var sky = new Sky(device);
				sky.zenith = new Vec3(0.01, 0.015, 0.04);
				sky.horizon = new Vec3(0.7, 0.45, 0.28);
				sky.ground = new Vec3(0.05, 0.045, 0.04);
				sky.sunColor = new Vec3(4, 3, 1.6);
				r.use(sky);
				r.sunDirection = new Vec3(0.1, 0.22, -1);
				r.sunColor = new Vec3(1.8, 1.4, 0.9);
				r.sky = new Vec3(0.18, 0.18, 0.24);
				r.ground = new Vec3(0.06, 0.05, 0.045);
				post.godRays = new GodRays({intensity: 0.45, density: 0.9, decay: 0.97, samples: 40});
				post.bloom = 0.03;
				pillars(world, device);
				eye.position = new Vec3(0, 1.6, 7);
				eye.lookAt(new Vec3(0, 2.2, -10));
				Scenes.probe = () -> post.godRays.texture != null ? allocated(device, frame) : 'godrays: no shafts drawn';
				return frame;
			case "occlusion":
				var crowd = occluders(world, device);
				var o = new Occlusion(device);
				r.use(o);
				for (n in crowd)
					Occlusion.test(n);
				eye.position = new Vec3(0, 1.4, 6);
				eye.lookAt(new Vec3(0, 1.2, 0));
				// (a frame drawn again until the queries answer: what is behind the wall culled)
				Scenes.probe = () -> {
					var culled = 0;
					for (_ in 0...20) {
						var enc = device.beginFrame();
						frame(enc);
						device.endFrame();
						culled = r.occluded;
						if (culled > 0) break;
					}
					culled >= 20 ? allocated(device, frame) : 'occlusion: ${culled} culled (of 30 behind the wall)';
				};
				// (the same frame without occlusion: the culled draws were hidden)
				Scenes.twin = enc -> {
					o.enabled = false;
					frame(enc);
				};
				return frame;
			case _:
				throw 'HighEndScenes: no scene $name';
		}
	}

	// (the frame drawn again: once warm, nothing allocated by a frame)
	static function allocated(device:Device, draw:Encoder->Void):Null<String> {
		for (_ in 0...3) {
			var enc = device.beginFrame();
			draw(enc);
			device.endFrame();
		}
		#if (target.name == "hxmc")
		var before = hxmc.GcStats.bytesAllocated();
		for (_ in 0...4) {
			var enc = device.beginFrame();
			draw(enc);
			device.endFrame();
		}
		var bytes = hxmc.GcStats.bytesAllocated() - before;
		Sys.println('HighEndScenes: $bytes bytes allocated by 4 frames');
		if (bytes != 0) return '$bytes bytes allocated by 4 frames (none expected)';
		#end
		return null;
	}

	static function put(world:World, name:String, mesh:Mesh, x:Float, y:Float, z:Float, ?turn:Float):Node {
		var n = world.node(name);
		n.position = new Vec3(x, y, z);
		if (turn != null) n.rotation = helder.scene.math.Quat.axisAngle(new Vec3(0, 1, 0), turn);
		MeshRenderer.attach(n, mesh);
		return n;
	}

	// a dark polished floor, a mirror of metal standing on it, coloured
	// blocks, a sphere, a back wall
	static function reflections(world:World, device:Device) {
		var floor = new Material("polished", new Vec4(0.08, 0.08, 0.09, 1), 0.2, 0.08);
		put(world, "floor", Shapes.plane(device, floor, 40), 0, 0, -6);
		put(world, "wall", Shapes.box(device, new Material("wall", new Vec4(0.7, 0.66, 0.6, 1), 0, 0.85), 10, 3.6, 0.3), 0, 1.75, -3);
		var mirror = new Material("mirror", new Vec4(0.95, 0.95, 0.95, 1), 1, 0.02);
		put(world, "mirror", Shapes.box(device, mirror, 1.6, 1.6, 0.06), 2.2, 0.85, -1.2, -0.6);
		var colors = [new Vec4(0.85, 0.25, 0.2, 1), new Vec4(0.2, 0.6, 0.3, 1), new Vec4(0.25, 0.4, 0.85, 1), new Vec4(0.9, 0.75, 0.2, 1)];
		for (k in 0...4)
			put(world, "block", Shapes.box(device, new Material("block", colors[k], 0, 0.6), 0.6, 0.6 + k * 0.3, 0.6), -2.2 + k * 1.0, 0.3 + k * 0.15, -1.4 + (k % 2) * 0.5, k * 0.3);
		put(world, "ball", Shapes.sphere(device, new Material("ball", new Vec4(0.9, 0.9, 0.85, 1), 0, 0.3), 0.45, 32, 16), 0.2, 0.45, 0.6);
	}

	// thin bars and a fence before a wall, a sphere: edges for antialiasing
	static function bars(world:World, device:Device) {
		put(world, "floor", Shapes.plane(device, new Material("floor", new Vec4(0.55, 0.55, 0.52, 1), 0, 0.9), 40), 0, 0, -6);
		put(world, "wall", Shapes.box(device, new Material("wall", new Vec4(0.75, 0.72, 0.66, 1), 0, 0.85), 9, 3.1, 0.3), 0, 1.5, -2.4);
		var dark = new Material("bar", new Vec4(0.07, 0.07, 0.09, 1), 0, 0.5);
		var bar = Shapes.box(device, dark, 0.06, 2.4, 0.06);
		for (k in 0...4)
			put(world, "bar", bar, -1.35 + k * 0.9, 1.2, 0.4, 0.2 + k * 0.15);
		var rail = Shapes.box(device, dark, 3.6, 0.05, 0.05);
		put(world, "rail", rail, 0, 2.2, 0.35, 0.12);
		put(world, "ball", Shapes.sphere(device, new Material("ball", new Vec4(0.85, 0.4, 0.25, 1), 0, 0.4), 0.5, 32, 16), 1.6, 0.5, -0.8);
	}

	// turned boxes, spheres and a wedge before a wall: edges of every slope
	// (SMAA's: short runs, steps a few pixels long)
	static function shapes(world:World, device:Device) {
		put(world, "floor", Shapes.plane(device, new Material("floor", new Vec4(0.55, 0.55, 0.52, 1), 0, 0.9), 40), 0, 0, -6);
		put(world, "wall", Shapes.box(device, new Material("wall", new Vec4(0.75, 0.72, 0.66, 1), 0, 0.85), 9, 3.1, 0.3), 0, 1.5, -2.4);
		var dark = new Material("dark", new Vec4(0.08, 0.08, 0.1, 1), 0, 0.5);
		var clay = new Material("clay", new Vec4(0.85, 0.4, 0.25, 1), 0, 0.5);
		for (k in 0...4) {
			var n = put(world, "box", Shapes.box(device, k % 2 == 0 ? dark : clay, 0.7, 0.7, 0.7), -1.9 + k * 1.25, 1.3 + (k % 2) * 0.5, -0.6, 0.35 + k * 0.4);
			n.rotation = helder.scene.math.Quat.fromEuler(0.5 + k * 0.3, 0.35 + k * 0.4, 0.2 * k);
		}
		put(world, "ball", Shapes.sphere(device, dark, 0.45, 32, 16), -0.6, 0.45, 0.6);
		put(world, "ball2", Shapes.sphere(device, clay, 0.35, 32, 16), 1.4, 0.35, 0.8);
	}

	// a courtyard with a box that flies and a wheel that turns
	static function motion(world:World, device:Device):{box:Node, wheel:Node} {
		put(world, "floor", Shapes.plane(device, new Material("floor", new Vec4(0.55, 0.55, 0.52, 1), 0, 0.9), 40), 0, 0, -6);
		put(world, "wall", Shapes.box(device, new Material("wall", new Vec4(0.75, 0.72, 0.66, 1), 0, 0.85), 9, 3.1, 0.3), 0, 1.5, -2.4);
		var stripes = new Material("stripe", new Vec4(0.15, 0.2, 0.5, 1), 0, 0.6);
		for (k in 0...6)
			put(world, "post", Shapes.box(device, stripes, 0.12, 2.4, 0.12), -2.5 + k * 1.0, 1.2, -2.0);
		var box = put(world, "box", Shapes.box(device, new Material("box", new Vec4(0.9, 0.35, 0.2, 1), 0, 0.5), 0.7, 0.7, 0.7), -1.6, 1.23, 0.6, 0.15);
		var wheel = world.node("wheel");
		wheel.position = new Vec3(1.6, 1.1, 0.2);
		var spoke = Shapes.box(device, new Material("spoke", new Vec4(0.95, 0.85, 0.3, 1), 0, 0.5), 1.6, 0.14, 0.14);
		for (k in 0...3) {
			var s = world.node("spoke", wheel);
			s.rotation = helder.scene.math.Quat.axisAngle(new Vec3(0, 0, 1), k * Math.PI / 3);
			// (each a little before the last: not one plane, whose overlaps any rasterizer breaks its own way)
			s.position = new Vec3(0, 0, k * 0.03);
			MeshRenderer.attach(s, spoke);
		}
		return {box: box, wheel: wheel};
	}

	// pillars and a wall with windows against a low sun
	static function pillars(world:World, device:Device) {
		var stone = new Material("stone", new Vec4(0.35, 0.3, 0.28, 1), 0, 0.85);
		put(world, "floor", Shapes.plane(device, new Material("floor", new Vec4(0.3, 0.28, 0.25, 1), 0, 0.9), 80), 0, 0, -10);
		var pillar = Shapes.box(device, stone, 0.5, 5, 0.5);
		for (k in 0...7)
			put(world, "pillar", pillar, -4.5 + k * 1.5, 2.5, -4);
		var beam = Shapes.box(device, stone, 10, 0.5, 0.6);
		put(world, "beam", beam, 0, 5.2, -4);
		// (a lintel near the eye, across the frame's top: a doorway's dark frame)
		put(world, "lintel", Shapes.box(device, new Material("lintel", new Vec4(0.015, 0.012, 0.012, 1), 0, 0.9), 12, 1.4, 0.4), 0, 3.4, 4.2);
		var tree = Shapes.sphere(device, new Material("crown", new Vec4(0.15, 0.25, 0.12, 1), 0, 0.9), 1.4, 24, 12);
		put(world, "crown", tree, -3, 3.2, -9);
		put(world, "crown2", tree, 3.5, 2.6, -11);
	}

	// a wall before a crowd of 30 boxes (behind it) and 6 beside it (in view)
	static function occluders(world:World, device:Device):Array<Node> {
		put(world, "floor", Shapes.plane(device, new Material("floor", new Vec4(0.55, 0.55, 0.52, 1), 0, 0.9), 40), 0, 0, -6);
		put(world, "wall", Shapes.box(device, new Material("wall", new Vec4(0.75, 0.72, 0.66, 1), 0, 0.85), 4.5, 3.3, 0.3), 0, 1.6, 1);
		var crowd = [];
		var clay = new Material("clay", new Vec4(0.85, 0.45, 0.3, 1), 0, 0.6);
		var moss = new Material("moss", new Vec4(0.35, 0.6, 0.35, 1), 0, 0.7);
		// (distinct meshes: one draw each, not one instanced run)
		for (k in 0...30)
			crowd.push(put(world, "hidden", Shapes.box(device, clay, 0.4, 0.4 + (k % 3) * 0.2, 0.4), -1.6 + (k % 6) * 0.65, 0.3, -1.2 - Std.int(k / 6) * 0.7));
		for (k in 0...6)
			crowd.push(put(world, "seen", Shapes.box(device, moss, 0.5, 0.5, 0.5), k < 3 ? -3.2 + k * 0.4 : 2.4 + (k - 3) * 0.4, 0.25, 0.5 + (k % 3) * 0.3));
		return crowd;
	}
}

// (debugging: a texture shown over the frame)
class Show {
	static var pipeline:Null<Pipeline> = null;
	static var triangle:Null<Buffer> = null;
	static var sampler:Null<Sampler> = null;

	public static function texture(device:Device, enc:Encoder, t:Null<Texture>) {
		if (t == null) return;
		if (pipeline == null) {
			pipeline = device.createPipeline(ShowColorShader.pipeline({}));
			var v = ShowColorShader.vertexBytes([{pos: new helder.gfx.shader.Vec2(-1, -1)}, {pos: new helder.gfx.shader.Vec2(3, -1)}, {pos: new helder.gfx.shader.Vec2(-1, 3)}]);
			triangle = device.createBuffer({size: v.length, usage: Vertex, data: v});
			sampler = device.createSampler({filter: Nearest, wrap: Clamp});
		}
		enc.beginPass({colors: [{load: Clear, clear: new Color(0, 0, 0, 1)}]});
		enc.setPipeline(pipeline);
		enc.setTexture(ShowColorShader.textures[0].binding, t, sampler);
		enc.setVertexBuffer(0, triangle);
		enc.draw(3);
		enc.endPass();
	}
}
