# HDR and post-processing

An offscreen renderer made with `hdr` (`new Renderer(device, true,
samples, true)`; a `<Scene hdr>` box) draws in linear light into half-float
targets (RGBA16F: light brighter than white kept; the shaders' last step
`PbrShader.output` leaves the tone mapping to later), and a `PostProcess`
turns the frame into the 8-bit image shown:

Its effects (AO, depth of field, outlines, FXAA, a LUT: [Post effects
and the view buffers](effects.md)) are fields of it, null by default.

```haxe
var post = new PostProcess(device);   // into RGBA8 targets (a <Scene>'s box's); (device, RGBA8, true): the frame
post.bloom = 0.05;                    // the share of the light spread: no threshold, what is bright blooms
post.toneMap = Aces;                  // Narkowicz's, the 8-bit path's; AgX; Clamp
post.saturation = 1.05; post.contrast = 1.05; post.lift = ...; post.gain = ...;
post.vignette = 0.3; post.grain = 0.03; // both 0 by default: no grain, a still dither
post.levels = 4; post.base = 2;       // a cheaper bloom: 4 levels from a quarter of the frame (default 6 from half)
renderer.post = post;                 // a <Scene hdr>'s box runs it; else post.run(enc, hdrColor, target, w, h, time)
```

Outside a `<Scene>`, the program draws into its HDR targets and runs the
chain into the frame itself (`renderer.drawInto`, then `post.run`). Tap
the example, or press Space, to switch the tone mapping: ACES, AgX, and
none (clipped at 1, what tone mapping saves):

<Example id="scene-post"/>

## Bloom

Bloom is the physically based kind (Jimenez, Call of Duty: Advanced
Warfare; Unity's HDRP): the frame filtered down a chain of half-sized
RGBA16F targets (13 taps, the first level in Karis' average against
fireflies) and back up (a tent filter, each level added to the one
above), mixed into the frame by its share. A run records 2 * levels
passes (6 levels by default) and allocates nothing; its targets are the
GPU's, as many as the levels, made again when the size, the base or the
levels change. On a phone 4 levels from a quarter of the frame (`base = 2`)
look alike at a third fewer passes and a quarter of the pixels.
`tests/3d/bloom.png` is its frame. A GPU that cannot draw into half floats
(GL ES without EXT_color_buffer_half_float or _float; WebGL2 enables
either): a `<Scene>` says so once and draws in 8 bits.

## Stages of your own

A program's own passes join the chain after the grade (`PostStage`), or
before the composite in linear light (`post.add(shader, bytes,
BeforeComposite)`: its image the scene's RGBA16F light, drawn into RGBA16F
targets, the last one's what depth of field, bloom and the composite
read; a blur of the program's own belongs there): a
shader drawn over the whole target, its vertex `{pos:Vec2}` (a triangle
in clip space, the chain's), its first texture the image so far (tone
mapped: a pixel art finish, a CRT, an outline), its first uniform block
the bytes given. Stages run in order, each reading the last one's image;
the last draws into the chain's output (the frame, or `run`'s target, of
any size: a frame drawn small and finished in big pixels on the screen),
the others into two RGBA8 targets of the run's size; the chain makes their
pipelines for what they draw into:

```haxe
var stage = post.add(FinishShader, finishBytes);   // fragment(i, p:{view:FinishView, frame:Texture2D})
stage.filter = Nearest;                            // read in big pixels (Linear by default)
stage.bind = enc -> enc.setTexture(slot, noise, sampler);  // anything else it reads
stage.enabled = false;                             // passed over; post.remove(stage)
stage.prepare = enc -> blurHalf(enc, post.source, post.width, post.height);  // its own passes first
```

While the chain runs, its context is the stages': `post.source` is the
scene's light it was given (linear, RGBA16F, its alpha the scene's
coverage) and `post.width`, `post.height` its size. A stage's `prepare`
is recorded before the chain's passes, outside any pass, every run
(enabled or not, so it may switch itself), for passes of its own from
that light: Little Skies' tilt-shift blurs it at half size there, then
mixes the blur in as its stage. A `<Scene hdr>`'s chain is there when its
`setup` is called, so stages are added there.

`tests/3d/poststage.png` is the bloom frame through two (a sepia grade,
then scanlines: tests/3d/StageShaders.hx). [examples/afterglow](/examples/afterglow)
finishes its whole frame as a painting this way.
