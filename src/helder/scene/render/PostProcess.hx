package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Vec2;
import helder.gfx.shader.Vec4;
import helder.scene.render.PostShader;
import helder.scene.render.CompositeFxaaShader;
import helder.scene.render.PostEffects;
import helder.scene.render.PostStage.PostPoint;

// The post-process chain of an HDR frame (Renderer.hdr: drawn in linear
// light into an RGBA16F target): its effects, physically based bloom, then
// the frame tone mapped, graded and finished into an 8-bit target, in an
// order fixed by what is right (AO in the lighting, depth of field in
// linear light, bloom, the curve, the grade, the LUT, FXAA in the
// composite's read of the scene):
//
//   var post = new PostProcess(device);
//   post.bloom = 0.05;                 // the share of the light spread (0: none)
//   post.toneMap = Aces;               // or AgX, Clamp
//   post.saturation = 1.1; post.vignette = 0.25; post.grain = 0.03;
//   post.ao = new Ssao({radius: 0.5, intensity: 1, samples: 8, halfRes: true});   // GTAO
//   post.dof = Dof.tiltShift({band: 0.2, falloff: 0.3, strength: 1});           // or Dof.focus({distance, aperture})
//   post.outline = new Outline({width: 2, color: new Vec4(1, 0.8, 0.2, 1)});     // Outline.select(node)
//   post.antialias = Fxaa;             // None (MSAA alone: the <Scene>'s antialias)
//   post.smaa = new Smaa();            // or SMAA's edges and weights, blended in the composite
//   post.taa = new Taa();              // or temporal: jittered, gathered with its history (desktop, web)
//   post.lut = Lut.fromImage(device, image);
//   post.ssr = new Ssr({maxDistance: 8});            // screen-space reflections (desktop, web)
//   post.motionBlur = new MotionBlur({strength: 0.5}); // the camera's, or by objects ({objects: true})
//   post.godRays = new GodRays({intensity: 0.6});      // the sky's light streaming past what is before it
//   renderer.post = post;              // a <Scene>'s box runs it (hdr={true})
//   // or by hand, after the renderer's drawInto into hdrColor:
//   post.run(enc, hdrColor, ldrColor, width, height, time);
//   post.add(FinishShader, finishBytes);  // a pass of its own after the grade (PostStage)
//   post.add(BlurShader, bytes, BeforeComposite);  // one in linear light
//
// The effects are null by default: one never set is never linked, its
// shaders and passes neither (an effect's class installs PostEffects:
// their passes and the composite with them folded in). AO, depth of field
// and the outline read the renderer's view buffers (ViewBuffers: a
// prepass of depth, normals and selection), which they ask the renderer
// for themselves, so the chain is the renderer's (renderer.post = post)
// for them to be drawn; AO is drawn before the frame's pass and darkens
// its indirect light (PbrShader's aoMap). The composite is one pass
// whatever the effects: a variant (compiled at build time) by FXAA and by
// whether an effect is folded in.
//
// Bloom has no threshold: everything spreads a little, what is bright
// (an engine, a laser, the sun: values far over 1) spreads visibly. The
// scene is filtered down a chain of RGBA16F targets each half the one
// above (levels, at most 6; the first half the frame's size, or a quarter
// with base 2: Jimenez's 13-tap filter, the first level in Karis' average)
// and back up it (a tent filter, each level added to the one above), as
// Call of Duty: Advanced Warfare and Unity's HDRP do; the composite mixes
// it in. The targets are the GPU's (as many as the levels, made at the
// first run and when the size, base or levels change, freed by dispose);
// a run records 2 * levels passes and allocates nothing. Without grain
// the dither is still: a frame drawn again is the same pixels. A program's
// own stages (add: a pixel art finish, a CRT, an outline) come after the
// composite, in order, each a pass reading the last one's image: the
// composite and all but the last stage into two RGBA8 targets of the
// run's size taken in turn, the last into the output; those added
// BeforeComposite before it, in linear light, into two RGBA16F ones.
class PostProcess {
	public final device:Device;
	// the light before the curve (1: as drawn)
	public var exposure = 1.0;
	// bloom's share of the frame (0 to 1: 0.04 is subtle, 0.15 dreamy; 0: no bloom passes)
	public var bloom = 0.04;
	// how far each level up spreads (its texels: 1 a tight halo, 2 wider)
	public var radius = 1.0;
	// the bloom chain's levels (1 to 6; fewer: a tighter, cheaper glow)
	public var levels = 6;
	// the first level's size: the frame's halved this many times (1 or 2;
	// 2: a quarter of the pixels to filter, the glow a little softer)
	public var base = 1;
	public var toneMap:ToneMap = Aces;
	// the grade, on the tone mapped colour: 1 as it is
	public var saturation = 1.0;
	public var contrast = 1.0;
	// added to the shadows (rgb, 0 to about 0.05) and the colour's gain (rgb)
	public var lift = new helder.gfx.shader.Vec3(0, 0, 0);
	public var gain = new helder.gfx.shader.Vec3(1, 1, 1);
	// how much darker the corners are (0 to 1)
	public var vignette = 0.0;
	// film grain's strength (0 to about 0.1); a dither below a step of 8 bits is always there
	public var grain = 0.0;
	// whether the frame's alpha is kept (the scene's coverage, where bloom
	// adds light its brightness: over a ui behind it, premultiplied); false: opaque
	public var transparent = true;
	// the screen's ambient occlusion (Ssao: GTAO; null none)
	public var ao(default, set):Null<Ssao> = null;
	// depth of field (Dof.focus, Dof.tiltShift; null none)
	public var dof(default, set):Null<Dof> = null;
	// the selection's outlines (Outline, Outline.select; null none)
	public var outline(default, set):Null<Outline> = null;
	// antialiasing after the frame's own (None, Fxaa: in the composite; its
	// variant linked only by a program that sets it); smaa and taa are
	// effects of their own, below
	public var antialias(default, set):Antialias = None;
	// SMAA (Smaa: edges and their blending weights in two passes, blended in
	// the composite, in place of antialias'; null none)
	public var smaa(default, set):Null<Smaa> = null;
	// temporal antialiasing (Taa: the frame jittered, gathered with its
	// history reprojected by the view buffers' motion; null none)
	public var taa(default, set):Null<Taa> = null;
	// screen-space reflections (Ssr; null none): before the other effects,
	// from the view buffers, mixed by each surface's Fresnel, roughness and metalness
	public var ssr(default, set):Null<Ssr> = null;
	// motion blur (MotionBlur; null none): the camera's from depth, or each
	// object's by the view buffers' motion
	public var motionBlur(default, set):Null<MotionBlur> = null;
	// god rays (GodRays; null none): the sky's light behind the scene blurred
	// towards the sun's place on the screen, added before the curve
	public var godRays(default, set):Null<GodRays> = null;
	// colour grading by a lookup table (Lut; null none), after the grade
	public var lut(default, set):Null<Lut> = null;
	// the last run's draws (each a full-screen pass: AO's, depth of field's,
	// bloom down and up, the composite, the stages; helder.gfx.FrameCounts.postDraws too)
	public var draws(default, null) = 0;
	// the run's context, for its stages (PostStage's prepare and bind): the
	// scene's light it was given (linear, RGBA16F, its alpha the scene's
	// coverage) and its size in pixels; null and 0 outside a run
	public var source(default, null):Null<Texture> = null;
	public var width(default, null) = 0;
	public var height(default, null) = 0;

	// (the effects beyond bloom and the grade: installed by the first
	// effect's class, made for a chain when one is set)
	@:noCompletion public static var effects:Null<PostProcess->RenderFeature.PostEffects> = null;

	static inline var MAX_LEVELS = 6;

	final down:Pipeline;
	final up:Pipeline;
	final triangle:Buffer;
	final linear:Sampler;
	final nearest:Sampler;
	// a program's own stages, after the composite (add) and before it
	final stages:Array<PostStage> = [];
	final early:Array<PostStage> = [];
	// (the targets between them, made for a size: RGBA8 after, RGBA16F before)
	final between:Array<Texture> = [];
	final betweenPasses:Array<PassDesc> = [];
	var betweenW = 0;
	var betweenH = 0;
	final linearTargets:Array<Texture> = [];
	final linearPasses:Array<PassDesc> = [];
	var linearW = 0;
	var linearH = 0;
	// (the plain composite's pipelines: by FXAA, into the output and between)
	final composites:Array<Null<Pipeline>> = [null, null, null, null];
	final output:TextureFormat;
	final frame:Bool;
	final black:Texture;
	final bloomBytes = Bytes.alloc(BloomDownShader.uniforms[0].size);
	final compositeBytes = Bytes.alloc(CompositeShader.uniforms[0].size);
	// (the blocks as written, kept: a struct literal per write would allocate)
	final bloomBlock:BloomParams = {texel: new Vec4(0, 0, 0, 0)};
	final compositeBlock:CompositeParams = {
		exposure: new Vec4(0, 0, 0, 0), grade: new Vec4(0, 0, 0, 0), lift: new Vec4(0, 0, 0, 0), gain: new Vec4(0, 0, 0, 0), size: new Vec4(0, 0, 0, 0)
	};
	// (the chain's targets and their passes: made for a size)
	final chain:Array<Texture> = [];
	final widths:Array<Int> = [];
	final heights:Array<Int> = [];
	final clearPasses:Array<PassDesc> = [];
	final loadPasses:Array<PassDesc> = [];
	final outPass:PassDesc = {colors: [{load: Clear, clear: new Vec4(0, 0, 0, 0)}]};
	var chainW = 0;
	var chainH = 0;
	var chainBase = 0;
	var chainN = 0;
	final downSlots:Array<Int>;
	final upSlots:Array<Int>;
	// (each composite variant's: its block, the scene, the bloom; plain, FXAA)
	final compositeSlots:Array<Array<Int>>;
	// (the effects, made when the first is set; the light the composite reads)
	var fx:Null<RenderFeature.PostEffects> = null;
	var light:Null<Texture> = null;

	// output: the format of the targets run writes (RGBA8: a <Scene>'s
	// box's); frame: run writes the frame instead (output unused)
	public function new(device:Device, output:TextureFormat = RGBA8, frame = false) {
		this.device = device;
		this.output = output;
		this.frame = frame;
		var d = BloomDownShader.pipeline({});
		d.colorFormat = RGBA16F;
		down = device.createPipeline(d);
		var u = BloomUpShader.pipeline({blend: Additive});
		u.colorFormat = RGBA16F;
		up = device.createPipeline(u);
		var v = BloomDownShader.vertexBytes([{pos: new Vec2(-1, -1)}, {pos: new Vec2(3, -1)}, {pos: new Vec2(-1, 3)}]);
		triangle = device.createBuffer({size: v.length, usage: Vertex, data: v});
		linear = device.createSampler({filter: Linear, wrap: Clamp});
		nearest = device.createSampler({filter: Nearest, wrap: Clamp});
		var b = Bytes.alloc(8);
		black = device.createTexture({width: 1, height: 1, format: RGBA16F, data: b});
		downSlots = [BloomDownShader.uniforms[0].binding, BloomDownShader.textures[0].binding];
		upSlots = [BloomUpShader.uniforms[0].binding, BloomUpShader.textures[0].binding];
		compositeSlots = [slotsOf(CompositeShader.uniforms, CompositeShader.textures), []];
	}

	// (FXAA's composite: its pipeline's description and slots, here once set)
	var fxaaDesc:Null<Void->PipelineDesc> = null;

	// (an effect set: the effects' composite installed, PostFx, and the
	// effect's pass's factory; here, not in the effects' constructors, so
	// that an effect made and never set on a chain links none of its GPU
	// code, the device's neither)
	function set_ao(v:Null<Ssao>):Null<Ssao> {
		if (v != null) {
			PostFx.install();
			PostFx.makeAo = SsaoPass.make;
		}
		return ao = v;
	}

	function set_dof(v:Null<Dof>):Null<Dof> {
		if (v != null) {
			PostFx.install();
			PostFx.makeDof = DofPass.make;
		}
		return dof = v;
	}

	function set_outline(v:Null<Outline>):Null<Outline> {
		if (v != null) {
			PostFx.install();
			PostFx.makeOutline = OutlinePass.make;
		}
		return outline = v;
	}

	function set_lut(v:Null<Lut>):Null<Lut> {
		if (v != null) PostFx.install();
		return lut = v;
	}

	function set_ssr(v:Null<Ssr>):Null<Ssr> {
		if (v != null) {
			PostFx.install();
			PostFx.makeSsr = SsrPass.make;
		}
		return ssr = v;
	}

	function set_motionBlur(v:Null<MotionBlur>):Null<MotionBlur> {
		if (v != null) {
			PostFx.install();
			PostFx.makeMotionBlur = MotionBlurPass.make;
			// (by objects: the view buffers' motion; a MotionBlur whose objects are turned on later too)
			@:privateAccess ViewBuffers.makeMotion = MotionPass.make;
		}
		return motionBlur = v;
	}

	function set_godRays(v:Null<GodRays>):Null<GodRays> {
		if (v != null) {
			PostFx.install();
			PostFx.makeGodRays = GodRaysPass.make;
		}
		return godRays = v;
	}

	function set_antialias(v:Antialias):Antialias {
		if (v == Fxaa && fxaaDesc == null) {
			fxaaDesc = () -> CompositeFxaaShader.pipeline({});
			compositeSlots[1] = slotsOf(CompositeFxaaShader.uniforms, CompositeFxaaShader.textures);
		}
		return antialias = v;
	}

	function set_smaa(v:Null<Smaa>):Null<Smaa> {
		if (v != null) {
			PostFx.install();
			SmaaPass.install();
		}
		return smaa = v;
	}

	function set_taa(v:Null<Taa>):Null<Taa> {
		if (v != null) {
			PostFx.install();
			PostFx.makeTaa = TaaPass.make;
			@:privateAccess ViewBuffers.makeMotion = MotionPass.make;
		}
		return taa = v;
	}

	// a composite variant's slots: its block (CompositeParams), the scene, the bloom
	@:allow(helder.scene.render) static function slotsOf(uniforms:Array<helder.gfx.shader.Shader.UniformBlock>,
			textures:Array<helder.gfx.shader.Shader.TextureBinding>):Array<Int> {
		var s = [-1, -1, -1];
		for (u in uniforms)
			if (u.name == "CompositeParams") s[0] = u.binding;
		for (t in textures)
			if (t.name == "scene") s[1] = t.binding else if (t.name == "bloom") s[2] = t.binding;
		return s;
	}

	// (the effects', made when an effect is set: null without)
	inline function effectsOf():Null<RenderFeature.PostEffects> {
		if (fx == null && effects != null && (ao != null || dof != null || outline != null || lut != null || ssr != null || motionBlur != null || godRays != null || smaa != null || taa != null)) fx = effects(this);
		return fx;
	}

	// (the renderer's frame, before its draw list: the effects' needs)
	@:allow(helder.scene.render.Renderer) function require(renderer:Renderer) {
		var e = effectsOf();
		if (e != null) e.require(renderer);
	}

	// (the renderer's frame, after the prepass: the screen's ambient occlusion)
	@:allow(helder.scene.render.Renderer) function occlusion(enc:Encoder, frame:Renderer.FrameInfo):Null<Texture> {
		var e = fx;
		return e != null && ao != null ? e.occlusion(enc, frame) : null;
	}

	// the chain for a frame of width by height (its targets made again when that changes)
	function size(width:Int, height:Int, b:Int, n:Int) {
		if (width == chainW && height == chainH && b == chainBase && n <= chainN) return;
		release();
		chainW = width;
		chainH = height;
		chainBase = b;
		chainN = n;
		var w = Std.int(Math.max(1, width >> (b - 1))), h = Std.int(Math.max(1, height >> (b - 1)));
		for (k in 0...n) {
			w = Std.int(Math.max(1, w >> 1));
			h = Std.int(Math.max(1, h >> 1));
			var t = device.createTexture({width: w, height: h, format: RGBA16F, renderTarget: true});
			chain.push(t);
			widths.push(w);
			heights.push(h);
			clearPasses.push({colors: [{load: Clear, clear: new Vec4(0, 0, 0, 0), texture: t}]});
			loadPasses.push({colors: [{load: Load, texture: t}]});
			if (w == 1 && h == 1) break;
		}
	}

	// a stage of the program's own (PostStage: its shader's first texture
	// the image so far, its first block bytes): after those before it at its
	// point (AfterComposite: tone mapped; BeforeComposite: in linear light)
	public function add<V, P>(shader:helder.gfx.shader.Shader<V, P>, ?bytes:Bytes, point:PostPoint = AfterComposite):PostStage {
		var s = new PostStage(shader, bytes, point);
		(point == BeforeComposite ? early : stages).push(s);
		return s;
	}

	// a cut: the history temporal antialiasing gathers let go (a camera
	// jumped, a scene changed), the next frame alone
	public function resetHistory()
		cuts++;

	var cuts = 0;

	public function remove(stage:PostStage) {
		stages.remove(stage);
		early.remove(stage);
	}

	// the frame: source (the scene's RGBA16F, width by height) into target
	// (the output format's render target of that size, or with stages any
	// size; null: the frame, a PostProcess made for it); time: seconds, the
	// grain's
	public function run(enc:Encoder, source:Texture, target:Null<Texture>, width:Int, height:Int, time = 0.0) {
		draws = 0;
		this.source = source;
		this.width = width;
		this.height = height;
		for (s in early)
			if (s.prepare != null) s.prepare(enc);
		for (s in stages)
			if (s.prepare != null) s.prepare(enc);
		// (the stages in linear light: each from the last, into RGBA16F targets)
		light = source;
		var from = 0;
		for (s in early) {
			if (!s.enabled) continue;
			linearTargetsFor(width, height);
			enc.beginPass(linearPasses[from]);
			if (s.middle == null) {
				s.desc.colorFormat = RGBA16F;
				s.middle = device.createPipeline(s.desc);
			}
			enc.setPipeline(s.middle);
			if (s.block >= 0 && s.bytes != null) enc.setUniforms(s.block, s.bytes);
			enc.setTexture(s.source, light, s.filter == Nearest ? nearest : linear);
			if (s.bind != null) s.bind(enc);
			enc.setVertexBuffer(0, triangle);
			enc.draw(3);
			draws++;
			enc.endPass();
			light = linearTargets[from];
			from = 1 - from;
		}
		var e = effectsOf();
		if (e != null) light = e.beforeComposite(enc, light);
		var n = bloom > 0 ? Std.int(Math.max(1, Math.min(levels, MAX_LEVELS))) : 0;
		var b = base >= 2 ? 2 : 1;
		if (n > 0) size(width, height, b, n);
		if (n > chain.length) n = chain.length;
		// (down the chain: each level from the one above, the first from the scene)
		for (k in 0...n) {
			var from = k == 0 ? light : chain[k - 1];
			var fw = k == 0 ? width : widths[k - 1], fh = k == 0 ? height : heights[k - 1];
			enc.beginPass(clearPasses[k]);
			enc.setPipeline(down);
			// (a quarter's first level: the 13 taps twice as far apart, over its 4 x 4 texels)
			var spread = k == 0 ? b : 1;
			bloomParams(spread / fw, spread / fh, 0, k == 0 ? 1 : 0);
			enc.setUniforms(downSlots[0], bloomBytes);
			enc.setTexture(downSlots[1], from, linear);
			enc.setVertexBuffer(0, triangle);
			enc.draw(3);
			draws++;
			enc.endPass();
		}
		// (back up: each level's tent filtered into the one above, added)
		var k = n - 1;
		while (k > 0) {
			enc.beginPass(loadPasses[k - 1]);
			enc.setPipeline(up);
			bloomParams(1 / widths[k], 1 / heights[k], radius, 0);
			enc.setUniforms(upSlots[0], bloomBytes);
			enc.setTexture(upSlots[1], chain[k], linear);
			enc.setVertexBuffer(0, triangle);
			enc.draw(3);
			draws++;
			enc.endPass();
			k--;
		}
		var count = 0;
		for (s in stages)
			if (s.enabled) count++;
		if (count > 0) targets(width, height);
		var into = count > 0 ? betweenPasses[0] : outPass;
		outPass.colors[0].texture = target;
		enc.beginPass(into);
		var fxaa = antialias == Fxaa;
		var aa = smaa != null ? 2 : fxaa ? 1 : 0;
		var format:Null<TextureFormat> = count > 0 ? RGBA8 : frame ? null : output;
		var folded = e != null && e.folded();
		var slots = compositeSlots[fxaa ? 1 : 0];
		if (folded) {
			enc.setPipeline(e.composite(aa, format));
			slots = e.slots(aa);
		} else
			enc.setPipeline(plain(fxaa, count > 0));
		// (the first level holds the n levels' light added: lift.w, 1 / n, scales it back)
		var c = compositeBlock;
		c.exposure = new Vec4(exposure, n > 0 ? Math.min(1, bloom) : 0, (cast toneMap : Int), grain > 0 ? time % 1000 : 0);
		c.grade = new Vec4(saturation, contrast, vignette, grain);
		c.lift = new Vec4(lift.x, lift.y, lift.z, n > 0 ? 1 / n : 0);
		c.gain = new Vec4(gain.x, gain.y, gain.z, 0);
		c.size = new Vec4(width, height, width / Math.max(1, height), transparent ? 1 : 0);
		CompositeShader.params.p.write(c, compositeBytes);
		enc.setUniforms(slots[0], compositeBytes);
		enc.setTexture(slots[1], light, linear);
		enc.setTexture(slots[2], n > 0 ? chain[0] : black, linear);
		if (folded) e.bind(enc, aa);
		enc.setVertexBuffer(0, triangle);
		enc.draw(3);
		draws++;
		enc.endPass();
		// (the stages: each from the last target into the next, the last into the output)
		var from = 0;
		for (s in stages) {
			if (!s.enabled) continue;
			var last = --count == 0;
			if (last) enc.beginPass(outPass) else enc.beginPass(betweenPasses[1 - from]);
			enc.setPipeline(last ? stageLast(s) : stageBetween(s));
			if (s.block >= 0 && s.bytes != null) enc.setUniforms(s.block, s.bytes);
			enc.setTexture(s.source, between[from], s.filter == Nearest ? nearest : linear);
			if (s.bind != null) s.bind(enc);
			enc.setVertexBuffer(0, triangle);
			enc.draw(3);
			draws++;
			enc.endPass();
			from = 1 - from;
		}
		outPass.colors[0].texture = null;
		if (e != null) draws += e.drawn();
		helder.gfx.FrameCounts.postDraws += draws;
		this.source = null;
		light = null;
		this.width = this.height = 0;
	}

	// (the plain composite: with FXAA or not, into the output or between)
	function plain(fxaa:Bool, middle:Bool):Pipeline {
		var k = (fxaa ? 2 : 0) + (middle ? 1 : 0);
		var p = composites[k];
		if (p == null) {
			var c = fxaa ? fxaaDesc() : CompositeShader.pipeline({});
			c.colorFormat = middle ? RGBA8 : frame ? null : output;
			p = composites[k] = device.createPipeline(c);
		}
		return p;
	}

	function stageBetween(s:PostStage):Pipeline {
		if (s.middle == null) {
			s.desc.colorFormat = RGBA8;
			s.middle = device.createPipeline(s.desc);
		}
		return s.middle;
	}

	function stageLast(s:PostStage):Pipeline {
		if (s.last == null) {
			s.desc.colorFormat = frame ? null : output;
			s.last = device.createPipeline(s.desc);
		}
		return s.last;
	}

	// the two targets between the composite and the stages, of the run's size
	function targets(width:Int, height:Int) {
		if (width == betweenW && height == betweenH) return;
		releaseBetween();
		betweenW = width;
		betweenH = height;
		for (_ in 0...2) {
			var t = device.createTexture({width: width, height: height, renderTarget: true});
			between.push(t);
			betweenPasses.push({colors: [{load: Clear, clear: new Vec4(0, 0, 0, 0), texture: t}]});
		}
	}

	// the two RGBA16F targets of the stages before the composite
	function linearTargetsFor(width:Int, height:Int) {
		if (width == linearW && height == linearH) return;
		releaseLinear();
		linearW = width;
		linearH = height;
		for (_ in 0...2) {
			var t = device.createTexture({width: width, height: height, format: RGBA16F, renderTarget: true});
			linearTargets.push(t);
			linearPasses.push({colors: [{load: Clear, clear: new Vec4(0, 0, 0, 0), texture: t}]});
		}
	}

	function releaseBetween() {
		for (t in between)
			device.destroyTexture(t);
		between.resize(0);
		betweenPasses.resize(0);
		betweenW = betweenH = 0;
	}

	function releaseLinear() {
		for (t in linearTargets)
			device.destroyTexture(t);
		linearTargets.resize(0);
		linearPasses.resize(0);
		linearW = linearH = 0;
	}

	inline function bloomParams(tx:Float, ty:Float, r:Float, first:Float) {
		bloomBlock.texel = new Vec4(tx, ty, r, first);
		BloomDownShader.params.p.write(bloomBlock, bloomBytes);
	}

	function release() {
		for (t in chain)
			device.destroyTexture(t);
		chain.resize(0);
		widths.resize(0);
		heights.resize(0);
		clearPasses.resize(0);
		loadPasses.resize(0);
		chainW = chainH = chainBase = chainN = 0;
	}

	public function dispose() {
		release();
		releaseBetween();
		releaseLinear();
		if (fx != null) fx.dispose();
		fx = null;
		device.destroyBuffer(triangle);
		device.destroyTexture(black);
	}
}

// the curve from linear light to the display
enum abstract ToneMap(Int) to Int {
	// Sobotka's AgX: hues kept, highlights to white
	var AgX;
	// ACES filmic, Narkowicz's fit: the 8-bit path's (aces), so a
	// scene tuned there keeps its look
	var Aces;
	// none: clipped at 1
	var Clamp;
}

// antialiasing in post (PostProcess.antialias), beside a <Scene>'s MSAA:
// None, or Fxaa (in the composite: its read of the scene along the edges);
// SMAA and TAA are effects of their own (post.smaa, post.taa: an enum's
// value set at run time would link every technique's passes)
enum abstract Antialias(Int) {
	var None;
	var Fxaa;
}
