# helder.scene: the 3D API, after a study of the engines

This is the roadmap's phase 5 item "the 3D API close to three.js, after a
study of three.js, Babylon.js, PlayCanvas, Godot and Bevy" (README.md,
Aims > Familiar APIs). It covers the areas where helder.scene trails
three.js: materials, lights and shadows, post-processing, and geometry,
helpers, picking and culling. Loaders and the ecosystem are out of scope.

It is a design. Nothing in it is built yet, except what "Today" says is
there. No spike was needed: every claim about helder's internals below was
read from the source, and the file is named where it matters.

The aim is the best API, not three.js's. three.js's names are kept where
they are what people know (`MeshToonMaterial`'s *toon*, `HemisphereLight`,
`CylinderGeometry`'s parameters, `Raycaster`'s results). Its object model
is not copied where another engine's is better.

## 0. Where helder starts, and what it must keep

**Today** (src/helder/scene/README.md):

- **Nodes.** Nodes are handles over flat stores. Components are `StoreKind`s
  (`Camera.KIND`, `MeshRenderer.KIND`, `Light.KIND`).
- **Math.** Vectors, quaternions and matrices are immutable values: `Vec3`,
  `Quat`, `Mat4`, `Aabb`.
- **Renderer.** One forward renderer. Draws are sorted and instanced
  automatically. Optional parts are opted in as `RenderFeature`s:
  `Shadows`, `Skinning`, `NormalMaps`, `Sky`, `Environment`,
  `GpuParticles`. Programs draw at injection points.
- **Materials.** One PBR material, `pbr` (`PbrShader`), is a slot object.
  `MaterialShader.material(pbr.with({...}))` compiles a material's own
  shader at build time, into every variant the renderer draws with. It
  works in Haxe and in TypeScript (`pbr.ts`, kept textually in step).
- **Lights.** The world's first directional light, with one shadow map
  (optionally two cascades, optionally PCSS-soft). Up to 4 point or spot
  lights in `PbrFrame`. A sky-and-ground ambient. An equirectangular or
  prefiltered-atlas environment.
- **Post.** HDR into RGBA16F, then `PostProcess`: bloom, tone maps, a
  grade, a vignette, grain, and the program's own `PostStage`s.
- **Shapes and picking.** `Shapes.box`, `sphere`, `capsule` and `plane`.
  `Pick.ray` tests bounds, not triangles.
- **Markup.** A prototype: `<Scene>`, `node`, `mesh`, `light`, `camera`
  and `instances`, with properties set by name.

**gfx's limits, which shape everything below.** These were read from
`src/helder/gfx`:

- **The floor is GL ES 3.0 and WebGL2.** Neither has storage buffers or
  compute. There are uniform blocks only, and GL ES 3.0 guarantees only
  16 KB each (`GL_MAX_UNIFORM_BLOCK_SIZE`).
- **Textures are 2D only.** `TextureDesc` has no cube or array textures,
  and the shader frontend has `Texture2D` alone.
- **Few formats.** RGBA8, RGBA8Srgb, R8, RG8, RGBA16F, R32F, Depth16,
  Depth32F, and the BC1, BC3 and ASTC 4x4 block formats. There is no
  RGBA32F and no integer format.
- **One colour target a pass.** Every back end reads `PassDesc.colors[0]`
  only (for example `GLBackend.hx:721`, `WebGPUBackend.hx:150`), so there
  is no MRT.
- **Multisampled depth is never sampled.** That is why Little Skies'
  TiltShift says "without depth (the `<Scene>`'s is multisampled, and the
  post chain is given none) the band is the screen's, not the world's".
- **Uniform arrays exist.** A block's field can be an array
  (`@:length(n) var positions:Array<Vec4>`), indexed by a value known at
  run time.

**Conventions every proposal below keeps:**

1. **Immutable math values.** Options are plain structures. Nothing
   returns a mutable vector to write through.
2. **Nodes as handles; components as `StoreKind`s.** A light, a probe, an
   LOD set or an outline is a component of a node. It is not a subclass of
   `Node` (three.js's and Babylon's `Object3D` and `Mesh` hierarchies) and
   not a node type (Godot's `OmniLight3D`).
3. **Opt-ins as `RenderFeature`s.** A program that never names a feature
   links none of its code or shaders. Factories such as `Material.toon`
   reference their shader only when called, so dead-code elimination
   drops them otherwise.
4. **Nothing allocated per frame.** Results go into structures the
   program owns (`Hit`), lists are refilled, and debug drawing goes into
   ring buffers.
5. **Slot materials compiled at build time.** There is no shader
   generator at run time, and no node graph shipped.
6. **The same API from TypeScript.** Each class is `@:typescript`, its
   options are object literals, and the slot objects are mirrored in
   `.ts` and checked textually equal (as `pbr.ts` is).
7. **Markup tags generated from the classes.** A tag's props are the
   class's properties or its options structure's fields, typed and
   checked when compiling. This is phase 5's "the tags generated from the
   3D API's classes".

**How the comparisons read.** In the tables below, "opt-in" says how a
feature is turned on, and "cost" says what it costs when it is unused and
when it is used.

## 1. Materials

### 1.1 Shading models (unlit, Lambert/Phong, toon, matcap, normal, depth)

| | Object model | Opt-in and cost |
|---|---|---|
| **three.js** | A class per model: `MeshBasicMaterial`, `MeshLambertMaterial`, `MeshPhongMaterial`, `MeshToonMaterial` (`gradientMap`: a 1D ramp texture), `MeshMatcapMaterial`, `MeshNormalMaterial`, `MeshDepthMaterial`, `MeshStandardMaterial`, `MeshPhysicalMaterial` [1] | Each class is its own shader program, generated when first used. All of them ship in the bundle unless tree-shaken. |
| **Babylon.js** | `StandardMaterial` (Blinn-Phong), `PBRMaterial`, `PBRMetallicRoughnessMaterial`; toon and cel shading come from the materials library or a `NodeMaterial` [2] | Defines are toggled by the material's fields, and shaders are compiled at run time per define set. |
| **PlayCanvas** | One `StandardMaterial` with a `useLighting` flag, a `shadingModel` and a `useMetalness` flag; unlit through `useLighting = false` [3] | Shader chunks are assembled at run time from flags. |
| **Godot 4** | One `StandardMaterial3D`: `shading_mode` (Unshaded, Per-Pixel, Per-Vertex), `diffuse_mode` (Burley, Lambert, Lambert Wrap, Toon), `specular_mode` (SchlickGGX, Toon, Disabled) [4] | Each combination is a generated shader, compiled when first used (an ubershader since 4.4). |
| **Bevy** | `StandardMaterial` with `unlit: bool`. Other models are a `Material` of your own, or `ExtendedMaterial<StandardMaterial, E>` [5][6] | Specialised pipelines keyed per material. |
| **Filament** | A material definition's `shadingModel`: `lit`, `unlit`, `subsurface`, `cloth`, `specularGlossiness`, compiled offline by `matc` [7] | Build time. Only the models you define ship. |
| **Unity URP** | Shaders: `Lit`, `Simple Lit` (Blinn-Phong), `Baked Lit`, `Unlit`; toon through Shader Graph's custom lighting [8] | Shader variants stripped at build time. |

**What is best.**

- **Godot's split.** A surface is one thing, and how light reaches it is
  another: Godot's `diffuse_mode`, and its shader language's `light()`
  function, which runs per light [9]. Toon, Lambert and wrap lighting
  are then a different *light function*, not a different material. They
  keep shadows, many lights, fog and the surface's textures without being
  rewritten.
- **Filament's offline compilation,** which helder already does.
- **three.js's names,** which are what people search for.

**Proposal.** `pbr` gains two slots, so a shading model is a slot override
of the same skeleton:

- `direct(s, l)`: the light one source adds, for each directional, point,
  spot or area light, shadowed;
- `indirect(s, env)`: the ambient, the probes' light and the reflections.

Here `s:Surface` is today's `PbrSurface` extended with the slots'
results: albedo, roughness, metalness, normal and view. `l:LightSample`
is the light's colour times its attenuation and shadow, its direction,
and its `NdotL`.

The models are slot objects in `helder.scene.render.shading`, each
`pbr.with({...})`:

```haxe
// what they are, in helder (compiled at build time, like any material)
final lambert = pbr.with({direct: (s, l) -> s.albedo * l.radiance * l.ndotl, indirect: diffuseOnly});
final toon = pbr.with({
	direct: (s, l, p:{toon:ToonParams}) -> s.albedo * l.radiance * ramp(l.ndotl * l.shadow, p.toon),   // banded, shadows banded too
	indirect: (s, env, p:{toon:ToonParams}) -> s.albedo * p.toon.shade.xyz,
});
final phong = pbr.with({direct: blinnPhong});   // three's MeshPhongMaterial, for ports; shininess from roughness
```

Unlit, matcap, normal and depth have no lights to sum. Each is a small
shader of its own, `unlit`, with the same `color`, `alpha` and `position`
slots. It reads no light uniforms, so a cheap material does not pay
`PbrFrame`'s 40 vectors.

Programs pick a model through factories on `Material`. Each factory sets
`material.shader` to the model's compiled `MaterialShader`, so a program
that never calls `Material.toon` links no toon shader:

```haxe
var grass = Material.toon({color: new Vec4(0.4, 0.8, 0.3, 1), steps: 3, shade: new Vec3(0.35, 0.4, 0.6)});
var sign  = Material.unlit({color: new Vec4(1, 0.9, 0.2, 1), texture: signImage});
var clay  = Material.matcap({matcap: clayImage});   // the normal in view space reads the sphere's picture
var debug = Material.normals();                     // MeshNormalMaterial; Material.depth(near, far): MeshDepthMaterial
var lam   = Material.lambert({color: ...});         // 1 dot a light, no GGX: the cheap lit one for phones
```

```html
<mesh geometry={Geometry.box()}><toonMaterial color={c} steps={3}/></mesh>
<mesh geometry={...} material={grass}/>              <!-- or a material made in code -->
```

**Why it is better than each engine:**

- **Toon keeps everything.** A toon material keeps shadows, clustered
  lights, fog and normal maps. three.js's `MeshToonMaterial` keeps
  three.js's lights, but its ramp is a texture lookup on the summed
  diffuse, so it can't band the shadow differently.
- **A program's own lighting model is twelve lines.** It is written as a
  slot (`pbr.with({direct: ...})`), checked when compiling, the same in
  TypeScript.
- **Unused models are not linked.** That is not true of three.js's
  classes unless tree-shaken, or of Godot's built-in modes.

**Cost.** The ALU cost of each model, from least to most:

| Model | Per pixel, per light |
|---|---|
| unlit | none |
| matcap | 1 texture read |
| lambert | 1 dot |
| toon | 1 dot and a step |
| phong | a pow |
| pbr | GGX, Smith and Schlick |

On a phone's fill-limited GPU, Lambert or toon at 1080p saves roughly
half the lit pixels' ALU against GGX. That is an estimate, to be measured
in phase 1's frames.

### 1.2 Points, lines with width, sprites and billboards

| | Points | Lines | Sprites / billboards |
|---|---|---|---|
| **three.js** | `Points` and `PointsMaterial` (size, `sizeAttenuation`) [10] | `LineBasicMaterial.linewidth` is "always 1 on most platforms" (GL core profile and WebGL ignore it) [11]. Wide lines are addons: `Line2`, `LineMaterial` and `LineSegments2`, as screen-space quads [12] | `Sprite` and `SpriteMaterial`, always facing the camera |
| **Babylon.js** | Particle and points cloud systems | `GreasedLine`: width in world or screen units, dashes, colour per segment [13] | `SpriteManager` and `Sprite`, billboard modes on meshes (`billboardMode`) |
| **PlayCanvas** | Particle system | `app.drawLine` and `drawLines` (debug, 1 px) | `billboard` in the particle system's or the material's chunks |
| **Godot 4** | `PointMesh`, plus `use_point_size` on a material | `ImmediateMesh` lines (1 px); wide lines need a shader | `Sprite3D`, `Label3D`, `billboard_mode` (Enabled or Y-Billboard) on `StandardMaterial3D` [4] |
| **Bevy** | No built-in | `Gizmos` (debug lines, with width) | No built-in (crates) |

**Proposal.** One instanced-quad primitive serves all three. gfx's `Lines`
and `Points` topologies stay for 1 px debug lines only.

- **`Sprites`** is an `InstancedMesh` of quads facing the camera:
  - `mode`: `Spherical` (always facing the camera), `Axis(up)` (turning
    about an axis: trees, Little Skies' clouds), or `Fixed`;
  - per-instance position, size, rotation, colour and an atlas cell;
  - a material, which may be `unlit` (halos, `Additive`) or lit (its
    normal faces the camera, so its lighting is cheap).
  
  Little Skies draws its clouds (Clouds.hx) and its lanterns' halos
  (Dressing.hx) as hand-made camera-facing quads. Those become
  `Sprites`.
- **`Lines`** are polylines or segments drawn as screen-space quads:
  - `width` in pixels or in metres (`widthUnits: Pixels | World`);
  - joins (Miter, Round or Bevel) and caps;
  - a colour per vertex;
  - `dash` and `gap`, with the dash's offset animatable (a moving dashed
    line);
  - depth tested, with an option to draw over everything.
  
  `Lines` is a RenderFeature (`renderer.use(new LineRenderer(device))`).
  A program writes its points into the line's flat array, as
  `InstancedMesh` takes its instances. The aim preview's dots in Little
  Skies (Game.hx: "the predicted path's dots (one instanced draw)") could
  be a dashed `Lines` with a fading colour.
- **Points** are `Sprites` with a round or soft mask and `size` in pixels
  or metres.

```haxe
var path = new Lines(device, 512, {width: 6, widthUnits: Pixels, join: Round, dash: 0.2, gap: 0.15});
Lines.attach(world.node("aim"), path);
// each frame: nothing allocated
path.count = n;
for (i in 0...n) path.setPoint(i, xs[i], ys[i], zs[i], fade(i));
```

```html
<lines of={path}/>
<sprites of={clouds} mode="axis"/>
```

### 1.3 The remaining glTF material extensions

| Extension | three.js (`MeshPhysicalMaterial` [14]) | Babylon.js (`PBRMaterial` [15]) | Godot 4 | Bevy (`StandardMaterial` [16]) | Filament [7] |
|---|---|---|---|---|---|
| sheen | `sheen`, `sheenColor`, `sheenRoughness` (+ maps) | `sheen.*` | no (rim only) | no | `cloth` model, `sheenColor` |
| specular | `specularIntensity`, `specularColor` | `metallicReflectance*` | `metallic_specular` | `reflectance`, `specular_tint` | `reflectance` |
| ior | `ior` | `indexOfRefraction` | no | `ior` | `ior` |
| volume, refraction | `thickness`, `attenuationColor`, `attenuationDistance`; a transmission render target of the opaque pass, mip-mapped | `subSurface.*` refraction | `refraction` (screen texture) | `thickness`, `attenuation_*`, `diffuse_transmission`, `specular_transmission` (a screen copy, `ScreenSpaceTransmission` steps) | `refraction` (screen or cubemap) |
| iridescence | `iridescence*` | `iridescence.*` | no | no | no |
| anisotropy | `anisotropy`, `anisotropyRotation` + map | `anisotropy.*` | `anisotropy` + flowmap | `anisotropy_*` | `anisotropy` |
| clearcoat and transmission textures | yes | yes | yes | yes | yes |

**What is best.** three.js and Babylon cover all of glTF, but at a price:
one physical shader per define set, built at run time. Filament and Bevy
pick the features by fields, and compile them offline (Filament) or
specialise them (Bevy).

**Proposal.** The extensions are **options of `pbr`**, folded at build
time like `normalMap`:

```haxe
pbr.variant({normalMap, skinned, instanced, sheen, specular, volume, iridescence, anisotropy, layerTextures})
```

`Material` gains their fields, each with glTF's name:

- `sheenColor`, `sheenRoughness`;
- `specularFactor`, `specularColor`, `ior`;
- `thickness`, `attenuationColor`, `attenuationDistance`;
- `iridescence`, `iridescenceIor`, `iridescenceThickness`;
- `anisotropy`, `anisotropyRotation`;
- and their textures, with clearcoat's and transmission's.

The options a material needs are worked out from its fields. They become
its pipeline key, as `normalMap` is now.

**Doing better: the variants come from the typed model.** `Model.of` and
the packed `.hxm3d` already know every material when compiling. The
macro, or the asset step, records which extension sets the model uses.
Only those variants are compiled and linked. A game with no sheen ships
no sheen code, and nothing is compiled at run time. three.js compiles
shaders at run time and can't know this ahead. Godot compiles at run time
too, and has an ubershader to hide the stall. A model loaded at run time
(`Model.load`) uses `Physical`, a RenderFeature holding the variant with
every extension (one big shader), opted in.

Two caveats on cost:

- **Volume and refraction** need the opaque frame as a texture, as three.js
  and Bevy do. That is a copy of the colour target after the opaque pass,
  with mip levels for rough glass: one RGBA16F copy, its mips about a
  third more. The `Transmission` feature owns it. Without the feature,
  today's thin transmission stays.
- **The variant count** is bounded. The options are chosen per material,
  and a typical model uses one to three sets.

### 1.4 The slot material system against TSL, NodeMaterial, visual shaders and Material

| | How a material is extended | When it compiles | Checked |
|---|---|---|---|
| **three.js TSL / NodeMaterial** | Node slots on a material: `colorNode`, `normalNode`, `positionNode`, `emissiveNode`, `outputNode`, `lightsNode`… Graphs are built by running JavaScript [17] | In the browser, when first used | Errors surface in the generated WGSL or GLSL at run time |
| **Babylon NodeMaterial** | A graph of blocks, edited in the Node Material Editor, saved as JSON. Material plugins inject code at named points of the standard shaders [18][19] | At run time | Graph connections are checked; code is not |
| **Godot visual shaders and shading language** | `vertex()`, `fragment()` and `light()` functions writing built-ins (`ALBEDO`, `ROUGHNESS`, `DIFFUSE_LIGHT`); visual shaders generate that language [9][20] | At load (cached), or with an ubershader | The language is typed, in the editor |
| **Bevy `Material` and `ExtendedMaterial`** | A struct with `AsBindGroup` plus WGSL files; an extension replaces the vertex or fragment entry and calls `pbr_fragment` functions [5][6] | At run time (naga) | Rust's types for the data, WGSL's at load for the code |
| **PlayCanvas** | Shader chunks: named GLSL strings replaced on `material.chunks` [3] | At run time | No |
| **Unity Shader Graph** | A graph with Master Stack blocks (Base Color, Normal…), custom function nodes | At build time (variants) | Graph types |
| **helder** (today) | `pbr.with({color, alpha, normal, roughness, metalness, emissive, position})`, plain Haxe or TypeScript functions | At build time, every variant | Fully, at the source line, in both languages |

helder's model already matches TSL's slots, with better checking and
nothing at run time (compiler/DESIGN.md 3, "Compared with TSL"). What it
lacks against the others:

1. **A `light()` slot.** This is Godot's, and the `direct` and `indirect`
   slots of 1.1 cover it.
2. **More slots.** TSL has `outputNode`, `opacityNode`, `aoNode`,
   `backdropNode` and `castShadowNode`; Godot has `vertex()`'s `NORMAL`.
   helder adds:
   - `normalVertex` (bending a normal with the position slot: wind on
     grass);
   - `occlusion`;
   - `output` (the final colour before fog, for dithering or a custom
     grade per material);
   - `shadowAlpha` (a cut-out a caster drops: leaves).
   
   The shadow casters are a slot object too (`shadowCaster`), so the
   position and shadow-alpha slots reach the shadow pass. TSL has this as
   `castShadowNode`; three's classic materials need `customDepthMaterial`.
3. **Varyings between slots,** for example a vertex slot computing a
   value the fragment reads. This is TSL's `varying()` and Godot's
   `varying`. Proposal: a slot object field `varyings:{wind:Float}` and a
   `p.varyings.wind` read on both sides, folded like options. This needs
   a change to `Slots`, recorded for phase 1.
4. **Instance data in slots.** `InstancedMesh`'s custom floats, read as
   `p.instance.custom0`, so a material of one's own varies per instance.
   Godot has `INSTANCE_CUSTOM`.
5. **A visual editor** would be the studio's, and it would write slot
   functions as code. helder ships no graph format, so there is nothing
   to keep in step and nothing interpreted at run time. Babylon's and
   Godot's graphs are a second source of truth beside their code.

## 2. Lights and shadows

### 2.1 Light types and object model

| | Types | Model, defaults |
|---|---|---|
| **three.js** | `AmbientLight`, `HemisphereLight`, `DirectionalLight`, `PointLight`, `SpotLight`, `RectAreaLight`, `LightProbe` [21] | Lights are `Object3D`s. Intensities are physical (candela) since r155. `decay` is 2 by default. `castShadow` is false by default, plus `light.shadow` (`mapSize` 512) |
| **Babylon.js** | `HemisphericLight`, `DirectionalLight`, `PointLight`, `SpotLight`, `RectAreaLight` [22] | A material evaluates at most `maxSimultaneousLights` lights (4 by default), the nearest; a `ShadowGenerator` per light |
| **PlayCanvas** | `directional`, `omni`, `spot`; area shapes (rect, disk, sphere) on omni and spot [23] | Clustered lighting is on by default since 1.56: up to 255 visible lights, a cell grid and an atlas for shadows and cookies [24] |
| **Godot 4** | `DirectionalLight3D`, `OmniLight3D`, `SpotLight3D`; no area lights | Forward+: clustered, 512 a cluster. Mobile: 8 omni and 8 spot a mesh, 256 a view. Compatibility: 8 a mesh [25] |
| **Bevy** | `DirectionalLight`, `PointLight`, `SpotLight`, `AmbientLight`, `EnvironmentMapLight`, `IrradianceVolume`; area through `PointLight.radius` (sphere lights) | Clustered forward. On WebGL2 the clusterable objects are a uniform buffer of 204 (under 16 KB) [26] |
| **Unity URP** | Directional, point, spot; area baked only | Forward: a per-object limit of additional lights; Forward+: clustered, no per-object limit, per-camera limits by platform (32 additional lights on mobile) [27][28] |
| **Filament** | directional, sun, point, spot, focused spot | Froxels assigned on the CPU each frame [7] |

**Proposal: the model.**

- **`Light` stays one component (`Light.KIND`) with a `kind`.** The kinds
  are `Directional`, `Point`, `Spot`, `Hemisphere`, `RectArea` and
  `DiscArea`. One store keeps lights flat and dense for the per-frame
  gather. Factories keep three.js's names:

  ```haxe
  Light.directional(color, intensity)       // as now
  Light.pointLight(color, intensity, range) // as now
  Light.spot(color, intensity, range, inner, outer)
  Light.hemisphere(sky, ground, intensity)  // three's HemisphereLight: today's renderer.sky and ground, as a light
  Light.rectArea(color, intensity, width, height)
  Light.discArea(color, intensity, radius)
  ```

- **Units stay helder's.** Colour times intensity in linear light, the
  inverse square windowed to `range` (glTF's KHR_lights_punctual), so
  imported files light the same. A `radius` on point and spot lights
  softens their highlight (Bevy's sphere lights, Karis' representative
  point), and costs one normalisation.

- **Shadows are a property of the light.** `light.castShadows = true` and
  `light.shadow = {size, bias, normalBias, radius, ...}`. They are not a
  generator object per light (Babylon), and not a renderer-wide map
  (helder today). The `Shadows` feature becomes the shadow *system*:

  - an **atlas** (one Depth32F texture, 4096² on desktop, 2048² on phones),
    tiled each frame by priority. A directional light gets its cascades
    (two or four). A spot light gets one tile, sized by its screen
    coverage. A point light gets six tiles (a cube's faces as six 90°
    frusta in the atlas, PlayCanvas' approach in clustered mode [24]),
    since gfx has no cube textures and an atlas keeps it at one binding;
  - a **budget**: `shadows.maxLocal` (4 by default, 2 on phones). Lights
    over it cast no shadow that frame, in priority order (distance, then
    intensity), as Godot's atlas quadrants do [29];
  - the **filters**: today's 3x3 and PCSS `soft(...)`, per light;
  - `shadows.cached` (static casters drawn once, redrawn when a caster
    moves or the light does: Godot's and Unity's cached shadows) for
    local lights that do not move. That is most lights in a level.

  `renderer.use(new Shadows(device))` keeps working: the first
  directional light casts, as now.

  ```haxe
  var lamp = Light.attach(world.node("lamp"), Light.spot(new Vec3(1, 0.8, 0.6), 30, 12, 0.3, 0.5));
  lamp.castShadows = true;
  lamp.shadow = {size: 512, bias: 0.002, radius: 0.05};
  renderer.use(new Shadows(device, {atlas: 2048, maxLocal: 2}));
  ```

  ```html
  <spotLight color={warm} intensity={30} range={12} inner={0.3} outer={0.5} castShadows shadowSize={512}/>
  <hemisphereLight sky={skyColor} ground={grassColor} intensity={1}/>
  ```

### 2.2 More lights: forward, then clustered (Forward+)

| | How | Notes |
|---|---|---|
| **three.js** | Every light in every lit shader (a loop), so the cost grows with lights × pixels. `TiledLighting` and `ClusteredLighting` are addons of the WebGPU renderer [30] | No WebGL path for clustered |
| **Babylon.js** | 4 nearest a material (`maxSimultaneousLights`). `ClusteredLightContainer` for point and spot lights (64×64 tiles by default, 16 depth slices; on WebGL2 through additive blending, not storage buffers; not for shadowed lights) [31] | |
| **PlayCanvas** | Clustered by default: lights and cells in textures, assigned on the CPU, so it works on WebGL2 [24] | 255 visible |
| **Godot 4** | Forward+ (Vulkan, D3D12, Metal): clustered on the GPU. Mobile: a list of lights per object [25] | |
| **Bevy** | Clustered forward. Light data in a uniform buffer on WebGL2 (204), storage buffers elsewhere [26] | |
| **Filament** | Froxels on the CPU, a record texture [7] | Runs on GL ES 3.0 |

**What fits helder.** PlayCanvas and Filament show that clustering on
GL ES 3.0 and WebGL2 works without compute: assign lights to cells on
the CPU, then upload the result as textures and a uniform block. Both
pieces work everywhere helder runs.

**Proposal: two tiers.**

1. **Forward, per object (the default).** The renderer picks each draw's
   8 most important local lights by distance and intensity against the
   object's bounds (Godot Mobile's and Unity's per-object lights). Their
   indices go into a small per-draw block: 8 bytes in `PbrObject`, as two
   `Vec4`s of indices. They index a frame block of up to 64 lights
   (64 × 64 B = 4 KB, well under 16 KB).
   - Instanced runs share one list, made from the run's bounds.
   - `pbr`'s light loop is unrolled to `MAX_LIGHTS` and folded by the
     option `lights: 8`.
   - This replaces today's fixed four with no new feature, and keeps the
     cost bounded per pixel.
2. **`ClusteredLights` (a RenderFeature).** For many lights:
   `renderer.use(new ClusteredLights(device, {maxLights: 256}))`.
   - **The grid.** A froxel grid of 16 × 9 × 24 by default (tiles across
     the view, exponential depth slices), assigned on the CPU each frame
     into preallocated arrays. Nothing is allocated. The work is
     O(lights × cells touched), each light's sphere or cone tested
     against the cells it can reach.
   - **Uploads.** Lights go into a uniform block (256 × 64 B = 16 KB, the
     GL ES floor). Cells are an RG8 texture of an offset and a count,
     with the lights' indices in an R8 texture (up to 255 lights, as
     PlayCanvas' 8-bit indices) or in RG8 for more.
   - **Shading.** `pbr`'s variant `clustered` reads the cell for the
     fragment and loops over its lights, up to `maxPerCell` (32 by
     default).
   - **Shadows.** Shadowed local lights take part, with their atlas
     tiles; Babylon's container excludes them.
   - **Area lights.** Rect and disc lights are clustered as their bounding
     sphere.
   - **gfx.** Needs only the formats it has (RG8, R8). If integer formats
     arrive later (R32UI), the index texture moves to them.

The renderer's directional lights (up to 4) stay outside the clusters, in
the frame block, as everywhere else.

```haxe
renderer.use(new ClusteredLights(device, {maxLights: 256, grid: {x: 16, y: 9, z: 24}, maxPerCell: 32}));
```

Mobile: tier 1 by default. `ClusteredLights` pays off past roughly 16
lights on screen. It costs per pixel one texel read, plus a loop over a
cell's lights (typically 2 to 6 in a level). The CPU assignment costs
about 0.1 ms for 100 lights (an estimate, measured in phase 4's
`clustered` frame).

### 2.3 Area lights (LTC) and the hemisphere light

- **Area lights.** three.js's `RectAreaLight` (no shadows, needs
  `RectAreaLightUniformsLib`'s LTC tables) [32], Babylon's
  `RectAreaLight` (LTC, in recent versions) [22] and PlayCanvas' area shapes
  (LTC; `areaLightsEnabled` in the clustered settings) [23] all use Heitz
  et al.'s linearly transformed cosines [33]. Godot and Bevy have none
  (Bevy approximates them with sphere lights).

  **Proposal.** `Light.rectArea` and `Light.discArea`, shaded with LTC:
  - two 64×64 lookup tables in RGBA16F (64 KB), made by code at build
    time (Haxe constants) into an embedded asset;
  - the `AreaLights` feature holds them, so no game pays for them
    unasked;
  - no shadows at first, as everywhere;
  - roughly 3× a point light per pixel, so they are best used one or two
    at a time on phones.
- **Hemisphere.** This is today's `renderer.sky` and `renderer.ground`,
  as a light. A world with a `Hemisphere` light uses it, else the
  renderer's fields as now. Nothing new is linked.

### 2.4 Light probes, spherical harmonics and reflection probes

| | Diffuse probes | Reflection probes |
|---|---|---|
| **three.js** | `LightProbe` (L2 SH, 9 coefficients). `LightProbeGenerator.fromCubeTexture` or `fromCubeRenderTarget`. One per scene, added to the ambient [34] | `CubeCamera` and `PMREMGenerator`; per-material `envMap` |
| **Babylon.js** | SH from an environment (`sphericalPolynomial`) | `ReflectionProbe` (a cube render), assigned per material |
| **PlayCanvas** | The ambient's SH from the skybox | Per-material cube maps; box-projected (`cubeMapProjection`) |
| **Godot 4** | `LightmapGI`'s probes (an SH grid), `VoxelGI`, SDFGI | `ReflectionProbe` (box projection, interior, blend distance) [35] |
| **Bevy** | `IrradianceVolume` (a voxel grid of ambient cubes, a 3D texture) [36] | `LightProbe` with `EnvironmentMapLight` (cubemaps; parallax-corrected) |
| **Unity** | Light Probe Groups (L2 SH, tetrahedral interpolation) [37] | Reflection Probes (box projection, blending) |

**Proposal.**

- **`Environment` learns SH.** The diffuse part of any environment is 9
  RGB coefficients (Ramamoorthi and Hanrahan [38]), projected from the
  image at load or in the asset step. That is 7 `Vec4`s in `PbrFrame`
  instead of today's irradiance row. It is cheaper, and free of seams.
- **`LightProbe` is a component of a node.** It holds L2 SH coefficients,
  baked or captured. A `ProbeGrid` is a box of probes on a regular grid,
  baked in the asset step or captured at load. The renderer interpolates
  each draw's SH trilinearly at the object's centre, on the CPU, into
  `PbrObject` (7 `Vec4`s: 112 B a draw). Instanced runs take the run's
  centre.
  - This is Unity's per-object model and costs nothing per pixel.
  - Per-pixel volumes (Bevy's, needing 3D textures) are not on GL ES 3.0
    without packing. They are left out.
- **`ReflectionProbe` is a component of a node.** It holds a box
  (parallax-corrected, as Godot and Unity do), a blend distance and an
  intensity. The image is a prefiltered octahedral map in a shared 2D
  atlas: one texture for all probes, rows by roughness, as
  `Environment.prefiltered` lays them out today.
  - Captured by the renderer (six faces into an octahedral map, then the
    GGX prefilter as passes), at load or on demand
    (`probe.capture()`), never per frame by default.
  - Each draw takes its two nearest probes, blended on the CPU by its
    centre, falling back to the `Environment`.
  - **Why octahedral 2D and not cubemaps.** One binding for every probe
    and the sky. No seam differences between back ends. And it works on
    today's gfx.
- **Cube textures in gfx** (`TextureDesc.layers: 6`, `cube: true`, and
  `TextureCube` in the shader frontend) are still worth adding: skyboxes
  from KTX2 and HDR cube files, and interop. Every back end has them
  (GL ES 3.0, WebGL2, Metal, D3D11, WebGPU). They are a gfx task beside
  this work, not a dependency of the renderer's probes. The same change
  adds 2D array textures (`layers: n`) and RGBA32F.
- **The prefilter in helder** (the roadmap's "still to come"): the GGX
  convolution as gfx passes, run at load (`Environment.prefilter(device,
  image)`) or in the asset step (`Pack --environment sky.hdr`). This
  replaces Expansion's `tools/envbake.py`.

```haxe
var probe = ReflectionProbe.attach(world.node("hall"), {box: Aabb.of(new Vec3(-6, 0, -4), new Vec3(6, 4, 4)), blend: 0.5});
probe.capture(renderer);                   // once, after the level is built
ProbeGrid.attach(world.node("gi"), PackedProbes.read(Asset.embed("level.probes")));   // baked
```

```html
<reflectionProbe position={...} box={hall} blend={0.5}/>
```

### 2.5 Baked lightmaps (TEXCOORD_1)

- three.js: `material.lightMap` reads `uv1` (`lightMapIntensity`) [39].
- Babylon: `lightmapTexture` and `useLightmapAsShadowmap`.
- PlayCanvas: a runtime lightmapper (`bake` on render components) [40].
- Godot: `LightmapGI` bakes in the editor [41].
- Bevy: a `Lightmap` component (image and uv rect) reading `UV_1` [42].
- Unity: Progressive Lightmapper.

**Proposal.**

- **A second uv set.** `PbrVertex` gains an optional `uv1`. The `lightmap`
  option reads it, and only that variant's layout carries it. glTF's
  TEXCOORD_1 is read by `Gltf` and by `Pack`.
- **Lightmaps are a component, not a material field.** `Lightmap.attach(node,
  texture, rect)` gives each node its rectangle of a shared atlas (Bevy's
  model). Instances of one mesh and one material then share the material
  and still batch. three's `material.lightMap` forces a material per
  baked object.
- **Bake modes.** `lightmap.mode`: `Indirect` (direct light stays dynamic;
  the default) or `All` (static lights are not evaluated for this node).
- **Baking stays outside.** Use Blender or another tool's atlas, or a
  later helder baker on the GPU. Packing the result (RGBM or RGBA16F,
  then BC6 or ASTC HDR when gfx gains them) is the asset step's.

## 3. Post-processing

### 3.1 The object model

| | Model | Order, merging |
|---|---|---|
| **three.js** | `EffectComposer` with `Pass`es (`RenderPass`, `UnrealBloomPass`, `GTAOPass`, `SSRPass`, `BokehPass`, `OutlinePass`, `SMAAPass`, `TAARenderPass`…) [43]. The WebGPU renderer has `PostProcessing` with TSL nodes (`pass()`, `ao()`, `dof()`, `bloom()`) | Order is the user's. Each pass is a full-screen draw. pmndrs/postprocessing merges effects into one pass [44] |
| **Babylon.js** | `DefaultRenderingPipeline` (bloom, DOF, FXAA, grain, chromatic aberration, sharpen, image processing), `SSAO2RenderingPipeline`, `SSRRenderingPipeline`, `MotionBlurPostProcess`, `TAARenderingPipeline`; a `PrePassRenderer` or `GeometryBufferRenderer` shares depth, normals and velocity [45][46] | Fixed inside a pipeline |
| **PlayCanvas** | `CameraFrame`: bloom, SSAO, TAA, DOF, vignette, grading, sharpening as options of one object [47] | Fixed, merged composite |
| **Godot 4** | `Environment` (glow, SSAO, SSIL, SSR, fog, adjustments, colour LUT) and `CameraAttributes` (DOF, exposure). `CompositorEffect` for one's own [48][49] | Fixed by the engine. Custom effects at callback points |
| **Bevy** | Components on the camera entity: `DepthPrepass`, `NormalPrepass`, `MotionVectorPrepass`, `ScreenSpaceAmbientOcclusion`, `ScreenSpaceReflections`, `DepthOfField`, `MotionBlur`, `TemporalAntiAliasing`, `Smaa`, `Fxaa`, `Bloom`, `Tonemapping` [50] | Fixed by the render graph. Effects add the prepasses they need |
| **Filament** | Options structures on the `View`: `setAmbientOcclusionOptions`, `setBloomOptions`, `setDepthOfFieldOptions`, `setTemporalAntiAliasingOptions`, `setScreenSpaceReflectionsOptions` [7] | Fixed. A frame graph culls what is off |
| **Unity URP** | Volume overrides (profiles blended by place), Renderer Features for one's own [51] | Fixed uber-post |

**What is best.** These have converged, outside three.js's classic
composer, and the convergence is right for a game engine:

- a **fixed order** owned by the engine, since the physically right order
  is known: AO in the lighting, SSR before the transparents, DOF and
  motion blur in linear light, bloom, the tone map, the grade, FXAA last;
- **options on one object** (PlayCanvas' `CameraFrame`, Filament's View,
  Godot's Environment, Bevy's camera components);
- **shared prepasses** that effects declare they need (Bevy, Babylon);
- **effects merged** into one composite (pmndrs, PlayCanvas, Unity);
- **a hook for one's own passes** at named points.

helder's `PostProcess` is already this shape: fields for bloom, the tone
map and the grade, and `PostStage`s after.

**Proposal.**

- **`PostProcess` grows fields, each null by default.** A null effect's
  class is not referenced, so it is not linked:

  ```haxe
  var post = new PostProcess(device);
  post.ao = new Ssao({radius: 0.5, intensity: 1, samples: 8, halfRes: true});   // GTAO
  post.dof = Dof.tiltShift({band: 0.2, falloff: 0.3, strength: 1});           // or Dof.focus({distance, aperture})
  post.outline = new Outline({width: 2, color: new Vec4(1, 0.8, 0.2, 1)});     // nodes selected: Outline.select(node)
  post.antialias = Fxaa;                                                         // None | Fxaa | Smaa | Taa
  post.lut = Lut.fromImage(device, Asset.image("grade.png"));                    // a 16³ strip, sampled 2D
  post.bloom = 0.05; post.toneMap = AgX;                                         // as now
  renderer.post = post;
  ```

- **The composite is a slot object folded by the effects present.** The
  tone map, grade, LUT, vignette, grain, bloom's mix, FXAA, outline's
  mix and DOF's mix happen in one full-screen pass. Its variant comes from
  which fields are set (compiled at build time, a few variants), as
  pmndrs merges effects at run time.
- **`PostStage`s keep their place** after the composite, plus two more
  points:
  - `BeforeComposite`, in linear light: Little Skies' tilt-shift blur
    belongs there;
  - `AfterOpaque`, with depth, through `renderer.inject`.
- **Markup is configuration of the box, not scene nodes:**

  ```html
  <Scene hdr grow={1}>
    <effects bloom={0.05} toneMap="agx">
      <ssao radius={0.5} samples={8}/>
      <dof mode="tiltShift" band={0.2}/>
      <outline width={2} color={gold}/>
      <fxaa/>
    </effects>
    ...
  </Scene>
  ```

  This mirrors @react-three/postprocessing's `<EffectComposer><Bloom/>…`.
  Each tag is generated from the effect's class, so a typo is a compile
  error.

### 3.2 The shared view buffers: a depth and normal prepass

**The problem.** helder's `<Scene>` draws multisampled, and a multisampled
depth is never sampled. gfx has no MRT. So today post gets no depth and
no normals.

**Proposal: `ViewBuffers`, a RenderFeature that effects request.**
`post.ao` and `post.dof` call `renderer.use(ViewBuffers.of(renderer))`
themselves; Bevy adds `DepthPrepass` the same way.

- **What it draws.** A single-sampled prepass of the opaque draws, at
  full or half resolution (`scale`), into:
  - a depth texture (Depth32F, sampled);
  - a colour target: RGBA8, view-space normal (octahedral, two channels),
    roughness, and a selection id.
  
  One pass, one colour target, so it works on today's gfx.
- **The shaders.** `pbr`'s `prepass` variant: the position, normal,
  roughness and alpha slots only. Custom materials get it for free,
  since it is a variant of their slot object.
- **Velocity.** Motion vectors are a further option (`velocity: true`),
  for TAA and motion blur. That needs MRT or a second pass, so it is
  desktop only until gfx has MRT.
- **The main pass.** The prepass's depth is not reused as the main pass's
  depth: the main pass is multisampled and the prepass is not. On
  desktops, which are not tilers, `ViewBuffers.depthOnly = false` could
  later share it in an early-Z way, if gfx learns to resolve depth.
- **Cost.** One more geometry pass. Its vertex work is about the main
  pass's; its fragment work is small. On a phone at 60 fps, a scene of
  Little Skies' size (main 17 draws, from the README's showroom numbers)
  costs about 0.3 to 0.6 ms, an estimate. At `scale: 0.5`, which AO and
  DOF both tolerate, it is a quarter of the fill.

### 3.3 The effects

The "cost on a phone" column is an estimate, at 1080×2400 with the
effect at half resolution unless marked. Each estimate is replaced by its
frame's measurement in the phase that builds it.

| Effect | three.js | Babylon | PlayCanvas | Godot | Bevy | helder proposal | Cost on a phone |
|---|---|---|---|---|---|---|---|
| **AO** | `GTAOPass`, `SAOPass`, `SSAOPass`; N8AO | SSAO2 | SSAO (in `CameraFrame`) | SSAO (not on Mobile) [25] | SSAO (GTAO-based, needs compute) | `Ssao`: GTAO, Jimenez et al. 2016 [52], half-res from `ViewBuffers`, 1 to 2 slices of 4 to 8 steps, a depth-aware bilateral upsample. It multiplies the indirect light only, in the composite or in `pbr` (option `ssao`: one texture read), not over the direct light (three's classic passes darken the whole frame) | 1 to 1.5 ms |
| **SSR** | `SSRPass` | `SSRRenderingPipeline` | no | yes (Forward+) | yes (deferred or prepass) | `Ssr`, desktop: a hierarchical-depth march, half-res, falling back to the probes. Off on mobile (no renderer listed ships it there) | desktop only |
| **DOF** | `BokehPass` | DOF in the default pipeline | DOF | `CameraAttributesPractical` near and far blur | `DepthOfField` (Gaussian, bokeh) | `Dof.focus({distance, aperture})` or `Dof.tiltShift({band, falloff})`. A circle of confusion from depth, gathered at half-res, then merged. Tilt-shift in world depth is what Little Skies' TiltShift.hx can't do now | 0.8 to 1.2 ms |
| **Motion blur** | addons | `MotionBlurPostProcess` | no | no | `MotionBlur` | `MotionBlur`: camera-only from depth and the last frame's view-projection (no velocity target: mobile-friendly); per-object with `ViewBuffers.velocity` on desktop | 0.5 ms |
| **AA** | `FXAAPass`, `SMAAPass`, `TAARenderPass` | FXAA, TAA | TAA | MSAA, FXAA, TAA, FSR2 | `Fxaa`, `Smaa`, `TemporalAntiAliasing` | MSAA stays the default (cheap on tiled GPUs, which resolve on chip). Then `Fxaa` in the composite (one variant), `Smaa` (three passes, desktop and web), and `Taa` (jitter plus velocity, desktop; it needs the prepass's velocity) | FXAA 0.3 ms |
| **Outlines and selection** | `OutlinePass` (mask, edge detect, blur) | `HighlightLayer`, `renderOutline` on meshes [53] | addons | the next-pass material trick | crates | `Outline`: the selection ids in `ViewBuffers`' colour target (8 bits: 255 groups, each a colour and width), edges found in the composite. `Outline.select(node, group)` is a component, so selection is data and a hover in markup is a binding | 0.3 ms |
| **God rays** | `GodRaysShader` (examples) | `VolumetricLightScatteringPostProcess` | no | volumetric fog | volumetric fog | `GodRays`: radial blur of the sky's coverage (from depth) toward the sun's screen point, at quarter-res (Mitchell's GPU Gems 3 approach). Volumetric fog is out of scope | 0.4 ms |
| **LUT grading** | `LUTPass` | `ColorGradingTexture` | grading | `adjustment_color_correction` (a LUT) | no (`ColorGrading` values) | `Lut`: a 16³ or 32³ LUT as a 2D strip (no 3D textures in gfx), one read in the composite after the tone map | ~0 |

## 4. Geometry and helpers

### 4.1 Primitives, text, lines and curves

| | Primitives | Text | Curves |
|---|---|---|---|
| **three.js** | `BoxGeometry`, `SphereGeometry`, `CylinderGeometry`, `ConeGeometry`, `TorusGeometry`, `TorusKnotGeometry`, `CapsuleGeometry`, `RingGeometry`, `CircleGeometry`, `PlaneGeometry`, `LatheGeometry`, `ExtrudeGeometry`, `ShapeGeometry`, `TubeGeometry`, polyhedra [54] | `TextGeometry` (extruded from typeface JSON); troika-three-text (SDF) | `Curve`, `CatmullRomCurve3`, `CubicBezierCurve3`, `CurvePath`, `Shape` and `Path` |
| **Babylon.js** | `MeshBuilder.CreateBox`, `Sphere`, `Cylinder` (cone by `diameterTop: 0`), `Torus`, `TorusKnot`, `Capsule`, `Disc`, `Ground`, `Lathe`, `ExtrudeShape`, `ExtrudePolygon`, `Tube`, `Ribbon`, `Polyhedron` [55] | `MeshBuilder.CreateText` (extruded) | `Curve3` (Bezier, Hermite, CatmullRom), `Path3D` |
| **PlayCanvas** | `BoxGeometry`, `SphereGeometry`, `CylinderGeometry`, `ConeGeometry`, `CapsuleGeometry`, `TorusGeometry`, `PlaneGeometry`, `DomeGeometry` | text elements (MSDF) in screen or world space | `Curve` (animation curves) |
| **Godot 4** | `PrimitiveMesh` resources: `BoxMesh`, `SphereMesh`, `CylinderMesh` (cone by top radius 0), `CapsuleMesh`, `TorusMesh`, `PlaneMesh`, `PrismMesh`, `QuadMesh`, `TextMesh`, `TubeTrailMesh`, `RibbonTrailMesh` [56]; CSG | `TextMesh` (extruded), `Label3D` (atlas, billboard) | `Curve3D`, `Path3D` |
| **Bevy** | `bevy_math` primitives (`Cuboid`, `Sphere`, `Cylinder`, `Cone`, `ConicalFrustum`, `Capsule3d`, `Torus`, `Tetrahedron`, `Extrusion<T>`), meshed by `Meshable::mesh()` builders [57] | none built in | `CubicCurve` (Bezier, Hermite, Cardinal, B-spline, NURBS) |

**What is best.**

- **Bevy separates the shape (math) from its mesh (a builder).** A
  `Cylinder` is a value you can also intersect, sample or bound; meshing
  it is a step with options (resolution, segments).
- **three.js's parameter names** are the most known.
- **Godot's `Label3D` and PlayCanvas' MSDF text** are what games want
  for text in the world, not extruded meshes.

**Proposal.**

- **`Geometry`, CPU-side generators returning `VertexData`** (positions,
  normals, uvs, indices, and tangents when asked). They are separate from
  upload, so they are testable without a GPU, usable by helder.physics
  for colliders, and packable by the asset step.
  - The names and defaults are three.js's, as option structures (typed,
    named, defaults filled):

    ```haxe
    Geometry.box({width, height, depth, segments});
    Geometry.sphere({radius, widthSegments, heightSegments});
    Geometry.cylinder({radiusTop, radiusBottom, height, radialSegments, heightSegments, openEnded});
    Geometry.cone({radius, height, radialSegments});        // cylinder with radiusTop 0
    Geometry.capsule({radius, length, capSegments, radialSegments});
    Geometry.torus({radius, tube, radialSegments, tubularSegments, arc});
    Geometry.torusKnot({...}); Geometry.ring({...}); Geometry.circle({...}); Geometry.plane({...});
    Geometry.lathe(points:Array<Vec2>, {segments, phiStart, phiLength});
    Geometry.extrude(shape:helder.canvas.Path, {depth, bevelSize, bevelSegments, curveSegments});
    Geometry.tube(curve:Curve3, {tubularSegments, radius, radialSegments, closed});
    Geometry.text(font:FontFile, text, {size, depth, bevelSize});   // helder.text's outlines, extruded
    ```

  - `Shapes.*` stays as the upload wrappers: `Shapes.of(device, geometry,
    material):Mesh`, with today's `Shapes.box` and the rest kept.
  - Little Skies' hand-written `Kit.cylinder` and `Kit.cone` (Kit.hx:452,
    470) become `Geometry.cylinder` and `Geometry.cone` with `flat:
    true` (vertices unshared, for flat shading, as the kit wants). A
    `flat` option on every generator matches its flat-shaded style.
- **Doing better: shapes from helder's own 2D stack.** `Geometry.extrude`
  takes a `helder.canvas` `Path`: the same curves, booleans and text
  outlines as 2D. So an SVG icon or a glyph run becomes a mesh with
  canvas' boolean ops (holes and unions), not three.js's separate `Shape`
  class.
- **`Curve3`, an immutable value:** `Curve3.catmullRom(points, closed,
  tension)`, `Curve3.bezier(a, b, c, d)`, and `Curve3.path([...])`. It
  has `point(t)`, `tangent(t)`, `length`, `pointAt(distance)` (by arc
  length, tabulated once), and `frames(n)` (parallel-transport frames,
  for tubes and for a camera on rails). The same value feeds `Lines` (a
  curve drawn) and animation (a node along a path).
- **Text in the world:** `Text3D`, a component drawing a `helder.text`
  run as quads from the window's glyph atlas, the same atlas ui uses.
  - Its size is in metres. It can be billboarded (Godot's `Label3D`),
    lit or unlit, and outlined.
  - It costs one instanced draw a text.
  - `<Ui>` stays for text that should be ui (layout, wrapping, input).
    `Text3D` is for text that belongs to the world: depth tested, sorted
    and fogged.

```html
<mesh geometry={Geometry.cylinder({radiusTop: 0.2, radiusBottom: 0.2, height: 1, flat: true})} material={rail}/>
<text3d text={score} size={0.3} billboard color={white}/>
```

In markup the geometry tags are generated too, r3f's way: `<mesh><cylinderGeometry
radiusTop={0.2} height={1}/><toonMaterial .../></mesh>`. A change to a
prop makes the geometry again: structure, not motion, as phase 5 says.

### 4.2 Debug helpers and a gizmo

| | Helpers | Immediate drawing | Gizmo |
|---|---|---|---|
| **three.js** | `AxesHelper`, `GridHelper`, `PolarGridHelper`, `BoxHelper`, `Box3Helper`, `ArrowHelper`, `CameraHelper`, `DirectionalLightHelper`, `PointLightHelper`, `SpotLightHelper`, `HemisphereLightHelper`, `SkeletonHelper`, `PlaneHelper` [58] | none | `TransformControls` (addon) [59] |
| **Babylon.js** | `AxesViewer`, `SkeletonViewer`, `PhysicsViewer`, the Inspector | `CreateLines` | `GizmoManager`: position, rotation, scale, bounding box [60] |
| **PlayCanvas** | none (editor) | `app.drawLine`, `drawWireSphere`, `drawWireAlignedBox` | `TranslateGizmo`, `RotateGizmo`, `ScaleGizmo` |
| **Godot 4** | editor-only gizmos | `ImmediateMesh` | editor |
| **Bevy** | none | `Gizmos`: `line`, `ray`, `sphere`, `cuboid`, `arrow`, `grid`, `axes`, retained or per frame, by config group [61] | crates |

**What is best.** Bevy's immediate gizmos for debugging (no objects to
manage, gone when not called), and three.js's helpers for the things
people want to see attached to a node.

**Proposal.**

- **`Debug`, immediate-mode, from anywhere.** Each frame's calls are
  written into a ring of line vertices, drawn by `DebugDraw` (a
  RenderFeature: one draw for lines, one for depth-ignoring lines), then
  cleared. Nothing is allocated.
  - Compiled out of release builds unless `-D helder.debugdraw`: the
    calls are `inline` and empty, so their arguments are not computed
    either.
  - The calls:

    ```haxe
    Debug.line(a, b, color); Debug.ray(origin, dir, length, color); Debug.aabb(box, color);
    Debug.sphere(center, r, color); Debug.axes(node, size); Debug.grid(center, size, divisions);
    Debug.frustum(camera, aspect); Debug.light(light); Debug.skeleton(skin); Debug.path(curve, n);
    ```

- **Helpers are components that call `Debug` each frame for their node,**
  so they are the same code:
  - `AxesHelper.attach(node, size)`;
  - `GridHelper.attach(node, {size, divisions})`;
  - `BoundsHelper.attach(node)`;
  - `LightHelper.attach(node)`;
  - `CameraHelper.attach(node)`;
  - `SkeletonHelper.attach(node)`.

  In markup: `<axesHelper size={1}/>`, `<gridHelper size={10}/>`,
  `<boundsHelper/>`.

  `GridHelper` is the exception: an infinite grid shader (fading with
  distance), not lines, for the studio's viewport.
- **`<TransformGizmo>`, in `helder.scene.view`.** It sits beside
  `<OrbitControls>` and competes in ui's gesture arena for each pointer,
  so a drag on its handle moves the node and a drag elsewhere orbits.
  - Modes: translate, rotate, scale; local or world space; snapping.
  - It binds to a `Signal<Vec3>` or writes the node.
  - It is the studio's scene inspector's (phase 5, "Games in the
    extension"), and examples' too.

### 4.3 Raycasting against triangles, with a BVH

| | |
|---|---|
| **three.js** | `Raycaster.intersectObjects` tests every triangle (bounds sphere first). three-mesh-bvh adds `computeBoundsTree` and accelerated raycasts, shapecasts and closest points; it is the de facto standard [62][63] |
| **Babylon.js** | `scene.pick` and `pickWithRay` (triangles; an octree optional) |
| **PlayCanvas** | none built in for meshes (physics raycasts) |
| **Godot 4** | through physics (`PhysicsRayQueryParameters3D` against collision shapes) |
| **Bevy** | `MeshRayCast` (a system param; AABB then triangles), and picking backends [64] |

**Proposal.**

- **`Raycaster`, as a value-free API.** `world.raycast(origin, dir,
  hit:Hit, ?options):Bool` fills a `Hit` the caller owns: node,
  distance, point, normal, primitive, triangle, barycentrics and uv.
  `raycastAll(…, hits:HitList)` refills a list. Nothing is allocated per
  cast.
  - The options are a max distance, a layer mask, `triangles` (default
    true) and `backfaces`.
  - `Pick.ray` stays as the bounds-only fast path.
- **`Bvh`, per primitive.** A flat array of nodes (SAH-binned, 8
  triangles a leaf) over the primitive's CPU positions.
  - Built when first cast against, or **in the asset step and packed in
    `.hxm3d`**, so a level loads with its BVHs made. That is better than
    three-mesh-bvh's build at load, and it needs keeping CPU positions:
    `PackedModel` gains `keepCpu: true` per mesh, the default for meshes
    marked pickable.
  - Skinned and morphed meshes cast against their bind pose's BVH,
    refitted on demand: `skin.refit()`, as three-mesh-bvh's `refit`.
  - Instanced meshes cast each instance's transformed ray against the
    shared BVH, after a top-level array of instance bounds.
- **`<Scene>`'s picking** (`SceneEvent`) gains triangles. A `pick="bounds"
  | "triangles"` prop on the box defaults to triangles once BVHs exist,
  and `SceneEvent` gains `normal` and `uv`. Painting on a model and
  placing on a surface come for free.

### 4.4 Culling and LOD

| | Frustum | Occlusion | LOD |
|---|---|---|---|
| **three.js** | `frustumCulled` per object (bounding sphere) | none built in | `LOD` (distance levels, `autoUpdate`, hysteresis); `BatchedMesh` per-instance culling [65] |
| **Babylon.js** | yes; octrees optional | occlusion queries per mesh (`occlusionType`), a frame late [66] | `addLODLevel(distance or screen coverage, mesh)` [67] |
| **PlayCanvas** | yes | no | no built-in |
| **Godot 4** | yes | `OccluderInstance3D` (Embree on the CPU, baked occluders) [68] | `visibility_range_begin` and `_end` with fade (HLOD), plus automatic mesh LOD (simplified at import) [69] |
| **Bevy** | yes (AABB) | GPU two-phase occlusion (compute, needs storage buffers) | `VisibilityRange` (with dithered crossfade) [70] |

**Proposal.** helder already culls by bounds against the view. Add:

- **`Lod`, a component.**
  - `Lod.attach(node, [{mesh: hi, until: 0.15}, {mesh: mid, until: 0.04},
    {mesh: lo}])`. The thresholds are screen-height fractions (Babylon's
    coverage, which does not change with the FOV or the resolution),
    with 10% hysteresis.
  - An optional dithered crossfade (`fade: 0.1`), which is `pbr`'s
    `lodFade` option: a dither discard by instance, as Bevy's.
  - The renderer picks a level during extraction. Instances of the same
    level still batch.
  - `Pack --lod 0.5,0.25` simplifies meshes at build time (quadric
    error, meshoptimizer's approach), as Godot's import does.
- **Visibility ranges:** `node.visibleRange = {begin, end, fade}`, Godot's
  HLOD for swapping clusters of nodes, the same machinery.
- **Occlusion.** gfx gains occlusion queries (GL ES 3.0's
  `ANY_SAMPLES_PASSED_CONSERVATIVE`, WebGPU's `occlusionQuerySet`,
  Metal's visibility results, D3D11's queries). `Occlusion` is a
  RenderFeature that tests large objects' bounds a frame late, as
  Babylon's occlusion queries do. It is last in the plan: Little Skies'
  levels and most mobile games are not occlusion-bound, and GPU-driven
  culling needs compute, which gfx lacks.
- **Shadow culling.** Shadow casters are culled per cascade and per atlas
  tile against the light's frustum. Static local lights' tiles are cached
  (2.1).

## 5. Markup and TypeScript, across all of it

- **Tags are generated, one per class or factory**, with their props from
  the class's public fields and the options structure's fields. That is
  phase 5's "the tags generated from the 3D API's classes":
  - materials: `<toonMaterial>`, `<lambertMaterial>`, `<unlitMaterial>`,
    `<matcapMaterial>`, `<standardMaterial>` (today's `Material`);
  - geometry: `<boxGeometry>`, `<cylinderGeometry>`…;
  - lights: `<pointLight>`, `<spotLight>`, `<directionalLight>`,
    `<hemisphereLight>`, `<rectAreaLight>`;
  - probes: `<reflectionProbe>`, `<lightProbe>`;
  - drawables: `<lines of>`, `<sprites of>`, `<text3d>`;
  - helpers: `<axesHelper>`, `<gridHelper>`, `<boundsHelper>`;
  - controls: `<TransformGizmo>`;
  - post: `<effects>` with `<ssao>`, `<dof>`, `<outline>`, `<fxaa>`, `<lut>`.

  A prop is checked against the field's type when compiling, which
  r3f's `args={[...]}` is not. Today's `light kind="point"` stays as an
  alias for `<pointLight>`.
- **Child tags of `<mesh>`** (`<cylinderGeometry>`, `<toonMaterial>`) set
  its geometry and material, r3f's `attach` convention. A geometry or
  material given as a prop is shared, not rebuilt.
- **Selection and hover as data:** `<node outline={hovered ? 1 : 0}>`
  binds `Outline.select`. `onPointerEnter` sets `hovered`. No pass to
  manage.
- **TypeScript.** Every class above is `@:typescript`, and its options
  are object literals typed from the Haxe structures. The shading models
  are slot objects mirrored in `src/helder/scene/shading/*.ts`, checked
  textually equal, as `pbr.ts` is (tests/typescript/definitions). Slot
  overrides of the new `direct` and `indirect` slots work as `pbr.with`
  does now.

## 6. Where helder does better than all of them

1. **Shading models as slots of one skeleton.** Toon or a program's own
   lighting keeps shadows, clustered lights, fog and normal maps, and
   compiles at build time, checked at the line, in Haxe and TypeScript
   alike. three.js has run-time TSL. Godot has `light()`, but compiles it
   at run time. Bevy has run-time WGSL.
2. **Material variants from typed models.** `Model.of` knows which glTF
   extensions a game's models use, so only those variants are compiled
   and linked. There is no shader compile at run time, and no
   ubershader.
3. **Unused features are not linked.** Lights, effects and helpers are
   RenderFeatures and factories, and `Debug` is compiled out of release.
   A Little Skies build pays for SSAO only if it sets `post.ao`.
4. **Zero-allocation frames, documented as tested.** Every per-frame API
   fills caller-owned results (`Hit`, `HitList`, line rings) and is
   checked by GcStats in `*.test.hx`, natively and as wasm32-wasi.
   three.js's `Raycaster` returns new arrays per cast.
5. **BVHs and probes made in the asset step,** packed with the model. A
   level loads pickable and lit.
6. **One shader language for materials, post stages and effects,** in
   both languages. Godot's visual shaders and Babylon's node graphs are a
   second source of truth beside their code.
7. **Shapes from the 2D stack.** Extrusions and text meshes come from
   `helder.canvas` paths and `helder.text` outlines, with booleans.
8. **Clustered lighting that runs on GL ES 3.0 and WebGL2,** as
   PlayCanvas and Filament do. Bevy's clustering on WebGL2 falls back to
   204 objects in a uniform buffer, and three.js has clustering in its
   WebGPU renderer only. helder's runs with shadowed lights included,
   which Babylon's container excludes.

## 7. Mobile budgets

**The target.** A 2021 mid-range Android (Adreno 619 or Mali-G57 class)
and an iPhone 12, at 60 fps, the 3D scene at a render scale of 0.75 or
more of a 1080×2400 screen, the GPU's frame at most 10 ms.

**These numbers are design estimates.** Each phase replaces its rows with
measurements: `bun run site:numbers` in CI, and the real devices' slots
in `page.json`.

| Budget | Phone (default) | Desktop and web (default) |
|---|---|---|
| Main pass draws (after instancing) | ≤ 150 | ≤ 1,000 |
| Shadow draws, all maps and tiles | ≤ 100 | ≤ 600 |
| Directional light | 1, shadowed: 1 map 2048² (or 2 cascades of 1024²), PCSS 8 to 12 taps | 1 to 2, 2 to 4 cascades, 16 to 32 taps |
| Local lights shading a pixel | ≤ 8 (forward, per object); `ClusteredLights` when more than 16 on screen | up to 32 a cell |
| Shadowed local lights | ≤ 2 (atlas 2048², cached when static) | ≤ 8 (atlas 4096²) |
| Area lights | ≤ 1 to 2 | ≤ 8 |
| Probes | SH per object (free per pixel); ≤ 2 reflection probes blended per draw | the same |
| Prepass (`ViewBuffers`) | at `scale: 0.5` when only AO and DOF read it | full |
| AO | GTAO half-res, 1 slice, 4 to 6 steps: ~1 to 1.5 ms | 2 slices, 8 steps |
| DOF | half-res gather: ~1 ms | full |
| Bloom | 4 levels from a quarter (`base = 2`): ~0.6 ms | 6 from half |
| AA | MSAA 4x (resolved on tile); FXAA when MSAA is off | MSAA or SMAA; TAA opt-in |
| SSR, TAA, per-object motion blur | off | opt-in |
| Post total (AO + DOF + bloom + composite) | ≤ 3.5 ms | ≤ 3 ms |
| Memory: shadow atlas + view buffers + post | ≤ 40 MB | — |

**The rules the defaults follow on phones:**

- **Prefer per-object work to per-pixel work:** SH, lights picked per
  draw, probes blended per draw.
- **Avoid storing what a tile could keep:** the prepass only when an
  effect asks, and depth single-sampled at half resolution.
- **Bound every loop** with a compile-time maximum folded into the
  variant.

## 8. Implementation plan, in phases

The order is by value to games like Little Skies against cost.

**Little Skies, read for this plan:**

- It is stylized: kit pieces flat shaded, a turf slot material
  (Turf.hx), emissive glows caught by bloom.
- It uses a soft directional shadow (`Shadows(r.device, 2048).soft(0.15,
  12, 0.08)`), point and spot lights, the post chain with a
  hand-written tilt-shift (TiltShift.hx, depth-less), and hand-written
  billboards (Clouds.hx, Dressing.hx).
- Its cylinders and cones are hand-written (Kit.hx).
- Its aim's dots are an instanced draw.

So geometry, cheap shading models, sprites, depth for DOF and outlines
come first. Indirect light and the full glTF extensions come later.
High-end screen-space effects come last.

Each phase lists its tests and frames. The frames are golden PNGs in
`tests/3d` (Scenes.hx, natively, and `3d-web` on WebGPU and WebGL2), their
TypeScript twins in `tests/3d/ts`, allocation checks in `*.test.hx`
natively and as wasm32-wasi, and an example where a feature needs showing.

### Phase 1: shapes, shading models, sprites (small, high value)

- **Geometry.** `Geometry` generators as `VertexData`: cylinder, cone,
  torus, torus knot, ring, circle, lathe, tube, with `flat`.
  `Curve3`. `Shapes.of`.
- **Shading.** `pbr`'s `direct` and `indirect` slots. The `lambert`,
  `toon` and `phong` slot objects. The `unlit` shader (unlit, matcap,
  normals, depth). The `Material.*` factories.
- **Slots.** `normalVertex`, `output`, `shadowAlpha`, the casters as
  slots, and varyings between slots (a `Slots` change).
- **Lights.** `Light.hemisphere`, and `Light.kind` with today's kinds.
- **Sprites.** `Sprites` (spherical and axis billboards, atlas cells),
  `<sprites of>`.
- **Markup.** Generated tags for the above: `<cylinderGeometry>`,
  `<toonMaterial>`, `<hemisphereLight>`.

Tests and frames:

- **Golden frames:** `primitives.png` (every generator, flat and smooth,
  normals checked), `toon.png` (toon with soft shadows and a point
  light), `shading.png` (unlit, matcap, normals, depth, lambert, phong
  and pbr in a row), `sprites.png` (axis and spherical, additive halos),
  `hemisphere.png`.
- **Unit tests:** `Geometry.test.hx` (vertex counts, closed and manifold
  where it should be, normals unit, uv ranges; three.js's counts for the
  same parameters), `Curve3.test.hx` (arc length, frames without flips).
- **TypeScript:** twins of `toon.png` and `primitives.png`.
- **Example:** `examples/primitives`; Little Skies' Kit moved onto
  `Geometry`, pixels unchanged.

### Phase 2: view buffers and the first screen-space effects

- `ViewBuffers` (a single-sampled depth plus normal, roughness and id
  prepass; `scale`).
- `PostProcess` fields, and the composite as a folded slot object.
- `Dof` (focus and tilt-shift), `Ssao` (GTAO half-res), `Outline` with
  `Outline.select`, `Fxaa`, `Lut`.
- `<effects>` markup.
- The `BeforeComposite` stage point.

Tests and frames:

- **Golden frames:** `prepass.png` (depth and normals shown),
  `ssao.png`, `dof.png` (focus), `tiltshift.png` (a far island in the band
  blurred by depth), `outline.png` (two groups, through a transparent
  surface), `fxaa.png`, `lut.png`.
- **Unit tests:** a GcStats run of a frame with every effect (nothing
  allocated).
- **Draw counts:** `--stats` gains `prepassDraws`; the README's
  draw-calls table gains its row.
- **Example:** `examples/postfx` (each effect toggled); Little Skies'
  TiltShift replaced by `Dof.tiltShift`, measured on its page's numbers.

### Phase 3: lines, debug drawing, picking

- `Lines` (pixel or world width, joins, dashes) with `LineRenderer`.
- `Debug` and `DebugDraw`, and the helpers.
- `GridHelper`'s infinite grid.
- `Raycaster`, `Hit` and `HitList`; `Bvh` (built on first cast, packed by
  `Pack`).
- `<Scene pick="triangles">`; `SceneEvent.normal` and `uv`.
- `Text3D`.

Tests and frames:

- **Golden frames:** `lines.png` (widths in pixels and metres, joins,
  dashes, behind and in front), `debugdraw.png` (each call),
  `helpers.png`, `text3d.png`.
- **Unit tests:** `Bvh.test.hx` (against brute force on random rays over
  Sponza's and a generated mesh's triangles, identical hits; nothing
  allocated per cast; packed equal to built), `Raycaster.test.hx`.
- **3d-ui:** a tap on a mesh's triangle gives its uv
  (`tests/3d-ui/SurfaceTest.hx`).
- **Example:** `examples/picking` (paint on a model).

### Phase 4: lights at scale and their shadows

- Per-object light lists (8 per draw, 64 in a frame).
- `ClusteredLights` (CPU froxels, uniform block, RG8 and R8 textures).
- The `Shadows` atlas: spot and point (six tiles) shadows, a budget,
  cached static tiles, per-light filters.
- `light.castShadows` and `light.shadow`.
- `Lod` and visibility ranges (cheap, and needed by large scenes).

Tests and frames:

- **Golden frames:** `lights8.png` (8 lights a draw), `clustered.png`
  (128 lights on a plane and Sponza, the same as brute force within a
  tolerance), `spotshadow.png`, `pointshadow.png`, `shadowatlas.png`
  (budget exceeded: priority), `lod.png`.
- **Unit tests:** `Clusters.test.hx` (cell assignment against brute
  force; nothing allocated; 256 lights' CPU time recorded), `Lod.test.hx`
  (hysteresis).
- **Example:** `examples/lights` (Sponza at night, 200 lights), with
  the site's numbers for it.

### Phase 5: indirect light

- **gfx (a gfx task, alongside):** cube textures, 2D arrays and RGBA32F
  on every back end, with `TextureCube` in the shader frontend.
- The environment prefilter in helder (passes at load, and `Pack
  --environment`). SH for the environment's diffuse.
- `LightProbe`, `ProbeGrid` (baked in the asset step), `ReflectionProbe`
  (box-projected, an octahedral atlas, captured).
- Lightmaps (`uv1`, the `lightmap` option, `Lightmap.attach`).
- Area lights (LTC, the `AreaLights` feature).

Tests and frames:

- **Golden frames:** `sh.png` (the environment's SH against today's
  irradiance row), `probes.png` (a room lit by a probe grid, a box
  reflection probe on a floor), `lightmap.png` (a glTF with TEXCOORD_1
  and a baked map), `arealight.png` (a rect and a disc over rough and
  smooth floors, against three.js's LTC reference).
- **Unit tests:** `Sh.test.hx` (projection of known functions), and
  gfx's cube and array frames in the gfx lane.
- **Example:** `examples/gltf-showcase` gains its environments
  prefiltered by helder.

### Phase 6: glTF materials, complete

- Clearcoat's and transmission's textures.
- The `KHR_materials_ior`, `_specular`, `_sheen`, `_iridescence`,
  `_anisotropy` and `_volume` options.
- `Transmission` (the opaque frame copied with mips, refraction).
- Variants chosen from typed models at compile time; `Physical` for
  models loaded at run time.

Tests and frames:

- **Golden frames:** Khronos' sample models in
  `examples/gltf-showcase` and `tests/3d`: SheenChair, IridescenceLamp,
  AnisotropyBarnLamp, TransmissionTest, the ior and specular tests,
  DragonAttenuation, compared with the sample viewer's renders.
- **Size:** a size test (`tests/3d/size`) that a model without an
  extension links no code of it.

### Phase 7: the high end (desktop and web first)

- `Ssr`, with velocity in the prepass (MRT in gfx, or a second pass).
- `Taa`, `Smaa`, per-object `MotionBlur`, `GodRays`.
- Occlusion queries in gfx, and `Occlusion`.
- `<TransformGizmo>` and the studio's scene inspector on it.

Tests and frames:

- **Golden frames:** `ssr.png`, `taa.png` (a still after N frames),
  `smaa.png`, `motionblur.png`, `godrays.png`, `occlusion` (draws
  culled, counted by `--stats`).
- **3d-ui:** a gizmo drag test in `tests/3d-ui`.

## Sources

1. three.js materials: https://threejs.org/docs/pages/MeshToonMaterial.html, https://threejs.org/docs/pages/MeshMatcapMaterial.html, https://threejs.org/docs/pages/MeshLambertMaterial.html, https://threejs.org/docs/pages/MeshBasicMaterial.html, https://threejs.org/docs/pages/MeshNormalMaterial.html, https://threejs.org/docs/pages/MeshDepthMaterial.html
2. Babylon.js materials: https://doc.babylonjs.com/features/featuresDeepDive/materials/using/materials_introduction
3. PlayCanvas StandardMaterial: https://api.playcanvas.com/engine/classes/StandardMaterial.html; shader chunks: https://developer.playcanvas.com/user-manual/graphics/shaders/
4. Godot StandardMaterial3D: https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html
5. Bevy `Material`: https://docs.rs/bevy/latest/bevy/pbr/trait.Material.html
6. Bevy `ExtendedMaterial`: https://docs.rs/bevy/latest/bevy/pbr/struct.ExtendedMaterial.html
7. Filament: https://google.github.io/filament/Filament.html; materials: https://google.github.io/filament/Materials.html
8. Unity URP shaders: https://docs.unity3d.com/Manual/urp/shaders-in-universalrp.html
9. Godot spatial shaders (`light()`): https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html
10. three.js `PointsMaterial`: https://threejs.org/docs/pages/PointsMaterial.html
11. three.js `LineBasicMaterial.linewidth`: https://threejs.org/docs/pages/LineBasicMaterial.html
12. three.js `Line2` and `LineMaterial`: https://threejs.org/docs/pages/Line2.html, https://threejs.org/examples/#webgl_lines_fat
13. Babylon GreasedLine: https://doc.babylonjs.com/features/featuresDeepDive/mesh/creation/param/greased_line
14. three.js `MeshPhysicalMaterial`: https://threejs.org/docs/pages/MeshPhysicalMaterial.html
15. Babylon PBR: https://doc.babylonjs.com/features/featuresDeepDive/materials/using/introToPBR
16. Bevy `StandardMaterial`: https://docs.rs/bevy/latest/bevy/pbr/struct.StandardMaterial.html
17. three.js TSL: https://github.com/mrdoob/three.js/wiki/Three.js-Shading-Language
18. Babylon NodeMaterial: https://doc.babylonjs.com/features/featuresDeepDive/materials/node_material/nodeMaterial
19. Babylon material plugins: https://doc.babylonjs.com/features/featuresDeepDive/materials/using/materialPlugins
20. Godot visual shaders: https://docs.godotengine.org/en/stable/tutorials/shaders/visual_shaders.html
21. three.js lights: https://threejs.org/docs/pages/HemisphereLight.html, https://threejs.org/docs/pages/LightShadow.html
22. Babylon lights: https://doc.babylonjs.com/features/featuresDeepDive/lights/lights_introduction; area lights: https://doc.babylonjs.com/features/featuresDeepDive/lights/areaLights
23. PlayCanvas area lights: https://developer.playcanvas.com/user-manual/graphics/lighting/area-lights/
24. PlayCanvas clustered lighting: https://developer.playcanvas.com/user-manual/graphics/lighting/clustered-lighting/
25. Godot renderers' limits: https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html
26. Bevy clustering (`ClusterConfig`, `MAX_UNIFORM_BUFFER_CLUSTERABLE_OBJECTS`): https://docs.rs/bevy/latest/bevy/pbr/enum.ClusterConfig.html, https://docs.rs/crate/bevy_light/latest/source/src/cluster/mod.rs
27. Unity URP light limits: https://docs.unity3d.com/Manual/urp/lighting/light-limits-in-urp.html
28. Unity URP Forward+: https://docs.unity3d.com/Manual/urp/rendering/forward-plus-rendering-path.html
29. Godot lights and shadows (shadow atlas): https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html
30. three.js `TiledLighting` and `ClusteredLighting`: https://threejs.org/docs/pages/TiledLighting.html, https://threejs.org/docs/pages/ClusteredLighting.html
31. Babylon clustered lighting: https://doc.babylonjs.com/features/featuresDeepDive/lights/clusteredLighting
32. three.js `RectAreaLight`: https://threejs.org/docs/pages/RectAreaLight.html
33. Heitz, Dupuy, Hill, Neubelt, "Real-Time Polygonal-Light Shading with Linearly Transformed Cosines", 2016: https://eheitzresearch.wordpress.com/415-2/
34. three.js `LightProbe`: https://threejs.org/docs/pages/LightProbe.html
35. Godot reflection probes: https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/reflection_probes.html
36. Bevy irradiance volumes: https://docs.rs/bevy/latest/bevy/pbr/irradiance_volume/index.html
37. Unity light probes: https://docs.unity3d.com/Manual/LightProbes.html
38. Ramamoorthi and Hanrahan, "An Efficient Representation for Irradiance Environment Maps", 2001: https://graphics.stanford.edu/papers/envmap/
39. three.js `MeshStandardMaterial.lightMap`: https://threejs.org/docs/pages/MeshStandardMaterial.html
40. PlayCanvas runtime lightmaps: https://developer.playcanvas.com/user-manual/graphics/lighting/runtime-lightmaps/
41. Godot LightmapGI: https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/using_lightmap_gi.html
42. Bevy `Lightmap`: https://docs.rs/bevy/latest/bevy/pbr/struct.Lightmap.html
43. three.js `EffectComposer`: https://threejs.org/docs/pages/EffectComposer.html
44. pmndrs/postprocessing: https://github.com/pmndrs/postprocessing
45. Babylon default rendering pipeline: https://doc.babylonjs.com/features/featuresDeepDive/postProcesses/defaultRenderingPipeline
46. Babylon SSR pipeline: https://doc.babylonjs.com/features/featuresDeepDive/postProcesses/SSRRenderingPipeline
47. PlayCanvas CameraFrame: https://developer.playcanvas.com/user-manual/graphics/posteffects/cameraframe/
48. Godot environment and post-processing: https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html
49. Godot compositor: https://docs.godotengine.org/en/stable/tutorials/rendering/compositor.html
50. Bevy prepass and effects: https://docs.rs/bevy/latest/bevy/core_pipeline/prepass/index.html, https://docs.rs/bevy/latest/bevy/pbr/struct.ScreenSpaceAmbientOcclusion.html
51. Unity URP Renderer Features: https://docs.unity3d.com/Manual/urp/urp-renderer-feature.html
52. Jimenez, Wu, Pesce, Jarabo, "Practical Real-Time Strategies for Accurate Indirect Occlusion" (GTAO), 2016: https://www.activision.com/cdn/research/Practical_Real_Time_Strategies_for_Accurate_Indirect_Occlusion_NEW%20VERSION_COLOR.pdf
53. Babylon highlight layer: https://doc.babylonjs.com/features/featuresDeepDive/mesh/highlightLayer
54. three.js geometries: https://threejs.org/docs/pages/CylinderGeometry.html, https://threejs.org/docs/pages/ExtrudeGeometry.html, https://threejs.org/docs/pages/TubeGeometry.html
55. Babylon MeshBuilder: https://doc.babylonjs.com/features/featuresDeepDive/mesh/creation/set
56. Godot `PrimitiveMesh`: https://docs.godotengine.org/en/stable/classes/class_primitivemesh.html
57. Bevy math primitives and meshing: https://docs.rs/bevy/latest/bevy/math/primitives/index.html
58. three.js helpers: https://threejs.org/docs/pages/AxesHelper.html, https://threejs.org/docs/pages/SkeletonHelper.html
59. three.js `TransformControls`: https://threejs.org/docs/pages/TransformControls.html
60. Babylon gizmos: https://doc.babylonjs.com/features/featuresDeepDive/mesh/gizmo
61. Bevy gizmos: https://docs.rs/bevy/latest/bevy/gizmos/index.html
62. three.js `Raycaster`: https://threejs.org/docs/pages/Raycaster.html
63. three-mesh-bvh: https://github.com/gkjohnson/three-mesh-bvh
64. Bevy `MeshRayCast`: https://docs.rs/bevy/latest/bevy/picking/mesh_picking/ray_cast/index.html
65. three.js `LOD` and `BatchedMesh`: https://threejs.org/docs/pages/LOD.html, https://threejs.org/docs/pages/BatchedMesh.html
66. Babylon occlusion queries: https://doc.babylonjs.com/features/featuresDeepDive/occlusionQueries
67. Babylon LOD: https://doc.babylonjs.com/features/featuresDeepDive/mesh/LOD
68. Godot occlusion culling: https://docs.godotengine.org/en/stable/tutorials/3d/occlusion_culling.html
69. Godot visibility ranges: https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html
70. Bevy `VisibilityRange`: https://docs.rs/bevy/latest/bevy/render/view/struct.VisibilityRange.html
