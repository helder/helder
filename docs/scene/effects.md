# Post effects and the view buffers

```haxe
var post = new PostProcess(device);
post.ao = new Ssao({radius: 0.5, intensity: 1, samples: 8, halfRes: true});   // GTAO
post.dof = Dof.tiltShift({band: 0.2, falloff: 0.3, strength: 1});           // or Dof.focus({distance: 6, aperture: 0.02})
post.outline = new Outline({width: 2, color: new Vec4(1, 0.8, 0.2, 1)});     // group 1; outline.group(2, color, width)
Outline.select(node);                                                          // node and what is under it, group 1 (0: none)
post.antialias = Fxaa;                                                         // None | Fxaa
post.lut = Lut.fromImage(device, image);                                       // a 16 cubed strip (256 x 16); Lut.of(device, 16, grade)
renderer.post = post;                                                          // the renderer draws what they read
```

The effects are a `PostProcess`'s fields, null by default: an effect a
program never sets is not linked (its class, its passes, its shaders,
and the view buffers if none reads them: `tests/3d/size/PostSize.hx`).
The order is fixed by what is right: AO in the lighting, depth of field
in linear light before bloom, the curve, the grade, the LUT; FXAA in
the composite's read of the scene, the outline over everything. The
composite stays one pass: a variant compiled at build time with the
effects folded in (and one with FXAA), each effect off while its part of
the block is zero.

## The effects

- **The view buffers** (`ViewBuffers.of(renderer)`, a `RenderFeature`):
  a single-sampled prepass of the frame's opaque draws (pbr's prepass
  variants: the position, normal, roughness and alpha slots alone; a
  material of its own that replaces one of those gets its own prepass
  variants) into a sampled `Depth32F` depth and an `RGBA8` target of the
  view-space normal (octahedral, xy), roughness (z) and the selection
  group (w). One pass of one colour target: gfx has no MRT. The main
  pass's multisampled depth is not theirs. AO, depth of field and the
  outline ask for them (`renderer.post` must be the chain: the renderer
  draws them); `scale` draws them at a share of the frame's size, by
  default half for AO and depth of field, whole with an outline. A
  program's own pass may read them (`depth`, `normals`,
  `inverseProjection`) in an `AfterPass` hook.
- **`Ssao`**: GTAO (Jimenez et al. 2016): slices of the hemisphere about
  the view (`slices`, 1 or 2), each's two horizons found in `samples`
  steps out to `radius` metres along whole texel steps (each tap a
  texel's centre on the slice), the visible arc integrated against the
  projected normal as a share of the slice's arc unoccluded (a plane is
  open whatever the slices: no stripes), at half the frame's size
  (`halfRes`), then blurred up to the view buffers' size by depth
  (bilateral), before the main pass. The standard material darkens its
  indirect light by it alone (the ambient, the environment's light and
  reflections), not the sun's or the lamps': a lit wall keeps its
  light. `intensity` is a power.
- **`Dof`**: a circle of confusion from the view buffers' depth, the
  scene's light gathered on a disc that wide (Vogel's, `samples` taps) at
  half the frame's size, a nearer tap taken only where its own circle
  reaches (a sharp foreground does not bleed), mixed in where the circle
  is wider than a texel. `Dof.focus({distance, aperture})`: a thin lens,
  sharp at the distance, its blur at infinity the aperture (a share of
  the frame's height), at most `radius`. `Dof.tiltShift({band, falloff,
  strength})`: a diorama's lens, sharp within `band` of the focus depth
  (a share of it), blurred past `falloff` more to `strength` times
  `radius`; its focus the depth under the frame at `center` (its v; the
  middle by default), or `distance`. A world's depth, not the screen's
  band: a far island inside the band is blurred.
- **`Outline`**: the selection is data, a group (1 to 255) on a node
  (`Outline.select(node, group)`, a component; its descendants take the
  nearest's), written by the prepass; the composite finds a group's edge
  within its width of a pixel (16 taps) and draws its colour over
  everything, see-through surfaces too. Each group has a colour and a
  width (`group(k, color, width)`); the view buffers are drawn whole.
- **`Fxaa`** (`post.antialias`): Lottes' FXAA 3 console pass, in the
  composite's read of the scene (its light read along the edge through
  the pixel, before the curve). A `<Scene>`'s MSAA stays the default:
  FXAA is for a box drawn with one sample (`antialias={false}`), or both.
- **`Lut`**: a 16 cubed (or 32) table as a 2D strip (gfx has no 3D
  textures: size slices of size by size side by side, red across, green
  down, blue by slice), read once in the composite after the grade,
  display values in and out: `Lut.fromImage(device, image)` (an
  identity strip graded in an image editor), `Lut.fromBytes(device,
  size, bytes)`, `Lut.of(device, size, (r, g, b) -> new Vec3(...))`;
  `strength` mixes it in.

## In markup

`<Effects>` configures a `<Scene>`'s chain (its box turned
HDR), and the effects in it are set while their tags are there (`import
helder.scene.view.EffectTags.*`; a `<Show>` toggles one); a node's
`outline` prop is its selection group, so a hover is a binding:

```haxe
<Scene grow={1}>
  <Effects bloom={0.05} toneMap={AgX}>
    <Ssao radius={0.5} samples={8}/>
    <Dof tiltShift={true} band={0.2}/>
    <Outline width={2.0} color={gold}/>
    <Fxaa/>
    <Lut grade={grade}/>
  </Effects>
  <mesh shape="box" outline={hovered() ? 1 : 0} onPointerEnter={_ -> hovered(true)} onPointerLeave={_ -> hovered(false)}/>
</Scene>
```

The tags are typed components (their props the effects' options: a typo
is a compile error, and an effect never named is not linked).
The example toggles each effect, the outline following the shape
clicked (drag to orbit):

<Example id="postfx"/>

## What they cost

Measured headless (`tests/3d/EffectBench.hx`: the
frames' courtyard below at a phone's render size, 0.75 of 1080 x 2400,
810 x 1800, each frame read back, the median of 15) on Mesa's llvmpipe (a
Ryzen 5 3600's 12 threads): a CPU's rasterizer, not a phone's GPU, so
the ratio to the frame without them is what carries over, not the
milliseconds. The passes and the texel reads a pixel are the code's:

| | Passes | Reads a pixel | llvmpipe, 810 x 1800 |
|---|---|---|---|
| the frame without them | | | 37.6 ms |
| view buffers (half size) | 1 geometry pass: the opaque draws | 2 (base colour, roughness) | +3.4 ms (+9%) |
| `Ssao` (2 slices of 8 steps; with the view buffers) | 2, half size | 34 (GTAO), 19 (blur), 1 in the main pass | +17.5 ms (+47%) |
| `Dof.focus` (16 taps; with the view buffers) | 1, half size | 34, 3 in the composite | +18.1 ms (+48%) |
| `Dof.tiltShift` (16 taps; with the view buffers) | 1, half size | 34, 3 in the composite | +13.1 ms (+35%) |
| `Outline` (with the view buffers, whole) | none | 17 to 33 in the composite | +13.0 ms (+35%) |
| `Fxaa` | none | 8 in the composite | +3.1 ms (+8%) |
| `Lut` | none | 2 in the composite | +1.0 ms (+3%) |
| all of them, and bloom (6 levels) | 15 post passes | | +60 ms (x2.6) |

D3D11's WARP finds the same order (`EffectBench` on Windows). On a phone,
prefer AO's one slice of 4 to 6 steps (`slices: 1, samples: 6`), depth of
field's 16 taps and the view buffers at half size (no outline). What each
adds to a program, natively (Linux x86-64) and as wasm, against the chain
without one (`tests/3d/size/sizes.sh`'s post table): FXAA 29 KB and 29
KB; a LUT 100 KB and 111 KB (the composite's variants with the effects);
an outline 224 KB and 254 KB, AO 261 KB and 297 KB, depth of field 241 KB
and 275 KB (those and the view buffers' prepass); all of them 329 KB and
364 KB.

## Tests

The frames: `tests/3d`'s prepass (the view buffers shown: depth, normals,
the selected tinted), ssao, dof, tiltshift, outline (two groups, one
behind a glass pane), fxaa, lut and effects (all at once; its probe
draws it again and checks a frame allocates nothing: `hxmc.GcStats`),
natively and in Chromium (`3d-web`); their CPU halves in
`src/helder/scene/render/Effects.test.hx` (natively and as wasm32-wasi);
from TypeScript, `tests/typescript/helder/effects.ts`.
