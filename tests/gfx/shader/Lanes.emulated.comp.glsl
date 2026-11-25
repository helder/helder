#version 310 es
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
shared int wg_2[64];
shared vec2 wg_3[64];
void cs(ComputeInput id) {
	int i = id.localIndex;
	int t0 = id.subgroupLane;
	wg_0[i] = t0;
	int t1 = id.subgroupIndex;
	wg_1[i] = t1;
	wg_2[id.localIndex] = i;
	memoryBarrierShared(); barrier();
	int sg_0 = wg_2[(id.localIndex & (-4)) + 0];
	memoryBarrierShared(); barrier();
	int first = sg_0;
	wg_2[id.localIndex] = i;
	memoryBarrierShared(); barrier();
	int sg_1 = wg_2[(id.localIndex & (-4)) + ((id.subgroupLane ^ 1) & 3)];
	memoryBarrierShared(); barrier();
	int other = sg_1;
	wg_2[id.localIndex] = other;
	memoryBarrierShared(); barrier();
	int sg_2 = wg_2[(id.localIndex & (-4)) + ((id.subgroupLane ^ 1) & 3)];
	memoryBarrierShared(); barrier();
	int back = sg_2;
	wg_3[id.localIndex] = vec2(float(i), 1.0);
	memoryBarrierShared(); barrier();
	vec2 sg_3 = wg_3[(id.localIndex & (-4)) + ((id.subgroupLane ^ 1) & 3)];
	memoryBarrierShared(); barrier();
	vec2 pair = sg_3;
	wg_3[id.localIndex] = vec2(1.0, 0.0);
	memoryBarrierShared(); barrier();
	vec2 sg_4 = ((wg_3[id.localIndex & (-4)] + wg_3[(id.localIndex & (-4)) + 1]) + wg_3[(id.localIndex & (-4)) + 2]) + wg_3[(id.localIndex & (-4)) + 3];
	memoryBarrierShared(); barrier();
	vec2 count = sg_4;
	memoryBarrierShared(); barrier();
	bool ok = ((((((((wg_0[first] == 0) && (wg_1[first] == id.subgroupIndex)) && (wg_0[other] == (id.subgroupLane ^ 1))) && (wg_1[other] == id.subgroupIndex)) && (back == i)) && (int(pair.x) == other)) && (int(count.x) == id.subgroupSize)) && (((id.subgroupIndex * id.subgroupSize) + id.subgroupLane) == i)) && ((id.subgroups * id.subgroupSize) == 64);
	int t2 = id.x;
	int t3 = ok ? 1 : 0;
	sb_0.data[t2] = t3;
}
void main() {
	cs(ComputeInput(int(gl_GlobalInvocationID.x), int(gl_GlobalInvocationID.y), int(gl_GlobalInvocationID.z), int(gl_LocalInvocationID.x), int(gl_LocalInvocationID.y), int(gl_LocalInvocationID.z), int(gl_LocalInvocationIndex), int(gl_WorkGroupID.x), int(gl_WorkGroupID.y), int(gl_WorkGroupID.z), int(gl_LocalInvocationIndex) & 3, 4, int(gl_LocalInvocationIndex) >> 2, 16));
}
