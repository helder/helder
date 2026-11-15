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
and up to four point or spot lights (a world without lights:
`renderer.sun*`), with a sky-and-ground ambient: the world's first
hemisphere light (`Light.hemisphere(sky, ground, intensity)`: the sky's
colour from above, the ground's from below, blended by the normal), else
`renderer.sky` and `renderer.ground`. A light's `kind` is `Directional`,
`Point`, `Spot` or `Hemisphere` (`light.local`: a point or a spot light);
tests/3d's `hemisphere` frame is lit by a hemisphere light alone. `renderer.rim` (a colour times intensity) and
`rimPower` add a rim light from the sun's side along the silhouettes.
`material.emissiveNight` (0 to 1) keeps a material's light to its night
side, faded in across the terminator (a planet's city lights).

## Shadows

Shadows are opted in: `renderer.use(new Shadows(device))` (one shadow map
for the directional light, fitted to the casters, filtered 3x3;
`Shadows.cascaded(device, size, split)`: two cascades, the first sharp
over the camera's view up to `split` metres; a primitive's casters one
instanced draw a cascade).

Softer shadows are opted in with `.soft(radius, samples, spread)`: a disc
of `samples` taps (8 for phones, 16, 32) out to `radius` metres, turned
per texel; with a `spread` a blocker search first (half as many taps), the
penumbra widening by `spread` a metre from its caster up to the radius,
so a shadow is sharp where it meets what casts it (PCSS); `spread` 0, the
radius everywhere. Each tap is compared with the surface's own depth there
(its plane as the light sees it), so a far smaller `bias` than the 3x3
filter's keeps tilted surfaces from shadowing themselves, and low casters
(a rail on a green) still cast: Little Skies (helder/little-skies) uses
`bias = 0.001` with one 2048 map (tests/3d's `softshadows` frame;
`shadows` and `cascades` keep the 3x3 filter).

<Example id="scene-lights"/>

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
