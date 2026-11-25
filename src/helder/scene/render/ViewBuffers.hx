package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Mat4;
import helder.gfx.shader.Vec4;
import helder.scene.Node;
import helder.scene.StoreKind;
import helder.scene.math.MathTools;
import helder.scene.render.PbrPrepassShader;
import helder.scene.render.PbrPrepassInstancedShader;
import helder.scene.render.PbrShader;
import helder.scene.render.PbrShader.materialOf;
import helder.scene.render.PbrShader.materialInto;

// The view buffers: a single-sampled prepass of the frame's opaque draws
// that post's effects read (Bevy's DepthPrepass and NormalPrepass, as one
// pass of one colour target: gfx has no MRT), after the shadow maps and
// before the frame's pass:
//
//   depth     Depth32F, sampled (Nearest): the view's depth, 0 near, 1 far
//   normals   RGBA8: the view-space normal (octahedral, xy), roughness (z),
//             the selection group (w, times 255: Outline.select)
//
// Effects ask for them (post.ao, post.dof, post.outline call
// ViewBuffers.of(renderer) themselves); a program's own passes may too
// (renderer.use(ViewBuffers.of(renderer)), then reads them in an AfterPass
// hook). The main pass's depth is not theirs: it is multisampled, these
// are not. scale draws them at a share of the frame's size (0.5: a quarter
// of the pixels, what AO and depth of field tolerate; an outline wants
// them whole). The shaders are pbr's prepass variants (PbrPrepassShader):
// the position, normal, roughness and alpha slots alone, a material's own
// (MaterialShader: its prepass variants, made when it replaces one of
// those). Nothing is allocated per frame.
class ViewBuffers implements RenderFeature implements RenderFeature.ViewSource {

	public final device:Device;
	// the share of the frame's size they are drawn at (0: the effects'
	// choice, 1 with an outline, else 0.5; a program's own use: 1)
	public var scale = 0.0;
	// off: no prepass drawn, no groups taken (what the effects made, while none reads them)
	public var enabled = true;
	// whether their motion is drawn too (motion: a second pass, gfx having
	// one colour target a pass; TAA and motion blur by objects ask for it
	// themselves; a program's own: withVelocity()): what moved since the
	// frame before, by each node's matrix then and now and the camera's
	// (MotionPass; desktop and web)
	public var velocity(default, null) = false;
	// the last frame's motion (RGBA16F, their size: xy this pixel's point's
	// uv now less the frame before's, z 1 where a surface wrote it; null:
	// velocity off)
	public var motion(get, never):Null<Texture>;
	// the last prepass's targets and their size
	public var depth(default, null):Texture = cast 0;
	public var normals(default, null):Texture = cast 0;
	public var width(default, null) = 0;
	public var height(default, null) = 0;
	// the last prepass's draws
	public var draws(default, null) = 0;
	// the share of the frame's size they were last drawn at
	public var drawnScale(default, null) = 1.0;
	// the last prepass's camera: its projection, the projection's inverse
	// (a view-space point from a texel's depth), its view
	public var projection(default, null):Mat4 = Mat4.identity();
	public var inverseProjection(default, null):Mat4 = Mat4.identity();
	public var view(default, null):Mat4 = Mat4.identity();

	// (the effects' share, when scale is 0; whether one wants the motion)
	@:allow(helder.scene.render) var wanted = 1.0;
	@:allow(helder.scene.render) var wantedMotion = false;
	// (the motion's pass, made when first asked for: a program that never
	// asks links none of it)
	var motionPass:Null<RenderFeature.MotionSource> = null;
	@:allow(helder.scene.render) static var makeMotion:Null<ViewBuffers->RenderFeature.MotionSource> = null;

	// their motion drawn too (velocity, motion; a method, not a setter: a
	// program that never calls it links no motion pass), or no longer
	public function withVelocity(on = true):ViewBuffers {
		if (on) makeMotion = MotionPass.make;
		velocity = on;
		return this;
	}

	function get_motion():Null<Texture>
		return motionPass != null && (velocity || wantedMotion) ? motionPass.texture() : null;

	// the last frame's motion pass's draws (0 without)
	public var motionDraws(get, never):Int;

	function get_motionDraws():Int
		return motionPass != null && (velocity || wantedMotion) ? motionPass.drawn() : 0;

	final pipelines:Array<Pipeline> = [];
	final slots:Array<Array<Int>> = [];
	// (their block's slot in each: the plain, instanced, skinned)
	final prepassSlots:Array<Int> = [];
	final prepassBytes = Bytes.alloc(PbrPrepassShader.uniforms[0].size);
	final materialBytes = Bytes.alloc(PbrShader.uniforms[2].size);
	// (the blocks as written, kept: nothing allocated per draw)
	final materialBlock:PbrMaterial = materialOf(new Material());
	final prepassBlock:PbrPrepass = {view: Mat4.identity(), id: new Vec4(0, 0, 0, 0)};
	final pass:PassDesc = {colors: [{load: Clear, clear: new Vec4(0.5, 0.5, 1, 0)}], depth: {load: Clear}};
	final white:Texture;
	final sampler:Sampler;
	// (a material's own prepass variants: plain and instanced, by cull)
	final customs = new Map<MaterialShader, Array<Null<{pipeline:Pipeline, slots:Array<Int>, prepass:Int}>>>();
	var renderer:Null<Renderer> = null;

	public function new(device:Device) {
		this.device = device;
		var w = Bytes.alloc(4);
		w.fill(0, 4, 255);
		white = device.createTexture({width: 1, height: 1, data: w});
		sampler = device.createSampler({filter: Linear, mipFilter: Linear, wrap: Repeat});
		for (k in 0...4) {
			var instanced = k >= 2;
			var d = (instanced ? PbrPrepassInstancedShader : PbrPrepassShader).pipeline({cull: k % 2 == 0 ? Back : None, depthCompare: Less, depthWrite: true});
			if (instanced) d.layout = @:privateAccess Renderer.INSTANCED_LAYOUT;
			pipelines.push(made(d));
		}
		slots.push(Renderer.slotsOf(PbrPrepassShader.uniforms, PbrPrepassShader.textures));
		slots.push(Renderer.slotsOf(PbrPrepassInstancedShader.uniforms, PbrPrepassInstancedShader.textures));
		prepassSlots.push(block(PbrPrepassShader.uniforms));
		prepassSlots.push(block(PbrPrepassInstancedShader.uniforms));
	}

	// the renderer's view buffers: made and turned on when first asked
	public static function of(renderer:Renderer):ViewBuffers {
		var v = Std.downcast(@:privateAccess renderer.views, ViewBuffers);
		if (v != null) return v;
		var b = new ViewBuffers(renderer.device);
		renderer.use(b);
		return b;
	}

	@:noCompletion public function attach(renderer:Renderer) {
		this.renderer = renderer;
		@:privateAccess renderer.views = this;
	}

	@:noCompletion public function drawn():Int
		return draws;

	@:noCompletion public function group(node:Node):Int
		return enabled ? groupOf(node) : 0;

	// a node's selection group: its own (Outline.select), else the nearest
	// of its ancestors' (0: none; Selection's)
	public static inline function groupOf(node:Node):Int
		return Selection.groupOf(node);

	// (a pipeline into the targets: RGBA8 and Depth32F, one sample; Skinning's too)
	@:allow(helder.scene.render) function made(d:PipelineDesc):Pipeline {
		d.colorFormat = RGBA8;
		d.depthFormat = Depth32F;
		d.samples = 1;
		return device.createPipeline(d);
	}

	@:allow(helder.scene.render) static function block(uniforms:Array<helder.gfx.shader.Shader.UniformBlock>):Int {
		for (u in uniforms)
			if (u.name == "PbrPrepass") return u.binding;
		return -1;
	}

	// the targets for a frame of width x height (made again when that changes)
	function size(w:Int, h:Int) {
		if (w == width && h == height) return;
		release();
		width = w;
		height = h;
		depth = device.createTexture({width: w, height: h, format: Depth32F});
		normals = device.createTexture({width: w, height: h, renderTarget: true});
		pass.colors[0].texture = normals;
		pass.depth.texture = depth;
	}

	@:noCompletion public function render(enc:Encoder, renderer:Renderer, frame:Renderer.FrameInfo) {
		draws = 0;
		if (!enabled) return;
		var s = drawnScale = scale > 0 ? scale : wanted;
		size(Std.int(Math.max(1, Math.round(frame.width * s))), Std.int(Math.max(1, Math.round(frame.height * s))));
		projection = frame.projection;
		inverseProjection = MathTools.inverse(projection);
		view = frame.view;
		draws = 0;
		@:privateAccess {
			var r = renderer;
			enc.beginPass(pass);
			var group = -1, current:Null<Pipeline> = null, material:Null<Material> = null, node = Node.NONE;
			var sl = slots[0], ps = -1;
			// (the instanced sets: whole, their node's group)
			for (k in 0...r.setCount) {
				var set = r.sets[k];
				for (p in set.mesh.primitives) {
					var m = p.material;
					if (p.skinned || m.blend) continue;
					var own = m.shader != null && m.shader.prepassInstanced != null ? custom(m, 1) : null;
					enc.setPipeline(own != null ? own.pipeline : pipelines[2 + (m.doubleSided ? 1 : 0)]);
					sl = own != null ? own.slots : slots[1];
					ps = own != null ? own.prepass : prepassSlots[1];
					enc.setUniforms(sl[0], r.frameBytes);
					if (sl[18] >= 0) enc.setTexture(sl[18], r.lightTexture, r.nearest);
					writeGroup(enc, ps, 0);
					bindMaterial(enc, sl, m, own != null ? 6 : -1);
					enc.setVertexBuffer(0, p.vertices);
					enc.setVertexBuffer(1, set.buffer);
					enc.setIndexBuffer(p.indices, p.indexFormat);
					enc.drawIndexed(p.count, set.count);
					draws++;
				}
			}
			current = null;
			for (b in 0...r.batchCount) {
				var start = r.batchStart[b], n = r.batchSize[b];
				var d = r.list[start], p = d.primitive, m = p.material;
				// (the see-through draws, last in the list: none of the view's)
				if (m.blend) break;
				var many = n > 1, skin = p.skinned ? r.skinSource : null;
				if (p.skinned && skin == null) continue;
				var own = !p.skinned && m.shader != null && (many ? m.shader.prepassInstanced : m.shader.prepass) != null ? custom(m, many ? 1 : 0) : null;
				var want = own != null ? own.pipeline : skin != null ? skin.prepassPipeline(m.doubleSided) : pipelines[(many ? 2 : 0) + (m.doubleSided ? 1 : 0)];
				if (want != current) {
					enc.setPipeline(want);
					sl = own != null ? own.slots : skin != null ? skin.prepassSlots() : slots[many ? 1 : 0];
					ps = own != null ? own.prepass : skin != null ? block(skin.prepassUniforms()) : prepassSlots[many ? 1 : 0];
					enc.setUniforms(sl[0], r.frameBytes);
					if (sl[18] >= 0) enc.setTexture(sl[18], r.lightTexture, r.nearest);
					current = want;
					material = null;
					node = Node.NONE;
					group = -1;
				}
				if (d.group != group) {
					writeGroup(enc, ps, d.group);
					group = d.group;
				}
				if (!many && d.node != node) {
					var model = d.node.worldMatrix(), t = d.tint;
					r.writeObject(model, t, null, 0, skin != null ? skin.rows(d.node) : 1);
					enc.setUniforms(sl[1], r.objectBytes);
					node = d.node;
				}
				if (skin != null) skin.bind(enc, sl, d.node);
				if (m != material) {
					bindMaterial(enc, sl, m, own != null ? (many ? 6 : 5) : -1);
					material = m;
				}
				enc.setVertexBuffer(0, p.vertices);
				if (many) enc.setVertexBuffer(1, r.instanceBuffer, r.batchOffset[b]);
				enc.setIndexBuffer(p.indices, p.indexFormat);
				enc.drawIndexed(p.count, n);
				draws++;
			}
			enc.endPass();
		}
		if ((velocity || wantedMotion) && makeMotion != null) {
			if (motionPass == null) motionPass = makeMotion(this);
			motionPass.render(enc, renderer, frame);
			draws += motionPass.drawn();
		}
	}

	inline function writeGroup(enc:Encoder, slot:Int, group:Int) {
		prepassBlock.view = view;
		prepassBlock.id = new Vec4(group, 0, 0, 0);
		PbrPrepassShader.params.prepass.write(prepassBlock, prepassBytes);
		if (slot >= 0) enc.setUniforms(slot, prepassBytes);
	}

	// a material's block and the textures its slots read (alpha, roughness:
	// the base colour's and the metallic-roughness map), white the others
	// the variant keeps; own: its own blocks' variant (MaterialShader's
	// kinds: 5 plain, 6 instanced), -1 none
	function bindMaterial(enc:Encoder, sl:Array<Int>, m:Material, own:Int) {
		PbrShader.params.material.write(materialInto(m, materialBlock), materialBytes);
		enc.setUniforms(sl[2], materialBytes);
		var ms = m.sampler != null ? m.sampler : sampler;
		// (every texture slot the variant keeps, the material's or white: a
		// parameter not optional stays in every variant, read or not, and
		// WebGPU binds none left unset; not the skin's, 5 and 6, a physical
		// shader's flag, 14, nor the lights' block, 18, nor phase 5's blocks, 19 and 22)
		for (k in 3...Renderer.OWN) {
			if (sl[k] < 0 || k == 5 || k == 6 || k == 14 || k == 18 || k == 19 || k == 22) continue;
			var t = k == 3 ? m.baseColorTexture : k == 7 ? m.metallicRoughnessTexture : k == 8 ? m.emissiveTexture : k == 9 ? m.occlusionTexture : k == 10 ? m.normalTexture : null;
			enc.setTexture(sl[k], t != null ? t : white, ms);
		}
		if (own >= 0 && m.uniforms != null)
			for (i in 0...m.shader.blocks.length) {
				var bytes = m.uniforms.get(m.shader.blocks[i].name);
				if (bytes != null && sl[Renderer.OWN + i] >= 0) enc.setUniforms(sl[Renderer.OWN + i], bytes);
			}
	}


	// a material's own prepass variant (kind 0 plain, 1 instanced), made when first drawn
	function custom(m:Material, kind:Int):{pipeline:Pipeline, slots:Array<Int>, prepass:Int} {
		var s = m.shader;
		var list = customs.get(s);
		if (list == null) customs.set(s, list = []);
		var k = kind * 2 + (m.doubleSided ? 1 : 0);
		var c = list[k];
		if (c == null) {
			var v = kind == 0 ? s.prepass : s.prepassInstanced;
			var d = v.pipeline({cull: m.doubleSided ? None : Back, depthCompare: Less, depthWrite: true});
			if (kind == 1) d.layout = @:privateAccess Renderer.INSTANCED_LAYOUT;
			c = list[k] = {pipeline: made(d), slots: Renderer.slotsOf(v.uniforms, v.textures).concat([for (b in s.blocks) b.bindings[5 + kind]]), prepass: block(v.uniforms)};
		}
		return c;
	}

	function release() {
		if (width == 0) return;
		device.destroyTexture(depth);
		device.destroyTexture(normals);
		width = height = 0;
	}

	public function dispose() {
		release();
		if (motionPass != null) motionPass.dispose();
		motionPass = null;
		device.destroyTexture(white);
		if (renderer != null && @:privateAccess renderer.views == this) @:privateAccess renderer.views = null;
	}
}
