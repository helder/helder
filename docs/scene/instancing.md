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
| post (bloom down and up, the composite, stages) | `renderer.post.draws` | `FrameCounts.postDraws` |
| everything the GPU was given (the UI's too) | | `FrameCounts.draws`, `passes`, `instances` |

`helder.gfx.FrameCounts` is counted from its last `reset()`; a headless
run's `--stats out.json` resets it at each frame and writes these for every
frame (`sceneDraws`, `shadowDraws`, `postDraws` beside `draws` and
`passes`), and prints their medians:

```
HELDER_CONTROLS=none bun run helder run examples/showroom --headless --stats bin/showroom-stats.json --at 4
headless: 3D draws by pass: main 17 (at most 18), shadow maps 17 (at most 17), post 12 (at most 12)
```
