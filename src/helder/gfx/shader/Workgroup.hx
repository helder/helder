package helder.gfx.shader;

// An array of a compute stage's workgroup memory (ShaderMath.compute's
// main: a field of its third parameter), shared by the invocations of a
// workgroup and read and written by index (w.part[i] = v): WGSL's
// var<workgroup>, GLSL's shared, MSL's threadgroup, HLSL's groupshared.
// Its elements are those of a storage buffer (Float, Int, Vec2, Vec4, Mat4
// or a struct of those); it is as long as the workgroup, or as its field's
// @:length(n) says:
//
//   main: function(id:ComputeInput, p:{...}, w:{var part:Workgroup<Float>; @:length(512) var tile:Workgroup<Vec4>;}) ...
//
// A stage's workgroup memory takes 16 KB at most (WebGPU's and GL ES 3.1's
// floor: checked as it compiles). Its values are undefined until written;
// a write is seen by the workgroup's other invocations after a barrier().
// Read and written in the compute function itself (not passed on). On the
// CPU: the elements' array.
abstract Workgroup<T>(Array<T>) from Array<T> to Array<T> {
	@:arrayAccess public inline function get(i:Int):T
		return this[i];

	@:arrayAccess public inline function set(i:Int, v:T):T
		return this[i] = v;
}
