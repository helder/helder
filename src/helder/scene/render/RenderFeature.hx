package helder.scene.render;

// An optional part of the renderer, turned on by the program
// (renderer.use(new Shadows(device))): the renderer core reaches it only
// through the interfaces it fills (ShadowSource, SkinSource, NormalSource,
// ViewSource; post's effects through PostEffects), so a program that never
// makes one links none of its code or shaders.
interface RenderFeature {
	function attach(renderer:Renderer):Void;
}

// what the renderer asks of the view buffers (ViewBuffers)
interface ViewSource {
	// the prepass: the frame's opaque draws (the renderer's draw list,
	// extracted) into the depth and normal targets, after the shadow maps
	// and before the frame's pass
	function render(enc:helder.gfx.Encoder, renderer:Renderer, frame:Renderer.FrameInfo):Void;
	// a node's selection group (Outline.select, on it or the nearest of its
	// ancestors; 0: none), taken into the draw list
	function group(node:helder.scene.Node):Int;
	// the last prepass's draws
	function drawn():Int;
}

// what a PostProcess asks of its effects beyond bloom and the grade
// (PostEffects.hx: the first effect made installs them, PostProcess.effects)
interface PostEffects {
	// before the frame's draw list: what the effects set need of the
	// renderer (the view buffers: ViewBuffers.of)
	function require(renderer:Renderer):Void;
	// after the prepass, before the frame's pass: the screen's ambient
	// occlusion (post.ao; null without), which the standard material reads
	function occlusion(enc:helder.gfx.Encoder, frame:Renderer.FrameInfo):Null<helder.gfx.Texture>;
	// before bloom (BeforeComposite: linear light), after the program's
	// stages there: the passes that make a new light of the scene's
	// (reflections, temporal antialiasing, motion blur; light the stages'),
	// returned, then those the composite reads (depth of field's blur, god
	// rays, SMAA's edges and weights)
	function beforeComposite(enc:helder.gfx.Encoder, light:helder.gfx.Texture):helder.gfx.Texture;
	// whether the composite mixes an effect in (dof, outline, lut, god rays, SMAA)
	function folded():Bool;
	// the composite's pipeline with the effects (aa: post.antialias's in
	// the composite, 0 none, 1 FXAA, 2 SMAA's blending) into a format
	// (null: the frame), and its effects bound
	function composite(aa:Int, format:Null<helder.gfx.TextureFormat>):helder.gfx.Pipeline;
	function bind(enc:helder.gfx.Encoder, aa:Int):Void;
	// its slots of the chain's own: the composite's block, the scene, the bloom
	function slots(aa:Int):Array<Int>;
	// the last frame's draws of their own passes (AO's, DOF's)
	function drawn():Int;
	function dispose():Void;
}

// what the renderer asks of occlusion culling (Occlusion)
interface OcclusionSource {
	// before the draw list: the results of the frames before read (what
	// hidden answers), the queries' pass set up
	// (viewProj: the frame's, eye: the camera's place)
	function prepare(renderer:Renderer, world:helder.scene.World, viewProj:helder.gfx.shader.Mat4, eye:helder.gfx.shader.Vec3):Void;
	// whether a node tested was hidden behind others when last answered
	function hidden(node:helder.scene.Node):Bool;
	// in the frame's pass, after its opaque surfaces: the tested nodes'
	// bounds drawn, each in its query
	function draw(enc:helder.gfx.Encoder, renderer:Renderer):Void;
}

// what the renderer asks of a shadow map (Shadows)
interface ShadowSource {
	// the map's pass, before the frame's
	// (skins: the renderer's skinning, for skinned casters; null without it)
	// (frame: the camera's view, for cascades fitted to it)
	function render(enc:helder.gfx.Encoder, world:helder.scene.World, toLight:helder.gfx.shader.Vec3, skins:Null<SkinSource>, frame:Renderer.FrameInfo):Void;
	// the last pass's map and how to read it (an object: hxmc passes struct
	// values through interface calls wrongly for now)
	function shadowFrame():ShadowFrame;
}

class ShadowFrame {
	public var map:helder.gfx.Texture = cast 0;
	public var viewProj:helder.gfx.shader.Mat4 = helder.gfx.shader.Mat4.identity();
	// x: strength, y: bias, z: a texel of the map
	public var params:helder.gfx.shader.Vec4 = new helder.gfx.shader.Vec4(0, 0, 0, 0);
	// the second cascade's (one cascade: the first's)
	public var mapFar:helder.gfx.Texture = cast 0;
	public var viewProjFar:helder.gfx.shader.Mat4 = helder.gfx.shader.Mat4.identity();
	public var paramsFar:helder.gfx.shader.Vec4 = new helder.gfx.shader.Vec4(0, 0, 0, 0);
	// the soft filter's (PbrFrame.shadowSoft; x 0: the 3x3 filter)
	public var soft:helder.gfx.shader.Vec4 = new helder.gfx.shader.Vec4(0, 0, 0, 0);
	// the last frame's draws into the maps, every cascade's
	public var draws = 0;

	public function new() {}
}

// what the renderer asks of skinning (Skinning)
interface SkinSource {
	// the node's skin brought up to date; false when it has none
	function prepare(node:helder.scene.Node):Bool;
	function pipeline(doubleSided:Bool):helder.gfx.Pipeline;
	// the skinned shader's slots, in Renderer.slotsOf's order
	function slots():Array<Int>;
	// the node's skin bound for a draw
	function bind(enc:helder.gfx.Encoder, slots:Array<Int>, node:helder.scene.Node):Void;
	// the shadow pass's skinned pipeline (made when first asked: only with
	// Shadows) and its slots (caster, skin, joints)
	function shadowPipeline():helder.gfx.Pipeline;
	function shadowSlots():Array<Int>;
	// the view buffers' skinned prepass (made when first asked: only with
	// ViewBuffers), its slots in Renderer.slotsOf's order, its blocks
	function prepassPipeline(doubleSided:Bool):helder.gfx.Pipeline;
	function prepassSlots():Array<Int>;
	function prepassUniforms():Array<helder.gfx.shader.Shader.UniformBlock>;
}

// what the renderer asks of normal mapping (NormalMaps)
interface NormalSource {
	function pipeline(doubleSided:Bool):helder.gfx.Pipeline;
	// the normal-mapped shader's slots, in Renderer.slotsOf's order
	function slots():Array<Int>;
	// its instanced runs' (PbrInstancedNormalShader: the vertices, the
	// tangents, the instances' matrices)
	function instancedPipeline(doubleSided:Bool):helder.gfx.Pipeline;
	function instancedSlots():Array<Int>;
	// the vertex buffers' layout (instanced: with the instances' third), for a material's own shader
	function layout(instanced:Bool):Array<helder.gfx.VertexBufferLayout>;
}
