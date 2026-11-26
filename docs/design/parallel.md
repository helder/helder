# Parallel: one function, four forms

The roadmap's item: _one function over a range or buffers, compiled to SIMD
across jobs and GPU compute, picked per call. Workgroup memory and subgroups
in `compute()`, with particles, cloth and soft bodies first._

Approved (November 2026, the decisions at the end), and being built in
parts (Plan): the first, `Items` and the CPU forms, is `helder.parallel`
(src/helder/parallel/README.md). The prototype (draft PR #214,
`parallel-proto`) held the smallest end to end slice: one particle step
written once as a compute stage (`tests/bench/parallel/ParallelShaders.hx`),
its CPU forms written by hand as the kernel compiler would emit them
(`ParallelKernels.hx`, kept as the bench's `hand` column), and a bench
that ran them as scalar code, as 4-lane SIMD, across helder.jobs' threads
and on the GPU. The bench (`bun run test bench parallel`,
`tests/bench/ParallelBench.hx`) now runs the real API's forms against
those; its GPU columns come back with the Gpu form. The tables under
Measured are the prototype's. (`helder.jobs.Parallel`, named below, is
`helder.jobs.Spread` now: helder.parallel's `Parallel` took the name.)

- [What exists](#what-exists)
- [The API](#the-api)
- [One body, four forms](#one-body-four-forms)
- [Buffers between the CPU and the GPU](#buffers-between-the-cpu-and-the-gpu)
- [Workgroup memory and subgroups in compute()](#workgroup-memory-and-subgroups-in-compute)
- [Measured](#measured)
- [Plan](#plan)
- [Risks and open questions](#risks-and-open-questions)

## What exists

**helder.jobs** (`src/helder/jobs/`, README there):

- `Jobs.job(f).run(input)` (`Jobs.hx`, `JobDefinition.hx`): async work
  awaited from a coroutine. GC-free jobs are `@:hxmc.kernel @:hxmc.callback`
  functions over spans (`Job.hx`), run in safe regions
  (`hxmc.unsafe.Blocking`); GC jobs copy `Sendable` values across
  (`Sendable.hx`, `Wire.hx`). A 28 µs round trip natively, 45-53 µs on
  wasm32's workers.
- The pools: natively `Pool.hx` (`Jobs.size()` threads on one `Deque`), in
  a browser `WebJobs.hx` + `imports.mjs`/`worker.mjs` (Web Workers each
  instantiating the page's module, data copied in and out: no
  SharedArrayBuffer).
- **`Parallel.hx`**, the synchronous tier: `Parallel.run(f, ctx, count)`
  calls a GC-free callback `f(ctx, i)` for each `i` on the pool's threads and
  the caller's, all in safe regions, over memory outside the GC heap; the
  threads spin 2M iterations between runs, then sleep. Without threads
  (wasm32, `Jobs.workers = 0`) the caller makes every call. The CPU back
  end's tiles use it (`gfx/soft/SoftBackend.hx:725`). **This is the jobs
  form's dispatch, as it is.** Its round trip when its threads are awake:
  2-3 µs (measured below).

**GPU compute** (`src/helder/gfx/`, README "Compute"):

- `compute({size, main})` (`gfx/shader/ShaderMath.hx` →
  `ShaderMacro.compute` → `ShaderDefinition.compute`): a Haxe function
  `main(id:ComputeInput, p:{...})` compiled at build time to GLSL ES 3.10,
  WGSL, MSL and HLSL cs_5_0 (`Glsl.hx`, `Wgsl.hx`, `Msl.hx`, `Hlsl.hx`, from
  the IR in `Ir.hx`, lowered by `Lower.hx`). Parameters: uniform blocks
  (std140 structs), `Storage<T>`/`RWStorage<T>` (std430), textures,
  `StorageTexture`; `atomicAdd/Min/Max` on Int storage. The result is a
  `ComputeShader` (`ComputeShader.hx`): `pipeline()`, `groups(n)`,
  `params.<name>` (codecs for the CPU's bytes), and `main` as CPU code.
- Back ends with compute: D3D11 (feature level 11_0), Metal, GL ES 3.1 (GL
  on Mesa), WebGPU, and the CPU back end; WebGL2 has none
  (`Device.has(Compute)`, `Feature.hx`). No Vulkan.
- Missing (README "Compute"): workgroup memory, barriers inside a
  dispatch, subgroups, storage in render stages, storage read in the
  functions `main` calls, Vec3 storage elements, Float atomics. TypeScript
  has no `compute(...)` (its shader adapter, `typescript/lower/Definitions.hx`'s
  `TsAdapter`, has no Int).
- The CPU back end (`-D helder.soft`, `gfx/soft/`, `gfx/shader/Soft.hx`):
  the macro emits each stage a fifth time as Haxe over `hxmc.simd`'s 4
  lanes (`soft_cs` for compute: 4 invocations a call, uniform values kept
  scalar, ifs as masks and selects, `-D helder.soft.reference` the scalar
  form lane by lane). Its storage reads and writes go lane by lane with a
  bounds check each (`gfx/soft/Buffers.hx`), and a dispatch runs on one
  thread, workgroup by workgroup (so atomics come in the same order
  everywhere).
- Tests: `tests/gfx/ComputeCheck.hx` (`gfx-compute`, `gfx-compute-web`),
  `tests/gfx/ShaderCheck.hx` (the four languages' text, the rejections),
  `tests/gfx/SoftShaderCheck.hx` (lanes against the scalar reference, bit
  for bit).

**hxmc's SIMD** (`node_modules/@hxmc/source/hxmc/std/hxmc/simd/`):

- 128-bit value types on every hxmc target: `F32x4`, `F64x2`, `I32x4`,
  `U32x4`, `I16x8`, `I8x16`, ... (`F32x4.hx`): arithmetic, `min/max/pmin/pmax`,
  `sqrt`, `floor`, comparisons to masks, `select`, constant `shuffle` and
  `swizzle`, `sum`, loads and stores from `Bytes`, spans and (unsafe) `Ptr`.
  The ops are WebAssembly SIMD128's (`Simd.hx`, `hxmc/src/hxmc/SimdOps.hx`),
  lowered to SSE on x86-64, NEON on arm64 and SIMD128 on wasm32. No fused
  multiply-add (the same bits everywhere), no 256-bit types, no gathers.
- **No auto-vectorisation.** hxmc compiles with its own back ends
  (`hxmc/src/hxmc/x64`, `a64`, `wasm`); there is no C back end. Its loop
  work is versioning of Array reads (`LoopVersion.hx`). An experimental
  LLVM path (`-D hxmc.llvm=O3`, `Options.hx`: functions compiled by clang)
  could vectorise plain loops, but needs clang on the machine (not here)
  and is not what helder ships. So the SIMD form has to be emitted, as
  Soft emits its lanes: vectorising is the kernel compiler's job.

**Who would call it:**

- `helder.physics` (`src/helder/physics/`): a rigid-body core with
  struct-of-arrays contacts (`Contacts.hx`), sequential impulses,
  allocation-free steps, the same numbers on every target, snapshots.
  Particles, cloth and soft bodies are new solvers beside it, stepped from
  the same `FixedStep` (`scene/FixedStep.hx`); their determinism rule is
  physics': the same steps give the same numbers on every target (which
  the SIMD and jobs forms keep, the GPU form does not: below).
- helder.scene's particles: `GpuParticles` (`scene/render/GpuParticles.hx`)
  is closed-form (each particle's motion a function of time: nothing
  simulated); `examples/fountain` simulates with a compute stage and, without
  compute, runs `Spray.main` over an `Array<Drop>` and uploads (the "today"
  column below). Simulated particles (collisions, forces, fields) are the
  first users.
- The scene draws from storage buffers directly: a storage buffer is a
  vertex and instance buffer too (README "Compute"), so particles simulated
  on the GPU are drawn without a copy.

## The API

A package of its own, `helder.parallel` (TypeScript `helder/parallel`):
four definitions, one buffer type, one choice.

| | |
|---|---|
| `each(n, i -> ...)` | the body for each `i` of `0...n` |
| `map(out, i -> value)` | `out[i] = value` for each `i` of `0...out.length` |
| `sum(n, i -> v)`, `min`, `max`, `reduce(n, empty, i -> v, (a, b) -> c)` | a reduction |
| `kernel(function(i, p:{...}) ...)` | a named body: `K.run(n, {...})`, reusable, testable, its own parameters |
| `Items<T>` | n values of `T` (Int, Float, Vec2/3/4, Mat4, structs of them) on the CPU and, when used there, the GPU |
| `On` | `Auto` (the default), `Scalar`, `Simd`, `Jobs`, `Gpu`: the last argument of each |

The names are new in `src/helder` (`Items`, `On`, `each`, `map`, `sum`,
`reduce`, `kernel`; checked by grep; `helder.jobs.Parallel` stays the
internal tier under it, and the package is not named after it). The vector
types are written against `helder.math` (audit G's move of
Vec2/3/4, Mat3/4, Quat): the shader IR keys its types by path, so both paths
map to the same IR types during the move.

### A loop over a range

```haxe
import helder.parallel.*;

var heights = new Items<Float>(w * h);
final k = 0.01;
each(w * h, i -> heights[i] = Math.sin(i % w * k) * Math.cos(Std.int(i / w) * k));
each(w * h, i -> heights[i] *= falloff(i), Jobs);   // forced: this call on the threads
```

```ts
import {each, Items} from 'helder/parallel'

const heights = new Items<number>(w * h)
const k = 0.01
each(w * h, i => { heights[i] = Math.sin((i % w) * k) * Math.cos(((i / w) | 0) * k) })
```

The body is a lambda at the call: what it reads from around it is captured
by the definition (as `job(f)`'s constants are): finals and values never
assigned after (`k`) become uniforms, `Items` become bindings. Each call
site is a definition (one pipeline, one CPU form, made once).

### A map over typed buffers

```haxe
map(speed, i -> length(vel[i]));                     // Items<Float> out, Items<Vec4> in
map(out, i -> a[i] * scale + b[i]);
```

```ts
map(out, i => a[i] * scale + b[i])                   // Items<number>; a Float32Array too, on the CPU
```

A TypeScript `Float32Array` (`Int32Array`) is accepted where an
`Items<number>` is, for `Scalar` and `Simd` (its bytes are the GC heap's,
which moves: no other thread or the GPU reads them in place); `Auto` then
picks among those two. `Items` has `of(array)`, `copyTo(array)` and
`view()` (a `Float32Array` over a copy, in TypeScript).

### A reduction

```haxe
var energy = sum(n, i -> 0.5 * mass[i] * dot(vel[i].xyz, vel[i].xyz));
var lowest = min(n, i -> pos[i].y);
var bounds = reduce(n, Box.empty, i -> Box.point(pos[i].xyz), (a, b) -> a.union(b));   // combine: associative
```

```ts
const energy = sum(n, i => 0.5 * mass[i] * dot(vel[i].xyz, vel[i].xyz))
```

Deterministic: the items are cut into fixed chunks (1024), each reduced in
a fixed tree (4 lanes, then pairs), the chunks combined in order, so `Simd`
and `Jobs` give the same bits whatever the thread count. On the GPU a
reduction needs workgroup memory (below) and a read back; natively that is
a wait, in a browser WebGPU reads back asynchronously only, so
`sum(..., Gpu)` there is awaited in a coroutine (as a job is), and
`Auto` keeps reductions of CPU data on the CPU.

### A particles step

```haxe
@:structInit @:publicFields class Particle {
	var pos:Vec4;   // xyz, w: age
	var vel:Vec4;
}

final particles = new Items<Particle>(100_000);

// each fixed step:
function step(dt:Float) {
	each(particles.length, i -> {
		var q = particles[i];
		var vel = q.vel.xyz * drag - vec3(0, gravity * dt, 0);
		var pos = q.pos.xyz + vel * dt;
		if (pos.y < 0) {
			pos = vec3(pos.x, -pos.y, pos.z);
			vel = vec3(vel.x, -vel.y * bounce, vel.z);
		}
		particles[i] = {pos: vec4(pos, q.pos.w + dt), vel: vec4(vel, q.vel.w)};
	});
}
// drawn: particles.buffer(device), an instance vertex buffer (no copy when the step ran there)
```

```ts
type Particle = {pos: Vec4, vel: Vec4}
const particles = new Items<Particle>(100_000)
function step(dt: number) {
  each(particles.length, i => {
    const q = particles[i]
    let vel = q.vel.xyz.mul(drag).sub(vec3(0, gravity * dt, 0))
    let pos = q.pos.xyz.add(vel.mul(dt))
    if (pos.y < 0) { pos = vec3(pos.x, -pos.y, pos.z); vel = vec3(vel.x, -vel.y * bounce, vel.z) }
    particles[i] = {pos: vec4(pos, q.pos.w + dt), vel: vec4(vel, q.vel.w)}
  })
}
```

This is the prototype's kernel (its bench body omits the age).

### One cloth constraint iteration

Cloth's distance constraints, relaxed in parallel: each particle gathers
the corrections of its springs (Jacobi, over-relaxed) into the other
buffer. The writes are each particle's own, so the step is race-free on
every form and deterministic on the CPU's.

```haxe
@:structInit @:publicFields class Spring {
	var other:Int;
	var rest:Float;
}

final Relax = kernel(function(i:Int, p:{from:Items<Vec4>, to:Items<Vec4>, first:Items<Int>, springs:Items<Spring>, omega:Float}) {
	var x = p.from[i];                               // xyz, w: inverse mass
	var move = vec3(0, 0, 0);
	var end = p.first[i + 1];
	for (k in p.first[i]...end) {
		var s = p.springs[k], y = p.from[s.other];
		var d = x.xyz - y.xyz, len = length(d);
		var w = x.w + y.w;
		if (len > 1e-6 && w > 0) move += d * ((s.rest - len) / len * x.w / w);
	}
	var n = end - p.first[i];
	p.to[i] = vec4(x.xyz + move * (p.omega / max(1.0, n)), x.w);
});

for (_ in 0...iterations >> 1) {
	Relax.run(cloth.count, {from: a, to: b, first: first, springs: springs, omega: 1.5});
	Relax.run(cloth.count, {from: b, to: a, first: first, springs: springs, omega: 1.5});
}
```

A named kernel's parameters are typed once in its definition and checked
at each `run` (a missing or extra field, a wrong type: the call's error).
At run time a written `Items` passed twice (`from: a, to: a`) throws
(`Relax: to is also from`: pointer compares, before the dispatch). Graph
coloured Gauss-Seidel (writes at `p[s.other]`) needs writes at an index
the compiler cannot prove disjoint: not in v1 (an open question).

### Picked per call

The last argument (`On`), or none:

- `Scalar`: the body as plain Haxe, one item at a time (the reference;
  Eval and tests).
- `Simd`: 4 items a turn on this thread (every hxmc target has 128-bit
  SIMD, so this is the CPU's default form, not an extra).
- `Jobs`: `Simd`'s chunks on `helder.jobs.Parallel`'s threads and this one.
- `Gpu`: a compute dispatch on `Parallel.device` (the program's device,
  set by `App`/the renderer), recorded before the next frame's passes or,
  when the CPU reads a result, submitted and waited for.
- `Auto` (the default) picks, as decided:
  1. **`Gpu` from residency alone, never from timings:** when an `Items`
     the body writes was last written by a dispatch, or is drawn by the
     GPU, and the device has compute, the call moves to the GPU right away
     (its data then stays there); a `Float32Array` operand rules out `Jobs`
     and `Gpu`. `On.Gpu` stays the explicit, approximate choice.
  2. **otherwise `Simd` or `Jobs`, by the site's own timings:** its first
     run on one thread, one on the threads where they might win (one
     thread's estimate over twice their measured fixed cost), then the one
     predicted faster for the call's n (nanoseconds an item for each, kept
     by a timed run now and then), changed only for a 20% gain so that a
     site does not flip from frame to frame. Those two give the same bits,
     so a CPU result is deterministic whatever Auto picks.
  3. `HELDER_PARALLEL=scalar|simd|jobs|gpu` forces every call (tests,
     bisecting a difference), and `Parallel.log` prints each site's choice.

Measured on this machine (below), the 30-flop particle step is
bandwidth-bound and the CPU's threads beat the GT 710 at every size, but
drawing what the CPU simulated means an upload each frame that costs more
than the GPU's own step. So residency decides more than size: what the
GPU draws, the GPU should move, once it is there.

## One body, four forms

The definition is one handler for both languages (helder.compiler's
`Definition`, as `shader` and `job` are: `HaxeAdapter` for Haxe,
`typescript/lower/Definitions.hx` for TypeScript). It lowers the body to
the shader IR (`Lower.hx`; `TsAdapter`), makes it a compute stage
(`ShaderDefinition.compute`: `i` is `id.x`, or `id.y * stride + id.x`
past 4M items, D3D11's and WebGPU's 65535 workgroups a dimension; `if (i
>= count) return` first; the captured values one uniform block, the
`Items` storage bindings), and prints four forms:

| form | from | what changes |
|---|---|---|
| GPU | `Glsl/Wgsl/Msl/Hlsl.compute` as today | the block and bindings the kernel made; `ComputeShader` underneath |
| Simd | a range form of `Soft`'s lanes | loads at `i` contiguous (below); a range entry `(ctx, from, to)` |
| Jobs | the Simd form's range entry as `Parallel.run`'s callback | fixed chunks |
| Scalar | `Soft`'s reference form (`-D helder.soft.reference`) over the std430 bytes | always emitted, not only with the define |

**The Simd form** reuses Soft's emitter (its uniform analysis, masks,
selects, inlined helpers, `Lane` types), with two changes the prototype
measures:

- an access at the invocation's own index (`items[i]`, the common case)
  loads 4 consecutive elements with 128-bit loads and transposes them into
  lanes (4 rows of a Vec4: 4 loads, 8 shuffles), stores the same way, and
  skips the bounds check inside the range (`ParallelKernels.lanes`); other
  indices (`from[s.other]`) stay gathers with checks, as Soft's are;
- the entry runs a range: groups of 4, then the last few under a mask
  (Soft's entry is one call per 4 invocations).

A body made only of Vec4 values could also be run one item a register
(`ParallelKernels.vec`); it is measured, slower than lanes, and not
general: not emitted.

**What a body may do** (checked when the definition is handled, each
error at its line, in the shader handler's words plus these):

- Types: Int (32 bits), Float (32 bits in every form but Scalar, which
  computes in doubles and rounds where it stores), Bool, Vec2/3/4, Mat4,
  `@:structInit` structs of them, `Items<T>` of them. Not: String, Array,
  Dynamic, classes, enums, closures, `Null<T>`.
- No allocation, no exceptions, no I/O, no calls but to static functions
  that obey the same rules (inlined where they touch `Items`: GLSL takes no
  buffers as parameters) and ShaderMath's builtins (`Math.*` mapped, as
  shaders do). No recursion, no `switch` (yet), no do-while.
- Captures: a captured local must be final or never assigned after the
  capture; the value is read at the call. `kernel ... count is a var
  assigned at Main.hx:40; a body reads values, not variables`.
- Writes: an `Items` is written only at the invocation's own index (`i`);
  an `Items` the body writes is not read at another index. `Relax: to[j] =
  ...: a body writes at its own index (i) only`. With these, items are
  independent: the order and the threads change nothing.
- Limits from the back ends: 16 resources, 8 of them written (D3D11's UAVs;
  GL ES 3.1 guarantees 4 storage buffers), a uniform block of 16 KB.

Errors come out where the definition is: Haxe's macro positions,
TypeScript's lines through the frontend (as `job(f)`'s Sendable check
does). Tests: a `tests/parallel/reject` set as `tests/jobs/reject` is.

**What the shader compiler lacks for this:** TypeScript's Int (needed for
`i`, indices, counts; proposed: a `number` is Int where it comes from `i`,
`|0`, an Int field or integer literals in index position, else Float;
open question), `compute()` in TypeScript at all, storage reads in called
functions, Vec3 storage elements (helder loads HLSL's at std430 offsets
itself, so a 16-byte Vec3 can be lifted), workgroup memory and subgroups
(below), and Float atomics (not planned: reductions use workgroup memory).

**Precision and determinism.** Simd and Jobs give the same bits on every
CPU and target (F32x4 has no FMA; chunks are fixed; checked in the
prototype: `vec` and `jobs` against `lanes`, the same bits). Scalar differs
by rounding (doubles: within 4e-6 here). The GPU is close but not the same
(fused multiply-adds, its own `sqrt`, `sin`): within 3e-6 after 64 steps
here. A physics solver that must replay exactly (snapshots, rewinds) runs
on the CPU forms; `On.Gpu` is the faster, approximate choice, said so in
the docs.

## Buffers between the CPU and the GPU

`Items<T>` owns its std430 bytes outside the GC heap (malloc'ed, as
`SoftTexture` and `Chunks` are), so `Jobs`' threads read and write them in
safe regions, and keeps a GPU buffer (`BufferUsage.Storage`, also a vertex
buffer) made the first time a `Gpu` run or a draw needs it. It knows which
side is current (CPU, GPU, both) and moves a copy only when the other side
reads:

- a CPU form after a dispatch: the dispatch's results read back
  (`Device.readBuffer`, into the Items' own memory: one copy);
- a dispatch or draw after a CPU write: an upload of the written range
  (`writeBuffer` straight from the Items' memory: D3D11's backend now copies
  `Bytes` into a scratch block first because they may move, which off-heap
  memory never does: one copy less);
- `items[i]` on the CPU after a dispatch reads back first (a wait), which is
  what tests and pickers want, and what a frame loop should not do.

Per back end: Metal on Apple silicon shares memory (`MTLStorageModeShared`:
the Items' bytes are the buffer's `contents`, nothing copied, the sync a
command buffer's completion); D3D11 and GL copy over the bus (discrete
GPUs: no way around one copy; `D3D11_USAGE_DYNAMIC` with `MAP_WRITE_NO_OVERWRITE`
or GL's `glMapBufferRange` for streamed uploads); WebGPU copies
(`queue.writeBuffer`, `mapAsync` reads); the CPU back end's buffer is the
Items' memory itself. Dirty ranges, as `GpuParticles`' ring uploads only
what was emitted, are the next refinement.

## Workgroup memory and subgroups in compute()

Needed by reductions, prefix sums (compaction of live particles),
per-body sums in shape matching, tiled neighbour searches.

```haxe
final Sums = compute({
	size: [256],
	main: function(id:ComputeInput, p:{values:Storage<Float>, out:RWStorage<Float>, count:Count}, w:{part:Workgroup<Float>}) {
		var v = id.x < p.count.n ? p.values[id.x] : 0.0;
		v = subgroupAdd(v);                                    // the subgroup's sum, in each of its lanes
		if (id.subgroupLane == 0) w.part[id.subgroupIndex] = v;
		barrier();                                             // the workgroup's writes seen by all of it
		if (id.localIndex == 0) {
			var s = 0.0;
			for (k in 0...id.subgroups) s += w.part[k];
			p.out[id.groupX] = s;
		}
	}
});
```

- Workgroup memory is a third parameter, an object of `Workgroup<T>`
  fields (T as storage's), each as long as the workgroup by default,
  `@:length(512)` another (as storage textures' `@:format`). Its total is
  checked against 16 KB (WebGPU's and GL ES 3.1's floor; D3D11 and Metal
  have 32 KB).
- `barrier()`: the workgroup waits, its workgroup memory's writes seen
  (WGSL `workgroupBarrier`, MSL `threadgroup_barrier(mem_flags::mem_threadgroup)`,
  HLSL `GroupMemoryBarrierWithGroupSync`, GLSL `barrier(); memoryBarrierShared()`).
  Only at the top of `main`'s body, outside ifs and loops on lane values
  (the uniform control flow WGSL requires; checked).
- Subgroups: `subgroupAdd/Min/Max(x)`, `subgroupBroadcast(x, lane)`,
  `subgroupShuffle(x, lane)`, `subgroupAll/Any(b)`, and `ComputeInput`'s
  `subgroupLane`, `subgroupSize`, `subgroupIndex`, `subgroups`. A new
  `Feature.Subgroups`. Where a device has none, the stage is compiled a
  second time with the subgroup operations made of workgroup memory and
  barriers (a subgroup of 4: same results, slower), so a stage runs
  everywhere compute does; their use is held to the same top-level rule.

| | workgroup memory, barrier | subgroups |
|---|---|---|
| WebGPU (WGSL) | `var<workgroup>`, 16 KB | the `subgroups` feature (Chrome, requested at device creation); else emulated |
| Metal (MSL) | `threadgroup`, 32 KB | `simd_sum`, `simd_shuffle`, ... (Apple GPUs: 32 wide) |
| D3D11 (HLSL cs_5_0) | `groupshared`, 32 KB | none (wave intrinsics are SM 6.0, D3D12's DXIL): emulated |
| GL ES 3.1 / GL on Mesa (GLSL) | `shared`, 16 KB | `GL_KHR_shader_subgroup` where the driver lists it (Mesa does for llvmpipe and others; Android varies); else emulated |
| Vulkan | no Vulkan back end (roadmap: later) | |
| CPU back end (Soft) | a block per workgroup; the body cut at its barriers into phases, each run over the whole workgroup before the next, the locals live across a barrier kept per invocation | the 4 lanes of a call are a subgroup of 4: exact and cheap |
| WebGL2 | no compute | |

The kernel forms use these too: `sum` on the GPU is the stage above plus
a pass over the groups' sums; on the CPU forms a reduction needs neither.

## Measured

`bun run test bench parallel` (`tests/bench/ParallelBench.hx`), the
prototype's kernel (`v' = v·drag − g·dt; p' = p + v'·dt`, bounced at y =
0; 32 bytes a particle, read and written), µs a step, the least of its runs
(a run: steps enough for 2 ms; on the GPU each run one frame, the least of
15-40).

- **today**: `Integrate.main` over an `Array<Particle>` (examples/fountain's
  CPU fallback), then `store`d into the buffer's bytes;
- **scalar**, **vec**, **lanes**: `ParallelKernels` over the bytes, one
  thread; **jobs**: lanes in `(threads + 1) × 4` chunks on `Parallel.run`;
- **gpu**: one dispatch in a frame, then a 32-byte `readBuffer` (the wait);
  **gpu x10**: ten dispatches a frame, a tenth; **sync**: an empty frame
  and the same read (the floor under gpu); **upload**: the whole buffer
  written, then sync; **+read**: gpu then the whole buffer read back;
  **+write+read**: upload, gpu, read back.

Checked first (1003 particles, 64 steps, against lanes): vec and jobs the
same bits; scalar and today within 4e-6; the GPU (D3D11) within 3e-6.

The machine: an AMD Ryzen 5 3600 (6 cores, 12 threads: `Parallel.run`
on 11 helpers and the caller), DDR4, an NVIDIA GT 710 (Kepler GK208, 64-bit
DDR3, about 14 GB/s, PCIe 2.0 x8) on D3D11 at feature level 11_0. The box was
shared with other agents' lanes throughout (WSL's load average 7-19): each
table is the least of each cell over three runs (two on the GPU), which
removes most of the contention but not all of it; the `jobs` column suffers
most (its threads are the ones preempted), Linux's worst (load 17-19 there).

**Windows, the CPU forms** (µs a step):

| N | today | scalar | vec | lanes | jobs |
|---:|---:|---:|---:|---:|---:|
| 1,000 | 26.3 | 3.8 | 2.8 | 1.8 | 3.7 |
| 3,000 | 77.4 | 10.6 | 8.4 | 5.2 | 4.9 |
| 10,000 | 259 | 35.2 | 28.2 | 17.6 | 7.8 |
| 30,000 | 778 | 102 | 84.7 | 52.9 | 16.7 |
| 100,000 | 2698 | 342 | 282 | 176 | 64.1 |
| 300,000 | 8939 | 1021 | 845 | 524 | 152 |
| 1,000,000 | 29580 | 3840 | 3479 | 3114 | 804 |

**Windows, the GPU** (GT 710, D3D11; µs):

| N | gpu | gpu x10 | sync | upload | gpu +read | gpu +write+read |
|---:|---:|---:|---:|---:|---:|---:|
| 1,000 | 83.9 | 15.4 | 44.3 | 106 | 101 | 129 |
| 3,000 | 88.7 | 19.7 | 43.4 | 120 | 122 | 173 |
| 10,000 | 101 | 38.2 | 43.6 | 224 | 219 | 377 |
| 30,000 | 268 | 183 | 42.4 | 466 | 601 | 1099 |
| 100,000 | 648 | 611 | 42.4 | 1914 | 1846 | 3786 |
| 300,000 | 1865 | 1905 | 43.6 | 7456 | 5462 | 13006 |
| 1,000,000 | 6229 | 6340 | 43.6 | 25014 | 18642 | 42458 |

**Windows, today's CPU back end** (`-D helder.soft`: the same `compute()`
dispatched on `Backend.Soft`, `soft_cs` on one thread; `PARALLEL_SOFT=1`),
µs a step (gpu x10's column; the same bits as lanes):

| N | 1,000 | 3,000 | 10,000 | 30,000 | 100,000 | 300,000 | 1,000,000 |
|---|---:|---:|---:|---:|---:|---:|---:|
| soft_cs | 64.7 | 194 | 529 | 1999 | 6688 | 21324 | 73354 |

**WSL Linux (Ubuntu 26.04, the same CPU), the CPU forms** (µs):

| N | today | scalar | vec | lanes | jobs |
|---:|---:|---:|---:|---:|---:|
| 1,000 | 31.2 | 4.9 | 2.8 | 1.7 | 18.2 |
| 3,000 | 113 | 14.6 | 10.4 | 6.4 | 20.5 |
| 10,000 | 248 | 37.4 | 34.2 | 21.4 | 24.1 |
| 30,000 | 1078 | 141 | 102 | 68.1 | 39.3 |
| 100,000 | 3961 | 464 | 329 | 211 | 90.1 |
| 300,000 | 11581 | 1170 | 1147 | 655 | 207 |
| 1,000,000 | 42120 | 5512 | 4441 | 4160 | 1883 |

What they say:

- **lanes over scalar**: 2.1x at 1,000 (where it all stays in L1/L2),
  1.9x to 300,000, 1.2x at 1M, where 32 MB read and written a step is the
  memory's speed, not the code's. vec (a Vec4 a register) sits between
  them: the transpose costs less than it saves.
- **today's CPU fallback** (`main` over an `Array` of struct objects, then
  `store`d) is 7-8x slower than scalar over the bytes and 10-15x slower
  than lanes, and today's CPU
  back end's compute (`soft_cs`: lane-by-lane gathers with a bounds check
  each, one call per 4 invocations) 36x slower than lanes at 1,000 and 24x
  at 1M, slower even than the Array path. The range form's contiguous
  loads are most of the win.
- **jobs over lanes**: the crossover is at about **3,000 particles**
  (4.9 against 5.2 µs: about 5 µs of one thread's work), on Windows; 3x at
  30,000, 3.4x at 300,000, 3.9x at 1M (11 helpers: bandwidth again).
  Its fixed cost is 2-3 µs a run (1,000: 3.7 against 1.8) while its threads
  spin. On the loaded Linux runs the crossover moved to between 10,000
  and 30,000 and the fixed cost to 16 µs (preempted helpers: a `Parallel.run` waits for
  the last chunk).
- **The GPU never beats the CPU here for this kernel.** Resident and
  throughput-bound (gpu x10), the GT 710 takes 6.3 ms at 1M (64 MB a step:
  about 10 GB/s, its memory's speed) against jobs' 0.8 ms and one thread's
  3.1 ms; at 1,000, 15 µs a dispatch against 1.8. A step that waits for its
  result (gpu) adds the 43 µs floor of a frame and a read back (sync).
- **But drawing changes it**: particles the GPU draws have to be uploaded
  after a CPU step, and the upload (`writeBuffer`, D3D11's
  `UpdateSubresource` of the whole buffer: 1.3 GB/s here) costs more than
  the GPU's own step at every size: at 1M, jobs + upload is 0.8 + 25.0 ms
  against the GPU's 6.2 ms; at 10,000, 7.8 + 180 µs against 58 µs; at
  1,000, 3.7 + 62 against 40 µs (upload and gpu less the sync floor, which
  a frame pays anyway). Reading the GPU's results back costs as much
  (1M: 12.4 ms more). So the crossovers this machine gives Auto are:
  **CPU data, CPU reader: lanes below about 3,000 items, jobs above, never
  the GPU; GPU reader (a draw): the GPU from the first item**, its upload
  avoided. A faster GPU moves the first, not the second.

## Plan

Each a PR that ships on its own, with its tests; each lands on main
when CI is no worse than main's.

1. **`Items<T>` and the CPU forms of `each`/`map`** (Haxe; built: also
   the reductions' and `kernel`'s CPU forms). `helder.parallel`:
   `Items<T>` (off-heap std430, the codecs `StorageSlot` has), the `each`
   and `map` definitions (Haxe adapter), Soft's range form with contiguous
   loads at `i`, the scalar reference form, `Jobs` over `Parallel.run` with
   fixed chunks, `On` (no `Gpu` yet: it throws). Tests: a `parallel` lane
   (each form against Scalar on random bodies, as SoftShaderCheck does;
   the bits of Simd and Jobs equal for 1-12 threads), `tests/parallel/reject`
   (captures, writes at another index, allocation, types), and `bench
   parallel` kept. Also: the Simd form for `soft_cs` itself where it reads
   at `id.x` (the CPU back end's compute gets faster for free).
2. **`Gpu` and `Auto`**, residency. `Items.buffer(device)`, `Parallel.device`,
   the dispatch outside a frame (a small `helder.gfx` addition: a compute
   pass recorded before the next frame's, or submitted and waited for),
   the readback and upload rules, the per-site calibration and
   `HELDER_PARALLEL`. Tests: `gfx-compute` and `gfx-compute-web` run the
   parallel lane's bodies on the GPU against Simd (within a tolerance), and
   a frame with a dispatch allocates nothing.
3. **Particles** (`helder.scene`): `Particles`, a simulated system beside
   `GpuParticles` (emission into a ring, forces, a floor and spheres to
   collide with, ages and deaths), stepped by `each`, drawn from the Items'
   buffer as instances. Example: `examples/particles`' sibling, 100k on the
   GPU, 10k on WebGL2 (CPU forms, uploaded). Tests: a step's numbers the
   same on every target on the CPU forms; the frame against a golden.
4. **Workgroup memory, barriers and subgroups in `compute()`**, per the
   table above, and `sum`/`min`/`max`/`reduce` on every form (the GPU's
   through them). Tests: ComputeCheck gains a workgroup reduction and a
   subgroup scan on each back end (D3D11 emulated), ShaderCheck the text,
   SoftShaderCheck the phases.
5. **TypeScript**: `helder/parallel` (the TS adapter's Int, `each`, `map`,
   `sum`, `kernel`, `Items<T>` from a TS object type, `Float32Array`
   operands), and `compute()` in TypeScript with it. Tests: the typescript
   lane's programs, their rejections.
6. **Cloth** (`helder.physics`): a `Cloth` of a grid or a mesh (springs from
   its edges, bending from its diagonals), Jacobi relaxation as above,
   pinned points, collisions with physics' spheres, capsules and planes,
   drawn as a mesh whose positions are the Items' buffer. Example: a flag
   and a curtain. Tests: energy falls, a pinned cloth hangs to the same
   numbers on every target.
7. **Soft bodies**: tetrahedral XPBD volumes and shape matching (its centre
   of mass and rotation a per-body reduction: workgroup memory), coupled to
   rigid bodies through contacts. The roadmap's "Later: soft bodies" moves
   here.

## Risks and open questions

Risks:

- **The GPU form is not deterministic**, and a fast GPU path will tempt
  physics into it. The rule (CPU forms for anything replayed) has to be
  explicit, and `Auto` must not move a deterministic solver to the GPU
  behind its back: a solver says `deterministic` and Auto keeps it on the
  CPU.
- **Small GPUs.** This machine's GT 710 loses to its own CPU at every size
  for a bandwidth-bound kernel; Auto's calibration is what makes "picked per
  call" right on such machines, and calibration has to be cheap and
  stable (a site that flips between forms frame to frame would stutter).
- **Soft's emitter is the Simd form's base**: changing it touches the CPU
  back end's 89 bit-exact shaders; the range form must stay a separate
  entry with SoftShaderCheck guarding both.
- The bench box is shared: a full run taken while other agents ran was up
  to 2x slower, and the tables are the least of three runs under load (WSL
  at 7-19), not quiet runs: the jobs column and Linux are pessimistic. A
  rerun on a quiet machine (and on an Apple GPU, which shares memory and
  has no upload) should precede Auto's thresholds.
- One full GPU run stalled at its last measurement (1M, upload + step +
  read back, a 32 MB `UpdateSubresource` each run) and was killed after ten
  minutes; run alone the same measurement takes 56 ms, and the later full
  runs passed. Not understood; watch it in phase 2's D3D11 upload path.

The open questions, decided (November 2026):

1. Both `each(n, i -> ...)` and `kernel(...)`; `each`, `map` and the
   reductions are anonymous kernels over the same compiler.
2. `Float` is 32 bits inside a body (Scalar computes in doubles and rounds
   where it stores).
3. TypeScript's Int is inferred (from `i`, `| 0`, Int fields, integer
   literals in index position): no new type.
4. Cloth uses Jacobi only; graph-coloured Gauss-Seidel is out of scope.
5. Auto picks `Gpu` only from residency, never from timings (Picked per
   call, above).

Also decided: `Items` owns its memory outside the heap, with `dispose()`
and a finaliser as a safety net (said in debug builds).

The questions as they were asked:

1. **One choice or two?** `each(n, f)` at the call (captures, no names)
   *and* `kernel(...)` (named, typed parameters). Both, as proposed, or
   only `kernel` at first (simpler checking, one form of parameters)?
2. **`Float` is 32 bits in a body.** Every form but Scalar rounds to
   float32, as storage already does. Fine, or should a body's Float be
   double on the CPU forms (twice the lanes' cost, no GPU equivalent)?
3. **TypeScript's Int**: infer it (from `i`, `| 0`, Int fields), or an
   explicit `int` type from `helder/gfx`? The inference keeps call sites
   annotation-free but makes `/` subtle.
4. **Cloth's solver**: Jacobi (race-free, every form, as above) first, and
   graph-coloured Gauss-Seidel (faster convergence; writes at other indices,
   which the compiler cannot prove safe) later or never?
5. **Auto's default for data drawn by the GPU**: move it to the GPU as soon
   as a dispatch is possible (fewer uploads), or only when calibration says
   so?
