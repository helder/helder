# Materials

## The renderer

```haxe
var renderer = new Renderer(device);
new GltfScene(Gltf.parse(Asset.embed("sample.glb")), device).instantiate(world);
// in the frame:
renderer.draw(enc, world, camera);   // one pass into the frame
```

The renderer extracts the world's meshes (`MeshRenderer`) into a draw
list (shown nodes inside the view, sorted by pipeline and material), then
records it with `PbrShader`: glTF's metallic-roughness model, the world's
lights ([Lights and shadows](lights.md)), a sky-and-ground ambient, ACES
tone mapping, sRGB output (or linear light into HDR targets:
[HDR and post-processing](post.md)). Nodes drawing the same primitive are
drawn in one instanced call (`renderer.instancing`, on by default:
[Instancing](instancing.md)). Programs draw at injection points:
`renderer.inject(BeforeOpaque | AfterOpaque | AfterPass, (enc, frame) -> ...)`;
features reach the renderer through `RenderFeature` (`renderer.use(...)`),
so unused ones are not linked. Shapes are made in code with `Geometry`
and `Shapes` ([Geometry](geometry.md)).

A frame records, in order: the shadow maps, the view buffers' prepass
(when an effect or the program asks for them: [Post effects](effects.md)),
the screen's ambient occlusion (`post.ao`), the main pass, the
`AfterPass` hooks; then post. Nothing is allocated per frame: the blocks
the renderer writes are kept and their fields set (a struct literal per
write would allocate on hxmc), and each uniform block's writer is a class
of its own (helder.gfx's `UniformWriter`: no closure).

## The standard material

```haxe
var gold = new Material("gold", new Vec4(1, 0.78, 0.34, 1), 1, 0.2);   // base colour, metallic, roughness
var lamp = new Material("lamp", new Vec4(0, 0, 0, 1), 0, 1, new Vec3(2.5, 1.6, 0.5));   // emissive: linear light
MeshRenderer.attach(world.node("ball"), Shapes.sphere(device, gold, 0.5));
```

A base colour (and its map), metallic and roughness (and theirs),
emission, an occlusion map and a normal map (with
`renderer.use(new NormalMaps(device))`, made before the models load: they
get tangents, the file's or computed). See-through materials
(`material.blend`, glTF's alphaMode BLEND) are drawn after the opaque
ones, farthest first. Materials also take a uv transform (`uvOffset`,
`uvRotation`, `uvScale`), an alpha cutoff (`alphaCutoff`: below it
dropped), a clear coat (`clearcoat`, `clearcoatRoughness`: a polished
dielectric layer, its reflection of the sun and the environment over the
base) and transmission (`transmission`: a thin surface, drawn see-through
twice: what is behind multiplied by its colour, then its reflections over
it). The rest of glTF's material extensions are the physical shaders',
below.

<Example id="scene-materials"/>

## The glTF material extensions

glTF's material extensions are `Material`'s fields, with glTF's names:

| Extension | Fields |
|---|---|
| KHR_materials_sheen | `sheenColor`, `sheenRoughness`, `sheenColorTexture`, `sheenRoughnessTexture` |
| KHR_materials_specular, _ior | `specularFactor`, `specularColor`, `specularTexture`, `specularColorTexture`, `ior` |
| KHR_materials_clearcoat | `clearcoat`, `clearcoatRoughness`, `clearcoatTexture`, `clearcoatRoughnessTexture`, `clearcoatNormalTexture`, `clearcoatNormalScale` |
| KHR_materials_transmission, _volume | `transmission`, `transmissionTexture`, `thickness`, `thicknessTexture`, `attenuationColor`, `attenuationDistance` |
| KHR_materials_iridescence | `iridescence`, `iridescenceIor`, `iridescenceThicknessMinimum`, `iridescenceThicknessMaximum`, `iridescenceTexture`, `iridescenceThicknessTexture` |
| KHR_materials_anisotropy | `anisotropy`, `anisotropyRotation`, `anisotropyTexture` |
| TEXCOORD_1, a transform a map | `textureTransforms` (a `UvTransform` each for the base colour, metallic-roughness, normal, occlusion and emissive maps) |

They are build-time options of `pbr` (`sheen`, `specular`, `clearcoat`,
`transmission`, `iridescence`, `anisotropy`, `uvSets`), not a shader
made at run time: a variant with one fills that layer of the surface
(`LitSurface`'s optional fields) between the surface's slots and the
lights, and its `direct` and `indirect` slots are the physical ones
(`physicalDirect`, `physicalIndirect`): Charlie's sheen, the specular
layer's f0 and f90, a clear coat with its own normal and roughness,
Belcour and Barla's thin film, anisotropic GGX with a bent reflection,
refraction through a volume with Beer's absorption. A layer a variant does
not fill reads as nothing and its code folds away (helder.gfx's `Prune`):
a variant without sheen has no sheen in its text. `PhysicalShader.of({sheen:
true, clearcoat: true})` is the `MaterialShader` of a set, each set
compiled once a build, linked only where it is named.

Which sets a game has comes from its models: `Model.of` reads each
material's extensions when compiling and names the sets they use, so a
game whose models have no sheen links no sheen. Materials made in code, and
models loaded at run time (`Model.load`, whose files are not known when
compiling), are drawn by `Physical`, the set with every extension, opted
in (one large shader):

```haxe
renderer.use(new Physical());                 // materials whose fields use an extension
renderer.use(new Transmission(device));       // the opaque frame behind see-through ones
```

<Example id="scene-physical" region="features,materials"/>

`Transmission` copies the opaque frame (with its mips) once a frame that
has a transmitting surface in view, after the opaque surfaces and the sky:
the frame's pass is split there, the copy read through the surface at the
point its refracted view leaves it, at the mip level of its roughness. It
needs the frame in a texture (an offscreen renderer: a `<Scene>`'s box,
`drawInto`); without it a transmitting surface shows the environment
refracted through it. A material's extension maps are read from up to two
images (glTF's channels: sheen's colour and roughness in one, the coat's
factor and roughness...: helder.gfx's 16 slots a shader).

Costs, against the renderer (`tests/3d/size/sizes.sh`, Windows x86-64 and
wasm32): see src/helder/scene/README.md's table; unused, nothing.

Against Khronos' sample viewer: [examples/gltf-showcase](/examples/gltf-showcase/README.md).

## A material of its own

The standard material is a slot object, `pbr` (`PbrShader`; helder.gfx's
`slots`, [DESIGN.md](/src/helder/compiler/DESIGN.md) 3): one shader whose
variants are the renderer's (`pbr.variant({normalMap, skinned,
instanced, prepass})`: `PbrShader`, `PbrNormalShader`, `PbrSkinnedShader`,
`PbrInstancedShader`, `PbrInstancedNormalShader`; the view buffers'
`PbrPrepassShader`, `PbrPrepassInstancedShader`, `PbrPrepassSkinnedShader`;
the shadow map's casters are `shadowCaster`'s) and whose slots a material replaces: `color`,
`alpha`, `normal`, `roughness`, `metalness` and `emissive` (of the
fragment's `PbrSurface`), `position` (of the vertex's `PbrPoint`), and
how light reaches the surface: `direct(s, l, p)`, the light one source
adds (the sun's, each point or spot light's; `l` a `LightSample`: its
`color` times its attenuation, its `shadow`, the two multiplied as
`radiance`, its `direction`, `ndotl`), and `indirect(s, env, p)`, the
ambient and the reflections (`env` an `IndirectLight`: `irradiance` along
the normal, `radiance` along the reflection, `occlusion`), each of the
surface with the other slots' results (`s` a `LitSurface`: `albedo`,
`alpha`, `metalness`, `roughness`, `normal`, `view`, `world`, `uv`, `up`).
A slot takes as many inputs as the slot object's type gives it before its
parameters. `MaterialShader.material(pbr.with({...}))` compiles them, at
build time, into a shader of the material's own (`material.shader`, every
variant the renderer draws with, for the GPU only: no CPU twin of its
stages is linked); a slot's parameters beyond the standard ones are
blocks of its own (`material.uniforms`, written by its `params`). Here the
emissive and colour slots are replaced:

<Example id="glow"/>

## Shading models

A shading model is a material's shader, made by `Material`'s factories,
three.js's materials by name:

```haxe
var grass = Material.toon({color: new Vec4(0.4, 0.8, 0.3, 1), steps: 3, shade: new Vec3(0.35, 0.4, 0.6)});
var sign  = Material.unlit({color: new Vec4(1, 0.9, 0.2, 1), texture: signImage});
var clay  = Material.matcap({matcap: clayImage});   // the normal in view space reads the sphere's picture
var debug = Material.normals();                     // MeshNormalMaterial; Material.depth(near, far): MeshDepthMaterial
var lam   = Material.lambert({color: c});           // 1 dot a light, no GGX: the cheap lit one for phones
var shiny = Material.phong({color: c, shininess: 60});
var std   = Material.standard({color: c, roughness: 0.4});   // pbr, as new Material(...)
```

| Factory | three.js | How | Per pixel, per light |
|---|---|---|---|
| `unlit` | `MeshBasicMaterial` | the colour times its texture, fogged | none |
| `matcap` | `MeshMatcapMaterial` | a lit sphere's picture (`matcap`, kept as the `emissiveTexture`) by the normal as the eye sees it | none (1 texture read) |
| `normals` | `MeshNormalMaterial` | the normal in view space as a colour | none |
| `depth(near, far)` | `MeshDepthMaterial` | the depth along the view, white at near, black at far (linear) | none |
| `lambert` | `MeshLambertMaterial` | each light's diffuse, the ambient's diffuse, no highlight | 1 dot |
| `toon` | `MeshToonMaterial` | each light's n.l times its shadow in `steps` bands, the side away from every light the albedo times `shade` | 1 dot and a step |
| `phong` | `MeshPhongMaterial` | Lambert's diffuse and a Blinn-Phong highlight (three's `shininess`, kept as the roughness of the same lobe), pbr's reflections | a pow |
| `standard` | `MeshStandardMaterial` | pbr: GGX, Smith and Schlick | GGX, Smith and Schlick |

The lit ones are `pbr` with `direct` and `indirect` replaced
(`helder.scene.render.shading`: `lambert`, `toon`, `phong`), so they keep
the shadows, the point and spot lights, the fog, normal maps, instancing
and skinning; toon's bands are per light, its shadow banded with it. The
unlit ones are a slot object of their own, `unlit` (its slots `color`,
`alpha`, `position`; its variants plain, skinned and instanced, no normal
map), which sums no light and reads no shadow map; `matcap`, `normals` and
`depth` are `unlit.with({color: ...})`. A material of one's own on any of
them is `MaterialShader.material(toon.with({...}))`. `material.toneMapped`
(three's) false shows a colour as it is, only encoded for an 8-bit target
(`normals` and `depth` by default).

Each factory references its own shader alone: a program that never calls
`Material.toon` links none of toon's. Unused, they cost the renderer 39 KB
natively and as wasm32 (its shader's text, the slots' structure); a lit
model, when used, costs its five variants' shader text, about 230 KB
natively (HLSL) and 300 KB as wasm32 (GLSL and WGSL)
(`tests/3d/size/sizes.sh`). Each row here is a model, each column a shape:

<Example id="primitives"/>

Tests: `src/helder/scene/render/shading/Shading.test.hx` (the slots on the
CPU), the 3d lane's `shading` (the seven in a row) and `toon` (soft
shadows and a point light; its TypeScript twin the same frame) frames,
`tests/typescript/definitions/shading.ts` (src/helder/scene/shading.ts the
same text as these).

The same in TypeScript: [TypeScript](typescript.md).
