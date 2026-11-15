# Text in the world

```haxe
var font = FontFile.parse(Asset.embed("fonts/Inter.ttf"));
var label = Text3D.attach(world.node("score"), new Text3D(device, font, "0", {size: 0.3, billboard: true}));
label.text = Std.string(score);   // its glyphs made again: a change, not a frame

var word = Geometry.text(font, "helder", {size: 1, depth: 0.2, bevelSize: 0.02});   // a VertexData
var badge = Geometry.extrude(path, {depth: 0.1});   // any helder.canvas Path, holes and all
```

## Extruded shapes and text

`Geometry.extrude(path, options)` makes a solid of a `helder.canvas`
`Path` (three's `ExtrudeGeometry`): the path made polygonal and simple
by canvas' boolean ops first (`PathOps.simplify`: curves flattened within
`tolerance`, overlaps merged, holes found by the fill rule, `evenOdd` or
non-zero), so an SVG icon, a union of shapes or a glyph run is one
shape; its caps cut into triangles (ear clipping, holes bridged in) and
its sides walled, from z 0 (the back, facing -z) to `depth` (the front,
facing +z). A `bevelSize` rounds the caps' edges inwards over
`bevelSegments` steps of a quarter circle; the sides are smooth along a
curve, sharp where the outline turns by more than 30 degrees. `depth: 0`
is the front alone, a flat shape.

`Geometry.text(font, text, options)` is a text's outlines made so
(three's `TextGeometry`): helder.text lays it out (`size` the em's height
in the scene's units, `lineHeight`, `letterSpacing`, lines aligned by
`align`: 0 left, 0.5 centred, 1 right), helder.canvas gives each glyph's
curves (`Glyphs`), and they are extruded as above, the first baseline at
y 0. Both are linked only by a program that calls them.

## Text3D

`Text3D` is text that belongs to the world (Godot's `Label3D` and
`TextMesh`): a component drawing `Geometry.text`'s geometry in one
instanced draw, sized in the scene's units, centred on its node, depth
tested, fogged, sorted and shadowed like any mesh, sharp at any
distance. Unlit by default (its `color` as given); `lit: true` makes it a
Lambert material, `material` any of the program's. `billboard` turns it
to the camera each frame, its node's position and scale kept. Setting
`text` makes its glyphs again. Rays hit its triangles
([Picking](picking.md)). `<Ui>` stays for text that is ui (layout,
wrapping, input) over the scene.

<Example id="scene-text" region="text"/>

It costs what it links (`tests/3d/size/sizes.sh`): 647 KB natively, 701
KB as wasm32, most of it helder.text's layout and font reading, canvas'
boolean ops and the unlit material's shaders; a program that already
draws text or uses `Material.unlit` pays less.

In markup: `<text3d font={face} text={score} size={0.3} billboard/>`, or
`of={label}` for one made in code ([`<Scene>` markup](markup.md)).

Tests: `src/helder/scene/render/Extrude.test.hx` (a square's and a ring's
solids closed and facing out, a circle's caps' area, a bevel's inset
caps, the triangulator with two holes, a text's glyphs flat, solid,
aligned and on two lines); the 3d lane's `text3d` frame (a word extruded,
bevelled, lit and shadowed, a label turned to the camera, two lines
aligned right; its probe casts rays at the word's glyphs, the word made
shorter, fewer hit).
