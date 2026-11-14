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
so unused ones are not linked. `Shapes.box`, `sphere`, `capsule` and
`plane` make meshes in code.

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
it; no refraction or blur).

<Example id="scene-materials"/>

## A material of its own

The standard material is a slot object, `pbr` (`PbrShader`; helder.gfx's
`slots`, [DESIGN.md](/src/helder/compiler/DESIGN.md) 3): one shader whose
variants are the renderer's (`pbr.variant({normalMap, skinned,
instanced})`: `PbrShader`, `PbrNormalShader`, `PbrSkinnedShader`,
`PbrInstancedShader`, `PbrInstancedNormalShader`; the shadow map's casters
are `shadowCaster`'s) and whose slots a material replaces: `color`,
`alpha`, `normal`, `roughness`, `metalness` and `emissive` (of the
fragment's `PbrSurface`), `position` (of the vertex's `PbrPoint`).
`MaterialShader.material(pbr.with({...}))` compiles them, at build time,
into a shader of the material's own (`material.shader`, every variant the
renderer draws with); a slot's parameters beyond the standard ones are
blocks of its own (`material.uniforms`, written by its `params`). Here the
emissive and colour slots are replaced:

<Example id="glow"/>

The same in TypeScript: [TypeScript](typescript.md).
