// helder.scene for TypeScript programs (helder.typescript): what
// helder/scene (src/helder/scene/index.ts, with its Node, pbr and material)
// exports of helder's Haxe classes. A World of nodes (Node: helder/scene's
// class over a node's handle, its members Script's), cameras, lights,
// meshes (Shapes, Geometry's shapes and Curve3, MeshRenderer, InstancedMesh,
// Sprites) and materials (Material's factories: toon, lambert, unlit...), glTF models (Model,
// helder/asset's model(path) loads one; GltfScene), the renderer, input
// actions (InputMap, Bindings), a fixed simulation step, and what a scene is
// drawn with: a window, its device (or a headless one), the app's loop. A
// program imports helder/scene, not this module.
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.
import type {Asset} from "helder/asset";
import type {Mat4, Quat, Vec2, Vec3, Vec4} from "helder/gfx";
import type {Node} from "helder/scene";

declare const __haxe: {Mesh: "helder.scene.render.Mesh", Encoder: "helder.gfx.Encoder", World: "helder.scene.World", Camera: "helder.scene.Camera", Light: "helder.scene.render.Light", Renderer: "helder.scene.render.Renderer", Shadows: "helder.scene.render.Shadows", Fog: "helder.scene.render.Fog", Material: "helder.scene.render.Material", MeshRenderer: "helder.scene.render.MeshRenderer", Shapes: "helder.scene.render.Shapes", Geometry: "helder.scene.render.Geometry", VertexData: "helder.scene.render.VertexData", Curve3: "helder.scene.math.Curve3", InstancedMesh: "helder.scene.render.InstancedMesh", Sprites: "helder.scene.render.Sprites", Model: "helder.scene.render.Model", MaterialShader: "helder.scene.render.MaterialShader", InputMap: "helder.scene.input.InputMap", Bindings: "helder.scene.input.Bindings", FixedStep: "helder.scene.FixedStep", Device: "helder.gfx.Device", Surface: "helder.os.Surface", Window: "helder.os.Window", App: "helder.os.App", Event: "helder.os.Event", Script: "helder.scene.Script", __module: "helder.scene.TypeScript"};

// What a node draws (node.mesh): primitives, each a vertex buffer in the
// renderer's layout (PbrVertex: position, normal, uv; 32 bytes a vertex),
// triangles' indices and a material, and the bounds of them all.
export declare class Mesh {
	private readonly mesh: never;
}

// Records a frame's passes: one per device, reused (no allocation per frame).
// What it records is counted in FrameCounts.
export declare class Encoder {
	private readonly encoder: never;
}

export type EventKind = number;

// What drives an action (InputMap.bind): a key (helder.os's KeySym: a Latin-1
// key's unshifted character, 0xFF51..0xFF54 the arrows, 0x20 Space), a
// mouse button (1 left, 2 middle, 3 right; the first finger or pen down
// that no control took is the left button while it is down), a region of
// the window held down by the mouse or such a finger
// (x0, y0, x1, y1 from 0 to 1 of its width and height: on-screen
// buttons), keys as an axis's two directions (negative, positive), a
// gamepad's button or one of its sticks' axes, times scale (any pad;
// helder.os.Gamepads' standard layout: PadButton(0) is A, PadAxis(1, -1) the
// left stick up), past a dead zone. Fingers and pens (helder.os.Pointers,
// a press taken by the first zone it began in, held until it lifts): a
// finger held in a zone (Touch: the old Region, per finger), a look zone's
// drag as an axis (TouchDelta: axis 0 x, 1 y; the points dragged over a
// step times scale), an on-screen stick's axis (Stick: 0 x right, 1 y up),
// an on-screen button (Button).
export declare class Binding {
	private readonly binding: never;
}

// What a device has beyond the render stages every back end has
// (Device.has): the compute tier. WebGPU, Metal, D3D11 (feature level
// 11_0: cs_5_0) and GL ES 3.1 (Android's floor) have all three; WebGL2 and
// a GL ES 3.0 context none, the render stages' path (helder.scene's
// fallbacks) staying theirs.
export type Feature = number;

export type AnyShader = unknown;

export type BoxOptions = { flat?: boolean; tangents?: boolean; width?: number; height?: number; depth?: number; widthSegments?: number; heightSegments?: number; depthSegments?: number };

export type CapsuleOptions = { flat?: boolean; tangents?: boolean; radius?: number; height?: number; capSegments?: number; radialSegments?: number; heightSegments?: number };

export type CircleOptions = { flat?: boolean; tangents?: boolean; radius?: number; segments?: number; thetaStart?: number; thetaLength?: number };

export type ConeOptions = { flat?: boolean; tangents?: boolean; radius?: number; height?: number; radialSegments?: number; heightSegments?: number; openEnded?: boolean; thetaStart?: number; thetaLength?: number };

export type CylinderOptions = { flat?: boolean; tangents?: boolean; radiusTop?: number; radiusBottom?: number; height?: number; radialSegments?: number; heightSegments?: number; openEnded?: boolean; thetaStart?: number; thetaLength?: number };

// a curve's frames (Curve3.frames): as many tangents, normals and binormals
export type Frames = { tangents: Vec3[]; normals: Vec3[]; binormals: Vec3[] };

export type LatheOptions = { flat?: boolean; tangents?: boolean; segments?: number; phiStart?: number; phiLength?: number };

// Material.matcap's: also the matcap, a lit sphere's picture (sRGB)
export type MatcapOptions = { name?: string; color?: Vec4; texture?: number; metallic?: number; roughness?: number; emissive?: Vec3; doubleSided?: boolean; blend?: boolean; blending?: number; alphaCutoff?: number; fog?: boolean; castShadows?: boolean; toneMapped?: boolean; matcap: number };

// what a material is made from (Material's factories): each field the
// material's of the same meaning, its default where not given (color the
// base colour, linear; texture the base colour's, sRGB)
export type MaterialOptions = { name?: string; color?: Vec4; texture?: number; metallic?: number; roughness?: number; emissive?: Vec3; doubleSided?: boolean; blend?: boolean; blending?: number; alphaCutoff?: number; fog?: boolean; castShadows?: boolean; toneMapped?: boolean };

// Material.phong's: also three's shininess (30 by default)
export type PhongOptions = { name?: string; color?: Vec4; texture?: number; metallic?: number; roughness?: number; emissive?: Vec3; doubleSided?: boolean; blend?: boolean; blending?: number; alphaCutoff?: number; fog?: boolean; castShadows?: boolean; toneMapped?: boolean; shininess?: number };

export type PlaneOptions = { flat?: boolean; tangents?: boolean; width?: number; height?: number; widthSegments?: number; heightSegments?: number };

export type RingOptions = { flat?: boolean; tangents?: boolean; innerRadius?: number; outerRadius?: number; thetaSegments?: number; phiSegments?: number; thetaStart?: number; thetaLength?: number };

export type SphereOptions = { flat?: boolean; tangents?: boolean; radius?: number; widthSegments?: number; heightSegments?: number; phiStart?: number; phiLength?: number; thetaStart?: number; thetaLength?: number };

// what Sprites are made with (each optional): how they face the camera
// (Spherical), the axis Axis turns about (y), the atlas' columns and rows
// (1 by 1), the sprites shown (all)
export type SpritesOptions = { mode?: number; axis?: Vec3; columns?: number; rows?: number; count?: number };

// Material.toon's: also its bands and its shade
export type ToonOptions = { name?: string; color?: Vec4; texture?: number; metallic?: number; roughness?: number; emissive?: Vec3; doubleSided?: boolean; blend?: boolean; blending?: number; alphaCutoff?: number; fog?: boolean; castShadows?: boolean; toneMapped?: boolean; steps?: number; shade?: Vec3 };

export type TorusKnotOptions = { flat?: boolean; tangents?: boolean; radius?: number; tube?: number; tubularSegments?: number; radialSegments?: number; p?: number; q?: number };

export type TorusOptions = { flat?: boolean; tangents?: boolean; radius?: number; tube?: number; radialSegments?: number; tubularSegments?: number; arc?: number };

export type TubeOptions = { flat?: boolean; tangents?: boolean; tubularSegments?: number; radius?: number; radialSegments?: number; closed?: boolean };

// A scene: a scene graph of Nodes (handles) over flat arrays, one slot per
// node: its local translation, rotation and scale (10 floats), its local
// and world matrices (16 each), its parent and siblings, its name and
// visibility. What nodes carry (a camera, a mesh, a light) is in typed
// stores keyed by node (ComponentStore, created by the kinds a program uses, so a
// kind nobody uses is not linked).
//
// World matrices are computed when asked and cached: a slot keeps the
// version of its parent's world matrix it was computed from, so a change
// high in the tree makes everything below it stale without visiting it,
// and still parts of a scene cost nothing per frame.
//
// A node's id: the world (4 bits: up to 16 worlds alive), the slot's
// generation (7 bits, never 0 for a live node, so no node is 0, NONE) and
// the slot (20 bits).
export declare class World {
	constructor(name?: string);
	readonly root: Node;
	// the world's slot freed for another (its nodes' handles stale)
	dispose(): void;
	// the number of live nodes, the root included
	readonly count: number;
	// a new node, under parent (by default the root)
	node(name?: string, parent?: Node): Node;
	// whether a node is in the tree under the root (not detached)
	inTree(n: Node): boolean;
	// the world's store of a kind (made on first use)
	store<T>(kind: unknown): unknown;
}

// A camera, a component of a node (Camera.attach(node, camera)): it looks
// down the node's -z, its up the node's +y. Projections are gfx's
// (Mat4.perspective, Mat4.orthographic: clip space y up, z from 0 at the
// near plane). Several cameras may look at one world (split screens,
// shadow views, XR's two eyes): each is drawn by its own Renderer.draw.
export declare class Camera {
	static readonly KIND: unknown;
	static perspective(fovY: number, near: number, far: number): Camera;
	static orthographic(height: number, near: number, far: number): Camera;
	// camera on node (a camera is on one node at a time; node had one: replaced)
	static attach(node: Node, camera: Camera): Camera;
	// node's camera, or null
	static of(node: Node): Camera | null;
	// the first camera of a world (in the order they were attached), or null
	static first(world: World): Camera | null;
	isPerspective: boolean;
	// perspective: the vertical field of view (radians); orthographic: the
	// height of the view (scene units)
	fovY: number;
	height: number;
	near: number;
	far: number;
	readonly node: Node;
	// the scene's space to the camera's (its node's world matrix inverted)
	view(): Mat4;
	projection(aspect: number): Mat4;
	viewProjection(aspect: number): Mat4;
	// the camera's position in the scene
	eye(): Vec3;
	// the ray through a point of the view (x, y from -1 to 1, y up), in the
	// scene's space: from the near plane, dir of unit length
	ray(x: number, y: number, aspect: number): { origin: Vec3; dir: Vec3 };
	// ray, written into out (returned): no object made
	rayInto(x: number, y: number, aspect: number, out: unknown): unknown;
}

// A light, a component of a node, as glTF's KHR_lights_punctual and
// three.js's lights: what kind of light it is (kind), its colour (linear)
// times its intensity.
//
//   Directional   shines down its node's -z, from far away (the sun)
//   Point         shines from its node's position, falling off with the
//                 inverse square of the distance, windowed to nothing at
//                 its range
//   Spot          a point light within a cone down its node's -z
//   Hemisphere    the ambient from above (color, the sky's) and below
//                 (groundColor), blended by a surface's normal: three's
//                 HemisphereLight, the renderer's sky and ground (which a
//                 world without one uses)
//
// The renderer takes the world's first directional light (shadowed by
// Shadows), its first hemisphere light, and up to four point and spot
// lights.
export declare class Light {
	static readonly KIND: unknown;
	static directional(color: Vec3, intensity: number): Light;
	static pointLight(color: Vec3, intensity: number, range: number): Light;
	// a point light shining down its node's -z within a cone: full inside
	// inner, fading to nothing at outer (radians from the axis)
	static spot(color: Vec3, intensity: number, range: number, inner: number, outer: number): Light;
	// three's HemisphereLight: the sky's colour from above, the ground's from
	// below, both times intensity (in place of the renderer's sky and ground)
	static hemisphere(sky: Vec3, ground: Vec3, intensity?: number): Light;
	static attach(node: Node, light: Light): Light;
	static of(node: Node): Light | null;
	readonly kind: number;
	color: Vec3;
	intensity: number;
	// a point or spot light's reach (scene units)
	range: number;
	// a spot light's cones (radians from its axis)
	innerCone: number;
	outerCone: number;
	// a hemisphere light's colour from below (linear; color is the sky's)
	groundColor: Vec3;
	// whether it shines from a point (a point or a spot light)
	readonly local: boolean;
}

// Draws a world's meshes (MeshRenderer) as seen by a camera, lit by its
// first directional Light and up to four point Lights (a world without
// lights: the renderer's sun) and an ambient from the sky and the ground,
// with PbrShader. Two stages:
//
//   extract   the world's meshes into a flat draw list: the nodes shown,
//             their bounds inside the camera's view, a draw per primitive
//             sorted by pipeline, material and primitive; runs of one
//             primitive become one instanced draw (PbrInstancedShader:
//             the matrices in an instance buffer); the seam for threads
//             and GPU culling later
//   record    the list as one depth-tested pass into the caller's encoder
//             (see-through materials last, farthest first, blended),
//             each draw's matrices and material in uniform blocks through
//             gfx's uniform ring (nothing allocated per frame: the list's
//             entries are kept)
//
// It is ordinary gfx code: draw records into the caller's encoder, so a
// program adds its own passes before or after; each camera of a world
// (split screens, XR's eyes) is a draw of its own.
export declare class Renderer {
	constructor(device: Device, offscreen?: boolean, samples?: number, hdr?: boolean);
	// (no tint: MeshRenderer.tint's default)
	static readonly WHITE: Vec3;
	// a shader's slots for its blocks and textures, in the renderer's order:
	// frame, object (-1: none), material, base colour, shadow map, skin,
	// joints, metallic-roughness, emissive, occlusion, normal, the far shadow
	// map, the environment map
	static slotsOf(uniforms: Array<{ name: string; binding: number; size: number }>, textures: Array<{ name: string; binding: number }>): number[];
	readonly device: Device;
	// without a Light in the world: towards the light (normalized when
	// drawn), and its colour times intensity
	sunDirection: Vec3;
	sunColor: Vec3;
	sky: Vec3;
	ground: Vec3;
	exposure: number;
	// a rim light from the sun's side: its colour times intensity (black:
	// none) and how tight to the silhouette it stays (the falloff's power)
	rim: Vec3;
	rimPower: number;
	// fog over the scene (Fog: colour, density, start, height falloff;
	// null: none), taken by the standard material, Sky, Environment and
	// GpuParticles; a material opts out with Material.fog
	fog: Fog | null;
	clearColor: unknown;
	// the last draw's draws in its main pass and primitives culled
	// (statistics); its shadow maps' draws (Shadows: every cascade's; 0
	// without); every renderer's by pass in helder.gfx.FrameCounts
	// (sceneDraws, shadowDraws, postDraws: PostProcess.draws)
	readonly draws: number;
	readonly culled: number;
	readonly shadowDraws: number;
	// whether runs of one primitive are drawn instanced (on by default)
	instancing: boolean;
	// the last draw's instances drawn by instanced draws (statistics)
	readonly instanced: number;
	// offscreen: drawn into textures (drawInto: RGBA8 and Depth32F, as a
	// <Scene>'s box in a ui), not the frame; its features' pipelines (skins,
	// normal maps, the sky, particles) made for those too (createPipeline)
	readonly offscreen: boolean;
	// offscreen: the targets' samples a pixel (4: multisampled, drawInto's
	// color and depth made with samples: 4, the colour resolved by the pass)
	readonly samples: number;
	// offscreen: drawn in linear light into half-float targets (RGBA16F:
	// light brighter than white kept), tone mapped after by a PostProcess
	// (a <Scene>'s box runs post's); false: tone mapped and encoded by the
	// shaders themselves into RGBA8
	readonly hdr: boolean;
	// the colour targets' format: RGBA16F with hdr, else RGBA8
	readonly colorFormat: number;
	// hdr: what turns the frame into the 8-bit image shown (bloom, tone
	// mapping, grading); a <Scene>'s box makes one when there is none
	post: unknown | null;
	// a pipeline for what it draws into: the frame, or drawInto's targets
	// (RGBA8, Depth32F, its samples); its features' and a program's own
	// passes inside its frame (inject) make theirs with it
	createPipeline(d: { vertex?: number; fragment?: number; program?: { vertex: { glsl?: string; msl?: string; hlsl?: string; wgsl?: string; bindings?: Array<{ name: string; slot: number; kind: number; size?: number; index?: number; format?: number }>; workgroupSize?: number[] }; fragment: { glsl?: string; msl?: string; hlsl?: string; wgsl?: string; bindings?: Array<{ name: string; slot: number; kind: number; size?: number; index?: number; format?: number }>; workgroupSize?: number[] } }; layout: Array<{ stride: number; attributes: Array<{ location: number; format: number; offset: number }>; step?: number }>; topology?: number; cull?: number; blend?: number; depthCompare?: number; depthWrite?: boolean; colorFormat?: number; depthFormat?: number; samples?: number }): number;
	// draw into color (colorFormat, a render target) and depth (Depth32F, its size), an offscreen renderer's
	// (multisampled, samples > 1: color and depth of those samples, color
	// resolved into resolve, a single-sampled RGBA8 render target)
	drawInto(enc: Encoder, world: World, camera: Camera, color: number, depth: number, width: number, height: number, resolve?: number): void;
	// what the frame's hooks get: the camera's view, the light (FrameInfo)
	readonly frame: unknown;
	// f runs at a point of each frame: BeforeOpaque and AfterOpaque inside
	// the frame's pass (draw with your own pipelines, depth-tested against
	// the scene), AfterPass after it (passes of your own: an overlay)
	inject(point: number, f: (arg0: Encoder, arg1: unknown) => void): void;
	// turns on an optional feature (Shadows, Skinning, NormalMaps, Sky, Environment); returns the renderer
	use(feature: unknown): Renderer;
	// records the frame's pass: world seen by camera (aspect: the target's,
	// by default the device's)
	draw(enc: Encoder, world: World, camera: Camera, aspect?: number): void;
	// the draw list: each shown mesh inside the view, a draw per primitive, sorted
	extract(world: World, viewProj: Mat4): void;
	dispose(): void;
}

// Shadow maps for the directional light, opted in (renderer.use(new
// Shadows(device))): before the frame's pass, every shown mesh drawn from
// the light into size x size R32F targets (the casters of one primitive
// in one instanced draw, their matrices in an instance buffer written once
// for every cascade), which the standard material then reads with a 3x3
// percentage-closer filter, or a soft one (soft: a wider disc of taps,
// sharper where the shadow meets its caster). One cascade: an
// orthographic view fitted to the casters' bounds. Two (Shadows.cascaded,
// whose fitting code a program without it does not link):
// the first fitted to the camera's view up to split metres (its bounding
// sphere, moved by whole texels: steady as the camera moves), sharp near
// the camera, the second the whole scene's, read beyond the first. A
// program that never makes a Shadows links none of this but the
// material's lookup of a 1x1 map that shadows nothing.
export declare class Shadows {
	// one cascade
	constructor(device: Device, size?: number);
	// two cascades, the first reaching split metres from the camera
	static cascaded(device: Device, size?: number, split?: number): Shadows;
	readonly device: Device;
	readonly size: number;
	// 1, or 2 (Shadows.cascaded)
	readonly cascades: number;
	// how far from the camera the first of two cascades reaches (metres)
	split: number;
	// the depth offset against shadow acne (in the whole scene's map's 0..1
	// depth; the first of two cascades', as many of its texels)
	bias: number;
	// the shadows' strength, 0 (none) to 1 (no direct light at all)
	strength: number;
	// the first cascade's map (one cascade: the only one), the second's
	readonly map: number;
	readonly mapFar: number;
	// the soft filter (soft): the widest penumbra's radius in metres (0: the
	// 3x3 filter), its taps a point (8 for phones, 16, 32), and how much
	// the penumbra widens a metre from its caster (0: the radius
	// everywhere, no blocker search)
	softRadius: number;
	softSamples: number;
	softSpread: number;
	// the last frame's draws into the maps (every cascade's: a primitive's
	// casters one instanced draw, a skinned caster one draw)
	readonly draws: number;
	// the last frame's light view-projections (the first cascade's, the second's)
	readonly viewProj: Mat4;
	readonly viewProjFar: Mat4;
	// the soft filter on (returns the shadows): taps on a disc out to radius
	// metres, samples a point (8: phones; 16; 32), and with a spread a
	// blocker search first, the penumbra growing by spread a metre from its
	// caster up to the radius (contact hardening: PCSS); spread 0, the
	// radius everywhere
	soft(radius?: number, samples?: number, spread?: number): Shadows;
	attach(renderer: Renderer): void;
	shadowFrame(): unknown;
	// the maps' passes: the world's shown meshes that cast (Material.castShadows)
	// seen from a light shining along -toLight, the map fitted to them
	render(enc: Encoder, world: World, toLight: Vec3, skins: unknown | null, view: unknown): void;
	dispose(): void;
}

// Fog over a scene (Renderer.fog; null: none). A surface's light is mixed
// towards color (linear, times the exposure) by the fog between it and
// the eye: 1 - e^(-density * the distance past start), at most max. With
// falloff, the fog thins upwards: density at height, times
// e^(-falloff * (y - height)), summed along the view, so valleys fill and
// what is high, the sky above among it, clears. In linear light before
// tone mapping, so an HDR frame blooms and grades it as the rest. The
// standard material (Material.fog: on by default), Sky and Environment's
// background (to the camera's far plane) and GpuParticles (faded, as they
// add light) take it; a program's own shaders read it through FrameInfo.fog
// (color and shape, as PbrShader.fogAmount takes them).
export declare class Fog {
	constructor(color: Vec3, density: number);
	// as shaders take it: rgb its colour, w the density (none: 0)
	static colorOf(f: Fog | null): Vec4;
	// x the start, y the falloff, z the height, w the most
	static shapeOf(f: Fog | null): Vec4;
	color: Vec3;
	// per metre (0.02: half gone at 35 m)
	density: number;
	// metres from the eye before it begins
	start: number;
	// how fast it thins upwards (per metre; 0: as thick at any height) and
	// the height where it is density
	falloff: number;
	height: number;
	// the most it hides (below 1: the far hills and the sky show through)
	max: number;
}

// A surface of glTF's metallic-roughness model: base colour (linear,
// times the texture's sRGB colour when there is one), metallic and
// roughness from 0 to 1, emitted light (linear); double-sided ones are
// drawn without back-face culling.
//
// Its shading model is its shader's (helder.scene.render.shading), chosen
// by the factory it is made with, three.js's materials by name:
//
//   Material.standard({...})   pbr, the default (MeshStandardMaterial; new Material(...))
//   Material.lambert({...})    a light's diffuse alone (MeshLambertMaterial): the cheap lit one for phones
//   Material.phong({...})      Blinn-Phong (MeshPhongMaterial), shininess as three's
//   Material.toon({...})       light in steps bands, the shade away from it (MeshToonMaterial)
//   Material.unlit({...})      the colour alone, no light (MeshBasicMaterial)
//   Material.matcap({...})     a lit sphere's picture by the normal (MeshMatcapMaterial)
//   Material.normals()         the normal in view space as a colour (MeshNormalMaterial)
//   Material.depth(near, far)  the view's depth as a grey (MeshDepthMaterial)
//
// The lit ones keep pbr's shadows, lights, fog and normal maps (only how a
// light reaches the surface differs); the unlit ones read no light. A
// factory references its model's shader alone, so a program that never
// calls Material.toon links no toon shader.
export declare class Material {
	constructor(name?: string, baseColor?: Vec4, metallic?: number, roughness?: number, emissive?: Vec3, doubleSided?: boolean);
	// the standard material (pbr: three's MeshStandardMaterial), made from options
	static standard(options?: MaterialOptions): Material;
	// Lambert's (three's MeshLambertMaterial): each light's diffuse alone,
	// the ambient's diffuse alone; no highlight, no reflection
	static lambert(options?: MaterialOptions): Material;
	// Blinn-Phong (three's MeshPhongMaterial): a highlight of shininess
	// (three's: 30 by default), kept as the roughness that lobe matches
	// (shading's Phong), the reflections pbr's
	static phong(options?: PhongOptions): Material;
	// toon shading (three's MeshToonMaterial): each light in steps bands
	// (3 by default), its shadow banded with it, the side away from every
	// light the albedo times shade (linear)
	static toon(options?: ToonOptions): Material;
	// no light (three's MeshBasicMaterial): the colour times its texture,
	// tinted and fogged
	static unlit(options?: MaterialOptions): Material;
	// a matcap (three's MeshMatcapMaterial): the picture of a lit sphere
	// (an sRGB image: matcap, kept as the emissiveTexture) read by the
	// normal as the eye sees it, times the colour
	static matcap(options: MatcapOptions): Material;
	// the normal in view space as a colour (three's MeshNormalMaterial),
	// not tone mapped
	static normals(options?: MaterialOptions): Material;
	// the depth along the view as a grey, white at near and black at far
	// (three's MeshDepthMaterial, linear), not tone mapped
	static depth(near?: number, far?: number, options?: MaterialOptions): Material;
	// the material's index (draws sort by it; an index into a material buffer later)
	readonly id: number;
	name: string;
	baseColor: Vec4;
	metallic: number;
	roughness: number;
	emissive: Vec3;
	baseColorTexture: number | null;
	// glTF's other maps: roughness (green) and metallic (blue), times the
	// factors; emitted colour (sRGB), times emissive; ambient occlusion (red)
	metallicRoughnessTexture: number | null;
	emissiveTexture: number | null;
	occlusionTexture: number | null;
	// a tangent-space normal map (drawn with NormalMaps, on primitives with
	// tangents), its x and y scaled by normalScale
	normalTexture: number | null;
	normalScale: number;
	doubleSided: boolean;
	// how its textures are read (null: the renderer's: linear, mip-mapped,
	// repeating; glTF's samplers otherwise)
	sampler: number | null;
	// see-through (glTF's alphaMode BLEND): blended over what is behind,
	// drawn after the opaque surfaces, farthest first, without writing depth
	blend: boolean;
	// how, when blend is on: by the base colour's alpha (Alpha), added to
	// what is behind (Additive: glows, holograms, beams; faded by its
	// alpha), or premultiplied
	blending: number;
	// whether it casts a shadow (Shadows: its primitives drawn into the map,
	// their meshes inside the map's bounds); off for glows and glass
	castShadows: boolean;
	// whether the renderer's fog (Renderer.fog) covers it (off: a glow or
	// a sign that cuts through it)
	fog: boolean;
	// how much of its light it emits only on its night side (0: all of it
	// everywhere, 1: none where the sun shines; city lights on a planet),
	// faded across the terminator
	emissiveNight: number;
	// how much it stands on a sphere whose outward normal is its node's up
	// (local +y: a building on a planet, a tree on a globe): 1 and the sun
	// sets on it as on that ground, its direct light and rim faded across
	// the sphere's terminator, so it darkens with its planet's night side
	// (0: lit by its own faces alone)
	ground: number;
	// the air between it and the eye (aerial perspective), with ground's
	// up: rgb its colour (linear), w how much at most, reached towards the
	// sphere's limb (where its up turns from the eye), lit by the sun over
	// that ground (0: none)
	air: Vec4;
	// how much it is a crystal (0 to 1): polished (roughness 0.07) and a
	// gem's reflectance, the environment's reflection and the rim light
	// strong at grazing angles (Fresnel), lit from inside by its emissive
	// colour lifted towards white, most where it faces the eye (a fake
	// subsurface), the sun through it from behind; its edges opaque, its
	// middle as see-through as its base colour's alpha with blend on
	// (Additive's an additive glass). Faceted by its normals: give its
	// facets flat ones (vertices not shared across their edges)
	crystal: number;
	// glTF's KHR_texture_transform: the uvs its textures are read at turned
	// by uvRotation (radians), scaled by uvScale, then moved by uvOffset
	// (one transform for all of a material's textures)
	uvOffset: Vec2;
	uvRotation: number;
	uvScale: Vec2;
	// glTF's alphaMode MASK: fragments whose alpha is below it are dropped,
	// the rest opaque (0: none)
	alphaCutoff: number;
	// a shader of its own (MaterialShader.material: pbr with slots
	// replaced), null: the standard one; the blocks of its own, by their
	// parameters' names (its slots' parameters the standard ones are not)
	shader: MaterialShader | null;
	uniforms: unknown | null;
	// a clear coat over the surface (KHR_materials_clearcoat): how much (0
	// to 1) and its roughness; a polished dielectric layer (f0 0.04) whose
	// reflection, from the sun and the environment, is added over the base
	// and dims it by its Fresnel
	clearcoat: number;
	clearcoatRoughness: number;
	// how much of the light goes through it (KHR_materials_transmission, 0
	// to 1), a thin surface without refraction: its diffuse light replaced
	// by what is behind it (drawn see-through, Premultiplied, after the
	// opaque surfaces), its reflections kept
	transmission: number;
	// the toon model's (Material.toon): bands of each light's n.l (1 or
	// more), and the shaded side's share of the albedo (linear)
	steps: number;
	shade: Vec3;
	// tone mapped as the target takes it (three's toneMapped); false: its
	// colour shown as it is, only encoded for an 8-bit target (the debug
	// views: Material.normals, Material.depth)
	toneMapped: boolean;
	// Material.depth's range along the camera's view: white at depthNear,
	// black at depthFar (scene units)
	depthNear: number;
	depthFar: number;
}

// The mesh a node draws: a component (a store keyed by node), several
// nodes may share one Mesh.
export declare class MeshRenderer {
	static readonly KIND: unknown;
	static attach(node: Node, mesh: Mesh): Mesh;
	static of(node: Node): Mesh | null;
	static detach(node: Node): void;
	// a node's tint: rgb times its materials' base colour (1, 1, 1 when
	// none), per node: nodes sharing a mesh and a material in one
	// instanced draw each their own (a building in its planet's palette)
	static readonly TINT: unknown;
	static tint(node: Node, color: Vec3): void;
}

// Meshes made in code (no file): Geometry's shapes uploaded, each one
// primitive of a material. Shapes.of takes any Geometry (or VertexData);
// box, sphere, capsule and plane are the common ones at their usual sizes.
//
//   var post = Shapes.of(device, Geometry.cylinder({radiusTop: 0.1, radiusBottom: 0.1, height: 2, flat: true}), wood);
export declare class Shapes {
	// a geometry (Geometry's, or any VertexData) as a mesh of one primitive
	static of(device: Device, geometry: VertexData, material: Material): Mesh;
	// a box of width, height and depth, centred, flat faces
	static box(device: Device, material: Material, w?: number, h?: number, d?: number): Mesh;
	// a sphere of radius, segments around and rings from pole to pole
	static sphere(device: Device, material: Material, radius?: number, segments?: number, rings?: number): Mesh;
	// a capsule along y: the points within radius of the segment from -half
	// to half (physics' Capsule(radius, half)), segments around, rings in
	// each end's hemisphere
	static capsule(device: Device, material: Material, radius?: number, half?: number, segments?: number, rings?: number): Mesh;
	// a square of size on y = 0, facing up (Geometry.plane turned from xy)
	static plane(device: Device, material: Material, size?: number): Mesh;
}

// Shapes made in code, on the CPU (three's geometries, Bevy's meshable
// primitives): each generator returns a VertexData (positions, normals,
// uvs and triangles in the renderer's layout; tangents with tangents:
// true), free of the GPU, so it is tested on Eval, read by physics for its
// colliders and packed by the asset step. Shapes.of(device, geometry,
// material) uploads one as a Mesh.
//
// The parameters, their names and defaults, their vertex counts and their
// triangles are three.js's, as option structures (each field optional):
//
//   Geometry.box({width, height, depth, widthSegments, heightSegments, depthSegments})
//   Geometry.sphere({radius, widthSegments, heightSegments, phiStart, phiLength, thetaStart, thetaLength})
//   Geometry.cylinder({radiusTop, radiusBottom, height, radialSegments, heightSegments, openEnded, thetaStart, thetaLength})
//   Geometry.cone({radius, height, radialSegments, heightSegments, openEnded, thetaStart, thetaLength})
//   Geometry.capsule({radius, height, capSegments, radialSegments, heightSegments})
//   Geometry.torus({radius, tube, radialSegments, tubularSegments, arc})
//   Geometry.torusKnot({radius, tube, tubularSegments, radialSegments, p, q})
//   Geometry.ring({innerRadius, outerRadius, thetaSegments, phiSegments, thetaStart, thetaLength})
//   Geometry.circle({radius, segments, thetaStart, thetaLength})
//   Geometry.plane({width, height, widthSegments, heightSegments})
//   Geometry.lathe(points, {segments, phiStart, phiLength})
//   Geometry.tube(curve, {tubularSegments, radius, radialSegments, closed})
//
// Like three's: y up, the plane, circle and ring in xy facing +z, the
// torus about z, a cylinder's seam at +z. Unlike three's, uvs run down the
// image as glTF's (three's v flipped: 1 - v), as every helder material
// reads them. Each also takes flat: true (its vertices unshared, each
// triangle's three with its face's normal: flat shading, a low-poly
// look) and tangents: true (VertexData.computeTangents', for normal maps).
export declare class Geometry {
	static box(o?: BoxOptions): VertexData;
	static sphere(o?: SphereOptions): VertexData;
	static cylinder(o?: CylinderOptions): VertexData;
	// a cylinder whose top is a point (three's ConeGeometry)
	static cone(o?: ConeOptions): VertexData;
	// a cylinder of height with half spheres of radius at its ends, along y
	// (physics' Capsule(radius, height / 2)): rows from the top pole down,
	// capSegments in each half sphere, heightSegments along the side
	static capsule(o?: CapsuleOptions): VertexData;
	static torus(o?: TorusOptions): VertexData;
	// a tube wound p times about the torus' axis and q times through its
	// hole (three's TorusKnotGeometry)
	static torusKnot(o?: TorusKnotOptions): VertexData;
	static ring(o?: RingOptions): VertexData;
	static circle(o?: CircleOptions): VertexData;
	static plane(o?: PlaneOptions): VertexData;
	// points (x the distance from the y axis, y the height) turned about y
	// (three's LatheGeometry: its normals from the profile's, averaged
	// between its segments)
	static lathe(points: Vec2[], o?: LatheOptions): VertexData;
	// a tube of radius along a curve, its rings on the curve's frames
	// (Curve3.frames: no twist where the curve bends back), at equal lengths
	// along it (three's TubeGeometry)
	static tube(curve: Curve3, o?: TubeOptions): VertexData;
}

// A primitive's vertices and indices in the renderer's layout, made from
// arrays (Mesh.add at run time, the asset step's packer at build time,
// Geometry's generators: one implementation, free of the GPU so that it
// runs on Eval): 32 bytes a vertex (position, normal, uv), 64 with joints
// and weights (skinned); indices of 16 bits where the vertices allow, else
// 32; tangents (x, y, z and the bitangent's sign, 16 bytes a vertex) in a
// buffer of their own, for normal maps (NormalMaps): drawn without them,
// the vertices are as any other's. An immutable value: read with
// position(i), normal(i), uv(i), index(k); transformed makes another.
export declare class VertexData {
	constructor(vertices: Uint8Array, indices: Uint8Array, wide: boolean, count: number, skinned: boolean, bounds: unknown, tangents?: Uint8Array);
	// normals null: computed from the triangles (smooth where vertices are
	// shared); indices null: 0, 1, 2, ...
	static make(positions: number[], normals: number[] | null, uvs: number[] | null, indices: number[] | null, joints?: number[], weights?: number[], tangents?: number[]): VertexData;
	// how loaders make tangents where a file has none (GltfScene): set by
	// NormalMaps when made (computeTangents), so that a program without
	// normal maps links neither; null: no tangents loaded
	static tangentsFrom: ((positions: number[], normals: number[], uvs: number[], indices: number[]) => number[]) | null;
	// each vertex's tangent (x, y, z: along the uvs' u, at right angles to
	// its normal; w: 1 or -1, the bitangent n x t's sign, the bitangent
	// pointing up the image) from its
	// triangles' uvs (Lengyel's method, summed over the triangles: glTF asks
	// for MikkTSpace's where a file has none, which agrees on meshes whose
	// uvs are not mirrored within a triangle fan)
	static computeTangents(positions: number[], normals: number[], uvs: number[], indices: number[]): number[];
	// each vertex's normal: the sum of its triangles' (area-weighted), normalized
	static smoothNormals(positions: number[], indices: number[]): number[];
	readonly vertices: Uint8Array;
	readonly indices: Uint8Array;
	readonly wide: boolean;
	readonly count: number;
	readonly skinned: boolean;
	readonly bounds: unknown;
	readonly tangents: Uint8Array | null;
	// the vertices there are (count is the indices')
	readonly vertexCount: number;
	// vertex i's position, normal (unit) and uvs
	position(i: number): Vec3;
	normal(i: number): Vec3;
	uv(i: number): Vec2;
	// the k-th index (a triangle is 3k, 3k + 1, 3k + 2: counter-clockwise from its front)
	index(k: number): number;
	// the same moved by an affine matrix (its normals by the inverse
	// transpose, unit again; its tangents turned); three's applyMatrix4
	transformed(m: Mat4): VertexData;
	// turned by Euler angles (radians: x, then y, then z, as Quat.fromEuler)
	rotated(x: number, y: number, z: number): VertexData;
	translated(x: number, y: number, z: number): VertexData;
}

// A curve in space, an immutable value (three's Curve and its kinds): a
// cubic Bezier, a Catmull-Rom spline through points (open or closed), a
// straight line, or a path of curves end to end. It is read by a parameter
// t from 0 to 1 (point, tangent: a path's t runs by length across its
// curves), or by a distance along it (pointAt, tangentAt: its length
// tabulated once, when made, over 200 steps as three's arcLengthDivisions).
// frames(n) gives n + 1 frames along it by length that turn as little as
// they can (parallel transport, three's computeFrenetFrames): a tube's
// rings (Geometry.tube), a camera on rails.
//
//   var rail = Curve3.catmullRom([a, b, c, d], true);
//   var p = rail.pointAt(rail.length * 0.25);
export declare class Curve3 {
	// a cubic Bezier from a to d, its handles b and c (three's CubicBezierCurve3)
	static bezier(a: Vec3, b: Vec3, c: Vec3, d: Vec3): Curve3;
	// a straight line from a to b (three's LineCurve3)
	static line(a: Vec3, b: Vec3): Curve3;
	// a Catmull-Rom spline through points (two at least), back to the
	// first when closed; tension 0.5 the classic spline (three's
	// CatmullRomCurve3 of type "catmullrom")
	static catmullRom(points: Vec3[], closed?: boolean, tension?: number): Curve3;
	// curves end to end (three's CurvePath), t by length across them
	static path(curves: Curve3[]): Curve3;
	// the curve's length (scene units)
	readonly length: number;
	// the point at t (0 to 1)
	point(t: number): Vec3;
	// the unit tangent at t (its derivative's direction)
	tangent(t: number): Vec3;
	// the point at a distance along it from the start (0 to length)
	pointAt(distance: number): Vec3;
	// the unit tangent at a distance along it
	tangentAt(distance: number): Vec3;
	// the parameter t at a distance along it (the table searched, linear between its steps)
	paramAt(distance: number): number;
	// n + 1 frames at equal lengths along it (n at least 1): each a unit
	// tangent, normal and binormal (tangent x normal), the normal carried
	// from one to the next by the turn between their tangents (no flips at
	// inflections, unlike Frenet's); closed, the twist between the last and
	// the first spread over them, so the ends meet
	frames(n: number, closed?: boolean): Frames;
}

// One mesh drawn many times in one instanced draw a primitive, its
// instances' data in flat arrays the program writes (no node, no object
// an instance): a swarm of asteroids, a fleet of ships, a forest. Each
// instance is a world transform (a position, a unit quaternion and a
// uniform scale, or any affine matrix: uneven scales too, the normals
// turned by its inverse transpose), a colour (rgb times the material's base colour, white by default)
// and, for a program's own shader, `custom` floats of its own (a second
// buffer, `custom` floats an instance, a multiple of 4). Attached to a
// node (InstancedMesh.attach), drawn by the Renderer while the node is
// shown (culled whole by bounds when given, never one by one; casting
// into Shadows' map), with the standard material (PbrInstancedShader: its layout's
// instance buffer, LAYOUT's second). Nothing is allocated a frame: a write
// marks the instances changed and the renderer uploads count of them
// before its pass (one writeBuffer, two with custom data).
//
//   var rocks = new InstancedMesh(Shapes.sphere(device, rock, 1), 100000);
//   InstancedMesh.attach(world.node("belt"), rocks);
//   // each frame:
//   for (i in 0...rocks.count) rocks.setTransform(i, x, y, z, qx, qy, qz, qw, s);
//
// The data's layout is the instance buffer's (`data`, 16 floats an
// instance, the matrix by columns, each of the first three columns' w the
// colour's channel less 1, the last column's w 1), so a program can also
// write it directly (data.setFloat, then changed()).
export declare class InstancedMesh {
	constructor(mesh: Mesh, capacity: number, count?: number, custom?: number);
	static readonly KIND: unknown;
	// bytes an instance in data
	static readonly STRIDE: number;
	static attach(node: Node, instances: InstancedMesh): InstancedMesh;
	static of(node: Node): InstancedMesh | null;
	static detach(node: Node): void;
	readonly mesh: Mesh;
	// the instances there is room for; grow with resize
	readonly capacity: number;
	// the instances drawn (0 to capacity)
	count: number;
	// custom floats an instance (custom's stride: 4 * custom bytes)
	readonly custom: number;
	// the instance buffer's data: STRIDE bytes an instance
	readonly data: Uint8Array;
	// the custom data (custom floats an instance; empty without)
	readonly customData: Uint8Array;
	// the GPU's copies, made by the renderer when first drawn (Buffer.NONE before)
	readonly buffer: number;
	readonly customBuffer: number;
	// the instances' bounds in the world, when the program knows them
	// (empty: unknown): the renderer culls the whole set by them and
	// Shadows fits its map to them; without, the set is always drawn and
	// casts into a map fitted to the other casters
	bounds: unknown;
	// whether it casts shadows (Shadows; its materials' castShadows too)
	castShadows: boolean;
	// room for capacity instances (the data kept, new ones at the origin, white)
	resize(capacity: number): void;
	// marks the data written directly as changed (the setters do)
	changed(): void;
	// instance i at x, y, z, turned by the unit quaternion (qx, qy, qz, qw)
	// and scaled by s, its colour kept
	setTransform(i: number, x: number, y: number, z: number, qx: number, qy: number, qz: number, qw: number, s?: number): void;
	// instance i's position only (its turn, scale and colour kept)
	setPosition(i: number, x: number, y: number, z: number): void;
	// instance i's world matrix (affine: any scale, uneven too), its colour kept
	setMatrix(i: number, m: Mat4): void;
	// instance i's colour (linear rgb, times the material's base colour)
	setColor(i: number, r: number, g: number, b: number): void;
	// instance i's position (axis 0, 1, 2: x, y, z), as written
	position(i: number, axis: number): number;
	// instance i's colour channel (0, 1, 2: r, g, b)
	color(i: number, channel: number): number;
	// instance i's custom float k (0 to custom - 1)
	setCustom(i: number, k: number, v: number): void;
	getCustom(i: number, k: number): number;
	// what a set does before it is uploaded for a camera's view-projection
	// (the renderer's, each frame it is shown: Sprites turns its quads to
	// the camera there); nothing by default
	prepare(viewProj: Mat4): void;
	// the changed instances to the GPU (the renderer's, before its pass; a
	// program drawing them with its own pipeline calls it too): count of
	// them, the buffers made or grown to the capacity
	upload(device: Device): void;
	// the GPU's buffers freed (the mesh is the caller's)
	dispose(): void;
}

// Quads that face the camera (three's Sprite, Godot's billboard modes), as
// one InstancedMesh: clouds, halos, trees far off, particles of one's own.
// Each sprite is a position (in the world), a width and a height (scene
// units), a turn in the screen's plane, a cell of an atlas and a colour;
// all of them are one instanced draw. The renderer turns them before its
// pass (prepare: from the camera's view-projection, the matrices written
// into the instance data and uploaded), so nothing is allocated a frame.
//
//   mode Spherical  facing the camera, upright on the screen (turned by rotation)
//   mode Axis       turning about axis only (a tree, a cloud's column, a
//                   flame): upright along it, as near facing the camera as it can
//   mode Fixed      facing +z, turned by rotation about z (a decal of one's own)
//
// Its material is any (Material.unlit with Additive: halos; with a texture
// and alphaCutoff: leaves; a lit one: its normal faces the camera, so it is
// lit as a card). See-through ones are drawn after the opaque surfaces
// (Material.blend), Alpha's sorted far to near among themselves when the
// camera moves. An atlas is columns by rows cells of the material's
// texture, left to right then top to bottom (the material's uvScale set to a
// cell's share; a sprite's cell moves its uvs there: PbrShader.instanceUv).
//
//   var halos = new Sprites(device, Material.unlit({color: gold, texture: glow, blend: true, blending: Additive}), 64);
//   Sprites.attach(world.node("halos"), halos);
//   halos.count = lamps.length;
//   for (i in 0...halos.count) halos.set(i, lamps[i].x, lamps[i].y, lamps[i].z, 0.8, 0.8);
//
// InstancedMesh's own setTransform and setMatrix are overwritten by the
// turn: a sprite is set with set, setPosition, setSize, setRotation,
// setCell and setColor. Its bounds (InstancedMesh.bounds: the whole set's,
// culled by them) are the program's, as an InstancedMesh's.
export declare class Sprites extends InstancedMesh {
	// capacity sprites of material (count of them shown: all by default);
	// their quad (Geometry.plane) made on device (null: none, their data
	// alone: tests)
	constructor(device: Device | null, material: Material, capacity: number, options?: SpritesOptions);
	static attach(node: Node, sprites: Sprites): Sprites;
	// what they are drawn with (the quad's)
	readonly material: Material;
	// how they face the camera
	mode: number;
	// the axis Axis turns about (the world's; unit)
	axis: Vec3;
	// the atlas' cells (1 by 1: the whole image)
	readonly columns: number;
	readonly rows: number;
	// sprite i at x, y, z, of width and height, turned by rotation
	// (radians, counter-clockwise on the screen; Axis: none), its atlas cell
	// (0 the first, left to right then down), its colour kept
	set(i: number, x: number, y: number, z: number, width: number, height: number, rotation?: number, cell?: number): void;
	setPosition(i: number, x: number, y: number, z: number): void;
	setSize(i: number, width: number, height: number): void;
	setRotation(i: number, rotation: number): void;
	// (column + columns * row)
	setCell(i: number, cell: number): void;
	// sprite i's colour (linear rgb, times the material's base colour)
	setColor(i: number, r: number, g: number, b: number): void;
	// sprite i's field: 0 to 2 its position, 3 and 4 its size, 5 its
	// rotation, 6 its cell, 7 to 9 its colour
	get(i: number, field: number): number;
	resize(capacity: number): void;
	// the instances turned to the camera of viewProj (the renderer's, before
	// its upload): its axes from the view-projection's rows (a symmetric
	// projection's right and up, its back the third row's opposite); nothing
	// done when neither the camera nor a sprite changed
	prepare(viewProj: Mat4): void;
}

// A glTF model referenced where it is used: Model.of("models/hero.glb") is
// a macro that checks the file exists (an asset's path: helder.asset's
// AssetPath), reads its structure when compiling and types the result from
// it: model.nodes, model.meshes, model.materials and model.animations have
// a field per name in the file (its value the name, for World.find; a name
// that is no identifier made one: "Left Hand" is Left_Hand), so a typo is a
// compile error. The file goes with the build as every asset does
// (helder.asset's Bundle: the executable's data, the APK's or the app's
// assets/, beside the page), and Model.of reads it before anything runs
// (on the web os's browser.mjs fetches it before main):
//
//   var hero = Model.of("models/hero.glb");
//   var root = hero.instantiate(world, device);
//   var hand = root.find(hero.nodes.LeftHand);
//
// helder.asset's Asset.model(path) (or Model.of(path, Lazy)) is an Asset
// of the model instead, loaded in the background (big games, loading
// screens: `var hero = Asset.model(path).load();` in a coroutine), its
// names typed the same, reloaded under helder dev (its meshes and
// materials swapped in the instances: replace); Model.load(path) loads a
// path known only at run time (an Asset, names unknown, not bundled).
//
// Its GPU meshes are made by the first instantiate with a device and
// shared by every instance.
export declare class Model<N, M, A, C> {
	// a model whose path is known only at run time: loaded in the background
	// (in the browser fetched, relative to the page; natively read at once),
	// its names unknown when compiling (find nodes by name: model.doc)
	static load(path: string): Asset<Model<{}, {}, {}, {}>>;
	// the model's scene as nodes of world (under parent, by default the root)
	instantiate(world: World, device: Device, parent?: Node, made?: Node[]): Node;
	// the model's GPU meshes released
	dispose(): void;
}

// A material's own shader (DESIGN.md 3 in src/helder/compiler): pbr (the
// standard material, PbrShader) with some of its slots replaced, compiled
// at build time into the variants the renderer draws with (plain, normal
// mapped, skinned, instanced, instanced and normal mapped), set on a
// Material (material.shader) as the shader its primitives are drawn with.
// Another slot object of the renderer's vertex and parameters (shading's
// unlit) works too: one without pbr's normalMap option has no normal-mapped
// variants (null; its primitives drawn without their normal maps):
//
//   final Glow = MaterialShader.material(pbr.with({
//     emissive: function(s, p:{glow:GlowParams}):Vec3 return p.glow.color.xyz * (0.5 + 0.5 * sin(p.glow.time.x)),
//     color: function(s, p:{}):Vec3 return s.baseColor.xyz * 1.5
//   }));
//   material.shader = Glow;
//   material.uniforms = ["glow" => bytes];   // its own block: Glow.params.glow.write(...)
//
// A slot's parameters are the stage's of the same names (the material's
// block and textures, the frame's); the others are uniform blocks of the
// material's own, bound from material.uniforms by their parameter's name
// (params: the plain variant's writers, typed; the class is the material's
// own, made beside its module).
export declare class MaterialShader {
	// a TypeScript program's material (helder/scene's material(pbr.with({...})),
	// a definition: helder.typescript.lower's Definitions compiles the same
	// variants and passes them here, JSON)
	static script(json: string): MaterialShader;
	readonly plain: AnyShader;
	readonly normalMapped: AnyShader | null;
	readonly skinned: AnyShader;
	readonly instanced: AnyShader;
	readonly instancedNormalMapped: AnyShader | null;
	// the blocks of the material's own: its parameter's name, its slot, in each variant (in the order above)
	readonly blocks: Array<{ name: string; bindings: number[] }>;
}

// Named actions bound to input (Binding: keys, mouse buttons, screen
// regions, pairs of keys as axes, gamepads, fingers: touch zones, a look
// zone's drag, on-screen sticks and buttons), read once per simulation
// step so that input and the simulation agree (a press and its release
// within one step still count as a press):
//
//   var actions = new InputMap();
//   final move = new VirtualStick({zone: Zone.rect(0, 0.4, 0.5, 1), radius: 60});
//   final fire = new VirtualButton({zone: Zone.circle(0.88, 0.8, 40)});
//   actions.bind("jump", Key(0x20)).bind("jump", Region(0.75, 0.6, 1, 1));
//   actions.bind("moveX", KeyAxis(0xFF51, 0xFF53)).bind("moveX", Stick(move, 0)).bind("moveX", PadAxis(0, 1));
//   actions.bind("lookX", TouchDelta(0, Zone.rect(0.5, 0, 1, 1), 0.3)).bind("fire", Button(fire)).bind("fire", PadButton(7));
//   App.run(..., e -> actions.event(e));
//   clock.advance(dt, step -> {
//     actions.step();
//     if (actions.pressed("jump")) ...;
//     player.x += actions.axis("moveX") * speed * step;
//   });
//
// Bindings are data (rebind at run time with unbind and bind). Gamepads:
// PadButton and PadAxis, read at each step from helder.os.Gamepads (which
// Stages.frame polls; Gamepads.set feeds an on-screen stick). Fingers and
// pens: read at each step from helder.os.Pointers, each press taken by
// the first control whose zone it began in (sticks, buttons and Touch
// zones first, then TouchDelta's look zones), if nobody had it (not the
// ui's: a press on a ui button is the ui's, Pointer.owner), and held by it
// until it lifts or is cancelled (a cancel lets go: the player stops). A
// zone shared by bindings is one control (equal zones). The first finger
// or pen down that no control took (nor the ui) is the mouse's left
// button while it is down: Mouse(1) held, the Region bindings under it.
// Nothing is allocated per event or per step.
export declare class InputMap {
	constructor();
	// a stick's travel taken as rest (its axes' first 0.15)
	deadZone: number;
	bind(action: string, b: Binding): InputMap;
	// all of an action's bindings removed
	unbind(action: string): InputMap;
	// the window's size, for Region bindings (by default the event's window)
	// and the zones of a pointer without a window
	setSize(width: number, height: number): void;
	// an event from helder.os's loop
	event(e: Event): void;
	// a simulation step begins: what happened since the last one becomes
	// what pressed, released and held answer
	step(): void;
	// went down since the last step (also when it went up again)
	pressed(action: string): boolean;
	released(action: string): boolean;
	// down at the step
	held(action: string): boolean;
	// an axis action's value now: KeyAxis, PadAxis and Stick from -1 to 1,
	// plus TouchDelta's drag over the last step (points times its scale)
	axis(action: string): number;
	// two axes as a vector (x right, y up), of length 1 at most
	stick(x: string, y: string): Vec2;
}

// InputMap's bindings as functions, for TypeScript programs (helder/scene:
// a Binding is an enum, which TypeScript does not construct):
// actions.bind("jump", Bindings.key(0x20)).
export declare class Bindings {
	static key(key: number): Binding;
	static mouse(button: number): Binding;
	static region(x0: number, y0: number, x1: number, y1: number): Binding;
	static keyAxis(negative: number, positive: number): Binding;
	static padButton(button: number): Binding;
	static padAxis(axis: number, scale: number): Binding;
}

// A fixed-timestep clock for a game's simulation, driven by the app loop's
// variable frames (helder.os.App.run): each frame's time goes into an
// accumulator and the simulation steps dt at a time while it holds a step,
// at most maxSteps a frame (after a stall the rest is dropped, so a slow
// frame does not make the next slower: no spiral). alpha is how far the
// accumulator is into the next step, 0 to 1, to draw between the last two
// states.
//
//   var clock = new FixedStep(1 / 60);
//   App.run(() -> {
//     clock.advance(frameSeconds, dt -> world.step(dt));
//     draw(world, clock.alpha);
//   }, onEvent);
export declare class FixedStep {
	constructor(dt?: number, maxSteps?: number);
	readonly dt: number;
	readonly maxSteps: number;
	// the simulated time: steps * dt
	readonly time: number;
	readonly steps: number;
	readonly alpha: number;
	// the time left over, under a step
	readonly accumulator: number;
	// frame seconds passed: runs step(dt) as many times as they hold (at
	// most maxSteps); returns how many
	advance(frame: number, step: (arg0: number) => void): number;
	// the state to carry over a reload (helder.dev.Hot): steps and what is left
	save(): { steps: number; accumulator: number };
	restore(s: { steps: number; accumulator: number }): void;
}

// A GPU device rendering to one Surface (a window, or headless), with a
// depth buffer of the colour target's size. Resources are created up front;
// a frame is beginFrame, passes recorded through the Encoder, endFrame
// (present). Main thread only. Under hxmc dev a device is disposed with the
// build (helder.dev.Hot.onDispose) when the next one is swapped in.
export declare class Device {
	// antialias: a window's frames multisampled, 4 samples a pixel (in the
	// browser the page's run option antialias decides when it is set);
	// headless surfaces stay single-sampled, readPixels reads the frame
	// resolved; render targets are multisampled by their own samples
	// (TextureDesc.samples, resolved through ColorTarget.resolve)
	static create(surface: Surface, options?: { antialias?: boolean }): Device;
	// whether it has a feature of the compute tier (Feature: Compute,
	// StorageTextures, Indirect): WebGPU, Metal, D3D11 at feature level
	// 11_0 and a GL ES 3.1 context do; WebGL2 and GL ES 3.0 do not (their
	// programs take the render stages' path)
	has(feature: Feature): boolean;
	// the frame's encoder (the same object each frame); null: no frame now
	// (a hidden window: Metal has no drawable for it), skip it
	beginFrame(): Encoder | null;
	// submits the frame and presents it
	endFrame(): void;
	// the frame's colour target as RGBA8, rows top to bottom (width * height
	// * 4 bytes into dst), after the passes and before endFrame; waits for
	// the GPU (tests and screenshots)
	readPixels(dst: Uint8Array): void;
	// the size of the colour target in pixels
	readonly width: number;
	// the size of the colour target in pixels
	readonly height: number;
	dispose(): void;
}

export declare class Surface {
	static headless(width: number, height: number): Surface;
	// the size in pixels
	readonly width: number;
	// the size in pixels
	readonly height: number;
}

// A top-level window, its size in points (pixels on X11). Its Surface
// carries the native handles for helder.gfx, its size in pixels. Cocoa on
// macOS (helder.os.cocoa.CocoaWindow), Win32 on Windows
// (helder.os.win32.Win32Window), a canvas in the browser (WebAssembly:
// helder.os.web.CanvasWindow, its size in CSS pixels), X11 elsewhere
// (helder.os.x11.X11Window); on Android the activity's window
// (helder.os.android.AndroidWindow: full screen, one per app, the size and
// title the system's), on iOS a UIWindow (helder.os.uikit.UIKitWindow: the
// same); on Linux with WAYLAND_DISPLAY set, Wayland's
// (helder.os.wayland.WaylandWindow; X11 where it cannot connect, or HELDER_X11=1).
export declare class Window {
	constructor(title: string, width: number, height: number, titlebar?: "standard" | "inset");
	readonly surface: Surface;
	// its title bar's text (the browser: the page's title)
	title: string;
	// its title bar's text (the browser: the page's title)
	readonly closed: boolean;
	// the surface's size in pixels
	readonly width: number;
	// the surface's size in pixels
	readonly height: number;
	// pixels per point (2 on a Retina display, the monitor's DPI / 96 on Windows,
	// the browser's devicePixelRatio; 1 on X11; iOS: the screen's native scale)
	readonly scale: number;
	close(): void;
}

// The app loop, callback driven (Cocoa, GTK and the browser own their
// loops): run calls onEvent for each pending event, then onFrame, until
// quit() or the last window closes. The loop is hxmc's own, polling the
// system's events without waiting (CocoaWindow on macOS, Win32Window on
// Windows, X11Window elsewhere); a frame's pace comes from the GPU's
// present (vsync), its time (App.frame) when it began. In the browser
// (WebAssembly) run returns at once, and main after it: each turn of the
// loop is then a frame of
// requestAnimationFrame (CanvasWindow). A frame with nothing to draw calls
// wait, so that an idle app sleeps until the system has an event for it.
// On Android the loop runs on the program's own thread (helder.os.android:
// NativeActivity's callbacks reach it through the thread's looper), and a
// frame is drawn only while the activity has its window and is not paused
// (otherwise the loop sleeps in the looper). On iOS the program runs inside
// UIKit's loop (helder.os.uikit.UIKitApp): each turn runs the main run loop
// without waiting, and draws only while the app is active (not in the
// background, nor inactive: otherwise it sleeps in the run loop). On both
// the frames are the display's: a turn that may draw asks for the next
// vsync (Android's Choreographer, helder.os.android.Vsync; iOS's
// CADisplayLink) and sleeps until it comes (or an event does), then the
// next turn draws the frame, App.frame its vsync's time. A frame that
// waits (App.wait: nothing to draw) asks for none until it has slept, so
// an idle app sleeps as elsewhere; the background, a window lost, pause
// them (App.frame.pause: the next delta a period). Each turn begins a
// frame of Pointers' (Pointers.step) before its events.
//
// helder.async's loop (the main thread's, once something made it: a task
// launched, a job run) runs on the app's: a turn of it in each turn of the
// app's, after the events and before the frame, and wait bounded by its next
// timer and woken by its I/O and by other threads' posts (a job's reply):
// X11's wait polls the loop's descriptors with the connection's, the others
// wait at most 10 ms while I/O or a post may come. While there are no frames
// (Android and iOS in the background) the loop still turns; in the browser
// the page turns it between frames too, and while a hidden tab has none.
export declare class App {
	// errors out of run's frames and events, and tasks' nobody hears of
	// (helder.async.Errors): handled (true), the loop goes on; otherwise, or
	// with none, the program fails as before
	static onError: ((error: unknown, source: string) => boolean) | null;
	static run(onFrame: () => void, onEvent: (arg0: Event) => void): void;
}

// One event, preallocated and refilled for each dispatch (App.run): copy
// what must outlive the callback.
export declare class Event {
	kind: EventKind;
	window: Window;
	// KeyDown, KeyUp: the key (an X11 KeySym for now, also on macOS and
	// Windows: Latin-1 keys are their unshifted character code, Escape 0xFF1B)
	key: number;
	// the pointer (Mouse*, Pointer*: rounded, from the top left) or the new size (Resize), in pixels
	x: number;
	// the pointer (Mouse*, Pointer*: rounded, from the top left) or the new size (Resize), in pixels
	y: number;
	// MouseDown, MouseUp: 1 left, 2 middle, 3 right
	button: number;
	// Scroll: pixels toward the right and the bottom
	deltaX: number;
	// Scroll: pixels toward the right and the bottom
	deltaY: number;
	// keys, mouse buttons and scrolls: the modifiers held (Mods: Shift, Control, Alt, Meta: the Windows or Command key)
	mods: number;
}

// What helder/scene's Node (src/helder/scene/index.ts, a class of the
// program's over a node's handle) calls for TypeScript programs: Node's
// accessors and methods, whose Haxe ones are inline (a node is an Int:
// World), as functions. A node crosses as helder/scene's Node, its id the
// handle (helder.typescript.lower.Haxe's NODE).
export declare class Script {
	static world(n: Node): World;
	static valid(n: Node): boolean;
	static name(n: Node): string;
	static setName(n: Node, v: string): void;
	static position(n: Node): Vec3;
	static setPosition(n: Node, v: Vec3): void;
	static rotation(n: Node): Quat;
	static setRotation(n: Node, v: Quat): void;
	static scale(n: Node): Vec3;
	static setScale(n: Node, v: Vec3): void;
	static visible(n: Node): boolean;
	static setVisible(n: Node, v: boolean): void;
	static parent(n: Node): Node;
	static add(n: Node, child: Node): Node;
	static detach(n: Node): void;
	// its children's ids, in order
	static children(n: Node): number[];
	static localMatrix(n: Node): Mat4;
	static worldMatrix(n: Node): Mat4;
	static worldPosition(n: Node): Vec3;
	static setMatrix(n: Node, m: Mat4): void;
	static lookAt(n: Node, target: Vec3): void;
	static lookAtUp(n: Node, target: Vec3, up: Vec3): void;
	static find(n: Node, name: string): Node;
	static shown(n: Node): boolean;
	static dispose(n: Node): void;
	// a material's block of its own (a shader of its own's: MaterialShader.blocks) by its parameter's name
	static materialBlock(m: Material, name: string, bytes: Uint8Array): void;
}
