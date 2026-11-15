package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Mat4;
import helder.gfx.shader.Vec4;
import helder.scene.math.MathTools;
import helder.scene.render.EffectShaders;
import helder.scene.render.MotionBlurShader;
import helder.scene.render.PostEffects;

// MotionBlur's pass (PostFx's, made by post.motionBlur's setter's factory):
// the light along each pixel's motion into an RGBA16F target of the frame's
// size, the light the chain goes on with. A module of its own: a MotionBlur
// made and never set on a chain links none of it.
class MotionBlurPass implements LightPass {
	final blur:MotionBlur;

	var device:Null<Device> = null;
	var pipeline:Null<Pipeline> = null;
	final bytes = Bytes.alloc(MotionBlurShader.uniforms[0].size);
	final block:MotionParams = {
		inverseViewProj: Mat4.identity(), current: Mat4.identity(), previous: Mat4.identity(), size: new Vec4(0, 0, 0, 0), p: new Vec4(0, 0, 0, 0),
		q: new Vec4(0, 0, 0, 0)
	};
	final pass:PassDesc = {colors: [{load: Clear, clear: new Color(0, 0, 0, 0)}]};
	var target:Null<Texture> = null;
	var w = 0;
	var h = 0;
	var draws = 0;

	public function new(blur:MotionBlur)
		this.blur = blur;

	public static function make(blur:MotionBlur):LightPass
		return new MotionBlurPass(blur);

	@:noCompletion public function require(fx:PostFx, renderer:Renderer)
		fx.read(ViewBuffers.of(renderer), 0.5, blur.objects);

	@:noCompletion public function drawn():Int
		return draws;

	@:noCompletion public function run(enc:Encoder, fx:PostFx, light:Texture):Texture {
		draws = 0;
		var v = fx.views, f = fx.frame;
		if (v == null || f == null || blur.strength <= 0) return light;
		if (device == null) {
			device = fx.device;
			var d = MotionBlurShader.pipeline({});
			d.colorFormat = RGBA16F;
			pipeline = device.createPipeline(d);
		}
		size(fx.post.width, fx.post.height);
		var b = block;
		b.inverseViewProj = MathTools.inverse(f.viewProj);
		b.current = f.stillViewProj;
		b.previous = f.previousViewProj;
		b.size = new Vec4(w, h, v.width, v.height);
		b.p = new Vec4(blur.strength, Math.max(2, blur.samples), 0, Math.max(0, blur.max));
		var motion = blur.objects ? v.motion : null;
		b.q = new Vec4(motion != null ? 1 : 0, w / Math.max(1, h), 0, 0);
		MotionBlurShader.params.m.write(b, bytes);
		enc.beginPass(pass);
		enc.setPipeline(pipeline);
		enc.setUniforms(MotionBlurShader.uniforms[0].binding, bytes);
		enc.setTexture(MotionBlurShader.params.scene.binding, light, fx.linear);
		enc.setTexture(MotionBlurShader.params.motion.binding, motion != null ? motion : fx.white, fx.linear);
		enc.setTexture(MotionBlurShader.params.depth.binding, v.depth, fx.nearest);
		enc.setVertexBuffer(0, fx.triangle);
		enc.draw(3);
		enc.endPass();
		draws = 1;
		return target;
	}

	function size(width:Int, height:Int) {
		if (width == w && height == h) return;
		release();
		w = width;
		h = height;
		target = device.createTexture({width: w, height: h, format: RGBA16F, renderTarget: true});
		pass.colors[0].texture = target;
	}

	function release() {
		if (target != null) device.destroyTexture(target);
		target = null;
		w = h = 0;
	}

	@:noCompletion public function dispose()
		if (device != null) release();
}
