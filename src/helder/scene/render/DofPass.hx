package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.math.Vec4;
import helder.scene.render.DofMode;
import helder.scene.render.EffectShaders;
import helder.scene.render.DofShader;
import helder.scene.render.PostEffects;

// Dof's pass (PostFx's, made by post.dof's setter's factory): the half-size
// gather into an RGBA16F target (dof.texture), and its part of the
// composite. A module of its own: a Dof made and never set on a chain links
// none of it.
class DofPass implements PostPass {
	final dof:Dof;

	var device:Null<Device> = null;
	var pipeline:Null<Pipeline> = null;
	final bytes = Bytes.alloc(DofShader.uniforms[1].size);
	final block:DofParams = {size: new Vec4(0, 0, 0, 0), views: new Vec4(0, 0, 0, 0)};
	final pass:PassDesc = {colors: [{load: Clear, clear: new Vec4(0, 0, 0, 0)}]};
	var w = 0;
	var h = 0;

	public function new(dof:Dof)
		this.dof = dof;

	public static function make(dof:Dof):PostPass
		return new DofPass(dof);

	@:noCompletion public function require(fx:PostFx, renderer:Renderer)
		fx.read(ViewBuffers.of(renderer), 0.5);

	@:noCompletion public function result():Null<Texture>
		return null;

	// (its part of the composite's block: the circle of confusion's, the focus)
	@:noCompletion public function write(fx:PostFx) {
		fx.block.dof = dof.params();
		fx.block.dofFocus = new Vec4(dof.mode == TiltShift ? dof.distance : 0, dof.center, 2, 0);
	}

	@:noCompletion public function bind(enc:Encoder, fx:PostFx, slots:Array<Int>) {
		var t = @:privateAccess dof.texture;
		if (slots[3] >= 0 && t != null) enc.setTexture(slots[3], t, fx.linear);
	}

	@:noCompletion public function draw(enc:Encoder, fx:PostFx):Int {
		var light = fx.light;
		if (light == null || fx.views == null) return 0;
		if (device == null) {
			device = fx.device;
			var d = DofShader.pipeline({});
			d.colorFormat = RGBA16F;
			pipeline = device.createPipeline(d);
		}
		size(Std.int(Math.max(1, (fx.post.width + 1) >> 1)), Std.int(Math.max(1, (fx.post.height + 1) >> 1)));
		block.size = new Vec4(w, h, fx.post.width / Math.max(1, fx.post.height), Math.max(4, dof.samples));
		block.views = new Vec4(fx.views.width, fx.views.height, 0, 0);
		DofShader.params.d.write(block, bytes);
		enc.beginPass(pass);
		enc.setPipeline(pipeline);
		enc.setUniforms(DofShader.uniforms[0].binding, fx.blockBytes);
		enc.setUniforms(DofShader.uniforms[1].binding, bytes);
		enc.setTexture(DofShader.params.scene.binding, light, fx.linear);
		enc.setTexture(DofShader.params.viewDepth.binding, fx.views.depth, fx.nearest);
		enc.setVertexBuffer(0, fx.triangle);
		enc.draw(3);
		enc.endPass();
		return 1;
	}

	function size(width:Int, height:Int) {
		if (width == w && height == h) return;
		release();
		w = width;
		h = height;
		var t = device.createTexture({width: w, height: h, format: RGBA16F, renderTarget: true});
		@:privateAccess dof.texture = t;
		pass.colors[0].texture = t;
	}

	function release() {
		var t = @:privateAccess dof.texture;
		if (t != null) device.destroyTexture(t);
		@:privateAccess dof.texture = null;
		w = h = 0;
	}

	@:noCompletion public function dispose()
		if (device != null) release();
}
