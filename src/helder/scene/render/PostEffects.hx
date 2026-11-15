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
		dof: new Vec4(0, 0, 0, 0), dofFocus: new Vec4(0, 0, 0, 0), outline: new Vec4(0, 0, 0, 0), lut: new Vec4(0, 0, 0, 0), rays: new Vec4(0, 0, 0, 0),
		smaa: new Vec4(0, 0, 0, 0), inverseProjection: Mat4.identity()
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
	final pipelines:Array<Null<Pipeline>> = [for (_ in 0...12) null];
	final formats:Array<Null<TextureFormat>> = [for (_ in 0...12) null];
	final used:Array<Bool> = [for (_ in 0...12) false];
	// (each variant's slots: the effects' block, the view buffers' depth and
	// normals, the blur, the lut, the groups; the chain's: its block, the
	// scene, the bloom)
	final fxSlots:Array<Array<Int>> = [];
	final baseSlots:Array<Array<Int>> = [];

	function get_light():Null<Texture>
		return current;

	// (the light so far in beforeComposite: the scene's, then each light pass's)
	var current:Null<Texture> = null;
	// the renderer whose frame the chain finishes (its last require's; null: none yet)
	public var renderer(default, null):Null<Renderer> = null;
	// the frame it drew (its FrameInfo: the camera, the jitter, the motion's matrices)
	public var frame(get, never):Null<Renderer.FrameInfo>;

	function get_frame():Null<Renderer.FrameInfo>
		return renderer != null ? renderer.frame : null;

	// (made by the first effect set on a chain: PostProcess.effects)
	public static function install()
		if (PostProcess.effects == null) PostProcess.effects = p -> new PostFx(p);

	// the effects' passes, made from them (installed by PostProcess's
	// setters: an effect never set on a chain links none of its pass)
	@:noCompletion public static var makeAo:Null<Ssao->PostPass> = null;
	@:noCompletion public static var makeDof:Null<Dof->PostPass> = null;
	@:noCompletion public static var makeOutline:Null<Outline->PostPass> = null;
	@:noCompletion public static var makeSsr:Null<Ssr->LightPass> = null;
	@:noCompletion public static var makeMotionBlur:Null<MotionBlur->LightPass> = null;
	@:noCompletion public static var makeGodRays:Null<GodRays->PostPass> = null;
	// (temporal antialiasing's and SMAA's, installed by post.antialias's setter;
	// SMAA's composite variant's description and bindings with them)
	@:noCompletion public static var makeTaa:Null<PostProcess->LightPass> = null;
	@:noCompletion public static var makeSmaa:Null<PostProcess->PostPass> = null;
	@:noCompletion public static var smaaComposite:Null<Void->PipelineDesc> = null;
	@:noCompletion public static var smaaUniforms:Null<Array<helder.gfx.shader.Shader.UniformBlock>> = null;
	@:noCompletion public static var smaaTextures:Null<Array<helder.gfx.shader.Shader.TextureBinding>> = null;

	// (the passes of the effects set, made again when an effect is replaced)
	var aoPass:Null<PostPass> = null;
	var aoOf:Null<Ssao> = null;
	var dofPass:Null<PostPass> = null;
	var dofOf:Null<Dof> = null;
	var outlinePass:Null<PostPass> = null;
	var outlineOf:Null<Outline> = null;

	var ssrPass:Null<LightPass> = null;
	var ssrOf:Null<Ssr> = null;
	var blurPass:Null<LightPass> = null;
	var blurOf:Null<MotionBlur> = null;
	var raysPass:Null<PostPass> = null;
	var raysOf:Null<GodRays> = null;
	var taaPass:Null<LightPass> = null;
	var smaaPass:Null<PostPass> = null;
	var lightDraws = 0;

	function passOfSsr():Null<LightPass> {
		var e = post.ssr;
		if (e == null) return null;
		if (ssrOf != e) {
			if (ssrPass != null) ssrPass.dispose();
			ssrPass = makeSsr(e);
			ssrOf = e;
		}
		return ssrPass;
	}

	function passOfMotionBlur():Null<LightPass> {
		var e = post.motionBlur;
		if (e == null) return null;
		if (blurOf != e) {
			if (blurPass != null) blurPass.dispose();
			blurPass = makeMotionBlur(e);
			blurOf = e;
		}
		return blurPass;
	}

	function passOfGodRays():Null<PostPass> {
		var e = post.godRays;
		if (e == null) return null;
		if (raysOf != e) {
			if (raysPass != null) raysPass.dispose();
			raysPass = makeGodRays(e);
			raysOf = e;
		}
		return raysPass;
	}

	function passOfTaa():Null<LightPass> {
		if (post.antialias != Taa || makeTaa == null) return null;
		if (taaPass == null) taaPass = makeTaa(post);
		return taaPass;
	}

	function passOfSmaa():Null<PostPass> {
		if (post.antialias != Smaa || makeSmaa == null) return null;
		if (smaaPass == null) smaaPass = makeSmaa(post);
		return smaaPass;
	}

	function passOfAo():Null<PostPass> {
		var e = post.ao;
		if (e == null) return null;
		if (aoOf != e) {
			if (aoPass != null) aoPass.dispose();
			aoPass = makeAo(e);
			aoOf = e;
		}
		return aoPass;
	}

	function passOfDof():Null<PostPass> {
		var e = post.dof;
		if (e == null) return null;
		if (dofOf != e) {
			if (dofPass != null) dofPass.dispose();
			dofPass = makeDof(e);
			dofOf = e;
		}
		return dofPass;
	}

	function passOfOutline():Null<PostPass> {
		var e = post.outline;
		if (e == null) return null;
		if (outlineOf != e) {
			if (outlinePass != null) outlinePass.dispose();
			outlinePass = makeOutline(e);
			outlineOf = e;
		}
		return outlinePass;
	}

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
		baseSlots.push([]);
		fxSlots.push([]);
	}

	// (SMAA's composite variant's slots, once it is set)
	function smaaSlots() {
		if (baseSlots[2].length > 0 || smaaUniforms == null) return;
		var u = smaaUniforms;
		baseSlots[2] = PostProcess.slotsOf(u, smaaTextures);
		fxSlots[2] = [u[slot(u, "CompositeFx")].binding].concat(textures(smaaTextures));
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
		return [t("viewDepth"), t("viewNormals"), t("blur"), t("lut"), t("groups"), t("rays"), t("weights")];
	}

	// (an effect's, in its require: it reads the renderer's view buffers v,
	// ViewBuffers.of(renderer), at least at share of the frame's size)
	// (motion: it reads their motion too, ViewBuffers.velocity's)
	public function read(v:ViewBuffers, share:Float, motion = false) {
		if (views != v) {
			made = !hadViews;
			views = v;
		}
		if (share > wanted) wanted = share;
		if (motion) {
			wantedMotion = true;
			@:privateAccess ViewBuffers.makeMotion = MotionPass.make;
		}
	}

	var wantedMotion = false;

	public function require(renderer:Renderer) {
		this.renderer = renderer;
		aoDraws = dofDraws = lightDraws = 0;
		wanted = 0;
		wantedMotion = false;
		hadViews = views == null && @:privateAccess renderer.views != null;
		var a = passOfAo(), d = passOfDof(), o = passOfOutline(), l:Null<PostPass> = post.lut;
		if (a != null) a.require(this, renderer);
		if (d != null) d.require(this, renderer);
		if (o != null) o.require(this, renderer);
		if (l != null) l.require(this, renderer);
		var sr = passOfSsr(), t = passOfTaa(), mb = passOfMotionBlur(), g = passOfGodRays(), sm = passOfSmaa();
		if (sr != null) sr.require(this, renderer);
		if (t != null) t.require(this, renderer) else renderer.jitter = new helder.gfx.shader.Vec2(0, 0);
		if (mb != null) mb.require(this, renderer);
		if (g != null) g.require(this, renderer);
		if (sm != null) sm.require(this, renderer);
		var v = views;
		if (v != null) {
			v.wanted = wanted > 0 ? wanted : 0.5;
			v.wantedMotion = wantedMotion;
			// (made here and read by none now: no prepass drawn)
			if (made) v.enabled = wanted > 0;
		}
	}

	public function occlusion(enc:Encoder, frame:Renderer.FrameInfo):Null<Texture> {
		var a = passOfAo();
		if (a == null || !ready()) return null;
		aoDraws = a.draw(enc, this);
		return a.result();
	}

	public function beforeComposite(enc:Encoder, light:Texture):Texture {
		current = light;
		if (ready()) {
			// (the passes making a new light: reflections, the history's, motion blur)
			var sr = passOfSsr(), t = passOfTaa(), mb = passOfMotionBlur();
			if (sr != null) current = sr.run(enc, this, current);
			if (t != null) current = t.run(enc, this, current);
			if (mb != null) current = mb.run(enc, this, current);
			if (sr != null) lightDraws += sr.drawn();
			if (t != null) lightDraws += t.drawn();
			if (mb != null) lightDraws += mb.drawn();
			// (then what the composite reads of it)
			write();
			var d = passOfDof(), g = passOfGodRays();
			if (d != null) dofDraws = d.draw(enc, this);
			if (g != null) lightDraws += g.draw(enc, this);
		}
		// (SMAA's edges and weights, of the light the composite reads: no view buffers)
		var sm = passOfSmaa();
		if (sm != null) lightDraws += sm.draw(enc, this);
		var out = current;
		current = null;
		return out;
	}

	// whether the view buffers were drawn this frame (what AO, depth of field and the outline read)
	public inline function ready():Bool
		return views != null && views.enabled && views.width > 0;

	public function folded():Bool
		return post.lut != null || smaaPass != null && post.antialias == Smaa || ready() && (post.dof != null || post.outline != null || post.godRays != null);

	public function composite(aa:Int, format:Null<TextureFormat>):Pipeline {
		var base = aa * 4;
		for (k in base...base + 4)
			if (used[k] && formats[k] == format) return pipelines[k];
		for (k in base...base + 4)
			if (!used[k]) {
				var d = aa == 2 ? smaaComposite() : (aa == 1 ? CompositeFxFxaaShader : CompositeFxShader).pipeline({});
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
		b.rays = z;
		b.smaa = z;
		b.inverseProjection = views != null ? views.inverseProjection : Mat4.identity();
		var d = passOfDof(), o = passOfOutline(), l:Null<PostPass> = post.lut;
		var on = ready();
		if (d != null && on) d.write(this);
		if (o != null && on) o.write(this);
		if (l != null) l.write(this);
		var g = passOfGodRays(), sm = passOfSmaa();
		if (g != null && on) g.write(this);
		if (sm != null) sm.write(this);
		CompositeFxShader.params.fx.write(b, blockBytes);
	}

	public function bind(enc:Encoder, aa:Int) {
		write();
		if (aa == 2) smaaSlots();
		var sl = fxSlots[aa];
		enc.setUniforms(sl[0], blockBytes);
		var on = ready(), v = views;
		if (sl[1] >= 0) enc.setTexture(sl[1], on ? v.depth : white, nearest);
		if (sl[2] >= 0) enc.setTexture(sl[2], on ? v.normals : white, nearest);
		for (k in 3...8)
			if (sl[k] >= 0) enc.setTexture(sl[k], white, linear);
		var d = passOfDof(), o = passOfOutline(), l:Null<PostPass> = post.lut, g = passOfGodRays(), sm = passOfSmaa();
		if (d != null && on) d.bind(enc, this, sl);
		if (o != null && on) o.bind(enc, this, sl);
		if (l != null) l.bind(enc, this, sl);
		if (g != null && on) g.bind(enc, this, sl);
		if (sm != null) sm.bind(enc, this, sl);
	}

	public function slots(aa:Int):Array<Int> {
		if (aa == 2) smaaSlots();
		return baseSlots[aa];
	}

	public function drawn():Int
		return aoDraws + dofDraws + lightDraws;

	public function dispose() {
		for (k in 0...12)
			pipelines[k] = null;
		device.destroyTexture(white);
		var a = aoPass, d = dofPass, o = outlinePass, g = raysPass, sm = smaaPass;
		if (a != null) a.dispose();
		if (d != null) d.dispose();
		if (o != null) o.dispose();
		if (g != null) g.dispose();
		if (sm != null) sm.dispose();
		var sr = ssrPass, t = taaPass, mb = blurPass;
		if (sr != null) sr.dispose();
		if (t != null) t.dispose();
		if (mb != null) mb.dispose();
		aoPass = dofPass = outlinePass = raysPass = smaaPass = null;
		ssrPass = taaPass = blurPass = null;
		aoOf = null;
		dofOf = null;
		outlineOf = null;
		ssrOf = null;
		blurOf = null;
		raysOf = null;
	}
}

// what PostFx asks of an effect's pass that makes a new light of the
// scene's before the composite (SsrPass, TaaPass, MotionBlurPass), in this
// order: screen-space reflections, temporal antialiasing, motion blur
interface LightPass {
	function require(fx:PostFx, renderer:Renderer):Void;
	// its passes: the light so far in, the new one out (its own target's)
	function run(enc:Encoder, fx:PostFx, light:Texture):Texture;
	// the last run's draws
	function drawn():Int;
	function dispose():Void;
}

// what PostFx asks of an effect's pass (SsaoPass, DofPass, OutlinePass,
// GodRaysPass, SmaaPass; Lut, its own), reached through this alone: a
// program links a pass only when it sets its effect on a chain. Its slots
// in bind: the effects' block, then the view buffers' depth and normals,
// the blur, the LUT, the groups, the god rays, SMAA's weights (PostFx's textures)
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
