# helder.parallel

One body over a range of items, compiled at build time into the forms
that run it: SIMD lanes on this thread, those lanes across helder.jobs'
threads, one item at a time, and a GPU compute dispatch, picked per call. The body is Haxe as a compute shader's is, lowered by the same
compiler (helder.gfx.shader's IR), and its CPU forms are printed by the CPU
back end's emitter. The design and its measurements: docs/design/parallel.md.

```haxe
import helder.parallel.Items;
import helder.parallel.Parallel;
import helder.gfx.shader.ShaderMath.*;

var heights = new Items<Float>(w * h);
final k = 0.01;
each(w * h, i -> heights[i] = Math.sin(i % w * k) * Math.cos(Std.int(i / w) * k));

map(speed, i -> length(vel[i].xyz));                      // speed[i] = ..., for each i of speed.length
var energy = sum(n, i -> 0.5 * mass[i] * dot(vel[i], vel[i]));
var lowest = min(n, i -> pos[i].y);
var span = reduce(n, vec2(1e30, -1e30), i -> vec2(pos[i].y, pos[i].y), (a, b) -> vec2(Math.min(a.x, b.x), Math.max(a.y, b.y)));
```

| | |
| --- | --- |
| `each(n, i -> ...)` | the body for each `i` of `0...n` |
| `map(out, i -> value)` | `out[i] = value` for each `i` of `0...out.length` (each `return` of a block body a store) |
| `sum(n, i -> v)`, `min`, `max` | a reduction: sum of Int, Float or a vector; min and max of Int or Float |
| `reduce(n, empty, i -> v, (a, b) -> c)` | `combine` associative, `empty` its identity; Int, Float or a vector |
| `kernel(function(i:Int, p:{...}) ...)` | a named body of its own parameters: `K.run(n, {...}, ?on)` |
| `Items<T>` | n values of T outside the GC heap, in the GPU's storage layout; `buffer(device)` its GPU buffer |
| `read(items)` | (a coroutine) its values the CPU's, read back where a dispatch wrote them |
| `On` | `Auto` (the default), `Scalar`, `Simd`, `Jobs`, `Gpu`: the last argument of each |

`min(a, b)` and `max(a, b)` with no function are ShaderMath's, so a body
that calls them keeps working whichever was imported last.

## Items

`new Items<T>(n)` is n zeroed values of T: Int, Float, Vec2, Vec4, Mat4,
or a struct of those (a `@:structInit` class, a typedef of an anonymous
structure; public: its Items is a type of its own). Its elements are
float32s and int32s at their std430 offsets, the layout a GPU storage
buffer has, so the next part draws and dispatches over the same bytes.
Bool and Vec3 have none (an Int; a Vec4).

```haxe
@:structInit @:publicFields class Particle {
	var pos:Vec4;   // xyz, w: age
	var vel:Vec4;
}

var ps = new Items<Particle>(100_000);
ps[0] = {pos: vec4(0, 1, 0, 0), vel: vec4(0)};     // an object literal of its fields, or a Particle
var q = ps[0];                                    // a Particle (CPU code: checked, allocates)
var vs = Items.of([vec2(1, 2), vec2(3, 4)]);
vs.copyTo(list);
ps.dispose();                                     // the memory back now
```

`items.buffer(device)` is its GPU buffer (a storage buffer, also a
vertex and instance buffer: draw particles from it), its values uploaded
where the CPU's are newer; from then on a body that writes it runs on the
GPU under Auto. Values move between the two sides only when the other one
reads: a dispatch after a CPU write uploads, `items[i]` after a dispatch
reads back (and waits). On Metal and the CPU back end the bytes are the
buffer's own (shared memory): nothing is copied. WebGPU reads back
asynchronously only: there `items[i]` after a dispatch throws until
`read(items)` is awaited in a coroutine (elsewhere `read` reads back at
once).

`dispose()` frees the memory at once; an Items never disposed is freed
when the collector finds it unreachable (said in debug builds; natively:
WebAssembly runs no finalisers, so dispose() there). Indexing outside
`0...length`, or a disposed Items, throws. On the CPU an element read
outside a body builds the value (an object for a class); inside a body
it is lanes.

## Where it runs

The last argument, or `HELDER_PARALLEL=scalar|simd|jobs|gpu` for every
call (tests, bisecting a difference):

- `Scalar`: one item at a time, the body as Haxe on doubles, rounded to
  float32 where it stores: the reference.
- `Simd`: 4 items a call on this thread, float32 lanes (`hxmc.simd`: SSE,
  NEON, WebAssembly SIMD128), reads and writes at `i` as 128-bit rows.
- `Jobs`: Simd's range in chunks (4 a thread, multiples of 4 items) on
  `helder.jobs.Spread`'s threads and this one; on this thread alone where
  there are none (a browser's wasm32, `Jobs.workers = 0`).
- `Gpu`: a compute dispatch on `Parallel.device` (a UiWindow's device
  where it has compute, set when the window makes it; or set it), in a
  compute pass of its own outside a frame (or between a frame's passes:
  not inside one), before the next frame's passes. Approximate: the GPU's
  rounding, fused multiply-adds and functions are its own (within 3e-6 of
  Simd on the particle step). Not for reductions yet (they need workgroup
  memory in compute()); GLSL leaves `%` of negative Ints undefined.
- `Auto`: **Gpu from residency alone**: where an Items the body writes
  was last written by a dispatch, or is drawn by the GPU
  (`items.buffer(device)`), and `Parallel.device` has compute, the body
  runs there at once, so that what the GPU draws the GPU moves, never
  uploaded each frame. **Otherwise Simd or Jobs, by the site's own
  timings**: its first run on one thread, one on the threads where those
  might win, then the one predicted faster for the call's n, changed only
  for a clear gain. Simd and Jobs give the same bits, so a CPU result is
  deterministic whatever Auto picks.

`Parallel.log = true` prints each site's choice when it changes
(`helder.parallel: Terrain.hx:40 each: jobs (n 30000, simd 6.1 ns an item, jobs 1.2)`).

**Precision and determinism.** A body's Float is 32 bits in every form but
Scalar. Simd and Jobs give the same bits on every CPU, target and thread
count (no fused multiply-adds; fixed chunks). A reduction cuts the items
into chunks of 1024, each reduced in its 4 lanes and the lanes in pairs,
the chunks' results combined in order: the same bits on one thread or
twelve. Scalar differs by rounding (within 4e-6 on the particle step after
64 steps). The GPU form will be close, not the same: anything replayed
(snapshots, rewinds, lockstep) runs on the CPU forms.

## A kernel

```haxe
final Relax = kernel(function(i:Int, p:{from:Items<Vec4>, to:Items<Vec4>, omega:Float}) {
	p.to[i] = p.from[i] * p.omega;
});

Relax.run(n, {from: a, to: b, omega: 1.5});
Relax.run(n, {from: b, to: a, omega: 1.5}, Jobs);
```

Its parameters are typed once and checked at each `run` by Haxe (a
missing or extra field, a wrong type). It reads its parameters and
statics, not locals.

## What a body may do

Checked at build time, each error at its expression (`each: ...`,
`kernel: ...`; the shader compiler's words for what shaders lack):

- **Types:** Int, Float, Bool, Vec2/3/4, Mat4 and structs of them, as a
  shader's; `Items<T>` of the storable ones. No String, Array, Dynamic,
  classes, enums, closures, `Null<T>`, allocation, exceptions or I/O.
- **Calls:** ShaderMath's builtins, `Math.*` (sqrt, sin, ..., min, max,
  floor), `Std.int`, and static functions of the same rules (not
  recursive; an Items is not passed to them).
- **Statements:** locals, if, while, `for (k in a...b)`, break, continue,
  return; no switch, no do-while.
- **Captures:** what a body reads from around it (locals, fields of
  `this`, statics) is read at the call: Int, Float, Bool, vectors, Mat4,
  Items. A body assigns none of them, nor its index.
- **Items:** indexed (`a[i]`, `a[i] = v`, `a[i] += v`) or their length
  read (`a.length`), not passed on. One is written at the item's own index
  only (`i`, or a local copy of it never assigned), and one written is not
  read at another index. So items are independent: the order and the
  threads change nothing. Graph-coloured writes (`a[other[i]] = ...`) are
  not in this version.
- **At the call** (thrown): an Items read or written at `i` with fewer
  than n items, a disposed one, a written one passed twice (`from: a, to:
  a`).

## How it is built

`each(n, body, on)` (Parallel.hx's macros, ParallelMacro):

1. the body is typed in the caller's scope and scanned (ParallelScan): its
   captures, how it reaches each Items, its rules;
2. it is lowered as a compute stage (ParallelLower, a Lower whose stage
   input is the index and whose captures become the stage's parameters
   where first read: scalars, and storage buffers for Items);
3. Soft (the CPU back end's emitter) prints its lanes and its scalar
   function; its index and the locals copied from it are rows (Soft.rows:
   a read or write at them four consecutive elements, `Soft.rowsRead`,
   `helder.gfx.soft.Rows`), the rest gathers as compute's;
4. each and kernel are lowered once more as a compute stage (an IR
   transform of the same function: its index `id.x + id.y * 65535 * 64`,
   the invocations past n returned, the captured values one uniform
   block's fields, the Items storage buffers) and printed in the build's
   shader languages: the site's GpuForm, data a GpuRunner dispatches
   (reached from `Parallel.device` alone: a program that never sets one
   has none of helder.gfx's calls, and none of its imports on wasm32);
5. a class per call site beside the caller holds the range loop (4 items a
   call, the last few under a mask), the scalar loop, the chunk callback
   for `helder.jobs.Spread.run`, the site's timings (Site), and
   `dispatch(n, on, captures...)`, what the call becomes: the checks, the
   form, the context (the captures' values and the Items' records) on the
   stack.

`-D helder.parallel.print` prints each site's class.

## Measured

`bun run test bench parallel` (tests/bench/ParallelBench.hx): the design's
particle step, 32 bytes a particle read and written, µs a step, the least
of its runs; `gpu` the step on the GPU, its particles staying there (a
32-byte read back after a run of them: the wait), `gpu+read` a step then
everything read back. Windows, a Ryzen 5 3600 (12 threads), an NVIDIA GT
710 (D3D11; 64-bit DDR3: about 14 GB/s), the box shared with
other agents' builds: this run at 12-25% load. Two more at 100% load were
2x slower, and `jobs` 2 ms a call whatever n (its threads preempted: a
run waits for its last chunk), where Auto timed it and kept to `simd`
below 300,000:

| N | today | hand | scalar | simd | jobs | auto | gpu | gpu+read |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1,000 | 28.2 | 1.8 | 25.8 | 5.8 | 6.2 | 7.3 | 68.9 | 81.1 |
| 10,000 | 282 | 18.1 | 491 | 58.9 | 16.2 | 18.8 | 101 | 240 |
| 100,000 | 3189 | 183 | 2618 | 545 | 113 | 113 | 634 | 2328 |
| 1,000,000 | 32695 | 3020 | 25619 | 5710 | 1063 | 1141 | 6483 | 21631 |

(The GPU columns from a run at 20-39% load.) The GT 710 never beats this
CPU's threads on a bandwidth-bound step; what decides is where the data
is read: particles the GPU draws cost an upload a frame after a CPU step
(more than the GPU's own step), which the residency rule avoids.

`today` is examples/fountain's CPU fallback (the compute stage's main over
an Array), `hand` the prototype's lanes written by hand (the same bits as
`simd`). The generated lanes are 3x the hand-written ones: Soft's lane
values are structs (a Particle's two Vec4s, a Vec3's three lanes), which
hxmc keeps in memory more than the hand form's F32x4 locals; closing that
is the emitter's next step. Jobs is under the hand lanes from 3,000 items.

## Tests

- src/helder/parallel/Parallel.test.hx (the test lane, natively and as
  wasm32-wasi): properties of random n, data and On: Simd and Jobs the
  same bits, Scalar within float32's rounding, the items past n untouched,
  reductions the same bits for 0 to 11 helper threads, Items' layout and
  bounds, the throws at the call.
- The parallel lane (`bun run test parallel`): tests/parallel/reject, one
  program a rule, each rejected with its message at its line; and
  HELDER_PARALLEL's forms (tests/parallel/ForcedCheck.hx, Parallel.log).
- tests/parallel/GpuCheck.hx (gfx-compute: D3D11, GL on Mesa, Metal;
  gfx-soft: the CPU back end's shared memory): the Gpu form against Simd
  (tails, loops, gathers, Ints, captured vectors, matrices, Bools, a
  kernel, 4M items past a row of workgroups, 64 particle steps resident),
  the residency rule and read backs; GpuWebCheck.hx (gfx-compute-web,
  WebGPU on SwiftShader): `read(items)` awaited.

## Not yet

Reductions on the GPU (with compute()'s workgroup memory), TypeScript
(`helder/parallel`), struct values in reductions and captures, an Items
passed to a function, graph-coloured writes, and uploads straight from an
Items' memory (one copy through a scratch block now, where the device
copies at all).
