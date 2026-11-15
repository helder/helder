package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Vec4;
import helder.scene.render.EffectShaders;
import helder.scene.render.GodRaysShader;
import helder.scene.render.PostEffects;

// GodRays' pass (PostFx's, made by post.godRays' setter's factory): the
// shafts into an RGBA16F target a quarter of the frame's size (rays.texture),
// added in the composite. A module of its own: a GodRays made and never set
// on a chain links none of it.
class GodRaysPass implements PostPass {
	final rays:GodRays;

	var device:Null<Device> = null;
	var pipeline:Null<Pipeline> = null;
	final bytes = Bytes.alloc(GodRaysShader.uniforms[0].size);
	final block:GodRaysParams = {sun: new Vec4(0, 0, 0, 0), p: new Vec4(0, 0, 0, 0), size: new Vec4(0, 0, 0, 0)};
	final pass:PassDesc = {colors: [{load: Clear, clear: new Color(0, 0, 0, 0)}]};
	var w = 0;
	var h = 0;
	// (the sun's fade this frame: 0 behind the camera)
	var fade = 0.0;

	public function new(rays:GodRays)
		this.rays = rays;

	public static function make(rays:GodRays):PostPass
		return new GodRaysPass(rays);

	@:noCompletion public function require(fx:PostFx, renderer:Renderer)
		fx.read(ViewBuffers.of(renderer), 0.5);

	@:noCompletion public function result():Null<Texture>
		return rays.texture;

	@:noCompletion public function write(fx:PostFx)
		fx.block.rays = new Vec4(fade > 0 && rays.texture != null ? 1 : 0, rays.intensity, 0, 0);

	@:noCompletion public function bind(enc:Encoder, fx:PostFx, slots:Array<Int>) {
		var t = rays.texture;
		if (slots[6] >= 0 && t != null) enc.setTexture(slots[6], t, fx.linear);
	}

	@:noCompletion public function draw(enc:Encoder, fx:PostFx):Int {
		var light = fx.light, v = fx.views, f = fx.frame;
		fade = 0;
		if (light == null || v == null || f == null) return 0;
		// (the sun's place: its direction through the view-projection, w 0)
		var l = f.toLight;
		var c = f.stillViewProj * new Vec4(l.x, l.y, l.z, 0);
		if (c.w <= 0.0001) return 0;
		var sx = (c.x / c.w) * 0.5 + 0.5, sy = 0.5 - (c.y / c.w) * 0.5;
		// (faded out as it leaves the screen, by half a frame beyond its edges)
		var out = Math.max(Math.max(-sx, sx - 1), Math.max(-sy, sy - 1));
		fade = 1 - Math.max(0, Math.min(1, out * 2));
		if (fade <= 0) return 0;
		if (device == null) {
			device = fx.device;
			var d = GodRaysShader.pipeline({});
			d.colorFormat = RGBA16F;
			pipeline = device.createPipeline(d);
		}
		size(Std.int(Math.max(1, (fx.post.width + 3) >> 2)), Std.int(Math.max(1, (fx.post.height + 3) >> 2)));
		block.sun = new Vec4(sx, sy, fade, fx.post.width / Math.max(1, fx.post.height));
		block.p = new Vec4(Math.max(4, rays.samples), rays.density, rays.decay, rays.falloff);
		block.size = new Vec4(w, h, v.width, v.height);
		GodRaysShader.params.g.write(block, bytes);
		enc.beginPass(pass);
		enc.setPipeline(pipeline);
		enc.setUniforms(GodRaysShader.uniforms[0].binding, bytes);
		enc.setTexture(GodRaysShader.params.scene.binding, light, fx.linear);
		enc.setTexture(GodRaysShader.params.depth.binding, v.depth, fx.nearest);
		enc.setVertexBuffer(0, fx.triangle);
		enc.draw(3);
		enc.endPass();
		// (its part of the composite's block, now that it is drawn)
		write(fx);
		return 1;
	}

	function size(width:Int, height:Int) {
		if (width == w && height == h) return;
		release();
		w = width;
		h = height;
		var t = device.createTexture({width: w, height: h, format: RGBA16F, renderTarget: true});
		@:privateAccess rays.texture = t;
		pass.colors[0].texture = t;
	}

	function release() {
		var t = rays.texture;
		if (t != null) device.destroyTexture(t);
		@:privateAccess rays.texture = null;
		w = h = 0;
	}

	@:noCompletion public function dispose()
		if (device != null) release();
}
