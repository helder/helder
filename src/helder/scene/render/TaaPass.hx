package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Mat4;
import helder.gfx.shader.Vec2;
import helder.gfx.shader.Vec4;
import helder.scene.math.MathTools;
import helder.scene.render.EffectShaders;
import helder.scene.render.PostEffects;
import helder.scene.render.TaaShader;

// Temporal antialiasing's passes (post.taa: Taa, TaaShader's notes):
// before each frame the renderer's projection jittered by the next of 8
// points of Halton's (2, 3) sequence about the pixel's centre (to a
// sixteenth of a pixel: the same edges on every rasterizer; its view
// buffers' and main pass's alike), the view buffers asked for whole and
// with their motion (ViewBuffers.velocity); after it, the resolve into
// one of two RGBA16F histories of the frame's size taken in turn, the new
// one the light the chain goes on with (depth of field, motion blur,
// bloom, the composite). A history is let go when the frame's size
// changes, for the first frame, and at a cut (PostProcess.resetHistory).
// A module of its own: linked by a program that sets post.taa.
class TaaPass implements LightPass {
	final taa:Taa;

	var device:Null<Device> = null;
	var pipeline:Null<Pipeline> = null;
	final bytes = Bytes.alloc(TaaShader.uniforms[0].size);
	final block:MotionParams = {
		inverseViewProj: Mat4.identity(), current: Mat4.identity(), previous: Mat4.identity(), size: new Vec4(0, 0, 0, 0), p: new Vec4(0, 0, 0, 0),
		q: new Vec4(0, 0, 0, 0)
	};
	final histories:Array<Texture> = [];
	final passes:Array<PassDesc> = [];
	var w = 0;
	var h = 0;
	var next = 0;
	// (whether the history is the frame before's: off at the first frame, a size, a cut)
	var valid = false;
	var cuts = 0;
	var draws = 0;

	public function new(taa:Taa)
		this.taa = taa;

	public static function make(taa:Taa):LightPass
		return new TaaPass(taa);

	// the k-th point of Halton's sequence in a base (0..1)
	static function halton(k:Int, base:Int):Float {
		var f = 1.0, r = 0.0, i = k;
		while (i > 0) {
			f /= base;
			r += f * (i % base);
			i = Std.int(i / base);
		}
		return r;
	}

	@:noCompletion public function require(fx:PostFx, renderer:Renderer) {
		fx.read(ViewBuffers.of(renderer), 1, true);
		// (the next of 8 points about the pixel's centre, in pixels, on a
		// sixteenth's grid: every rasterizer's sub-pixel precision has it, so
		// a jittered edge falls where an unjittered one would, moved)
		var k = renderer.frames % 8 + 1;
		renderer.jitter = new Vec2(Math.round(halton(k, 2) * 16) / 16 - 0.5, Math.round(halton(k, 3) * 16) / 16 - 0.5);
	}

	@:noCompletion public function drawn():Int
		return draws;

	@:noCompletion public function run(enc:Encoder, fx:PostFx, light:Texture):Texture {
		draws = 0;
		var v = fx.views, f = fx.frame;
		if (v == null || f == null) return light;
		if (device == null) {
			device = fx.device;
			var d = TaaShader.pipeline({});
			d.colorFormat = RGBA16F;
			pipeline = device.createPipeline(d);
		}
		size(fx.post.width, fx.post.height);
		if (@:privateAccess fx.post.cuts != cuts) {
			cuts = @:privateAccess fx.post.cuts;
			valid = false;
		}
		var b = block;
		b.inverseViewProj = MathTools.inverse(f.viewProj);
		b.current = f.stillViewProj;
		b.previous = f.previousViewProj;
		b.size = new Vec4(w, h, v.width, v.height);
		b.p = new Vec4(Math.max(0.01, Math.min(1, taa.blend)), valid ? 1 : 0, 0, 0);
		var motion = v.motion;
		b.q = new Vec4(motion != null ? 1 : 0, w / Math.max(1, h), 0, 0);
		TaaShader.params.m.write(b, bytes);
		var into = histories[next], from = histories[1 - next];
		enc.beginPass(passes[next]);
		enc.setPipeline(pipeline);
		enc.setUniforms(TaaShader.uniforms[0].binding, bytes);
		enc.setTexture(TaaShader.params.scene.binding, light, fx.nearest);
		enc.setTexture(TaaShader.params.history.binding, from, fx.linear);
		enc.setTexture(TaaShader.params.motion.binding, motion != null ? motion : fx.white, fx.nearest);
		enc.setTexture(TaaShader.params.depth.binding, v.depth, fx.nearest);
		enc.setVertexBuffer(0, fx.triangle);
		enc.draw(3);
		enc.endPass();
		draws = 1;
		next = 1 - next;
		valid = true;
		return into;
	}

	function size(width:Int, height:Int) {
		if (width == w && height == h) return;
		release();
		w = width;
		h = height;
		for (_ in 0...2) {
			var t = device.createTexture({width: w, height: h, format: RGBA16F, renderTarget: true});
			histories.push(t);
			passes.push({colors: [{load: Clear, clear: new Color(0, 0, 0, 0), texture: t}]});
		}
		valid = false;
	}

	function release() {
		for (t in histories)
			device.destroyTexture(t);
		histories.resize(0);
		passes.resize(0);
		w = h = 0;
	}

	@:noCompletion public function dispose()
		if (device != null) release();
}
