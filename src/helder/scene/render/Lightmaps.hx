package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.math.Vec4;
import helder.scene.Node;
import helder.scene.render.PbrLightmapShader;
import helder.scene.render.PbrShader;

// Baked lightmaps, opted in (renderer.use(new Lightmaps(device))): the
// standard material's opaque draws of nodes with a Lightmap (and second
// uvs) are drawn with pbr's lightmap variant (PbrLightmapShader: the
// lightmap read at the second uvs placed in its rectangle, its light the
// ambient), one a node: a run of instanced draws stops at a lightmapped node.
// A program without one links none of it.
class Lightmaps implements RenderFeature implements RenderFeature.LightmapSource {
	public final device:Device;

	final sampler:Sampler;
	var renderer:Null<Renderer> = null;
	final pipelines:Array<Null<Pipeline>> = [null, null];
	final plainSlots:Array<Int>;
	final block:PbrLightmap = {rect: new Vec4(0, 0, 1, 1), params: new Vec4(1, 0, 0, 0)};
	final bytes = Bytes.alloc(PbrLightmapShader.params.lightmap.block.size);

	public function new(device:Device) {
		this.device = device;
		sampler = device.createSampler({filter: Linear, wrap: Clamp});
		plainSlots = Renderer.slotsOf(PbrLightmapShader.uniforms, PbrLightmapShader.textures);
	}

	public function attach(renderer:Renderer) {
		this.renderer = renderer;
		@:privateAccess renderer.lightmapSource = this;
	}

	// ---- LightmapSource

	@:noCompletion public function has(node:Node):Bool
		return !node.isNone && node.world.store(Lightmap.KIND).get(node) != null;

	@:noCompletion public function pipeline(doubleSided:Bool):Pipeline {
		var k = doubleSided ? 1 : 0;
		var p = pipelines[k];
		if (p == null) {
			var d = PbrLightmapShader.pipeline({cull: doubleSided ? None : Back, depthCompare: Less, depthWrite: true});
			// (the second uvs a buffer of their own, after the mesh's)
			var base = @:privateAccess Renderer.INSTANCED_LAYOUT[0];
			d.layout = [base, {stride: 8, attributes: [{location: base.attributes.length, format: Float2, offset: 0}]}];
			p = pipelines[k] = renderer.createPipeline(d);
		}
		return p;
	}

	@:noCompletion public function slots():Array<Int>
		return plainSlots;

	// a node's lightmap: its block and texture
	@:noCompletion public function bind(enc:Encoder, node:Node) {
		var l = node.world.store(Lightmap.KIND).get(node);
		if (l == null) return;
		block.rect = l.rect;
		block.params = new Vec4(l.intensity, (l.mode == All ? 1 : 0) + (l.srgb ? 2 : 0), 0, 0);
		PbrLightmapShader.params.lightmap.write(block, bytes);
		enc.setUniforms(PbrLightmapShader.params.lightmap.block.binding, bytes);
		enc.setTexture(PbrLightmapShader.params.lightMap.binding, l.texture, sampler);
	}
}
