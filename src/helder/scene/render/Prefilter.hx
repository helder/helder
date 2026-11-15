package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Vec2;
import helder.gfx.shader.Vec4;
import helder.scene.render.PrefilterShader;

// The environment prefilter in helder (PrefilterShader): fills a column of an
// octahedral atlas (atlas: RGBA16F, columns of cells of size x size texels,
// levels + 1 rows of them: the light along a reflection by roughness, then
// the irradiance) from an equirectangular image or a cube, once, at load.
// Where the device has compute (Device.has(Compute)) a dispatch a column
// writes the atlas (a storage texture), else a fragment pass draws into it
// (a render target); the same texels either way. An Environment's
// (Environment.prefilter: one column) and ReflectionProbes' (a column a
// probe, the environment's the first). Recorded in a frame
// (Renderer's BeforePass point), nothing allocated per column.
class Prefilter {
	public final device:Device;
	// whether it dispatches (Device.has(Compute)) or draws
	public final compute:Bool;
	// a cell's texels across, the rows of roughness, the samples a texel
	public final size:Int;
	public final levels:Int;
	public final samples:Int;

	var pass:Null<Pipeline> = null;
	var dispatch:Null<ComputePipeline> = null;
	final quad:Buffer;
	final bytes = Bytes.alloc(PrefilterPass.uniforms[0].size);
	final block:PrefilterParams;
	final sampler:Sampler;
	// (the source not read: a 1x1 texel of each kind)
	final noImage:Texture;
	final noCube:Texture;
	final into:PassDesc = {colors: [{load: Load}]};

	public function new(device:Device, size = 128, levels = 6, samples = 64) {
		if (size < 8 || levels < 1) throw "helder.scene: Prefilter: cells of 8 texels or more, a level or more";
		this.device = device;
		this.size = size;
		this.levels = levels;
		this.samples = samples;
		compute = device.has(Compute) && device.has(StorageTextures);
		var z = new Vec4(0, 0, 0, 0);
		block = {cell: z, source: z, options: z, sh: [for (_ in 0...7) z]};
		var v = PrefilterPass.vertexBytes([{pos: new Vec2(-1, -1)}, {pos: new Vec2(1, -1)}, {pos: new Vec2(-1, 1)}, {pos: new Vec2(-1, 1)}, {pos: new Vec2(1, -1)}, {pos: new Vec2(1, 1)}]);
		quad = device.createBuffer({size: v.length, usage: Vertex, data: v});
		sampler = device.createSampler({filter: Linear, mipFilter: Linear, wrap: Clamp});
		var w = Bytes.alloc(4);
		noImage = device.createTexture({width: 1, height: 1, data: w});
		noCube = device.createTexture({width: 1, height: 1, cube: true, data: Bytes.alloc(24)});
	}

	// an atlas of columns cells across (RGBA16F; a storage texture where it
	// dispatches, else a render target)
	public function atlas(columns:Int):Texture
		return compute ? device.createTexture({width: columns * size, height: (levels + 1) * size, format: RGBA16F, storage: true}) : device.createTexture({
			width: columns * size,
			height: (levels + 1) * size,
			format: RGBA16F,
			renderTarget: true
		});

	// the atlas' column filled from an equirectangular image (mip-mapped;
	// srgb: its colours encoded, an image's RGBA8) or a cube (a capture,
	// mip-mapped, linear); sh: the irradiance row's harmonics (else sampled);
	// width: the source's (a cube's face's); intensity: its light's scale;
	// columns: the atlas'
	public function run(enc:Encoder, atlas:Texture, columns:Int, column:Int, source:Texture, cube:Bool, width:Int, mipLevels:Int, srgb:Bool, ?sh:Sh,
			intensity = 1.0) {
		var b = block;
		b.cell = new Vec4(column * size, size, levels, samples);
		b.source = new Vec4(cube ? 1 : 0, mipLevels - 1, cube ? 6.0 * width * width : width * (width >> 1), intensity);
		b.options = new Vec4(sh != null ? 1 : 0, srgb ? 1 : 0, -1 + 2.0 * column / columns, 2.0 / columns);
		if (sh != null) sh.pack(b.sh);
		PrefilterPass.params.prefilter.write(b, bytes);
		var image = cube ? noImage : source, faces = cube ? source : noCube;
		if (compute) {
			if (dispatch == null) dispatch = device.createComputePipeline(PrefilterDispatch.pipeline());
			enc.beginCompute();
			enc.setComputePipeline(dispatch);
			enc.setUniforms(PrefilterDispatch.params.prefilter.block.binding, bytes);
			enc.setTexture(PrefilterDispatch.params.equirectMap.binding, image, sampler);
			enc.setTexture(PrefilterDispatch.params.cubeMap.binding, faces, sampler);
			enc.setStorageTexture(PrefilterDispatch.params.atlas.binding, atlas);
			enc.dispatch((size + 7) >> 3, ((levels + 1) * size + 7) >> 3);
			enc.endCompute();
			return;
		}
		if (pass == null) {
			var d = PrefilterPass.pipeline();
			d.colorFormat = RGBA16F;
			pass = device.createPipeline(d);
		}
		// (the column's quad: options' share of the atlas' width)
		into.colors[0].texture = atlas;
		enc.beginPass(into);
		enc.setPipeline(pass);
		enc.setUniforms(PrefilterPass.params.prefilter.block.binding, bytes);
		enc.setTexture(PrefilterPass.params.equirectMap.binding, image, sampler);
		enc.setTexture(PrefilterPass.params.cubeMap.binding, faces, sampler);
		enc.setVertexBuffer(0, quad);
		enc.draw(6);
		enc.endPass();
		into.colors[0].texture = null;
	}

	public function dispose() {
		device.destroyBuffer(quad);
		device.destroyTexture(noImage);
		device.destroyTexture(noCube);
	}
}
