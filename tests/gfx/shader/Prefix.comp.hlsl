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
int sb_1_load(int i) {
	uint at = uint(i) * 4u;
	return asint(sb_1.Load(at));
}
RWByteAddressBuffer sb_2 : register(u0);
int sb_2_load(int i) {
	uint at = uint(i) * 4u;
	return asint(sb_2.Load(at));
}
void sb_2_store(int i, int v) {
	uint at = uint(i) * 4u;
	sb_2.Store(at + 0u, asuint(v));
}
int sb_2_atomicAdd(int i, int v) {
	int o;
	sb_2.InterlockedAdd(uint(i) * 4u, v, o);
	return o;
}
int sb_2_atomicMin(int i, int v) {
	int o;
	sb_2.InterlockedMin(uint(i) * 4u, v, o);
	return o;
}
int sb_2_atomicMax(int i, int v) {
	int o;
	sb_2.InterlockedMax(uint(i) * 4u, v, o);
	return o;
}
groupshared int wg_0[256];
void cs(ComputeInput id, Count count) {
	int i = id.localIndex;
	int t0 = (id.x < count.n) ? sb_1_load(id.x) : 0;
	wg_0[i] = t0;
	GroupMemoryBarrierWithGroupSync();
	int offset = 1;
	while (offset < 256) {
		int v = wg_0[i];
		if (i >= offset) {
			v += wg_0[i - offset];
		}
		GroupMemoryBarrierWithGroupSync();
		wg_0[i] = v;
		GroupMemoryBarrierWithGroupSync();
		offset *= 2;
	}
	if (id.x < count.n) {
		int t1 = id.x;
		int t2 = wg_0[i];
		sb_2_store(t1, t2);
	}
}
cbuffer Count_block : register(b0) {
	int u_0_n : packoffset(c0);
};
[numthreads(256, 1, 1)]
void main(uint3 gid : SV_DispatchThreadID, uint3 lid : SV_GroupThreadID, uint lidx : SV_GroupIndex, uint3 grp : SV_GroupID) {
	cs(make_ComputeInput(int(gid.x), int(gid.y), int(gid.z), int(lid.x), int(lid.y), int(lid.z), int(lidx), int(grp.x), int(grp.y), int(grp.z), int(lidx) & 3, 4, int(lidx) >> 2, 64), make_Count(u_0_n));
}
