#version 310 es
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
	int data[];
} sb_1;
layout(std430, binding = 0) buffer sb_2_block {
	int data[];
} sb_2;
shared int wg_0[256];
void cs(ComputeInput id, Count count) {
	int i = id.localIndex;
	int t0 = (id.x < count.n) ? sb_1.data[id.x] : 0;
	wg_0[i] = t0;
	memoryBarrierShared(); barrier();
	int offset = 1;
	while (offset < 256) {
		int v = wg_0[i];
		if (i >= offset) {
			v += wg_0[i - offset];
		}
		memoryBarrierShared(); barrier();
		wg_0[i] = v;
		memoryBarrierShared(); barrier();
		offset *= 2;
	}
	if (id.x < count.n) {
		int t1 = id.x;
		int t2 = wg_0[i];
		sb_2.data[t1] = t2;
	}
}
layout(std140, binding = 0) uniform Count_block {
	int n;
} u_0;
void main() {
	cs(ComputeInput(int(gl_GlobalInvocationID.x), int(gl_GlobalInvocationID.y), int(gl_GlobalInvocationID.z), int(gl_LocalInvocationID.x), int(gl_LocalInvocationID.y), int(gl_LocalInvocationID.z), int(gl_LocalInvocationIndex), int(gl_WorkGroupID.x), int(gl_WorkGroupID.y), int(gl_WorkGroupID.z), int(gl_LocalInvocationIndex) & 3, 4, int(gl_LocalInvocationIndex) >> 2, 64), Count(u_0.n));
}
