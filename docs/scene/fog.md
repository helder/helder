# Fog

```haxe
var fog = new Fog(new Vec3(0.05, 0.07, 0.12), 0.03);   // colour (linear), density per metre
fog.start = 5;                       // metres clear before it
fog.falloff = 0.3; fog.height = 0;   // thinner upwards: valleys fill, hills and the sky above clear
fog.max = 0.9;                       // the most it hides
renderer.fog = fog;                  // null: none
glow.fog = false;                    // a material it does not cover
```

Exponential fog by distance, 1 - e^(-density * the distance past start),
with an optional height falloff (the density e^(-falloff (y - height))
times its own, summed along the view in closed form: Unreal's and
Quilez's exponential height fog), in linear light before tone mapping
(its colour times the exposure), so an HDR frame blooms and grades it
with the rest. It covers the standard material and the materials made
from it (`MaterialShader`), `Sky` and `Environment`'s background (as far
as the camera's far plane: uniform fog covers the sky, height fog clears
above), and fades `GpuParticles` and Additive materials (light added, not
turned to the fog's colour).

Here the fog's floor rises and falls (`fog.height`), the sky covered with
it; the sign at the end of the colonnade is a material the fog does not
cover:

<Example id="scene-fog"/>

## In a shader of your own

A program's own shaders take it from `FrameInfo.fog` (`Fog.colorOf`,
`Fog.shapeOf` into their block, `PbrShader.fogAmount(color, shape, eye,
point)` in the shader). `tests/3d/fog.png` is its frame;
`Material.test.hx` checks the amounts.
