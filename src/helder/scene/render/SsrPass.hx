package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Mat4;
import helder.gfx.shader.Vec4;
import helder.scene.render.EffectShaders;
import helder.scene.render.PostEffects;
import helder.scene.render.SsrShaders;

// Ssr's passes (PostFx's, made by post.ssr's setter's factory): the rays
// into an RGBA16F target at half the frame's size (ssr.texture), then the
// scene's light with them mixed in into one of the frame's size, the light
// the chain goes on with. A module of its own: an Ssr made and never set on
// a chain links none of it.
class SsrPass implements LightPass {
	final ssr:Ssr;

	var device:Null<Device> = null;
	var trace:Null<Pipeline> = null;
	var resolve:Null<Pipeline> = null;
	var out:Null<Texture> = null;
	final bytes = Bytes.alloc(SsrTraceShader.uniforms[0].size);
	final block:SsrParams = {
		projection: Mat4.identity(), inverseProjection: Mat4.identity(), p: new Vec4(0, 0, 0, 0), size: new Vec4(0, 0, 0, 0), q: new Vec4(0, 0, 0, 0)
	};
	final tracePass:PassDesc = {colors: [{load: Clear, clear: new Vec4(0, 0, 0, 0)}]};
	final resolvePass:PassDesc = {colors: [{load: Clear, clear: new Vec4(0, 0, 0, 0)}]};
	var w = 0;
	var h = 0;
	var rw = 0;
	var rh = 0;
	var draws = 0;

	public function new(ssr:Ssr)
		this.ssr = ssr;

	public static function make(ssr:Ssr):LightPass
		return new SsrPass(ssr);

	@:noCompletion public function require(fx:PostFx, renderer:Renderer)
		fx.read(ViewBuffers.of(renderer), ssr.halfRes ? 0.5 : 1);

	@:noCompletion public function drawn():Int
		return draws;

	@:noCompletion public function run(enc:Encoder, fx:PostFx, light:Texture):Texture {
		draws = 0;
		var v = fx.views;
		if (v == null || ssr.intensity <= 0) return light;
		if (device == null) {
			device = fx.device;
			var t = SsrTraceShader.pipeline({});
			t.colorFormat = RGBA16F;
			trace = device.createPipeline(t);
			var r = SsrResolveShader.pipeline({});
			r.colorFormat = RGBA16F;
			resolve = device.createPipeline(r);
		}
		var width = fx.post.width, height = fx.post.height;
		size(width, height, ssr.halfRes ? Std.int(Math.max(1, (width + 1) >> 1)) : width, ssr.halfRes ? Std.int(Math.max(1, (height + 1) >> 1)) : height);
		var b = block;
		b.projection = v.projection;
		b.inverseProjection = v.inverseProjection;
		b.p = new Vec4(Math.max(0.01, ssr.maxDistance), Math.max(0.001, ssr.thickness), Math.max(4, ssr.steps), Math.max(0.01, ssr.maxRoughness));
		b.size = new Vec4(rw, rh, v.width, v.height);
		// (with TAA the dither turned each frame by the golden ratio: the history gathers it smooth)
		var f = fx.frame;
		b.q = new Vec4(ssr.intensity, fx.post.taa != null && f != null ? (f.index * 0.618034) % 1 : 0, 0, 0);
		SsrTraceShader.params.s.write(b, bytes);
		enc.beginPass(tracePass);
		enc.setPipeline(trace);
		enc.setUniforms(SsrTraceShader.uniforms[0].binding, bytes);
		enc.setTexture(SsrTraceShader.params.depth.binding, v.depth, fx.nearest);
		enc.setTexture(SsrTraceShader.params.normals.binding, v.normals, fx.nearest);
		enc.setTexture(SsrTraceShader.params.scene.binding, light, fx.linear);
		enc.setVertexBuffer(0, fx.triangle);
		enc.draw(3);
		enc.endPass();
		// (the resolve at the frame's size: its own pixels' texels of the view buffers)
		b.size = new Vec4(w, h, v.width, v.height);
		SsrTraceShader.params.s.write(b, bytes);
		enc.beginPass(resolvePass);
		enc.setPipeline(resolve);
		enc.setUniforms(SsrResolveShader.uniforms[0].binding, bytes);
		enc.setTexture(SsrResolveShader.params.depth.binding, v.depth, fx.nearest);
		enc.setTexture(SsrResolveShader.params.normals.binding, v.normals, fx.nearest);
		enc.setTexture(SsrResolveShader.params.scene.binding, light, fx.nearest);
		enc.setTexture(SsrResolveShader.params.reflections.binding, ssr.texture, fx.linear);
		enc.setVertexBuffer(0, fx.triangle);
		enc.draw(3);
		enc.endPass();
		draws = 2;
		return out;
	}

	function size(width:Int, height:Int, tw:Int, th:Int) {
		if (width == w && height == h && tw == rw && th == rh) return;
		release();
		w = width;
		h = height;
		rw = tw;
		rh = th;
		var t = device.createTexture({width: rw, height: rh, format: RGBA16F, renderTarget: true});
		@:privateAccess ssr.texture = t;
		out = device.createTexture({width: w, height: h, format: RGBA16F, renderTarget: true});
		tracePass.colors[0].texture = t;
		resolvePass.colors[0].texture = out;
	}

	function release() {
		var t = ssr.texture;
		if (t != null) device.destroyTexture(t);
		if (out != null) device.destroyTexture(out);
		@:privateAccess ssr.texture = null;
		out = null;
		w = h = rw = rh = 0;
	}

	@:noCompletion public function dispose()
		if (device != null) release();
}
