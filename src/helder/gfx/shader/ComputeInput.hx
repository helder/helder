package helder.gfx.shader;

// A compute stage's input (ShaderMath.compute's main: its first parameter):
// the invocation's ids. x, y, z: in the whole dispatch (GLSL's
// gl_GlobalInvocationID, WGSL's global_invocation_id, MSL's
// thread_position_in_grid, HLSL's SV_DispatchThreadID); localX, localY,
// localZ and localIndex: in its workgroup; groupX, groupY, groupZ: the
// workgroup's in the dispatch. A dispatch of n workgroups of the
// definition's size runs size * n invocations: the last workgroup's past
// the data return early (if (id.x >= count) return).
@:structInit @:publicFields class ComputeInput {
	var x:Int;
	var y:Int;
	var z:Int;
	var localX:Int;
	var localY:Int;
	var localZ:Int;
	var localIndex:Int;
	var groupX:Int;
	var groupY:Int;
	var groupZ:Int;

	// the invocation x, y, z of a dispatch of workgroups of size (sx, sy, sz) (the CPU's)
	public static function at(x:Int, y:Int, z:Int, sx:Int, sy:Int, sz:Int):ComputeInput
		return {
			x: x,
			y: y,
			z: z,
			localX: x % sx,
			localY: y % sy,
			localZ: z % sz,
			localIndex: x % sx + sx * (y % sy + sy * (z % sz)),
			groupX: Std.int(x / sx),
			groupY: Std.int(y / sy),
			groupZ: Std.int(z / sz)
		};
}
