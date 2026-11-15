# Indirect light

The light that does not come straight from a lamp: the sky's, what the
walls bounce, what a polished floor reflects. Each part below is opted in,
and a program that names none of them links none of it.

## An environment prefiltered by helder

`Environment.prefilter(device, width, height, texels, format)` takes an
equirectangular image (longitude across, latitude down; RGBA8 sRGB as an
image decodes, or linear `RGBA16F` or `RGBA32F` for an HDR sky) and
filters it once, at the first frame drawn with it, into the atlas
`Environment.prefiltered` reads: `levels` rows of the sphere by roughness
(GGX's lobe, the split sum's first half, by filtered importance samples)
and the diffuse irradiance's row, made from the image's spherical harmonics (`env.sh`,
projected on the CPU at load). Where the device has compute (WebGPU,
Metal, D3D11, GL ES 3.1) the atlas is written by a dispatch, elsewhere
(WebGL2) by a fragment pass: the same texels, one golden frame (tests/3d's
`sh`). The image itself is drawn behind the scene.
`Environment.prefilterImage(device, mime, bytes)` decodes one first.

<Example id="scene-environment" region="environment"/>

`Environment.prefiltered` (an atlas filtered ahead by a tool) and
`Environment.fromImage` (a mip-mapped image read by roughness) still
work as before.

## Light probes

A `LightProbe` on a node is the light around a point as spherical
harmonics (`Sh`: nine RGB coefficients; `Sh.ofEquirect`, `ofFunction`,
`ofHemisphere`, `addDirectional`), reaching `radius`. A `ProbeGrid` is a
box of them on a regular grid, filled by code (`grid.fill(p -> ...)`) or
read from bytes baked once (`ProbeGrid.read`, `grid.write()`). With
`renderer.use(new Probes(device))`, each draw of the standard material
takes the light at its centre (a grid holding it, blended trilinearly on
the CPU, else its nearest probes), evaluated at its vertices: Unity's
per-object probes, nothing per pixel.

## Reflection probes

A `ReflectionProbe` on a node captures the scene from there once (six
faces into a cube, drawn by an offscreen twin of the renderer, then
prefiltered into its column of `Probes`' atlas) and is reflected by the
draws its box holds, parallax-corrected: a reflection is looked up where
it leaves the box, so a room's walls are reflected where they are. A draw
blends its two probes by how much of it each box holds (the box's walls
soft over `blend`), falling back to the environment. `probe.capture()`
captures it again; nothing is captured every frame.

<Example id="scene-probes" region="probes"/>

The probes share one atlas (a column a probe, the environment's layout),
read by the probes variants alone; the environment stays its own, the
probes' fallback. Drawn with probes: the standard material's opaque draws, plain and instanced (pbr's
`probes` variants); normal-mapped, skinned and see-through draws, instanced
sets and materials of their own shader read the environment alone.

## Area lights

`Light.rectArea(color, intensity, width, height, range)` and
`Light.discArea(color, intensity, radius, range)` shine down their node's
-z from their front only, `color` times `intensity` their radiance
(three.js's units). With `renderer.use(new AreaLights(device))` the
standard material shades them with linearly transformed cosines (Heitz et
al.; three.js's tables, 64 KB): a rectangle's polygon, a disc as an
octagon of its area. Without it, and in other materials, an area light
is a point light at its centre. They take part in the frame's lights and
in `ClusteredLights` as their bounding sphere, and cast no shadows.

## Lightmaps

A `Lightmap` on a node is its baked light (the irradiance over pi, linear
`RGBA16F` or sRGB `RGBA8`) in its rectangle of a texture several nodes
share, read at the second uvs (glTF's TEXCOORD_1, a primitive's `uv1`).
With `renderer.use(new Lightmaps(device))` it replaces the ambient (mode
`Indirect`, the lights still added) or all the light (`All`). Nodes of one
mesh and material keep their own lightmaps (Bevy's model, not three's
`material.lightMap`); a lightmapped node is a draw of its own. Baking is a
tool's.

```haxe
var l = Lightmap.attach(node, new Lightmap(baked, new Vec4(0, 0, 0.5, 0.5), true));   // texture, rect (offset, scale), sRGB
l.mode = All;
renderer.use(new Lightmaps(device));
```

## Costs

Each part is a variant of the standard material compiled when a frame
first draws with it, so a frame without probes, area lights or lightmaps
compiles and draws as before. Per pixel: light probes cost nothing (their
light is evaluated at the vertices), a reflection probe two atlas reads
and a box intersection, an area light two polygons' integrals (four or
eight edges each) and two table reads. Per draw on the CPU: a probe
grid's eight probes blended, and each reflection probe's box tested. On
the GPU: the atlas (`(probes + 1) x size` by `(levels + 1) x size`
RGBA16F texels: 9 x 64 by 7 x 64, 2 MB, by default), a capture's cube.

What each adds to a program (`tests/3d/size/sizes.sh`, the renderer's
level, Linux x86-64 and wasm32; unused, the whole phase adds 27 KB and 29
KB):

| | native | wasm32 |
|---|---|---|
| `Environment.prefilter` (Sh, the prefilter's pass and dispatch) | +144 KB | +145 KB |
| `Probes` (with the prefilter, the captures, two variants) | +300 KB | +334 KB |
| `AreaLights` (four variants, the 64 KB tables) | +295 KB | +355 KB |
| `Lightmaps` (one variant) | +71 KB | +98 KB |
