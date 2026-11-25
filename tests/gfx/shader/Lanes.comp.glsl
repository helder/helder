#version 310 es
#extension GL_KHR_shader_subgroup_basic : require
#extension GL_KHR_shader_subgroup_arithmetic : require
#extension GL_KHR_shader_subgroup_ballot : require
#extension GL_KHR_shader_subgroup_shuffle : require
layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
precision highp float;
precision highp int;
struct ComputeInput {
	int x;
	int y;
	int z;
	int localX;
	int localY;
	int localZ;
	int localIndex;
	int groupX;
	int groupY;
	int groupZ;
	int subgroupLane;
	int subgroupSize;
	int subgroupIndex;
	int subgroups;
};
layout(std430, binding = 0) buffer sb_0_block {
	int data[];
} sb_0;
shared int wg_0[64];
shared int wg_1[64];
void cs(ComputeInput id) {
	int i = id.localIndex;
	int t0 = id.subgroupLane;
	wg_0[i] = t0;
	int t1 = id.subgroupIndex;
	wg_1[i] = t1;
	int first = subgroupBroadcast(i, uint(0));
	int other = subgroupShuffle(i, uint(id.subgroupLane ^ 1));
	int back = subgroupShuffle(other, uint(id.subgroupLane ^ 1));
	vec2 pair = subgroupShuffle(vec2(float(i), 1.0), uint(id.subgroupLane ^ 1));
	vec2 count = subgroupAdd(vec2(1.0, 0.0));
	memoryBarrierShared(); barrier();
	bool ok = ((((((((wg_0[first] == 0) && (wg_1[first] == id.subgroupIndex)) && (wg_0[other] == (id.subgroupLane ^ 1))) && (wg_1[other] == id.subgroupIndex)) && (back == i)) && (int(pair.x) == other)) && (int(count.x) == id.subgroupSize)) && (((id.subgroupIndex * id.subgroupSize) + id.subgroupLane) == i)) && ((id.subgroups * id.subgroupSize) == 64);
	int t2 = id.x;
	int t3 = ok ? 1 : 0;
	sb_0.data[t2] = t3;
}
void main() {
	cs(ComputeInput(int(gl_GlobalInvocationID.x), int(gl_GlobalInvocationID.y), int(gl_GlobalInvocationID.z), int(gl_LocalInvocationID.x), int(gl_LocalInvocationID.y), int(gl_LocalInvocationID.z), int(gl_LocalInvocationIndex), int(gl_WorkGroupID.x), int(gl_WorkGroupID.y), int(gl_WorkGroupID.z), int(gl_SubgroupInvocationID), int(gl_SubgroupSize), int(gl_SubgroupID), int(gl_NumSubgroups)));
}
