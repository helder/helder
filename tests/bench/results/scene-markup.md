# 3D in markup against code, by milestone

DESIGN-MARKUP.md 9's benchmark (tests/bench/SceneMarkupBench.hx, `bun run
test bench scene-markup`): the same scene in code and in markup at 1,000
and 10,000 meshes of one geometry and material, natively on a headless
device and as wasm32-wasi (no GPU there: bare nodes, the world's matrices
for the pass). Each milestone adds its section; the latest is the lane's
output (bin/bench/scene-markup.md) as it ran.

Columns: mount (ms, KB allocated); a frame with every node moving, the
markup's share (the writes, the clock's steps, the flush: ms, its ratio to
code's, GC bytes) and the recorded pass (ms; with it, the ratio to code's);
of 100 idle frames, those asking for a redraw; unmount (ms, and the world's
nodes left over its count before mounting).

Variants: `code` (world.node, MeshRenderer.attach, a loop writing
positions), `constant` (markup, positions set once; the same loop writing
the nodes it made), `signals` (each position bound to a signal written
every frame), `steps` (examples/planets' pattern: a helder.ui.Clock step
per node writing its signal). The design's `onFrame` variants come with
M2. `constant` builds its rows with an array comprehension, not a `<For>`:
a row's `p()` (a Vec3 through a closure) is the Quat gap of 10.1 until M1.

## M0: the prototype (2026-11-15, windows-x86_64, D3D11 WARP)

What it shows:

- **Every removed node leaks**: `left` is all of them (1,001 and 10,001),
  and SceneUiCheck's leak check (a `<Show>` toggled 100 times, a `<For>` of
  100 emptied and filled) leaves 305 nodes of 1 (a known failure until M2).
- **Signals cost 15x to 70x code's frame** in the markup's share, and
  allocate 32 B per node per frame (each Vec3 boxed by its signal and its
  binding): 320 KB a frame at 10,000. With the pass, 1.7x to 7x.
- **Mounting** costs 7x code at 1,000 and 40x natively at 10,000 (180 ms;
  27 ms as wasm32, 2.2x).
- **Clock steps never stop**: `steps` asks for a redraw in every idle
  frame, and its steps outlive the markup that added them.
- Writing markup's nodes directly (`constant`) costs what code does.

### windows-x86_64

| variant | nodes | mount ms | mount KB | frame ms | x code | B a frame | pass ms | with the pass, x code | idle drawing | unmount ms | left |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| code | 1000 | 0.375 | 894 | 0.039 | 1 | 0 | 0.792 | 1 | 0 | 0.129 | 0 |
| constant | 1000 | 2.731 | 2515 | 0.039 | 1 | 0 | 0.916 | 1.15 | 0 | 0.005 | 1001 |
| signals | 1000 | 3.689 | 2907 | 0.584 | 14.97 | 32000 | 0.859 | 1.74 | 0 | 0.123 | 1001 |
| steps | 1000 | 3.7 | 2964 | 0.619 | 15.87 | 32000 | 0.866 | 1.79 | 100 | 0.136 | 1001 |
| code | 10000 | 4.488 | 10201 | 0.362 | 1 | 0 | 6.84 | 1 | 0 | 2.772 | 0 |
| constant | 10000 | 179.672 | 29731 | 0.363 | 1 | 0 | 7.945 | 1.15 | 0 | 0.005 | 10001 |
| signals | 10000 | 186.272 | 33497 | 24.278 | 67.07 | 320000 | 7.711 | 4.44 | 0 | 0.836 | 10001 |
| steps | 10000 | 193.878 | 34145 | 25.41 | 70.19 | 320000 | 8.03 | 4.64 | 100 | 0.484 | 10001 |

### wasm32-wasi

| variant | nodes | mount ms | mount KB | frame ms | x code | B a frame | pass ms | with the pass, x code | idle drawing | unmount ms | left |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| code | 1000 | 1 | 861 | 0.06 | 1 | 0 | 0.391 | 1 | 0 | 0 | 0 |
| constant | 1000 | 3 | 1411 | 0.068 | 1.13 | 0 | 0.417 | 1.08 | 0 | 0 | 1001 |
| signals | 1000 | 4.015 | 1802 | 0.559 | 9.32 | 32000 | 0.492 | 2.33 | 0 | 0 | 1001 |
| steps | 1000 | 4.003 | 1858 | 0.488 | 8.13 | 32000 | 0.47 | 2.12 | 100 | 0 | 1001 |
| code | 10000 | 12.043 | 11744 | 0.562 | 1 | 0 | 3.729 | 1 | 0 | 1.005 | 0 |
| constant | 10000 | 26.715 | 17902 | 0.523 | 0.93 | 0 | 4.392 | 1.15 | 0 | 0 | 10001 |
| signals | 10000 | 34.034 | 21618 | 26.182 | 46.59 | 320000 | 4.52 | 7.15 | 0 | 2.999 | 10001 |
| steps | 10000 | 33.559 | 22267 | 26.207 | 46.63 | 320000 | 4.519 | 7.16 | 100 | 1 | 10001 |

## M1: typed bindings (2026-11-15, windows-x86_64, D3D11 WARP)

Run while other builds shared the machine: absolute times are 1.5-2x M0's (code's own pass 13.7 ms at 10,000, against 6.8), the ratios and bytes compare.

- **No regression from the typed path**: bytes a frame as M0's (32 B a node: the signal's own box of its Vec3; a bound signal's value is passed on as it is held, not unboxed and boxed again), the frame's ratio to code within the noise of M0's.
- **What M1 changes is not here**: struct values inline (no Signal needed), types checked when compiling, a light's or camera's set prop written in place; the frame's cost is the graph's, for M2's onFrame.
- A bound value allocates when it changes (the graph holds values boxed): a `Quat` 56 B, a `Float` 32. Motion every frame is `onFrame`'s (M2).

### windows-x86_64

| variant | nodes | mount ms | mount KB | frame ms | x code | B a frame | pass ms | with the pass, x code | idle drawing | unmount ms | left |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| code | 1000 | 0.669 | 894 | 0.053 | 1 | 0 | 1.014 | 1 | 0 | 0.16 | 0 |
| constant | 1000 | 6.546 | 2445 | 0.052 | 0.98 | 0 | 1.311 | 1.28 | 0 | 0.006 | 1001 |
| signals | 1000 | 5.6 | 2860 | 1.513 | 28.55 | 32000 | 1.387 | 2.72 | 0 | 0.112 | 1001 |
| steps | 1000 | 6.779 | 2917 | 1.21 | 22.83 | 32000 | 1.343 | 2.39 | 100 | 0.082 | 1001 |
| code | 10000 | 10.441 | 10201 | 0.839 | 1 | 0 | 13.735 | 1 | 0 | 5.756 | 0 |
| constant | 10000 | 278.769 | 29076 | 0.58 | 0.69 | 0 | 15.398 | 1.1 | 0 | 0.006 | 10001 |
| signals | 10000 | 307.452 | 32975 | 50.783 | 60.53 | 320000 | 16.009 | 4.58 | 0 | 1.953 | 10001 |
| steps | 10000 | 293.686 | 33623 | 46.432 | 55.34 | 320000 | 13.77 | 4.13 | 100 | 1.107 | 10001 |

### wasm32-wasi

| variant | nodes | mount ms | mount KB | frame ms | x code | B a frame | pass ms | with the pass, x code | idle drawing | unmount ms | left |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| code | 1000 | 1.996 | 861 | 0.125 | 1 | 0 | 0.575 | 1 | 0 | 0.53 | 0 |
| constant | 1000 | 6.055 | 1411 | 0.109 | 0.87 | 0 | 0.709 | 1.17 | 0 | 0 | 1001 |
| signals | 1000 | 8.115 | 1825 | 1.042 | 8.34 | 32000 | 0.776 | 2.6 | 0 | 0.51 | 1001 |
| steps | 1000 | 7.585 | 1882 | 1.013 | 8.1 | 32000 | 0.667 | 2.4 | 100 | 0.997 | 1001 |
| code | 10000 | 18.74 | 11744 | 0.91 | 1 | 0 | 6.008 | 1 | 0 | 2.054 | 0 |
| constant | 10000 | 38.98 | 17902 | 0.891 | 0.98 | 0 | 7.331 | 1.19 | 0 | 0.522 | 10001 |
| signals | 10000 | 52.712 | 21853 | 47.358 | 52.04 | 320000 | 7.091 | 7.87 | 0 | 4.04 | 10001 |
| steps | 10000 | 34.841 | 22501 | 33.518 | 36.83 | 320000 | 5.633 | 5.66 | 100 | 2.003 | 10001 |
