# Debugging

`FrameStats` keeps the last frames' times (and, given to `add`, the CPU's
share of each), the renderer's counts, `percentile(0.5)`, `percentile(0.99,
true)` and `fps()` without allocating; `Overlay` draws them over the frame
with `helder.ui`'s drawn renderer (put `src` on the class path where it is
used): its bars and figures, with `detail` the fps, frame time and CPU
p50/p99 and the program's own `lines`, and with `extra` a program's own
controls in its pass (`text` in its pixel font, `rect`; `panel = false`:
those alone).

The performance examples use it: [Instancing](instancing.md)'s asteroid
belt, [GPU particles](particles.md)' galaxy,
[examples/bunnymark](/examples/bunnymark) and
[examples/physics-stress](/examples/physics-stress). What a frame costs
in draw calls, by pass: [Instancing](instancing.md#draw-calls-by-pass).

## Debug drawing

```haxe
renderer.use(new DebugDraw());
// anywhere, each frame (a script, the physics step): gone the next frame
Debug.line(a, b, 0xFF4040);
Debug.ray(origin, velocity, 0.5);
Debug.aabb(mesh.bounds);
Debug.sphere(target, 2);
Debug.onTop(true);  Debug.axes(player.worldMatrix(), 0.5);  Debug.onTop(false);
```

`Debug`'s calls draw lines for one frame from anywhere (Bevy's gizmos):
nothing to keep or remove, and nothing allocated, written into a ring of
segments that the `DebugDraw` feature draws through a `LineRenderer`
([Lines](lines.md)), one draw depth tested and one over everything
(`Debug.onTop`), then clears. A colour is `0xRRGGBB` as written, not lit,
fogged or tone mapped. The calls: `line`, `ray` (an arrow's head at its
end), `arrow`, `aabb`, `boxOf(matrix, min, max)` (a turned box: a node's
bounds), `sphere`, `circle`, `cross3`, `axes(matrix, size)`, `grid`,
`frustum(camera, aspect)`, `light(node)` (a directional light's arrows, a
point light's range, a spot's cone), `skeleton(skin)` and `path(curve,
n)`.

**Compiled out of a release.** `Debug`'s calls are macros: in a release
build (`helder build`'s `-D helder.release`) they are nothing, their
arguments not computed either, unless `-D helder.debugdraw`. `DebugDraw`'s
own functions of the same names are always there (TypeScript calls
those). The ring holds `DebugDraw.capacity` segments a frame (16,384; set
before the first call), calls past it dropped and counted (`dropped`).

## Helpers

Helpers are components of a node that make those calls for it each frame
(three's helpers): `AxesHelper.attach(node, size)`,
`BoundsHelper.attach(node)` (its mesh's box, turned with it),
`LightHelper.attach(node)`, `CameraHelper.attach(node)` (its camera's view
volume), `SkeletonHelper.attach(node)` (its skin's bones), and
`GridHelper.attach(node, {size, divisions})`: an infinite grid on the
node's plane, a shader, not lines (each line a pixel wide however far, a
major line every tenth, the axes red and blue, fading out at `fade`).
Unlike `Debug`'s calls they stay in a release: a program attaching one
wants it. In markup: `<axesHelper size={1}/>`, `<gridHelper size={10}/>`,
`<boundsHelper/>` in a mesh, `<lightHelper/>` in a light ([`<Scene>`
markup](markup.md)), their box given a `DebugDraw`.

What it costs a program that uses it (`tests/3d/size/sizes.sh`):
`DebugDraw` with its calls and the line helpers, 82 KB natively and 99 KB
as wasm32 (the lines' renderer with it); `GridHelper` 21 KB more; `Debug`'s
calls in a release, nothing.

<Example id="scene-debug" region="helpers,calls"/>

Tests: `src/helder/scene/render/DebugDraw.test.hx` (each call's segments,
a colour as written, the ring's capacity, nothing allocated); the 3d
lane's `debugdraw` frame (each call, a frame allocating nothing) and
`helpers` frame (each helper, the grid under them).

## Headless

`helder run <entry> --headless` runs a program offscreen on a virtual
clock: `--snap out.png --at 2` writes its frame at two seconds, `--stats
out.json` every frame's times and counts (the draws by pass). The 3d
lane's frames and the examples' videos on the site are made this way.
