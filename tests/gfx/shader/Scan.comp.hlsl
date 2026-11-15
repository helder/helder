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
};
ComputeInput make_ComputeInput(int f0, int f1, int f2, int f3, int f4, int f5, int f6, int f7, int f8, int f9) {
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
	return s;
}
struct ScanStep {
	int offset;
	int count;
};
ScanStep make_ScanStep(int f0, int f1) {
	ScanStep s;
	s.offset = f0;
	s.count = f1;
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
void cs(ComputeInput id, ScanStep step_2) {
	int i = id.x;
	if (i >= step_2.count) {
		return;
	}
	int v = sb_1_load(i);
	if (i >= step_2.offset) {
		v += sb_1_load(i - step_2.offset);
	}
	sb_2_store(i, v);
}
cbuffer ScanStep_block : register(b0) {
	int u_0_offset : packoffset(c0);
	int u_0_count : packoffset(c0.y);
};
[numthreads(64, 1, 1)]
void main(uint3 gid : SV_DispatchThreadID, uint3 lid : SV_GroupThreadID, uint lidx : SV_GroupIndex, uint3 grp : SV_GroupID) {
	cs(make_ComputeInput(int(gid.x), int(gid.y), int(gid.z), int(lid.x), int(lid.y), int(lid.z), int(lidx), int(grp.x), int(grp.y), int(grp.z)), make_ScanStep(u_0_offset, u_0_count));
}
