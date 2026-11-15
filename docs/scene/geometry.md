# Geometry

## Shapes made in code

Shapes are made in code on the CPU, three.js's geometries by name, their
parameters three's names and defaults (option structures, each field
optional), their vertex and index counts three's for the same parameters:

```haxe
var rail = Geometry.cylinder({radiusTop: 0.2, radiusBottom: 0.2, height: 1, radialSegments: 8, flat: true});
var post = Shapes.of(device, rail, wood);    // the upload: a Mesh of one primitive
var knot = Geometry.torusKnot({radius: 0.5, tube: 0.15, p: 2, q: 3});
var vase = Geometry.lathe([new Vec2(0.2, 0), new Vec2(0.4, 0.5), new Vec2(0.15, 1)], {segments: 24});
var hose = Geometry.tube(Curve3.catmullRom(points), {radius: 0.05, tubularSegments: 96});
```

`Geometry.box`, `sphere`, `cylinder`, `cone`, `capsule`, `torus`,
`torusKnot`, `ring`, `circle`, `plane`, `lathe(points, ...)` and
`tube(curve, ...)` return a `VertexData`, free of the GPU: tested on Eval,
read by physics, packable. Like three's: y up, the plane, circle and ring
in xy facing +z, the torus about z, a cylinder's seam at +z; unlike
three's, uvs run down the image (v flipped) as glTF's do and every helder
material reads them. Every generator also takes `flat: true` (its vertices
unshared, each triangle its face's normal: the low-poly look) and
`tangents: true` (for normal maps).

A `VertexData` is read with `position(i)`, `normal(i)`, `uv(i)`,
`index(k)`, `vertexCount` and `count`, and moved into another with
`transformed(m)`, `rotated(x, y, z)` and `translated(x, y, z)` (three's
`applyMatrix4`; a mirror keeps the winding). `Shapes.of(device, geometry,
material)` uploads one; `Shapes.box`, `sphere`, `capsule` and `plane` are
the common ones at their usual sizes (`Shapes.plane` is `Geometry.plane`
turned to face up). In markup a geometry is a tag: `<cylinderGeometry
radiusTop={0.2} height={1}/>` ([`<Scene>` markup](markup.md)).

Each column here is a generator, each row a shading model
([Materials](materials.md)):

<Example id="primitives"/>

## Curves

`Curve3` is a curve in space, an immutable value (three's `Curve`):
`Curve3.bezier(a, b, c, d)`, `catmullRom(points, closed, tension)`,
`line(a, b)` and `path(curves)`, read by a parameter (`point(t)`,
`tangent(t)`) or by a distance along it (`pointAt(d)`, `tangentAt(d)`:
its `length` tabulated once, when made), and `frames(n, closed)`: n + 1
frames at equal lengths that turn as little as they can (parallel
transport, so no flip where the curve bends back), for a tube's rings or
a camera on rails.

Tests: `src/helder/scene/render/Geometry.test.hx` (three's counts, closed
shapes closed and wound one way round, normals unit, uvs 0 to 1, flat, the
transforms), `src/helder/scene/math/Curve3.test.hx` (lengths, frames
without flips); the 3d lane's `primitives` frame (every generator, smooth
with its normals as colours, flat in Lambert's light; its TypeScript twin
the same frame).
