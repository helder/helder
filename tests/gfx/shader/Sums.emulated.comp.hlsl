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
struct Count {
	int n;
};
Count make_Count(int f0) {
	Count s;
	s.n = f0;
	return s;
}
ByteAddressBuffer sb_1 : register(t1);
float sb_1_load(int i) {
	uint at = uint(i) * 4u;
	return asfloat(sb_1.Load(at));
}
RWByteAddressBuffer sb_2 : register(u0);
float sb_2_load(int i) {
	uint at = uint(i) * 4u;
	return asfloat(sb_2.Load(at));
}
void sb_2_store(int i, float v) {
	uint at = uint(i) * 4u;
	sb_2.Store(at + 0u, asuint(v));
}
groupshared float wg_0[256];
groupshared float wg_1[256];
void cs(ComputeInput id, Count count) {
	float v = (id.x < count.n) ? sb_1_load(id.x) : 0.0;
	wg_1[id.localIndex] = v;
	GroupMemoryBarrierWithGroupSync();
	float sg_0 = ((wg_1[id.localIndex & (-4)] + wg_1[(id.localIndex & (-4)) + 1]) + wg_1[(id.localIndex & (-4)) + 2]) + wg_1[(id.localIndex & (-4)) + 3];
	GroupMemoryBarrierWithGroupSync();
	v = sg_0;
	if (id.subgroupLane == 0) {
		int t0 = id.subgroupIndex;
		wg_0[t0] = v;
	}
	GroupMemoryBarrierWithGroupSync();
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
		sb_2_store(t1, s);
	}
}
cbuffer Count_block : register(b0) {
	int u_0_n : packoffset(c0);
};
[numthreads(256, 1, 1)]
void main(uint3 gid : SV_DispatchThreadID, uint3 lid : SV_GroupThreadID, uint lidx : SV_GroupIndex, uint3 grp : SV_GroupID) {
	cs(make_ComputeInput(int(gid.x), int(gid.y), int(gid.z), int(lid.x), int(lid.y), int(lid.z), int(lidx), int(grp.x), int(grp.y), int(grp.z), int(lidx) & 3, 4, int(lidx) >> 2, 64), make_Count(u_0_n));
}
