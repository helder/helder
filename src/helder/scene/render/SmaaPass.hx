package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Vec4;
import helder.scene.render.CompositeFxSmaaShader;
import helder.scene.render.PostEffects;
import helder.scene.render.SmaaShaders;

// SMAA's passes (post.smaa: Smaa, SmaaShaders' notes): the edges of
// the light the composite reads into an RGBA8 target of the frame's size,
// their blending weights into another, blended by the composite's SMAA
// variant (CompositeFxSmaaShader). A module of its own, installed by
// post.smaa's setter: a program that never sets one links none of it.
class SmaaPass implements PostPass {
	final smaa:Smaa;

	var device:Null<Device> = null;
	var edgePipeline:Null<Pipeline> = null;
	var weightPipeline:Null<Pipeline> = null;
	var edges:Null<Texture> = null;
	var weights:Null<Texture> = null;
	final bytes = Bytes.alloc(SmaaEdgeShader.uniforms[0].size);
	final block:SmaaParams = {size: new Vec4(0, 0, 0, 0)};
	final edgePass:PassDesc = {colors: [{load: Clear, clear: new Color(0, 0, 0, 0)}]};
	final weightPass:PassDesc = {colors: [{load: Clear, clear: new Color(0, 0, 0, 0)}]};
	var w = 0;
	var h = 0;

	function new(smaa:Smaa)
		this.smaa = smaa;

	// (post.smaa: the pass and the composite's variant)
	public static function install() {
		PostFx.makeSmaa = s -> new SmaaPass(s);
		PostFx.smaaComposite = () -> CompositeFxSmaaShader.pipeline({});
		PostFx.smaaUniforms = CompositeFxSmaaShader.uniforms;
		PostFx.smaaTextures = CompositeFxSmaaShader.textures;
	}

	@:noCompletion public function require(fx:PostFx, renderer:Renderer) {}

	@:noCompletion public function result():Null<Texture>
		return weights;

	@:noCompletion public function write(fx:PostFx)
		fx.block.smaa = new Vec4(1 / Math.max(1, w), 1 / Math.max(1, h), 0, 0);

	@:noCompletion public function bind(enc:Encoder, fx:PostFx, slots:Array<Int>)
		if (slots[7] >= 0 && weights != null) enc.setTexture(slots[7], weights, fx.nearest);

	@:noCompletion public function draw(enc:Encoder, fx:PostFx):Int {
		var light = fx.light;
		if (light == null) return 0;
		if (device == null) {
			device = fx.device;
			var e = SmaaEdgeShader.pipeline({});
			e.colorFormat = RGBA8;
			edgePipeline = device.createPipeline(e);
			var g = SmaaWeightShader.pipeline({});
			g.colorFormat = RGBA8;
			weightPipeline = device.createPipeline(g);
		}
		size(fx.post.width, fx.post.height);
		block.size = new Vec4(w, h, smaa.threshold, 16);
		SmaaEdgeShader.params.s.write(block, bytes);
		enc.beginPass(edgePass);
		enc.setPipeline(edgePipeline);
		enc.setUniforms(SmaaEdgeShader.uniforms[0].binding, bytes);
		enc.setTexture(SmaaEdgeShader.params.scene.binding, light, fx.nearest);
		enc.setVertexBuffer(0, fx.triangle);
		enc.draw(3);
		enc.endPass();
		enc.beginPass(weightPass);
		enc.setPipeline(weightPipeline);
		enc.setUniforms(SmaaWeightShader.uniforms[0].binding, bytes);
		enc.setTexture(SmaaWeightShader.params.edges.binding, edges, fx.nearest);
		enc.setVertexBuffer(0, fx.triangle);
		enc.draw(3);
		enc.endPass();
		return 2;
	}

	function size(width:Int, height:Int) {
		if (width == w && height == h) return;
		release();
		w = width;
		h = height;
		edges = device.createTexture({width: w, height: h, renderTarget: true});
		weights = device.createTexture({width: w, height: h, renderTarget: true});
		edgePass.colors[0].texture = edges;
		weightPass.colors[0].texture = weights;
	}

	function release() {
		if (edges != null) device.destroyTexture(edges);
		if (weights != null) device.destroyTexture(weights);
		edges = weights = null;
		w = h = 0;
	}

	@:noCompletion public function dispose()
		if (device != null) release();
}
