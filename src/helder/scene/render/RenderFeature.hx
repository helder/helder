package helder.scene.render;

// An optional part of the renderer, turned on by the program
// (renderer.use(new Shadows(device))): the renderer core reaches it only
// through the interfaces it fills (ShadowSource, SkinSource, NormalSource,
// ViewSource; post's effects through PostEffects), so a program that never
// makes one links none of its code or shaders.
interface RenderFeature {
	function attach(renderer:Renderer):Void;
}

// what the renderer asks of light and reflection probes (Probes): the
// standard material's variants with them, each draw's probes (by its
// centre), the atlas where the environment is bound, its frame vector
interface ProbeSource {
	function pipeline(instanced:Bool, doubleSided:Bool):helder.gfx.Pipeline;
	function slots(instanced:Bool):Array<Int>;
	// (a draw's bounds in the world: its centre, its half size)
	function bind(enc:helder.gfx.Encoder, cx:Float, cy:Float, cz:Float, ex:Float, ey:Float, ez:Float):Void;
	function bindAtlas(enc:helder.gfx.Encoder, slot:Int, sampler:helder.gfx.Sampler):Void;
	function environmentVector():helder.gfx.shader.Vec4;
}

// what the renderer asks of area lights (AreaLights): the standard
// material's variants with them (with probes or not), the tables bound
interface AreaSource {
	function pipeline(instanced:Bool, doubleSided:Bool, probes:Bool):helder.gfx.Pipeline;
	function slots(instanced:Bool, probes:Bool):Array<Int>;
	function bind(enc:helder.gfx.Encoder, instanced:Bool, probes:Bool):Void;
}

// what the renderer asks of lightmaps (Lightmaps): whether a node has one,
// the standard material's lightmap variant, a node's block and texture bound
interface LightmapSource {
	function has(node:helder.scene.Node):Bool;
	function pipeline(doubleSided:Bool):helder.gfx.Pipeline;
	function slots():Array<Int>;
	function bind(enc:helder.gfx.Encoder, node:helder.scene.Node):Void;
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

// what the view buffers ask of their motion's pass (MotionPass: made when
// their velocity is first asked for)
interface MotionSource {
	function render(enc:helder.gfx.Encoder, renderer:Renderer, frame:Renderer.FrameInfo):Void;
	// its target (RGBA16F) and the last frame's draws into it
	function texture():helder.gfx.Texture;
	function drawn():Int;
	function dispose():Void;
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

// what the renderer asks of its shadows (Shadows)
interface ShadowSource {
	// the atlas' pass, before the frame's: the sun's cascades (towards the
	// light toLight, fitted to frame's view), the local lights' tiles (the
	// renderer's frameLights, their tiles set there)
	function render(enc:helder.gfx.Encoder, renderer:Renderer, toLight:helder.gfx.shader.Vec3, frame:Renderer.FrameInfo):Void;
	// the last pass's atlas and how to read it (an object: hxmc passes struct
	// values through interface calls wrongly for now)
	function shadowFrame():ShadowFrame;
}

class ShadowFrame {
	// the atlas
	public var map:helder.gfx.Texture = cast 0;
	// the sun's first cascade: its view-projection; x strength, y bias, z a
	// texel of the tile, w the soft radius in its uv; its tile in the atlas
	public var viewProj:helder.gfx.shader.Mat4 = helder.gfx.shader.Mat4.identity();
	public var params:helder.gfx.shader.Vec4 = new helder.gfx.shader.Vec4(0, 0, 0, 0);
	public var rect:helder.gfx.shader.Vec4 = new helder.gfx.shader.Vec4(0, 0, 1, 1);
	// the second cascade's (one cascade: the first's)
	public var viewProjFar:helder.gfx.shader.Mat4 = helder.gfx.shader.Mat4.identity();
	public var paramsFar:helder.gfx.shader.Vec4 = new helder.gfx.shader.Vec4(0, 0, 0, 0);
	public var rectFar:helder.gfx.shader.Vec4 = new helder.gfx.shader.Vec4(0, 0, 1, 1);
	// the soft filter's (PbrFrame.shadowSoft; x 0: the 3x3 filter)
	public var soft:helder.gfx.shader.Vec4 = new helder.gfx.shader.Vec4(0, 0, 0, 0);
	// a texel of the atlas (x, y)
	public var atlas:helder.gfx.shader.Vec4 = new helder.gfx.shader.Vec4(1, 1, 0, 0);
	// PbrLights' tiles: the local lights'
	public var tiles:Null<haxe.io.Bytes> = null;
	// the last frame's draws into the atlas, every tile's
	public var draws = 0;

	public function new() {}
}

// what Shadows asks of its local lights' tiles (LocalShadows: made by
// shadows.local, so a program without links none of it)
interface LocalShadowSource {
	// the frame's tiles for its casting local lights (their first tiles set
	// in lights), each one's casters, whether each is kept
	function place(shadows:Shadows, lights:FrameLights, world:helder.scene.World):Void;
	// the instances its tiles drawn draw, their matrices into the shadows'
	// instance bytes from at (returns the end)
	function instances():Int;
	function layout(shadows:Shadows, at:Int):Int;
	// its tiles not kept drawn, the atlas' pass begun (clear: some kept)
	function draw(enc:helder.gfx.Encoder, shadows:Shadows, world:helder.scene.World, skins:Null<SkinSource>, clear:Bool):Void;
	// the tiles it kept this frame; PbrLights' tiles' bytes
	function kept():Int;
	function tiles():haxe.io.Bytes;
	// the atlas made again: nothing kept
	function forget():Void;
}

// what the renderer asks of clustered lighting (ClusteredLights)
interface ClusterSource {
	// the frame's lights it takes at most (FrameLights.reserve)
	function capacity():Int;
	// after the frame's lights are gathered (renderer.frameLights) and
	// their shadows' tiles set, before the frame's pass: their cells (a
	// compute pass, or the CPU's), the light data and the cluster map
	function assign(enc:helder.gfx.Encoder, renderer:Renderer, frame:Renderer.FrameInfo):Void;
	// what the frame's block and the material read (an object, as ShadowFrame)
	function clusterFrame():ClusterFrame;
	function dispose():Void;
}

class ClusterFrame {
	// the cells' lists, then the lights' rows
	public var clusterMap:helder.gfx.Texture = cast 0;
	// PbrFrame's clusters, clusterDepth, clusterAxis
	public var clusters:helder.gfx.shader.Vec4 = new helder.gfx.shader.Vec4(0, 0, 0, 0);
	public var depth:helder.gfx.shader.Vec4 = new helder.gfx.shader.Vec4(0, 0, 0, 0);
	public var axis:helder.gfx.shader.Vec4 = new helder.gfx.shader.Vec4(0, 0, 0, 0);

	public function new() {}
}

// what the renderer asks of instance culling (InstanceCulling): each
// instanced set's instances culled one by one and their levels picked
interface CullSource {
	// before the frame's passes (a compute pass, or the CPU's): the frame's
	// sets (the renderer's sets, setCount of them) culled for the view
	function cull(enc:helder.gfx.Encoder, renderer:Renderer, frame:Renderer.FrameInfo):Void;
	// whether it draws a set (else the renderer draws it whole)
	function takes(set:InstancedMesh):Bool;
	// a set's draws of one material's pass (blended: false, true) at the
	// renderer's bound pipeline and blocks; the draws it made
	// (slot: the instances' vertex buffer's)
	function draw(enc:helder.gfx.Encoder, set:InstancedMesh, primitive:Int, level:Int, slot:Int):Int;
	function dispose():Void;
}

// what the renderer asks of skinning (Skinning)
interface SkinSource {
	// the node's skin brought up to date; false when it has none
	function prepare(node:helder.scene.Node):Bool;
	function pipeline(doubleSided:Bool):helder.gfx.Pipeline;
	// the skinned shader's slots, in Renderer.slotsOf's order
	function slots():Array<Int>;
	// the node's skin bound for a draw (its joints' count: PbrSkinInfo's, a
	// shader's that has it; pbr's reads rows' in PbrObject's tint.w)
	function bind(enc:helder.gfx.Encoder, slots:Array<Int>, node:helder.scene.Node):Void;
	// the node's skin's joints (the rows of its joints' texture)
	function rows(node:helder.scene.Node):Float;
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

// the physical shader of materials with glTF extensions and none of their
// own (Physical: every extension's; null for a material that uses none)
interface PhysicalSource {
	function shaderOf(m:Material):Null<MaterialShader>;
}

// a physical shader's material data (PhysicalLayers): the extensions' fields
// into the material's block, their maps and the frame behind bound
interface LayerSource {
	function block(m:Material, out:PbrShader.PbrMaterial, behind:Float):Void;
	function layout(base:Array<helder.gfx.VertexBufferLayout>):Array<helder.gfx.VertexBufferLayout>;
	function bind(enc:helder.gfx.Encoder, slots:Array<Int>, sampler:helder.gfx.Sampler, white:helder.gfx.Texture, behind:helder.gfx.Texture,
		behindSampler:helder.gfx.Sampler):Void;
}

// what draws the opaque frame behind see-through surfaces (Transmission:
// Renderer splits its pass there, the copy read by the physical shaders)
interface TransmissionSource {
	function capture(enc:helder.gfx.Encoder, pass:helder.gfx.PassDesc, width:Int, height:Int, format:helder.gfx.TextureFormat):helder.gfx.Texture;
	function levels():Float;
}
