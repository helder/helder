package helder.scene.render;

import helder.gfx.*;
import helder.gfx.shader.Shader.PipelineOptions;
import helder.scene.render.PbrAreaShader;

// Area lights shaded with linearly transformed cosines (Heitz, Dupuy, Hill
// and Neubelt, "Real-Time Polygonal-Light Shading with Linearly Transformed
// Cosines"), opted in (renderer.use(new AreaLights(device))): in a frame
// with rect or disc lights (Light.rectArea, discArea), the standard
// material's opaque draws are drawn with pbr's area variants
// (PbrAreaShader), which integrate each area light's polygon (a disc as an
// octagon of its area) against the cosine and against GGX's lobe through
// the fitted tables (ltcMap: two 64 x 64 tables, three.js's, in RGBA16F
// one above the other: 64 KB, an embedded asset). The other materials, and
// a frame without the feature, light an area light as a point light at its
// centre. No shadows. A frame without area lights draws as before: its
// variants are compiled only when one is drawn.
class AreaLights implements RenderFeature implements RenderFeature.AreaSource {
	public final device:Device;
	// the tables (RGBA16F, 64 x 128)
	public final ltc:Texture;

	final sampler:Sampler;
	var renderer:Null<Renderer> = null;
	final pipelines:Array<Null<Pipeline>> = [for (_ in 0...8) null];
	final slotsOf:Array<Array<Int>>;

	public function new(device:Device) {
		this.device = device;
		ltc = device.createTexture({width: 64, height: 128, format: RGBA16F, data: helder.asset.Embed.bytes("helder/scene/render/ltc.bin")});
		sampler = device.createSampler({filter: Linear, wrap: Clamp});
		slotsOf = [
			Renderer.slotsOf(PbrAreaShader.uniforms, PbrAreaShader.textures),
			Renderer.slotsOf(PbrInstancedAreaShader.uniforms, PbrInstancedAreaShader.textures),
			Renderer.slotsOf(PbrAreaProbesShader.uniforms, PbrAreaProbesShader.textures),
			Renderer.slotsOf(PbrInstancedAreaProbesShader.uniforms, PbrInstancedAreaProbesShader.textures)
		];
	}

	public function attach(renderer:Renderer) {
		this.renderer = renderer;
		@:privateAccess renderer.areaSource = this;
	}

	// ---- AreaSource: the variants (with probes: Probes' block too)

	@:noCompletion public function pipeline(instanced:Bool, doubleSided:Bool, probes:Bool):Pipeline {
		var k = (probes ? 4 : 0) + (instanced ? 2 : 0) + (doubleSided ? 1 : 0);
		var p = pipelines[k];
		if (p == null) {
			var cull:Cull = doubleSided ? None : Back;
			var o:PipelineOptions = {cull: cull, depthCompare: Less, depthWrite: true};
			var d = probes ? (instanced ? PbrInstancedAreaProbesShader.pipeline(o) : PbrAreaProbesShader.pipeline(o)) : instanced ? PbrInstancedAreaShader.pipeline(o) : PbrAreaShader.pipeline(o);
			if (instanced) d.layout = @:privateAccess Renderer.INSTANCED_LAYOUT;
			p = pipelines[k] = renderer.createPipeline(d);
		}
		return p;
	}

	@:noCompletion public function slots(instanced:Bool, probes:Bool):Array<Int>
		return slotsOf[(probes ? 2 : 0) + (instanced ? 1 : 0)];

	// the tables at a variant's slot (Renderer.slotsOf's 21)
	@:noCompletion public function bind(enc:Encoder, slots:Array<Int>)
		if (slots[21] >= 0) enc.setTexture(slots[21], ltc, sampler);

	public function dispose()
		device.destroyTexture(ltc);
}
