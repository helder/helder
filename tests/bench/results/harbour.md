# The harbour: a TypeScript 3D app's frames

tests/bench/harbour is a papercraft harbour diorama a Studio field test
built in TypeScript: 47 pieces of 81 groups, 1,128 meshes (boxes,
cylinders, cones, tori; 535 distinct shapes and paints), each piece
rising about its crease and 16 groups moving: about 100 transforms set
a frame through a `time` signal. Soft shadows (a 2048 map, 16 taps),
SSAO, Lambert materials. `bun run test bench harbour` runs it headless
for 8 s of its clock at 1180x740, 2x (RUNS runs, each a process) and
reads its `--stats` (tests/bench/harbour.mjs: frames from the 5th).
2026-11-26, an Apple M4 Mac shared with other sessions.

## Before and after

Main (ff9f333a) and this change built alike, run in turns, four rounds
each, while the Mac's load was 6 to 8:

| | frame ms median | p95 | renderer CPU ms median | process CPU s (8 s run) | GPU ms a frame | draws (main, shadow, prepass) |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| main | 9.6–10.0 | 15.3–16.9 | 9.3–9.6 | 5.7–6.0 | 9.6–11.1 | 3,095 (978, 1,128, 978) |
| this change | 8.3–8.5 | 10.0–10.7 | 3.2–4.2 | 2.2–2.5 | 7.8–9.1 | 1,326 (408, 495, 408) |

At a load of 13 to 22 main's median was 11.6–14.1 ms (p95 20–40) and
this change's 7.1–7.3 ms (p95 11–34): the p95 then is other programs'.
The frames are now the GPU's (frame ms over renderer CPU ms); GC bytes a
frame are the same, 180 KB, the TypeScript program's own values.

## Where main's frame went

`sample` of a release build with symbols (no pixels read back): the
renderer's pass 91% of the main thread, the clock's tick (the reactive
graph and the TypeScript expressions) 4%:

- Metal's encoding of 3,100 draws: 41%;
- world matrices walked up to the root at every ask, five asks a mesh a
  frame (extract, shadow layout, shadow pass, prepass, main): 26%;
- a material bound a draw (each mesh its own): 9%; normal matrices 4%.

No two meshes shared a primitive: every `<boxGeometry>` and
`<lambertMaterial>` made its own geometry and material, so nothing was
instanced.

## What changed

- Geometry and material tags of the same props share one value
  (SceneRenderer.keyOf, counted users): their meshes are one primitive,
  one instanced draw.
- Shadow casters run by geometry, not primitive (a material's casters
  are one draw to the map).
- World: a slot's world matrix checked at an epoch (bumped by any
  transform or tree change) is not walked up again; a transform set to
  its value changes nothing; inTree kept for the tree's shape.
- The draw list and the casters sorted by a merge sort (an insertion
  sort over store order was n²).
- Metal: a texture and sampler bound at a slot again in a pass are not
  sent.
- No local light in the frame: no light list looked for a draw.

Coplanar cards that already z-fought draw in another order (shared
materials, instanced runs): about 1,500 of 3.5M pixels differ at t=1, 3
and 6, all on z-fighting edges and discs.
