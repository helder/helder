package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.math.Vec4;
import helder.scene.render.EffectShaders;
import helder.scene.render.AoShaders;
import helder.scene.render.PostEffects;

// Ssao's passes (PostFx's, made by post.ao's setter's factory): GTAO from
// the view buffers into an R8 target, its bilateral blur up to their size
// (ao.texture). A module of its own: an Ssao made and never set on a chain
// links none of it.
class SsaoPass implements PostPass {
	final ao:Ssao;

	var device:Null<Device> = null;
	var raw:Null<Texture> = null;
	var gtao:Null<Pipeline> = null;
	var blur:Null<Pipeline> = null;
	final aoBytes = Bytes.alloc(GtaoShader.uniforms[0].size);
	final blurBytes = Bytes.alloc(AoBlurShader.uniforms[0].size);
	// (the blocks as written, kept: nothing allocated per frame)
	final aoBlock:AoParams = {inverseProjection: helder.math.Mat4.identity(), p: new Vec4(0, 0, 0, 0), size: new Vec4(0, 0, 0, 0), more: new Vec4(0, 0, 0, 0)};
	final blurBlock:AoBlurParams = {p: new Vec4(0, 0, 0, 0), inverseProjection: helder.math.Mat4.identity()};
	final rawPass:PassDesc = {colors: [{load: Clear, clear: new Vec4(1, 1, 1, 1)}]};
	final outPass:PassDesc = {colors: [{load: Clear, clear: new Vec4(1, 1, 1, 1)}]};
	var w = 0;
	var h = 0;
	var rw = 0;
	var rh = 0;

	public function new(ao:Ssao)
		this.ao = ao;

	public static function make(ao:Ssao):PostPass
		return new SsaoPass(ao);

	@:noCompletion public function require(fx:PostFx, renderer:Renderer)
		fx.read(ViewBuffers.of(renderer), 0.5);

	@:noCompletion public function result():Null<Texture>
		return @:privateAccess ao.texture;

	@:noCompletion public function write(fx:PostFx) {}

	@:noCompletion public function bind(enc:Encoder, fx:PostFx, slots:Array<Int>) {}

	@:noCompletion public function draw(enc:Encoder, fx:PostFx):Int {
		var v = fx.views;
		if (v == null) return 0;
		if (device == null) {
			device = fx.device;
			var g = GtaoShader.pipeline({});
			g.colorFormat = R8;
			gtao = device.createPipeline(g);
			var b = AoBlurShader.pipeline({});
			b.colorFormat = R8;
			blur = device.createPipeline(b);
		}
		// (half the frame's size: the view buffers' halved when they are whole)
		size(v.width, v.height, ao.halfRes && v.drawnScale > 0.75);
		var p = v.projection;
		var perspective = p.c3.w == 0;
		// (a metre at a distance of 1 in the height's uv: the projection's y scale, halved)
		var scale = perspective ? p.c1.y * 0.5 : 0;
		var a = aoBlock;
		a.inverseProjection = v.inverseProjection;
		a.p = new Vec4(ao.radius, Math.max(1, ao.slices), Math.max(1, ao.samples), scale);
		a.size = new Vec4(rw, rh, v.width, v.height);
		a.more = new Vec4(v.width / Math.max(1, v.height), ao.intensity, 0, perspective ? 0 : p.c1.y * 0.5 * ao.radius);
		GtaoShader.params.a.write(a, aoBytes);
		enc.beginPass(rawPass);
		enc.setPipeline(gtao);
		enc.setUniforms(GtaoShader.uniforms[0].binding, aoBytes);
		enc.setTexture(GtaoShader.params.depth.binding, v.depth, fx.nearest);
		enc.setTexture(GtaoShader.params.normals.binding, v.normals, fx.nearest);
		enc.setVertexBuffer(0, fx.triangle);
		enc.draw(3);
		enc.endPass();
		blurBlock.p = new Vec4(1 / rw, 1 / rh, ao.intensity, 0);
		blurBlock.inverseProjection = v.inverseProjection;
		AoBlurShader.params.b.write(blurBlock, blurBytes);
		enc.beginPass(outPass);
		enc.setPipeline(blur);
		enc.setUniforms(AoBlurShader.uniforms[0].binding, blurBytes);
		enc.setTexture(AoBlurShader.params.occlusion.binding, raw, fx.nearest);
		enc.setTexture(AoBlurShader.params.depth.binding, v.depth, fx.nearest);
		enc.setVertexBuffer(0, fx.triangle);
		enc.draw(3);
		enc.endPass();
		return 2;
	}

	// (the targets for view buffers of width x height)
	function size(width:Int, height:Int, half:Bool) {
		var hw = half ? Std.int(Math.max(1, (width + 1) >> 1)) : width, hh = half ? Std.int(Math.max(1, (height + 1) >> 1)) : height;
		if (width == w && height == h && hw == rw && hh == rh) return;
		release();
		w = width;
		h = height;
		rw = hw;
		rh = hh;
		raw = device.createTexture({width: rw, height: rh, format: R8, renderTarget: true});
		var t = device.createTexture({width: w, height: h, format: R8, renderTarget: true});
		@:privateAccess ao.texture = t;
		rawPass.colors[0].texture = raw;
		outPass.colors[0].texture = t;
	}

	function release() {
		if (raw != null) device.destroyTexture(raw);
		var t = @:privateAccess ao.texture;
		if (t != null) device.destroyTexture(t);
		raw = null;
		@:privateAccess ao.texture = null;
		w = h = rw = rh = 0;
	}

	@:noCompletion public function dispose()
		if (device != null) release();
}
