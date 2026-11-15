# TypeScript

`helder/scene` (src/helder/scene/index.ts, over `helder/scene/runtime`,
which `TypeScript.hx` declares: [helder.typescript](/src/helder/typescript/README.md))
is this package for TypeScript programs: World, Camera, Light, Material,
MeshRenderer, Shapes, Model, Renderer, PostProcess and its effects (Ssao,
Dof, Outline, Lut; ViewBuffers; `ToneMap`, `Antialias` and `DofMode` by
name; `Lut.of(device, size, grade)` a LUT from a grade written in
TypeScript, its `Vec3` returned into Haxe), InputMap (its bindings made by
Bindings: `actions.bind("jump", Bindings.key(0x20))`), FixedStep, and what
a scene is drawn with (helder.os's Window, App, Event and Surface,
helder.gfx's Device). A Node is the program's class over a node's handle
(its members `Script`'s functions: Node's own are inline), Vec3 and Quat
helder/gfx's values:

```ts
const world = new World("demo");
const eye = world.node("eye");
const camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
eye.position = vec3(0, 1, 4);
eye.lookAt(vec3(0, 0, 0));
```

The examples with a TypeScript twin show both, a tab each: the scene
graph's, node for node in either language:

<Example id="scene-nodes"/>

## A material of its own

A material of its own is `material(pbr.with({...}))`, as Haxe's
MaterialShader.material: `pbr` is the standard material's slot object
(src/helder/scene/pbr.ts: PbrShader.hx in TypeScript, keep the two in
step; tests/typescript/definitions/pbr.ts checks their text is the same),
and its value's `apply(material, {glow: bytes})` gives a material the
shader and its blocks (`params.glow.write(value, bytes)`):

```ts
type GlowParams = {color: Vec4, time: Vec4};
const Glow = material(pbr.with({
	emissive: (s: PbrSurface, p: {glow: GlowParams}): Vec3 => p.glow.color.xyz.mul(0.6 + 0.4 * sin(p.glow.time.x * 3 + s.world.x)),
}));
Glow.apply(orb, {glow: bytes});
```

The shading models are `helder/scene`'s too: `lambert`, `toon`, `phong`,
`unlit`, `matcap`, `normals` and `depth` (src/helder/scene/shading.ts,
helder.scene.render.shading's in TypeScript, checked the same text by
tests/typescript/definitions/shading.ts), so `material(toon.with({...}))`
is a toon material of one's own; `Material.toon({...})` and the other
factories, `Geometry`, `Curve3`, `Sprites` and `Light.hemisphere` are the
generated declarations' (`LightKind`, `SpriteMode` and `Blend` their
enums' values by name). A slot of several inputs is typed as its default:
`direct: (s: LitSurface, l: LightSample, p: {...}) => Vec3`. The 3d lane
draws `primitives` and `toon` from TypeScript too (tests/3d/ts/twins.ts),
node for node as Scenes.hx's, against the same goldens.

Phase 3's are there too: `Lines` (`LineJoin`, `LineCap` and `LineUnits`
by name) and `LineRenderer`, `DebugDraw` and the helpers (TypeScript has
no release build to compile `Debug` out of: it calls `DebugDraw`'s
functions), `world.raycast` with `Hit`, `HitList`, `RaycastOptions`,
`Raycaster` and `Bvh`, `Shapes.cpu`, and `Text3D` and `Geometry.text`
with a font from helder/asset. `Geometry.extrude` takes a helder.canvas
`Path`, which helder/canvas' TypeScript (a DOM facade) does not give: it
is Haxe's alone for now.

`tests/typescript/helder/scene.ts` checks it without a GPU, and
`tests/typescript/helder/picking.ts` phase 3's (rays at meshes of data
alone, a tree read back from its bytes, lines' points as uploaded,
DebugDraw's ring, helpers), a static build linking no device.
`examples/ts-scene` puts it together (scene.ts: examples/gltf-viewer's
sample model, a point light, glowing orbs of a material of their own; the
arrow keys turn the camera, an InputMap's axis), and the 3d lane draws its
scenes headless from TypeScript (tests/3d/ts/frames.ts, FrameCheck):
examples/glow's scene node for node, against Haxe's glow.png, and the
showcase against tsscene.png, which its Haxe twin (tests/3d/TsScene.hx,
Scenes' tsscene) draws too.

<Example id="ts-scene" file="scene.ts"/>
