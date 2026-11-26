package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.math.Mat4;
import helder.math.Vec3;
import helder.math.Vec4;
import helder.scene.*;
import helder.math.Quat;
import helder.scene.render.PbrProbesShader;
import helder.scene.render.PbrShader;

// Light probes and reflection probes, opted in (renderer.use(new
// Probes(device))): the world's LightProbes, ProbeGrids and
// ReflectionProbes light the standard material's draws (pbr's probes
// variants: PbrProbesShader).
//
//   - Each draw's diffuse light is its centre's (the run's centre for an
//     instanced run): a ProbeGrid holding it (trilinear), else its nearest
//     LightProbes, blended; evaluated at its vertices (spherical harmonics:
//     nothing per pixel). Without, the environment's or the sky's.
//   - Its reflections are its two reflection probes' (the two whose boxes
//     hold most of its bounds), box-projected per pixel, A blended over B
//     or the environment.
//
// The atlas: one RGBA16F texture (Prefilter's: a prefiltered atlas' rows by
// roughness, a column a probe), the probes variants' own texture
// (probesMap); the environment stays its own, read as before by every
// material (the probes' fallback). A probe is captured when first drawn and after
// capture(): the world drawn six times from its centre into a cube (an
// offscreen renderer of the renderer's light, sky and environment: a twin,
// its faces mirrored as a cube's are), then prefiltered into its column; at
// the frame's BeforePass point, a probe or two a frame (captures).
//
// Not lit by probes (they read the environment alone): the
// normal-mapped, skinned and see-through draws, instanced sets
// (InstancedMesh, Sprites) and materials of their own shader (Physical's
// among them).
class Probes implements RenderFeature implements RenderFeature.ProbeSource {
	public final device:Device;
	// a cell's texels across (its height half), the rows of roughness, the
	// probes at most (the atlas' columns), a capture's face's texels
	public final size:Int;
	public final levels:Int;
	public final max:Int;
	public final captureSize:Int;
	// captures done a frame at most
	public var capturesPerFrame = 2;
	// captures done so far
	public var captures(default, null) = 0;
	// the atlas (Prefilter's: a column of rows a probe)
	public final atlas:Texture;

	final prefilter:Prefilter;
	final cube:Texture;
	final depth:Texture;
	final cubeLevels:Int;
	var renderer:Null<Renderer> = null;
	var twin:Null<Renderer> = null;
	final atlasSampler:Sampler;
	final block:PbrProbes;
	final bytes = Bytes.alloc(PbrProbesShader.params.probes.block.size);
	final sh = new Sh();
	final pipelines:Array<Null<Pipeline>> = [null, null, null, null];
	final plainSlots:Array<Int>;
	final instancedSlots:Array<Int>;
	var world:Null<World> = null;

	public function new(device:Device, ?options:{?size:Int, ?levels:Int, ?max:Int, ?captureSize:Int, ?samples:Int}) {
		this.device = device;
		size = options != null && options.size != null ? options.size : 64;
		levels = options != null && options.levels != null ? options.levels : 6;
		max = options != null && options.max != null ? options.max : 8;
		captureSize = options != null && options.captureSize != null ? options.captureSize : 128;
		prefilter = new Prefilter(device, size, levels, options != null && options.samples != null ? options.samples : 64);
		atlas = prefilter.atlas(max);
		atlasSampler = device.createSampler({filter: Linear, wrap: Clamp});
		cube = device.createTexture({width: captureSize, height: captureSize, cube: true, format: RGBA16F, renderTarget: true, mipLevels: 0});
		depth = device.createTexture({width: captureSize, height: captureSize, format: Depth32F});
		var l = 0;
		while ((captureSize >> l) > 0)
			l++;
		cubeLevels = l;
		var z = new Vec4(0, 0, 0, 0);
		// (the atlas' shape: its columns, rows of roughness, half a texel across and down a cell)
		block = {sh: [for (_ in 0...7) z], probeA: z, extentA: z, probeB: z, extentB: z, atlas: new Vec4(max, levels, 0.5 / size, 1 / size)};
		plainSlots = Renderer.slotsOf(PbrProbesShader.uniforms, PbrProbesShader.textures);
		instancedSlots = Renderer.slotsOf(PbrInstancedProbesShader.uniforms, PbrInstancedProbesShader.textures);
	}

	public function attach(renderer:Renderer) {
		this.renderer = renderer;
		@:privateAccess renderer.probeSource = this;
		renderer.inject(BeforePass, (enc, frame) -> prepare(enc, renderer, frame));
	}

	// (BeforePass) the stale probes captured
	function prepare(enc:Encoder, renderer:Renderer, frame:Renderer.FrameInfo) {
		world = frame.world;
		var store = world.store(ReflectionProbe.KIND), done = 0;
		for (k in 0...store.length) {
			var p = store.valueAt(k);
			var column = k < max ? k + 1 : 0;
			if (p.column != column) {
				p.column = column;
				p.stale = true;
			}
			if (p.stale && column > 0 && done < capturesPerFrame) {
				capture(enc, renderer, world, p);
				p.stale = false;
				done++;
			}
		}
	}

	// the faces of a cube: each its forward and up (+x, -x, +y, -y, +z, -z;
	// a face's right the other way round from a camera's: mirrored)
	static final FORWARD = [new Vec3(1, 0, 0), new Vec3(-1, 0, 0), new Vec3(0, 1, 0), new Vec3(0, -1, 0), new Vec3(0, 0, 1), new Vec3(0, 0, -1)];
	static final UP = [new Vec3(0, 1, 0), new Vec3(0, 1, 0), new Vec3(0, 0, -1), new Vec3(0, 0, 1), new Vec3(0, 1, 0), new Vec3(0, 1, 0)];

	function capture(enc:Encoder, renderer:Renderer, world:World, probe:ReflectionProbe) {
		if (twin == null) twin = @:privateAccess renderer.twin();
		@:privateAccess renderer.copyInto(twin);
		var eye = world.node();
		var camera = Camera.attach(eye, Camera.perspective(Math.PI / 2, 0.05, 500));
		eye.position = probe.node.worldPosition();
		// (the camera's x the face's right mirrored: scale -1, its winding turned by the twin's culling)
		eye.scale = new Vec3(-1, 1, 1);
		for (f in 0...6) {
			var fw = FORWARD[f], up = UP[f];
			var x = new Vec3(fw.y * up.z - fw.z * up.y, fw.z * up.x - fw.x * up.z, fw.x * up.y - fw.y * up.x);
			eye.rotation = Quat.fromMat4(new Mat4(new Vec4(x.x, x.y, x.z, 0), new Vec4(up.x, up.y, up.z, 0), new Vec4(-fw.x, -fw.y, -fw.z, 0), new Vec4(0, 0, 0, 1)));
			twin.drawInto(enc, world, camera, cube, depth, captureSize, captureSize, null, f);
		}
		eye.dispose();
		device.generateMips(cube);
		prefilter.run(enc, atlas, max, probe.column - 1, cube, true, captureSize, cubeLevels, false, null, probe.intensity);
		captures++;
	}

	// ---- ProbeSource

	@:noCompletion public function pipeline(instanced:Bool, doubleSided:Bool):Pipeline {
		var k = (instanced ? 2 : 0) + (doubleSided ? 1 : 0);
		var p = pipelines[k];
		if (p == null) {
			var cull:Cull = doubleSided ? None : Back;
			if (instanced) {
				var d = PbrInstancedProbesShader.pipeline({cull: cull, depthCompare: Less, depthWrite: true});
				d.layout = @:privateAccess Renderer.INSTANCED_LAYOUT;
				p = renderer.createPipeline(d);
			} else
				p = renderer.createPipeline(PbrProbesShader.pipeline({cull: cull, depthCompare: Less, depthWrite: true}));
			pipelines[k] = p;
		}
		return p;
	}

	@:noCompletion public function slots(instanced:Bool):Array<Int>
		return instanced ? instancedSlots : plainSlots;

	// a draw's probes (its bounds': its centre, its half size) into its block,
	// set with the atlas at a variant's slots (Renderer.slotsOf's 19 and 20)
	@:noCompletion public function bind(enc:Encoder, slots:Array<Int>, cx:Float, cy:Float, cz:Float, ex:Float, ey:Float, ez:Float) {
		var b = block;
		var has = world != null && lightAt(world, new Vec3(cx, cy, cz), sh);
		if (has) sh.pack(b.sh) else for (k in 0...7)
			b.sh[k] = new Vec4(0, 0, 0, 0);
		// (the two reflection probes it is deepest in)
		var a:Null<ReflectionProbe> = null, c:Null<ReflectionProbe> = null, wa = 0.0, wc = 0.0;
		if (world != null) {
			var store = world.store(ReflectionProbe.KIND);
			for (k in 0...store.length) {
				var p = store.valueAt(k);
				if (p.column == 0 || p.stale) continue;
				var w = p.weight(cx, cy, cz, ex, ey, ez);
				if (w <= 0) continue;
				if (w > wa) {
					c = a;
					wc = wa;
					a = p;
					wa = w;
				} else if (w > wc) {
					c = p;
					wc = w;
				}
			}
		}
		b.probeA = a == null ? new Vec4(0, 0, 0, 0) : vec(a.node.worldPosition(), a.column);
		b.extentA = a == null ? new Vec4(0, 0, 0, 0) : vec(a.size * 0.5, wa);
		b.probeB = c == null ? new Vec4(0, 0, 0, 0) : vec(c.node.worldPosition(), c.column);
		b.extentB = c == null ? new Vec4(0, 0, 0, has ? 1 : 0) : vec(c.size * 0.5, has ? 1 : 0);
		PbrProbesShader.params.probes.write(b, bytes);
		enc.setUniforms(slots[19], bytes);
		enc.setTexture(slots[20], atlas, atlasSampler);
	}

	static inline function vec(v:Vec3, w:Float):Vec4
		return new Vec4(v.x, v.y, v.z, w);

	// the light probes' light at a point (a grid's holding it, else the
	// nearest two probes' that reach it, blended by their distances), into
	// out; false: none
	public static function lightAt(world:World, p:Vec3, out:Sh):Bool {
		var grids = world.store(ProbeGrid.KIND);
		for (k in 0...grids.length) {
			var g = grids.valueAt(k), c = g.node.worldPosition();
			var q = new Vec3(p.x - c.x, p.y - c.y, p.z - c.z);
			if (g.holds(q)) {
				g.sample(q, out);
				return true;
			}
		}
		var probes = world.store(LightProbe.KIND);
		var a:Null<LightProbe> = null, b:Null<LightProbe> = null, da = Math.POSITIVE_INFINITY, db = Math.POSITIVE_INFINITY;
		for (k in 0...probes.length) {
			var l = probes.valueAt(k), c = l.node.worldPosition();
			var d = Math.sqrt((p.x - c.x) * (p.x - c.x) + (p.y - c.y) * (p.y - c.y) + (p.z - c.z) * (p.z - c.z));
			if (d > l.radius) continue;
			if (d < da) {
				b = a;
				db = da;
				a = l;
				da = d;
			} else if (d < db) {
				b = l;
				db = d;
			}
		}
		if (a == null) return false;
		out.clear().addScaled(a.sh, a.intensity * (b == null ? 1 : db / (da + db)));
		if (b != null) out.addScaled(b.sh, b.intensity * da / (da + db));
		return true;
	}

	public function dispose() {
		device.destroyTexture(atlas);
		device.destroyTexture(cube);
		device.destroyTexture(depth);
		prefilter.dispose();
		if (twin != null) twin.dispose();
	}
}
