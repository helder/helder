package helder.scene.render;

import helder.math.*;
import helder.gfx.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.PostShader;

// The opaque frame behind see-through surfaces
// (KHR_materials_transmission and _volume), what a physical shader's
// transmitting surface (PhysicalShader, Material.transmission) shows
// through it, refracted by its ior and thickness and blurred by its
// roughness (a mip level a roughness): once a frame that draws one, after
// the opaque surfaces and the AfterOpaque hooks (the sky), the frame's pass
// is ended, its colour copied into a mip-mapped texture of the target's
// format, and the pass begun again where it was (its colour and depth
// kept), the see-through surfaces drawn after:
//
//   renderer.use(new Transmission(renderer.device));
//
// An offscreen renderer's (a <Scene>'s box, drawInto: the frame's colour
// is a texture there); a renderer of the device's frame, or a frame with no
// transmitting surface in view, copies nothing. Without it a transmitting
// surface shows the environment refracted through it instead. Its cost: a
// copy of the frame and its mips (a third more) in the target's format,
// a pass split in two on the frames that need it (Renderer.split counts them).
class Transmission implements RenderFeature implements RenderFeature.TransmissionSource {
	public final device:Device;
	var pipeline:Null<Pipeline> = null;
	var format:Null<TextureFormat> = null;
	final triangle:Buffer;
	final linear:Sampler;
	var texture:Null<Texture> = null;
	var width = 0;
	var height = 0;
	var mipLevels = 0;

	public function new(device:Device) {
		this.device = device;
		var v = TransmissionCopyShader.vertexBytes([{pos: new Vec2(-1, -1)}, {pos: new Vec2(3, -1)}, {pos: new Vec2(-1, 3)}]);
		triangle = device.createBuffer({size: v.length, usage: Vertex, data: v});
		linear = device.createSampler({filter: Linear, wrap: Clamp});
	}

	public function attach(renderer:Renderer)
		@:privateAccess renderer.transmissionSource = this;

	// the frame's pass (pass, into textures of width x height texels of
	// format) ended, its colour so far copied (resolved) and its mips made,
	// the pass begun again where it was; returns the copy
	public function capture(enc:Encoder, pass:PassDesc, width:Int, height:Int, format:TextureFormat):Texture {
		enc.endPass();
		var c = pass.colors[0];
		var source = c.resolve != null ? c.resolve : c.texture;
		if (texture == null || this.width != width || this.height != height || this.format != format) {
			if (texture != null) device.destroyTexture(texture);
			texture = device.createTexture({width: width, height: height, format: format, renderTarget: true, mipLevels: 0});
			this.width = width;
			this.height = height;
			var n = 1, s = width > height ? width : height;
			while (s > 1) {
				s >>= 1;
				n++;
			}
			mipLevels = n;
			if (this.format != format || pipeline == null) {
				var d = TransmissionCopyShader.pipeline({});
				d.colorFormat = format;
				pipeline = device.createPipeline(d);
			}
			this.format = format;
		}
		copy.colors[0].texture = texture;
		enc.beginPass(copy);
		enc.setPipeline(pipeline);
		enc.setTexture(TransmissionCopyShader.textures[0].binding, source, linear);
		enc.setVertexBuffer(0, triangle);
		enc.draw(3);
		enc.endPass();
		copy.colors[0].texture = null;
		device.generateMips(texture);
		resume.colors[0].texture = c.texture;
		resume.colors[0].resolve = c.resolve;
		resume.depth.texture = pass.depth.texture;
		enc.beginPass(resume);
		resume.colors[0].texture = null;
		resume.colors[0].resolve = null;
		resume.depth.texture = null;
		return texture;
	}

	final resume:PassDesc = {colors: [{load: Load}], depth: {load: Load}};

	// the copy's mip levels below its first (the roughest's)
	public function levels():Float
		return mipLevels - 1;

	final copy:PassDesc = {colors: [{load: DontCare}]};

	public function dispose() {
		if (texture != null) device.destroyTexture(texture);
		texture = null;
		device.destroyBuffer(triangle);
	}
}

// the frame's texel as it is (Transmission's copy)
final TransmissionCopyShader = shader({
	vertex: function(v:PostVertex):PostVaryings
		return fullscreen(v),
	fragment: function(i:PostVaryings, params:{source:Texture2D}):Vec4
		return vec4(sampleLevel(params.source, i.uv, 0).xyz, 1)
});
