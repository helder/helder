# Picking

```haxe
final hit = new Hit();                                   // the program's, refilled by each cast
var ray = camera.ray(x, y, aspect);
if (world.raycast(ray.origin, ray.dir, hit)) paint(hit.node, hit.uv);

final hits = new HitList(), through = new RaycastOptions({maxDistance: 50, layers: 2, backfaces: true});
world.raycastAll(origin, dir, hits, through);            // every triangle crossed, nearest first
```

`world.raycast(origin, dir, hit, ?options)` casts a ray at a world's
triangles (three's `Raycaster`, Bevy's `MeshRayCast`): each shown node
drawing a mesh, and each instance of an instanced set (`InstancedMesh`,
`Sprites`, `Text3D`), the ray brought into its frame (turned, moved,
scaled unevenly too), its bounds first, then each primitive's bounds and
its triangles. The nearest hit fills a `Hit` the program owns: the
node, the distance (the world's units), the point, the normal there (its
vertices' normals blended, in the world, turned towards the ray), which
side was hit (`front`), the primitive, its `triangle`, the barycentric
weights of its corners, the `uv` there and the `instance` (-1 for a
node's mesh). `raycastAll` refills a `HitList` with every triangle
crossed. Nothing is allocated a cast.

`RaycastOptions` (kept, not made a cast): `maxDistance`, `layers` (a
mask; a node's are 1 unless `Raycaster.setLayers(node, mask)`),
`triangles: false` (the primitives' bounds alone, `Pick.ray`'s way),
`backfaces` and `instances`. `Pick.ray(world, origin, dir)` stays the
bounds-only path.

## Trees

Each primitive's triangles are searched through a `Bvh` (three-mesh-bvh's
MeshBVH): a flat array of nodes, each a box and two children or a leaf of
at most 8 triangles, built by the surface area heuristic over 12 bins a
split, the triangles' corners copied in its order beside it. A primitive
keeps its data on the CPU for it (`Primitive.data`: the bytes the GPU was
given; `Mesh.keepCpu = false` lets them go, and its casts are by bounds)
and builds its tree when first cast at; `Shapes.cpu(geometry, material)`
is a mesh of data alone, cast at but not drawn (a level's collision
shapes, tests). The asset step packs the trees with a model
(`helder.scene.gltf.Pack --bvh`: read as they are, so a level loads
pickable). A tree is a cast's alone (its stack is its own: one cast at a
time). Skinned and morphed meshes are cast at in their rest pose;
`bvh.refit(vertices, stride, data)` fits a tree to moved vertices.

Raycasting costs a program that casts 55 KB natively, 53 KB as wasm32
(`tests/3d/size/sizes.sh`: the raycaster, the tree's build and casts).

## In a `<Scene>`

`<Scene pick="triangles">` picks the pointers' nodes by their triangles,
and `SceneEvent` gains the triangle's `normal` and `uv`, a drag that
stays on its node updating them: painting on a model, placing on a
surface. `pick="bounds"` (the default) picks by the meshes' boxes. The
choice is made when compiling, so a box picking by bounds links no
raycaster.

<Example id="picking"/>

Tests: `src/helder/scene/render/Bvh.test.hx` (against brute force on
random rays at a torus knot, a soup of crossing triangles and a flat grid:
the same nearest triangle at the same distance, every triangle by
`intersectAll`; its leaves; packed equal to built; backs; refit; nothing
allocated a cast), `Raycaster.test.hx` (turned and unevenly scaled nodes,
the nearest of several, children, hidden nodes and layers, bounds alone,
backs, instances, every hit in order, nothing allocated a cast),
`tests/3d-ui/SurfaceTest.hx` (a click on a box's face in a `<Scene
pick="triangles">`: its uv and normal), the 3d lane's `packed` frame (the
sample packed with `--bvh`: each tree the one built from its data) and
`text3d` frame (rays at a word's glyphs), `tests/typescript/helder/picking.ts`
(from TypeScript, without a GPU).
