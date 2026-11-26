package helder.gfx.shader;

import haxe.macro.Expr;

// The builtins of shader code, usable in CPU code as well (import
// helder.gfx.shader.ShaderMath.*): the constructors vec2, vec3, vec4 and mat4
// (as GLSL's: vec4(v.xy, 0, 1), vec3(1)), GLSL's componentwise functions on
// Float and the vectors (abs, sign, floor, ceil, fract, sqrt, inversesqrt,
// sin, cos, tan, asin, acos, atan, exp, log, min, max, pow, step, mix,
// clamp, smoothstep; atan2(y, x), GLSL's atan of two, the angle of (x, y)) and
// the geometric ones (dot, length, distance, normalize, reflect, cross),
// and sample(t, uv), a Texture2D's colour at uv (in the fragment stage at
// the mip level its footprint needs, in the vertex stage the first), and
// sampleLevel(t, uv, level) at a mip level (fractions blend two levels with
// a sampler's mipFilter Linear), and their forms for a TextureCube (sample(t,
// dir), along a direction) and a Texture2DArray (sample(t, uv, layer)); discard(), in the fragment stage, drops the
// fragment (alpha testing: nothing on the CPU). Written out by
// VecBuild.builtins. The compute stage's: atomicAdd(b, i, v), atomicMin and
// atomicMax on an RWStorage<Int>'s element (its value before), and
// textureStore(t, x, y, c), a StorageTexture's texel written; barrier(),
// the workgroup waits for all of it, its workgroup memory's writes before
// seen after (Workgroup); the subgroup operations (ComputeInput's
// subgroupLane ...): subgroupAdd(x), subgroupMin(x), subgroupMax(x) of the
// subgroup's lanes, in each lane, subgroupBroadcast(x, lane) a lane's x
// (lane a constant, 0 to 3), subgroupShuffle(x, lane) the lane's x it
// names (each its own), subgroupAll(b) and subgroupAny(b), of Float, Int
// and the vectors (Bool: all, any). Those two only where every invocation
// of the workgroup reaches them: not under an if or a loop on values that
// differ between invocations (the ids, RWStorage and Workgroup reads,
// subgroup results), nor after a return under one (checked: WGSL's
// uniform control flow), in the compute function itself.
//
// And the shader definition, shader({vertex, fragment}) (Shader), with
// position(v), which marks the varyings' clip-space position where the
// vertex stage builds them ({clip: position(m * p), uv: v.uv}); slots({vertex,
// fragment, options, <slot>: ...}), a shader with slots and options whose
// variants are shaders (Slots); compute({size, main}), a compute stage
// (ComputeShader), on the devices that have them (Device.has(Compute)).
#if !macro
@:build(helder.gfx.shader.VecBuild.builtins())
#end
class ShaderMath {
	// a pipeline's two stages, compiled at build time (Shader)
	@:definition public static macro function shader(def:Expr):Expr
		return helder.gfx.shader.ShaderMacro.shader(def);

	// a compute stage, compiled at build time (ComputeShader): {size: [x, y, z]
	// (its workgroup's, 1 for the ones left out), main: function(id:ComputeInput, p:{...}, ?w:{...})}
	@:definition public static macro function compute(def:Expr):Expr
		return helder.gfx.shader.ShaderMacro.compute(def);

	// a shader with slots and options (Slots): its variants compiled at build time
	@:definition public static macro function slots(def:Expr):Expr
		return helder.gfx.shader.SlotsMacro.slots(def);

	#if !macro
	// a value the CPU sets, read by shaders as uniform.value (a module-level final: Shader.uniformBytes)
	@:generic public static function uniform<T>(value:T):Uniform<T>
		return new Uniform(value);

	// (compute) b[i] += v, atomically; b[i]'s value before
	public static function atomicAdd(b:RWStorage<Int>, i:Int, v:Int):Int {
		var o = b[i];
		b[i] = o + v;
		return o;
	}

	// (compute) b[i] = min(b[i], v), atomically; b[i]'s value before
	public static function atomicMin(b:RWStorage<Int>, i:Int, v:Int):Int {
		var o = b[i];
		if (v < o) b[i] = v;
		return o;
	}

	// (compute) b[i] = max(b[i], v), atomically; b[i]'s value before
	public static function atomicMax(b:RWStorage<Int>, i:Int, v:Int):Int {
		var o = b[i];
		if (v > o) b[i] = v;
		return o;
	}

	// (compute) the texel x, y (from the top left) of t written: c's channels
	// in its format (RGBA8: clamped to 0..1)
	public static function textureStore(t:StorageTexture, x:Int, y:Int, c:Vec4):Void
		t.store(x, y, c);

	// (compute) the subgroup operations of a Float, an Int or a vector
	// (Lower checks the type); on the CPU an invocation is called alone, a
	// subgroup of one: each its own value
	public static function subgroupAdd<T>(x:T):T
		return x;

	public static function subgroupMin<T>(x:T):T
		return x;

	public static function subgroupMax<T>(x:T):T
		return x;

	public static function subgroupBroadcast<T>(x:T, lane:Int):T
		return x;

	public static function subgroupShuffle<T>(x:T, lane:Int):T
		return x;

	public static function subgroupAll(b:Bool):Bool
		return b;

	public static function subgroupAny(b:Bool):Bool
		return b;

	// the clip-space position among a vertex stage's varyings (its value as it is)
	public static inline function position(v:Vec4):Vec4
		return v;
	#end
}
