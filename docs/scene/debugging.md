# Debugging

`FrameStats` keeps the last frames' times (and, given to `add`, the CPU's
share of each), the renderer's counts, `percentile(0.5)`, `percentile(0.99,
true)` and `fps()` without allocating; `Overlay` draws them over the frame
with `helder.ui`'s drawn renderer (put `src` on the class path where it is
used): its bars and figures, with `detail` the fps, frame time and CPU
p50/p99 and the program's own `lines`, and with `extra` a program's own
controls in its pass (`text` in its pixel font, `rect`; `panel = false`:
those alone).

The performance examples use it: [Instancing](instancing.md)'s asteroid
belt, [GPU particles](particles.md)' galaxy,
[examples/bunnymark](/examples/bunnymark) and
[examples/physics-stress](/examples/physics-stress). What a frame costs
in draw calls, by pass: [Instancing](instancing.md#draw-calls-by-pass).

## Headless

`helder run <entry> --headless` runs a program offscreen on a virtual
clock: `--snap out.png --at 2` writes its frame at two seconds, `--stats
out.json` every frame's times and counts (the draws by pass). The 3d
lane's frames and the examples' videos on the site are made this way.
