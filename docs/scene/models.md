# glTF and models

## glTF

`Gltf.parse(bytes, ?resolve)` reads glTF 2.0, .gltf (buffers as `data:`
URIs or files `resolve` returns) and .glb, into a `GltfDoc`: typed and
checked data (indices in range, views inside buffers, accessors inside
views). `doc.floats(accessor)` and `doc.indices(accessor)` read accessors of
any component type, normalized or strided. Materials' extensions:
KHR_texture_transform (one transform for a material's maps, or each map
its own with TEXCOORD_1: `Material.textureTransforms`),
KHR_materials_emissive_strength, KHR_materials_clearcoat,
_transmission, _volume, _ior, _specular, _sheen, _iridescence and
_anisotropy with their maps ([Materials](materials.md#the-gltf-material-extensions));
alphaMode MASK is cut out at alphaCutoff. `GltfNodes.build(doc, world, ?parent, ?scene, ?mesh)` makes the node
hierarchy (TRS or matrices, cameras); `GltfScene` makes the GPU meshes and
materials once and `instantiate(world)` copies the hierarchy into a world.
helder.asset's `Asset.embed(path)` builds a file into the code itself.

## Models

```haxe
var hero = Model.of("models/hero.glb");      // checked and typed when compiling
var root = hero.instantiate(world, device);  // GPU meshes made once, shared
var hand = root.find(hero.nodes.LeftHand);   // hero.nodes.LeftHnad: a compile error
```

`Model.of` reads the file's names when compiling (nodes, meshes,
materials, animations: `model.nodes`, ...). Its path is an asset's
([helder.asset](/src/helder/asset/README.md)): found under a class path or
the project, checked when compiling, the file in every build that still
uses it (the executable's data, the APK's or the app's `assets/`, beside
the page), read before anything runs (in the browser fetched before main:
`browser.mjs`'s `assets` option, `<module>.assets.json`). For now
self-contained files only (one embedded buffer, images inside it).
Textures need a decoder, named by the program so that none is linked
otherwise (`helder.image`'s; a glTF viewer natively: 805 KB without one,
1.1 MB with PNG, JPEG and WebP):

```haxe
Images.decode = Images.png;     // PNG only
Images.decode = Images.common;  // PNG, JPEG and WebP
```

A model referenced with `Model.of`, its nodes and its animation typed from
the file, under a sun with a shadow map:

<Example id="gltf-viewer"/>

## The asset step

```sh
haxe -cp src \
  --run helder.scene.gltf.Pack level.glb level.hxm3d
```

```haxe
PackedModel.read(Asset.embed("level.hxm3d"), device).instantiate(world);
```

A packed model needs no glTF reader or JSON at run time (73 KB less
natively, `tests/3d/size/sizes.sh`): meshes (vertices in the renderer's layout,
joints and weights, tangents computed at build time for normal maps),
materials (factors, maps, sampler, the extensions' fields), images (decoded by `Images.decode`
when loaded), cameras, lights, skins, morph targets, animations (`model.clip(name)`,
playing on the nodes `instantiate` made) and the hierarchy.

`--textures bc` or `--textures astc` compresses the images for a target's
GPUs (BC1, BC3 with alpha: desktops and the web; ASTC 4x4: phones), their
mip chains made at build time (helder.image's `BlockCompress`):
`PackedModel` uploads the levels as they are (`Images.compressed`), or on a
GPU without the format (`Device.supports`) decodes them on the CPU.
Sponza's 69 textures: 363 MB on the GPU as RGBA8, 50 MB as BC, 95 MB as
ASTC ([examples/sponza](/examples/sponza)). Built natively, the step packs
them in seconds.

## Loading in the background

Big files or loading screens: `Asset.model(path)` (or `Model.of(path,
Lazy)`) is an `Asset` of the same typed model, loaded in the background
(`var hero = Asset.model(path).load();` in a coroutine; `asset.ready`,
`asset.peek()` in the frame loop); under `helder dev` a change to the file
is loaded again into the same `Model` (`replace`: each mesh's primitives
and materials swapped in the mesh objects its instances draw; their nodes,
morphs and skins as they were made). `Model.load(path)` loads a path known
only at run time (not bundled). Loads advance on the main thread's loop
(`App.run`), or in `Assets.poll()`, which `Stages.frame` calls.

## Animation

```haxe
var made = [];
var root = hero.instantiate(world, device, null, made);   // made: the glTF nodes by index
var animator = new Animator(made);
animator.play(hero.clip(hero.animations.Run), {loop: true, fade: 0.2});
// each simulation step:
animator.update(dt);
```

Clips are glTF's keyframes (translation, rotation, scale; step, linear,
cubic spline). Skinned glTF meshes deform with their joints (a `Skin` per
instance, joint matrices in a texture: `renderer.use(new
Skinning(device))`); `tests/3d/skinned.glb` is a generated two-joint
sample.
