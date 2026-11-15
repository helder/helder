# Lights and shadows

## Lights

```haxe
var sun = world.node("sun");
Light.attach(sun, Light.directional(new Vec3(1, 0.95, 0.85), 2.2));   // colour, intensity
sun.lookAt(new Vec3(0.35, -0.45, 0.82));                              // it shines along its node's -z
Light.attach(world.node("lamp"), Light.pointLight(new Vec3(1, 0.3, 0.1), 3, 4));   // and a range, metres
Light.attach(world.node("spot"), Light.spot(color, 6, 10, 0.15, 0.3));            // inner and outer cones, radians
Light.attach(world.node("sky"), Light.hemisphere(skyColor, groundColor, 1));     // three's HemisphereLight
```

The standard material is lit by the world's first directional `Light`
(a world without lights: `renderer.sun*`), its point and spot lights, and
a sky-and-ground ambient: the world's first hemisphere light
(`Light.hemisphere(sky, ground, intensity)`: the sky's colour from above,
the ground's from below, blended by the normal), else `renderer.sky` and
`renderer.ground`. A light's `kind` is `Directional`, `Point`, `Spot` or
`Hemisphere` (`light.local`: a point or a spot light); tests/3d's
`hemisphere` frame is lit by a hemisphere light alone. `renderer.rim` (a
colour times intensity) and `rimPower` add a rim light from the sun's side
along the silhouettes. `material.emissiveNight` (0 to 1) keeps a
material's light to its night side, faded in across the terminator (a
planet's city lights).

## Many lights

Each frame the renderer gathers the world's point and spot lights whose
reach (a sphere of their `range`) meets the view, the most important
first (the brightest over their distance past their range), at most 32:
the frame's lights (`renderer.frameLights`, one uniform block, 1.5 KB:
some GL ES 3.0 drivers, Android's emulator's, count a block's vectors
among a fragment stage's 224 uniform vectors). Each
draw is lit by the eight of them that reach its bounds most, listed by the
renderer as it extracts the draw (Godot Mobile's and Unity's per-object
lights): a lamp lights the objects it reaches, a far one costs them
nothing, and a pixel never loops over more than eight. Nodes of one mesh
are still one instanced draw when their lists are the same (the lists
are by light, so the same lights make the same list); a floor of tiles
gets a list a tile (tests/3d's `lights8` frame: 32 lights over 64 tiles
and a pillar twelve of them reach, its eight brightest lighting it).

One large surface under many lights wants more than eight:
`ClusteredLights` (Forward+) cuts the view into cells (16 x 9 tiles, 24
slices of depth growing away from the camera), lists the lights reaching
each (at most `maxPerCell`, 32), and lights each pixel by its cell's,
from up to `maxLights` (256) a frame:

<Example id="scene-clustered" region="clustered"/>

The lists are made by a compute pass where the device has one (WebGPU,
Metal, D3D11, GL ES 3.1: an invocation a cell, every light tested), else
on the CPU (WebGL2, GL ES 3.0: each light tested against the cells its
sphere's box touches), the same test in the same order, so both paths draw
the same frame (tests/3d's `clustered` frame is drawn by both, against one
golden, and is its brute force's: every light at every pixel). The lists
and the lights go into one R32F texture the standard material reads in a
branch, so no material has a variant more and it runs on WebGL2.

Measured (`tests/3d/LightBench.hx`, headless at a phone's render size,
810 x 1800, on Mesa's llvmpipe; a CPU's rasterizer is not a phone's GPU,
the ratios are what carry over; a floor and nine pillars, 24.5 ms with no
local light):

| 128 point lights | Frame | Against none |
|---|---|---|
| each draw's eight (the floor lit by eight of them) | 47.6 ms | 1.95x |
| `ClusteredLights`, its cells on the GPU | 74.2 ms | 3.03x |
| `ClusteredLights`, its cells on the CPU (0.37 ms of it) | 71.4 ms | 2.92x |
| every light at every pixel (one cell) | 324 ms | 13.3x |

Each draw's eight cost what eight lights cost a pixel; clustered, a pixel
pays for its cell's lights alone (here up to a dozen, the floor lit by all
of them), a quarter of the brute force's. The CPU's cells for 256 lights
take 0.6 ms (`Clusters.test.hx`, natively). What it adds to a program:
66 KB natively, 61 KB as wasm32 (`tests/3d/size/sizes.sh`), nothing
unused; the renderer's lists and the frame's lights are the renderer's
own.

## Shadows

Shadows are opted in: `renderer.use(new Shadows(device))`. `Shadows` is
one atlas (an R32F texture and its depth buffer) of tiles: the sun's and
its cascades, and the point and spot lights' that cast.

**The sun.** The world's first directional light casts (its
`castShadows`, true by default; the renderer's sun in a world without
lights): one map of `size` texels fitted to the casters, filtered 3x3;
`Shadows.cascaded(device, size, split)`: two cascades, the first sharp
over the camera's view up to `split` metres. A primitive's casters are one
instanced draw a tile.

Softer shadows are opted in with `.soft(radius, samples, spread)`: a disc
of `samples` taps (8 for phones, 16, 32) out to `radius` metres, turned
per texel; with a `spread` a blocker search first (half as many taps), the
penumbra widening by `spread` a metre from its caster up to the radius,
so a shadow is sharp where it meets what casts it (PCSS); `spread` 0, the
radius everywhere. Each tap is compared with the surface's own depth there
(its plane as the light sees it), so a far smaller `bias` than the 3x3
filter's keeps tilted surfaces from shadowing themselves, and low casters
(a rail on a green) still cast: Little Skies (helder/little-skies) uses
`new Shadows(device, 2048).soft(0.15, 12, 0.08)` with `bias = 0.001`, its
sun's map the whole atlas (tests/3d's `softshadows` frame; `shadows` and
`cascades` keep the 3x3 filter).

<Example id="scene-lights"/>

**Point and spot lights** cast when asked, `light.castShadows = true`
(three.js's `castShadow`), each with its own `light.shadow`:

<Example id="scene-shadows" region="shadows,lights"/>

The first local light to cast makes the atlas wider by a square of
`atlas` texels (1024: `new Shadows(device, size, {atlas: 1024, maxLocal:
4, tileSize: 512})`), where a spot light gets one tile of its cone and a
point light six, a cube's faces as six frusta (gfx has no cube textures,
and one atlas is one binding), 12 tiles at most a frame (two point lights,
or a point light and six spot lights). At most `maxLocal` lights cast a frame, in
the frame's order (the ones that matter most to the view); while their
tiles do not fit the square, they are halved; the others cast nothing that
frame. A tile is kept from the frame before while its light and what it
holds stay put (`cached`, and `light.shadow.cached`: Godot's and Unity's
cached shadows), so a level's lamps cost their shadows once. Their
filter is a 3x3 or a disc of 12 taps (`radius`, in the tile's texels),
their bias in metres a metre from the light (`localBias`, `bias`), and an
offset along the surface's normal (`normalBias`, in texels), both growing
with the distance as the tile's texels do.

tests/3d's `spotshadow` (two spot lights, a 3x3 and a disc), `pointshadow`
(a point light between pillars and two walls) and `shadowatlas` (six
lights, `maxLocal` 3, beside the sun's two cascades: the three that matter
most cast, a second frame keeps their tiles, a moved caster draws its
light's again) are its frames. Measured as above (two spot lights and a
point light over 25 posts, 33.6 ms unshadowed): their eight tiles drawn
each frame, 62.2 ms (1.85x); kept while nothing moves, 49.2 ms (1.46x: the
lookups alone). `Shadows` adds 115 KB natively (117 KB as wasm32),
`local` 46 KB more (43 KB): a program whose sun alone casts links none of
the local tiles.

## Sky and environment

`renderer.use(new Sky(device))` draws a sky behind the scene;
`renderer.use(Environment.fromImage(device, mime, bytes))` an
equirectangular image behind it that also lights it (image-based ambient
and reflections). The showroom puts the optional features together: an
environment map, normal maps, two shadow cascades, a morphing surface and
glass:

<Example id="showroom"/>

### Image-based light, prefiltered

`Environment.prefiltered(device, mime, bytes, levels)` lights the scene
from an atlas filtered once ahead (a tool: Expansion's `tools/envbake.py`):
`levels` rows of the sphere (equirectangular, width by width / 2) by
roughness (GGX's lobe convolved, the split sum's first half) and the
diffuse irradiance's row below them. The standard material reads two rows
by its roughness, blended, along the reflection, and the last along its
normal: 128 x 448 for 6 levels, 224 KB on the GPU, no mip levels.

[examples/gltf-showcase](/examples/gltf-showcase) shows Khronos' sample
models (DamagedHelmet, FlightHelmet, SciFiHelmet, the extensions' tests)
under prefiltered HDR environments, compared with the sample viewer's
renders in its README (tens of MB of models: fetched when it plays):

<Example id="gltf-showcase" file="Showcase.hx" region="environments"/>
