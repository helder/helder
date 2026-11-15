# Instancing

## Batched nodes

Nodes drawing one primitive are one instanced draw whatever their scale
(uneven too: the normals are turned by the instance matrix's inverse
transpose), unless their material is see-through (`blend`) or skinned;
`renderer.instancing = false` draws each alone. The shadow maps batch
their casters the same way, a primitive's casters one instanced draw a
cascade (a skinned caster alone).

## InstancedMesh

For many copies without a node each, an `InstancedMesh` is one mesh drawn
from flat per-instance data in one instanced draw a primitive: a transform
(position, unit quaternion, uniform scale; or any affine matrix), a colour (times
the material's), and custom floats for a program's own shader:

```haxe
var rocks = new InstancedMesh(Shapes.box(device, rock), 100000);   // capacity, count, custom floats
InstancedMesh.attach(world.node("belt"), rocks);                  // drawn while the node is shown
rocks.bounds = beltBounds;                                        // optional: culled whole, fitted by Shadows
// each frame, nothing allocated:
for (i in 0...rocks.count) rocks.setTransform(i, x, y, z, qx, qy, qz, qw, scale);
rocks.setColor(i, r, g, b);
```

The data is the instance buffer's layout (`data`, 64 bytes an instance;
`customData` beside it, uploaded to `customBuffer`), uploaded by the
renderer before its pass when written (count instances, one
`writeBuffer`); the standard material draws it (normal maps too), and it
casts into `Shadows`' map. In markup: `<instances of={rocks}/>`.

The asteroid belt draws its rocks three ways (its buttons): as nodes one
by one, as nodes batched by the renderer, and as one `InstancedMesh` of
up to 200,000; the overlay counts the draws. Its InstancedMesh, made once
and written each frame:

<Example id="instancing" region="instanced-mesh,update"/>

Tests: `src/helder/scene/render/InstancedMesh.test.hx` (the layout, resize,
nothing allocated), the 3d lane's `instancedmesh` frame (shadows, a set
culled), `tests/3d-ui/SceneUiTest.hx`.

## Draw calls by pass

What a frame costs in draw calls, by pass, to measure the next
optimisation against:

| Pass | The last frame's, this renderer | Every renderer's, summed |
|---|---|---|
| main (the scene's colour pass) | `renderer.draws` (and `instanced`, `culled`) | `FrameCounts.sceneDraws` |
| shadow maps (every cascade) | `renderer.shadowDraws` (`Shadows.draws`) | `FrameCounts.shadowDraws` |
| the view buffers' prepass (`ViewBuffers`: the opaque draws again, single-sampled) | `renderer.prepassDraws` | `FrameCounts.prepassDraws` |
| post (AO's and depth of field's passes, bloom down and up, the composite, stages) | `renderer.post.draws` | `FrameCounts.postDraws` |
| everything the GPU was given (the UI's too) | | `FrameCounts.draws`, `passes`, `instances` |

`helder.gfx.FrameCounts` is counted from its last `reset()`; a headless
run's `--stats out.json` resets it at each frame and writes these for every
frame (`sceneDraws`, `shadowDraws`, `prepassDraws`, `postDraws` beside
`draws` and `passes`), and prints their medians:

```
HELDER_CONTROLS=none bun run helder run examples/showroom --headless --stats bin/showroom-stats.json --at 4
headless: 3D draws by pass: main 12 (at most 12), shadow maps 24 (at most 24), prepass 0 (at most 0), post 0 (at most 0)
bun run helder run examples/postfx --headless --stats bin/postfx-stats.json --at 2
headless: 3D draws by pass: main 7 (at most 7), shadow maps 0 (at most 0), prepass 7 (at most 7), post 15 (at most 15)
```

(examples/postfx: the prepass draws the opaque shapes again, one sample
a pixel; post is AO's two passes, depth of field's one, bloom's 11 and
one composite, the outline, FXAA and the tilt-shift's mix folded in.)

## Sprites

Quads that face the camera (three's `Sprite`, Godot's billboard modes), as
one `InstancedMesh` of a material: clouds, halos, trees far off.

```haxe
var trees = new Sprites(device, Material.unlit({texture: atlas, alphaCutoff: 0.5}), 64, {mode: Axis, columns: 2, rows: 1});
Sprites.attach(world.node("trees"), trees);
trees.count = n;
for (i in 0...n) trees.set(i, x[i], h[i] / 2, z[i], h[i] * 0.7, h[i], 0, i % 2);   // position, size, rotation, atlas cell
trees.setColor(i, r, g, b);
```

`mode` is `Spherical` (facing the camera, turned on the screen by a
sprite's rotation), `Axis` (turning about `axis` alone: upright along it)
or `Fixed` (facing +z). Each sprite is a position in the world, a width and
a height, a rotation, an atlas cell (`columns` by `rows` of the material's
texture, left to right then down: the material's `uvScale` set to a
cell's share, the cell in the instance matrix's last w, which the
instanced variants read: `PbrShader.instanceUv`) and a colour. The
renderer turns them before its pass (`InstancedMesh.prepare(viewProj)`:
the camera's axes from its view-projection), only when the camera or a
sprite changed; see-through ones are drawn after the opaque surfaces with
the see-through instanced sets (an `Additive` halo), `Alpha`'s sorted far
to near among themselves. Nothing is allocated a frame. In markup:
`<sprites of={trees} mode="axis"/>`. Tests:
`src/helder/scene/render/Sprites.test.hx` (the turn, the atlas, the
sorting, nothing allocated, natively and as wasm32-wasi), the 3d lane's
`sprites` frame (trees on an axis, clouds sorted, additive halos).
