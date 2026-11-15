import helder.gfx.*;
import helder.gfx.shader.Vec3;
import helder.asset.Asset;
import helder.asset.Assets;
import helder.scene.*;
import helder.scene.gltf.*;
import helder.scene.render.*;
import helder.scene.math.MathTools;
import StageShaders;

// packages/3d's test scenes (RenderTest natively, SceneWebTest in the
// browser), each a frame against tests/3d/<name>.png:
//   gltf   the sample glTF scene (examples/sample.glb) from its camera,
//          lit by the renderer's sun and sky
//   shadows the same with a shadow map (Shadows, 512x512)
//   physics helder.physics' Falling example after STEPS steps
//   instances 169 nodes on two meshes: instanced draws (RenderTest checks
//          their count)
//   skin   the skinned sample (examples/skinned.glb) bent by its animation,
//          casting its shadow
//   overlay the sample scene under the debug overlay (FrameStats, Overlay)
//   textured the textured sample (a PNG in the file, decoded by helder.image)
//   normals  the normal-mapped sample (NormalMaps, tangents computed)
//   blend    see-through materials over opaque ones, farthest first
//   packedskin, packednormals  the skinned and the normal-mapped samples
//            packed at build time (Pack: skins, animations, images,
//            tangents): skin.png's and normals.png's frames
//   cascades two shadow cascades over a long street of pillars: sharp near
//            the camera, the whole street's map beyond
//   bloom    emissive spheres and a bar far brighter than white, drawn in
//            HDR (Renderer.hdr: RGBA16F) and through a PostProcess: bloom
//            down and up its chain, ACES, a grade and a vignette
//   environment  spheres from mirror to rough, metal and not, lit by an
//            environment map (Environment) drawn behind them
//   morph    the morph sample's targets played by its animation at 1.5 s
//            (half the bump, half the wave), two instances, one bent apart
//   chains   physics' Chains example after 1.2 s: the ball through the chains
//   walker   physics' Walker example: the character walked through the crates, jumping
//   packed the sample scene from the asset step's packed file: gltf.png
//   spot   two spot lights and a point light, no sun
//   sky    the shadows scene under a sky (Sky, drawn at an injection point)
//   lazy   the skinned sample loaded in the background (Model.of(path, Lazy))
//   orbits the Orbits example (shapes made in code on a scene graph, a
//          directional Light) at TIME seconds
//   crystal a planet lit from the side, blocks standing on it all round
//          (Material.ground: dark past its terminator; Material.air towards
//          its limb; tinted per node, MeshRenderer.tint, in one instanced
//          draw) and faceted crystals (Material.crystal, see-through) on
//          its day and night sides
//   khrtransform, khrclearcoat  Khronos' TextureTransformTest and
//          ClearCoatTest (glTF-Sample-Assets: CC0 Microsoft; CC BY 4.0 Ed
//          Mackey) lit by a prefiltered studio (studio-ibl.png: Poly Haven's
//          studio_small_09, CC0, examples/gltf-showcase/envbake.py)
//   packedbc, packedastc  the textured sample packed with its texture
//          compressed (Pack --textures bc, astc)
//   compressed a pattern as RGBA8, BC1, BC3 and ASTC 4x4 (helder.image's
//          BlockCompress, Images.compressed), each on a quad
//   instancedmesh 400 cubes of one InstancedMesh in a spiral, each turned,
//          scaled and coloured from flat arrays: one instanced draw,
//          casting shadows on a floor; another set out of view, culled
//   fog    two rows of pillars into a dusk's fog (Renderer.fog: a start,
//          thinner upwards) under a sky it fogs to the far plane, drawn in
//          HDR through a PostProcess; a glowing sign far off that it does
//          not cover (Material.fog off)
//   poststage the bloom scene through a PostProcess with two stages of
//          its own (StageShaders, PostProcess.add): a sepia grade into a
//          target between, then scanlines into the frame
//   unevenscale boxes and spheres scaled unevenly and turned, on two
//          meshes: one instanced draw each (normals by the instance
//          matrix's inverse transpose), the shadow map's casters batched
//          too; its twin, drawn with renderer.instancing off (each node
//          alone, its normal matrix from the CPU), the same frame
//   softshadows Shadows.cascaded's soft filter (soft: taps on a disc, a
//          blocker search, the penumbra widening away from the caster):
//          pillars, slabs on stems and balls down a street, sharp where
//          they stand, soft under the slabs, in both cascades
//   shading  the shading models in a row, a sphere each (Material's
//          factories): unlit, matcap, normals, depth, Lambert, Blinn-Phong,
//          pbr, under a sun and a blue point light
//   primitives every Geometry generator, smooth (their normals as
//          colours: Material.normals) and flat (flat: true, Lambert's light);
//          its TypeScript twin, tests/3d/ts/twins.ts, the same frame
//   toon   Material.toon: three bands of the sun's light and its soft
//          shadow (Shadows.soft) banded with it, a point light's bands;
//          its TypeScript twin too
//   sprites Sprites: trees turning about y (Axis, an atlas' two cells, cut
//          out), clouds facing the camera (see-through, sorted), lamps'
//          additive halos; its draws checked (one a set)
//   hemisphere a hemisphere light alone (Light.hemisphere): Lambert's,
//          pbr's and a rough metal's spheres and boxes
//   prepass, ssao, dof, tiltshift, outline, fxaa, lut, effects  the view
//          buffers and post's effects (EffectScenes)
//   lines, debugdraw, helpers, text3d  lines with width, debug drawing, the
//          helpers, text in the world (LineScenes)
class Scenes {
	public static final NAMES = ["gltf", "orbits", "shadows", "physics", "instances", "skin", "overlay", "textured", "packed", "spot", "sky", "lazy", "normals", "blend", "walker", "packedskin", "packednormals", "cascades", "environment", "morph", "chains", "packedmorph", "bloom", "normalgrid", "gpuparticles", "crystal", "khrtransform", "khrclearcoat", "compressed", "packedbc", "packedastc", "instancedmesh", "glow", "tsscene", "fog", "poststage", "unevenscale", "softshadows", "shading", "primitives", "toon", "sprites", "hemisphere"].concat(EffectScenes.NAMES).concat(LineScenes.NAMES);
	// whether the last scene has what it draws (a lazy one: once its files loaded)
	public static var ready:Void->Bool = () -> true;
	// the last scene's renderer (its statistics: RenderTest)
	public static var renderer:Null<Renderer>;
	// the last scene's own checks beyond its frame (RenderTest; null: none)
	public static var probe:Null<Void->String>;
	// the last scene drawn another way that must give the same frame
	// (RenderTest, after the first and its probe; null: none)
	public static var twin:Null<Encoder->Void>;
	public static inline var TIME = 2.0;
	public static inline var STEPS = 150;

	public static function make(name:String, device:Device):Encoder->Void {
		ready = () -> true;
		probe = null;
		twin = null;
		return switch name {
			case "crystal":
				var r = new Renderer(device);
				renderer = r;
				r.sunDirection = new Vec3(-1, 0.25, 0.35);
				r.sunColor = new Vec3(3, 2.9, 2.8);
				r.sky = new Vec3(0.06, 0.07, 0.1);
				r.ground = new Vec3(0.06, 0.07, 0.1);
				r.rim = new Vec3(0.6, 0.65, 0.8);
				var world = new World();
				var planet = world.node("planet");
				MeshRenderer.attach(planet, Shapes.sphere(device, new Material("planet", new helder.gfx.shader.Vec4(0.55, 0.32, 0.18, 1), 0, 0.9), 1, 48, 24));
				var hull = new Material("hull", new helder.gfx.shader.Vec4(0.5, 0.52, 0.56, 1), 0.3, 0.5);
				hull.ground = 1;
				hull.air = new helder.gfx.shader.Vec4(0.2, 0.45, 1, 0.3);
				var block = Shapes.box(device, hull, 0.22, 0.3, 0.22);
				var gem = new Material("crystal", new helder.gfx.shader.Vec4(0.08, 0.35, 1, 0.7), 0, 0.1, new Vec3(0.05, 0.3, 1.1));
				gem.crystal = 1;
				gem.ground = 1;
				gem.blend = true;
				var crystal = Shapes.box(device, gem, 0.1, 0.32, 0.1);
				// (round the planet's rim as the eye sees it, each standing on the
				// sphere: its up the normal there, turned from y about y x up)
				for (k in 0...10) {
					var a = k * Math.PI * 2 / 10 + 0.3, up = new Vec3(Math.cos(a) * 0.8, Math.sin(a) * 0.8, 0.6);
					var axis = new Vec3(up.z, 0, -up.x), turn = Math.acos(up.y);
					var n = world.node();
					n.position = new Vec3(up.x * 1.05, up.y * 1.05, up.z * 1.05);
					n.rotation = helder.scene.math.Quat.axisAngle(axis * (1 / Math.sqrt(up.z * up.z + up.x * up.x)), turn) * helder.scene.math.Quat.axisAngle(new Vec3(0, 1, 0), k * 0.7);
					MeshRenderer.attach(n, k % 3 == 2 ? crystal : block);
					if (k % 3 != 2) MeshRenderer.tint(n, k % 2 == 0 ? new Vec3(1.5, 0.8, 0.55) : new Vec3(0.65, 1, 1.5));
				}
				var eye = world.node("eye");
				var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
				eye.position = new Vec3(0, 0, 3.6);
				eye.lookAt(new Vec3(0, 0, 0));
				// (the blocks in one instanced draw, each its own tint)
				probe = () -> r.instanced >= 7 ? null : 'instanced: ${r.instanced}';
				enc -> r.draw(enc, world, camera);
			case "overlay":
				// the sample scene under the debug overlay (helder.ui), its frame times made up
				var under = make("gltf", device);
				var r = renderer;
				var overlay = new helder.scene.debug.Overlay(device);
				var stats = new helder.scene.debug.FrameStats(100);
				for (k in 0...100)
					stats.add(k % 17 == 0 ? 0.04 : k % 5 == 0 ? 0.025 : 0.008 + (k % 7) * 0.001);
				enc -> {
					under(enc);
					stats.from(r);
					overlay.draw(enc, stats);
				};
			case "gltf" | "shadows" | "sky":
				var renderer = new Renderer(device);
				Scenes.renderer = renderer;
				if (name != "gltf") renderer.use(new Shadows(device, 512));
				// (the sky at the BeforeOpaque injection point)
				// (a night sky: the tests want a dark corner, compare.mjs and GfxTest alike)
				if (name == "sky") {
					var sky = new Sky(device);
					sky.zenith = new Vec3(0.004, 0.008, 0.03);
					sky.horizon = new Vec3(0.02, 0.025, 0.05);
					sky.ground = new Vec3(0.01, 0.01, 0.01);
					renderer.use(sky);
				}
				var world = new World();
				var model = Model.of("sample.glb");
				model.instantiate(world, device);
				// (typed from the file when compiling)
				if (world.root.find(model.nodes.camera).isNone) throw "Scenes: no camera node";
				var camera = Camera.first(world);
				enc -> renderer.draw(enc, world, camera);
			case "orbits":
				var orbits = new Orbits(device);
				orbits.at(TIME);
				enc -> orbits.draw(enc);
			case "glow":
				// a material of its own (examples/glow: pbr's emissive and colour slots replaced), its orbs instanced
				var glow = new Glow(device);
				glow.at(TIME);
				renderer = glow.renderer;
				enc -> glow.draw(enc);
			case "tsscene":
				// examples/ts-scene's Showcase in Haxe (TsScene): its frame is the TypeScript one's (tests/3d/ts/frames.ts)
				var scene = new TsScene(device);
				scene.at(TIME);
				renderer = scene.renderer;
				enc -> scene.draw(enc);
			case "physics":
				var falling = new Falling(device);
				for (_ in 0...STEPS)
					falling.physics.step(1 / 60);
				enc -> falling.draw(enc);
			case "chains":
				var chains = new Chains(device);
				for (_ in 0...72)
					chains.physics.step(1 / 60);
				enc -> chains.draw(enc);
			case "walker":
				var walker = new Walker(device);
				for (k in 0...STEPS)
					walker.step(1 / 60, k < 20 || k >= 100 ? new Vec3(0, 0, 0) : new Vec3(0.8, 0, -1), k == 60);
				enc -> walker.draw(enc);
			case "instances":
				// a field of 13x13 cubes and spheres on two meshes: instanced draws
				var r = new Renderer(device);
				renderer = r;
				var world = new World();
				var cube = Shapes.box(device, new Material("cube", new helder.gfx.shader.Vec4(0.9, 0.45, 0.2, 1), 0, 0.45), 0.5, 0.5, 0.5);
				var ball = Shapes.sphere(device, new Material("ball", new helder.gfx.shader.Vec4(0.25, 0.5, 0.95, 1), 0, 0.3), 0.3, 16, 8);
				for (x in 0...13)
					for (z in 0...13) {
						var n = world.node();
						n.position = new Vec3((x - 6) * 0.8, 0, (z - 6) * 0.8);
						n.rotation = helder.scene.math.Quat.axisAngle(new Vec3(0, 1, 0), (x * 13 + z) * 0.3);
						MeshRenderer.attach(n, (x + z) % 2 == 0 ? cube : ball);
					}
				var eye = world.node("eye");
				var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
				eye.position = new Vec3(0, 6, 8);
				eye.lookAt(new Vec3(0, 0, 0));
				// (picking: straight down onto the cube at the centre, its top at 0.25;
				// through the camera's centre; beside the field, nothing)
				probe = () -> {
					var down = Pick.ray(world, new Vec3(0, 5, 0), new Vec3(0, -1, 0));
					var r = camera.ray(0, 0, 4 / 3);
					var centre = Pick.ray(world, r.origin, r.dir);
					var miss = Pick.ray(world, new Vec3(20, 5, 0), new Vec3(0, -1, 0));
					down != null && down.node.position.x == 0 && down.node.position.z == 0 && Math.abs(down.distance - 4.75) < 1e-6 && centre != null
						&& centre.node.position.x == 0 && miss == null ? null : 'picking: ${down?.distance} ${centre?.node.position.x} ${miss != null}';
				};
				enc -> r.draw(enc, world, camera);
			case "skin":
				// the skinned sample bent by its animation at 1 s (the elbow at 1.2 radians)
				var r = new Renderer(device).use(new Skinning(device)).use(new Shadows(device, 512));
				renderer = r;
				var world = new World();
				var model = Model.of("skinned.glb");
				var made = [];
				model.instantiate(world, device, null, made);
				var animator = new helder.scene.anim.Animator(made);
				animator.play(model.clip(model.animations.bend));
				animator.update(1.0);
				var floor = world.node("floor");
				MeshRenderer.attach(floor, Shapes.plane(device, new Material("floor", new helder.gfx.shader.Vec4(0.5, 0.5, 0.55, 1), 0, 0.9), 6));
				var eye = world.node("eye");
				var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
				eye.position = new Vec3(0.4, 1.4, 4.2);
				eye.lookAt(new Vec3(-0.3, 1.1, 0));
				enc -> r.draw(enc, world, camera);
			case "textured" | "packedbc" | "packedastc":
				// the textured sample, its PNG decoded by helder.image's decoder,
				// mip-mapped; packed with its texture compressed (Pack --textures bc,
				// astc: bin/3d/textured.bc.hxm3d, textured.astc.hxm3d)
				Images.decode = Images.png;
				var r = new Renderer(device);
				renderer = r;
				var world = new World();
				var crate = if (name == "textured") {
					var model = Model.of("textured.glb");
					model.instantiate(world, device).find(model.nodes.crate);
				} else
					PackedModel.read(name == "packedbc" ? Asset.embed("bin/3d/textured.bc.hxm3d") : Asset.embed("bin/3d/textured.astc.hxm3d"), device).instantiate(world)
						.find("crate");
				crate.rotation = helder.scene.math.Quat.fromEuler(0.5, 0.7, 0);
				var floor = world.node("floor");
				floor.position = new Vec3(0, -1.1, 0);
				MeshRenderer.attach(floor, Shapes.plane(device, new Material("floor", new helder.gfx.shader.Vec4(0.45, 0.47, 0.5, 1), 0, 0.9), 8));
				var eye = world.node("eye");
				var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
				eye.position = new Vec3(0, 0.8, 3.2);
				eye.lookAt(new Vec3(0, -0.1, 0));
				enc -> r.draw(enc, world, camera);
			case "normals":
				// the normal-mapped sample (NormalMaps; tangents computed when loaded)
				Images.decode = Images.png;
				var r = new Renderer(device).use(new NormalMaps(device));
				renderer = r;
				var world = new World();
				var model = Model.of("normals.glb");
				var tiles = model.instantiate(world, device).find(model.nodes.tiles);
				// (then the file loaded again into the same model, as helder dev's
				// reload does: Model.replace swaps the instance's meshes' primitives
				// and materials, the old ones released; the same frame)
				model.replace(Model.of("normals.glb"));
				tiles.rotation = helder.scene.math.Quat.fromEuler(0.5, 0.7, 0);
				var floor = world.node("floor");
				floor.position = new Vec3(0, -1.1, 0);
				MeshRenderer.attach(floor, Shapes.plane(device, new Material("floor", new helder.gfx.shader.Vec4(0.45, 0.47, 0.5, 1), 0, 0.9), 8));
				var eye = world.node("eye");
				var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
				eye.position = new Vec3(0, 0.8, 3.2);
				eye.lookAt(new Vec3(0, -0.1, 0));
				enc -> r.draw(enc, world, camera);
			case "normalgrid":
				// the normal-mapped sample four times, turned alike: one
				// instanced draw of its tiles, mapped (PbrInstancedNormalShader)
				Images.decode = Images.png;
				var r = new Renderer(device).use(new NormalMaps(device));
				renderer = r;
				var world = new World();
				var model = Model.of("normals.glb");
				for (k in 0...4) {
					var tiles = model.instantiate(world, device).find(model.nodes.tiles);
					tiles.position = new Vec3(-1.2 + 0.8 * k, 0, -0.4 * (k % 2));
					tiles.scale = new Vec3(0.45, 0.45, 0.45);
					tiles.rotation = helder.scene.math.Quat.fromEuler(0.5, 0.7, 0);
				}
				var eye = world.node("eye");
				var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
				eye.position = new Vec3(0, 0.8, 3.2);
				eye.lookAt(new Vec3(0, -0.1, 0));
				probe = () -> r.instanced >= 4 ? null : 'mapped tiles drawn instanced: ${r.instanced} instances, not 4';
				enc -> r.draw(enc, world, camera);
			case "blend":
				// three see-through panes (one double-sided) crossing in front of
				// an opaque ball: drawn after it, farthest first
				var r = new Renderer(device);
				renderer = r;
				var world = new World();
				var floor = world.node("floor");
				MeshRenderer.attach(floor, Shapes.plane(device, new Material("floor", new helder.gfx.shader.Vec4(0.5, 0.5, 0.52, 1), 0, 0.9), 8));
				var ball = world.node("ball");
				ball.position = new Vec3(0, 0.6, -1.2);
				MeshRenderer.attach(ball, Shapes.sphere(device, new Material("ball", new helder.gfx.shader.Vec4(0.9, 0.75, 0.2, 1), 1, 0.3), 0.6, 24, 12));
				var colors = [new helder.gfx.shader.Vec4(0.2, 0.5, 1, 0.45), new helder.gfx.shader.Vec4(1, 0.3, 0.2, 0.45), new helder.gfx.shader.Vec4(0.3, 1, 0.4, 0.35)];
				for (k in 0...3) {
					var glass = new Material("glass" + k, colors[k], 0, 0.1, null, k == 2);
					glass.blend = true;
					var pane = world.node("pane" + k);
					pane.position = new Vec3(-0.7 + 0.7 * k, 0.8, 0.4 - 0.5 * k);
					pane.rotation = helder.scene.math.Quat.fromEuler(0, -0.5 + 0.5 * k, 0);
					MeshRenderer.attach(pane, Shapes.box(device, glass, 1, 1.2, 0.05));
				}
				var eye = world.node("eye");
				var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
				eye.position = new Vec3(0.3, 1.6, 4);
				eye.lookAt(new Vec3(0, 0.6, -0.3));
				enc -> r.draw(enc, world, camera);
			case "packedskin":
				// the skinned sample packed (make 3d-programs writes bin/3d/skinned.hxm3d):
				// its skin and clip from the packed file, skin.png's frame
				var r = new Renderer(device).use(new Skinning(device)).use(new Shadows(device, 512));
				renderer = r;
				var world = new World();
				var model = PackedModel.read(Asset.embed("bin/3d/skinned.hxm3d"), device);
				var made = [];
				model.instantiate(world, null, made);
				var animator = new helder.scene.anim.Animator(made);
				animator.play(model.clip("bend"));
				animator.update(1.0);
				var floor = world.node("floor");
				MeshRenderer.attach(floor, Shapes.plane(device, new Material("floor", new helder.gfx.shader.Vec4(0.5, 0.5, 0.55, 1), 0, 0.9), 6));
				var eye = world.node("eye");
				var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
				eye.position = new Vec3(0.4, 1.4, 4.2);
				eye.lookAt(new Vec3(-0.3, 1.1, 0));
				enc -> r.draw(enc, world, camera);
			case "packednormals":
				// the normal-mapped sample packed (its PNG, its tangents): normals.png's frame
				Images.decode = Images.png;
				var r = new Renderer(device).use(new NormalMaps(device));
				renderer = r;
				var world = new World();
				var tiles = PackedModel.read(Asset.embed("bin/3d/normals.hxm3d"), device).instantiate(world).find("tiles");
				tiles.rotation = helder.scene.math.Quat.fromEuler(0.5, 0.7, 0);
				var floor = world.node("floor");
				floor.position = new Vec3(0, -1.1, 0);
				MeshRenderer.attach(floor, Shapes.plane(device, new Material("floor", new helder.gfx.shader.Vec4(0.45, 0.47, 0.5, 1), 0, 0.9), 8));
				var eye = world.node("eye");
				var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
				eye.position = new Vec3(0, 0.8, 3.2);
				eye.lookAt(new Vec3(0, -0.1, 0));
				enc -> r.draw(enc, world, camera);
			case "cascades":
				// (HXMC_CASCADES=1: the same with one, to compare)
				var one = Sys.getEnv("HXMC_CASCADES") == "1";
				var shadows = one ? new Shadows(device, 512) : Shadows.cascaded(device, 512, 7);
				var r = new Renderer(device).use(shadows);
				renderer = r;
				var world = new World();
				var floor = world.node("floor");
				floor.position = new Vec3(0, 0, -18);
				MeshRenderer.attach(floor, Shapes.plane(device, new Material("floor", new helder.gfx.shader.Vec4(0.6, 0.6, 0.62, 1), 0, 0.9), 44));
				var pillar = Shapes.box(device, new Material("pillar", new helder.gfx.shader.Vec4(0.8, 0.55, 0.35, 1), 0, 0.6), 0.4, 2.4, 0.4);
				var ball = Shapes.sphere(device, new Material("ball", new helder.gfx.shader.Vec4(0.3, 0.55, 0.9, 1), 0, 0.3), 0.35, 16, 8);
				for (k in 0...10) {
					for (x in [-2.2, 2.2]) {
						var n = world.node();
						n.position = new Vec3(x, 1.2, 2 - k * 4);
						MeshRenderer.attach(n, pillar);
					}
					var b = world.node();
					b.position = new Vec3((k % 2) * 1.2 - 0.6, 0.35, 0.5 - k * 4);
					MeshRenderer.attach(b, ball);
				}
				var sun = world.node("sun");
				Light.attach(sun, Light.directional(new Vec3(1, 0.95, 0.88), 2.6));
				sun.rotation = helder.scene.math.Quat.fromEuler(-0.7, 0.9, 0);
				var eye = world.node("eye");
				var camera = Camera.attach(eye, Camera.perspective(0.9, 0.1, 60));
				eye.position = new Vec3(0.6, 1.5, 4.5);
				eye.lookAt(new Vec3(0, 0.6, -6));
				enc -> r.draw(enc, world, camera);
			case "environment":
				Images.decode = Images.png;
				var env = Environment.fromImage(device, "image/png", Asset.embed("panorama.png"));
				var r = new Renderer(device).use(env);
				renderer = r;
				var world = new World();
				for (k in 0...5) {
					var rough = 0.05 + k * 0.235;
					var metal = world.node("metal" + k), plastic = world.node("plastic" + k);
					metal.position = new Vec3(-2.4 + k * 1.2, 0.65, 0);
					plastic.position = new Vec3(-2.4 + k * 1.2, -0.65, 0);
					MeshRenderer.attach(metal, Shapes.sphere(device, new Material("metal", new helder.gfx.shader.Vec4(0.95, 0.93, 0.88, 1), 1, rough), 0.5, 32, 16));
					MeshRenderer.attach(plastic, Shapes.sphere(device, new Material("plastic", new helder.gfx.shader.Vec4(0.8, 0.2, 0.15, 1), 0, rough), 0.5, 32, 16));
				}
				var sun = world.node("sun");
				Light.attach(sun, Light.directional(new Vec3(1, 0.95, 0.85), 2));
				sun.lookAt(new Vec3(0.35, -0.45, 0.82));
				var eye = world.node("eye");
				var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
				eye.position = new Vec3(0, 0.3, 5.5);
				eye.lookAt(new Vec3(0, 0, 0));
				// (a bright background: a black mark in the corner, where the
				// tests' check that something was drawn looks for the clear colour)
				var ui = new helder.ui.draw.Renderer(device);
				var markPass:PassDesc = {colors: [{load: Load}]};
				r.inject(AfterPass, (enc, frame) -> {
					ui.begin(device.width, device.height);
					ui.rect(0, 0, 4, 4, 0, 0xFF000000, 0, 0);
					enc.beginPass(markPass);
					ui.end(enc);
					enc.endPass();
				});
				enc -> r.draw(enc, world, camera);
			case "morph" | "packedmorph":
				var r = new Renderer(device).use(new Shadows(device, 512));
				renderer = r;
				var world = new World();
				var made = [];
				var left:Node, right:Node;
				if (name == "morph") {
					var model = Model.of("morph.glb");
					left = model.instantiate(world, device, null, made);
					var animator = new helder.scene.anim.Animator(made);
					animator.play(model.clip(model.animations.breathe));
					animator.update(1.5);
					// (a second instance at its mesh's default weights, its own vertices)
					right = model.instantiate(world, device);
				} else {
					// (packed at build time: bin/3d/morph.hxm3d, morph.png's frame)
					var model = PackedModel.read(Asset.embed("bin/3d/morph.hxm3d"), device);
					left = model.instantiate(world, null, made);
					var animator = new helder.scene.anim.Animator(made);
					animator.play(model.clip("breathe"));
					animator.update(1.5);
					right = model.instantiate(world);
				}
				left.position = new Vec3(-1.15, 0, 0);
				right.position = new Vec3(1.15, 0, 0);
				var floor = world.node("floor");
				floor.position = new Vec3(0, -0.4, 0);
				MeshRenderer.attach(floor, Shapes.plane(device, new Material("floor", new helder.gfx.shader.Vec4(0.5, 0.5, 0.52, 1), 0, 0.9), 8));
				var eye = world.node("eye");
				var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
				eye.position = new Vec3(0, 1.1, 3.3);
				eye.lookAt(new Vec3(0, 0.05, 0));
				enc -> r.draw(enc, world, camera);
			case "packed":
				// the sample scene packed at build time (Pack: npm test -- 3d writes
				// bin/3d/sample.hxm3d first), read without JSON: gltf.png's frame
				var r = new Renderer(device);
				renderer = r;
				var world = new World();
				var model = PackedModel.read(Asset.embed("bin/3d/sample.hxm3d"), device);
				model.instantiate(world);
				var camera = Camera.first(world);
				// (packed with its trees, Pack --bvh: each the tree made from its data)
				probe = () -> {
					var trees = 0;
					for (m in model.meshes)
						for (p in m.primitives) {
							@:privateAccess var packed = p.tree;
							if (packed == null) return "a primitive packed without its tree";
							if (packed.bytes().compare(Bvh.build(p.data).bytes()) != 0) return "a packed tree not the one built from its data";
							trees++;
						}
					var hit = new Hit();
					if (!world.raycast(camera.eye(), MathTools.transformDir(camera.node.worldMatrix(), new Vec3(0, 0, -1)), hit)) return 'no hit through the middle of the view ($trees trees)';
					null;
				};
				enc -> r.draw(enc, world, camera);
			case "spot":
				// two spot lights and a point light over a floor and spheres, no sun
				var r = new Renderer(device);
				renderer = r;
				r.sky = new Vec3(0.03, 0.035, 0.05);
				r.ground = new Vec3(0.02, 0.02, 0.02);
				var world = new World();
				var floor = world.node("floor");
				MeshRenderer.attach(floor, Shapes.plane(device, new Material("floor", new helder.gfx.shader.Vec4(0.7, 0.7, 0.72, 1), 0, 0.7), 10));
				var ball = Shapes.sphere(device, new Material("ball", new helder.gfx.shader.Vec4(0.9, 0.9, 0.9, 1), 0, 0.4), 0.5, 24, 12);
				for (x in [-1.6, 0.0, 1.6]) {
					var n = world.node();
					n.position = new Vec3(x, 0.5, 0);
					MeshRenderer.attach(n, ball);
				}
				var warm = world.node("warm");
				warm.position = new Vec3(-1.5, 3, 1);
				warm.lookAt(new Vec3(-1.2, 0, 0));
				Light.attach(warm, Light.spot(new Vec3(1, 0.6, 0.3), 14, 12, 0.25, 0.45));
				var cool = world.node("cool");
				cool.position = new Vec3(1.5, 3, 1);
				cool.lookAt(new Vec3(1.2, 0, 0));
				Light.attach(cool, Light.spot(new Vec3(0.3, 0.6, 1), 14, 12, 0.2, 0.35));
				var fill = world.node("fill");
				fill.position = new Vec3(0, 1.5, 2.5);
				Light.attach(fill, Light.pointLight(new Vec3(1, 1, 1), 1.5, 8));
				var eye = world.node("eye");
				var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
				eye.position = new Vec3(0, 3, 5.5);
				eye.lookAt(new Vec3(0, 0.3, 0));
				enc -> r.draw(enc, world, camera);
			case "lazy":
				// the skinned sample loaded in the background (Model.of(path, Lazy)),
				// drawn bent once it is here: skin.png's frame (until then the clear colour)
				var r = new Renderer(device).use(new Skinning(device)).use(new Shadows(device, 512));
				renderer = r;
				var world = new World();
				var floor = world.node("floor");
				MeshRenderer.attach(floor, Shapes.plane(device, new Material("floor", new helder.gfx.shader.Vec4(0.5, 0.5, 0.55, 1), 0, 0.9), 6));
				var eye = world.node("eye");
				var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
				eye.position = new Vec3(0.4, 1.4, 4.2);
				eye.lookAt(new Vec3(-0.3, 1.1, 0));
				var asset = Model.of("skinned.glb", Lazy);
				helder.async.Async.launch(_ -> {
					var model = asset.load();
					var made = [];
					model.instantiate(world, device, null, made);
					var animator = new helder.scene.anim.Animator(made);
					animator.play(model.clip(model.animations.bend));
					animator.update(1.0);
				});
				ready = () -> {
					Assets.poll();
					asset.ready;
				};
				enc -> {
					Assets.poll();
					r.draw(enc, world, camera);
				};
			case "bloom" | "poststage":
				// (an HDR renderer's targets: the scene in half floats, then the post into the frame)
				var r = new Renderer(device, true, 1, true);
				renderer = r;
				r.sunColor = new Vec3(1.2, 1.15, 1.1);
				r.sky = new Vec3(0.04, 0.05, 0.08);
				r.ground = new Vec3(0.02, 0.02, 0.02);
				r.clearColor = new Color(0.01, 0.012, 0.02, 1);
				var post = new PostProcess(device, RGBA8, true);
				post.bloom = 0.08;
				post.vignette = 0.3;
				post.saturation = 1.1;
				if (name == "poststage") {
					var bytes = haxe.io.Bytes.alloc(SepiaShader.uniforms[0].size);
					SepiaShader.params.stage.write({size: new helder.gfx.shader.Vec4(device.width, device.height, 8, 0.8)}, bytes);
					post.add(SepiaShader, bytes);
					post.add(ScanShader, bytes).filter = Nearest;
				}
				var world = new World();
				var floor = world.node("floor");
				floor.position = new Vec3(0, -0.6, 0);
				MeshRenderer.attach(floor, Shapes.plane(device, new Material("floor", new helder.gfx.shader.Vec4(0.25, 0.25, 0.28, 1), 0, 0.5), 8));
				var lights = [new Vec3(8, 2.4, 0.6), new Vec3(0.4, 2.2, 6), new Vec3(1.2, 1.2, 1.2)];
				for (k in 0...3) {
					var n = world.node("lamp" + k);
					n.position = new Vec3(-1.6 + k * 1.6, 0, 0);
					MeshRenderer.attach(n, Shapes.sphere(device, new Material("lamp" + k, new helder.gfx.shader.Vec4(0.1, 0.1, 0.1, 1), 0, 0.5, lights[k]), 0.4, 32, 16));
				}
				var bar = world.node("bar");
				bar.position = new Vec3(0, 1, -1);
				MeshRenderer.attach(bar, Shapes.box(device, new Material("bar", new helder.gfx.shader.Vec4(0, 0, 0, 1), 0, 1, new Vec3(20, 14, 6)), 3.2, 0.06, 0.06));
				var eye = world.node("eye");
				var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
				eye.position = new Vec3(0, 0.8, 5);
				eye.lookAt(new Vec3(0, 0.2, 0));
				var w = device.width, h = device.height;
				var light = device.createTexture({width: w, height: h, format: RGBA16F, renderTarget: true});
				var depth = device.createTexture({width: w, height: h, format: Depth32F});
				enc -> {
					r.drawInto(enc, world, camera, light, depth, w, h);
					post.run(enc, light, null, w, h);
				};
			case "fog":
				var r = new Renderer(device, true, 1, true);
				renderer = r;
				r.sunDirection = new Vec3(1, 0.25, -0.4);
				r.sunColor = new Vec3(0.9, 0.7, 0.5);
				r.sky = new Vec3(0.05, 0.06, 0.1);
				r.ground = new Vec3(0.02, 0.02, 0.02);
				var fog = new Fog(new Vec3(0.012, 0.03, 0.07), 0.09);
				fog.start = 2;
				fog.falloff = 0.35;
				r.fog = fog;
				var sky = new Sky(device);
				sky.zenith = new Vec3(0.004, 0.008, 0.03);
				sky.horizon = new Vec3(0.03, 0.018, 0.014);
				sky.ground = new Vec3(0.01, 0.01, 0.01);
				sky.sunColor = new Vec3(0.5, 0.35, 0.2);
				r.use(sky);
				var post = new PostProcess(device, RGBA8, true);
				post.bloom = 0.04;
				var world = new World();
				var floor = world.node("floor");
				MeshRenderer.attach(floor, Shapes.plane(device, new Material("floor", new helder.gfx.shader.Vec4(0.3, 0.3, 0.3, 1), 0, 0.8), 120));
				var stone = new Material("stone", new helder.gfx.shader.Vec4(0.6, 0.55, 0.5, 1), 0, 0.7);
				var pillar = Shapes.box(device, stone, 0.6, 4, 0.6);
				for (k in 0...12)
					for (side in [-1, 1]) {
						var n = world.node("pillar");
						n.position = new Vec3(side * 2.5, 2, -k * 5);
						MeshRenderer.attach(n, pillar);
					}
				var glow = new Material("sign", new helder.gfx.shader.Vec4(0, 0, 0, 1), 0, 1, new Vec3(6, 2, 0.5));
				glow.fog = false;
				var sign = world.node("sign");
				sign.position = new Vec3(0, 1.5, -45);
				MeshRenderer.attach(sign, Shapes.box(device, glow, 3, 0.4, 0.2));
				var eye = world.node("eye");
				var camera = Camera.attach(eye, Camera.perspective(0.9, 0.1, 80));
				eye.position = new Vec3(0, 1.7, 6);
				eye.lookAt(new Vec3(0, 2, -20));
				var w = device.width, h = device.height;
				var light = device.createTexture({width: w, height: h, format: RGBA16F, renderTarget: true});
				var depth = device.createTexture({width: w, height: h, format: Depth32F});
				enc -> {
					r.drawInto(enc, world, camera, light, depth, w, h);
					post.run(enc, light, null, w, h);
				};
			case "instancedmesh":
				var r = new Renderer(device).use(new Shadows(device, 1024));
				renderer = r;
				var world = new World();
				var cube = Shapes.box(device, new Material("cube", new helder.gfx.shader.Vec4(1, 1, 1, 1), 0, 0.45), 0.3, 0.3, 0.3);
				var set = new InstancedMesh(cube, 512, 400);
				for (i in 0...400) {
					var a = i * 0.25, d = 0.4 + i * 0.012;
					var q = helder.scene.math.Quat.axisAngle(new Vec3(0.2822, 0.9407, 0.1881), i * 0.37);
					set.setTransform(i, Math.cos(a) * d, Math.sin(i * 0.05) * 0.4, Math.sin(a) * d, q.x, q.y, q.z, q.w, 0.6 + (i % 5) * 0.12);
					set.setColor(i, 0.5 + 0.5 * Math.cos(a), 0.5 + 0.5 * Math.cos(a + 2.1), 0.5 + 0.5 * Math.cos(a + 4.2));
				}
				set.bounds = new helder.scene.math.Aabb(new Vec3(-6, -0.8, -6), new Vec3(6, 0.8, 6));
				InstancedMesh.attach(world.node("swarm"), set);
				// (a floor under it, the set's shadows on it; a second set out of the view: culled whole)
				var floor = world.node("floor");
				floor.position = new Vec3(0, -1, 0);
				MeshRenderer.attach(floor, Shapes.plane(device, new Material("floor", new helder.gfx.shader.Vec4(0.5, 0.5, 0.55, 1), 0, 0.8), 16));
				var away = new InstancedMesh(cube, 4);
				away.bounds = new helder.scene.math.Aabb(new Vec3(-0.5, 40, -0.5), new Vec3(0.5, 41, 0.5));
				for (i in 0...4)
					away.setPosition(i, 0, 40.5, 0);
				InstancedMesh.attach(world.node("away"), away);
				var eye = world.node("eye");
				var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
				eye.position = new Vec3(0, 6, 7);
				eye.lookAt(new Vec3(0, 0, 0));
				probe = () -> r.draws == 2 && r.instanced == 400 && r.culled == 1 ? null : '${r.draws} draws, ${r.instanced} instanced, ${r.culled} culled (2, 400, 1)';
				enc -> r.draw(enc, world, camera);
			case "gpuparticles":
				// GpuParticles over a floor: a burst of sparks as streaks (drag and
				// gravity), a ring of soft puffs growing, a particle not yet born
				// and one past its life (neither drawn), at the clock's 0.4 s
				var fx = new GpuParticles(device, 256);
				var r = new Renderer(device).use(fx);
				renderer = r;
				var world = new World();
				var floor = world.node("floor");
				MeshRenderer.attach(floor, Shapes.plane(device, new Material("floor", new helder.gfx.shader.Vec4(0.3, 0.3, 0.33, 1), 0, 0.8), 8));
				fx.drag = 1.5;
				fx.gravity = new Vec3(0, -3, 0);
				for (k in 0...24) {
					var a = k * Math.PI * 2 / 24, up = 0.6 + 0.4 * ((k * 7) % 5) / 4;
					fx.emit(-0.6, 0.6, 0, Math.cos(a) * 3, up * 3, Math.sin(a) * 1.5, 2.0, 1.1, 0.4, 1, 0.03, 0.01, 1.2, 0.08, 1);
				}
				for (k in 0...12) {
					var a = k * Math.PI * 2 / 12;
					fx.emit(1.0, 0.4, 0, Math.cos(a) * 0.8, Math.sin(a) * 0.8, 0, 0.1, 0.3, 0.9, 1, 0.08, 0.3, 1.5);
				}
				fx.emit(0, 1, 0, 0, 0, 0, 5, 5, 5, 1, 0.5, 0.5, 1, 0, 0, 1.0);
				fx.emit(0, 1, 0, 0, 0, 0, 5, 5, 5, 1, 0.5, 0.5, 0.1);
				fx.time = 0.4;
				var eye = world.node("eye");
				var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
				eye.position = new Vec3(0, 1.2, 4);
				eye.lookAt(new Vec3(0, 0.4, 0));
				probe = () -> fx.pending == 0 ? null : '${fx.pending} particles not uploaded';
				enc -> r.draw(enc, world, camera);
			case "khrtransform" | "khrclearcoat":
				// (Khronos' glTF sample models, examples/gltf-showcase's: KHR_texture_transform's
				// test, KHR_materials_clearcoat's; lit by a prefiltered studio, from the front)
				Images.decode = Images.common;
				var r = new Renderer(device).use(new NormalMaps(device));
				var env = Environment.prefiltered(device, "image/png", Asset.embed("studio-ibl.png"), 6);
				env.intensity = 6.055;
				env.background = false;
				r.use(env);
				r.sunColor = new Vec3(0, 0, 0);
				// (dark: the tests' check that something was drawn looks for a dark corner)
				r.clearColor = new Color(0.02, 0.02, 0.025, 1);
				renderer = r;
				var world = new World();
				if (name == "khrtransform") Model.of("TextureTransformTest.glb").instantiate(world, device) else Model.of("ClearCoatTest.glb").instantiate(world, device);
				var b = helder.scene.math.Aabb.empty(), meshes = world.store(MeshRenderer.KIND);
				for (k in 0...meshes.length)
					b = b.union(meshes.valueAt(k).bounds.transform(meshes.nodeAt(k).worldMatrix()));
				var c = (b.min + b.max) * 0.5, d = b.max - b.min, t = Math.tan(0.4);
				var eye = world.node("eye");
				var camera = Camera.attach(eye, Camera.perspective(0.8, 0.01, 100));
				eye.position = c + new Vec3(0, 0, Math.max(d.x * 0.5 / (t * 256 / 192), d.y * 0.5 / t) * 1.1 + d.z * 0.5);
				eye.lookAt(c);
				enc -> r.draw(enc, world, camera);
			case "compressed":
				// (a pattern's texture compressed by helder.image's BlockCompress, as
				// RGBA8, BC1, BC3 and ASTC 4x4, each on a quad: the GPU's decoder
				// reading the asset step's blocks; a format the GPU lacks drawn black)
				var r = new Renderer(device);
				r.sunColor = new Vec3(0, 0, 0);
				r.sky = new Vec3(1, 1, 1);
				r.ground = new Vec3(1, 1, 1);
				r.clearColor = new Color(0.02, 0.02, 0.025, 1);
				renderer = r;
				var w = 64, rgba = haxe.io.Bytes.alloc(w * w * 4);
				for (y in 0...w)
					for (x in 0...w) {
						var p = 4 * (y * w + x), check = ((x >> 3) + (y >> 3)) & 1;
						rgba.set(p, Std.int(x * 255 / w));
						rgba.set(p + 1, check == 1 ? 220 : 40);
						rgba.set(p + 2, Std.int(y * 255 / w));
						rgba.set(p + 3, x < w / 2 ? 255 : 96);
					}
				var world = new World(), supported = [];
				var formats:Array<{f:TextureFormat, name:String}> = [{f: RGBA8, name: ""}, {f: BC1, name: "bc1"}, {f: BC3, name: "bc3"}, {f: ASTC4x4, name: "astc"}];
				for (k in 0...formats.length) {
					var f = formats[k];
					var tex = f.name == "" ? Images.mipmapped(device, w, w, rgba) : Images.compressed(device, f.f, w, w, helder.image.BlockCompress.mips(rgba, w, w, f.name));
					if (tex != null) supported.push(f.name == "" ? "rgba8" : f.name);
					var m = new Material(f.name, new helder.gfx.shader.Vec4(tex != null ? 1 : 0, tex != null ? 1 : 0, tex != null ? 1 : 0, 1), 0, 1);
					m.baseColorTexture = tex;
					var n = world.node(f.name);
					n.position = new Vec3(-1.5 + k, 0, 0);
					n.rotation = helder.scene.math.Quat.axisAngle(new Vec3(1, 0, 0), Math.PI / 2);
					MeshRenderer.attach(n, Shapes.plane(device, m, 1));
				}
				Sys.println("Scenes: compressed: the GPU samples " + supported.join(", "));
				// (Mesa's llvmpipe has them all; elsewhere a format missing is no failure of its frame's other quads)
				probe = () -> supported.length == 4 || Sys.getEnv("HXMC_3D_COMPRESSED") == "some" ? null : "formats missing: " + supported.join(", ");
				var eye = world.node("eye");
				var camera = Camera.attach(eye, Camera.perspective(0.6, 0.1, 100));
				eye.position = new Vec3(0, 0, 6);
				eye.lookAt(new Vec3(0, 0, 0));
				enc -> r.draw(enc, world, camera);
			case "unevenscale":
				var shadows = new Shadows(device, 1024);
				var r = new Renderer(device).use(shadows);
				renderer = r;
				var world = new World();
				var floor = world.node("floor");
				floor.position = new Vec3(0, -0.6, 0);
				MeshRenderer.attach(floor, Shapes.plane(device, new Material("floor", new helder.gfx.shader.Vec4(0.55, 0.56, 0.6, 1), 0, 0.85), 14));
				var box = Shapes.box(device, new Material("box", new helder.gfx.shader.Vec4(0.9, 0.5, 0.25, 1), 0, 0.35));
				var ball = Shapes.sphere(device, new Material("ball", new helder.gfx.shader.Vec4(0.25, 0.55, 0.95, 1), 0, 0.25), 0.5, 24, 12);
				// (each scaled unevenly, turned about a tilted axis: an uneven scale under a turn, and a turn after it from the parent)
				var scales = [new Vec3(0.3, 1.2, 0.7), new Vec3(1.4, 0.25, 0.5), new Vec3(0.5, 0.6, 1.5), new Vec3(1, 0.4, 0.3)];
				for (k in 0...16) {
					var x = (k % 4) - 1.5, z = Std.int(k / 4) - 1.5;
					var parent = world.node();
					parent.position = new Vec3(x * 1.6, 0, z * 1.5);
					parent.rotation = helder.scene.math.Quat.axisAngle(new Vec3(0, 1, 0), k * 0.4);
					var n = world.node("", parent);
					n.rotation = helder.scene.math.Quat.axisAngle(new Vec3(0.48, 0.8, 0.36), k * 0.9);
					n.scale = scales[k % 4] * (k % 3 == 0 ? 1.3 : 1);
					MeshRenderer.attach(n, k % 2 == 0 ? box : ball);
				}
				var sun = world.node("sun");
				Light.attach(sun, Light.directional(new Vec3(1, 0.95, 0.88), 2.8));
				sun.rotation = helder.scene.math.Quat.fromEuler(-0.6, 0.7, 0);
				var eye = world.node("eye");
				var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 60));
				eye.position = new Vec3(1.5, 5.5, 6.5);
				eye.lookAt(new Vec3(0, -0.2, 0));
				// (the floor, the boxes, the balls: three draws, in the main pass and the map's)
				probe = () -> r.draws == 3 && r.instanced == 16 && r.shadowDraws == 3 ? null : '${r.draws} draws, ${r.instanced} instanced, ${r.shadowDraws} shadow draws (3, 16, 3)';
				twin = enc -> {
					r.instancing = false;
					r.draw(enc, world, camera);
					r.instancing = true;
					if (r.draws != 17) throw 'Scenes: unevenscale: ${r.draws} draws without instancing (17)';
				};
				enc -> r.draw(enc, world, camera);
			case "softshadows":
				var shadows = Shadows.cascaded(device, 1024, 6);
				// (HXMC_SOFT=0: the same with the 3x3 filter, to compare)
				if (Sys.getEnv("HXMC_SOFT") != "0") shadows.soft(0.16, 16, 0.05);
				var r = new Renderer(device).use(shadows);
				renderer = r;
				var world = new World();
				var floor = world.node("floor");
				floor.position = new Vec3(0, 0, -10);
				MeshRenderer.attach(floor, Shapes.plane(device, new Material("floor", new helder.gfx.shader.Vec4(0.62, 0.62, 0.64, 1), 0, 0.9), 30));
				var stone = new Material("stone", new helder.gfx.shader.Vec4(0.82, 0.58, 0.38, 1), 0, 0.6);
				var pillar = Shapes.box(device, stone, 0.3, 2.6, 0.3);
				var stem = Shapes.box(device, stone, 0.08, 1.6, 0.08);
				var slab = Shapes.box(device, new Material("slab", new helder.gfx.shader.Vec4(0.35, 0.6, 0.85, 1), 0, 0.5), 1.4, 0.08, 1.0);
				var ball = Shapes.sphere(device, new Material("ball", new helder.gfx.shader.Vec4(0.9, 0.85, 0.8, 1), 0, 0.3), 0.3, 24, 12);
				for (k in 0...5) {
					var z = 1 - k * 4.5;
					var p = world.node();
					p.position = new Vec3(-1.8, 1.3, z);
					MeshRenderer.attach(p, pillar);
					var st = world.node();
					st.position = new Vec3(1.4, 0.8, z - 1);
					MeshRenderer.attach(st, stem);
					var sl = world.node();
					sl.position = new Vec3(1.4, 1.64, z - 1);
					MeshRenderer.attach(sl, slab);
					var b = world.node();
					b.position = new Vec3(-0.2, 0.3, z - 2);
					MeshRenderer.attach(b, ball);
				}
				var sun = world.node("sun");
				Light.attach(sun, Light.directional(new Vec3(1, 0.95, 0.88), 2.6));
				sun.rotation = helder.scene.math.Quat.fromEuler(-0.75, 1.1, 0);
				var eye = world.node("eye");
				var camera = Camera.attach(eye, Camera.perspective(0.9, 0.1, 60));
				eye.position = new Vec3(0.4, 3.2, 4.5);
				eye.lookAt(new Vec3(0, 0.2, -5));
				enc -> r.draw(enc, world, camera);
			case "shading":
				// the shading models side by side, a sphere each (Material's
				// factories): unlit, matcap, normals, depth; lambert, phong, pbr;
				// under a sun and a blue point light, on a floor of lambert
				var r = new Renderer(device);
				renderer = r;
				var world = new World();
				var ball = Geometry.sphere({radius: 0.4, widthSegments: 32, heightSegments: 16});
				var orange = new helder.gfx.shader.Vec4(0.9, 0.25, 0.05, 1);
				var materials = [
					Material.unlit({color: orange}),
					Material.matcap({matcap: matcapImage(device)}),
					Material.normals(),
					Material.depth(5.5, 8.5),
					Material.lambert({color: orange}),
					Material.phong({color: orange, shininess: 80}),
					Material.standard({color: orange, roughness: 0.3})
				];
				for (i in 0...materials.length) {
					var n = world.node();
					n.position = new Vec3(-2.7 + i * 0.9, 0.4, 0);
					MeshRenderer.attach(n, Shapes.of(device, ball, materials[i]));
				}
				var floor = world.node("floor");
				MeshRenderer.attach(floor,
					Shapes.of(device, Geometry.plane({width: 9, height: 4}).rotated(-Math.PI / 2, 0, 0), Material.lambert({color: new helder.gfx.shader.Vec4(0.45, 0.47, 0.5, 1)})));
				var sun = world.node("sun");
				Light.attach(sun, Light.directional(new Vec3(1, 0.96, 0.9), 2.4));
				sun.rotation = helder.scene.math.Quat.fromEuler(-0.8, 0.6, 0);
				var lamp = world.node("lamp");
				lamp.position = new Vec3(2.2, 1.2, 1.0);
				Light.attach(lamp, Light.pointLight(new Vec3(0.3, 0.55, 1), 4, 4));
				var eye = world.node("eye");
				var camera = Camera.attach(eye, Camera.perspective(0.62, 0.1, 50));
				eye.position = new Vec3(0, 2.4, 7);
				eye.lookAt(new Vec3(0, 0.3, 0));
				enc -> r.draw(enc, world, camera);
			case "primitives":
				// every Geometry generator at three's parameters, smooth above
				// (their normals as colours: Material.normals, a wrong one shows)
				// and flat below (flat: true, lit by Lambert: each face its own)
				var r = new Renderer(device);
				renderer = r;
				var world = new World();
				var helix = helder.scene.math.Curve3.catmullRom([for (k in 0...9) new Vec3(Math.cos(k * 1.4) * 0.22, -0.3 + k * 0.075, Math.sin(k * 1.4) * 0.22)]);
				var vase = [
					new helder.gfx.shader.Vec2(0.01, -0.3), new helder.gfx.shader.Vec2(0.22, -0.28), new helder.gfx.shader.Vec2(0.3, -0.1),
					new helder.gfx.shader.Vec2(0.18, 0.12), new helder.gfx.shader.Vec2(0.14, 0.24), new helder.gfx.shader.Vec2(0.22, 0.32)
				];
				function shapes(flat:Bool):Array<VertexData>
					return [
						Geometry.box({width: 0.5, height: 0.5, depth: 0.5, flat: flat}),
						Geometry.sphere({radius: 0.32, widthSegments: flat ? 12 : 32, heightSegments: flat ? 8 : 16, flat: flat}),
						Geometry.cylinder({radiusTop: 0.22, radiusBottom: 0.28, height: 0.6, radialSegments: flat ? 8 : 32, flat: flat}),
						Geometry.cone({radius: 0.3, height: 0.65, radialSegments: flat ? 8 : 32, flat: flat}),
						Geometry.capsule({radius: 0.2, height: 0.3, capSegments: flat ? 3 : 6, radialSegments: flat ? 8 : 16, flat: flat}),
						Geometry.torus({radius: 0.24, tube: 0.1, radialSegments: flat ? 6 : 12, tubularSegments: flat ? 16 : 48, flat: flat}),
						Geometry.torusKnot({radius: 0.2, tube: 0.06, tubularSegments: flat ? 48 : 96, radialSegments: flat ? 5 : 8, flat: flat}),
						Geometry.ring({innerRadius: 0.14, outerRadius: 0.32, thetaSegments: flat ? 10 : 32, flat: flat}),
						Geometry.circle({radius: 0.32, segments: flat ? 8 : 32, flat: flat}),
						Geometry.plane({width: 0.55, height: 0.55, widthSegments: 2, heightSegments: 2, flat: flat}),
						Geometry.lathe(vase, {segments: flat ? 8 : 24, flat: flat}),
						Geometry.tube(helix, {tubularSegments: flat ? 24 : 64, radius: 0.06, radialSegments: flat ? 5 : 8, flat: flat})
					];
				var normals = Material.normals({doubleSided: true});
				var clay = Material.lambert({color: new helder.gfx.shader.Vec4(0.85, 0.62, 0.4, 1), doubleSided: true});
				for (flat in [false, true]) {
					var all = shapes(flat);
					for (i in 0...all.length) {
						var n = world.node();
						n.position = new Vec3(-2.25 + (i % 6) * 0.9, (flat ? -0.55 : 1.45) - Std.int(i / 6) * 0.95, 0);
						// (turned a little: the flat shapes' faces and the discs' fronts seen)
						n.rotation = helder.scene.math.Quat.fromEuler(0.35, i < 7 ? 0.5 : 0.2, 0);
						MeshRenderer.attach(n, Shapes.of(device, all[i], flat ? clay : normals));
					}
				}
				var sun = world.node("sun");
				Light.attach(sun, Light.directional(new Vec3(1, 0.97, 0.92), 2.6));
				sun.rotation = helder.scene.math.Quat.fromEuler(-0.7, 0.5, 0);
				Light.attach(world.node("sky"), Light.hemisphere(new Vec3(0.35, 0.4, 0.5), new Vec3(0.12, 0.1, 0.08)));
				var eye = world.node("eye");
				var camera = Camera.attach(eye, Camera.perspective(0.9, 0.1, 50));
				// (a column at the frame's centre, which RenderTest checks is drawn)
				eye.position = new Vec3(0.45, 0.45, 5);
				eye.lookAt(new Vec3(0.45, 0.45, 0));
				enc -> r.draw(enc, world, camera);
			case "toon":
				// toon shading (Material.toon): three bands of the sun's light,
				// its soft shadow banded with it, a warm point light's own bands,
				// the shaded sides the materials' shade; a toon floor
				var shadows = new Shadows(device, 1024);
				shadows.soft(0.12, 12, 0.08);
				var r = new Renderer(device).use(shadows);
				renderer = r;
				var world = new World();
				var floor = world.node("floor");
				MeshRenderer.attach(floor, Shapes.of(device, Geometry.plane({width: 10, height: 10}).rotated(-Math.PI / 2, 0, 0),
					Material.toon({color: new helder.gfx.shader.Vec4(0.45, 0.75, 0.35, 1), steps: 2, shade: new Vec3(0.22, 0.3, 0.45)})));
				var red = Material.toon({color: new helder.gfx.shader.Vec4(0.9, 0.2, 0.15, 1), steps: 3, shade: new Vec3(0.12, 0.12, 0.3)});
				var gold = Material.toon({color: new helder.gfx.shader.Vec4(0.95, 0.7, 0.2, 1), steps: 4, shade: new Vec3(0.15, 0.12, 0.28)});
				var blue = Material.toon({color: new helder.gfx.shader.Vec4(0.25, 0.45, 0.95, 1), steps: 2, shade: new Vec3(0.15, 0.15, 0.35)});
				function put(g:VertexData, m:Material, x:Float, y:Float, z:Float) {
					var n = world.node();
					n.position = new Vec3(x, y, z);
					MeshRenderer.attach(n, Shapes.of(device, g, m));
					return n;
				}
				put(Geometry.sphere({radius: 0.6}), red, -1.4, 0.6, 0);
				put(Geometry.torusKnot({radius: 0.45, tube: 0.16, tubularSegments: 128, radialSegments: 12}), gold, 0.2, 0.85, -0.3).rotation = helder.scene.math.Quat.fromEuler(0.3, 0.4, 0);
				put(Geometry.cylinder({radiusTop: 0.35, radiusBottom: 0.45, height: 1.4}), blue, 1.6, 0.7, 0.2);
				put(Geometry.box({width: 0.6, height: 0.6, depth: 0.6}), blue, -0.4, 0.3, 1.1).rotation = helder.scene.math.Quat.fromEuler(0, 0.6, 0);
				var sun = world.node("sun");
				Light.attach(sun, Light.directional(new Vec3(1, 0.96, 0.88), 3));
				sun.rotation = helder.scene.math.Quat.fromEuler(-0.85, 0.9, 0);
				var lamp = world.node("lamp");
				lamp.position = new Vec3(0.9, 0.5, 1.4);
				Light.attach(lamp, Light.pointLight(new Vec3(1, 0.55, 0.2), 3, 2.5));
				var eye = world.node("eye");
				var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 50));
				eye.position = new Vec3(0, 2.6, 5.2);
				eye.lookAt(new Vec3(0, 0.5, 0));
				enc -> r.draw(enc, world, camera);
			case "sprites":
				// Sprites: trees as cards turning about y (Axis, two cells of an
				// atlas, cut out), clouds facing the camera (Spherical, see-through,
				// sorted far to near), lamps' halos added (Additive, unlit)
				var r = new Renderer(device);
				renderer = r;
				r.clearColor = new Color(0.05, 0.07, 0.12);
				var world = new World();
				var floor = world.node("floor");
				MeshRenderer.attach(floor,
					Shapes.of(device, Geometry.plane({width: 14, height: 14}).rotated(-Math.PI / 2, 0, 0), Material.lambert({color: new helder.gfx.shader.Vec4(0.35, 0.5, 0.3, 1)})));
				var trees = new Sprites(device,
					Material.unlit({color: new helder.gfx.shader.Vec4(1, 1, 1, 1), texture: treeAtlas(device), alphaCutoff: 0.5, doubleSided: true}), 16,
					{mode: Axis, columns: 2, rows: 1});
				Sprites.attach(world.node("trees"), trees);
				trees.count = 9;
				for (i in 0...9) {
					var x = -3.2 + i * 0.8, z = -1.5 - (i % 3) * 0.9, h = 1.1 + (i % 4) * 0.25;
					trees.set(i, x, h / 2, z, h * 0.7, h, 0, i % 2);
					trees.setColor(i, 0.7 + 0.1 * (i % 3), 0.9, 0.7);
				}
				var clouds = new Sprites(device,
					Material.unlit({color: new helder.gfx.shader.Vec4(1, 1, 1, 0.85), texture: softDisc(device), blend: true, fog: false}), 8);
				Sprites.attach(world.node("clouds"), clouds);
				clouds.count = 5;
				for (i in 0...5)
					clouds.set(i, -2.6 + i * 1.3, 2.4 + (i % 2) * 0.3, -3 + (i % 3) * 0.6, 1.6, 0.8, (i - 2) * 0.12);
				var lamps = Material.lambert({color: new helder.gfx.shader.Vec4(0.25, 0.25, 0.28, 1)});
				var post = Geometry.cylinder({radiusTop: 0.04, radiusBottom: 0.05, height: 1, radialSegments: 8});
				var halos = new Sprites(device,
					Material.unlit({color: new helder.gfx.shader.Vec4(0.9, 0.5, 0.15, 1), texture: softDisc(device), blend: true, blending: Additive}), 4);
				Sprites.attach(world.node("halos"), halos);
				halos.count = 3;
				var postMesh = Shapes.of(device, post, lamps);
				for (i in 0...3) {
					var x = -1.6 + i * 1.6;
					var n = world.node();
					n.position = new Vec3(x, 0.5, 0.6);
					MeshRenderer.attach(n, postMesh);
					halos.set(i, x, 1.05, 0.6, 0.7, 0.7);
					halos.setColor(i, 1, 1 - i * 0.25, 0.5 + i * 0.5);
				}
				var sun = world.node("sun");
				Light.attach(sun, Light.directional(new Vec3(1, 0.9, 0.8), 1.6));
				sun.rotation = helder.scene.math.Quat.fromEuler(-0.6, 0.4, 0);
				var eye = world.node("eye");
				var camera = Camera.attach(eye, Camera.perspective(0.85, 0.1, 50));
				eye.position = new Vec3(0, 1.6, 4.6);
				eye.lookAt(new Vec3(0, 0.9, -1));
				probe = () -> r.draws == 5 && r.instanced == 20 ? null : '${r.draws} draws, ${r.instanced} instanced (5, 20: the floor, three posts in one, trees, clouds, halos)';
				enc -> r.draw(enc, world, camera);
			case "hemisphere":
				// a hemisphere light alone (Light.hemisphere: a sky's blue from
				// above, a ground's brown from below, three's HemisphereLight):
				// lambert and standard spheres, a rough metal one, boxes
				var r = new Renderer(device);
				renderer = r;
				r.clearColor = new Color(0.08, 0.1, 0.14);
				var world = new World();
				Light.attach(world.node("sky"), Light.hemisphere(new Vec3(0.55, 0.7, 1.0), new Vec3(0.45, 0.28, 0.12), 1.6));
				var white = new helder.gfx.shader.Vec4(0.9, 0.9, 0.9, 1);
				var ms = [Material.lambert({color: white}), Material.standard({color: white, roughness: 0.6}), Material.standard({color: white, metallic: 1, roughness: 0.35})];
				for (i in 0...3) {
					var n = world.node();
					n.position = new Vec3(-1.3 + i * 1.3, 0.55, 0);
					MeshRenderer.attach(n, Shapes.of(device, Geometry.sphere({radius: 0.5}), ms[i]));
					var b = world.node();
					b.position = new Vec3(-1.3 + i * 1.3, -0.45, 0);
					b.rotation = helder.scene.math.Quat.fromEuler(0.5, 0.7, 0);
					MeshRenderer.attach(b, Shapes.of(device, Geometry.box({width: 0.55, height: 0.55, depth: 0.55}), ms[i]));
				}
				var eye = world.node("eye");
				var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 50));
				eye.position = new Vec3(0, 0.6, 4.2);
				eye.lookAt(new Vec3(0, 0.25, 0));
				enc -> r.draw(enc, world, camera);
			case n if (EffectScenes.NAMES.contains(n)): EffectScenes.make(n, device);
			case n if (LineScenes.NAMES.contains(n)): LineScenes.make(n, device);
			case n: throw 'Scenes: no scene $n';
		}
	}

	// two trees side by side in a 2 x 1 atlas (64 x 64 each, cut out by
	// alpha): a fir's triangles and a round crown on a trunk
	public static function treeAtlas(device:Device):Texture {
		var w = 128, h = 64, px = haxe.io.Bytes.alloc(w * h * 4);
		for (y in 0...h)
			for (x in 0...w) {
				var cell = x >> 6, u = (x & 63) / 63 * 2 - 1, v = y / 63;
				var trunk = Math.abs(u) < 0.09 && v > 0.78;
				var crown = cell == 0 ? Math.abs(u) < (v - 0.05) * 0.85 && v < 0.82 && (v * 3 % 1 > 0.15 || Math.abs(u) < (v - 0.05) * 0.6) : u * u + (v - 0.42) * (v - 0.42) * 1.6 < 0.36;
				var o = (y * w + x) * 4;
				if (crown) {
					var shadeK = 0.75 + 0.25 * (1 - v) - 0.15 * u;
					px.set(o, Std.int((cell == 0 ? 40 : 70) * shadeK));
					px.set(o + 1, Std.int((cell == 0 ? 120 : 150) * shadeK));
					px.set(o + 2, Std.int(50 * shadeK));
					px.set(o + 3, 255);
				} else if (trunk) {
					px.set(o, 110);
					px.set(o + 1, 75);
					px.set(o + 2, 45);
					px.set(o + 3, 255);
				}
			}
		return device.createTexture({width: w, height: h, data: px});
	}

	// a white disc fading out from its middle (32 x 32, alpha)
	public static function softDisc(device:Device):Texture {
		var size = 32, px = haxe.io.Bytes.alloc(size * size * 4);
		for (y in 0...size)
			for (x in 0...size) {
				var u = (x + 0.5) / size * 2 - 1, v = (y + 0.5) / size * 2 - 1;
				var a = Math.max(0, 1 - Math.sqrt(u * u + v * v));
				var o = (y * size + x) * 4;
				px.set(o, 255);
				px.set(o + 1, 255);
				px.set(o + 2, 255);
				px.set(o + 3, Std.int(a * a * (3 - 2 * a) * 255));
			}
		return device.createTexture({width: size, height: size, data: px});
	}

	// a matcap drawn in code: a sphere lit from the upper left, a warm key
	// and a cool rim (64x64 sRGB)
	public static function matcapImage(device:Device):Texture {
		var size = 64, px = haxe.io.Bytes.alloc(size * size * 4);
		for (y in 0...size)
			for (x in 0...size) {
				var u = (x + 0.5) / size * 2 - 1, v = 1 - (y + 0.5) / size * 2;
				var d = u * u + v * v, z = Math.sqrt(Math.max(0, 1 - d));
				var key = Math.max(0, -0.5 * u + 0.6 * v + 0.62 * z), rim = Math.pow(1 - z, 3);
				var spec = Math.pow(key, 24);
				function ch(k:Float, base:Float, cool:Float):Int
					return Std.int(Math.min(255, Math.pow(Math.min(1, base * (0.12 + 0.9 * key) + cool * rim + spec * k), 1 / 2.2) * 255));
				var o = (y * size + x) * 4;
				px.set(o, ch(1, 0.85, 0.15));
				px.set(o + 1, ch(1, 0.8, 0.35));
				px.set(o + 2, ch(1, 0.75, 0.7));
				px.set(o + 3, 255);
			}
		return device.createTexture({width: size, height: size, data: px});
	}
}
