# helder.gfx

A portable GPU layer for hxmc in pure Haxe (`helder.gfx`): integer handles,
immutable pipelines, back ends over GL through EGL (Linux, Android: GLES 3.1,
or 3.0 where the driver has no more, on the activity's window), Metal (macOS, iOS),
Direct3D 11 (Windows), WebGPU and WebGL2 (the browser). See
`examples/triangle/Triangle.hx` (the least a program needs), `examples/cube/Cube.hx`
(textures, depth, uniforms, blending, indices), `examples/fountain/Fountain.hx`
(a helder.parallel body: a compute dispatch, or SIMD lanes without compute), `examples/instances/Instances.hx`
(instanced draws), `examples/cube/Targets.hx` (render targets),
`examples/mips/Mips.hx` (mip maps) and `examples/formats/Formats.hx` (texture formats).

## API

Resources are made up front from descriptors (allocating there is fine);
a frame records passes through the device's one `Encoder` and allocates
nothing in the layer.

```haxe
var device = Device.create(window.surface);          // or Surface.headless(w, h)
var vb = device.createBuffer({size: bytes.length, usage: Vertex, data: bytes});
var ib = device.createBuffer({size: indices.length, usage: Index, data: indices});
device.writeBuffer(vb, 0, newBytes);                  // later updates
var tex = device.createTexture({width: 64, height: 64, format: RGBA8, data: texels});
device.writeTexture(tex, texels);                     // all of it, or a region: (tex, bytes, x, y, w, h[, offset, level])
device.destroyTexture(tex);                           // (and destroyBuffer)
var smp = device.createSampler({filter: Linear, wrap: Repeat});
var pipeline = device.createPipeline(CubeShader.pipeline({
	cull: Back, depthCompare: Less, depthWrite: true, blend: Opaque // or Alpha, Additive (src + dst), Premultiplied, Multiply (dst * src: a tint)
}));

var enc = device.beginFrame();                        // null: no frame now (a hidden window)
enc.beginPass({colors: [{load: Clear, clear: new Vec4(0.1, 0.1, 0.12, 1)}], depth: {load: Clear}});
enc.setPipeline(pipeline);
CubeShader.params.cam.write({mvp: mvp, model: model}, bytes); // a uniform block's std140 bytes
enc.setUniforms(0, bytes);                            // its slot: into the frame's uniform ring
enc.setTexture(1, tex, smp);
enc.setVertexBuffer(0, vb);
enc.setIndexBuffer(ib, UInt16);                       // or UInt32
enc.drawIndexed(36);                                  // or draw(vertices)
enc.endPass();
device.endFrame();                                    // submit and present
```

Slots: a shader's uniform blocks and textures (the fields of each stage's
object of parameters, its second parameter) are numbered 0, 1, ... in
order of appearance, the vertex stage's first; the generated `uniforms`
and `textures` lists give each one's `binding`, as do `params.<field>`
(`.block.binding` of a writer, `.binding` of a texture's slot). `setUniforms` copies the block into the frame's uniform
ring (`Encoder.UNIFORM_RING` bytes a frame, 256-byte aligned blocks; one
ring per frame in flight; Metal: `setVertexBytes`, at most 4 KB a block).
The device has a depth buffer of the target's size; `PassDesc.depth`
clears or keeps it. `Device.readPixels` reads the frame back (tests,
screenshots; on WebGPU, `readPixels` in `imports.mjs`, asynchronously).

Antialiasing: `Device.create(window.surface, {antialias: true})`
multisamples a window's frames, 4 samples a pixel (Metal: a multisampled
colour and depth texture resolved into the drawable at each pass's end;
GL: an EGL config with 4 samples, when there is one; D3D11: a
multisampled colour and depth texture resolved into the back buffer before
`Present`, when the device has 4 samples; in the browser the page's
`antialias` run option decides when it is set, else the device's option:
WebGPU a multisampled colour and depth texture, WebGL2 the context's
antialias). Headless surfaces stay single-sampled; `readPixels` reads the
frame resolved. helder.ui's `<Surface>` (UiWindow) asks for it by default
(`antialias={false}`: one sample), and so does a `<Scene>`'s box.

Multisampled render targets: a render target or depth texture made with
`samples: 4` (RGBA8, RGBA8Srgb, RGBA16F or a depth format, one level) is
drawn into by pipelines made with `PipelineDesc.samples = 4` and never
sampled; the pass's colour is resolved at its end into
`ColorTarget.resolve`, a single-sampled render target of its size and
format, which is then sampled as usual (GL and WebGL2: a multisampled
renderbuffer blitted into the texture; Metal: a 2D multisample texture and
its resolve texture; D3D11: `ResolveSubresource`; WebGPU: the attachment's
`resolveTarget`). `examples/cube/Targets.hx` with `samples` 4 is the
`msaa` frame of the gfx lanes (tests/gfx/msaa.png: GL, D3D11 under Wine,
WebGPU and WebGL2 in Chromium; Metal on CI's macOS):

```haxe
var multi = device.createTexture({width: w, height: h, renderTarget: true, samples: 4});
var depth = device.createTexture({width: w, height: h, format: Depth32F, samples: 4});
var color = device.createTexture({width: w, height: h, renderTarget: true});
enc.beginPass({colors: [{load: Clear, texture: multi, resolve: color}], depth: {load: Clear, texture: depth}});
```

Instancing: a vertex buffer slot whose layout has `step: Instance` advances
once per instance instead of once per vertex (GL's and WebGL2's attribute
divisor 1, D3D11's per-instance input slots, Metal's per-instance step
function, WebGPU's `stepMode: 'instance'`); `draw` and `drawIndexed` take
the instance count, and `drawIndexed`'s base vertex moves the per-vertex
buffers only. A shader reads both kinds of attributes from its one input
struct; the pipeline's layout says which buffer each location comes from:

```haxe
var d = InstancesShader.pipeline();
d.layout = [
	{stride: 8, attributes: [{location: 0, format: Float2, offset: 0}]},  // the shape's corners
	{stride: 28, step: Instance, attributes: [                             // each instance's
		{location: 1, format: Float2, offset: 0}, {location: 2, format: Float1, offset: 8},
		{location: 3, format: Float1, offset: 12}, {location: 4, format: Float3, offset: 16}
	]}
];
var pipeline = device.createPipeline(d);
...
enc.setVertexBuffer(0, shapes);
enc.setVertexBuffer(1, instances, first * 28);       // the instances from first
enc.drawIndexed(6, count);                            // count instances of the quad
```

Textures: `TextureFormat` has the formats every back end has: `RGBA8`,
`RGBA8Srgb` (decoded when sampled, encoded when rendered to), `R8`, `RG8`,
`RGBA16F` (half floats), `R32F`, `RGBA32F` (floats) and the depth formats
`Depth16` and `Depth32F`; data is `format.texelSize` bytes a texel. R32F,
RGBA32F and depth textures are not filterable everywhere: they are read
through a sampler of `Nearest` filters and have no generated mip levels. `Device.textureBytes`
counts the bytes of the textures alive (their levels and samples, as
their formats store them): the GPU memory a scene's textures take.

Mip maps: `mipLevels` levels (0: all of them, down to 1x1), each written
with `writeTexture`'s level or generated from the first (GL's
`glGenerateMipmap`, D3D11's `GenerateMips`, Metal's blit, a small pass on
WebGPU; outside a pass); a sampler's `mipFilter` reads between them
(`Linear` with `filter: Linear`: trilinear; none: the first level only):

```haxe
var checks = device.createTexture({width: 256, height: 256, mipLevels: 0, data: texels});
device.generateMips(checks);                          // or writeTexture(t, bytes, 0, 0, -1, -1, 0, level)
var trilinear = device.createSampler({filter: Linear, mipFilter: Linear});
```

Render targets: a texture made with `renderTarget: true` (and every depth
texture) is a pass's colour target (`ColorTarget.texture`) or depth target
(`DepthTarget.texture`, of the same size; a pass into a texture has a depth
buffer only when it names one), filled by passes (not data), then sampled
like any texture (after `endPass`). Metal and WebGPU make a pipeline for
its targets' formats: `PipelineDesc.colorFormat` and `depthFormat` (by
default the frame's colour and the device's depth buffer):

```haxe
var color = device.createTexture({width: 128, height: 128, renderTarget: true});
var depth = device.createTexture({width: 128, height: 128, format: Depth32F});
var d = SceneShader.pipeline({depthCompare: Less, depthWrite: true});
d.colorFormat = RGBA8;
d.depthFormat = Depth32F;
var offscreen = device.createPipeline(d);
...
enc.beginPass({colors: [{load: Clear, texture: color}], depth: {load: Clear, texture: depth}});
enc.setPipeline(offscreen);                           // ... draw into it
enc.endPass();
enc.beginPass(framePass);
enc.setTexture(1, color, sampler);                    // ... and sample it
```

Cubes and arrays: `cube: true` makes a cube texture (six square layers,
its faces +x, -x, +y, -y, +z, -z), `layers: n` a 2D array; data fills
every layer one after another, `writeTexture`'s `layer` one of them, a
pass draws into one (`ColorTarget.layer`, its first level). Shaders take
them as `TextureCube` (`sample(t, dir)`: along a direction, as every API
reads a cube's faces) and `Texture2DArray` (`sample(t, uv, layer)`):
GLSL's `samplerCube` and `sampler2DArray`, WGSL's `texture_cube` and
`texture_2d_array`, MSL's `texturecube` and `texture2d_array`, HLSL's
`TextureCube` and `Texture2DArray`. A face drawn into has its rows top to
bottom as a 2D target's, so a camera drawing a face sees it mirrored (a
cube is seen from inside): helder.scene's reflection probes turn their
winding. tests/gfx's `layers` frame checks every face and layer, uploaded
and drawn into, on each back end:

```haxe
var sky = device.createTexture({width: 64, height: 64, cube: true, format: RGBA16F, renderTarget: true, mipLevels: 0});
enc.beginPass({colors: [{load: Clear, texture: sky, layer: 2}]});   // the +y face
// ... fragment: function(i:Varyings, p:{sky:TextureCube}) return sample(p.sky, i.dir)
```

Shared textures: a render target another process samples without a copy
(helder.story's native preview host draws each screen into one, the
studio composites it). `Device.sharing` says how: `"iosurface"` (Metal: an
IOSurface found by its id), `"dxgi"` (Direct3D 11: a texture with a keyed
mutex, by its DXGI shared handle; a frame holds the mutex from the first
draw that samples it, or from beginFrame into it, to endFrame), `"dmabuf"`
(GL: exported with EGL_MESA_image_dma_buf_export, its descriptor taken by
the other process with pidfd_getfd and imported with
EGL_EXT_image_dma_buf_import), or null (WebGPU, WebGL2, Android, an EGL
without those: llvmpipe without udmabuf; `HELDER_NO_DMABUF=1`). A frame
into a shared texture waits for the GPU at `endFrame`, so its pixels are
complete when the other process is told; the producer does not draw into a
texture the consumer is sampling (helder.story keeps buffers for that).
`tests/gfx/SharedTextureCheck.hx` is the gfx-shared lane's check, two processes:

```haxe
var s = device.createShared(w, h);                   // null: no sharing here
device.frameInto(s.texture);                          // the next frames into it (null: the surface again)
var enc = device.beginFrame(); ... device.endFrame(); // complete: give s.handle to the other process
var t = other.openShared(handle, w, h);               // there: a texture to sample (destroyTexture when done)
```

Conventions, the same on every back end: clip space y up and z from 0
(near) to w (far), counter-clockwise front faces; the fragment position in
pixels from the target's top left; a texture's first row is its top
(v = 0), a render target's too (GL renders into it upside down, its front
faces clockwise, so that it reads alike); `readPixels` rows top to bottom. `Mat4.perspective` and
`Mat4.orthographic` project into that clip space. The GLSL a shader definition
emits makes GL match (its clip z and `gl_FragCoord.y` differ).

## Render thread

Every call after `Device.create` is recorded (`Commands`: flat words in
memory outside the collector's heap, each command its op, its size and its
arguments; uploads' bytes copied in, so a program reuses its arrays at
once) and run in order on the back end (`Replay`). Handles are the
device's own, given on the program's thread; the back end's objects are
made where it runs, a table mapping one to the other. Synchronously (the
default: headless surfaces, tests, goldens, games), it runs inline at each
call that may throw and at each pass's end, so errors are thrown where
they were and golden images exercise the recording.

`Device.create(surface, {thread: true})` (helder.ui's windows and their
`<Scene>`s) runs it on the render thread (`RenderThread`, one a process),
which owns the context (Metal's queue and drawables, GL's EGL context made
current there, D3D11's immediate context and swap chain) and presents:

- the program hands over what it recorded at a pass's end (when the thread
  is free and there are 16 KB of it) and at `endFrame`, and records the
  next into a second buffer; one buffer runs at a time;
- it waits for the thread at `beginFrame` (the last frame presented: one
  frame at most on its way; the frame's size and drawable known), at calls
  that answer (`readPixels`, `readBuffer`, `createShader`,
  `createPipeline`, `createShared`: their errors thrown there; what threw
  in a command without an answer is thrown at the next wait), at `settle`
  and at `dispose` (drained, the context let go; the last device ends the
  thread). `queryResult` answers from the set's answers taken at a frame's
  first question;
- `settle()` waits for the last frame's present. helder.ui's loop settles
  before it takes the next events, so the thread adds no frame of latency:
  a `<Scene>` or game covering the window is submitted and presented in the
  turn it was drawn. A program that does not settle draws its next frame
  while this one presents (more throughput, its input a frame older);
- the thread is a GC thread: its waits (for work, nextDrawable, the swap,
  `Present`, the GPU) are in safe regions (sys.thread's locks, EGL's and
  objc's calls), so collections wait only for its stretches of encoding
  between them, not for vsync;
- Apple: autorelease pools of its own around what runs outside a frame;
  Surface.onPresent (a macOS window shown at its first frame) called on
  the program's thread; GL: the context let go by the creating thread
  (X11's display opened with `XInitThreads`: Mesa's software path presents
  through Xlib); Android: `Surface.lost` run on the thread, waited for.

`HELDER_RENDER_THREAD=0` turns it off, `=1` on for every window's device.
`tests/ui/RenderThreadCheck.hx` (ui-draw) draws random trees on the thread
and synchronously in one window and compares every frame pixel for pixel,
and hammers creation, uploads, read-backs, destruction and resizes while
frames are on their way (nothing left in the back end's tables), on Metal
and Mesa. Frame times (examples/orbits with `--time`), with 4 ms of the
program's own work after each frame:

| | synchronous | render thread |
| --- | ---: | ---: |
| 400 rows scrolled, llvmpipe (not paced) | 13.1 ms | 10.8 ms |
| Orbits, llvmpipe (not paced) | 9.7 ms | 6.3 ms |

Without such work they are the same, as is the time from a frame's start
to its present. Paced by a 60 Hz display (Metal, five runs each way, with
and without the work), frames and the start-to-present time are the same
either way: 16.7 ms a frame, the present 16.6 ms after the start (12.6
with the work, which then fits in the frame's wait for the drawable). Not yet: the web (step
4b's worker), scrolling and animations on the thread, and the back ends'
own code is GC code (a kernel's discipline would let collections skip it).

## Shaders

Shaders are Haxe (`helder.gfx.shader`): a definition, `shader({vertex,
fragment})` (src/helder/compiler/README.md), of functions on helder.math's
types (`Vec2`, `Vec3`, `Vec4`, `Mat4`, swizzles, operators:
/src/helder/math/README.md) and `ShaderMath`'s builtins, structs of them (`@:structInit` classes, typedefs of anonymous
structures) and `Texture2D` parameters (`sample(t, uv)`: in the fragment
stage at the mip level the fragment's footprint needs, in the vertex stage
the first; `sampleLevel(t, uv, level)` at a given one; `discard()`, a
statement of the fragment stage, drops the fragment: alpha testing). The
stages call any static or module-level function of those values. They run
on the CPU as they are; the definition compiles them, when the program is
built, to GLSL ES 3.00, WGSL, MSL and HLSL (the target's only), with the
vertex layout, the uniform blocks' layout, the slots and the CPU writers:

```haxe
@:structInit @:publicFields class Vertex { var pos:Vec2; var uv:Vec2; }
@:structInit @:publicFields class Varyings { var pos:Vec4; var uv:Vec2; }
@:structInit @:publicFields class Tint { var color:Vec4; }

final SpriteShader = shader({
	vertex: function(v:Vertex):Varyings
		return {pos: position(vec4(v.pos, 0, 1)), uv: v.uv},  // position: the clip-space position
	fragment: function(i:Varyings, p:{tint:Tint, image:Texture2D}):Vec4
		return sample(p.image, i.uv) * p.tint.color   // slots: tint 0, image 1
});

var pipeline = device.createPipeline(SpriteShader.pipeline({blend: Alpha}));
var bytes = SpriteShader.vertexBytes([{pos: vec2(0, 0.6), uv: vec2(0.5, 0)}, ...]);
SpriteShader.params.tint.write({color: vec4(1)}, uniformBytes);   // std140
enc.setTexture(SpriteShader.params.image.binding, texture, sampler);
```

Constants: a static or module-level `final` of literals, or of the
constructors and builtins over literals (`final GLOW = vec3(0.2, 0.3,
0.9)`, `mat4(1)`), is printed where shader code reads it. Arrays: a
uniform block's field of Vec4s or Mat4s with its length (std140 pads the
other types to 16 bytes: pack them into Vec4s), read by an index known or
not when compiling; the writer takes the elements given, zeros after:

```haxe
@:structInit @:publicFields class Lights {
	var count:Float;
	@:length(8) var positions:Array<Vec4>;   // xyz, w: the range
	@:length(8) var colors:Array<Vec4>;
}
// for (k in 0...8) if (k < Std.int(p.lights.count)) ... p.lights.positions[k] ...
```

(`tests/gfx/PaletteShader.hx` has both, and `atan2(y, x)`, GLSL's `atan`
of two.)

A stage takes its input and, optionally, one object of parameters (an
anonymous structure, written out or a typedef): its fields, in order, are
the stage's uniform blocks and textures, read as `p.tint`; a field both
stages name is one resource. `params` has a field for each: a uniform
block's writer (`UniformWriter`), a texture's slot (`TextureSlot`).

A shader written once with parts to replace is a slot object,
`slots({vertex, fragment, options, <slot>: ...})` (`Slots`): its stages
take the object as a third parameter, `m.options.<name>` an option and
`m.<slot>(s, p)` a slot (a function with a default; its own parameters
the stage's of the same names, the others joining them). `variant(options)`
is a shader compiled at build time with the options folded (an `if` on
one takes its branch, a loop over constants is unrolled), the slots
inlined and what it never reads of the optional fields (`@:optional`:
vertex attributes, varyings, parameters) dropped; `gpuVariant(options)`
the same without its CPU stages (`vertex` and `fragment` null: a shader
only ever drawn, none of their code linked); `with({<slot>: ...})`
replaces slots. helder.scene's standard material is one (`pbr`).

`uniform(value)` (a module-level final) is a value the CPU sets
(`time.value = t`) and any stage reads as `time.value`: a shader that
reads uniforms gets a block of them, `Uniforms` (a field each, in the
order first read; `params.uniforms`), `uniformBytes()` the block with
their values now, `bind(encoder)` binding it at `uniformBinding`.

In TypeScript, `import {shader, position, vec4, ...} from "helder/gfx"`: the
same definition with the operators as methods (`a.mul(b)`) and type
aliases as the structs, compiled to the same text (helder.typescript's
README): `fragment: (i, p: {tint: Tint, image: Texture2D}) => ...`, its
`params` typed by `Params<P>` (a `TextureSlot` for a `Texture2D` field,
a `UniformWriter<T>` for the others).

`src/helder/gfx/shader/Shader.hx` lists the generated members; the tests are
`tests/gfx/ShaderCheck.hx` (`bun run test gfx-shader`) and GfxCheck and WebCheck,
the examples' frames against `tests/gfx/<scene>.png` (triangle, cube,
instances, targets, mips, formats) on each back end (`bun run test gfx`, `bun run test gfx-web`).

## Compute

A tier above the render stages every back end has: `Device.has(Compute)`
(and `StorageTextures`, `Indirect`, the same devices today) says whether
the device runs compute stages. WebGPU, Metal, Direct3D 11 at feature
level 11_0 (`cs_5_0`), GL ES 3.1 (Android's native floor) and the
[CPU back end](#on-the-cpu) all run compute. The CPU back end runs Haxe
compute stages four invocations at a time and supports storage buffers
and textures. On WebGL2 and GL ES 3.0, use a render-stage path or run
the work on the CPU: helder.parallel's bodies run as compute dispatches
where there is compute and as SIMD lanes elsewhere, as `examples/fountain`'s
does.
`createComputePipeline` and storage buffers throw on those devices.

```haxe
@:structInit @:publicFields class Particle { var pos:Vec4; var vel:Vec4; }
@:structInit @:publicFields class Step { var dt:Float; var count:Int; }

final Move = compute({
	size: [64],                                    // the workgroup's (x, y, z), 256 invocations at most
	main: function(id:ComputeInput, p:{step:Step, particles:RWStorage<Particle>, kept:RWStorage<Vec4>, args:RWStorage<Int>}) {
		if (id.x >= p.step.count) return;          // (the last workgroup's past the data)
		var q = p.particles[id.x];                 // an element read
		var moved:Particle = {pos: q.pos + q.vel * p.step.dt, vel: q.vel};
		p.particles[id.x] = moved;                 // and written (a local of the struct's type)
		p.kept[atomicAdd(p.args, 1, 1)] = moved.pos;   // appended, counted into a draw's instances
	}
});

var particles = device.createBuffer({size: n * Move.params.particles.stride, usage: Storage, data: Move.params.particles.bytesOf(list)});
var args = device.createBuffer({size: 16, usage: Indirect});   // vertices, instances, first vertex, first instance
var move = device.createComputePipeline(Move.pipeline());
...
var enc = device.beginFrame();
enc.beginCompute();                                // between render passes
enc.setComputePipeline(move);
enc.setUniforms(Move.params.step.block.binding, stepBytes);
enc.setStorage(Move.params.particles.binding, particles);
enc.setStorage(Move.params.kept.binding, kept);
enc.setStorage(Move.params.args.binding, args);
enc.dispatch(Move.groups(n));                      // or dispatchIndirect(buffer, offset)
enc.endCompute();
enc.beginPass(pass);
enc.setVertexBuffer(1, kept);                      // a storage buffer is a vertex (and index) buffer too
enc.drawIndirect(args);                            // (drawIndexedIndirect: five UInt32s)
enc.endPass();
device.readBuffer(particles, 0, bytes);            // tests: waits for the GPU (WebGPU: imports.mjs's readBuffer)
```

The compute function takes the invocation's ids (`ComputeInput`: `x, y,
z` in the dispatch, `localX ... localIndex` in the workgroup, `groupX ...`
the workgroup's) and an object of parameters, at slots in order as the
render stages' are: uniform blocks (std140), `Texture2D`s (sampled at a
mip level: `sampleLevel`, or the first), `Storage<T>` (read) and
`RWStorage<T>` (read and written) buffers, and `StorageTexture`s
(written by `textureStore(t, x, y, c)`; RGBA8, or the field's
`@:format(RGBA16F)` or `@:format(R32F)`; the texture made with
`storage: true`). A storage buffer's elements are Float, Int, Vec2, Vec4,
Mat4 or structs of them (no Vec3: 16 bytes in std430 and WGSL, 12 in
HLSL), laid out as std430 everywhere; `params.<name>` (a `StorageSlot`
of its own class) has its `stride`, `store`, `storeAt`, `load` and
`bytesOf` for the CPU's bytes. An `RWStorage<Int>` has `atomicAdd`,
`atomicMin` and `atomicMax` (its value before). Storage is read and
written in the compute function itself, not passed on to the functions
it calls (GLSL's buffers are no parameters); a buffer's length is not
known to every back end (Metal's): counts go in a uniform block. The
function runs on the CPU as it is (`ComputeInput.at(x, y, z, sx, sy, sz)`
gives the ids). It compiles, as the render stages do, to:

| | Storage buffer | Written | Storage texture | Ids |
|---|---|---|---|---|
| GLSL ES 3.10 | `layout(std430, binding = index) readonly buffer` | `buffer` | `layout(binding, rgba8) writeonly image2D` | `gl_GlobalInvocationID` ... |
| WGSL | `var<storage, read>` at `@binding(slot)` | `read_write` (Ints: `atomic<i32>`) | `texture_storage_2d<..., write>` | `@builtin(global_invocation_id)` ... |
| MSL | `const device T* [[buffer(slot)]]` | `device T*` (Ints: `atomic_int`) | `texture2d<float, access::write>` | `[[thread_position_in_grid]]` ... |
| HLSL (cs_5_0) | `ByteAddressBuffer : register(t<slot>)`, loaded at the std430 offsets | `RWByteAddressBuffer : register(u<index>)` | `RWTexture2D<float4>` (a UAV) | `SV_DispatchThreadID` ... |

Synchronisation is the back end's: a compute pass's dispatches run in
order, each seeing what the ones before wrote, and the draws, samples and
`readBuffer` after it see what they wrote (GL: `glMemoryBarrier(
GL_ALL_BARRIER_BITS)` after each dispatch; D3D11: the written buffers
bound as UAVs before the read ones' views, all unbound at `endCompute`;
Metal: a compute encoder of serial dispatches; WebGPU: its passes' usage
scopes). A frame's uniform ring serves the compute passes' blocks too.
Recording a compute pass allocates nothing, as a render pass does.
Limits: 16 resources a stage, 8 of them written (D3D11's UAVs; GL ES
3.1's devices have 4 storage buffers and 4 images at least), 256
invocations a workgroup (WebGPU's default), 16 KB of workgroup memory
([below](#workgroup-memory-and-subgroups)); no storage in the render
stages (GL ES 3.1 guarantees none there: results reach draws as vertex,
index and indirect buffers and sampled textures). `compute(...)` is Haxe's: the
TypeScript shader adapter has no Int yet; TypeScript sees `Device.has`
and `Feature` (helder/scene).

### Workgroup memory and subgroups

A workgroup's invocations share memory and wait for each other: a third
parameter of the compute function, an object of `Workgroup<T>` arrays (T
as a storage buffer's elements), each as long as the workgroup or its
field's `@:length(n)`; `barrier()`, the workgroup waits there, its
workgroup memory's writes before seen by all of it after. A workgroup
also runs in subgroups (32 lanes on Apple's GPUs, 4 on the CPU and where
they are emulated): `subgroupAdd`, `subgroupMin`, `subgroupMax` (of
Float, Int and the vectors: the subgroup's, in each of its lanes),
`subgroupBroadcast(x, lane)` (lane a constant of 0 to 3),
`subgroupShuffle(x, lane)` (each its own), `subgroupAll` and
`subgroupAny` (Bool), with ComputeInput's `subgroupLane`, `subgroupSize`,
`subgroupIndex` (`localIndex / subgroupSize`) and `subgroups`:

```haxe
final Sums = compute({
	size: [256],
	main: function(id:ComputeInput, p:{count:Count, values:Storage<Float>, out:RWStorage<Float>}, w:{part:Workgroup<Float>}) {
		var v = id.x < p.count.n ? p.values[id.x] : 0.0;
		v = subgroupAdd(v);                                // the subgroup's sum, in each of its lanes
		if (id.subgroupLane == 0) w.part[id.subgroupIndex] = v;
		barrier();                                         // the workgroup's writes seen by all of it
		if (id.localIndex == 0) {
			var s = 0.0;
			for (k in 0...id.subgroups) s += w.part[k];
			p.out[id.groupX] = s;                          // the workgroup's sum
		}
	}
});
```

`barrier()` and the subgroup operations are where every invocation of
the workgroup reaches them (WGSL's uniform control flow, which the
others want too; checked as the stage compiles, an error at the call):
in the compute function itself, not under an `if` or a loop on values
that differ between invocations (ComputeInput's fields, `RWStorage` and
`Workgroup` reads, atomics, subgroup results, and locals assigned any of
those), nor after a `return` under one (`id.x < count ? ... : 0.0`, not
an early return), nor in a loop's condition; an `if` or a loop on
uniform blocks' values and constants may hold them (`while (offset <
256) { ...; barrier(); ... }`), a loop with a barrier no `break` or
`continue`. A stage's workgroup memory is 16 KB at most (WebGPU's and GL
ES 3.1's floor; Direct3D 11's and Metal's are 32 KB), its values
undefined until written.

| | Workgroup memory, `barrier()` | Subgroups (`Feature.Subgroups`) |
|---|---|---|
| WGSL | `var<workgroup>`, `workgroupBarrier()` | the `subgroups` feature, asked for with the device where the adapter has it (Chrome; SwiftShader's 4 lanes) |
| MSL | `threadgroup` (in `main0`, passed on), `threadgroup_barrier(mem_flags::mem_threadgroup)` | `simd_sum`, `simd_shuffle`, ... on Apple7 (A14) and Mac2 GPUs |
| GLSL ES 3.10 | `shared`, `memoryBarrierShared(); barrier()` | `GL_KHR_shader_subgroup` (basic, vote, arithmetic, ballot, shuffle) where the context lists it |
| HLSL (cs_5_0) | `groupshared`, `GroupMemoryBarrierWithGroupSync()` | none (wave intrinsics are D3D12's SM 6.0) |
| CPU | a block for each workgroup; the function cut at its barriers into phases, each run over the workgroup before the next, the locals that live across a barrier kept for each invocation | a call's 4 lanes |

Where a device has no subgroups, a stage using them takes its second
form, `code.emulated` (`Device.createShader` picks it; Direct3D 11's
only form): each operation a scratch array of workgroup memory (one for
each type, as long as the workgroup, counted in the 16 KB), its value
written, a barrier, its 4 lanes' values combined, a barrier: subgroups of
4, slower, the same results wherever they do not depend on the
subgroup's size. On the CPU, `main` called alone is a subgroup of one and
`barrier()` does nothing (`ComputeInput.at` gives `subgroupSize` 1).

The tests: `tests/gfx/ComputeCheck.hx` (`bun run test gfx-compute`: GL on
Mesa, D3D11, Metal; `gfx-compute-web`: WebGPU in Chromium, and WebGL2's
lack of it; `gfx-soft`: the CPU) runs a prefix sum of ten dispatches, an
indirect dispatch that moves particles and counts the kept ones into an
indirect draw of them, a storage texture sampled into the frame, the
workgroup stages (a reduction, a prefix sum in workgroup memory, the
other subgroup operations' workgroup results, the subgroups' ids against
what they broadcast and shuffle) in both forms, the device's and the
emulated one, against the CPU's results, and checks that a frame
allocates nothing; `ShaderCheck` the compute stages' text in the four
languages (`tests/gfx/shader/*.comp.*`), their CPU runs and the programs
it rejects (a barrier under an `if`, a subgroup operation after an early
return, workgroup memory over 16 KB).

## Occlusion queries

Every back end counts whether a draw's samples passed the depth test (GL
ES 3.0's and WebGL2's `ANY_SAMPLES_PASSED`, WebGPU's occlusion query sets,
Metal's visibility results, D3D11's occlusion queries), answered a frame
or more later and never waited for:

```haxe
var queries = device.createQueries(64);
var pass:PassDesc = {colors: [...], depth: {...}, queries: queries};   // WebGPU names the set when a pass begins
enc.beginPass(pass);
enc.beginQuery(k);                                 // one at a time, each at most once a pass
enc.drawIndexed(36);                               // a box, depth tested, not written
enc.endQuery();
enc.endPass();
// a frame or more later:
device.queryResult(queries, k);                    // 1 some sample passed, 0 none, -1 no answer yet
device.resetQuery(queries, k);                     // its answer let go (one on its way too)
```

A query begun again before its last answer came is not begun (its draws
drawn, uncounted), so an answer always comes: GL and D3D11 poll their
queries without flushing, Metal reads its shared buffer once the frame's
command buffer completed, WebGPU resolves a frame's queries into a buffer
mapped after its submit (while one read is on its way, the next frames'
answers are let go). helder.scene's `Occlusion` culls by them.

## On the CPU

`-D helder.soft` (`helder run --headless --soft`) builds the device on the
CPU (`Backend.Soft`, `helder.gfx.soft`): no GPU code linked, a static
executable on Linux, frames byte-identical on every machine. Its shaders
are the definitions' own: the macro emits each stage a fifth time
(`helder.gfx.shader.Soft`), as Haxe over `hxmc.simd`'s 4 lanes, one 2x2
quad of pixels (or 4 vertices) a call:

- values every lane shares (constants, uniform blocks, what only they
  make) stay scalar, computed as the CPU code computes them; their `if`s
  and loops are plain; the rest runs under a mask of its lanes (an `if`
  runs the branches its lanes take, a loop while a lane is in it, a
  `return` or `discard` takes its lanes out);
- `sample` takes its mip level from the quad (lane 1 - lane 0 across,
  lane 2 - lane 0 down, one level for the four pixels, as GPUs do);
- lanes are float32 (`exp`, `log`, `pow`, `sin` and `cos` SIMD polynomials,
  no fused multiply-adds: the same bits everywhere); with
  `-D helder.soft.exact` two `F64x2`s, Haxe's doubles, and with
  `-D helder.soft.reference` each stage also as its scalar code lane by
  lane: `tests/gfx/SoftShaderCheck.hx` runs every shader of `src/helder`
  both ways on random inputs, blocks and textures and requires the same
  bits (89 of 89). `Lane`, `LaneInt` and `LaneBool` are the one place the
  width is known: wider lanes are another implementation of those three.

A draw runs its vertex stage at once, clips (near, far, and a guard band
that keeps the fixed point exact), sets triangles up in fixed point (8 bits
under the pixel, the top-left rule; the planes of depth, 1/w and each
varying over w: perspective-correct) and bins them into the pass's 32x32
tiles. The pass's end shades the tiles in parallel (`helder.jobs.Spread`:
GC-free callbacks on the pool's threads, which spin a while between runs;
`HELDER_SOFT_THREADS=n` caps them, 1 none), each its triangles in order:
a row's span from the edges, the depth test before the fragment stage,
blending as GL's factors into the target's format (unorm clamped and
rounded, sRGB in linear values, RGBA16F rounded to halves), a pass's
clears in its tiles first. Targets, textures and the pass's records are
outside the collector's heap (`SoftTexture`, `Chunks`): tiles read and
write them from any thread with no copies. Textures: every
`TextureFormat` (R8 and RG8 as RGBA8, half floats as floats, BC1, BC3 and
the ASTC helder's encoder writes decoded when written, another ASTC block
magenta), nearest, linear and trilinear, repeat, clamp and mirror, cubes
filtered across their faces' edges (seamless, as
GL_TEXTURE_CUBE_MAP_SEAMLESS), no anisotropy (helder's
samplers have none). MSAA: 4 samples at the standard positions, the pixel
shaded once, resolved at the pass's end. Compute stages have the same
form (`soft_cs`: 4 invocations a call, a lane each, their ids
ComputeInput's fields, a subgroup of 4; with barriers the call runs a
phase and returns the next: `helder.gfx.shader.Phases`), run on the
calling thread workgroup by workgroup, its workgroup memory zeroed at its
start
(so that atomics come in the same order on every machine): storage buffers
read and written by element (std430), an index past a buffer read as 0 and
written nowhere, atomics lane by lane, a storage texture's texel written
in its format (`Buffers`); `has` is true for Compute, StorageTextures and
Indirect, and helder.scene takes its compute paths (clustered lights,
instance culling, prefiltering), whose frames are its fallbacks'. Not
here: shared textures, shaders without a CPU form (TypeScript's
`shader(...)` and materials: JSON, compiled straight to hxmc's IR, no
Haxe for the macro to emit them from; they draw nothing); lines and points
are a pixel-wide quad.

A window's frame is shown by the system's own path, no GPU API
(`helder.os.Blit`, at `endFrame`, where `damaged` said it changed): X11 an
XImage, through MIT-SHM where the server is this machine's (else
XPutImage); Wayland two wl_shm buffers on the window's wl_surface (no
wl_egl_window in a `-D helder.soft` build); macOS a CGImage as the
contents of the view's layer (a plain CALayer, in the screen's colour
space: shown unconverted, as an untagged Metal layer's); Windows
StretchDIBits into the window's DC; the web putImageData into the canvas's
2D context. Built without `helder.headless`, a `-D helder.soft` program
opens windows as any (on Linux glibc then, not static), smaller than its
GPU build (counter: macOS 3.88 MB against 4.11, Linux 3.67 against 4.35,
Windows 3.46 against 3.97), and the web's imports no GL or GPU module.

Against the GPUs, tests/3d's 76 scenes and tests/gfx's 10 frames (`bun
run test gfx-soft`, GfxCheck's rule): all within it of their goldens
(llvmpipe's), but khrspecular and khrclearcoat, within 6 levels (Metal
lands 9 and 151 from those goldens too: specular sparkles); against Metal
74 of 76 (khrclearcoat's sparkles; compressed: Metal on the Mac draws its
ASTC quad grey, the CPU decodes it). helder.ui's GPU nodes draw on it in a
`--soft` UI (`GpuHost`): glow's `<Scene>` is Metal's frame exactly,
showreel's material within a level; fx's effects that hash with `sin`
(`fract(sin(x) * 43758.5)`) differ, as GPUs differ between themselves there.

What keeps it fast: a stage's small helpers are emitted inline (straight
code of a few dozen nodes, with the inlined ones it calls), so their
struct values stay in registers; constants and uniform blocks' fields
reach the lanes as their float32 bits (hxmc builds a Float's splat as a
double, converted at each use); `sampleLevel(t, uv, 0)` and a texture of
one level read their level directly (no level of detail found), a float
texture's four texels blended whole per lane, then turned into lanes once,
sRGB and float texels gathered as bits; on x86-64, whole texel coordinates
converted by 2^23's bits (hxmc's saturating conversion is 7 instructions
there). Each change leaves the frames as they were, byte for byte.

Speed: tests/bench/FrameBench.hx (`bun run test bench frame`) (each scene's first frame, made, drawn and
read back, then the least of 10), the 76 scenes summed, Linux x86-64 in
Docker (`helder-llvmpipe-dejavu`, emulated on an M4, 10 threads, scenes
alternating between the two so that the machine's load weighs on both):

| | steady | first frames |
| --- | ---: | ---: |
| llvmpipe, 256x192 | 563 ms | 128 s |
| CPU, 256x192 | 429 ms | 8.9 s |
| llvmpipe, 1024x768 | 2286 ms | 97 s |
| CPU, 1024x768 | 3178 ms | 10.1 s |
| llvmpipe, one thread, 256x192 | 1263 ms | 93 s |
| CPU, one thread, 256x192 | 1278 ms | 4.2 s |

First frames are 10 to 20 times faster (llvmpipe compiles each shader when
first drawn); steady frames are faster at the tests' size, level on one
thread, slower at 1024x768: one thread there is about as fast as
llvmpipe's, but llvmpipe gains more from 10 threads in Docker. What is
left is the generated code itself (hxmc keeps few vectors in registers
across a call) and texture gathers. On the M4 natively: 0.26 s for the 76
scenes at 256x192.

Size: a `--soft` headless build with a `<Scene>` (examples/glow) 2.1 MB →
3.2 MB (the back end and its shaders' SIMD forms; the grey box before),
todo 3.88 → 4.01 MB (its controls' part shaders now drawn); GPU builds
are unchanged (counter: the same size on macOS and Windows, 16 bytes more on
Linux).
