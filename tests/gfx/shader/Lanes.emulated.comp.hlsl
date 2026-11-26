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
ComputeInput make_ComputeInput(int f0, int f1, int f2, int f3, int f4, int f5, int f6, int f7, int f8, int f9, int f10, int f11, int f12, int f13) {
	ComputeInput s;
	s.x = f0;
	s.y = f1;
	s.z = f2;
	s.localX = f3;
	s.localY = f4;
	s.localZ = f5;
	s.localIndex = f6;
	s.groupX = f7;
	s.groupY = f8;
	s.groupZ = f9;
	s.subgroupLane = f10;
	s.subgroupSize = f11;
	s.subgroupIndex = f12;
	s.subgroups = f13;
	return s;
}
RWByteAddressBuffer sb_0 : register(u0);
int sb_0_load(int i) {
	uint at = uint(i) * 4u;
	return asint(sb_0.Load(at));
}
void sb_0_store(int i, int v) {
	uint at = uint(i) * 4u;
	sb_0.Store(at + 0u, asuint(v));
}
int sb_0_atomicAdd(int i, int v) {
	int o;
	sb_0.InterlockedAdd(uint(i) * 4u, v, o);
	return o;
}
int sb_0_atomicMin(int i, int v) {
	int o;
	sb_0.InterlockedMin(uint(i) * 4u, v, o);
	return o;
}
int sb_0_atomicMax(int i, int v) {
	int o;
	sb_0.InterlockedMax(uint(i) * 4u, v, o);
	return o;
}
groupshared int wg_0[64];
groupshared int wg_1[64];
groupshared int wg_2[64];
groupshared float2 wg_3[64];
void cs(ComputeInput id) {
	int i = id.localIndex;
	int t0 = id.subgroupLane;
	wg_0[i] = t0;
	int t1 = id.subgroupIndex;
	wg_1[i] = t1;
	wg_2[id.localIndex] = i;
	GroupMemoryBarrierWithGroupSync();
	int sg_0 = wg_2[(id.localIndex & (-4)) + 0];
	GroupMemoryBarrierWithGroupSync();
	int first = sg_0;
	wg_2[id.localIndex] = i;
	GroupMemoryBarrierWithGroupSync();
	int sg_1 = wg_2[(id.localIndex & (-4)) + ((id.subgroupLane ^ 1) & 3)];
	GroupMemoryBarrierWithGroupSync();
	int other = sg_1;
	wg_2[id.localIndex] = other;
	GroupMemoryBarrierWithGroupSync();
	int sg_2 = wg_2[(id.localIndex & (-4)) + ((id.subgroupLane ^ 1) & 3)];
	GroupMemoryBarrierWithGroupSync();
	int back = sg_2;
	wg_3[id.localIndex] = float2(float(i), 1.0);
	GroupMemoryBarrierWithGroupSync();
	float2 sg_3 = wg_3[(id.localIndex & (-4)) + ((id.subgroupLane ^ 1) & 3)];
	GroupMemoryBarrierWithGroupSync();
	float2 pair = sg_3;
	wg_3[id.localIndex] = float2(1.0, 0.0);
	GroupMemoryBarrierWithGroupSync();
	float2 sg_4 = ((wg_3[id.localIndex & (-4)] + wg_3[(id.localIndex & (-4)) + 1]) + wg_3[(id.localIndex & (-4)) + 2]) + wg_3[(id.localIndex & (-4)) + 3];
	GroupMemoryBarrierWithGroupSync();
	float2 count = sg_4;
	GroupMemoryBarrierWithGroupSync();
	bool ok = ((((((((wg_0[first] == 0) && (wg_1[first] == id.subgroupIndex)) && (wg_0[other] == (id.subgroupLane ^ 1))) && (wg_1[other] == id.subgroupIndex)) && (back == i)) && (int(pair.x) == other)) && (int(count.x) == id.subgroupSize)) && (((id.subgroupIndex * id.subgroupSize) + id.subgroupLane) == i)) && ((id.subgroups * id.subgroupSize) == 64);
	int t2 = id.x;
	int t3 = ok ? 1 : 0;
	sb_0_store(t2, t3);
}
[numthreads(64, 1, 1)]
void main(uint3 gid : SV_DispatchThreadID, uint3 lid : SV_GroupThreadID, uint lidx : SV_GroupIndex, uint3 grp : SV_GroupID) {
	cs(make_ComputeInput(int(gid.x), int(gid.y), int(gid.z), int(lid.x), int(lid.y), int(lid.z), int(lidx), int(grp.x), int(grp.y), int(grp.z), int(lidx) & 3, 4, int(lidx) >> 2, 16));
}
