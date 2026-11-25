# Shaders and the GPU

Under everything sits `helder.gfx`: one small GPU API over Metal, Direct3D 11, OpenGL, WebGPU and WebGL2. Shaders are ordinary functions in your language, type-checked with the rest of your program, translated to each platform's shading language when you build, and runnable on the CPU for tests.

<Example id="fountain"/>

A shader is a vertex and a fragment function over vector types. Its uniforms, textures and vertex layout come from the function's types.

```ts
import {shader, position, sample, vec4} from 'helder/gfx'
import type {Vec2, Vec4, Texture2D} from 'helder/gfx'

type Vertex = {pos: Vec2, uv: Vec2}
type Varyings = {pos: Vec4, uv: Vec2}
type Tint = {color: Vec4}

export const Sprite = shader({
  vertex: (v: Vertex): Varyings =>
    ({pos: position(vec4(v.pos, 0, 1)), uv: v.uv}),
  fragment: (i: Varyings, p: {tint: Tint, image: Texture2D}): Vec4 =>
    sample(p.image, i.uv).mul(p.tint.color)
})
```

```haxe
@:structInit @:publicFields class Vertex {var pos:Vec2; var uv:Vec2;}
@:structInit @:publicFields class Varyings {var pos:Vec4; var uv:Vec2;}
@:structInit @:publicFields class Tint {var color:Vec4;}

final Sprite = shader({
  vertex: function(v:Vertex):Varyings
    return {pos: position(vec4(v.pos, 0, 1)), uv: v.uv},
  fragment: function(i:Varyings, p:{tint:Tint, image:Texture2D}):Vec4
    return sample(p.image, i.uv) * p.tint.color
});
```

## What else

- **Compute:** compute stages with storage buffers and atomics on WebGPU, Metal, Direct3D 11 and OpenGL ES 3.1 and the CPU back end, with a CPU fallback for WebGL2 ([Murmuration](https://helder.build/examples/#murmuration) steers half a million birds this way).
- **Workgroups:** shared workgroup memory, `barrier()` and subgroup operations (sums, minimums, broadcasts, shuffles, votes) for reductions and prefix sums, the GPU's own subgroups where it has them and the same results everywhere else.
- **The API:** buffers, textures in every portable format, render targets, mip maps, instanced and indirect draws, occlusion queries.
- **Shared textures** between processes, through IOSurface and DXGI.
- **No surprises:** pipelines are immutable, handles are integers, and a steady frame allocates nothing.

<Reference to="gfx"/>
