package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Vec4;
import helder.scene.math.MathTools;
import helder.scene.render.EnvironmentShader;

// An environment, opted in (renderer.use(new Environment(device,
// texture))): an equirectangular image (longitude across, latitude down;
// sRGB, mip-mapped) drawn behind the scene (at the renderer's BeforeOpaque
// point, as the sky) and lighting it: the standard material's ambient
// from it, diffuse from a small mip level along the normal, specular
// along the reflection from a level by roughness (mip levels standing in
// for a filtered map: a cheap image-based light). A program without one
// keeps the sky-and-ground ambient and links none of this.
//   var env = Environment.fromImage(device, "image/png", helder.asset.Asset.embed("sky.png")); // with Images.decode set (Images.png)
//
// Prefiltered (Environment.prefiltered): the light filtered once ahead,
// image-based lighting proper. An atlas of levels + 1 rows, each the whole
// sphere (equirectangular, width by width / 2): row k the specular light
// for a roughness of k / (levels - 1) (the environment convolved with
// GGX's lobe, the split sum's first half), the last the diffuse
// irradiance (cosine weighted, over pi); the material reads two rows by
// its roughness, blended, and the last along its normal. Small (128 x 448
// for 6 levels: 224 KB on the GPU), made by a tool once (Expansion's
// tools/envbake.py), no mips; the decoded pixels freed after the upload.
//   var env = Environment.prefiltered(device, "image/png", bytes, 6);
//
// Prefiltered by helder (Environment.prefilter): an equirectangular image
// (RGBA8 sRGB, or linear RGBA16F or RGBA32F: HDR) filtered at load into an
// octahedral atlas (Prefilter: a compute dispatch where the device has
// compute, else a fragment pass; done at the first frame's BeforePass
// point), levels rows of roughness and the irradiance's, made from its
// spherical harmonics (sh: projected from the image here, the diffuse
// light ReflectionProbes and ProbeGrid fall back to); the image itself
// drawn behind the scene.
//   var env = Environment.prefilter(device, image.width, image.height, image.rgba); // or prefilterImage(device, mime, bytes)
class Environment implements RenderFeature {
	public final device:Device;
	public final texture:Texture;
	// the mip levels below the first (the map's width 2^levels)
	public final levels:Int;
	// how bright the environment is, as light (1: its colours)
	public var intensity = 1.0;
	// whether it is drawn behind the scene (false: it only lights it)
	public var background = true;
	// a prefiltered atlas's levels of roughness (0: a mip-mapped image)
	public final rows:Int;
	// (half a texel of an atlas's row, in its rows' v)
	final edge:Float;
	// the diffuse light as spherical harmonics (prefilter's; else null)
	public var sh(default, null):Null<Sh> = null;
	// (prefilter's) its octahedral atlas (one column), the work, whether its
	// image is linear (HDR) or sRGB-encoded
	@:noCompletion public var atlas(default, null):Null<Texture> = null;
	var prefilterer:Null<Prefilter> = null;
	@:noCompletion public var linear(default, null) = false;

	final quad:Buffer;
	final sampler:Sampler;
	// (an atlas's: one level)
	final flat:Sampler;
	final bytes = Bytes.alloc(EnvironmentShader.uniforms[0].size);
	// (the block as written, kept: nothing allocated per frame)
	final block:EnvironmentParams = {invViewProj: helder.gfx.shader.Mat4.identity(), eye: new Vec4(0, 0, 0, 0), params: new Vec4(0, 0, 0, 0), fog: new Vec4(0, 0, 0, 0), fogShape: new Vec4(0, 0, 0, 0)};

	// texture: mip-mapped (Images.mipmapped's), width twice its height; or
	// a prefiltered atlas of rows levels (prefiltered), width its width
	public function new(device:Device, texture:Texture, width:Int, rows = 0) {
		this.device = device;
		this.texture = texture;
		this.rows = rows;
		edge = 1 / width;
		var l = 0;
		while ((1 << (l + 1)) <= width)
			l++;
		levels = l;
		var v = EnvironmentShader.vertexBytes([
			{pos: new helder.gfx.shader.Vec2(-1, -1)}, {pos: new helder.gfx.shader.Vec2(1, -1)}, {pos: new helder.gfx.shader.Vec2(-1, 1)},
			{pos: new helder.gfx.shader.Vec2(-1, 1)}, {pos: new helder.gfx.shader.Vec2(1, -1)}, {pos: new helder.gfx.shader.Vec2(1, 1)}
		]);
		quad = device.createBuffer({size: v.length, usage: Vertex, data: v});
		sampler = device.createSampler({filter: Linear, mipFilter: Linear, wrap: Repeat});
		flat = device.createSampler({filter: Linear, wrap: Repeat});
	}

	// an encoded image's environment (Images.decode must read it); null when it cannot
	public static function fromImage(device:Device, mime:String, bytes:Bytes):Null<Environment> {
		if (Images.decode == null) return null;
		var image = Images.decode(mime, bytes);
		if (image == null) return null;
		return new Environment(device, Images.mipmapped(device, image.width, image.height, image.rgba), image.width);
	}

	// a prefiltered atlas's environment (levels rows of roughness and the
	// irradiance's, each width by width / 2; Images.decode must read it); null when it cannot
	public static function prefiltered(device:Device, mime:String, bytes:Bytes, levels:Int):Null<Environment> {
		if (Images.decode == null) return null;
		var image = Images.decode(mime, bytes);
		if (image == null) return null;
		if (image.height != (levels + 1) * (image.width >> 1)) throw "helder.scene: Environment.prefiltered: an atlas of " + (levels + 1) + " rows of " + image.width + " x " + (image.width >> 1) + " expected, not " + image.width + " x " + image.height;
		var t = device.createTexture({width: image.width, height: image.height, data: image.rgba});
		return new Environment(device, t, image.width, levels);
	}

	// an equirectangular image's environment prefiltered by helder (width x
	// height texels, its rows top to bottom; RGBA8: sRGB-encoded, as an
	// image's; RGBA16F or RGBA32F: linear light, HDR): an octahedral atlas of
	// size-texel cells, levels rows of roughness (Prefilter; samples a texel),
	// filled at the first frame drawn with it, and its harmonics (sh)
	public static function prefilter(device:Device, width:Int, height:Int, texels:Bytes, format:TextureFormat = RGBA8, ?options:{?size:Int, ?levels:Int,
			?samples:Int}):Environment {
		if (format != RGBA8 && format != RGBA16F && format != RGBA32F) throw "helder.scene: Environment.prefilter: RGBA8, RGBA16F or RGBA32F texels";
		var sh = Sh.ofEquirect(width, height, texels, format);
		var t:Texture;
		if (format == RGBA8) t = Images.mipmapped(device, width, height, texels) else {
			// (RGBA32F: halved to RGBA16F, filterable, its mips made by the GPU)
			var data = format == RGBA16F ? texels : halves(texels, width * height * 4);
			t = device.createTexture({width: width, height: height, format: RGBA16F, mipLevels: 0, data: data});
			device.generateMips(t);
		}
		var e = new Environment(device, t, width);
		e.sh = sh;
		e.linear = format != RGBA8;
		var p = new Prefilter(device, options == null || options.size == null ? 64 : options.size, options == null || options.levels == null ? 6 : options.levels,
			options == null || options.samples == null ? 64 : options.samples);
		e.prefilterer = p;
		e.atlas = p.atlas(1);
		return e;
	}

	// an encoded image's environment prefiltered by helder (prefilter; Images.decode must read it); null when it cannot
	public static function prefilterImage(device:Device, mime:String, bytes:Bytes, ?options:{?size:Int, ?levels:Int, ?samples:Int}):Null<Environment> {
		if (Images.decode == null) return null;
		var image = Images.decode(mime, bytes);
		if (image == null) return null;
		return prefilter(device, image.width, image.height, image.rgba, RGBA8, options);
	}

	// (n floats as IEEE 754 binary16s)
	static function halves(floats:Bytes, n:Int):Bytes {
		var out = Bytes.alloc(n * 2);
		for (k in 0...n)
			out.setUInt16(2 * k, half(floats.getFloat(4 * k)));
		return out;
	}

	// a float as an IEEE 754 binary16 (rounded; past its range, its largest)
	@:noCompletion public static function half(f:Float):Int {
		if (Math.isNaN(f)) return 0x7E00;
		var s = f < 0 ? 0x8000 : 0;
		var a = Math.abs(f);
		if (a >= 65504) return s | 0x7BFF;
		if (a < 6.103515625e-5) return s | Math.round(a / 5.960464477539063e-8);
		var e = Math.floor(Math.log(a) / Math.log(2));
		var m = Math.round((a / Math.pow(2, e) - 1) * 1024);
		if (m == 1024) {
			m = 0;
			e++;
		}
		return s | ((e + 15) << 10) | m;
	}

	// the cells' texels across, the rows of roughness (prefilter's; 0: none)
	@:noCompletion public var cellSize(get, never):Int;
	@:noCompletion public var cellLevels(get, never):Int;

	inline function get_cellSize()
		return prefilterer == null ? 0 : prefilterer.size;

	inline function get_cellLevels()
		return prefilterer == null ? 0 : prefilterer.levels;

	var filled = false;

	// (each renderer its pipeline: Probes' twin draws it too)
	public function attach(renderer:Renderer) {
		var pipeline = renderer.createPipeline(EnvironmentShader.pipeline());
		@:privateAccess renderer.environment = this;
		renderer.inject(BeforeOpaque, (enc, frame) -> if (background) draw(enc, frame, renderer, pipeline));
		// (prefilter's atlas filled at the first frame)
		if (atlas != null) renderer.inject(BeforePass, (enc, frame) -> fill(enc));
	}

	// (prefilter's atlas filled, once)
	@:noCompletion public function fill(enc:Encoder) {
		if (filled || atlas == null) return;
		filled = true;
		prefilterer.run(enc, atlas, 1, 0, texture, false, Math.round(1 / edge), levels + 1, !linear, sh, 1);
	}

	// (the standard material's binding: the octahedral atlas, a prefiltered
	// atlas, or the mip-mapped image)
	@:allow(helder.scene.render.Renderer) function bind(enc:Encoder, slot:Int)
		atlas != null ? enc.setTexture(slot, atlas, flat) : enc.setTexture(slot, texture, rows > 0 ? flat : sampler);

	// (PbrFrame's environment: x the intensity; an octahedral atlas' y -1 (its
	// columns, negated), z its rows of roughness, w a cell's texels; else y the
	// image's mip levels, z a prefiltered atlas' rows, w half its texel)
	@:allow(helder.scene.render) function frameVector():Vec4
		return atlas != null ? new Vec4(intensity, -1, cellLevels, cellSize) : new Vec4(intensity, levels, rows, edge);

	function draw(enc:Encoder, frame:Renderer.FrameInfo, renderer:Renderer, pipeline:Pipeline) {
		var e = frame.eye;
		var b = block;
		b.invViewProj = MathTools.inverse(frame.viewProj);
		b.eye = new Vec4(e.x, e.y, e.z, 1);
		// (z -1: a linear image, not decoded)
		b.params = new Vec4(intensity * renderer.exposure, frame.hdr ? 1 : 0, linear ? -1 : rows, edge);
		b.fog = Fog.colorOf(frame.fog) * renderer.exposure;
		b.fogShape = Fog.shapeOf(frame.fog);
		EnvironmentShader.params.env.write(b, bytes);
		enc.setPipeline(pipeline);
		enc.setUniforms(0, bytes);
		enc.setTexture(EnvironmentShader.textures[0].binding, texture, rows > 0 ? flat : sampler);
		enc.setVertexBuffer(0, quad);
		enc.draw(6);
	}

	public function dispose() {
		device.destroyTexture(texture);
		if (atlas != null) device.destroyTexture(atlas);
		if (prefilterer != null) prefilterer.dispose();
		device.destroyBuffer(quad);
	}
}
