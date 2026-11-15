package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Mat4;
import helder.gfx.shader.Vec4;
import helder.scene.math.MathTools;
import helder.scene.render.EffectShaders;
import helder.scene.render.MotionBlurShader;
import helder.scene.render.PostEffects;

// MotionBlur's passes (PostFx's, made by post.motionBlur's setter's
// factory; MotionBlurShader's notes): the motion at the view buffers' size,
// its tiles' longest and their neighbourhoods' (RGBA16F), the light along
// each pixel's line at half the frame's size, then mixed in at the frame's
// size where it moves (an RGBA16F target), the light the chain goes on with. A module of its own: a MotionBlur made and
// never set on a chain links none of it.
class MotionBlurPass implements LightPass {
	final blur:MotionBlur;

	var device:Null<Device> = null;
	final pipelines:Array<Pipeline> = [];
	// (each pass's block's slot)
	final slots = [MotionPrepShader.uniforms[0].binding, MotionTileShader.uniforms[0].binding, MotionNeighbourShader.uniforms[0].binding,
		MotionBlurShader.uniforms[0].binding, MotionMixShader.uniforms[0].binding];
	final bytes = Bytes.alloc(MotionBlurShader.uniforms[0].size);
	final block:MotionParams = {
		inverseViewProj: Mat4.identity(), current: Mat4.identity(), previous: Mat4.identity(), size: new Vec4(0, 0, 0, 0), p: new Vec4(0, 0, 0, 0),
		q: new Vec4(0, 0, 0, 0)
	};
	// (the targets: the motion, the tiles, their neighbourhoods, the blur at half size, the mix)
	final targets:Array<Texture> = [];
	final passes:Array<PassDesc> = [];
	var w = 0;
	var h = 0;
	var vw = 0;
	var vh = 0;
	var tw = 0;
	var th = 0;
	var bw = 0;
	var bh = 0;
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
			for (d in [
				MotionPrepShader.pipeline({}),
				MotionTileShader.pipeline({}),
				MotionNeighbourShader.pipeline({}),
				MotionBlurShader.pipeline({}),
				MotionMixShader.pipeline({})
			]) {
				d.colorFormat = RGBA16F;
				pipelines.push(device.createPipeline(d));
			}
		}
		size(fx.post.width, fx.post.height, v.width, v.height);
		var b = block;
		b.inverseViewProj = MathTools.inverse(f.viewProj);
		b.current = f.stillViewProj;
		b.previous = f.previousViewProj;
		b.p = new Vec4(blur.strength, Math.max(2, blur.samples), 0, Math.max(0, blur.max));
		var motion = blur.objects ? v.motion : null;
		// (the motion: its texels the view buffers')
		b.size = new Vec4(vw, vh, vw, vh);
		b.q = new Vec4(motion != null ? 1 : 0, w / Math.max(1, h), w, h);
		pass(enc, 0, fx);
		enc.setTexture(MotionPrepShader.params.motion.binding, motion != null ? motion : fx.white, fx.nearest);
		enc.setTexture(MotionPrepShader.params.depth.binding, v.depth, fx.nearest);
		draw(enc, fx);
		// (the tiles' longest, then their neighbourhoods')
		b.size = new Vec4(tw, th, vw, vh);
		pass(enc, 1, fx);
		enc.setTexture(MotionTileShader.params.prep.binding, targets[0], fx.nearest);
		draw(enc, fx);
		b.size = new Vec4(tw, th, tw, th);
		pass(enc, 2, fx);
		enc.setTexture(MotionNeighbourShader.params.tiles.binding, targets[1], fx.nearest);
		draw(enc, fx);
		// (the blur at half size: q.z the view buffers' share of it, to find a pixel's tile)
		b.size = new Vec4(bw, bh, tw, th);
		b.q = new Vec4(0, w / Math.max(1, h), vw / Math.max(1, bw), 0);
		pass(enc, 3, fx);
		enc.setTexture(MotionBlurShader.params.scene.binding, light, fx.linear);
		enc.setTexture(MotionBlurShader.params.prep.binding, targets[0], fx.linear);
		enc.setTexture(MotionBlurShader.params.neighbours.binding, targets[2], fx.nearest);
		draw(enc, fx);
		// (mixed in at the frame's size where it moves)
		b.size = new Vec4(w, h, tw, th);
		b.q = new Vec4(0, w / Math.max(1, h), vw / Math.max(1, w), 0);
		pass(enc, 4, fx);
		enc.setTexture(MotionMixShader.params.scene.binding, light, fx.nearest);
		enc.setTexture(MotionMixShader.params.blur.binding, targets[3], fx.linear);
		enc.setTexture(MotionMixShader.params.neighbours.binding, targets[2], fx.nearest);
		draw(enc, fx);
		return targets[4];
	}

	// (a pass of the four: its target, its pipeline, the block as it is now)
	function pass(enc:Encoder, k:Int, fx:PostFx) {
		MotionBlurShader.params.m.write(block, bytes);
		enc.beginPass(passes[k]);
		enc.setPipeline(pipelines[k]);
		enc.setUniforms(slots[k], bytes);
	}

	function draw(enc:Encoder, fx:PostFx) {
		enc.setVertexBuffer(0, fx.triangle);
		enc.draw(3);
		enc.endPass();
		draws++;
	}

	function size(width:Int, height:Int, viewsWidth:Int, viewsHeight:Int) {
		if (width == w && height == h && viewsWidth == vw && viewsHeight == vh) return;
		release();
		w = width;
		h = height;
		vw = viewsWidth;
		vh = viewsHeight;
		tw = Std.int(Math.max(1, (vw + 7) >> 3));
		th = Std.int(Math.max(1, (vh + 7) >> 3));
		bw = Std.int(Math.max(1, (w + 1) >> 1));
		bh = Std.int(Math.max(1, (h + 1) >> 1));
		for (s in [[vw, vh], [tw, th], [tw, th], [bw, bh], [w, h]]) {
			var t = device.createTexture({width: s[0], height: s[1], format: RGBA16F, renderTarget: true});
			targets.push(t);
			passes.push({colors: [{load: Clear, clear: new Color(0, 0, 0, 0), texture: t}]});
		}
	}

	function release() {
		for (t in targets)
			device.destroyTexture(t);
		targets.resize(0);
		passes.resize(0);
		w = h = 0;
	}

	@:noCompletion public function dispose()
		if (device != null) release();
}
