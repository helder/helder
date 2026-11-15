# Levels of detail

## Lod

A `Lod` on a node lists its meshes from the finest to the coarsest, each
drawn while the node covers at least its `until` of the view's height:
the share its bounds' sphere covers (Babylon's screen coverage), the same
at any field of view or resolution. The last level's `until` is 0 by
default (drawn however far); past a last `until` above 0 nothing is drawn.
A level holds within a band of `hysteresis` about its threshold (0.1: 5%
each way), so a node at the edge does not flicker between two:

```haxe
Lod.attach(world.node("tree"), [{mesh: hi, until: 0.15}, {mesh: mid, until: 0.04}, {mesh: lo}]);
```

The renderer picks the level as it extracts the frame's draws, so nodes
of one level and material are still one instanced draw. `lod.level` and
`lod.coverage` are the last frame's; `Lod.coverageOf(viewProj, x, y, z,
radius)` and `lod.choose(coverage)` are the pick itself. A program that
never attaches a `Lod` links none of it (the renderer reaches it through
`Lod.pick`, set by `attach`).

`Lod.range(node, begin, end)` is a visible range (Godot's
`visibility_range`): the node and what is under it drawn only while the
camera is `begin` to `end` metres from it, a cluster of nodes swapped
for one far off (HLOD).

In markup: `<lod levels={levels} hysteresis={0.1} end={80}/>`.

## Instances culled and levelled

An `InstancedMesh` is drawn whole by default, culled only by its set's
`bounds`. With `renderer.use(new InstanceCulling(device))` its instances
are tested against the view one by one (their mesh's bounds' sphere
through each one's matrix), and each kept one drawn at its level of the
set's `levels` (Lod's thresholds), so a forest of thousands draws the few
hundred in view, the far ones coarse:

<Example id="scene-lod" region="levels"/>

Where the device has compute and indirect draws (WebGPU, Metal, D3D11,
GL ES 3.1) it runs on the GPU: a dispatch a set, each kept instance's
matrix appended to its level's part of a buffer the draws read as their
instances, their counts into indirect draws' arguments, nothing read back.
Elsewhere (WebGL2) the same test runs on the CPU and the kept matrices
are uploaded by level. Both draw the same frame (tests/3d's `lod` frame,
drawn by both against one golden). A set it does not take is drawn whole:
one with custom data (its second buffer is not culled with it), a
see-through one (its order is its own: `Sprites`), more than four levels
or four primitives a level. Shadows draw every instance at the set's mesh.

Measured (`tests/3d/LightBench.hx`, as [Lights and
shadows](lights.md#many-lights)): a field of 20,000 spheres of three
levels, 678 of them in view, drawn whole 438 ms a frame; culled and
levelled on the GPU 42.4 ms (0.1x), on the CPU 41.3 ms. `InstanceCulling`
adds 52 KB natively (50 KB as wasm32), `Lod` 42 KB (28 KB), nothing when
unused.

Not built: `Pack --lod` (meshes simplified at build time), a dithered
crossfade between levels, and occlusion culling (phase 7).
