import helder.gfx.*;
import helder.gfx.shader.Vec2;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.*;
import helder.scene.render.*;
import helder.scene.render.PostProcess;
import StageShaders;

// Post-processing reference frames: one courtyard drawn in HDR through a
// PostProcess into the frame (renderer.post: the view buffers its effects
// ask for drawn by the renderer):
//   prepass    the view buffers themselves (ViewBuffers): depth on the
//              left, view-space normals on the right, the selected nodes
//              tinted (StageShaders' ViewsShader)
//   ssao       GTAO (Ssao) under a bright sky and a dim sun: the corners,
//              the boxes' feet and the stack's seams darkened, the sun's
//              light not
//   dof        a lens focused on the sphere (Dof.focus): the near floor and
//              the far wall and island soft
//   tiltshift  a diorama's lens (Dof.tiltShift): the band about the
//              sphere's depth sharp, the far island, which the band's rows
//              cross on the screen, blurred by its depth
//   outline    two selection groups (Outline.select): the sphere's gold
//              (through the glass pane before it), the pillar's blue and
//              wider
//   fxaa       a thin bar before the courtyard, one sample a pixel, FXAA
//              in the composite (post.antialias)
//   lut        a grade by a 16 cubed table made in code (Lut.of): teal
//              shadows, warm highlights
//   effects    all of them at once with bloom; its probe draws it again
//              and checks that a frame allocates nothing (hxmc.GcStats)
// Debugging: HXMC_SHOW=ao shows ssao's occlusion instead of its frame;
// HXMC_FX=ao,dof,... the effects frame's effects (all by default);
// HXMC_ALLOC=1 its probe's allocations apart (an empty frame, the
// renderer's alone). "views" (the view buffers alone) is EffectBench's.
class EffectScenes {
	public static final NAMES = ["prepass", "ssao", "dof", "tiltshift", "outline", "fxaa", "lut", "effects"];

	public static function make(name:String, device:Device):Encoder->Void {
		var r = new Renderer(device, true, 1, true);
		Scenes.renderer = r;
		// (a dark sky: GfxTest takes a dark corner and a lit middle as drawn)
		r.clearColor = new Vec4(0.02, 0.03, 0.06, 1);
		r.sunColor = new Vec3(1.6, 1.5, 1.35);
		r.sunDirection = new Vec3(-0.5, 0.9, 0.35);
		r.sky = new Vec3(0.5, 0.58, 0.72);
		r.ground = new Vec3(0.22, 0.2, 0.18);
		if (name == "ssao") {
			// (the indirect light most of it: what AO darkens)
			r.sunColor = new Vec3(0.35, 0.33, 0.3);
			r.sky = new Vec3(1.1, 1.15, 1.25);
			r.ground = new Vec3(0.5, 0.46, 0.42);
		}
		var post = new PostProcess(device, RGBA8, true);
		post.bloom = name == "effects" ? 0.05 : 0;
		r.post = post;
		var world = new World();
		var s = courtyard(world, device, name == "fxaa");
		var eye = world.node("eye");
		var camera = Camera.attach(eye, Camera.perspective(0.85, 0.1, 60));
		eye.position = new Vec3(0.2, 1.7, 6.2);
		eye.lookAt(new Vec3(0, 0.8, 0));
		switch name {
			case "ssao":
				post.ao = new Ssao({radius: 1.0, intensity: 2, samples: 8, slices: 2, halfRes: true});
			case "dof":
				post.dof = Dof.focus({distance: 6.2, aperture: 0.04, radius: 0.025});
			case "tiltshift":
				post.dof = Dof.tiltShift({band: 0.15, falloff: 0.35, strength: 1, radius: 0.02});
			case "outline":
				post.outline = new Outline({width: 2, color: new Vec4(1, 0.78, 0.15, 1)});
				post.outline.group(2, new Vec4(0.25, 0.65, 1, 1), 3);
				Outline.select(s.sphere, 1);
				Outline.select(s.pillar, 2);
			case "fxaa":
				post.antialias = Fxaa;
			case "lut":
				post.lut = Lut.of(device, 16, grade);
			// (EffectBench's: the view buffers alone, at half size, no effect reading them)
			case "views":
				ViewBuffers.of(r).scale = 0.5;
			// (EffectBench's, phase 7's on the same courtyard: each effect alone)
			case "bench-ssr":
				post.ssr = new Ssr();
			case "bench-taa":
				post.taa = new Taa();
			case "bench-smaa":
				post.smaa = new Smaa();
			case "bench-motion" | "bench-objects":
				post.motionBlur = new MotionBlur({objects: name == "bench-objects"});
			case "bench-godrays":
				// (a sun before the camera, low)
				r.sunDirection = new Vec3(0.2, 0.25, -1);
				post.godRays = new GodRays();
			case "bench-occlusion":
				r.use(new Occlusion(device));
				for (n in ["box", "box2", "stack1", "stack2", "stack3", "sphere", "pillar", "island", "islandTop"])
					Occlusion.test(world.root.find(n));
			case "effects":
				// (HXMC_FX: the effects on, by their names; all by default)
				var on = (Sys.getEnv("HXMC_FX") ?? "ao,dof,outline,fxaa,lut").split(",");
				if (on.contains("ao")) post.ao = new Ssao({radius: 0.6, intensity: 1.3, samples: 6, slices: 1});
				if (on.contains("dof")) post.dof = Dof.tiltShift({band: 0.2, falloff: 0.4, strength: 0.8, radius: 0.015});
				if (on.contains("outline")) {
					post.outline = new Outline({width: 2, color: new Vec4(1, 0.78, 0.15, 1)});
					Outline.select(s.sphere, 1);
				}
				if (on.contains("fxaa")) post.antialias = Fxaa;
				if (on.contains("lut")) {
					post.lut = Lut.of(device, 16, grade);
					post.lut.strength = 0.6;
				}
			case _:
		}
		var w = device.width, h = device.height;
		var light = device.createTexture({width: w, height: h, format: RGBA16F, renderTarget: true});
		var depth = device.createTexture({width: w, height: h, format: Depth32F});
		if (name == "prepass") {
			// (the view buffers whole, shown instead of the frame)
			var views = ViewBuffers.of(r);
			views.scale = 1;
			Outline.select(s.sphere, 1);
			var pipeline = device.createPipeline(ViewsShader.pipeline({}));
			var v = ViewsShader.vertexBytes([{pos: new Vec2(-1, -1)}, {pos: new Vec2(3, -1)}, {pos: new Vec2(-1, 3)}]);
			var triangle = device.createBuffer({size: v.length, usage: Vertex, data: v});
			var nearest = device.createSampler({filter: Nearest, wrap: Clamp});
			var bytes = haxe.io.Bytes.alloc(ViewsShader.uniforms[0].size);
			var pass:PassDesc = {colors: [{load: Clear, clear: new Vec4(0, 0, 0, 1)}]};
			Scenes.probe = () -> r.prepassDraws > 0 && views.width == w ? null : 'prepass: ${r.prepassDraws} draws, ${views.width} wide';
			return enc -> {
				r.drawInto(enc, world, camera, light, depth, w, h);
				ViewsShader.params.views.write({inverseProjection: views.inverseProjection, far: new Vec4(24, 0, 0, 0)}, bytes);
				enc.beginPass(pass);
				enc.setPipeline(pipeline);
				enc.setUniforms(ViewsShader.uniforms[0].binding, bytes);
				enc.setTexture(ViewsShader.params.depth.binding, views.depth, nearest);
				enc.setTexture(ViewsShader.params.normals.binding, views.normals, nearest);
				enc.setVertexBuffer(0, triangle);
				enc.draw(3);
				enc.endPass();
			};
		}
		// (motion blur's bench: the camera swaying, a frame's motion every frame)
		var sway = name == "bench-motion" || name == "bench-objects", t = 0.0;
		var draw = (enc:Encoder) -> {
			if (sway) {
				t += 1;
				eye.position = new Vec3(0.2 + Math.sin(t) * 0.15, 1.7, 6.2);
				eye.lookAt(new Vec3(0, 0.8, 0));
			}
			r.drawInto(enc, world, camera, light, depth, w, h);
			post.run(enc, light, null, w, h);
		};
		if (name == "effects") Scenes.probe = () -> {
			// (HXMC_ALLOC=1: what a frame allocates, apart: an empty one, the renderer's alone)
			if (Sys.getEnv("HXMC_ALLOC") == "1") {
				allocated(device, enc -> {});
				allocated(device, enc -> r.drawInto(enc, world, camera, light, depth, w, h));
			}
			allocated(device, draw);
		};
		if (Sys.getEnv("HXMC_SHOW") == "ao" && post.ao != null) {
			// (debugging: the occlusion over the frame)
			var pipeline = device.createPipeline(ShowShader.pipeline({}));
			var v = ShowShader.vertexBytes([{pos: new Vec2(-1, -1)}, {pos: new Vec2(3, -1)}, {pos: new Vec2(-1, 3)}]);
			var triangle = device.createBuffer({size: v.length, usage: Vertex, data: v});
			var sampler = device.createSampler({filter: Linear, wrap: Clamp});
			var pass:PassDesc = {colors: [{load: Clear, clear: new Vec4(0, 0, 0, 1)}]};
			return enc -> {
				draw(enc);
				enc.beginPass(pass);
				enc.setPipeline(pipeline);
				enc.setTexture(ShowShader.textures[0].binding, post.ao.texture, sampler);
				enc.setVertexBuffer(0, triangle);
				enc.draw(3);
				enc.endPass();
			};
		}
		return draw;
	}

	// (the frame drawn again: once warm, nothing allocated by a frame; and the passes counted)
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
		var r = Scenes.renderer;
		Sys.println('EffectScenes: effects: ${r.prepassDraws} prepass draws, ${r.post.draws} post draws a frame');
		Sys.println('EffectScenes: $bytes bytes allocated by 4 frames');
		if (bytes != 0) return 'effects: $bytes bytes allocated by 4 frames (none expected)';
		#end
		return null;
	}

	// a grade (display values): teal shadows, warm highlights, a little more saturation
	static function grade(r:Float, g:Float, b:Float):Vec3 {
		var y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
		var t = y * y * (3 - 2 * y);
		var sr = y + (r - y) * 1.25, sg = y + (g - y) * 1.25, sb = y + (b - y) * 1.25;
		return new Vec3(sr + (1 - t) * -0.03 + t * 0.06, sg + (1 - t) * 0.02 + t * 0.02, sb + (1 - t) * 0.06 - t * 0.05);
	}

	// the courtyard: a floor, a back wall, boxes on the floor and stacked,
	// a sphere, a pillar, a glass pane, a far island; thin: bars and boxes
	// turned (FXAA's edges)
	static function courtyard(world:World, device:Device, thin:Bool):{sphere:Node, pillar:Node} {
		function put(name:String, mesh:Mesh, x:Float, y:Float, z:Float, ?turn:Float):Node {
			var n = world.node(name);
			n.position = new Vec3(x, y, z);
			if (turn != null) n.rotation = helder.scene.math.Quat.axisAngle(new Vec3(0, 1, 0), turn);
			MeshRenderer.attach(n, mesh);
			return n;
		}
		var stone = new Material("stone", new Vec4(0.72, 0.68, 0.62, 1), 0, 0.85);
		var clay = new Material("clay", new Vec4(0.85, 0.45, 0.3, 1), 0, 0.6);
		var moss = new Material("moss", new Vec4(0.35, 0.6, 0.35, 1), 0, 0.7);
		put("floor", Shapes.plane(device, new Material("floor", new Vec4(0.6, 0.6, 0.58, 1), 0, 0.9), 60), 0, 0, -10);
		put("wall", Shapes.box(device, stone, 9, 3, 0.4), 0, 1.5, -2.6);
		var box = Shapes.box(device, clay, 1, 1, 1);
		put("box", box, -1.9, 0.5, -0.6, 0.4);
		put("box2", box, -2.6, 0.5, -2.0);
		var small = Shapes.box(device, moss, 0.5, 0.5, 0.5);
		put("stack1", small, 2.4, 0.25, -1.4);
		put("stack2", small, 2.4, 0.75, -1.4, 0.3);
		put("stack3", small, 2.95, 0.25, -1.4);
		var sphere = put("sphere", Shapes.sphere(device, new Material("ball", new Vec4(0.9, 0.85, 0.8, 1), 0, 0.35), 0.6, 32, 16), -0.1, 0.6, 0.2);
		var pillar = put("pillar", Shapes.box(device, stone, 0.45, 2.6, 0.45), 1.3, 1.3, -0.9);
		var glass = new Material("glass", new Vec4(0.6, 0.8, 0.9, 0.35), 0, 0.1);
		glass.blend = true;
		glass.doubleSided = true;
		put("pane", Shapes.box(device, glass, 1.2, 1.4, 0.04), 0.6, 0.75, 1.4, -0.3);
		// (the island: far behind, its rows the sphere's on the screen)
		var island = Shapes.box(device, moss, 3, 1.2, 2.5);
		put("island", island, -3.5, 0.6, -18);
		put("islandTop", Shapes.sphere(device, clay, 1.1, 24, 12), -3.2, 1.6, -18);
		// (FXAA's: one bar, the courtyard's own edges besides)
		if (thin) put("bar", Shapes.box(device, new Material("bar", new Vec4(0.08, 0.08, 0.1, 1), 0, 0.5), 0.07, 2.2, 0.07), -0.9, 1.6, 1.2, 0.3);
		return {sphere: sphere, pillar: pillar};
	}
}
