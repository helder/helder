# Lines

```haxe
renderer.use(new LineRenderer(device));
var path = Lines.attach(world.node("aim"), new Lines(512, {width: 6, join: Round, cap: Round, dash: 0.2, gap: 0.15}));
// each frame: nothing allocated
path.count = n;
for (i in 0...n) path.setPoint(i, xs[i], ys[i], zs[i], 1, 1, 1, fade(i));
path.dashOffset = -time;     // the dashes march along it
```

`Lines` are a polyline through their points, or separate segments
(`segments: true`, a pair of points each), drawn by a `LineRenderer` (a
`RenderFeature`) as quads on the screen: gfx's `Lines` topology is one
pixel wide, and WebGL ignores a line's width, so a width here is the
same on every back end (three's `Line2` and `LineMaterial`, Babylon's
GreasedLine). A point is a position in its node's frame and a colour
(linear rgb and alpha, blended along a segment). The program writes them
into the line's flat data, as an `InstancedMesh` takes its instances:
nothing is allocated a frame, and the renderer uploads the points once
they changed.

- **`width`** in pixels (`widthUnits: Pixels`, the default), or in the
  world's units (`World`: thinner far off, as geometry is).
- **`join`**, where segments meet: `Miter` (bevelled past four half
  widths out), `Round` or `Bevel`; **`cap`**, the line's ends: `Butt`,
  `Round` or `Square`; `closed` joins the last point back to the first.
- **`dash`** and **`gap`**: a dashed line, lengths in the line's own
  units along it, `dashOffset` moving them (a marching line).
- **`onTop`**: drawn over everything, after the scene, not depth tested;
  else depth tested and written. **`transparent`**: blended by the
  colours' alpha, after the see-through surfaces (not written to depth);
  an opaque line ignores alpha.
- **`toneMapped: false`**: its colours as they are into an 8-bit target
  (a debug colour's pure red), not tone mapped. Lines are fogged.

Each line is one instanced draw of a segment an instance: a quad across
the segment and a fan of eight triangles at each end (the start's cap,
the end's join with the next segment or cap), placed in pixels by the
vertex stage from four views of one point buffer (the point before, the
segment's two, the point after). A segment crossing the near plane is
cut at it.

<Example id="scene-lines" region="lines,frame"/>

A program drawing lines links the `LineRenderer` and its shader: 64 KB
natively, 80 KB as wasm32 (`tests/3d/size/sizes.sh`); one that never
makes one, nothing.

In markup a line is `<lines of={path}/>` ([`<Scene>` markup](markup.md):
its box given a `LineRenderer`). Lines are what `DebugDraw` draws with
([Debugging](debugging.md)).

Tests: `src/helder/scene/render/DebugDraw.test.hx` (a polyline's points
as uploaded: its ends padded as neighbours, closed's wrapped, distances
along it); the 3d lane's `lines` frame (each join and cap at 9 pixels, a
ribbon 0.12 metres wide running away, a dashed ring behind a pillar, a
line over everything, see-through segments), on llvmpipe, WARP, WebGPU
and WebGL2.
