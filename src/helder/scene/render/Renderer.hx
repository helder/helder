package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Mat4;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.Camera;
import helder.scene.Node;
import helder.scene.World;
import helder.scene.math.MathTools;
import helder.scene.render.PbrShader;
import helder.scene.render.PbrInstancedShader;
import helder.scene.render.PbrShader.PbrSunShader;
import helder.scene.render.PbrInstancedShader.PbrInstancedSunShader;
import helder.scene.render.PbrShader.PbrUntiledShader;
import helder.scene.render.PbrInstancedShader.PbrInstancedUntiledShader;
import helder.scene.render.PbrShader.materialOf;
import helder.scene.render.PbrShader.materialInto;
import helder.scene.render.PbrShader.output;

// Draws a world's meshes (MeshRenderer) as seen by a camera, lit by its
// first directional Light (a world without lights: the renderer's sun),
// its point and spot Lights (the frame's MAX_LIGHTS most important to the
// view, FrameLights: each draw lit by the eight that reach it most, or
// each pixel by its cell's with ClusteredLights) and an ambient from the
// sky and the ground, with PbrShader. The passes a frame records, in order
// (all but the main one opted in): instance culling (InstanceCulling: a
// compute pass where the device has one), the shadow atlas (Shadows), the
// lights' cells (ClusteredLights: a compute pass where it can), the view
// buffers' prepass (ViewBuffers: depth, normals, roughness and selection,
// for post's effects), the screen's ambient occlusion (post.ao: Ssao), the
// main pass, then the AfterPass hooks; post (PostProcess) after, into the
// image shown. Two stages:
//
//   extract   the world's meshes into a flat draw list: the nodes shown,
//             their level (Lod) and their visible range, their bounds
//             inside the camera's view, a draw per primitive sorted by
//             pipeline, material and primitive; runs of one primitive
//             become one instanced draw (PbrInstancedShader: the matrices
//             in an instance buffer), each run's light list from its
//             bounds; the seam for threads
//   record    the list as one depth-tested pass into the caller's encoder
//             (see-through materials last, farthest first, blended),
//             each draw's matrices and material in uniform blocks through
//             gfx's uniform ring (nothing allocated per frame: the list's
//             entries are kept)
//
// It is ordinary gfx code: draw records into the caller's encoder, so a
// program adds its own passes before or after; each camera of a world
// (split screens, XR's eyes) is a draw of its own.
class Renderer {
	public final device:Device;
	// the instanced pipelines' two buffers: the mesh's vertices, the instances' matrices
	static final INSTANCED_LAYOUT:Array<VertexBufferLayout> = [
		{
			stride: 32,
			attributes: [{location: 0, format: Float3, offset: 0}, {location: 1, format: Float3, offset: 12}, {location: 2, format: Float2, offset: 24}]
		},
		{
			stride: 64,
			step: Instance,
			attributes: [
				{location: 3, format: Float4, offset: 0}, {location: 4, format: Float4, offset: 16}, {location: 5, format: Float4, offset: 32},
				{location: 6, format: Float4, offset: 48}
			]
		}
	];
	// (a skinned vertex: position, normal, uvs, joints, weights)
	static final SKINNED_LAYOUT:VertexBufferLayout = {
		stride: 64,
		attributes: [
			{location: 0, format: Float3, offset: 0}, {location: 1, format: Float3, offset: 12}, {location: 2, format: Float2, offset: 24},
			{location: 3, format: Float4, offset: 32}, {location: 4, format: Float4, offset: 48}
		]
	};
	// without a Light in the world: towards the light (normalized when
	// drawn), and its colour times intensity
	public var sunDirection = new Vec3(-0.4, 0.8, 0.45);
	// (no tint: MeshRenderer.tint's default)
	public static final WHITE = new Vec3(1, 1, 1);
	public var sunColor = new Vec3(2.1, 1.95, 1.8);
	public var sky = new Vec3(0.3, 0.36, 0.48);
	public var ground = new Vec3(0.12, 0.1, 0.09);
	public var exposure = 1.0;
	// a rim light from the sun's side: its colour times intensity (black:
	// none) and how tight to the silhouette it stays (the falloff's power)
	public var rim = new Vec3(0, 0, 0);
	public var rimPower = 4.0;
	// fog over the scene (Fog: colour, density, start, height falloff;
	// null: none), taken by the standard material, Sky, Environment and
	// GpuParticles; a material opts out with Material.fog
	public var fog:Null<Fog> = null;
	public var clearColor = new Vec4(0.07, 0.08, 0.1, 1);
	// the last draw's draws in its main pass and primitives culled
	// (statistics); its shadow maps' draws (Shadows: every cascade's; 0
	// without); every renderer's by pass in helder.gfx.FrameCounts
	// (sceneDraws, shadowDraws, postDraws: PostProcess.draws)
	public var draws(default, null) = 0;
	public var culled(default, null) = 0;
	// the last draw's primitives not drawn as hidden behind others
	// (Occlusion: its queries of the frames before; 0 without)
	public var occluded(default, null) = 0;
	public var shadowDraws(default, null) = 0;
	// the view buffers' prepass draws (ViewBuffers; 0 without)
	public var prepassDraws(default, null) = 0;
	// a sub-pixel offset of the projection this frame, in pixels of the
	// target (x right, y down; 0, 0: none): temporal antialiasing's
	// (post.taa: Taa sets it before each frame), the view buffers' and
	// the main pass's alike; the motion the view buffers record leaves it out
	public var jitter:helder.gfx.shader.Vec2 = new helder.gfx.shader.Vec2(0, 0);
	// the frames drawn (each draw one)
	public var frames(default, null) = 0;
	// the frame's point and spot lights (gathered by draw: what the draws'
	// lists, Shadows' tiles and ClusteredLights' cells are made of)
	@:noCompletion public final frameLights = new FrameLights();

	// the opaque materials' pipelines (plain, double-sided, instanced, both),
	// made when first drawn: each a full fragment stage to compile, seconds
	// on a software GPU (SwiftShader: the page stalled while the four were)
	final opaquePipelines:Array<Null<Pipeline>> = [for (_ in 0...12) null];
	// whether no local light casts this frame (its tiles: none): the opaque
	// standard materials drawn by the untiled variants (PbrUntiledShader)
	var untiled = false;
	// whether this frame has no local lights (and no ClusteredLights): its
	// opaque standard materials drawn by the sun-only variants (PbrSunShader,
	// no light loop: their compile as before phase 4's lights)
	var sunOnly = false;
	// (see-through materials: made when first drawn)
	// the see-through materials' pipelines, made when first drawn: by
	// Material.blending, then double-sided
	final blendedPipelines:Array<Null<Pipeline>> = [for (_ in 0...8) null];
	final plainSlots:Array<Int>;
	final sunSlots:Array<Int>;
	final sunInstancedSlots:Array<Int>;
	final untiledSlots:Array<Int>;
	final untiledInstancedSlots:Array<Int>;
	var skinSource:Null<RenderFeature.SkinSource>;
	var normalSource:Null<RenderFeature.NormalSource>;
	// (the physical shader of the materials with glTF extensions and no
	// shader of their own: Physical's, every extension's; null: the standard)
	var physical:Null<RenderFeature.PhysicalSource> = null;
	// (the opaque frame behind see-through surfaces: Transmission; this
	// frame's copy, null before it or without; whether the frame's list has
	// a surface a physical shader refracts through)
	var transmissionSource:Null<RenderFeature.TransmissionSource> = null;
	var behind:Null<Texture> = null;
	var behindLevels = 0.0;
	var refracts = false;
	// the last draw's main pass split for Transmission's copy (1: the frame
	// behind its see-through surfaces copied; statistics)
	public var splits(default, null) = 0;
	final black:Texture;
	final flatNormal:Texture;
	final mipClamped:Sampler;
	var environment:Null<Environment>;
	// (the view buffers: ViewBuffers, attached by use or by post's effects)
	var views:Null<RenderFeature.ViewSource>;
	// (the frame's ambient occlusion: post.ao's, null without)
	var occlusion:Null<Texture> = null;
	// (drawInto's target size; 0: the device's)
	var targetWidth = 0;
	var targetHeight = 0;
	final instancedSlots:Array<Int>;
	// whether runs of one primitive are drawn instanced (on by default)
	public var instancing = true;
	// the last draw's instances drawn by instanced draws (statistics)
	public var instanced(default, null) = 0;
	// (the batches: a start in the list, a size, an offset in the instance buffer)
	final batchStart:Array<Int> = [];
	final batchSize:Array<Int> = [];
	final batchOffset:Array<Int> = [];
	var batchCount = 0;
	var instanceBytes = Bytes.alloc(64 * 64);
	var instanceBuffer:Buffer = Buffer.NONE;
	var instanceCapacity = 0;
	final white:Texture;
	final sampler:Sampler;
	final nearest:Sampler;
	final clamped:Sampler;
	// (no shadows: a 1x1 map, never read; no ClusteredLights: its textures', 1x1)
	final noShadow:Texture;
	var shadowSource:Null<RenderFeature.ShadowSource>;
	var clusterSource:Null<RenderFeature.ClusterSource>;
	var cullSource:Null<RenderFeature.CullSource>;
	// (Probes': the standard material's opaque draws lit by probes)
	var probeSource:Null<RenderFeature.ProbeSource>;
	// (AreaLights': the standard material's opaque draws' area lights by LTC)
	var areaSource:Null<RenderFeature.AreaSource>;
	// (Lightmaps': the standard material's opaque draws of lightmapped nodes)
	var lightmapSource:Null<RenderFeature.LightmapSource>;
	// (Sky's, when used: a twin draws it too)
	var skyFeature:Null<Sky> = null;
	// (a twin capturing a cube's faces: its views mirrored, its faces' winding turned)
	var mirrored = false;
	final frameBytes = Bytes.alloc(PbrShader.uniforms[0].size);
	// (the frame's lights' texture's rows, PbrShader's lightTexel: a row a
	// light, then the shadow tiles' rows)
	static inline var TILES = FrameLights.MAX_LIGHTS * FrameLights.ROW;
	final lightBytes = Bytes.alloc(FrameLights.ROWS * FrameLights.ROW);
	// (the textures they are written into, in turn, each one's rows beside:
	// a write lands before the GPU draws what was recorded before it on
	// Metal and WebGPU, so one is written again only after the others; rows
	// the same as one's, that one is bound, unwritten. Eight: a cube's six
	// faces and a view between frames in flight)
	static inline var LIGHT_TEXTURES = 8;
	final lightTextures:Array<Texture> = [];
	final lightRows:Array<Bytes> = [];
	var lightNext = 0;
	var lightTexture:Null<Texture> = null;
	// (each batch's lights, each instanced set's: FrameLights.PER_DRAW rows of the frame's lights)
	final batchLights:Array<Float> = [];
	final setLights:Array<Float> = [];
	// (the blocks as written, kept: a struct literal per write would allocate)
	final frameBlock:PbrFrame = blankFrame();
	@:allow(helder.scene.render) final objectBlock:PbrObject = {
		model: Mat4.identity(),
		normalMatrix: Mat4.identity(),
		tint: new Vec4(1, 1, 1, 1),
		lights0: new Vec4(-1, -1, -1, -1),
		lights1: new Vec4(-1, -1, -1, -1)
	};
	@:allow(helder.scene.render) final materialBlock:PbrMaterial = materialOf(new Material());
	final objectBytes = Bytes.alloc(PbrShader.uniforms[1].size);
	final materialBytes = Bytes.alloc(PbrShader.uniforms[2].size);
	final pass:PassDesc;
	// the draw list: entries kept between frames, count of them in use
	final list:Array<DrawItem> = [];
	var count = 0;
	// the frame's instanced sets (InstancedMesh), setCount of them in use
	final sets:Array<InstancedMesh> = [];
	var setCount = 0;

	// offscreen: drawn into textures (drawInto: RGBA8 and Depth32F, as a
	// <Scene>'s box in a ui), not the frame; its features' pipelines (skins,
	// normal maps, the sky, particles) made for those too (createPipeline)
	public final offscreen:Bool;
	// offscreen: the targets' samples a pixel (4: multisampled, drawInto's
	// color and depth made with samples: 4, the colour resolved by the pass)
	public final samples:Int;
	// offscreen: drawn in linear light into half-float targets (RGBA16F:
	// light brighter than white kept), tone mapped after by a PostProcess
	// (a <Scene>'s box runs post's); false: tone mapped and encoded by the
	// shaders themselves into RGBA8
	public final hdr:Bool;
	// the colour targets' format: RGBA16F with hdr, else RGBA8
	public final colorFormat:TextureFormat;
	// hdr: what turns the frame into the 8-bit image shown (bloom, tone
	// mapping, grading); a <Scene>'s box makes one when there is none
	public var post:Null<PostProcess> = null;

	public function new(device:Device, offscreen = false, samples = 1, hdr = false) {
		this.device = device;
		this.offscreen = offscreen;
		this.samples = offscreen ? samples : 1;
		this.hdr = offscreen && hdr;
		colorFormat = this.hdr ? RGBA16F : RGBA8;
		plainSlots = slotsOf(PbrShader.uniforms, PbrShader.textures);
		instancedSlots = slotsOf(PbrInstancedShader.uniforms, PbrInstancedShader.textures);
		sunSlots = slotsOf(PbrSunShader.uniforms, PbrSunShader.textures);
		sunInstancedSlots = slotsOf(PbrInstancedSunShader.uniforms, PbrInstancedSunShader.textures);
		untiledSlots = slotsOf(PbrUntiledShader.uniforms, PbrUntiledShader.textures);
		untiledInstancedSlots = slotsOf(PbrInstancedUntiledShader.uniforms, PbrInstancedUntiledShader.textures);
		var w = Bytes.alloc(4);
		w.fill(0, 4, 255);
		white = device.createTexture({width: 1, height: 1, data: w});
		sampler = device.createSampler({filter: Linear, mipFilter: Linear, wrap: Repeat});
		nearest = device.createSampler({filter: Nearest, wrap: Clamp});
		clamped = device.createSampler({filter: Linear, wrap: Clamp});
		var one = Bytes.alloc(4);
		one.setFloat(0, 1);
		noShadow = device.createTexture({width: 1, height: 1, format: R32F, data: one});
		var k = Bytes.alloc(4);
		k.set(3, 255);
		black = device.createTexture({width: 1, height: 1, data: k});
		var f = Bytes.alloc(4);
		f.set(0, 128);
		f.set(1, 128);
		f.set(2, 255);
		f.set(3, 255);
		flatNormal = device.createTexture({width: 1, height: 1, data: f});
		mipClamped = device.createSampler({filter: Linear, mipFilter: Linear, wrap: Clamp});
		frameLights.writeTexels(lightBytes);
		uploadLights();
		pass = {colors: [{load: Clear, clear: clearColor}], depth: {load: Clear}};
	}

	// a pipeline for what it draws into: the frame, or drawInto's targets
	// (RGBA8, Depth32F, its samples); its features' and a program's own
	// passes inside its frame (inject) make theirs with it
	public function createPipeline(d:PipelineDesc):Pipeline
		return create(d);

	function create(d:PipelineDesc):Pipeline {
		if (mirrored) d.cull = d.cull == Back ? Front : d.cull == Front ? Back : d.cull;
		if (offscreen) {
			d.colorFormat = colorFormat;
			d.depthFormat = Depth32F;
			d.samples = samples;
		}
		return device.createPipeline(d);
	}

	// draw into color (colorFormat, a render target) and depth (Depth32F, its size), an offscreen renderer's
	// (multisampled, samples > 1: color and depth of those samples, color
	// resolved into resolve, a single-sampled RGBA8 render target)
	// (layer: color's, a cube's face or a 2D array's layer)
	public function drawInto(enc:Encoder, world:World, camera:Camera, color:Texture, depth:Texture, width:Int, height:Int, ?resolve:Texture, layer = 0) {
		if (!offscreen) throw "helder.scene: drawInto needs an offscreen Renderer (new Renderer(device, true))";
		pass.colors[0].texture = color;
		pass.colors[0].resolve = resolve;
		pass.colors[0].layer = layer;
		pass.depth.texture = depth;
		targetWidth = width;
		targetHeight = height;
		draw(enc, world, camera, width / Math.max(1, height));
		pass.colors[0].texture = null;
		pass.colors[0].resolve = null;
		pass.colors[0].layer = 0;
		pass.depth.texture = null;
		targetWidth = targetHeight = 0;
	}

	// (Probes' captures) an offscreen HDR renderer of this one's light (copyInto),
	// its sky and environment, its shadows and physical materials; mirrored
	function twin():Renderer {
		var t = new Renderer(device, true, 1, true);
		t.mirrored = true;
		t.shadowSource = shadowSource;
		t.physical = physical;
		if (skyFeature != null) skyFeature.attach(t);
		if (environment != null) environment.attach(t);
		return t;
	}

	// (a twin's) this one's light, sky, ground, fog and exposure
	function copyInto(t:Renderer) {
		t.sunDirection = sunDirection;
		t.sunColor = sunColor;
		t.sky = sky;
		t.ground = ground;
		t.exposure = exposure;
		t.rim = rim;
		t.rimPower = rimPower;
		t.fog = fog;
		t.clearColor = clearColor;
		if (environment != null && t.environment != environment) environment.attach(t);
	}

	// what the frame's hooks get: the camera's view, the light (FrameInfo)
	public final frame = new FrameInfo();
	final hooks:Array<Array<(Encoder, FrameInfo) -> Void>> = [[], [], [], [], []];
	// (the line renderer, LineRenderer.of's: attached by use, by DebugDraw or by
	// markup; the debug drawing, DebugDraw.of's)
	var lines:Null<RenderFeature> = null;
	var debug:Null<RenderFeature> = null;

	// f runs at a point of each frame: BeforeOpaque, AfterOpaque and
	// AfterTransparent inside the frame's pass (draw with your own
	// pipelines, depth-tested against the scene; AfterTransparent after the
	// see-through surfaces too: what is drawn over everything), AfterPass
	// after it (passes of your own: an overlay), BeforePass before the
	// frame's passes (a texture of your own the frame reads)
	public function inject(point:InjectionPoint, f:(Encoder, FrameInfo) -> Void)
		hooks[point].push(f);

	// turns on an optional feature (Shadows, Skinning, NormalMaps, Sky,
	// Environment, ClusteredLights, InstanceCulling); returns the renderer
	public function use(feature:RenderFeature):Renderer {
		feature.attach(this);
		return this;
	}

	// records the frame's pass: world seen by camera (aspect: the target's,
	// by default the device's)
	public function draw(enc:Encoder, world:World, camera:Camera, ?aspect:Float) {
		if (aspect == null) aspect = device.width / device.height;
		var still = camera.viewProjection(aspect);
		// (morph targets blended where their weights changed: Morph)
		if (Morph.updateWorld != null) Morph.updateWorld(world);
		var width = targetWidth > 0 ? targetWidth : device.width, height = targetHeight > 0 ? targetHeight : device.height;
		frame.width = width;
		frame.height = height;
		// (post's effects' needs first: the view buffers, whose groups the
		// draw list takes; temporal antialiasing's jitter)
		if (post != null) post.require(this);
		var jx = jitter.x * 2 / width, jy = -jitter.y * 2 / height;
		var jittered = jx != 0 || jy != 0;
		var viewProj = jittered ? jitterOf(still, jx, jy) : still;
		var eye = camera.eye();
		// (occlusion's results of the frames before: the nodes hidden then, culled)
		if (occluder != null) occluder.prepare(this, world, viewProj, eye);
		// (the frame's local lights first: each draw's list is made as it is extracted)
		if (clusterSource != null) frameLights.reserve(clusterSource.capacity());
		frameLights.gather(world, eye, viewProj);
		sunOnly = frameLights.count == 0 && clusterSource == null;
		extractFrom(world, viewProj, eye);
		occlusion = null;
		var toLight = writeFrame(world, camera, viewProj, false);
		frame.world = world;
		frame.camera = camera;
		frame.aspect = aspect;
		frame.view = camera.view();
		var projection = camera.projection(aspect);
		frame.projection = jittered ? jitterOf(projection, jx, jy) : projection;
		frame.viewProj = viewProj;
		frame.jitter = new helder.gfx.shader.Vec2(jx, jy);
		frame.stillViewProj = still;
		frame.previousViewProj = frames > 0 && lastWorld == world ? lastViewProj : still;
		frame.index = frames;
		frame.eye = eye;
		frame.toLight = toLight;
		frame.hdr = hdr;
		frame.fog = fog;
		frame.exposure = exposure;
		for (f in hooks[BeforePass])
			f(enc, frame);
		lists();
		if (cullSource != null) cullSource.cull(enc, this, frame);
		shadowDraws = 0;
		var shadowed = false;
		if (shadowSource != null) {
			shadowSource.render(enc, this, toLight, frame);
			shadowed = true;
			shadowDraws = shadowSource.shadowFrame().draws;
			FrameCounts.shadowDraws += shadowDraws;
		}
		if (clusterSource != null) clusterSource.assign(enc, this, frame);
		untiled = true;
		for (k in 0...frameLights.count)
			if (frameLights.tile(k) >= 0) untiled = false;
		frameLights.writeTexels(lightBytes);
		writeFrame(world, camera, viewProj, shadowed);
		prepassDraws = 0;
		if (views != null) {
			views.render(enc, this, frame);
			prepassDraws = views.drawn();
			FrameCounts.prepassDraws += prepassDraws;
		}
		// (the screen's ambient occlusion from the view buffers, read by the main pass)
		if (post != null) {
			occlusion = post.occlusion(enc, frame);
			if (occlusion != null) writeFrame(world, camera, viewProj, shadowed);
		}
		record(enc);
		FrameCounts.sceneDraws += draws;
		for (f in hooks[AfterPass])
			f(enc, frame);
		lastViewProj = still;
		lastWorld = world;
		frames++;
	}

	// (the frame before's unjittered view-projection, and its world)
	var lastViewProj:Mat4 = Mat4.identity();
	var lastWorld:Null<World> = null;

	// (occlusion culling: Occlusion's, attached by use)
	var occluder:Null<RenderFeature.OcclusionSource> = null;

	// m with clip space moved by x, y (a sub-pixel jitter: each column's x
	// and y plus its w times the offset)
	static function jitterOf(m:Mat4, x:Float, y:Float):Mat4 {
		inline function moved(c:Vec4):Vec4
			return new Vec4(c.x + x * c.w, c.y + y * c.w, c.z, c.w);
		return new Mat4(moved(m.c0), moved(m.c1), moved(m.c2), moved(m.c3));
	}

	// the draw list: each shown mesh inside the view (at its level: Lod; in
	// its visible range), a draw per primitive, sorted (seen from the centre
	// of the view's near plane: the camera, a near plane's distance off)
	public inline function extract(world:World, viewProj:Mat4)
		extractFrom(world, viewProj, MathTools.transformPoint(MathTools.inverse(viewProj), new Vec3(0, 0, 0)));

	// extract's, seen from eye (the camera's; an optional Vec3 would be boxed)
	@:noCompletion public function extractFrom(world:World, viewProj:Mat4, eye:Vec3) {
		count = 0;
		culled = 0;
		occluded = 0;
		refracts = false;
		extractViewProj = viewProj;
		extractEye = eye;
		var meshes = world.store(MeshRenderer.KIND), tints = world.store(MeshRenderer.TINT);
		var levels = Lod.pick;
		var listed = clusterSource == null;
		for (k in 0...meshes.length) {
			var node = meshes.nodeAt(k), mesh = meshes.valueAt(k);
			if (!node.shown() || !world.inTree(node)) continue;
			var model = node.worldMatrix();
			// (its level of detail and its visible range: Lod's, linked by Lod.attach)
			if (levels != null) {
				var m = levels(node, mesh, this);
				if (m == null) {
					culled += mesh.primitives.length;
					continue;
				}
				mesh = m;
			}
			var skinned = mesh.primitives.length > 0 && mesh.primitives[0].skinned;
			// (skinned: drawn only with Skinning, its bounds its rest pose's: not culled)
			if (skinned && (skinSource == null || !skinSource.prepare(node))) continue;
			if (!skinned && !visible(viewProj * model, mesh)) {
				culled += mesh.primitives.length;
				continue;
			}
			// (hidden behind others the frames before: Occlusion's)
			if (occluder != null && occluder.hidden(node)) {
				occluded += mesh.primitives.length;
				FrameCounts.occluded += mesh.primitives.length;
				continue;
			}
			var tint = tints.get(node) ?? WHITE;
			// (its selection group: the view buffers', Outline.select)
			var group = views != null ? views.group(node) : 0;
			for (p in mesh.primitives) {
				if (count == list.length) list.push(new DrawItem());
				var d = list[count++];
				d.node = node;
				d.tint = tint;
				d.group = group;
				// (its lights: the eight of the frame's that reach its bounds most, by their rows)
				if (listed) {
					bx0 = by0 = bz0 = Math.POSITIVE_INFINITY;
					bx1 = by1 = bz1 = Math.NEGATIVE_INFINITY;
					grow(p.bounds, model);
					if (bx0 > bx1) frameLights.first(d.lights, 0) else {
						var dx = bx1 - bx0, dy = by1 - by0, dz = bz1 - bz0;
						frameLights.select((bx0 + bx1) / 2, (by0 + by1) / 2, (bz0 + bz1) / 2, Math.sqrt(dx * dx + dy * dy + dz * dz) / 2, d.lights, 0);
					}
					d.lightKey = DrawItem.keyOf(d.lights);
				} else {
					for (i in 0...FrameLights.PER_DRAW)
						d.lights[i] = -1;
					d.lightKey = 0;
				}
				d.primitive = p;
				// (the pipeline, then the material)
				d.key = (p.material.blended ? 1 << 26 : 0) | (mapped(p) ? 1 << 25 : 0) | (p.material.doubleSided ? 1 << 24 : 0) | (p.material.id & 0xFFFFFF);
				if (p.material.blended) {
					// (how far: the bounds' centre's depth in clip space)
					var b = p.bounds, c = viewProj * (model * new Vec4((b.min.x + b.max.x) / 2, (b.min.y + b.max.y) / 2, (b.min.z + b.max.z) / 2, 1));
					d.depth = c.w != 0 ? c.z / c.w : c.z;
					// (a physical shader's transmission: the opaque frame copied behind it)
					var s = shaderOf(p.material);
					if (p.material.transmission > 0 && s != null && s.extensions & Material.TRANSMISSION != 0) refracts = true;
				}
			}
		}
		// (the instanced sets: drawn whole while their node is shown)
		setCount = 0;
		var instancedSets = world.store(InstancedMesh.KIND);
		for (k in 0...instancedSets.length) {
			var node = instancedSets.nodeAt(k), s = instancedSets.valueAt(k);
			if (s.count == 0 || !node.shown() || !world.inTree(node)) continue;
			if (!s.bounds.isEmpty() && !visibleBox(viewProj, s.bounds)) {
				culled += s.mesh.primitives.length;
				continue;
			}
			if (setCount == sets.length) sets.push(s) else sets[setCount] = s;
			setCount++;
		}
		// (insertion sort: a scene's order changes little from frame to frame)
		for (i in 1...count) {
			var d = list[i], j = i - 1;
			while (j >= 0 && (list[j].key > d.key || list[j].key == d.key && (list[j].primitive.id > d.primitive.id || list[j].primitive == d.primitive && (list[j].group > d.group
				|| list[j].group == d.group && list[j].lightKey > d.lightKey)))) {
				list[j + 1] = list[j];
				j--;
			}
			list[j + 1] = d;
		}
		// (the see-through draws, last in the list: farthest first)
		var first = count;
		while (first > 0 && list[first - 1].primitive.material.blended)
			first--;
		for (i in first + 1...count) {
			var d = list[i], j = i - 1;
			while (j >= first && list[j].depth < d.depth) {
				list[j + 1] = list[j];
				j--;
			}
			list[j + 1] = d;
		}
		batch();
		// (their data to the GPU, before the pass: Sprites turned to the camera first)
		for (k in 0...setCount) {
			sets[k].prepare(viewProj);
			sets[k].upload(device);
		}
	}

	// (each batch's lights, its draws' (one list: a run joins draws of the
	// same list alone), and each set's: the eight the frame's that reach its
	// bounds most; none read with ClusteredLights)
	function lists() {
		var per = FrameLights.PER_DRAW;
		while (batchLights.length < batchCount * per)
			batchLights.push(-1);
		while (setLights.length < setCount * per)
			setLights.push(-1);
		var clustered = clusterSource != null;
		for (b in 0...batchCount) {
			var d = list[batchStart[b]];
			for (i in 0...per)
				batchLights[b * per + i] = clustered ? -1 : d.lights[i];
		}
		for (k in 0...setCount) {
			var s = sets[k];
			if (clustered) {
				for (i in 0...per)
					setLights[k * per + i] = -1;
			} else if (s.bounds.isEmpty()) frameLights.first(setLights, k * per) else {
				var b = s.bounds, dx = b.max.x - b.min.x, dy = b.max.y - b.min.y, dz = b.max.z - b.min.z;
				frameLights.select((b.min.x + b.max.x) / 2, (b.min.y + b.max.y) / 2, (b.min.z + b.max.z) / 2, Math.sqrt(dx * dx + dy * dy + dz * dz) / 2, setLights,
					k * per);
			}
		}
	}

	// (a draw's bounds in the world, grown by a box through a matrix: Arvo's, as numbers)
	var bx0 = 0.0;
	var by0 = 0.0;
	var bz0 = 0.0;
	var bx1 = 0.0;
	var by1 = 0.0;
	var bz1 = 0.0;

	function grow(b:helder.scene.math.Aabb, m:Mat4) {
		if (b.isEmpty()) return;
		var cx = (b.min.x + b.max.x) * 0.5, cy = (b.min.y + b.max.y) * 0.5, cz = (b.min.z + b.max.z) * 0.5;
		var hx = (b.max.x - b.min.x) * 0.5, hy = (b.max.y - b.min.y) * 0.5, hz = (b.max.z - b.min.z) * 0.5;
		var tc = m * new Vec4(cx, cy, cz, 1);
		var ex = Math.abs(m.c0.x) * hx + Math.abs(m.c1.x) * hy + Math.abs(m.c2.x) * hz;
		var ey = Math.abs(m.c0.y) * hx + Math.abs(m.c1.y) * hy + Math.abs(m.c2.y) * hz;
		var ez = Math.abs(m.c0.z) * hx + Math.abs(m.c1.z) * hy + Math.abs(m.c2.z) * hz;
		bx0 = Math.min(bx0, tc.x - ex);
		by0 = Math.min(by0, tc.y - ey);
		bz0 = Math.min(bz0, tc.z - ez);
		bx1 = Math.max(bx1, tc.x + ex);
		by1 = Math.max(by1, tc.y + ey);
		bz1 = Math.max(bz1, tc.z + ez);
	}

	// (the frame's block; returns the direction towards the light)
	function writeFrame(world:World, camera:Camera, viewProj:Mat4, shadowed:Bool):Vec3 {
		var eye = camera.eye();
		var l = sunDirection, c = sunColor;
		var lights = world.store(Light.KIND);
		var sun = false, hemisphere = false;
		var up = sky, down = ground;
		for (k in 0...lights.length) {
			var node = lights.nodeAt(k), light = lights.valueAt(k);
			if (!node.shown() || !world.inTree(node)) continue;
			if (light.kind == Hemisphere) {
				// (the world's first hemisphere light: the ambient, in place of sky and ground)
				if (!hemisphere) {
					up = light.color * light.intensity;
					down = light.groundColor * light.intensity;
					hemisphere = true;
				}
			} else if (light.local) {
				// (FrameLights': the lights' texture)
			} else if (!sun) {
				// (it shines down its node's -z: the light is towards +z)
				l = MathTools.transformDir(node.worldMatrix(), new Vec3(0, 0, 1));
				c = light.color * light.intensity;
				sun = true;
			}
		}
		// (lights in the world but no directional one: no sun)
		if (!sun && lights.length > 0) c = new Vec3(0, 0, 0);
		l = l / Math.sqrt(l.x * l.x + l.y * l.y + l.z * l.z);
		var lightViewProj:Mat4 = Mat4.identity(), lightViewProjFar:Mat4 = Mat4.identity();
		var shadow:Vec4 = new Vec4(0, 0, 0, 0), shadowFar:Vec4 = new Vec4(0, 0, 0, 0), soft:Vec4 = new Vec4(0, 0, 0, 0);
		var rect = new Vec4(0, 0, 1, 1), rectFar = rect, atlas = new Vec4(1, 1, 0, 0);
		if (shadowed) {
			var f = shadowSource.shadowFrame();
			lightViewProj = f.viewProj;
			shadow = f.params;
			lightViewProjFar = f.viewProjFar;
			shadowFar = f.paramsFar;
			soft = f.soft;
			rect = f.rect;
			rectFar = f.rectFar;
			atlas = f.atlas;
		}
		// (the block kept, its fields set: nothing allocated)
		var b = frameBlock;
		b.viewProj = viewProj;
		b.eye = new Vec4(eye.x, eye.y, eye.z, 1);
		b.lightDir = new Vec4(l.x, l.y, l.z, 0);
		b.lightColor = new Vec4(c.x, c.y, c.z, 0);
		b.sky = new Vec4(up.x, up.y, up.z, 0);
		b.ground = new Vec4(down.x, down.y, down.z, 0);
		b.exposure = new Vec4(exposure, hdr ? 1 : 0, occlusion != null ? 1 : 0, 0);
		b.lightViewProj = lightViewProj;
		b.shadow = shadow;
		b.lightViewProjFar = lightViewProjFar;
		b.shadowFar = shadowFar;
		b.shadowRect = rect;
		b.shadowRectFar = rectFar;
		b.shadowAtlas = atlas;
		b.environment = environment != null ? environment.frameVector() : new Vec4(0, 0, 0, 0);
		b.rim = new Vec4(rim.x, rim.y, rim.z, rimPower);
		b.fog = Fog.colorOf(fog);
		b.fogShape = Fog.shapeOf(fog);
		b.shadowSoft = soft;
		if (clusterSource != null) {
			var cf = clusterSource.clusterFrame();
			b.clusters = cf.clusters;
			b.clusterDepth = cf.depth;
			b.clusterAxis = cf.axis;
		} else
			b.clusters = b.clusterDepth = b.clusterAxis = new Vec4(0, 0, 0, 0);
		PbrShader.params.frame.write(b, frameBytes);
		// (the local lights' tiles, Shadows' bytes: the arrays as written are zeros, an Array<Mat4> would box what it holds)
		var tiles = shadowed ? shadowSource.shadowFrame().tiles : null;
		if (tiles != null) lightBytes.blit(TILES, tiles, 0, tiles.length);
		uploadLights();
		return l;
	}

	// (the frame's lights' rows into a texture of the turn's, or the one that has them)
	function uploadLights() {
		for (k in 0...lightTextures.length)
			if (lightRows[k].compare(lightBytes) == 0) {
				lightTexture = lightTextures[k];
				return;
			}
		if (lightTextures.length < LIGHT_TEXTURES) {
			lightTextures.push(lightTexture = device.createTexture({
				width: FrameLights.COLUMNS,
				height: FrameLights.ROWS,
				format: RGBA32F,
				data: lightBytes
			}));
			lightRows.push(lightBytes.sub(0, lightBytes.length));
			return;
		}
		var k = lightNext;
		lightNext = (k + 1) % LIGHT_TEXTURES;
		device.writeTexture(lightTexture = lightTextures[k], lightBytes);
		lightRows[k].blit(0, lightBytes, 0, lightBytes.length);
	}

	// a pipeline for the frame's pass, its frame's block and lights bound
	// (the lights, their shadows' tiles) when it is not the one bound
	function bindPipeline(enc:Encoder, p:Pipeline, slots:Array<Int>) {
		if (p == bound) return;
		enc.setPipeline(p);
		enc.setUniforms(slots[0], frameBytes);
		if (slots[18] >= 0) enc.setTexture(slots[18], lightTexture, nearest);
		bound = p;
	}

	// (the view extract draws for: Lod.pick's)
	var extractViewProj:Mat4 = Mat4.identity();
	var extractEye:Vec3 = new Vec3(0, 0, 0);

	// (the pipeline last bound in the frame's pass: null after a hook)
	var bound:Null<Pipeline> = null;

	function record(enc:Encoder) {
		helder.gfx.ColorTarget.ClearValue.set(pass.colors[0], clearColor.x, clearColor.y, clearColor.z, clearColor.w);
		enc.beginPass(pass);
		bound = null;
		for (f in hooks[BeforeOpaque])
			f(enc, frame);
		bound = null;
		var current:Null<Pipeline> = null, material:Null<Material> = null, node = Node.NONE;
		var slots = plainSlots;
		draws = 0;
		instanced = 0;
		var opaque = true;
		behind = null;
		splits = 0;
		recordSets(enc, false);
		current = null;
		for (b in 0...batchCount) {
			var start = batchStart[b], n = batchSize[b];
			var d = list[start], p = d.primitive, m = p.material;
			if (opaque && m.blended) {
				// (the hooks after the opaque surfaces, the sky's among them,
				// before the see-through ones; their pipelines are theirs;
				// then the see-through instanced sets: Sprites' halos)
				opaque = false;
				if (occluder != null) occluder.draw(enc, this);
				bound = null;
				for (f in hooks[AfterOpaque])
					f(enc, frame);
				// (the opaque frame copied, behind the physical shaders' transmission)
				if (refracts && transmissionSource != null && offscreen) split(enc);
				bound = null;
				recordSets(enc, true);
				current = null;
				material = null;
				node = Node.NONE;
			}
			var shader = shaderOf(m);
			if (m.transmission > 0 && !p.skinned && (shader == null || shader.extensions & Material.TRANSMISSION == 0)) {
				// (transmission: what is behind first tinted by the surface's
				// colour (Multiply), then its own light over it: the draw below)
				tint(enc, d, p, m, b);
				current = null;
				material = null;
				node = Node.NONE;
			}
			var many = n > 1;
			var skin = p.skinned ? skinSource : null;
			var normals = skin == null && mapped(p) ? normalSource : null;
			var own = shader != null ? custom(shader, m, many ? (normals != null ? 4 : 3) : skin != null ? 2 : normals != null ? 1 : 0) : null;
			// (lit by probes, area lights by LTC: the standard material's opaque draws, plain and instanced)
			var standard = own == null && skin == null && normals == null && !m.blended;
			// (a lightmapped node with second uvs: the lightmap variant, alone)
			var baked = lightmapSource != null && standard && !many && p.uv1 != null && lightmapSource.has(d.node);
			var probed = probeSource != null && standard && !baked;
			var areaLit = areaSource != null && frameLights.areas > 0 && standard && !baked;
			var want = baked ? lightmapSource.pipeline(m.doubleSided) : areaLit ? areaSource.pipeline(many, m.doubleSided, probed) : probed ? probeSource.pipeline(many, m.doubleSided) : own != null ? own.pipeline : many ? (normals != null ? normals.instancedPipeline(m.doubleSided) : opaquePipeline(true, m.doubleSided)) : skin != null ? skin.pipeline(m.doubleSided) : normals != null ? normals.pipeline(m.doubleSided) : m.blended ? blended(m) : opaquePipeline(false, m.doubleSided);
			if (want != current) {
				slots = baked ? lightmapSource.slots() : areaLit ? areaSource.slots(many, probed) : probed ? probeSource.slots(many) : own != null ? own.slots : many ? (normals != null ? normals.instancedSlots() : m.blended ? instancedSlots : sunOnly ? sunInstancedSlots : untiled ? untiledInstancedSlots : instancedSlots) : skin != null ? skin.slots() : normals != null ? normals.slots() : m.blended ? plainSlots : sunOnly ? sunSlots : untiled ? untiledSlots : plainSlots;
				bindPipeline(enc, want, slots);
				if (areaLit) areaSource.bind(enc, slots);
				current = want;
				material = null;
				node = Node.NONE;
			}
			if (many) {
				// (an instanced run: its matrices the instances', its block its light list)
				writeObject(Mat4.identity(), WHITE, batchLights, b * FrameLights.PER_DRAW);
				if (slots[1] >= 0) enc.setUniforms(slots[1], objectBytes);
				// (its probes the run's bounds')
				if (probed) bindRun(start, n, p, enc, slots);
				node = Node.NONE;
			} else if (d.node != node) {
				var model = d.node.worldMatrix(), t = d.tint;
				writeObject(model, t, batchLights, b * FrameLights.PER_DRAW, skin != null ? skin.rows(d.node) : 1);
				enc.setUniforms(slots[1], objectBytes);
				if (baked) lightmapSource.bind(enc, d.node);
				if (probed) {
					// (its bounds in the world: the centre moved, the half size by the matrix's absolute values)
					var c = p.bounds.center(), e = (p.bounds.max - p.bounds.min) * 0.5;
					var w = MathTools.transformPoint(model, c), x = MathTools.col(model, 0), y = MathTools.col(model, 1), z = MathTools.col(model, 2);
					probeSource.bind(enc, slots, w.x, w.y, w.z, Math.abs(x.x) * e.x + Math.abs(y.x) * e.y + Math.abs(z.x) * e.z,
						Math.abs(x.y) * e.x + Math.abs(y.y) * e.y + Math.abs(z.y) * e.z, Math.abs(x.z) * e.x + Math.abs(y.z) * e.y + Math.abs(z.z) * e.z);
				}
				node = d.node;
			}
			if (skin != null) skin.bind(enc, slots, d.node);
			if (m != material) {
				bindMaterial(enc, slots, m, normals);
				material = m;
			}
			enc.setVertexBuffer(0, p.vertices);
			if (normals != null) enc.setVertexBuffer(1, p.tangents);
			if (many) enc.setVertexBuffer(normals != null ? 2 : 1, instanceBuffer, batchOffset[b]);
			if (baked) enc.setVertexBuffer(1, p.uv1);
			// (each map its own uvs: the second uvs' buffer, after the others)
			if (shader != null && shader.extensions & Material.UV_SETS != 0)
				enc.setVertexBuffer(1 + (normals != null ? 1 : 0) + (many ? 1 : 0), p.uv1 != null ? p.uv1 : p.vertices);
			enc.setIndexBuffer(p.indices, p.indexFormat);
			enc.drawIndexed(p.count, n);
			draws++;
			if (many) instanced += n;
		}
		if (opaque) {
			if (occluder != null) occluder.draw(enc, this);
			bound = null;
			for (f in hooks[AfterOpaque])
				f(enc, frame);
			bound = null;
			recordSets(enc, true);
		}
		bound = null;
		for (f in hooks[AfterTransparent])
			f(enc, frame);
		enc.endPass();
		bound = null;
	}

	inline function lightmapped(n:Node):Bool
		return lightmapSource != null && lightmapSource.has(n);

	// an instanced run's probes (Probes): its draws' bounds' union's
	function bindRun(start:Int, n:Int, p:Mesh.Primitive, enc:Encoder, slots:Array<Int>) {
		var x0 = Math.POSITIVE_INFINITY, y0 = x0, z0 = x0, x1 = Math.NEGATIVE_INFINITY, y1 = x1, z1 = x1;
		var c = p.bounds.center(), e = (p.bounds.max - p.bounds.min) * 0.5;
		for (k in start...start + n) {
			var m = list[k].node.worldMatrix();
			var w = MathTools.transformPoint(m, c), a = MathTools.col(m, 0), b = MathTools.col(m, 1), d = MathTools.col(m, 2);
			var ex = Math.abs(a.x) * e.x + Math.abs(b.x) * e.y + Math.abs(d.x) * e.z;
			var ey = Math.abs(a.y) * e.x + Math.abs(b.y) * e.y + Math.abs(d.y) * e.z;
			var ez = Math.abs(a.z) * e.x + Math.abs(b.z) * e.y + Math.abs(d.z) * e.z;
			x0 = Math.min(x0, w.x - ex);
			y0 = Math.min(y0, w.y - ey);
			z0 = Math.min(z0, w.z - ez);
			x1 = Math.max(x1, w.x + ex);
			y1 = Math.max(y1, w.y + ey);
			z1 = Math.max(z1, w.z + ez);
		}
		probeSource.bind(enc, slots, (x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5, (x1 - x0) * 0.5, (y1 - y0) * 0.5, (z1 - z0) * 0.5);
	}

	// (the frame's pass ended after its opaque surfaces, its colour copied
	// by Transmission, the pass begun again where it was)
	function split(enc:Encoder) {
		behind = transmissionSource.capture(enc, pass, targetWidth, targetHeight, colorFormat);
		behindLevels = transmissionSource.levels();
		splits = 1;
	}

	// the shader a material is drawn with: its own, else Physical's where
	// its fields use a glTF extension, else null (the standard one)
	inline function shaderOf(m:Material):Null<MaterialShader>
		return m.shader != null ? m.shader : physical != null ? physical.shaderOf(m) : null;

	// (a node's block into objectBytes: its matrices, its tint, its light
	// list (lights' rows from at; none: -1s), w: a skin's joints' count)
	@:allow(helder.scene.render) function writeObject(model:Mat4, t:Vec3, ?lights:Array<Float>, at = 0, w = 1.0) {
		var o = objectBlock;
		o.model = model;
		o.normalMatrix = MathTools.normalMatrix(model);
		o.tint = new Vec4(t.x, t.y, t.z, w);
		if (lights != null) {
			o.lights0 = new Vec4(lights[at], lights[at + 1], lights[at + 2], lights[at + 3]);
			o.lights1 = new Vec4(lights[at + 4], lights[at + 5], lights[at + 6], lights[at + 7]);
		} else
			o.lights0 = o.lights1 = new Vec4(-1, -1, -1, -1);
		PbrShader.params.object.write(o, objectBytes);
	}

	static function blankFrame():PbrFrame {
		var z = new Vec4(0, 0, 0, 0), m = Mat4.identity();
		return {
			viewProj: m, eye: z, lightDir: z, lightColor: z, sky: z, ground: z, exposure: z, lightViewProj: m, shadow: z, lightViewProjFar: m, shadowFar: z,
			shadowRect: z, shadowRectFar: z, shadowAtlas: z, environment: z, rim: z, fog: z, fogShape: z, shadowSoft: z, clusters: z, clusterDepth: z,
			clusterAxis: z
		};
	}

	// the instanced sets (InstancedMesh, Sprites) of the frame, each
	// primitive one instanced draw with their own buffer: the opaque ones
	// first in the pass, the see-through ones (blended: false, true) after
	// the opaque surfaces and their hooks, in the sets' order (a set sorts
	// its own instances: Sprites)
	function recordSets(enc:Encoder, blended:Bool) {
		for (k in 0...setCount) {
			var s = sets[k];
			var culls = cullSource != null && cullSource.takes(s);
			var levels = culls ? s.levels : null;
			for (level in 0...(levels != null ? levels.length : 1)) {
				var mesh = levels != null ? levels[level].mesh : s.mesh;
				for (i in 0...mesh.primitives.length) {
					var p = mesh.primitives[i];
					if (p.skinned || p.material.blended != blended) continue;
					var m = p.material;
					var normals = mapped(p) ? normalSource : null;
					var shader = shaderOf(m);
					var own = shader != null ? custom(shader, m, normals != null ? 4 : 3) : null;
					var slots = own != null ? own.slots : normals != null ? normals.instancedSlots() : m.blended ? instancedSlots : sunOnly ? sunInstancedSlots : untiled ? untiledInstancedSlots : instancedSlots;
					bindPipeline(enc, own != null ? own.pipeline : normals != null ? normals.instancedPipeline(m.doubleSided) : m.blended ? blendedInstanced(m) : opaquePipeline(true, m.doubleSided),
						slots);
					writeObject(Mat4.identity(), WHITE, setLights, k * FrameLights.PER_DRAW);
					if (slots[1] >= 0) enc.setUniforms(slots[1], objectBytes);
					bindMaterial(enc, slots, m, normals);
					enc.setVertexBuffer(0, p.vertices);
					if (normals != null) enc.setVertexBuffer(1, p.tangents);
					// (the second uvs after the instances' buffer: a physical shader's with uvSets)
					if (shader != null && shader.extensions & Material.UV_SETS != 0) enc.setVertexBuffer(normals != null ? 3 : 2, p.uv1 != null ? p.uv1 : p.vertices);
					enc.setIndexBuffer(p.indices, p.indexFormat);
					if (culls) {
						// (its instances culled, at their level: the culling's buffer and counts)
						draws += cullSource.draw(enc, s, i, level, normals != null ? 2 : 1);
						continue;
					}
					enc.setVertexBuffer(normals != null ? 2 : 1, s.buffer);
					enc.drawIndexed(p.count, s.count);
					draws++;
					instanced += s.count;
				}
			}
		}
	}

	// a material's block and textures, at a shader's slots
	function bindMaterial(enc:Encoder, slots:Array<Int>, m:Material, normals:Null<RenderFeature.NormalSource>) {
		var block = materialInto(m, materialBlock);
		// (a physical shader's: the glTF extensions' fields, the frame behind)
		var layers = slots[14] >= 0 ? shaderOf(m).layers : null;
		if (layers != null) layers.block(m, block, behind != null ? behindLevels : 0);
		PbrShader.params.material.write(block, materialBytes);
		enc.setUniforms(slots[2], materialBytes);
		var ms = m.sampler != null ? m.sampler : sampler;
		enc.setTexture(slots[3], m.baseColorTexture != null ? m.baseColorTexture : white, ms);
		enc.setTexture(slots[7], m.metallicRoughnessTexture != null ? m.metallicRoughnessTexture : white, ms);
		enc.setTexture(slots[8], m.emissiveTexture != null ? m.emissiveTexture : white, ms);
		enc.setTexture(slots[9], m.occlusionTexture != null ? m.occlusionTexture : white, ms);
		var sf = shadowSource != null ? shadowSource.shadowFrame() : null;
		enc.setTexture(slots[4], sf != null ? sf.map : noShadow, nearest);
		bindClusters(enc, slots);
		if (environment != null) environment.bind(enc, slots[12]) else enc.setTexture(slots[12], white, sampler);
		if (slots[13] >= 0) enc.setTexture(slots[13], occlusion != null ? occlusion : white, clamped);
		if (normals != null) enc.setTexture(slots[10], m.normalTexture != null ? m.normalTexture : flatNormal, ms);
		if (layers != null) layers.bind(enc, slots, ms, white, behind != null ? behind : black, mipClamped);
		// (a shader of its own: its own blocks, after the renderer's slots)
		if (m.shader != null && m.uniforms != null) bindOwn(enc, slots, m);
	}

	// ClusteredLights' map (its cells' lists and its lights; without, a 1x1 texel never read)
	inline function bindClusters(enc:Encoder, slots:Array<Int>) {
		var cf = clusterSource != null ? clusterSource.clusterFrame() : null;
		if (slots[11] >= 0) enc.setTexture(slots[11], cf != null ? cf.clusterMap : noShadow, nearest);
	}

	// a material's own blocks (MaterialShader's) at a variant's slots: after the renderer's (OWN)
	@:allow(helder.scene.render) function bindOwn(enc:Encoder, slots:Array<Int>, m:Material)
		for (i in 0...m.shader.blocks.length) {
			var bytes = m.uniforms.get(m.shader.blocks[i].name);
			if (bytes != null && slots[OWN + i] >= 0) enc.setUniforms(slots[OWN + i], bytes);
		}

	// where a variant's slots of a material's own blocks begin (slotsOf's length)
	public static inline var OWN = 24;

	// a material's own shader's pipeline and slots for a kind of draw (0
	// plain, 1 normal mapped, 2 skinned, 3 instanced, 4 instanced and normal
	// mapped), made when first drawn; its own blocks' slots after the renderer's
	// an opaque material's pipeline (opaquePipelines), made the first time
	function opaquePipeline(instanced:Bool, doubleSided:Bool):Pipeline {
		var k = (sunOnly ? 4 : untiled ? 8 : 0) + (instanced ? 2 : 0) + (doubleSided ? 1 : 0);
		var p = opaquePipelines[k];
		if (p == null) {
			var cull:helder.gfx.Cull = doubleSided ? None : Back;
			if (instanced) {
				var d = sunOnly ? PbrInstancedSunShader.pipeline({cull: cull, depthCompare: Less, depthWrite: true}) : untiled ? PbrInstancedUntiledShader.pipeline({
					cull: cull, depthCompare: Less, depthWrite: true}) : PbrInstancedShader.pipeline({cull: cull, depthCompare: Less, depthWrite: true});
				d.layout = INSTANCED_LAYOUT;
				p = create(d);
			} else
				p = create(sunOnly ? PbrSunShader.pipeline({cull: cull, depthCompare: Less, depthWrite: true}) : untiled ? PbrUntiledShader.pipeline({cull: cull,
					depthCompare: Less, depthWrite: true}) : PbrShader.pipeline({cull: cull, depthCompare: Less, depthWrite: true}));
			opaquePipelines[k] = p;
		}
		return p;
	}

	final customs = new Map<MaterialShader, Array<Null<{pipeline:Pipeline, slots:Array<Int>}>>>();

	function custom(s:MaterialShader, m:Material, kind:Int):{pipeline:Pipeline, slots:Array<Int>} {
		var list = customs.get(s);
		if (list == null) customs.set(s, list = []);
		// (blended: a plain draw's, or an instanced set's)
		var blend = (kind == 0 || kind == 3) && m.blended;
		var k = kind * 2 + (m.doubleSided ? 1 : 0) + (blend ? 10 * (1 + (cast m.blending : Int)) : 0);
		var c = list[k];
		if (c == null) {
			var v = switch kind {
				case 0: s.plain;
				case 1: s.normalMapped;
				case 2: s.skinned;
				case 3: s.instanced;
				case _: s.instancedNormalMapped;
			}
			var cull:helder.gfx.Cull = m.doubleSided ? None : Back;
			var d = blend ? v.pipeline({cull: cull, depthCompare: Less, depthWrite: false, blend: m.blending}) : v.pipeline({cull: cull, depthCompare: Less, depthWrite: true});
			if (kind == 1 || kind == 4) d.layout = normalSource.layout(kind == 4);
			if (kind == 3) d.layout = INSTANCED_LAYOUT;
			// (each map its own uvs: the second uvs a buffer of their own, last)
			if (s.extensions & Material.UV_SETS != 0) d.layout = s.layers.layout(kind == 0 ? [INSTANCED_LAYOUT[0]] : kind == 2 ? [SKINNED_LAYOUT] : d.layout);
			c = list[k] = {pipeline: create(d), slots: slotsOf(v.uniforms, v.textures).concat([for (b in s.blocks) b.bindings[kind]])};
		}
		return c;
	}

	// the draw list cut into batches: a run of draws of one primitive (one
	// mesh, one material) is one instanced draw, its matrices written to the
	// instance buffer (before the pass: gfx writes buffers between passes)
	function batch() {
		batchCount = 0;
		var bytes = 0, i = 0;
		while (i < count) {
			var j = i + 1;
			// (any scale: the instanced shader turns normals by the matrix's
			// inverse transpose, as the object's normalMatrix)
			// (a lightmapped node a draw of its own: its lightmap its)
			if (instancing && !list[i].primitive.skinned && !list[i].primitive.material.blended && !lightmapped(list[i].node))
				while (j < count && list[j].primitive == list[i].primitive && list[j].group == list[i].group && list[j].lightKey == list[i].lightKey
					&& !lightmapped(list[j].node)
					&& DrawItem.same(list[j].lights, list[i].lights))
					j++;
			if (batchCount == batchStart.length) {
				batchStart.push(0);
				batchSize.push(0);
				batchOffset.push(0);
			}
			batchStart[batchCount] = i;
			batchSize[batchCount] = j - i;
			batchOffset[batchCount] = bytes;
			if (j - i > 1) {
				if (bytes + 64 * (j - i) > instanceBytes.length) {
					var grown = Bytes.alloc(Std.int(Math.max(instanceBytes.length * 2, bytes + 64 * (j - i))));
					grown.blit(0, instanceBytes, 0, bytes);
					instanceBytes = grown;
				}
				for (k in i...j) {
					var m = list[k].node.worldMatrix(), t = list[k].tint;
					for (c in 0...4) {
						var col = MathTools.col(m, c);
						instanceBytes.setFloat(bytes, col.x);
						instanceBytes.setFloat(bytes + 4, col.y);
						instanceBytes.setFloat(bytes + 8, col.z);
						// (the last row's first three, 0 in an affine matrix: the tint less 1)
						instanceBytes.setFloat(bytes + 12, c == 3 ? col.w : (c == 0 ? t.x : c == 1 ? t.y : t.z) - 1);
						bytes += 16;
					}
				}
			}
			batchCount++;
			i = j;
		}
		if (bytes > 0) {
			if (bytes > instanceCapacity) {
				if (instanceCapacity > 0) device.destroyBuffer(instanceBuffer);
				instanceCapacity = instanceBytes.length;
				instanceBuffer = device.createBuffer({size: instanceCapacity, usage: Vertex});
			}
			device.writeBuffer(instanceBuffer, 0, instanceBytes, 0, bytes);
		}
	}

	// a transmitting material's first draw: the target multiplied by its
	// colour where light goes through it (PbrShader: layers.z negative)
	function tint(enc:Encoder, d:DrawItem, p:Mesh.Primitive, m:Material, batch:Int) {
		var k = m.doubleSided ? 1 : 0;
		if (tintPipelines[k] == null) tintPipelines[k] = create(PbrShader.pipeline({cull: m.doubleSided ? None : Back, depthCompare: Less, depthWrite: false, blend: Multiply}));
		var slots = plainSlots;
		bindPipeline(enc, tintPipelines[k], slots);
		var model = d.node.worldMatrix(), t = d.tint;
		writeObject(model, t, batchLights, batch * FrameLights.PER_DRAW);
		enc.setUniforms(slots[1], objectBytes);
		var block = materialInto(m, materialBlock);
		block.layers = new Vec4(block.layers.x, block.layers.y, -m.transmission, block.layers.w);
		PbrShader.params.material.write(block, materialBytes);
		enc.setUniforms(slots[2], materialBytes);
		var ms = m.sampler != null ? m.sampler : sampler;
		enc.setTexture(slots[3], m.baseColorTexture != null ? m.baseColorTexture : white, ms);
		enc.setTexture(slots[7], white, ms);
		enc.setTexture(slots[8], white, ms);
		enc.setTexture(slots[9], white, ms);
		enc.setTexture(slots[4], noShadow, nearest);
		bindClusters(enc, slots);
		if (environment != null) environment.bind(enc, slots[12]) else enc.setTexture(slots[12], white, sampler);
		enc.setTexture(slots[13], white, clamped);
		enc.setVertexBuffer(0, p.vertices);
		enc.setIndexBuffer(p.indices, p.indexFormat);
		enc.drawIndexed(p.count, 1);
		draws++;
	}

	final tintPipelines:Array<Null<Pipeline>> = [null, null];

	// the standard shader blended as the material is, depth tested but not written
	function blended(m:Material):Pipeline {
		var k = (cast m.blending : Int) * 2 + (m.doubleSided ? 1 : 0);
		var p = blendedPipelines[k];
		if (p == null) p = blendedPipelines[k] = create(PbrShader.pipeline({cull: m.doubleSided ? None : Back, depthCompare: Less, depthWrite: false, blend: m.blending}));
		return p;
	}

	// its instanced variant's, for a see-through instanced set (Sprites' halos)
	function blendedInstanced(m:Material):Pipeline {
		var k = (cast m.blending : Int) * 2 + (m.doubleSided ? 1 : 0);
		var p = blendedInstancedPipelines[k];
		if (p == null) {
			var d = PbrInstancedShader.pipeline({cull: m.doubleSided ? None : Back, depthCompare: Less, depthWrite: false, blend: m.blending});
			d.layout = INSTANCED_LAYOUT;
			p = blendedInstancedPipelines[k] = create(d);
		}
		return p;
	}

	final blendedInstancedPipelines:Array<Null<Pipeline>> = [for (_ in 0...10) null];

	// whether a primitive is drawn with its tangents (NormalMaps on, its
	// tangents there, its material's normal map, coat's normal map or
	// anisotropy: Material.tangents; its shader with normal-mapped variants:
	// not shading's unlit ones)
	inline function mapped(p:Mesh.Primitive):Bool
		return normalSource != null && p.tangents != null && !p.skinned && p.material.tangents()
			&& (shaderOf(p.material) == null || shaderOf(p.material).normalMapped != null);

	// a shader's slots for its blocks and textures, in the renderer's order:
	// frame, object (-1: none), material, base colour, shadow atlas, skin,
	// joints, metallic-roughness, emissive, occlusion, normal, the cluster map
	// (ClusteredLights'), the environment map, the screen's ambient
	// occlusion; a physical shader's (0: one, -1: not), its two maps, the
	// frame behind (Transmission's); the frame's lights; then a material's
	// own blocks (OWN on)
	public static function slotsOf(uniforms:Array<helder.gfx.shader.Shader.UniformBlock>, textures:Array<helder.gfx.shader.Shader.TextureBinding>):Array<Int> {
		function u(name:String):Int {
			for (b in uniforms)
				if (b.name == name) return b.binding;
			return -1;
		}
		function t(name:String):Int {
			for (b in textures)
				if (b.name == name) return b.binding;
			return -1;
		}
		return [u("PbrFrame"), u("PbrObject"), u("PbrMaterial"), t("baseColorTexture"), t("shadowMap"), u("PbrSkinInfo"), t("jointMatrices"),
			t("metallicRoughnessTexture"), t("emissiveTexture"), t("occlusionTexture"), t("normalTexture"), t("clusterMap"), t("environmentMap"), t("aoMap"),
			layered(textures), t("layerMap0"), t("layerMap1"), t("transmissionMap"),
			t("lights"), u("PbrProbes"), t("probesMap"), t("ltcMap"), u("PbrLightmap"), t("lightMap")];
	}

	// (a physical shader's variant: one reading a layer's map)
	static function layered(textures:Array<helder.gfx.shader.Shader.TextureBinding>):Int {
		for (b in textures)
			if (b.name == "layerMap0" || b.name == "transmissionMap") return 0;
		return -1;
	}

	// whether a mesh's bounds, through mvp, reach the view: not all eight
	// corners beyond one of the clip space's planes
	static inline function visible(mvp:Mat4, mesh:Mesh):Bool
		return visibleBox(mvp, mesh.bounds);

	static function visibleBox(mvp:Mat4, b:helder.scene.math.Aabb):Bool {
		if (b.isEmpty()) return false;
		var o0 = 0, o1 = 0, o2 = 0, o3 = 0, o4 = 0, o5 = 0;
		for (k in 0...8) {
			var c = mvp * new Vec4((k & 1) == 0 ? b.min.x : b.max.x, (k & 2) == 0 ? b.min.y : b.max.y, (k & 4) == 0 ? b.min.z : b.max.z, 1);
			if (c.x < -c.w) o0++;
			if (c.x > c.w) o1++;
			if (c.y < -c.w) o2++;
			if (c.y > c.w) o3++;
			if (c.z < 0) o4++;
			if (c.z > c.w) o5++;
		}
		return o0 < 8 && o1 < 8 && o2 < 8 && o3 < 8 && o4 < 8 && o5 < 8;
	}

	public function dispose() {
		if (post != null) post.dispose();
		post = null;
		if (clusterSource != null) clusterSource.dispose();
		clusterSource = null;
		if (cullSource != null) cullSource.dispose();
		cullSource = null;
		device.destroyTexture(white);
		device.destroyTexture(noShadow);
		device.destroyTexture(black);
		device.destroyTexture(flatNormal);
		for (t in lightTextures)
			device.destroyTexture(t);
		if (instanceCapacity > 0) device.destroyBuffer(instanceBuffer);
	}
}

// the points of a frame where programs and features draw (Renderer.inject)
enum abstract InjectionPoint(Int) to Int {
	var BeforeOpaque;
	var AfterOpaque;
	var AfterPass;
	var AfterTransparent;
	// before the frame's passes (its shadows, its prepass, its main pass):
	// passes and dispatches of one's own the frame then reads (a prefilter,
	// a capture)
	var BeforePass;
}

// the frame being drawn, for the hooks
class FrameInfo {
	public var world:Null<World>;
	public var camera:Null<Camera>;
	public var aspect = 1.0;
	// the target's size in pixels (drawInto's, else the device's)
	public var width = 1;
	public var height = 1;
	// the camera's view (the scene's space to the camera's) and projection
	public var view:Mat4 = Mat4.identity();
	public var projection:Mat4 = Mat4.identity();
	public var viewProj:Mat4 = Mat4.identity();
	// the view-projection without the frame's jitter (Renderer.jitter), and
	// the frame before's (its first frame, or a world's first: this one's):
	// what moved on the screen since (post's motion: TAA, motion blur)
	public var stillViewProj:Mat4 = Mat4.identity();
	public var previousViewProj:Mat4 = Mat4.identity();
	// the jitter in clip space (x, y: Renderer.jitter's)
	public var jitter:helder.gfx.shader.Vec2 = new helder.gfx.shader.Vec2(0, 0);
	// the renderer's frames drawn before this one
	public var index = 0;
	public var eye:Vec3 = new Vec3(0, 0, 0);
	// towards the light (the world's sun or the renderer's)
	public var toLight:Vec3 = new Vec3(0, 1, 0);
	// whether the target is the renderer's HDR one (linear light, RGBA16F:
	// output)
	public var hdr = false;
	// the renderer's fog (null: none) and exposure, for what a program
	// draws itself (Fog.colorOf, shapeOf; PbrShader.fogAmount)
	public var fog:Null<Fog> = null;
	public var exposure = 1.0;

	public function new() {}
}

// an entry of the draw list
class DrawItem {
	public var node:Node = Node.NONE;
	public var primitive:Null<Mesh.Primitive>;
	public var key = 0;
	// (see-through draws: the depth they sort by, farthest first)
	public var depth = 0.0;
	// (its node's tint: MeshRenderer.tint)
	public var tint:Vec3 = Renderer.WHITE;
	// (its node's selection group: the view buffers', 0 without; runs of
	// one primitive are split by it)
	public var group = 0;
	// (its lights: FrameLights.PER_DRAW rows of the frame's, by row, -1
	// after the last; a key of them: runs of one primitive split by them)
	public final lights:Array<Float> = Filled.floats(FrameLights.PER_DRAW, -1.0);
	public var lightKey = 0;

	public function new() {}

	// (a list's key: its rows mixed, the same for the same rows)
	public static function keyOf(l:Array<Float>):Int {
		var h = 17;
		for (i in 0...FrameLights.PER_DRAW)
			h = (h * 31 + Std.int(l[i]) + 1) & 0x3FFFFFFF;
		return h;
	}

	public static function same(a:Array<Float>, b:Array<Float>):Bool {
		for (i in 0...FrameLights.PER_DRAW)
			if (a[i] != b[i]) return false;
		return true;
	}
}


