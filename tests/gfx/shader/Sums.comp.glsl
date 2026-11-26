#version 310 es
#extension GL_KHR_shader_subgroup_basic : require
#extension GL_KHR_shader_subgroup_arithmetic : require
layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;
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
struct Count {
	int n;
};
layout(std430, binding = 1) readonly buffer sb_1_block {
	float data[];
} sb_1;
layout(std430, binding = 0) buffer sb_2_block {
	float data[];
} sb_2;
shared float wg_0[256];
void cs(ComputeInput id, Count count) {
	float v = (id.x < count.n) ? sb_1.data[id.x] : 0.0;
	v = subgroupAdd(v);
	if (id.subgroupLane == 0) {
		int t0 = id.subgroupIndex;
		wg_0[t0] = v;
	}
	memoryBarrierShared(); barrier();
	if (id.localIndex == 0) {
		float s = 0.0;
		int t = 0;
		int t_2 = id.subgroups;
		while (t < t_2) {
			int k = t;
			t += 1;
			s += wg_0[k];
		}
		int t1 = id.groupX;
		sb_2.data[t1] = s;
	}
}
layout(std140, binding = 0) uniform Count_block {
	int n;
} u_0;
void main() {
	cs(ComputeInput(int(gl_GlobalInvocationID.x), int(gl_GlobalInvocationID.y), int(gl_GlobalInvocationID.z), int(gl_LocalInvocationID.x), int(gl_LocalInvocationID.y), int(gl_LocalInvocationID.z), int(gl_LocalInvocationIndex), int(gl_WorkGroupID.x), int(gl_WorkGroupID.y), int(gl_WorkGroupID.z), int(gl_SubgroupInvocationID), int(gl_SubgroupSize), int(gl_SubgroupID), int(gl_NumSubgroups)), Count(u_0.n));
}
