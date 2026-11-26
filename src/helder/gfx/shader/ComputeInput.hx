package helder.gfx.shader;

// A compute stage's input (ShaderMath.compute's main: its first parameter):
// the invocation's ids. x, y, z: in the whole dispatch (GLSL's
// gl_GlobalInvocationID, WGSL's global_invocation_id, MSL's
// thread_position_in_grid, HLSL's SV_DispatchThreadID); localX, localY,
// localZ and localIndex: in its workgroup; groupX, groupY, groupZ: the
// workgroup's in the dispatch. A dispatch of n workgroups of the
// definition's size runs size * n invocations: the last workgroup's past
// the data return early (if (id.x >= count) return).
//
// A workgroup's invocations run in subgroups (ShaderMath's subgroupAdd and
// the others): subgroupLane, the invocation's lane in its subgroup;
// subgroupSize, the lanes of a subgroup (the GPU's: 32 on Apple's, 4
// where they are emulated, and on the CPU back end); subgroupIndex, the
// subgroup's in the workgroup (localIndex / subgroupSize); subgroups, the
// workgroup's count of them.
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
	var subgroupLane:Int;
	var subgroupSize:Int;
	var subgroupIndex:Int;
	var subgroups:Int;

	// the invocation x, y, z of a dispatch of workgroups of size (sx, sy,
	// sz) (the CPU's: an invocation called alone, a subgroup of one)
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
			groupZ: Std.int(z / sz),
			subgroupLane: 0,
			subgroupSize: 1,
			subgroupIndex: x % sx + sx * (y % sy + sy * (z % sz)),
			subgroups: sx * sy * sz
		};
}
