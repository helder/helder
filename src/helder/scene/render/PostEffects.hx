package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Mat4;
import helder.gfx.shader.Vec4;
import helder.scene.render.EffectShaders;
import helder.scene.render.CompositeFxShader;
import helder.scene.render.PostShader;

// What a PostProcess's effects beyond bloom and the grade share (post.ao,
// post.dof, post.outline, post.lut): the composite with them folded in
// (CompositeFxShader, with FXAA CompositeFxFxaaShader: their block and
// textures bound), and the renderer's view buffers those that read them
// asked for (ViewBuffers.of, before the frame's draw list). Each effect is
// reached through PostPass alone, and asks for the view buffers itself:
// a program links an effect's class, passes and shaders, and the view
// buffers, only when it makes one that needs them. The first effect made
// installs this (PostProcess.effects): a program that makes none links
// none of it.
class PostFx implements RenderFeature.PostEffects {
	public final post:PostProcess;
	public final device:Device;
	// the view buffers the effects read (null: none asked for them, or the
	// chain is run without its renderer having drawn: renderer.post)
	public var views(default, null):Null<ViewBuffers> = null;
	// the light the chain's composite reads (its BeforeComposite stages'
	// result, else the scene's): depth of field's source
	public var light(get, never):Null<Texture>;
	// the triangle over the target, the samplers: the chain's
	public final triangle:Buffer;
	public final linear:Sampler;
	public final nearest:Sampler;
	// the effects' block (CompositeFx: each effect writes its part)
	public final block:CompositeFx = {
		dof: new Vec4(0, 0, 0, 0), dofFocus: new Vec4(0, 0, 0, 0), outline: new Vec4(0, 0, 0, 0), lut: new Vec4(0, 0, 0, 0), inverseProjection: Mat4.identity()
	};
	public final blockBytes = Bytes.alloc(CompositeFxShader.uniforms[slot(CompositeFxShader.uniforms, "CompositeFx")].size);
	// a white texel (a texture slot no effect fills)
	public final white:Texture;

	// (the view buffers made for the effects: on while one reads them; the share wanted)
	var made = false;
	var hadViews = false;
	var wanted = 0.0;
	var aoDraws = 0;
	var dofDraws = 0;
	// (the composite's pipelines with the effects: by fxaa, then by format)
	final pipelines:Array<Null<Pipeline>> = [for (_ in 0...8) null];
	final formats:Array<Null<TextureFormat>> = [for (_ in 0...8) null];
	final used:Array<Bool> = [for (_ in 0...8) false];
	// (each variant's slots: the effects' block, the view buffers' depth and
	// normals, the blur, the lut, the groups; the chain's: its block, the
	// scene, the bloom)
	final fxSlots:Array<Array<Int>> = [];
	final baseSlots:Array<Array<Int>> = [];

	function get_light():Null<Texture>
		return @:privateAccess post.light;

	// (made by the first effect: PostProcess.effects)
	public static function install()
		if (PostProcess.effects == null) PostProcess.effects = p -> new PostFx(p);

	function new(post:PostProcess) {
		this.post = post;
		device = post.device;
		triangle = @:privateAccess post.triangle;
		linear = @:privateAccess post.linear;
		nearest = @:privateAccess post.nearest;
		var w = Bytes.alloc(4);
		w.fill(0, 4, 255);
		white = device.createTexture({width: 1, height: 1, data: w});
		baseSlots.push(PostProcess.slotsOf(CompositeFxShader.uniforms, CompositeFxShader.textures));
		baseSlots.push(PostProcess.slotsOf(CompositeFxFxaaShader.uniforms, CompositeFxFxaaShader.textures));
		var u0 = CompositeFxShader.uniforms, u1 = CompositeFxFxaaShader.uniforms;
		fxSlots.push([u0[slot(u0, "CompositeFx")].binding].concat(textures(CompositeFxShader.textures)));
		fxSlots.push([u1[slot(u1, "CompositeFx")].binding].concat(textures(CompositeFxFxaaShader.textures)));
	}

	static function slot(uniforms:Array<helder.gfx.shader.Shader.UniformBlock>, name:String):Int {
		for (k in 0...uniforms.length)
			if (uniforms[k].name == name) return k;
		return 0;
	}

	// (a variant's effects' textures: the view buffers' depth, normals, the blur, the LUT, the groups)
	static function textures(list:Array<helder.gfx.shader.Shader.TextureBinding>):Array<Int> {
		function t(name:String):Int {
			for (b in list)
				if (b.name == name) return b.binding;
			return -1;
		}
		return [t("viewDepth"), t("viewNormals"), t("blur"), t("lut"), t("groups")];
	}

	// (an effect's, in its require: it reads the renderer's view buffers v,
	// ViewBuffers.of(renderer), at least at share of the frame's size)
	public function read(v:ViewBuffers, share:Float) {
		if (views != v) {
			made = !hadViews;
			views = v;
		}
		if (share > wanted) wanted = share;
	}

	public function require(renderer:Renderer) {
		aoDraws = dofDraws = 0;
		wanted = 0;
		hadViews = views == null && @:privateAccess renderer.views != null;
		var a:Null<PostPass> = post.ao, d:Null<PostPass> = post.dof, o:Null<PostPass> = post.outline, l:Null<PostPass> = post.lut;
		if (a != null) a.require(this, renderer);
		if (d != null) d.require(this, renderer);
		if (o != null) o.require(this, renderer);
		if (l != null) l.require(this, renderer);
		var v = views;
		if (v != null) {
			v.wanted = wanted > 0 ? wanted : 0.5;
			// (made here and read by none now: no prepass drawn)
			if (made) v.enabled = wanted > 0;
		}
	}

	public function occlusion(enc:Encoder, frame:Renderer.FrameInfo):Null<Texture> {
		var a:Null<PostPass> = post.ao;
		if (a == null || !ready()) return null;
		aoDraws = a.draw(enc, this);
		return a.result();
	}

	public function beforeComposite(enc:Encoder) {
		var d:Null<PostPass> = post.dof;
		if (d == null || !ready()) return;
		write();
		dofDraws = d.draw(enc, this);
	}

	// whether the view buffers were drawn this frame (what AO, depth of field and the outline read)
	public inline function ready():Bool
		return views != null && views.enabled && views.width > 0;

	public function folded():Bool
		return post.lut != null || ready() && (post.dof != null || post.outline != null);

	public function composite(fxaa:Bool, format:Null<TextureFormat>):Pipeline {
		var base = fxaa ? 4 : 0;
		for (k in base...base + 4)
			if (used[k] && formats[k] == format) return pipelines[k];
		for (k in base...base + 4)
			if (!used[k]) {
				var d = (fxaa ? CompositeFxFxaaShader : CompositeFxShader).pipeline({});
				d.colorFormat = format;
				pipelines[k] = device.createPipeline(d);
				formats[k] = format;
				used[k] = true;
				return pipelines[k];
			}
		throw "helder.scene: PostProcess: too many composite formats";
	}

	// the effects' block: each effect's part (zeros: off)
	function write() {
		var b = block, z = new Vec4(0, 0, 0, 0);
		b.dof = z;
		b.dofFocus = z;
		b.outline = z;
		b.lut = z;
		b.inverseProjection = views != null ? views.inverseProjection : Mat4.identity();
		var d:Null<PostPass> = post.dof, o:Null<PostPass> = post.outline, l:Null<PostPass> = post.lut;
		var on = ready();
		if (d != null && on) d.write(this);
		if (o != null && on) o.write(this);
		if (l != null) l.write(this);
		CompositeFxShader.params.fx.write(b, blockBytes);
	}

	public function bind(enc:Encoder, fxaa:Bool) {
		write();
		var sl = fxSlots[fxaa ? 1 : 0];
		enc.setUniforms(sl[0], blockBytes);
		var on = ready(), v = views;
		if (sl[1] >= 0) enc.setTexture(sl[1], on ? v.depth : white, nearest);
		if (sl[2] >= 0) enc.setTexture(sl[2], on ? v.normals : white, nearest);
		for (k in 3...6)
			if (sl[k] >= 0) enc.setTexture(sl[k], white, linear);
		var d:Null<PostPass> = post.dof, o:Null<PostPass> = post.outline, l:Null<PostPass> = post.lut;
		if (d != null && on) d.bind(enc, this, sl);
		if (o != null && on) o.bind(enc, this, sl);
		if (l != null) l.bind(enc, this, sl);
	}

	public function slots(fxaa:Bool):Array<Int>
		return baseSlots[fxaa ? 1 : 0];

	public function drawn():Int
		return aoDraws + dofDraws;

	public function dispose() {
		for (k in 0...8)
			pipelines[k] = null;
		device.destroyTexture(white);
		var a:Null<PostPass> = post.ao, d:Null<PostPass> = post.dof;
		if (a != null) a.dispose();
		if (d != null) d.dispose();
	}
}

// what PostFx asks of an effect (Ssao, Dof, Outline, Lut), reached through
// this alone: a program links an effect only when it makes one. Its slots
// in bind: the effects' block, then the view buffers' depth and normals,
// the blur, the LUT, the groups (PostFx's textures)
interface PostPass {
	// what it needs of the renderer before the frame's draw list: the view
	// buffers (fx.read(ViewBuffers.of(renderer), share))
	function require(fx:PostFx, renderer:Renderer):Void;
	// its passes for the frame (AO's before the frame's pass, depth of
	// field's before bloom); the draws recorded
	function draw(enc:Encoder, fx:PostFx):Int;
	// its result the frame's pass reads (AO's occlusion; null the others')
	function result():Null<Texture>;
	// its part of the composite's block (fx.block) and its textures
	function write(fx:PostFx):Void;
	function bind(enc:Encoder, fx:PostFx, slots:Array<Int>):Void;
	function dispose():Void;
}
