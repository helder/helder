# helder.math

The math types every package shares (Haxe package `helder.math`,
TypeScript `helder/math`): immutable values, `@:hxmc.struct` values on
hxmc's targets (copied, never allocated), objects elsewhere (Eval, the
macro context). They are also the shader types: a shader definition
(helder.gfx.shader) reads and writes them as they are, so what the CPU
computes is what a shader reads.

```haxe
import helder.math.*;

var p = new Vec3(1, 2, 3);
var q = p.xy * 2 + 1;                       // swizzles and operators: a Vec2
var m = Mat4.perspective(Math.PI / 3, 16 / 9, 0.1, 100) * Mat4.translation(0, 0, -5);
var clip = m * new Vec4(p.x, p.y, p.z, 1);
var turn = Quat.axisAngle(new Vec3(0, 1, 0), Math.PI / 2);
var r = turn.rotate(p);
```

| Type | What |
|---|---|
| `Vec2`, `Vec3`, `Vec4` | 2 to 4 floats: `x`, `y`, `z`, `w` and every swizzle of 2 to 4 of them (`v.yx`, `v.xyz`), read only; `+ - * /` componentwise, with a Float on either side, unary `-` (written out by `VecBuild`) |
| `Mat4` | a 4x4 matrix of four columns (`c0`..`c3`): `m * v` transforms a column vector, `a * b` applies `b` first; `identity`, `translation`, `scaling`, `rotationX/Y/Z`, `perspective`, `orthographic` (the clip space of every back end: y up, z 0 to 1, right-handed) |
| `Quat` | a rotation as a unit quaternion: `identity`, `axisAngle`, `fromEuler`, `fromMat4`, `a * b` (b first), `rotate`, `toMat4`, `slerp`, `conjugate`, `normalized`, `dot`, `length` |

The functions on them (`dot`, `length`, `normalize`, `cross`, `mix`,
`clamp`, the constructors `vec2`..`vec4`, `mat4`) are the shader builtins,
`helder.gfx.shader.ShaderMath.*` (TypeScript: helder/gfx's), usable on the
CPU as well. helder.scene.math adds `Aabb`, `Curve3` and `MathTools`
(`inverse`, `transpose`, `lookAt`, `decompose` of a `Mat4`).

In TypeScript they are classes (`src/helder/math/index.ts`, written by
`src/helder/math/typescript.mjs`), the operators methods (`a.mul(b)`,
`a.add(1)`), crossing to Haxe by value (src/helder/typescript/README.md).
