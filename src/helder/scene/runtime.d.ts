// helder.scene for TypeScript programs (helder.typescript): what
// helder/scene (src/helder/scene/index.ts, with its Node, pbr and material)
// exports of helder's Haxe classes. A World of nodes (Node: helder/scene's
// class over a node's handle, its members Script's), cameras, lights,
// meshes (Shapes, Geometry's shapes and Curve3, MeshRenderer, InstancedMesh,
// Sprites) and materials (Material's factories: toon, lambert, unlit...;
// the glTF extensions' fields, drawn by Physical, Transmission), glTF models (Model,
// helder/asset's model(path) loads one; GltfScene), the renderer and its
// post chain (PostProcess: its effects Ssao, Dof, Outline, Lut, Ssr,
// MotionBlur, GodRays, Taa, Smaa; the view buffers they read, ViewBuffers), occlusion
// culling (Occlusion), lines with width and debug drawing
// (Lines, LineRenderer, DebugDraw, the helpers), rays cast at triangles
// (world.raycast: Hit, HitList, RaycastOptions, Bvh), text in the world
// (Text3D), lights at scale and their shadows (ClusteredLights and its
// grid, Clusters; Shadows' atlas, a light's castShadows and shadow), levels
// of detail (Lod, InstanceCulling), indirect light (Environment, prefiltered
// by helder; Sh, LightProbe, ProbeGrid, ReflectionProbe and Probes; Lightmap
// and Lightmaps; AreaLights), input
// actions (InputMap, Bindings), a fixed simulation step, and what a scene is
// drawn with: a window, its device (or a headless one), the app's loop. A
// program imports helder/scene, not this module.
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.
import type {Asset, FontFile, Image} from "helder/asset";
import type {Mat4, Quat, Vec2, Vec3, Vec4} from "helder/gfx";
import type {Node} from "helder/scene";
import type {Read} from "helder/view";

declare const __haxe: {World: "helder.scene.World", Camera: "helder.scene.Camera", CameraRay: "helder.scene.Camera.CameraRay", Aabb: "helder.scene.math.Aabb", Light: "helder.scene.render.Light", Renderer: "helder.scene.render.Renderer", Shadows: "helder.scene.render.Shadows", Fog: "helder.scene.render.Fog", Material: "helder.scene.render.Material", UvTransform: "helder.scene.render.Material.UvTransform", Physical: "helder.scene.render.Physical", Transmission: "helder.scene.render.Transmission", MeshRenderer: "helder.scene.render.MeshRenderer", Shapes: "helder.scene.render.Shapes", Geometry: "helder.scene.render.Geometry", VertexData: "helder.scene.render.VertexData", Curve3: "helder.scene.math.Curve3", InstancedMesh: "helder.scene.render.InstancedMesh", Sprites: "helder.scene.render.Sprites", Model: "helder.scene.render.Model", MaterialShader: "helder.scene.render.MaterialShader", PostProcess: "helder.scene.render.PostProcess", Ssao: "helder.scene.render.Ssao", Dof: "helder.scene.render.Dof", Outline: "helder.scene.render.Outline", Lut: "helder.scene.render.Lut", ViewBuffers: "helder.scene.render.ViewBuffers", Ssr: "helder.scene.render.Ssr", MotionBlur: "helder.scene.render.MotionBlur", GodRays: "helder.scene.render.GodRays", Taa: "helder.scene.render.Taa", Smaa: "helder.scene.render.Smaa", Occlusion: "helder.scene.render.Occlusion", Lines: "helder.scene.render.Lines", LineRenderer: "helder.scene.render.LineRenderer", DebugDraw: "helder.scene.render.DebugDraw", Helper: "helder.scene.render.Helper", AxesHelper: "helder.scene.render.AxesHelper", GridHelper: "helder.scene.render.GridHelper", BoundsHelper: "helder.scene.render.BoundsHelper", LightHelper: "helder.scene.render.LightHelper", CameraHelper: "helder.scene.render.CameraHelper", SkeletonHelper: "helder.scene.render.SkeletonHelper", Hit: "helder.scene.render.Hit", HitList: "helder.scene.render.Hit.HitList", RaycastOptions: "helder.scene.render.Hit.RaycastOptions", Raycaster: "helder.scene.render.Raycaster", Bvh: "helder.scene.render.Bvh", Text3D: "helder.scene.render.Text3D", ClusteredLights: "helder.scene.render.ClusteredLights", Clusters: "helder.scene.render.Clusters", Lod: "helder.scene.render.Lod", InstanceCulling: "helder.scene.render.InstanceCulling", Environment: "helder.scene.render.Environment", Sh: "helder.scene.render.Sh", LightProbe: "helder.scene.render.LightProbe", ProbeGrid: "helder.scene.render.ProbeGrid", ReflectionProbe: "helder.scene.render.ReflectionProbe", Probes: "helder.scene.render.Probes", Lightmap: "helder.scene.render.Lightmap", Lightmaps: "helder.scene.render.Lightmaps", AreaLights: "helder.scene.render.AreaLights", InputMap: "helder.scene.input.InputMap", Bindings: "helder.scene.input.Bindings", FixedStep: "helder.scene.FixedStep", Device: "helder.gfx.Device", Surface: "helder.os.Surface", Window: "helder.os.Window", App: "helder.os.App", Event: "helder.os.Event", Script: "helder.scene.Script", __module: "helder.scene.TypeScript"};

// a handle (Buffer); TypeScript's a number of its own kind
export type Texture = number & {readonly textureBrand: never};

// A shader: what shader({vertex, fragment}) makes (ShaderMath.shader, a
// definition: README.md in src/helder/compiler), its stages' functions
// compiled at build time:
//
//   @:structInit @:publicFields class Vertex { var pos:Vec2; var color:Vec3; }
//   @:structInit @:publicFields class Varyings { var pos:Vec4; var color:Vec3; }
//
//   final TriangleShader = shader({
//     vertex: function(v:Vertex):Varyings return {pos: position(vec4(v.pos, 0, 1)), color: v.color},
//     fragment: function(i:Varyings):Vec4 return vec4(i.color, 1)
//   });
//   device.createPipeline(TriangleShader.pipeline({topology: Triangles}));
//
// The vertex function takes a vertex (its fields are the vertex buffer's
// attributes, in order) and returns the varyings, one of them built
// position(...): the clip-space position; the fragment function takes the
// same varyings (its first parameter's type may be left out) and returns
// the colour. Either may take one more parameter, an object of parameters
// (an anonymous structure: function(i:Varyings, p:{cam:Camera, image:Texture2D})),
// whose fields, read as p.cam, are uniform blocks (structs of scalars,
// vectors and matrices) and textures (Texture2D, read with sample(t, uv)),
// each at a slot (Encoder.setUniforms, setTexture): 0, 1, ... in order of
// appearance, the vertex stage's first, a block shared by both stages (the
// same struct) or a texture (the same name) once. Structs
// are @:structInit classes (objects in CPU code, whose math-type fields are
// stored inline, so that vertex Arrays hold them as they are) or typedefs
// of anonymous structures. The functions they call are any static or
// module-level functions of the same kinds of values (helpers, as the
// stages are: they run as CPU code too). The shader has:
//
//   vertexCode, fragmentCode   the stages' ShaderCode, in the languages of
//                              the target (-D helder.gfx.shaders=glsl,wgsl,msl,hlsl
//                              or all to choose)
//   layout                     the vertex buffer's layout (Float32 attributes,
//                              packed in the vertex type's order)
//   uniforms                   the uniform blocks: name, binding (the slot), size (std140)
//   textures                   the textures: the parameter's name, binding (the slot)
//   pipeline(?options)         a PipelineDesc of all three (Device.createPipeline
//                              compiles the code)
//   vertexBytes(vertices)      the vertex buffer's contents
//   params.<name>              a field of the stages' objects of parameters:
//                              a uniform block's writer (UniformWriter:
//                              .write(u, bytes, offset), std140) or a
//                              texture's slot (TextureSlot: .binding)
//   vertex, fragment           the stages as CPU code
//   uniformBytes(), uniformBinding, bind(encoder)
//                              the block of the uniform(...)s the stages
//                              read (ShaderMath.uniform), their values now
//
// (Each shader is a class of its own extending Shader, made by the
// definition beside its module: <Module>_<name>, its stages' fields of
// their exact function types, which hxmc calls directly.)
//
// The conventions, the same on every back end (WebGPU's, D3D's and
// Metal's; the GLSL makes GL match): the position is in clip space, x
// right and y up, z from 0 (near) to w (far), its front faces counter-
// clockwise; in the fragment stage it is the fragment's position in pixels
// from the target's top left (pixel centres at .5) and its depth (0..1) in
// z; a texture's v = 0 is its first row, the top (TextureDesc), and
// readPixels returns rows top to bottom. Mat4's perspective and
// orthographic projections map to this clip space.
export declare class Shader<V, P> {
	private readonly shader: never;
}

// What a node draws (node.mesh): primitives, each a vertex buffer in the
// renderer's layout (PbrVertex: position, normal, uv; 32 bytes a vertex),
// triangles' indices and a material, and the bounds of them all. Each
// primitive keeps its data on the CPU too (Primitive.data: the same bytes
// the GPU was given, for casting rays at its triangles: Raycaster), unless
// Mesh.keepCpu is off when it is made.
export declare class Mesh {
	private readonly mesh: never;
}

// Records a frame's passes: one per device, reused (no allocation per frame),
// into the device's commands, run at each pass's end (Device). What it
// records is counted in FrameCounts.
export declare class Encoder {
	private readonly encoder: never;
}

export type EventKind = "none" | "close" | "resize" | "key-down" | "key-up" | "mouse-move" | "mouse-down" | "mouse-up" | "text-input" | "redraw" | "text-editing" | "scroll" | "scale-change" | "suspend" | "resume" | "pointer-down" | "pointer-move" | "pointer-up" | "pointer-cancel" | "drop" | "text-replace" | "text-select";

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
// 11_0: cs_5_0) and GL ES 3.1 (Android's floor) have the first three, and
// some of them Subgroups; WebGL2 and a GL ES 3.0 context none, the render
// stages' path (helder.scene's fallbacks) staying theirs.
export type Feature = "compute" | "storage-textures" | "indirect" | "subgroups";

// the curve from linear light to the display
export type ToneMap = "agx" | "aces" | "clamp";

// antialiasing in post (PostProcess.antialias), beside a <Scene>'s MSAA:
// None, or Fxaa (in the composite: its read of the scene along the edges);
// SMAA and TAA are effects of their own (post.smaa, post.taa: an enum's
// value set at run time would link every technique's passes)
export type Antialias = "none" | "fxaa";

// how depth of field's circle grows (Dof.focus, Dof.tiltShift)
export type DofMode = "focus" | "tilt-shift";

// a line's width: in pixels on the screen, or in the world's units
export type LineUnits = "pixels" | "world";

// where a polyline's segments meet
export type LineJoin = "miter" | "round" | "bevel";

// a line's ends
export type LineCap = "butt" | "round" | "square";

// what kind of light a Light is
export type LightKind = "directional" | "point" | "spot" | "hemisphere" | "rect-area" | "disc-area";

// what a Lightmap holds: the ambient light alone (the lights added), or all of it
export type LightmapMode = "indirect" | "all";

// how sprites face the camera (Sprites.mode)
export type SpriteMode = "spherical" | "axis" | "fixed";

// how a see-through material is blended over what is behind (Material.blend)
export type MaterialBlend = "none" | "alpha" | "additive" | "premultiplied" | "multiply";

export type BoxOptions = { flat?: boolean; tangents?: boolean; width?: number; height?: number; depth?: number; widthSegments?: number; heightSegments?: number; depthSegments?: number };

export type CapsuleOptions = { flat?: boolean; tangents?: boolean; radius?: number; height?: number; capSegments?: number; radialSegments?: number; heightSegments?: number };

export type CircleOptions = { flat?: boolean; tangents?: boolean; radius?: number; segments?: number; thetaStart?: number; thetaLength?: number };

// ClusteredLights' options (new ClusteredLights(device, options))
export type ClusteredOptions = { maxLights?: number; grid?: { x?: number; y?: number; z?: number }; maxPerCell?: number; gpu?: boolean };

export type ConeOptions = { flat?: boolean; tangents?: boolean; radius?: number; height?: number; radialSegments?: number; heightSegments?: number; openEnded?: boolean; thetaStart?: number; thetaLength?: number };

export type CylinderOptions = { flat?: boolean; tangents?: boolean; radiusTop?: number; radiusBottom?: number; height?: number; radialSegments?: number; heightSegments?: number; openEnded?: boolean; thetaStart?: number; thetaLength?: number };

// what Geometry.extrude takes (each optional): its depth (1), a bevel's
// size (0: none) and steps (3), the curves' flattening tolerance (0.01, the
// path's units), the fill rule that finds its holes (non-zero; evenOdd),
// and every generator's flat and tangents
export type ExtrudeOptions = { depth?: number; bevelSize?: number; bevelSegments?: number; tolerance?: number; evenOdd?: boolean; flat?: boolean; tangents?: boolean };

// a curve's frames (Curve3.frames): as many tangents, normals and binormals
export type Frames = { tangents: Vec3[]; normals: Vec3[]; binormals: Vec3[] };

export type GodRaysOptions = { intensity?: number; density?: number; decay?: number; samples?: number; falloff?: number };

// a GridHelper's (each optional): 10 wide in 10 cells, fading at 30
export type GridOptions = { size?: number; divisions?: number; fade?: number; color?: Vec4; majorColor?: Vec4 };

export type LatheOptions = { flat?: boolean; tangents?: boolean; segments?: number; phiStart?: number; phiLength?: number };

// a light's shadow (light.shadow = {size: 512, radius: 1.5}; a field left
// out: Shadows' default)
export type LightShadow = { size?: number; bias?: number; normalBias?: number; radius?: number; strength?: number; cached?: boolean };

// what Lines are made with (each optional): 2 pixels wide, mitred, butt
// ends, solid, depth tested, opaque, tone mapped, none drawn
export type LinesOptions = { segments?: boolean; width?: number; widthUnits?: LineUnits; join?: LineJoin; cap?: LineCap; dash?: number; gap?: number; dashOffset?: number; closed?: boolean; onTop?: boolean; transparent?: boolean; toneMapped?: boolean; count?: number };

// LocalShadows' options (shadows.local(options))
export type LocalShadowsOptions = { atlas?: number; maxLocal?: number; tileSize?: number };

// a level of a Lod ({mesh: m, until: 0.1}): its mesh, the least share of
// the view's height it is drawn at (null: 0, however far)
export type LodLevel = { mesh: Mesh; until?: number };

// Material.matcap's: also the matcap, a lit sphere's picture (sRGB)
export type MatcapOptions = { name?: string; color?: Vec4; texture?: Texture; metallic?: number; roughness?: number; emissive?: Vec3; doubleSided?: boolean; blend?: MaterialBlend; alphaCutoff?: number; fog?: boolean; castShadows?: boolean; toneMapped?: boolean; matcap: Texture };

// what a material is made from (Material's factories): each field the
// material's of the same meaning, its default where not given (color the
// base colour, linear; texture the base colour's, sRGB)
export type MaterialOptions = { name?: string; color?: Vec4; texture?: Texture; metallic?: number; roughness?: number; emissive?: Vec3; doubleSided?: boolean; blend?: MaterialBlend; alphaCutoff?: number; fog?: boolean; castShadows?: boolean; toneMapped?: boolean };

export type MotionBlurOptions = { strength?: number; samples?: number; max?: number; objects?: boolean };

// Material.phong's: also three's shininess (30 by default)
export type PhongOptions = { name?: string; color?: Vec4; texture?: Texture; metallic?: number; roughness?: number; emissive?: Vec3; doubleSided?: boolean; blend?: MaterialBlend; alphaCutoff?: number; fog?: boolean; castShadows?: boolean; toneMapped?: boolean; shininess?: number };

export type PlaneOptions = { flat?: boolean; tangents?: boolean; width?: number; height?: number; widthSegments?: number; heightSegments?: number };

export type RingOptions = { flat?: boolean; tangents?: boolean; innerRadius?: number; outerRadius?: number; thetaSegments?: number; phiSegments?: number; thetaStart?: number; thetaLength?: number };

export type SmaaOptions = { threshold?: number };

export type SphereOptions = { flat?: boolean; tangents?: boolean; radius?: number; widthSegments?: number; heightSegments?: number; phiStart?: number; phiLength?: number; thetaStart?: number; thetaLength?: number };

// what Sprites are made with (each optional): how they face the camera
// (Spherical), the axis Axis turns about (y), the atlas' columns and rows
// (1 by 1), the sprites shown (all)
export type SpritesOptions = { mode?: SpriteMode; axis?: Vec3; columns?: number; rows?: number; count?: number };

export type SsaoOptions = { radius?: number; intensity?: number; samples?: number; slices?: number; halfRes?: boolean };

export type SsrOptions = { intensity?: number; maxDistance?: number; thickness?: number; steps?: number; maxRoughness?: number; halfRes?: boolean };

export type TaaOptions = { blend?: number };

// what a Text3D is made with (each optional): the em's height (0.3), a
// depth (0: flat, double-sided), a bevel, the lines' alignment (0.5:
// centred), height and letter spacing (Geometry.text's), its colour
// (white), lit (false: unlit, its colour as given) or a material of its
// own, turned to the camera (billboard), casting shadows (false)
export type Text3DOptions = { size?: number; depth?: number; bevelSize?: number; align?: number; lineHeight?: number; letterSpacing?: number; color?: Vec4; lit?: boolean; material?: Material; billboard?: boolean; castShadows?: boolean };

// what Geometry.text takes (each optional): the em's size (1), its depth
// (0: flat), a bevel (as extrude's), the lines' height (1.2 ems), the
// letters' spacing (ems), the lines' alignment (0 left, 0.5 centred, 1
// right), the curves' tolerance (the scene's units: size / 200)
export type TextGeometryOptions = { size?: number; depth?: number; bevelSize?: number; bevelSegments?: number; lineHeight?: number; letterSpacing?: number; align?: number; tolerance?: number; flat?: boolean; tangents?: boolean };

// Material.toon's: also its bands and its shade
export type ToonOptions = { name?: string; color?: Vec4; texture?: Texture; metallic?: number; roughness?: number; emissive?: Vec3; doubleSided?: boolean; blend?: MaterialBlend; alphaCutoff?: number; fog?: boolean; castShadows?: boolean; toneMapped?: boolean; steps?: number; shade?: Vec3 };

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
	// the nearest triangle a ray from origin along dir meets, into hit (a
	// Hit the program keeps: nothing allocated a cast); false when none.
	// options (kept too): a distance, layers, bounds alone, backs
	// (helder.scene.render.Raycaster)
	raycast(origin: Vec3, dir: Vec3, hit: Hit, options?: RaycastOptions): boolean;
	// every triangle the ray meets into hits, nearest first; their count
	raycastAll(origin: Vec3, dir: Vec3, hits: HitList, options?: RaycastOptions): number;
}

// A camera, a component of a node (Camera.attach(node, camera)): it looks
// down the node's -z, its up the node's +y. Projections are gfx's
// (Mat4.perspective, Mat4.orthographic: clip space y up, z from 0 at the
// near plane). Several cameras may look at one world (split screens,
// shadow views, XR's two eyes): each is drawn by its own Renderer.draw.
export declare class Camera {
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
	rayInto(x: number, y: number, aspect: number, out: CameraRay): CameraRay;
}

// a ray through the view to fill (Camera.rayInto): its origin on the near
// plane, its dir of unit length
export declare class CameraRay {
	constructor();
	origin: Vec3;
	dir: Vec3;
}

// An axis-aligned box, min to max (an empty one: min above max, Aabb.empty),
// immutable as the math types are.
export declare class Aabb {
	constructor(min: Vec3, max: Vec3);
	static empty(): Aabb;
	// the box around points given as x, y, z triples
	static ofPoints(xyz: number[]): Aabb;
	// An axis-aligned box, min to max (an empty one: min above max, Aabb.empty),
	// immutable as the math types are.
	readonly min: Vec3;
	readonly max: Vec3;
	isEmpty(): boolean;
	center(): Vec3;
	size(): Vec3;
	union(b: Aabb): Aabb;
	contains(p: Vec3): boolean;
	intersects(b: Aabb): boolean;
	// the box around this one transformed by m (Arvo's: the centre moved,
	// the extent through the matrix's absolute values)
	transform(m: Mat4): Aabb;
	// the distance along dir (any length: in its units) from origin to the
	// box, 0 from inside; -1 when the ray misses it (the slab test)
	ray(origin: Vec3, dir: Vec3): number;
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
//   RectArea      a rectangle (width along its node's x, height along its
//                 y) shining down its node's -z, from its front only: a
//                 window, a panel, a screen (three's RectAreaLight); color
//                 times intensity its radiance (three's units), windowed to
//                 nothing at its range
//   DiscArea      a disc of radius, likewise
//
// Area lights are shaded with linearly transformed cosines (Heitz et al.)
// with AreaLights (renderer.use(new AreaLights(device)): the standard
// material's area variants); without it, and by other materials, as a
// point light at their centre. They cast no shadows.
//
// The renderer takes the world's first directional light (its cascades
// Shadows'), its first hemisphere light, and up to MAX_LIGHTS point and
// spot lights a frame (the nearest the view and the brightest): each draw
// lit by the eight that reach its bounds most, or each pixel by its
// cell's with ClusteredLights. A light casts shadows with Shadows when
// castShadows (a directional light by default, a point or spot light when
// asked: Shadows' tiles, within its budget), filtered as shadow says.
export declare class Light {
	static directional(color: Vec3, intensity: number): Light;
	static pointLight(color: Vec3, intensity: number, range: number): Light;
	// a point light shining down its node's -z within a cone: full inside
	// inner, fading to nothing at outer (radians from the axis)
	static spot(color: Vec3, intensity: number, range: number, inner: number, outer: number): Light;
	// three's HemisphereLight: the sky's colour from above, the ground's from
	// below, both times intensity (in place of the renderer's sky and ground)
	static hemisphere(sky: Vec3, ground: Vec3, intensity?: number): Light;
	// three's RectAreaLight: a rectangle of width (its node's x) by height
	// (its y) shining down its node's -z (color times intensity its
	// radiance), reaching range
	static rectArea(color: Vec3, intensity: number, width: number, height: number, range?: number): Light;
	// a disc of radius shining down its node's -z, reaching range
	static discArea(color: Vec3, intensity: number, radius: number, range?: number): Light;
	static attach(node: Node, light: Light): Light;
	static of(node: Node): Light | null;
	readonly kind: LightKind;
	color: Vec3;
	intensity: number;
	// a point or spot light's reach (scene units)
	range: number;
	// a spot light's cones (radians from its axis)
	innerCone: number;
	outerCone: number;
	// a hemisphere light's colour from below (linear; color is the sky's)
	groundColor: Vec3;
	// an area light's size: a rectangle's width and height, a disc's radius in width
	width: number;
	height: number;
	// whether it casts shadows (Shadows): a directional light's first of
	// the world (its cascades), a point or spot light's (its tiles of the
	// atlas: a spot's one, a point's six) while within shadows.maxLocal
	castShadows: boolean;
	// its shadow's size and filter (null: Shadows' defaults)
	shadow: LightShadow | null;
	// whether it shines from a place (a point, spot or area light: the
	// frame's local lights)
	readonly local: boolean;
	// whether it is an area light (rect or disc)
	readonly area: boolean;
}

// Draws a world's meshes (MeshRenderer) as seen by a camera, lit by its
// first directional Light (a world without lights: the renderer's sun),
// its point and spot Lights (the frame's MAX_LIGHTS most important to the
// view, FrameLights: each draw lit by the eight that reach it most, or
// each pixel by its cell's with ClusteredLights) and an ambient from the
// sky and the ground, with PbrShader. The passes a frame records, in order
// (all but the main one opted in): instance culling (InstanceCulling: a
// compute pass where the device has one), the shadow atlas (Shadows), the
// lights' cells (ClusteredLights: a compute pass where it can), the view
// buffers' prepass (ViewBuffers: depth, normals, roughness and selection,
// for post's effects), the screen's ambient occlusion (post.ao: Ssao), the
// main pass, then the AfterPass hooks; post (PostProcess) after, into the
// image shown. Two stages:
//
//   extract   the world's meshes into a flat draw list: the nodes shown,
//             their level (Lod) and their visible range, their bounds
//             inside the camera's view, a draw per primitive sorted by
//             pipeline, material and primitive; runs of one primitive
//             become one instanced draw (PbrInstancedShader: the matrices
//             in an instance buffer), each run's light list from its
//             bounds; the seam for threads
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
	// where a variant's slots of a material's own blocks begin (slotsOf's length)
	static readonly OWN: number;
	// a shader's slots for its blocks and textures, in the renderer's order:
	// frame, object (-1: none), material, base colour, shadow atlas, skin,
	// joints, metallic-roughness, emissive, occlusion, normal, the cluster map
	// (ClusteredLights'), the environment map, the screen's ambient
	// occlusion; a physical shader's (0: one, -1: not), its two maps, the
	// frame behind (Transmission's); the frame's lights; then a material's
	// own blocks (OWN on)
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
	clearColor: Vec4;
	// the last draw's draws in its main pass and primitives culled
	// (statistics); its shadow maps' draws (Shadows: every cascade's; 0
	// without); every renderer's by pass in helder.gfx.FrameCounts
	// (sceneDraws, shadowDraws, postDraws: PostProcess.draws)
	readonly draws: number;
	readonly culled: number;
	// the last draw's primitives not drawn as hidden behind others
	// (Occlusion: its queries of the frames before; 0 without)
	readonly occluded: number;
	readonly shadowDraws: number;
	// the view buffers' prepass draws (ViewBuffers; 0 without)
	readonly prepassDraws: number;
	// a sub-pixel offset of the projection this frame, in pixels of the
	// target (x right, y down; 0, 0: none): temporal antialiasing's
	// (post.taa: Taa sets it before each frame), the view buffers' and
	// the main pass's alike; the motion the view buffers record leaves it out
	jitter: Vec2;
	// the frames drawn (each draw one)
	readonly frames: number;
	// the last draw's main pass split for Transmission's copy (1: the frame
	// behind its see-through surfaces copied; statistics)
	readonly splits: number;
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
	post: PostProcess | null;
	// a pipeline for what it draws into: the frame, or drawInto's targets
	// (RGBA8, Depth32F, its samples); its features' and a program's own
	// passes inside its frame (inject) make theirs with it
	createPipeline(d: { vertex?: number; fragment?: number; program?: { vertex: { glsl?: string; msl?: string; hlsl?: string; wgsl?: string; bindings?: Array<{ name: string; slot: number; kind: number; size?: number; index?: number; format?: number; dimension?: number }>; workgroupSize?: number[]; emulated?: { glsl?: string; msl?: string; hlsl?: string; wgsl?: string } }; fragment: { glsl?: string; msl?: string; hlsl?: string; wgsl?: string; bindings?: Array<{ name: string; slot: number; kind: number; size?: number; index?: number; format?: number; dimension?: number }>; workgroupSize?: number[]; emulated?: { glsl?: string; msl?: string; hlsl?: string; wgsl?: string } } }; layout: Array<{ stride: number; attributes: Array<{ location: number; format: number; offset: number }>; step?: number }>; topology?: number; cull?: number; blend?: number; depthCompare?: number; depthWrite?: boolean; colorFormat?: number; depthFormat?: number; samples?: number }): number;
	// draw into color (colorFormat, a render target) and depth (Depth32F, its size), an offscreen renderer's
	// (multisampled, samples > 1: color and depth of those samples, color
	// resolved into resolve, a single-sampled RGBA8 render target)
	// (layer: color's, a cube's face or a 2D array's layer)
	drawInto(enc: Encoder, world: World, camera: Camera, color: Texture, depth: Texture, width: number, height: number, resolve?: Texture, layer?: number): void;
	// what the frame's hooks get: the camera's view, the light (FrameInfo)
	readonly frame: unknown;
	// f runs at a point of each frame: BeforeOpaque, AfterOpaque and
	// AfterTransparent inside the frame's pass (draw with your own
	// pipelines, depth-tested against the scene; AfterTransparent after the
	// see-through surfaces too: what is drawn over everything), AfterPass
	// after it (passes of your own: an overlay), BeforePass before the
	// frame's passes (a texture of your own the frame reads)
	inject(point: number, f: (arg0: Encoder, arg1: unknown) => void): void;
	// turns on an optional feature (Shadows, Skinning, NormalMaps, Sky,
	// Environment, ClusteredLights, InstanceCulling); returns the renderer
	use(feature: unknown): Renderer;
	// records the frame's pass: world seen by camera (aspect: the target's,
	// by default the device's)
	draw(enc: Encoder, world: World, camera: Camera, aspect?: number): void;
	// the draw list: each shown mesh inside the view (at its level: Lod; in
	// its visible range), a draw per primitive, sorted (seen from the centre
	// of the view's near plane: the camera, a near plane's distance off)
	extract(world: World, viewProj: Mat4): void;
	dispose(): void;
}

// The shadow system, opted in (renderer.use(new Shadows(device))): one
// atlas (an R32F texture, each texel a depth from its light, and its depth
// buffer) holding, as tiles, the sun's cascades and, opted in, the point
// and spot lights' shadows, drawn before the frame's pass and read by the
// standard material.
//
//   the sun     the world's first directional light that casts
//               (Light.castShadows, a directional light's default; the
//               renderer's sun without lights): one cascade of size x size
//               fitted to the casters' bounds, or two (Shadows.cascaded,
//               whose fitting code a program without it does not link):
//               the first fitted to the camera's view up to split metres
//               (its bounding sphere, moved by whole texels: steady as the
//               camera moves), sharp near the camera, the second the whole
//               scene's, read beyond the first; a 3x3 percentage-closer
//               filter or a soft one (soft: a disc of taps, a blocker
//               search, sharper where the shadow meets its caster)
//   local       shadows.local({atlas, maxLocal, tileSize}): the point and
//               spot lights that cast, their tiles in a square of the atlas
//               beside the cascades (LocalShadows: a spot light's one, a
//               point light's six, a budget, kept while nothing moves); a
//               program that never asks links none of it
//
// The casters: every shown mesh whose material casts (Material.castShadows,
// InstancedMesh.castShadows), a primitive's in one instanced draw a tile
// (their matrices in an instance buffer written once for every tile), a
// local tile's culled by its frustum, each tile's draws kept to its
// rectangle (ShadowShader). Nothing is allocated a frame. A program that
// never makes a Shadows links none of this but the material's lookup of a
// 1x1 map that shadows nothing.
export declare class Shadows {
	// one cascade of size texels
	constructor(device: Device, size?: number);
	// two cascades, the first reaching split metres from the camera
	static cascaded(device: Device, size?: number, split?: number): Shadows;
	// the local lights' tiles a frame at most (the frame's lights' texture's tile rows)
	static readonly MAX_TILES: number;
	readonly device: Device;
	// a cascade's tile, in texels
	readonly size: number;
	// 1, or 2 (Shadows.cascaded)
	readonly cascades: number;
	// how far from the camera the first of two cascades reaches (metres)
	split: number;
	// the sun's depth offset against shadow acne (in the whole scene's map's
	// 0..1 depth; the first of two cascades', as many of its texels)
	bias: number;
	// the shadows' strength, 0 (none) to 1 (no direct light at all)
	strength: number;
	// the sun's soft filter (soft): the widest penumbra's radius in metres
	// (0: the 3x3 filter), its taps a point (8 for phones, 16, 32), and how
	// much the penumbra widens a metre from its caster (0: the radius
	// everywhere, no blocker search)
	softRadius: number;
	softSamples: number;
	softSpread: number;
	// the point and spot lights' shadows (local: null without)
	readonly locals: unknown | null;
	// the atlas (made again, wider, when a local light first casts) and its size
	readonly atlas: Texture;
	readonly atlasWidth: number;
	readonly atlasHeight: number;
	// the last frame's draws into the atlas (every tile's: a primitive's
	// casters one instanced draw a tile, a skinned caster one draw)
	readonly draws: number;
	// the last frame's sun's view-projections (the first cascade's, the second's)
	readonly viewProj: Mat4;
	readonly viewProjFar: Mat4;
	// the point and spot lights' shadows on (returns the shadows): their
	// tiles in a square of the atlas atlas texels wide (1024), at most
	// maxLocal lights a frame (4), a spot light's tile tileSize texels (512;
	// a point light's faces half); the lights that cast, Light.castShadows
	local(options?: LocalShadowsOptions): Shadows;
	// the sun's soft filter on (returns the shadows): taps on a disc out to
	// radius metres, samples a point (8: phones; 16; 32), and with a spread
	// a blocker search first, the penumbra growing by spread a metre from
	// its caster up to the radius (contact hardening: PCSS); spread 0, the
	// radius everywhere
	soft(radius?: number, samples?: number, spread?: number): Shadows;
	attach(renderer: Renderer): void;
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
	static readonly SHEEN: number;
	static readonly SPECULAR: number;
	static readonly CLEARCOAT: number;
	static readonly TRANSMISSION: number;
	static readonly IRIDESCENCE: number;
	static readonly ANISOTROPY: number;
	static readonly UV_SETS: number;
	// the material's index (draws sort by it; an index into a material buffer later)
	readonly id: number;
	name: string;
	baseColor: Vec4;
	metallic: number;
	roughness: number;
	emissive: Vec3;
	baseColorTexture: Texture | null;
	// glTF's other maps: roughness (green) and metallic (blue), times the
	// factors; emitted colour (sRGB), times emissive; ambient occlusion (red)
	metallicRoughnessTexture: Texture | null;
	emissiveTexture: Texture | null;
	occlusionTexture: Texture | null;
	// a tangent-space normal map (drawn with NormalMaps, on primitives with
	// tangents), its x and y scaled by normalScale
	normalTexture: Texture | null;
	normalScale: number;
	doubleSided: boolean;
	// how its textures are read (null: the renderer's: linear, mip-mapped,
	// repeating; glTF's samplers otherwise)
	sampler: number | null;
	// see-through (glTF's alphaMode BLEND): blended over what is behind,
	// drawn after the opaque surfaces, farthest first, without writing
	// depth; by the base colour's alpha (Alpha), added to what is behind
	// (Additive: glows, holograms, beams; faded by its alpha), premultiplied
	// or multiplied; None (the default): opaque
	blend: MaterialBlend;
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
	// each core map's own uvs (glTF: a texture's texCoord, TEXCOORD_0 or
	// _1, and its own KHR_texture_transform), in order base colour,
	// metallic-roughness, normal, occlusion, emissive (the extensions' maps
	// read the base colour's); null: the transform above for all, on the
	// first uvs. Drawn by a physical shader (PhysicalShader's uvSets), its
	// primitives' second uvs their own buffer (Mesh.Primitive.uv1)
	textureTransforms: UvTransform[] | null;
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
	// and dims it by its Fresnel. With a physical shader (PhysicalShader:
	// Model.of's, or Physical's for any material) each light's, and its maps:
	// clearcoatTexture's red times clearcoat, clearcoatRoughnessTexture's
	// green times its roughness, clearcoatNormalTexture its own normal map
	// (its x and y scaled by clearcoatNormalScale; else the geometry's normal)
	clearcoat: number;
	clearcoatRoughness: number;
	clearcoatTexture: Texture | null;
	clearcoatRoughnessTexture: Texture | null;
	clearcoatNormalTexture: Texture | null;
	clearcoatNormalScale: number;
	// how much of the light goes through it (KHR_materials_transmission, 0
	// to 1; transmissionTexture's red times it): its diffuse light replaced
	// by what is behind it (drawn see-through, Premultiplied, after the
	// opaque surfaces), its reflections kept. The standard shader's: a thin
	// surface, what is behind tinted by its colour; a physical shader's:
	// what is behind refracted through it (the opaque frame with
	// Transmission, else the environment), blurred by its roughness
	transmission: number;
	transmissionTexture: Texture | null;
	// its volume (KHR_materials_volume, a physical shader's): how thick it
	// is (in its node's units, 0: thin; thicknessTexture's green times it),
	// and the light it absorbs on the way through: attenuationColor reached
	// at attenuationDistance (0: none, glTF's infinity), Beer's law
	thickness: number;
	thicknessTexture: Texture | null;
	attenuationColor: Vec3;
	attenuationDistance: number;
	// its index of refraction (KHR_materials_ior: 1.5, a dielectric's 0.04
	// reflectance at normal incidence), and that reflectance's strength and
	// colour (KHR_materials_specular: specularTexture's alpha times
	// specularFactor, specularColorTexture's colour, sRGB, times
	// specularColor; a metal's is its albedo); a physical shader's
	ior: number;
	specularFactor: number;
	specularColor: Vec3;
	specularTexture: Texture | null;
	specularColorTexture: Texture | null;
	// a sheen over it (KHR_materials_sheen, cloth's and velvet's: black for
	// none), its colour (linear; sheenColorTexture's, sRGB, times it) and
	// roughness (sheenRoughnessTexture's alpha times it); a physical shader's
	sheenColor: Vec3;
	sheenRoughness: number;
	sheenColorTexture: Texture | null;
	sheenRoughnessTexture: Texture | null;
	// a thin film over it (KHR_materials_iridescence: soap bubbles, oil):
	// how much (iridescenceTexture's red times it), the film's index of
	// refraction and thickness in nanometres (iridescenceThicknessTexture's
	// green from the minimum to the maximum); a physical shader's
	iridescence: number;
	iridescenceIor: number;
	iridescenceThicknessMinimum: number;
	iridescenceThicknessMaximum: number;
	iridescenceTexture: Texture | null;
	iridescenceThicknessTexture: Texture | null;
	// its highlight stretched (KHR_materials_anisotropy: brushed metal):
	// how much (0 to 1), along the tangent turned by anisotropyRotation
	// (radians), or anisotropyTexture's direction (red and green) and
	// strength (blue, times anisotropy); drawn with its primitive's
	// tangents (NormalMaps); a physical shader's
	anisotropy: number;
	anisotropyRotation: number;
	anisotropyTexture: Texture | null;
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
	// the glTF extensions its fields use (PhysicalShader's options, as
	// flags: SHEEN, SPECULAR, CLEARCOAT, TRANSMISSION, IRIDESCENCE,
	// ANISOTROPY; 0: none, the standard shader's surface); what Physical
	// draws it with
	extensions(): number;
	// whether it is drawn with its primitives' tangents (a normal map, the
	// clear coat's own, an anisotropy: NormalMaps)
	tangents(): boolean;
}

// a map's uvs (Material.textureTransforms): TEXCOORD_0 or _1 (texCoord),
// turned by rotation (radians), scaled, then moved (KHR_texture_transform)
export declare class UvTransform {
	constructor(offset?: Vec2, rotation?: number, scale?: Vec2, texCoord?: number);
	offset: Vec2;
	rotation: number;
	scale: Vec2;
	texCoord: number;
}

// The physical shader for every material: one variant
// set with every glTF material extension (PhysicalShader.ALL: sheen,
// specular and ior, clearcoat with its maps, transmission and volume,
// iridescence, anisotropy; each core map at its own uvs), drawing each material whose fields use one
// (Material.extensions) and that has no shader of its own: a model loaded
// at run time (Model.load, whose extensions are not known when compiling),
// or materials made in code. Opted in, as it is big (one shader with every
// layer, each a branch on the material's values):
//
//   renderer.use(new Physical());   // made before Model.load's models are read
//
// Model.of's models need none: their materials get the variants of the
// extensions they use, made when compiling (PhysicalShader).
export declare class Physical {
	// (glTF files read from now on read their extensions: GltfExtensions;
	// made before the models load)
	constructor();
	attach(renderer: Renderer): void;
	// the shader of a material that uses an extension (Material.extensions)
	shaderOf(m: Material): MaterialShader | null;
}

// The opaque frame behind see-through surfaces
// (KHR_materials_transmission and _volume), what a physical shader's
// transmitting surface (PhysicalShader, Material.transmission) shows
// through it, refracted by its ior and thickness and blurred by its
// roughness (a mip level a roughness): once a frame that draws one, after
// the opaque surfaces and the AfterOpaque hooks (the sky), the frame's pass
// is ended, its colour copied into a mip-mapped texture of the target's
// format, and the pass begun again where it was (its colour and depth
// kept), the see-through surfaces drawn after:
//
//   renderer.use(new Transmission(renderer.device));
//
// An offscreen renderer's (a <Scene>'s box, drawInto: the frame's colour
// is a texture there); a renderer of the device's frame, or a frame with no
// transmitting surface in view, copies nothing. Without it a transmitting
// surface shows the environment refracted through it instead. Its cost: a
// copy of the frame and its mips (a third more) in the target's format,
// a pass split in two on the frames that need it (Renderer.split counts them).
export declare class Transmission {
	constructor(device: Device);
	readonly device: Device;
	attach(renderer: Renderer): void;
	// the frame's pass (pass, into textures of width x height texels of
	// format) ended, its colour so far copied (resolved) and its mips made,
	// the pass begun again where it was; returns the copy
	capture(enc: Encoder, pass: { colors: Array<{ load: number; clear?: Vec4; texture?: Texture; resolve?: Texture; layer?: number }>; depth?: { load: number; clear?: number; texture?: Texture }; queries?: number }, width: number, height: number, format: number): Texture;
	// the copy's mip levels below its first (the roughest's)
	levels(): number;
	dispose(): void;
}

// The mesh a node draws: a component (a store keyed by node), several
// nodes may share one Mesh.
export declare class MeshRenderer {
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
	// a mesh of a geometry's data alone, on the CPU (Mesh.addCpu): not drawn,
	// cast at (world.raycast), with no device (tests, a level's collision
	// shapes)
	static cpu(geometry: VertexData, material: Material): Mesh;
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
//   Geometry.extrude(path, {depth, bevelSize, bevelSegments, tolerance, evenOdd})
//   Geometry.text(font, text, {size, depth, bevelSize, bevelSegments, lineHeight, letterSpacing, align})
//
// extrude and text make solids of helder.canvas' paths and helder.text's
// outlines (Extrude: canvas' boolean ops, then the caps triangulated):
// linked only by a program that calls them.
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
	// a 2D path (helder.canvas.Path: lines, curves, holes, unions) made
	// solid, from z 0 to depth (Extrude.shape)
	static extrude(shape: unknown, o?: ExtrudeOptions): VertexData;
	// a text's outlines in font made solid (or flat: depth 0), size the em's
	// height, its first baseline at y 0 (Extrude.text)
	static text(font: FontFile, text: string, o?: TextGeometryOptions): VertexData;
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
	constructor(vertices: Uint8Array, indices: Uint8Array, wide: boolean, count: number, skinned: boolean, bounds: Aabb, tangents?: Uint8Array);
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
	readonly bounds: Aabb;
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
	bounds: Aabb;
	// whether it casts shadows (Shadows; its materials' castShadows too)
	castShadows: boolean;
	// its levels of detail (InstanceCulling: each instance drawn at the one
	// its share of the view's height picks, Lod's thresholds; null: its mesh)
	levels: LodLevel[] | null;
	// counted up at each change (Shadows: a cached tile drawn again when a
	// set it holds changed)
	readonly version: number;
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
	setColor(i: number, color: Vec3): void;
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
// (Material.blended), Alpha's sorted far to near among themselves when the
// camera moves. An atlas is columns by rows cells of the material's
// texture, left to right then top to bottom (the material's uvScale set to a
// cell's share; a sprite's cell moves its uvs there: PbrShader.instanceUv).
//
//   var halos = new Sprites(device, Material.unlit({color: gold, texture: glow, blend: Additive}), 64);
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
	mode: SpriteMode;
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
	setColor(i: number, color: Vec3): void;
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
// shared by every instance. Its materials' glTF extensions (sheen,
// specular, clearcoat, transmission, iridescence, anisotropy) are read when
// compiling too: each set its materials use is compiled into the build
// (PhysicalShader), and no other, so a game whose models have no sheen links
// no sheen; a model Model.load reads is drawn by Physical's (every
// extension), when the program uses it.
export declare class Model<N, M, A, C> {
	private constructor();
	// a model whose path is known only at run time: loaded in the background
	// (in the browser fetched, relative to the page; natively read at once),
	// its names unknown when compiling (find nodes by name: model.doc)
	static load(path: string): Asset<Model<{}, {}, {}, {}>>;
	// the model's scene as nodes of world (under parent, by default the root)
	instantiate(world: World, device: Device, parent?: Node, made?: Node[]): Node;
	// the model's GPU meshes released
	dispose(): void;
}

// A material's own shader (README.md 3 in src/helder/compiler): pbr (the
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
// own, made beside its module). A material that replaces the position,
// normal, roughness or alpha slot also gets the view buffers' prepass
// variants (prepass, prepassInstanced: ViewBuffers); one that replaces none
// is drawn there by the standard material's, which is the same.
export declare class MaterialShader {
	// a TypeScript program's material (helder/scene's material(pbr.with({...})),
	// a definition: helder.typescript.lower's Definitions compiles the same
	// variants and passes them here, JSON)
	static script(json: string): MaterialShader;
	readonly plain: Shader<unknown, unknown>;
	readonly normalMapped: Shader<unknown, unknown> | null;
	readonly skinned: Shader<unknown, unknown>;
	readonly instanced: Shader<unknown, unknown>;
	readonly instancedNormalMapped: Shader<unknown, unknown> | null;
	// the view buffers' (ViewBuffers): plain and instanced; null, the
	// standard material's (its position, normal, roughness and alpha slots
	// as they are)
	readonly prepass: Shader<unknown, unknown> | null;
	// the view buffers' (ViewBuffers): plain and instanced; null, the
	// standard material's (its position, normal, roughness and alpha slots
	// as they are)
	readonly prepassInstanced: Shader<unknown, unknown> | null;
	// the blocks of the material's own: its parameter's name, its slot, in
	// each variant (in the order above; -1: not in it)
	readonly blocks: Array<{ name: string; bindings: number[] }>;
	// the glTF extensions its variants have (PhysicalShader's: Material's
	// flags, SHEEN ...; 0: none, a material's own slots)
	extensions: number;
}

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
export declare class PostProcess {
	// output: the format of the targets run writes (RGBA8: a <Scene>'s
	// box's); frame: run writes the frame instead (output unused)
	constructor(device: Device, output?: number, frame?: boolean);
	readonly device: Device;
	// the light before the curve (1: as drawn)
	exposure: number;
	// bloom's share of the frame (0 to 1: 0.04 is subtle, 0.15 dreamy; 0: no bloom passes)
	bloom: number;
	// how far each level up spreads (its texels: 1 a tight halo, 2 wider)
	radius: number;
	// the bloom chain's levels (1 to 6; fewer: a tighter, cheaper glow)
	levels: number;
	// the first level's size: the frame's halved this many times (1 or 2;
	// 2: a quarter of the pixels to filter, the glow a little softer)
	base: number;
	toneMap: ToneMap;
	// the grade, on the tone mapped colour: 1 as it is
	saturation: number;
	contrast: number;
	// added to the shadows (rgb, 0 to about 0.05) and the colour's gain (rgb)
	lift: Vec3;
	gain: Vec3;
	// how much darker the corners are (0 to 1)
	vignette: number;
	// film grain's strength (0 to about 0.1); a dither below a step of 8 bits is always there
	grain: number;
	// whether the frame's alpha is kept (the scene's coverage, where bloom
	// adds light its brightness: over a ui behind it, premultiplied); false: opaque
	transparent: boolean;
	// the screen's ambient occlusion (Ssao: GTAO; null none)
	ao: Ssao | null;
	// depth of field (Dof.focus, Dof.tiltShift; null none)
	dof: Dof | null;
	// the selection's outlines (Outline, Outline.select; null none)
	outline: Outline | null;
	// antialiasing after the frame's own (None, Fxaa: in the composite; its
	// variant linked only by a program that sets it); smaa and taa are
	// effects of their own, below
	antialias: Antialias;
	// SMAA (Smaa: edges and their blending weights in two passes, blended in
	// the composite, in place of antialias'; null none)
	smaa: Smaa | null;
	// temporal antialiasing (Taa: the frame jittered, gathered with its
	// history reprojected by the view buffers' motion; null none)
	taa: Taa | null;
	// screen-space reflections (Ssr; null none): before the other effects,
	// from the view buffers, mixed by each surface's Fresnel, roughness and metalness
	ssr: Ssr | null;
	// motion blur (MotionBlur; null none): the camera's from depth, or each
	// object's by the view buffers' motion
	motionBlur: MotionBlur | null;
	// god rays (GodRays; null none): the sky's light behind the scene blurred
	// towards the sun's place on the screen, added before the curve
	godRays: GodRays | null;
	// colour grading by a lookup table (Lut; null none), after the grade
	lut: Lut | null;
	// the last run's draws (each a full-screen pass: AO's, depth of field's,
	// bloom down and up, the composite, the stages; helder.gfx.FrameCounts.postDraws too)
	readonly draws: number;
	// the run's context, for its stages (PostStage's prepare and bind): the
	// scene's light it was given (linear, RGBA16F, its alpha the scene's
	// coverage) and its size in pixels; null and 0 outside a run
	readonly source: Texture | null;
	readonly width: number;
	readonly height: number;
	// a stage of the program's own (PostStage: its shader's first texture
	// the image so far, its first block bytes): after those before it at its
	// point (AfterComposite: tone mapped; BeforeComposite: in linear light)
	add<V, P>(shader: Shader<V, P>, bytes?: Uint8Array, point?: number): unknown;
	// a cut: the history temporal antialiasing gathers let go (a camera
	// jumped, a scene changed), the next frame alone
	resetHistory(): void;
	remove(stage: unknown): void;
	// the frame: source (the scene's RGBA16F, width by height) into target
	// (the output format's render target of that size, or with stages any
	// size; null: the frame, a PostProcess made for it); time: seconds, the
	// grain's
	run(enc: Encoder, source: Texture, target: Texture | null, width: number, height: number, time?: number): void;
	dispose(): void;
}

// Screen-space ambient occlusion, a PostProcess's (post.ao = new
// Ssao({...})): GTAO (Jimenez et al. 2016) from the renderer's view
// buffers (ViewBuffers: their depth and normals, asked for by the chain),
// at half their size (halfRes) or whole, then blurred up to their size by
// depth (bilateral), before the frame's pass, whose standard material
// darkens its indirect light by it alone (the ambient, the environment's
// light and reflections: PbrShader's aoMap), not the sun's or the lamps'
// (three.js' classic passes darken the whole frame). Its targets are R8;
// nothing is allocated per frame.
//
//   post.ao = new Ssao({radius: 0.5, intensity: 1, samples: 8, halfRes: true});
//
// On a phone: one slice of 4 to 6 steps at half size (samples 4, slices 1).
// Its options alone: its passes are SsaoPass's, linked by a program that
// sets it on a chain (post.ao's setter).
export declare class Ssao {
	constructor(options?: SsaoOptions);
	// how far an occluder reaches (metres)
	radius: number;
	// how dark: the occlusion's power (1 as found, 2 darker)
	intensity: number;
	// the steps along each side of a slice
	samples: number;
	// the slices of the hemisphere (1 or 2: the noise turns them per pixel)
	slices: number;
	// at half the frame's size (a quarter of the pixels: the view buffers'
	// when they are at half, else half theirs), blurred up to theirs
	halfRes: boolean;
	// the last frame's occlusion (R8, the view buffers' size; red 1 open, 0 occluded)
	readonly texture: Texture | null;
}

// Depth of field, a PostProcess's (post.dof): a circle of confusion from
// the view buffers' depth (ViewBuffers, asked for by the chain), the
// scene's light gathered on a disc that wide at half the frame's size in
// linear light (before bloom and the curve: bright specks spread as
// discs), then mixed into the composite where the circle is wider than a
// texel. Two lenses:
//
//   post.dof = Dof.focus({distance: 6, aperture: 0.02});   // sharp at 6 m, a thin lens's blur
//   post.dof = Dof.tiltShift({band: 0.2, falloff: 0.3, strength: 1});
//
// focus: sharp at distance (metres), the blur growing as a thin lens's to
// aperture at infinity (a share of the frame's height). tiltShift, a
// diorama's: sharp within band of the focus depth (a share of it: 0.2,
// within 20% nearer or farther), the blur growing past it to strength
// times radius over falloff more; its focus the depth under the frame at
// center (0 the top, 1 the bottom; the screen's centre by default), or
// distance when given. A world's depth, not the screen's band: a far
// island inside the band is blurred, as a lens would. Its target is
// RGBA16F, half the frame's size; nothing is allocated per frame. Its
// options alone: its pass is DofPass's, linked by a program that sets it
// on a chain (post.dof's setter).
export declare class Dof {
	// a lens focused at distance metres, aperture its blur at infinity (a
	// share of the frame's height), at most radius
	static focus(options: { distance: number; aperture?: number; radius?: number; samples?: number }): Dof;
	// a diorama's lens: sharp within band of the focus depth, blurred to
	// strength times radius past falloff more
	static tiltShift(options: { band?: number; falloff?: number; strength?: number; radius?: number; center?: number; distance?: number; samples?: number }): Dof;
	mode: DofMode;
	// focus: the distance in focus (metres); tiltShift: its focus (0: the
	// depth at center)
	distance: number;
	// focus: the blur at infinity (a share of the frame's height)
	aperture: number;
	// tiltShift: the depth kept sharp about the focus, and the depth past it
	// over which the blur reaches its most (shares of the focus depth)
	band: number;
	falloff: number;
	// tiltShift: how much of the radius the blur reaches (0 none, 1 all)
	strength: number;
	// the most blur (a share of the frame's height)
	radius: number;
	// tiltShift: where on the frame its focus is read (0 the top, 1 the bottom)
	center: number;
	// the taps of the blur's disc (16 for phones, 24, 32)
	samples: number;
	// the last frame's blur (RGBA16F, half the frame's size)
	readonly texture: Texture | null;
}

// Outlines around selected nodes, a PostProcess's (post.outline): the
// selection is data, a group (1 to 255) on a node (Outline.select: a
// component, its descendants drawn in it too), written by the view
// buffers' prepass (ViewBuffers: their normals' w) and its edges found in
// the composite, over everything drawn (see-through surfaces too). Each
// group has its colour (its alpha the outline's) and width in pixels:
//
//   post.outline = new Outline({width: 2, color: new Vec4(1, 0.8, 0.2, 1)});   // group 1
//   post.outline.group(2, new Vec4(0.3, 0.7, 1, 1), 3);
//   Outline.select(node);          // group 1; Outline.select(other, 2); Outline.select(node, 0): none
//
// The view buffers are drawn whole for it (scale 1). Nothing is allocated
// per frame; the groups' texture (256 x 2 RGBA8) is written when a group
// changes. Its groups alone: its part of the composite is OutlinePass's,
// linked by a program that sets it on a chain (post.outline's setter);
// selecting (Outline.select, Selection) links neither.
export declare class Outline {
	constructor(options?: { width?: number; color?: Vec4 });
	// node and its descendants outlined in group (1 to 255; 0: not selected)
	static select(node: Node, group?: number): void;
	// node's own group (0: none)
	static selected(node: Node): number;
	// group 1's width in pixels and colour
	width: number;
	color: Vec4;
	// a group's colour (its alpha the outline's) and width in pixels (at most 32)
	group(k: number, color: Vec4, width: number): Outline;
}

// Colour grading by a lookup table, a PostProcess's (post.lut): a size cubed
// table (16 or 32) as a 2D strip of size slices side by side (size^2 by
// size texels: red across a slice, green down it, blue by slice; gfx has no
// 3D textures), read once in the composite after the curve and the grade,
// display values in and out (an identity strip graded in an image editor,
// as Unreal's and Unity's LUT strips are):
//
//   post.lut = Lut.fromImage(device, image);                 // a 256 x 16 strip (helder.image's Image)
//   post.lut = Lut.of(device, 16, (r, g, b) -> new Vec3(...));   // a grade of the program's own
//   post.lut.strength = 0.5;                                 // halfway from none to the table
export declare class Lut {
	// a strip's image (size * size by size: 256 x 16, 1024 x 32), its pixels RGBA8
	static fromImage(device: Device, image: Image): Lut;
	// a strip's RGBA8 texels (size * size by size: strip's), size a side
	static fromBytes(device: Device, size: number, bytes: Uint8Array): Lut;
	// a table made from a grade (display values 0..1 in, out), size a side
	static of(device: Device, size: number, grade: (r: number, g: number, b: number) => Vec3): Lut;
	// the identity table (what a strip to grade in an editor starts from)
	static identity(device: Device, size?: number): Lut;
	// a grade's strip, RGBA8 (a PNG of it is a strip to grade elsewhere)
	static strip(size: number, grade: (r: number, g: number, b: number) => Vec3): Uint8Array;
	readonly device: Device;
	// the table's size a side (16, 32)
	readonly size: number;
	// how much of it (0: none, 1: the table's)
	strength: number;
	// the strip (RGBA8, size * size by size)
	readonly texture: Texture;
	dispose(): void;
}

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
export declare class ViewBuffers {
	constructor(device: Device);
	// the renderer's view buffers: made and turned on when first asked
	static of(renderer: Renderer): ViewBuffers;
	// a node's selection group: its own (Outline.select), else the nearest
	// of its ancestors' (0: none; Selection's)
	static groupOf(node: Node): number;
	readonly device: Device;
	// the share of the frame's size they are drawn at (0: the effects'
	// choice, 1 with an outline, else 0.5; a program's own use: 1)
	scale: number;
	// off: no prepass drawn, no groups taken (what the effects made, while none reads them)
	enabled: boolean;
	// whether their motion is drawn too (motion: a second pass, gfx having
	// one colour target a pass; TAA and motion blur by objects ask for it
	// themselves; a program's own: withVelocity()): what moved since the
	// frame before, by each node's matrix then and now and the camera's
	// (MotionPass; desktop and web)
	readonly velocity: boolean;
	// the last frame's motion (RGBA16F, their size: xy this pixel's point's
	// uv now less the frame before's, z 1 where a surface wrote it; null:
	// velocity off)
	readonly motion: Texture | null;
	// the last prepass's targets and their size
	readonly depth: Texture;
	readonly normals: Texture;
	readonly width: number;
	readonly height: number;
	// the last prepass's draws
	readonly draws: number;
	// the share of the frame's size they were last drawn at
	readonly drawnScale: number;
	// the last prepass's camera: its projection, the projection's inverse
	// (a view-space point from a texel's depth), its view
	readonly projection: Mat4;
	readonly inverseProjection: Mat4;
	readonly view: Mat4;
	// their motion drawn too (velocity, motion; a method, not a setter: a
	// program that never calls it links no motion pass), or no longer
	withVelocity(on?: boolean): ViewBuffers;
	// the last frame's motion pass's draws (0 without)
	readonly motionDraws: number;
	dispose(): void;
}

// Screen-space reflections, a PostProcess's (post.ssr = new Ssr({...})):
// from the view buffers' depth and normals (asked for by the chain), each
// glossy pixel's reflected ray marched through the depth in view space at
// half the frame's size (or whole), its hit refined between its last two
// steps, the scene's light there taken; then, at the frame's size, mixed
// over the scene's light by the surface's Fresnel (Schlick's, its F0 from
// its metalness: the view buffers keep no base colour, a metal's
// reflection is untinted), its gloss and the hit's confidence (faded at
// the screen's edges, with the distance, for rays towards the camera).
// Where nothing is hit the scene keeps what the frame's pass gave it (the
// environment's or the sky's reflection). Desktop and web: no renderer
// listed ships it on phones. Its targets are RGBA16F; nothing is allocated
// per frame. Its options alone: its passes are SsrPass's, linked by a
// program that sets it on a chain.
//
//   post.ssr = new Ssr({maxDistance: 8, thickness: 0.2});
export declare class Ssr {
	constructor(options?: SsrOptions);
	// how much of the reflection is mixed in (1: as Fresnel says)
	intensity: number;
	// how far a ray goes (metres)
	maxDistance: number;
	// how thick a surface is taken to be behind its depth (metres): a ray
	// behind it by more passes behind it
	thickness: number;
	// the steps along a ray (16 to 48), then 4 halvings between the last two
	steps: number;
	// the roughest surface that reflects (0..1: rougher ones keep their
	// own light); the reflection fades towards it
	maxRoughness: number;
	// at half the frame's size (a quarter of the rays)
	halfRes: boolean;
	// the last frame's reflections (RGBA16F: rgb the light hit, a its weight)
	readonly texture: Texture | null;
}

// Motion blur, a PostProcess's (post.motionBlur = new MotionBlur({...})):
// each pixel's light gathered along its motion on the screen since the
// frame before, in linear light before depth of field and bloom: the
// camera's motion from the view buffers' depth and the last frame's
// view-projection (no motion target: what a phone affords), or with objects
// each node's own too (the view buffers' motion, ViewBuffers.velocity: a
// second geometry pass, desktop and web). Its target is RGBA16F, the frame's
// size; nothing is allocated per frame. Its options alone: its pass is
// MotionBlurPass's, linked by a program that sets it on a chain.
//
//   post.motionBlur = new MotionBlur({strength: 0.5});                 // the camera's
//   post.motionBlur = new MotionBlur({strength: 0.5, objects: true});  // and each object's
export declare class MotionBlur {
	constructor(options?: MotionBlurOptions);
	// the share of the frame's motion blurred (the shutter: 0.5 a half-open
	// one, 180 degrees; 1 the whole frame's)
	strength: number;
	// the taps along the motion (8 for phones, 12, 16)
	samples: number;
	// the longest blur (a share of the frame's height)
	max: number;
	// each object's motion too (the view buffers' motion), not the camera's alone
	objects: boolean;
}

// God rays, a PostProcess's (post.godRays = new GodRays({...})): the sky's
// light (where the view buffers' depth is the far plane's) blurred towards
// the sun's place on the screen, at a quarter of the frame's size, added to
// the scene's light before the curve, so what stands before the sky casts
// shafts of shadow through the glow (Mitchell's "Volumetric Light
// Scattering as a Post-Process", GPU Gems 3). The sun is the renderer's:
// the world's first directional light, else Renderer.sunDirection; behind
// the camera, none. One pass at a quarter of the pixels; its target RGBA16F;
// nothing is allocated per frame. Volumetric fog is not this. Its options
// alone: its pass is GodRaysPass's, linked by a program that sets it.
//
//   post.godRays = new GodRays({intensity: 0.6, decay: 0.96});
export declare class GodRays {
	constructor(options?: GodRaysOptions);
	// how much light the shafts add
	intensity: number;
	// how far towards the sun each pixel gathers (a share of the way)
	density: number;
	// how much each tap weighs against the one nearer the pixel (0..1: less
	// fades the shafts sooner)
	decay: number;
	// the taps along the way (24 for phones, 32, 48)
	samples: number;
	// how tight the glow is about the sun (more: only near it)
	falloff: number;
	// the last frame's shafts (RGBA16F, a quarter of the frame's size)
	readonly texture: Texture | null;
}

// Temporal antialiasing, a PostProcess's (post.taa = new Taa()): the
// frame's projection jittered by a sub-pixel each frame (Renderer.jitter),
// gathered with its history reprojected by the view buffers' motion (asked
// for whole, with ViewBuffers.velocity), the history kept within each
// pixel's neighbourhood (TaaShader's notes); in linear light, before depth
// of field, motion blur and bloom. Desktop and web (MSAA stays a phone's).
// A cut (a camera's jump): PostProcess.resetHistory. Its options alone: its
// passes are TaaPass's, linked by a program that sets it on a chain.
//
//   post.taa = new Taa({blend: 0.1});
export declare class Taa {
	constructor(options?: TaaOptions);
	// the share of each new frame in the history (0.1: about ten frames
	// gathered; more: quicker to follow, less smooth)
	blend: number;
}

// SMAA, a PostProcess's (post.smaa = new Smaa()): Jimenez et al.'s
// morphological antialiasing of the light the composite reads, its edges
// and their blending weights in two passes, blended in the composite (its
// own variant), in place of FXAA's (SmaaShaders' notes: the orthogonal
// patterns, their areas worked out; no diagonal or corner patterns: SMAA's
// medium preset). Its options alone: its passes are SmaaPass's, linked by
// a program that sets it on a chain.
//
//   post.smaa = new Smaa({threshold: 0.1});
export declare class Smaa {
	constructor(options?: SmaaOptions);
	// the edges' threshold, of perceptual luma (0.1 SMAA's medium, 0.05 finer)
	threshold: number;
}

// Occlusion culling by queries, a RenderFeature (renderer.use(new
// Occlusion(device))), as Babylon's occlusion queries: each node marked
// (Occlusion.test(node): large ones, what a wall may hide) has its bounds
// drawn as a box after the frame's opaque surfaces, depth tested and not
// written, inside a query of gfx's (Device.createQueries); a node whose
// last answered query passed no sample is culled at the next frames'
// extraction (Renderer.occluded counts it, --stats' occluded), its box
// still drawn each frame so that it comes back when it is seen again (a
// frame or more late: the queries are never waited for). A node outside
// the view, or whose bounds hold the eye, is not tested and never culled;
// its last answer is let go (Device.resetQuery). The boxes are one draw
// each (a query each): test what is worth it, not every pebble. Nothing is
// allocated per frame. GPU-driven culling against a depth pyramid is the
// compute tier's.
//
//   renderer.use(new Occlusion(device));
//   Occlusion.test(building);           // its node's meshes culled while hidden
export declare class Occlusion {
	constructor(device: Device, capacity?: number);
	// a node's meshes culled while what is drawn before them hides their bounds
	static test(node: Node): void;
	// a node no longer tested (drawn whenever in view)
	static untest(node: Node): void;
	// whether a node is tested (Occlusion.test)
	static tested(node: Node): boolean;
	readonly device: Device;
	// the queries (one a node tested, at most capacity: those past it untested)
	readonly capacity: number;
	// off: nothing culled, no boxes drawn (the answers let go)
	enabled: boolean;
	// the last frame's boxes drawn (each a query)
	readonly draws: number;
	// how much larger than its bounds a box is drawn (a share of its size,
	// and metres: its own surfaces not taken for what hides it)
	margin: number;
	dispose(): void;
}

// Lines with a width (three's Line2 and LineMaterial, Babylon's
// GreasedLine): a polyline through its points, or separate segments (a
// pair of points each), drawn by LineRenderer (renderer.use(new
// LineRenderer(device))) as quads on the screen, so a width is the same on
// every back end (gfx's Lines topology is 1 px, and WebGL ignores widths):
//
//   width        in pixels (widthUnits Pixels, the default) or in the
//                world's units (World: thinner far off, as geometry is)
//   join         where segments meet: Miter (Bevel past 4 half widths),
//                Round or Bevel
//   cap          the line's ends: Butt, Round or Square
//   dash, gap    a dashed line (lengths in the line's own units along it;
//                0: solid), dashOffset moving the dashes along (animated:
//                a marching line)
//   onTop        drawn over everything (not depth tested), after the
//                scene; else depth tested against it
//   transparent  blended by its colours' alpha, after the see-through
//                surfaces (not written to depth)
//   toneMapped   false: its colours as they are into an 8-bit target (a
//                debug colour's pure red), not tone mapped
//
// A point is a position in the node's frame (Lines.attach) and a colour
// (linear rgb and alpha, blended along a segment). The program writes
// them into the line's flat data, as InstancedMesh takes its instances:
// nothing is allocated a frame, and the line renderer uploads the points
// once they changed (one writeBuffer; its GPU copy made when first drawn,
// so lines themselves link no device).
//
//   var path = new Lines(512, {width: 6, join: Round, dash: 0.2, gap: 0.15});
//   Lines.attach(world.node("aim"), path);
//   // each frame:
//   path.count = n;
//   for (i in 0...n) path.setPoint(i, xs[i], ys[i], zs[i], 1, 1, 1, fade(i));
export declare class Lines {
	// capacity points (count of them drawn: none by default)
	constructor(capacity: number, options?: LinesOptions);
	static attach(node: Node, lines: Lines): Lines;
	static of(node: Node): Lines | null;
	static detach(node: Node): void;
	readonly capacity: number;
	// separate segments (points 2k and 2k + 1), not a polyline
	readonly segments: boolean;
	// the points drawn (0 to capacity; a polyline's segments count - 1, closed's count)
	count: number;
	width: number;
	widthUnits: LineUnits;
	join: LineJoin;
	cap: LineCap;
	dash: number;
	gap: number;
	dashOffset: number;
	// a polyline's last point joined back to its first
	closed: boolean;
	onTop: boolean;
	transparent: boolean;
	toneMapped: boolean;
	visible: boolean;
	// its GPU copy, LineRenderer's (made when first drawn: Buffer.NONE before)
	readonly buffer: number;
	// point i at x, y, z (the node's frame), of the linear colour r, g, b and alpha a
	setPoint(i: number, x: number, y: number, z: number, r?: number, g?: number, b?: number, a?: number): void;
	setPosition(i: number, x: number, y: number, z: number): void;
	// point i's colour (linear rgb, and its alpha)
	setColor(i: number, color: Vec4): void;
	// point i's field: 0 to 2 its position, 3 to 6 its colour
	get(i: number, field: number): number;
	// the segments drawn (instances of LineRenderer's draw)
	readonly drawn: number;
	// the records as uploaded (the point buffer's bytes: tests)
	readonly data: Uint8Array;
	// the records made from the points, when they changed (the renderer
	// uploads them after: their bytes, data)
	prepare(): void;
	// its GPU copy let go (made again if drawn again)
	dispose(device: Device): void;
}

// Draws a world's Lines (renderer.use(new LineRenderer(device)), or
// LineRenderer.of(renderer)): each shown node's lines one instanced draw
// (LineShader: a segment an instance), the depth-tested opaque ones after
// the opaque surfaces (AfterOpaque), the see-through ones (transparent)
// after the see-through surfaces, those drawn over everything (onTop) last
// (AfterTransparent). Their points are uploaded once changed; nothing is
// allocated a frame. DebugDraw draws through it.
export declare class LineRenderer {
	constructor(device: Device);
	// the renderer's line renderer, made and turned on when it has none
	static of(renderer: Renderer): LineRenderer;
	readonly device: Device;
	// the last frame's draws (statistics)
	readonly draws: number;
	attach(renderer: Renderer): void;
	dispose(): void;
}

// Immediate-mode debug drawing (Bevy's gizmos, PlayCanvas' drawLine): a
// frame's calls, from anywhere (a script, the physics step, a loop), are
// written into a ring of segments, drawn by the DebugDraw feature
// (renderer.use(new DebugDraw())) as one draw of lines through the
// renderer's LineRenderer, another for those drawn over everything
// (onTop), then cleared: nothing to keep or remove, and nothing allocated
// a frame. A colour is 0xRRGGBB as a page writes it (shown as written: not
// lit, fogged or tone mapped).
//
//   DebugDraw.line(a, b, 0xFF4040);
//   DebugDraw.aabb(mesh.bounds, 0x40FF40);
//   DebugDraw.onTop = true;               // the calls from here on over everything
//   DebugDraw.axes(player.worldMatrix(), 0.5);
//   DebugDraw.onTop = false;
//
// Debug's calls are these, compiled out of a release build (helder build's
// -D helder.release) unless -D helder.debugdraw: their arguments not
// computed either. The helpers (AxesHelper, GridHelper, BoundsHelper,
// LightHelper, CameraHelper, SkeletonHelper: components of a node) draw
// through them each frame the feature draws.
//
// The ring holds capacity segments (set before the first call): calls past
// it in a frame are dropped (dropped counts them). Several renderers
// drawing in a frame: the first one's DebugDraw takes them.
export declare class DebugDraw {
	constructor(options?: { width?: number });
	// the segments a frame holds (before the first call), and those dropped
	// past it (the last frame's)
	static capacity: number;
	static readonly dropped: number;
	// whether the calls from here on are drawn over everything (not depth tested)
	static onTop: boolean;
	// the renderer's DebugDraw, made and turned on when it has none
	static of(renderer: Renderer): DebugDraw;
	// a segment from a to b
	static line(a: Vec3, b: Vec3, color?: number): void;
	// from origin along dir for length (dir's length times it), an arrow's head at its end
	static ray(origin: Vec3, dir: Vec3, length?: number, color?: number): void;
	// an arrow from a to b
	static arrow(a: Vec3, b: Vec3, color?: number): void;
	// a box's twelve edges (in the world)
	static aabb(box: Aabb, color?: number): void;
	// the box min to max moved by m (an oriented box: a node's bounds through its world matrix)
	static boxOf(m: Mat4, min: Vec3, max: Vec3, color?: number): void;
	// a circle about center facing normal
	static circle(center: Vec3, normal: Vec3, radius: number, color?: number, segments?: number): void;
	// a sphere as its three great circles
	static sphere(center: Vec3, radius: number, color?: number, segments?: number): void;
	// a point's three crossed strokes, size long
	static cross3(p: Vec3, size?: number, color?: number): void;
	// a frame's axes from its origin, size long: x red, y green, z blue (a node's: its worldMatrix())
	static axes(m: Mat4, size?: number): void;
	// a node's axes (axes of its world matrix)
	static axesOf(node: Node, size?: number): void;
	// a square grid on the xz plane about center, size wide, of divisions cells a side
	static grid(center: Vec3, size?: number, divisions?: number, color?: number): void;
	// a camera's view volume (its frustum) at an aspect (width over height)
	static frustum(camera: Camera, aspect: number, color?: number): void;
	// a light of a node: a directional one's arrows down its -z, a point
	// light's range, a spot's cone to its range, a hemisphere's two halves;
	// in its colour unless one is given (-1)
	static light(node: Node, color?: number): void;
	// a skin's bones: each joint to its parent where that is a joint too
	static skeleton(skin: unknown, color?: number): void;
	// joints' bones: each joint to its parent where that is one of them too
	static bones(joints: Node[], color?: number): void;
	// a curve as n segments
	static path(curve: Curve3, n?: number, color?: number): void;
	// its lines' width in pixels (2 by default)
	width: number;
	attach(renderer: Renderer): void;
	// the segments the last frame drew (both rings)
	readonly drawn: number;
	dispose(): void;
}

// A debug view of a node (three's helpers: AxesHelper, Box3Helper,
// CameraHelper, the light helpers, SkeletonHelper), a component drawn each
// frame by the renderer's DebugDraw (renderer.use(new DebugDraw())):
// the same calls as DebugDraw's, for its node, so a helper is what a
// program could write itself. A node may have several (attach adds one).
//
//   AxesHelper.attach(node, 0.5);        // its axes: x red, y green, z blue
//   BoundsHelper.attach(node);           // its mesh's box, turned with it
//   LightHelper.attach(lamp);            // a light's direction, range or cone
//   CameraHelper.attach(eye);            // a camera's view volume
//   SkeletonHelper.attach(character);    // a skin's bones
//   GridHelper.attach(floor, {size: 10, divisions: 10});   // an infinite grid (a shader)
//
// Unlike DebugDraw's calls, helpers are not compiled out of a release build:
// a program attaching one wants it.
export declare class Helper {
	// h added to node's helpers
	static add<T>(node: Node, h: T): T;
	// node's helpers removed
	static clear(node: Node): void;
	// whether it is drawn
	visible: boolean;
	// drawn for its node's parent, not its node (markup's helper tags: a
	// <BoundsHelper/> in a mesh shows the mesh's)
	ofParent: boolean;
	// (its calls for node, each frame DebugDraw draws; enc, frame and the
	// renderer for one drawing on its own: GridHelper)
	draw(node: Node, enc: Encoder, frame: unknown, renderer: Renderer): void;
}

// a node's axes, size long: x red, y green, z blue
export declare class AxesHelper extends Helper {
	constructor(size?: number);
	static attach(node: Node, size?: number): AxesHelper;
	size: number;
	draw(node: Node, enc: Encoder, frame: unknown, renderer: Renderer): void;
}

// An infinite grid on its node's xz plane (a studio's viewport, an editor's
// floor: GridShader, not lines): cells of size / divisions (the node's
// units), a major line every tenth, the x axis red and the z axis blue,
// each line a pixel wide however far, fading out at fade (size * 3 by
// default) from the eye. Drawn by DebugDraw (its pipeline made on its
// renderer when first drawn), blended over the scene, depth tested.
//
//   GridHelper.attach(world.node("grid"), {size: 10, divisions: 10});
export declare class GridHelper extends Helper {
	constructor(options?: GridOptions);
	static attach(node: Node, options?: GridOptions): GridHelper;
	size: number;
	divisions: number;
	fade: number;
	// the cells' lines' colour and the major ones' (linear, alpha their opacity)
	color: Vec4;
	majorColor: Vec4;
	draw(node: Node, enc: Encoder, frame: unknown, renderer: Renderer): void;
}

// a node's mesh's (or instanced set's) box, in its frame: turned and scaled with it
export declare class BoundsHelper extends Helper {
	constructor(color?: number);
	static attach(node: Node, color?: number): BoundsHelper;
	color: number;
	draw(node: Node, enc: Encoder, frame: unknown, renderer: Renderer): void;
}

// a node's light (DebugDraw.light: its direction, range or cone), in its
// colour unless one is given (-1)
export declare class LightHelper extends Helper {
	constructor(color?: number);
	static attach(node: Node, color?: number): LightHelper;
	color: number;
	draw(node: Node, enc: Encoder, frame: unknown, renderer: Renderer): void;
}

// a node's camera's view volume, at the frame's aspect (or its own, above 0)
export declare class CameraHelper extends Helper {
	constructor(color?: number, aspect?: number);
	static attach(node: Node, color?: number, aspect?: number): CameraHelper;
	color: number;
	aspect: number;
	draw(node: Node, enc: Encoder, frame: unknown, renderer: Renderer): void;
}

// a node's skin's bones (its Skin's joints, each to its parent)
export declare class SkeletonHelper extends Helper {
	constructor(color?: number);
	static attach(node: Node, color?: number): SkeletonHelper;
	color: number;
	draw(node: Node, enc: Encoder, frame: unknown, renderer: Renderer): void;
}

// Where a ray met the world (world.raycast, Raycaster): filled by the cast,
// owned by the program (one kept and refilled: nothing allocated a cast).
// The node hit, how far along the ray (the world's units), the point,
// the surface's normal there (its vertices' normals blended, in the world,
// turned towards the ray: the back's when the back was hit), which side,
// the primitive and its triangle (indices 3 * triangle on), the
// barycentrics of the triangle's corners and the uvs there; an instanced
// set's instance (-1: a node's mesh). A cast at bounds alone (triangles
// off, or a primitive with no data on the CPU) gives the box's point, no
// triangle (-1), the ray's opposite for a normal.
export declare class Hit {
	constructor();
	node: Node;
	distance: number;
	point: Vec3;
	normal: Vec3;
	// whether the triangle's front was hit (counter-clockwise towards the ray)
	front: boolean;
	primitive: unknown | null;
	triangle: number;
	// the weights of the triangle's three corners (x the first's)
	barycentric: Vec3;
	uv: Vec2;
	instance: number;
	// another hit's values in this one
	copyFrom(h: Hit): Hit;
}

// The hits of world.raycastAll, nearest first, refilled by each cast: its
// hits kept between casts (more made only when a cast has more hits than
// any before it).
export declare class HitList {
	constructor();
	// the last cast's hits
	readonly count: number;
	get(i: number): Hit;
}

// What a cast looks at (world.raycast's options; kept by the program, not
// made a cast): as far as maxDistance, the nodes of layers (a mask of
// Raycaster.setLayers' bits: a node's 1 unless set), at the triangles
// (false: the primitives' bounds alone, Pick.ray's way), their backs too
// with backfaces, instanced sets (InstancedMesh, Sprites, Text3D) with
// instances.
export declare class RaycastOptions {
	constructor(o?: { maxDistance?: number; layers?: number; triangles?: boolean; backfaces?: boolean; instances?: boolean });
	maxDistance: number;
	layers: number;
	triangles: boolean;
	backfaces: boolean;
	instances: boolean;
}

// Rays cast at a world's triangles (world.raycast, world.raycastAll: three's
// Raycaster, Bevy's MeshRayCast): each shown node drawing a mesh
// (MeshRenderer) and each instance of an instanced set (InstancedMesh,
// Sprites, Text3D), the ray brought into its frame (turned, moved and
// scaled, unevenly too), its bounds first, then each primitive's bounds and
// its triangles through the primitive's Bvh (made when first cast at, from
// the data it keeps on the CPU: Mesh.keepCpu; or the asset step's). The
// nearest hit fills a Hit the program owns, every hit a HitList: nothing is
// allocated a cast, the trees once made.
//
//   final hit = new Hit();
//   if (world.raycast(ray.origin, ray.dir, hit)) paint(hit.node, hit.uv);
//
// Skinned and morphed meshes are cast at in their rest pose (Bvh.refit to
// fit a tree to moved vertices). Pick.ray stays the bounds-only fast path.
export declare class Raycaster {
	// a node's layers (a mask; 1 unless set), which a cast's options.layers picks
	static readonly LAYERS: unknown;
	static setLayers(node: Node, mask: number): void;
	static layersOf(node: Node): number;
	// the nearest hit of the ray from origin along dir (normalized here)
	// into hit; false when it hits nothing (hit as it was)
	static raycast(world: World, origin: Vec3, dir: Vec3, hit: Hit, options?: RaycastOptions): boolean;
	// every hit of the ray into hits, nearest first (the list refilled);
	// their count
	static raycastAll(world: World, origin: Vec3, dir: Vec3, hits: HitList, options?: RaycastOptions): number;
	// (castAll's: each triangle hit)
	hit(t: number, triangle: number, u: number, v: number, front: boolean): void;
}

// A bounding volume hierarchy over one primitive's triangles (three-mesh-bvh's
// MeshBVH), for casting rays against them (Raycaster, world.raycast): a flat
// array of nodes, each a box and either two children (the next pair) or a
// leaf's run of triangles, built by the surface area heuristic over 12 bins
// a split (at most 8 triangles a leaf, more only where their centres
// coincide), the triangles' corners copied in the tree's order beside it.
// Built when first cast against (Primitive.bvh), or in the asset step
// (helder.scene.gltf.Pack --bvh) and read with the packed model, its bytes
// as they are (bytes(), read): a level loads with its trees made.
//
// A cast allocates nothing: the traversal's stack is the tree's own (one
// cast at a time: not shared between threads), the nearest hit's distance,
// triangle and barycentrics left in t, triangle, u and v.
//
//   var bvh = Bvh.build(Geometry.sphere());
//   if (bvh.intersect(origin, dir, 100, false)) trace(bvh.t, bvh.triangle);
export declare class Bvh {
	// the tree of a primitive's data (its positions and triangles)
	static build(data: VertexData): Bvh;
	// the tree of positions (x, y, z a vertex) and triangles' indices
	static fromArrays(positions: number[], indices: number[]): Bvh;
	static read(b: Uint8Array): Bvh;
	readonly nodes: Uint8Array;
	readonly triangles: Uint8Array;
	readonly nodeCount: number;
	readonly triangleCount: number;
	// the tree's depth (its traversal's stack)
	readonly depth: number;
	// the last cast's nearest hit: its distance along the ray (in the ray
	// direction's lengths), its triangle (the primitive's: indices 3k to
	// 3k + 2), the barycentrics of its second and third corners (the first's
	// 1 - u - v), whether its front was hit (counter-clockwise towards the ray)
	readonly t: number;
	readonly triangle: number;
	readonly u: number;
	readonly v: number;
	readonly front: boolean;
	// the nearest triangle the ray from origin along dir (any length: the
	// distances are in its lengths) crosses within maxT, its back too when
	// backfaces; false when none (t, triangle, u, v, front: the hit's)
	intersect(origin: Vec3, dir: Vec3, maxT: number, backfaces: boolean): boolean;
	// every triangle the ray crosses within maxT, each given to sink (in no
	// order); their count
	intersectAll(origin: Vec3, dir: Vec3, maxT: number, backfaces: boolean, sink: unknown): number;
	// its boxes fitted again to moved vertices (a morph's or a skin's
	// positions on the CPU: vertices of stride bytes, the primitive's own
	// triangles' indices), the tree's shape kept (three-mesh-bvh's refit)
	refit(vertices: Uint8Array, stride: number, data: VertexData): void;
	// the tree as bytes (the asset step's: read takes them back as they are)
	bytes(): Uint8Array;
}

// Text in the world (Godot's Label3D and TextMesh, three's TextGeometry): a
// component drawing a text's glyphs as geometry (Geometry.text: helder.text's
// layout, its outlines through helder.canvas, flat or extruded) in one
// instanced draw, sized in the scene's units (size: the em's height),
// centred on its node (align: its lines left, centred or right), depth
// tested, fogged and sorted with the scene, sharp at any distance. Unlit by
// default (its colour as given); lit: a lambert material, or any of the
// program's. billboard: turned to face the camera each frame (its node's
// position and scale kept). Setting text makes its geometry again (a
// score's change, not a frame's); nothing is allocated a frame. Rays hit
// it (world.raycast: its triangles).
//
//   var label = Text3D.attach(world.node("score"), new Text3D(device, font, "0", {size: 0.3, billboard: true}));
//   label.text = Std.string(score);
export declare class Text3D extends InstancedMesh {
	constructor(device: Device | null, font: FontFile, text: string, options?: Text3DOptions);
	static attach(node: Node, t: Text3D): Text3D;
	readonly font: FontFile;
	text: string;
	readonly size: number;
	readonly depth: number;
	readonly align: number;
	readonly material: Material;
	// turned to face the camera
	billboard: boolean;
	// its node (Text3D.attach's)
	readonly node: Node;
	// (its instance's matrix: its node's, turned to the camera when billboard)
	prepare(viewProj: Mat4): void;
}

// Clustered lighting (Forward+), opted in for scenes of many lights
// (renderer.use(new ClusteredLights(device, {maxLights: 256}))): the view
// cut into a grid of cells (Clusters: grid.x by grid.y tiles, grid.z slices
// of depth growing away from the camera), each cell listing the frame's
// lights that reach it (at most maxPerCell), and each pixel lit by its
// cell's lights instead of its draw's eight. The lists and the frame's
// lights (up to maxLights, the renderer's FrameLights: the most important
// to the view) go into one texture, the cluster map (R32F: each cell its
// count then its lights' rows, then a row a light), read by pbr's light
// loop where frame.clusters.x is on: no variant of any material more, no
// uniform block past GL ES 3.0's 16 KB or Metal's 4 KB (the renderer's 32 rows
// stay the draws'), one texture more (a pipeline's slots are 16), so it
// runs on WebGL2.
//
// Where the device has compute (Device.has(Compute)) the cells are
// assigned on the GPU (ClusterShader: a dispatch a frame, an invocation a
// cell, the lights copied in from a storage buffer), else on the CPU
// (Clusters.assign, then the map uploaded): the
// same test in the same order, so the same lists. Shadowed local lights
// take part with their tiles (Shadows). The camera is perspective. Nothing
// is allocated a frame.
export declare class ClusteredLights {
	// options: maxLights (256), grid ({x: 16, y: 9, z: 24}), maxPerCell (32),
	// gpu (true: on the GPU where the device can)
	constructor(device: Device, options?: ClusteredOptions);
	readonly device: Device;
	// the frame's lights it lights with at most
	readonly maxLights: number;
	// whether its cells are assigned on the GPU (the device has compute and
	// gpu was not turned off), else on the CPU
	readonly gpu: boolean;
	// the grid and its lists (the CPU's assignment, the map's layout)
	readonly clusters: Clusters;
	// the last frame's lights, its full cells' lights left out (the CPU's only)
	readonly lights: number;
	readonly overflow: number;
	// the CPU's last assignment, in ms (the GPU's: 0)
	readonly assignMs: number;
	attach(renderer: Renderer): void;
	dispose(): void;
}

// The view's grid of cells (froxels: tiles across the view, slices of
// depth growing exponentially from the camera) and the lights that reach
// each, on the CPU (ClusteredLights' path without compute; its compute
// path, ClusterShader, does the same work a cell an invocation). A light
// reaches a cell when its sphere (its range about it) meets the cell's box
// in the view; a cell lists the first perCell that do, in the frame's
// order. The lists are the cluster map's texels (map, R32F: a row a tile's
// row and slice, a cell a block of perCell + 1 texels: its count, then
// its lights' rows). Each light is tested against the cells its sphere's
// bounds touch (a few of the grid, not all of it); assign allocates
// nothing.
export declare class Clusters {
	constructor(tilesX?: number, tilesY?: number, slices?: number, perCell?: number, lights?: number);
	readonly tilesX: number;
	readonly tilesY: number;
	readonly slices: number;
	readonly perCell: number;
	// the cluster map: its width (tilesX * (perCell + 1), 12 at least) and
	// height (tilesY * slices, then lights), its first light's row, its texels
	readonly width: number;
	readonly height: number;
	readonly lights: number;
	readonly lightRow: number;
	readonly map: Uint8Array;
	// the last assign's lens (as ClusterGrid's: the slopes, the near depth, a slice's step of log depth)
	readonly slopeX: number;
	readonly slopeY: number;
	readonly near: number;
	readonly step: number;
	// the last assign's lists that were full (a light left out of a cell)
	readonly overflow: number;
	// the lens for a perspective projection, its slices from near to far
	// (each slice's depths, each tile's slopes: worked out once a frame)
	lens(projection: Mat4, near: number, far: number): void;
	// a cell's count, its k-th light's row
	count(x: number, y: number, z: number): number;
	light(x: number, y: number, z: number, k: number): number;
	// each cell's lights: of the count lights at (xs, ys, zs) (in the
	// world, their ranges rs), seen through view (the world to the view)
	assign(view: Mat4, xs: number[], ys: number[], zs: number[], rs: number[], count: number): void;
	// whether a sphere in the view (centre c, radius r) meets cell (x, y, z)'s
	// box: ClusterShader's test, the same numbers
	reaches(x: number, y: number, z: number, cx: number, cy: number, cz: number, r: number): boolean;
}

// Levels of detail, a component of a node: its meshes from the finest to
// the coarsest, each drawn while the node covers at least its `until` of
// the view's height (its bounds' sphere, Babylon's screen coverage: the
// same at any field of view or resolution), the last one's 0 by default
// (drawn however far; an until past 0: beyond it nothing is drawn). A
// level holds within a band of hysteresis about its threshold (0.1: 5%
// each way), so a node at the edge does not flicker between two. The
// renderer picks the level as it extracts the frame's draws (Lod.pick:
// set when a program first attaches one, so a program without links
// none of this); nodes of one level and material still batch.
//
//   Lod.attach(world.node("tree"), [{mesh: hi, until: 0.15}, {mesh: mid, until: 0.04}, {mesh: lo}]);
//
// A visible range (Lod.range: Godot's, three's LOD with nothing past it)
// draws a node and what is under it only while the camera is between
// begin and end metres from it: a cluster of nodes swapped for one far
// off (HLOD). The level is the last camera's: a world drawn by several
// cameras keeps one level a node.
export declare class Lod {
	constructor(levels: LodLevel[], hysteresis?: number);
	static readonly RANGE: unknown;
	// the levels on node (its MeshRenderer the first's, made if it has none)
	static attach(node: Node, levels: LodLevel[], hysteresis?: number): Lod;
	static of(node: Node): Lod | null;
	// node and what is under it drawn only while the camera is begin to end
	// metres from it
	static range(node: Node, begin: number, end: number): unknown;
	// a node's mesh seen through viewProj from eye: its level's (Lod), null
	// past its last level or out of its visible range, else mesh
	static meshOf(node: Node, mesh: Mesh, viewProj: Mat4, eye: Vec3): Mesh | null;
	// the share of the view's height a sphere (centre x, y, z, radius r)
	// covers through viewProj: its radius times the projection's vertical
	// scale (the length of the matrix's second row: the view a rotation)
	// over its depth (the fourth row's w; 1 for an orthographic camera)
	static coverageOf(viewProj: Mat4, x: number, y: number, z: number, r: number): number;
	// a level's threshold (none given: 0, however far)
	static untilOf(l: LodLevel): number;
	readonly levels: LodLevel[];
	// the band about each threshold a level holds within (a share of it)
	hysteresis: number;
	// the last level drawn (levels.length: none; -1 before the first frame)
	readonly level: number;
	// the last share of the view's height its bounds covered
	readonly coverage: number;
	// the level for a coverage, from the last one within its bands
	// (levels.length: none)
	choose(coverage: number): number;
}

// Instanced sets culled one instance at a time, opted in
// (renderer.use(new InstanceCulling(device))): each InstancedMesh's
// instances tested against the view (their mesh's bounds' sphere through
// each one's matrix) and each kept one drawn at its level (the set's
// levels: Lod's thresholds, a share of the view's height; without, its
// mesh), so a set of a hundred thousand rocks draws the few thousand in
// view, the far ones coarse. Where the device has compute and indirect
// draws (Device.has(Compute), has(Indirect)) it runs on the GPU
// (CullShader: a dispatch a set, the kept matrices appended to a buffer the
// draws read, their counts into indirect draws' arguments: no readback),
// else on the CPU (the same test, the kept ones' matrices uploaded by
// level). A set it does not take is drawn whole, as without it: one with
// custom data (its second buffer is not culled with it), a see-through one
// (its order is its own: Sprites), more than four levels or four
// primitives a level. Shadows draw every instance at the set's mesh.
// Nothing is allocated a frame but a set's buffers when first seen or
// grown.
export declare class InstanceCulling {
	// gpu false: on the CPU even where the device has compute
	constructor(device: Device, gpu?: boolean);
	static readonly MAX_LEVELS: number;
	static readonly MAX_PRIMITIVES: number;
	readonly device: Device;
	// whether it culls on the GPU (else the CPU)
	readonly gpu: boolean;
	// the last frame's instances kept and culled (the CPU's: the GPU's are
	// on the GPU), and its dispatches
	readonly kept: number;
	readonly culled: number;
	readonly dispatches: number;
	attach(renderer: Renderer): void;
	dispose(): void;
}

// An environment, opted in (renderer.use(new Environment(device,
// texture))): an equirectangular image (longitude across, latitude down;
// sRGB, mip-mapped) drawn behind the scene (at the renderer's BeforeOpaque
// point, as the sky) and lighting it: the standard material's ambient
// from it, diffuse from a small mip level along the normal, specular
// along the reflection from a level by roughness (mip levels standing in
// for a filtered map: a cheap image-based light). A program without one
// keeps the sky-and-ground ambient and links none of this.
//   var env = Environment.fromImage(device, "image/png", helder.asset.Asset.embed("sky.png")); // with Images.decode set (Images.png)
//
// Prefiltered (Environment.prefiltered): the light filtered once ahead,
// image-based lighting proper. An atlas of levels + 1 rows, each the whole
// sphere (equirectangular, width by width / 2): row k the specular light
// for a roughness of k / (levels - 1) (the environment convolved with
// GGX's lobe, the split sum's first half), the last the diffuse
// irradiance (cosine weighted, over pi); the material reads two rows by
// its roughness, blended, and the last along its normal. Small (128 x 448
// for 6 levels: 224 KB on the GPU), made by a tool once (Expansion's
// tools/envbake.py), no mips; the decoded pixels freed after the upload.
//   var env = Environment.prefiltered(device, "image/png", bytes, 6);
//
// Prefiltered by helder (Environment.prefilter): an equirectangular image
// (RGBA8 sRGB, or linear RGBA16F or RGBA32F: HDR) filtered at load into an
// prefiltered atlas as above (Prefilter: a compute dispatch where the device has
// compute, else a fragment pass; done at the first frame's BeforePass
// point), levels rows of roughness and the irradiance's, made from its
// spherical harmonics (sh: projected from the image here, the diffuse
// light ReflectionProbes and ProbeGrid fall back to); the image itself
// drawn behind the scene.
//   var env = Environment.prefilter(device, image.width, image.height, image.rgba); // or prefilterImage(device, mime, bytes)
export declare class Environment {
	// texture: mip-mapped (Images.mipmapped's), width twice its height; or
	// a prefiltered atlas of rows levels (prefiltered), width its width
	constructor(device: Device, texture: Texture, width: number, rows?: number);
	// an encoded image's environment (Images.decode must read it); null when it cannot
	static fromImage(device: Device, mime: string, bytes: Uint8Array): Environment | null;
	// a prefiltered atlas's environment (levels rows of roughness and the
	// irradiance's, each width by width / 2; Images.decode must read it); null when it cannot
	static prefiltered(device: Device, mime: string, bytes: Uint8Array, levels: number): Environment | null;
	// an equirectangular image's environment prefiltered by helder (width x
	// height texels, its rows top to bottom; RGBA8: sRGB-encoded, as an
	// image's; RGBA16F or RGBA32F: linear light, HDR): a prefiltered atlas,
	// rows of size x size / 2 texels, levels of roughness (Prefilter; samples a texel),
	// filled at the first frame drawn with it, and its harmonics (sh)
	static prefilter(device: Device, width: number, height: number, texels: Uint8Array, format?: number, options?: { size?: number; levels?: number; samples?: number }): Environment;
	// an encoded image's environment prefiltered by helder (prefilter; Images.decode must read it); null when it cannot
	static prefilterImage(device: Device, mime: string, bytes: Uint8Array, options?: { size?: number; levels?: number; samples?: number }): Environment | null;
	readonly device: Device;
	readonly texture: Texture;
	// the mip levels below the first (the map's width 2^levels)
	readonly levels: number;
	// how bright the environment is, as light (1: its colours)
	intensity: number;
	// whether it is drawn behind the scene (false: it only lights it)
	background: boolean;
	// a prefiltered atlas's levels of roughness (0: a mip-mapped image)
	readonly rows: number;
	// the diffuse light as spherical harmonics (prefilter's; else null)
	readonly sh: Sh | null;
	// (each renderer its pipeline: Probes' twin draws it too)
	attach(renderer: Renderer): void;
	dispose(): void;
}

// Light around a point as L2 spherical harmonics (Ramamoorthi and Hanrahan,
// "An Efficient Representation for Irradiance Environment Maps"): nine RGB
// coefficients of the radiance arriving from each direction (the real SH
// basis, bands 0 to 2), from which the diffuse light along any normal is a
// polynomial of it: smooth, cheap, free of seams. An Environment's diffuse
// light (Environment.sh), a LightProbe's, a ProbeGrid's at a point.
//
// coefficients: 27 floats, coefficient k's red, green and blue at 3k, in the
// order Y00, Y1-1 (y), Y10 (z), Y11 (x), Y2-2 (xy), Y2-1 (yz), Y20 (3z^2 - 1),
// Y21 (xz), Y22 (x^2 - y^2). Directions are the world's (y up).
//
// irradiance(n) is the irradiance along n over pi (the light a white
// Lambertian surface reflects: an environment atlas' irradiance row's
// meaning); pack writes it as the seven vectors a shader evaluates
// (irradianceOf in PbrShader: Unity's SHAr, SHAg, SHAb, SHBr, SHBg, SHBb, SHC).
export declare class Sh {
	constructor(coefficients?: number[]);
	// the nine basis functions at a unit direction, into out (nine floats)
	static basis(x: number, y: number, z: number, out: number[]): void;
	// the light of a sky over a ground (a hemisphere light: sky above,
	// ground below, the horizon between blended as the standard material's
	// ambient blends them by the normal's height)
	static ofHemisphere(sky: Vec3, ground: Vec3): Sh;
	// the radiance f gives each direction, projected (integrated over a grid
	// of the sphere, size rows of latitude by twice as many of longitude)
	static ofFunction(f: (arg0: Vec3) => Vec3, size?: number): Sh;
	// an equirectangular image's light (longitude across, -z at its centre,
	// latitude down: Environment's layout), its texels of format (RGBA8:
	// sRGB-encoded, decoded as the standard material decodes it, c^2.2;
	// RGBA16F, RGBA32F: linear), each its solid angle's share, times intensity
	static ofEquirect(width: number, height: number, texels: Uint8Array, format?: number, intensity?: number): Sh;
	// an IEEE 754 binary16's value
	static half(h: number): number;
	readonly coefficients: number[];
	// a copy
	copy(): Sh;
	// every coefficient 0
	clear(): Sh;
	// a light of colour c from the unit direction d (a delta: the sun's
	// light as a point of the sky), added
	addDirectional(d: Vec3, c: Vec3): Sh;
	// o's coefficients times w, added
	addScaled(o: Sh, w: number): Sh;
	// every coefficient times s
	scale(s: number): Sh;
	// a's blended towards b by t, into this (nothing allocated)
	setLerp(a: Sh, b: Sh, t: number): Sh;
	// the irradiance along the unit normal n over pi (Lambert's reflected
	// light for a white surface)
	irradiance(n: Vec3): Vec3;
	// the radiance arriving from the unit direction d (the band-limited light
	// itself, not convolved: a probe's preview)
	radiance(d: Vec3): Vec3;
	// the seven vectors of irradiance's polynomial (over pi) into out from at:
	// for each of red, green and blue its band 0 and 1 (x, y, z: the normal's
	// factors, w the constant), then its band 2's xy, yz, zz, zx, then the
	// x^2 - y^2 factor of each (rgb); what PbrObject's and the prefilter's
	// blocks hold
	pack(out: Vec4[], at?: number): void;
}

// A light probe, a component of a node: the light around its node's position
// as spherical harmonics (Sh: baked, projected from an image or a function,
// Sh.ofHemisphere), lighting the draws whose centres are within radius of it
// with Probes (three.js's LightProbe, placed). A draw takes the nearest
// probe that reaches it, blended towards the next nearest by their
// distances; a ProbeGrid that holds the draw comes first. Diffuse light
// only, a draw's (its centre's) and evaluated at its vertices: nothing
// per pixel.
export declare class LightProbe {
	constructor(sh: Sh, radius?: number);
	// probe on node (a node has one; the one it had is replaced)
	static attach(node: Node, probe: LightProbe): LightProbe;
	static of(node: Node): LightProbe | null;
	sh: Sh;
	// how far it reaches (scene units)
	radius: number;
	// its light's scale
	intensity: number;
	readonly node: Node;
}

// A grid of light probes, a component of a node: a box (size, centred on
// its node's position, the world's axes) of nx x ny x nz probes at its
// corners and between, each the light there as spherical harmonics (Sh).
// With Probes, a draw whose centre is in the box is lit by the probes
// around it, blended trilinearly on the CPU (Unity's light probes, on a
// grid): its diffuse light, per draw, evaluated at its vertices. Filled by
// a program (set, fill), or read from its bytes (read, write: baked once,
// by a tool or a program, kept as an asset).
//   var grid = new ProbeGrid(new Vec3(12, 4, 8), 4, 2, 3);
//   grid.fill(p -> Sh.ofHemisphere(...));
//   ProbeGrid.attach(world.node("gi"), grid);
export declare class ProbeGrid {
	constructor(size: Vec3, nx: number, ny: number, nz: number);
	// grid on node (a node has one)
	static attach(node: Node, grid: ProbeGrid): ProbeGrid;
	static of(node: Node): ProbeGrid | null;
	static read(b: Uint8Array): ProbeGrid;
	// the box's size (scene units) and its probes along each axis (2 or more)
	readonly size: Vec3;
	readonly nx: number;
	readonly ny: number;
	readonly nz: number;
	// each probe, x fastest, then y, then z
	readonly probes: Sh[];
	// its light's scale
	intensity: number;
	readonly node: Node;
	// probe (i, j, k)'s place relative to the box's centre
	offset(i: number, j: number, k: number): Vec3;
	at(i: number, j: number, k: number): Sh;
	set(i: number, j: number, k: number, sh: Sh): void;
	// each probe's light from f (its place, relative to the box's centre)
	fill(f: (arg0: Vec3) => Sh): void;
	// whether a point relative to the box's centre is inside it
	holds(p: Vec3): boolean;
	// the light at a point relative to the box's centre (held in the box),
	// its eight probes blended trilinearly, into out (nothing allocated)
	sample(p: Vec3, out: Sh): Sh;
	// the grid as bytes (its size, counts, each probe's 27 floats; read gives it back)
	write(): Uint8Array;
}

// A reflection probe, a component of a node: the scene seen from its node's
// position, captured once (six faces into a cube, then prefiltered into its
// column of Probes' atlas: its rows by roughness), reflected by the draws
// whose bounds are in its box (size: centred on the node, the world's
// axes), parallax-corrected: a reflection is looked up where it leaves
// the box, so a room's walls reflect where they are (Godot's and Unity's
// box projection). A draw takes the two probes that hold most of it, A
// blended over B (or the environment) by its share inside A's box, the
// box's walls soft over blend. Captured when first drawn with Probes, again after
// capture(); never every frame.
//   var hall = ReflectionProbe.attach(world.node("hall"), new ReflectionProbe(new Vec3(12, 4, 8), 0.5));
//   hall.node.position = new Vec3(0, 2, 0);
export declare class ReflectionProbe {
	constructor(size: Vec3, blend?: number);
	// probe on node (a node has one)
	static attach(node: Node, probe: ReflectionProbe): ReflectionProbe;
	static of(node: Node): ReflectionProbe | null;
	// its box's size (scene units), centred on its node
	size: Vec3;
	// the depth inside its box over which it fades out towards its walls
	blend: number;
	// its light's scale
	intensity: number;
	readonly node: Node;
	// captured again at the next frame drawn with Probes (the scene changed)
	capture(): void;
	// whether it has been captured since it was attached or capture() was called
	readonly captured: boolean;
	// how much of a box (its centre, its half size; the world's axes) is in
	// this one: 0 outside, 1 inside, the walls soft over blend (along each
	// axis the membership averaged over the box's extent, Simpson's rule)
	weight(cx: number, cy: number, cz: number, ex: number, ey: number, ez: number): number;
}

// Light probes and reflection probes, opted in (renderer.use(new
// Probes(device))): the world's LightProbes, ProbeGrids and
// ReflectionProbes light the standard material's draws (pbr's probes
// variants: PbrProbesShader).
//
//   - Each draw's diffuse light is its centre's (the run's centre for an
//     instanced run): a ProbeGrid holding it (trilinear), else its nearest
//     LightProbes, blended; evaluated at its vertices (spherical harmonics:
//     nothing per pixel). Without, the environment's or the sky's.
//   - Its reflections are its two reflection probes' (the two whose boxes
//     hold most of its bounds), box-projected per pixel, A blended over B
//     or the environment.
//
// The atlas: one RGBA16F texture (Prefilter's: a prefiltered atlas' rows by
// roughness, a column a probe), the probes variants' own texture
// (probesMap); the environment stays its own, read as before by every
// material (the probes' fallback). A probe is captured when first drawn and after
// capture(): the world drawn six times from its centre into a cube (an
// offscreen renderer of the renderer's light, sky and environment: a twin,
// its faces mirrored as a cube's are), then prefiltered into its column; at
// the frame's BeforePass point, a probe or two a frame (captures).
//
// Not lit by probes (they read the environment alone): the
// normal-mapped, skinned and see-through draws, instanced sets
// (InstancedMesh, Sprites) and materials of their own shader (Physical's
// among them).
export declare class Probes {
	constructor(device: Device, options?: { size?: number; levels?: number; max?: number; captureSize?: number; samples?: number });
	// the light probes' light at a point (a grid's holding it, else the
	// nearest two probes' that reach it, blended by their distances), into
	// out; false: none
	static lightAt(world: World, p: Vec3, out: Sh): boolean;
	readonly device: Device;
	// a cell's texels across (its height half), the rows of roughness, the
	// probes at most (the atlas' columns), a capture's face's texels
	readonly size: number;
	readonly levels: number;
	readonly max: number;
	readonly captureSize: number;
	// captures done a frame at most
	capturesPerFrame: number;
	// captures done so far
	readonly captures: number;
	// the atlas (Prefilter's: a column of rows a probe)
	readonly atlas: Texture;
	attach(renderer: Renderer): void;
	dispose(): void;
}

// A baked lightmap, a component of a node (Bevy's model, not a material's
// field: nodes of one mesh and one material share both and keep their own
// lightmaps): its texture (an atlas several nodes share), its rectangle of
// it (rect: xy the offset, zw the scale of the second uvs, TEXCOORD_1: a
// primitive's uv1), the light it holds (the irradiance over pi a white
// surface reflects: linear RGBA16F, or sRGB-encoded RGBA8 with srgb) times
// intensity. Drawn with Lightmaps (renderer.use(new Lightmaps())): mode
// Indirect (the default) replaces the ambient (the sky's, the environment's,
// the probes') and keeps the lights; All has the lights baked too, none
// added. A primitive without second uvs is drawn as before. Baking is a
// tool's (Blender's, another's atlas).
//   Lightmap.attach(node, new Lightmap(baked, new Vec4(0, 0, 0.5, 0.5)));
export declare class Lightmap {
	constructor(texture: Texture, rect?: Vec4, srgb?: boolean);
	// lightmap on node (a node has one)
	static attach(node: Node, lightmap: Lightmap): Lightmap;
	static of(node: Node): Lightmap | null;
	texture: Texture;
	rect: Vec4;
	intensity: number;
	mode: LightmapMode;
	// whether its colours are sRGB-encoded (an image's RGBA8; RGBA16F's are linear)
	srgb: boolean;
	readonly node: Node;
}

// Baked lightmaps, opted in (renderer.use(new Lightmaps(device))): the
// standard material's opaque draws of nodes with a Lightmap (and second
// uvs) are drawn with pbr's lightmap variant (PbrLightmapShader: the
// lightmap read at the second uvs placed in its rectangle, its light the
// ambient), one a node: a run of instanced draws stops at a lightmapped node.
// A program without one links none of it.
export declare class Lightmaps {
	constructor(device: Device);
	readonly device: Device;
	attach(renderer: Renderer): void;
}

// Area lights shaded with linearly transformed cosines (Heitz, Dupuy, Hill
// and Neubelt, "Real-Time Polygonal-Light Shading with Linearly Transformed
// Cosines"), opted in (renderer.use(new AreaLights(device))): in a frame
// with rect or disc lights (Light.rectArea, discArea), the standard
// material's opaque draws are drawn with pbr's area variants
// (PbrAreaShader), which integrate each area light's polygon (a disc as an
// octagon of its area) against the cosine and against GGX's lobe through
// the fitted tables (ltcMap: two 64 x 64 tables, three.js's, in RGBA16F
// one above the other: 64 KB, an embedded asset). The other materials, and
// a frame without the feature, light an area light as a point light at its
// centre. No shadows. A frame without area lights draws as before: its
// variants are compiled only when one is drawn.
export declare class AreaLights {
	constructor(device: Device);
	readonly device: Device;
	// the tables (RGBA16F, 64 x 128)
	readonly ltc: Texture;
	attach(renderer: Renderer): void;
	dispose(): void;
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
// Every call is recorded (Commands) and run in order (Replay): here, at
// each call that may throw and each pass's end (synchronous: headless
// surfaces, tests, games by default), or on the render thread (the thread
// option: helder.ui's windows), which owns the context and presents. A
// thread's device hands over what it recorded at pass and frame ends while
// the thread is free, and waits for it at beginFrame (one frame on its way
// at most), at calls that answer (readPixels, createShader: their errors
// thrown there), at settle and at dispose.
export declare class Device {
	// antialias: a window's frames multisampled, 4 samples a pixel (in the
	// browser the page's run option antialias decides when it is set);
	// headless surfaces stay single-sampled, readPixels reads the frame
	// resolved; render targets are multisampled by their own samples
	// (TextureDesc.samples, resolved through ColorTarget.resolve). thread:
	// executed and presented on the render thread (a window's, natively;
	// helder.ui's windows ask for it); HELDER_RENDER_THREAD=0 turns it off,
	// =1 on for every window
	static create(surface: Surface, options?: { antialias?: boolean; thread?: boolean }): Device;
	// until what was handed to the render thread has run: the last frame
	// presented (synchronous: at once). helder.ui's loop waits so before it
	// takes the next events, so that a frame shows the input it was drawn
	// for, as without the thread; a program that does not, overlaps its next
	// frame with this one's present (a frame more on its way, its input older)
	settle(): void;
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
	// what was recorded run (on the render thread: drained), then everything
	// let go, the context too
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
// macOS (helder.os.apple.MacWindow), Win32 on Windows
// (helder.os.windows.WinWindow), a canvas in the browser (WebAssembly:
// helder.os.web.CanvasWindow, its size in CSS pixels), X11 elsewhere
// (helder.os.linux.x11.X11Window); on Android the activity's window
// (helder.os.android.AndroidWindow: full screen, one per app, the size and
// title the system's), on iOS a UIWindow (helder.os.apple.IosWindow: the
// same); on Linux with WAYLAND_DISPLAY set, Wayland's
// (helder.os.linux.wayland.WaylandWindow; X11 where it cannot connect, or HELDER_X11=1).
export declare class Window {
	// (transparent: its pixels' alpha shows what is behind it, premultiplied;
	// where the system cannot, opaque: see transparent)
	constructor(title: string, width: number, height: number, titlebar?: "standard" | "inset" | "none", transparent?: boolean);
	readonly surface: Surface;
	// its title bar's text (the browser: the page's title)
	title: string;
	// its title bar's text (the browser: the page's title)
	readonly closed: boolean;
	// whether what is behind it shows through its clear pixels: asked for
	// when made, and the system composes it so (macOS, Windows through
	// DirectComposition, Wayland, X11 with a compositing manager, the
	// browser's canvas); false where it was not asked for or cannot be
	readonly transparent: boolean;
	// the surface's size in pixels
	readonly width: number;
	// the surface's size in pixels
	readonly height: number;
	// pixels per point (2 on a Retina display, the monitor's DPI / 96 on Windows,
	// the browser's devicePixelRatio; 1 on X11; iOS: the screen's native scale)
	readonly scale: number;
	// the soft keyboard's height over the window in points, 0 while it is
	// hidden (a signal): iOS's keyboard frame (UIKeyboardWillChangeFrame),
	// Android's IME insets, the browser's visual viewport against the
	// window; 0 on the desktop. A change comes with a Resize, the safe
	// area's bottom following it; keyboardDuration is its animation's
	// seconds where the system gives them (iOS's), else 0
	readonly keyboard: Read<number>;
	close(): void;
}

// The app loop, callback driven (Cocoa, GTK and the browser own their
// loops): run calls onEvent for each pending event, then onFrame, until
// quit() or the last window closes. The loop is hxmc's own, polling the
// system's events without waiting (MacWindow on macOS, WinWindow on
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
// UIKit's loop (helder.os.apple.IosApp): each turn runs the main run loop
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
// On macOS, iOS, Windows and Linux the loop runs on a thread of its own,
// the main thread the system's (OsThread), which reads the input while the
// program runs on: each event goes to its window's compositor first
// (Window.route: scrolling while the program is busy), then to the
// program's next poll; on iOS it turns UIKit's run loop, its scroll views'
// offsets the compositor's as they move. beforeEvents run at each turn's
// start.
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
	mods: Array<import("helder/os").Mod>;
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

export {};
