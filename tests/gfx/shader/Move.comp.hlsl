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
struct MoveStep {
	float dt;
	int count;
};
MoveStep make_MoveStep(float f0, int f1) {
	MoveStep s;
	s.dt = f0;
	s.count = f1;
	return s;
}
struct Particle {
	float4 pos;
	float4 vel;
};
Particle make_Particle(float4 f0, float4 f1) {
	Particle s;
	s.pos = f0;
	s.vel = f1;
	return s;
}
RWByteAddressBuffer sb_1 : register(u0);
Particle sb_1_load(int i) {
	uint at = uint(i) * 32u;
	return make_Particle(asfloat(sb_1.Load4(at + 0u)), asfloat(sb_1.Load4(at + 16u)));
}
void sb_1_store(int i, Particle v) {
	uint at = uint(i) * 32u;
	sb_1.Store4(at + 0u, asuint(v.pos));
	sb_1.Store4(at + 16u, asuint(v.vel));
}
RWByteAddressBuffer sb_2 : register(u1);
float4 sb_2_load(int i) {
	uint at = uint(i) * 16u;
	return asfloat(sb_2.Load4(at));
}
void sb_2_store(int i, float4 v) {
	uint at = uint(i) * 16u;
	sb_2.Store4(at + 0u, asuint(v));
}
RWByteAddressBuffer sb_3 : register(u2);
int sb_3_load(int i) {
	uint at = uint(i) * 4u;
	return asint(sb_3.Load(at));
}
void sb_3_store(int i, int v) {
	uint at = uint(i) * 4u;
	sb_3.Store(at + 0u, asuint(v));
}
int sb_3_atomicAdd(int i, int v) {
	int o;
	sb_3.InterlockedAdd(uint(i) * 4u, v, o);
	return o;
}
int sb_3_atomicMin(int i, int v) {
	int o;
	sb_3.InterlockedMin(uint(i) * 4u, v, o);
	return o;
}
int sb_3_atomicMax(int i, int v) {
	int o;
	sb_3.InterlockedMax(uint(i) * 4u, v, o);
	return o;
}
void cs(ComputeInput id, MoveStep step_2) {
	if (id.x >= step_2.count) {
		return;
	}
	Particle q = sb_1_load(id.x);
	Particle moved = make_Particle(float4(q.pos.xyz + (q.vel.xyz * step_2.dt), q.pos.w), q.vel);
	int t0 = id.x;
	sb_1_store(t0, moved);
	if (moved.pos.w > 0.5) {
		int k = sb_3_atomicAdd(1, 1);
		float4 t1 = moved.pos;
		sb_2_store(k, t1);
	}
}
cbuffer MoveStep_block : register(b0) {
	float u_0_dt : packoffset(c0);
	int u_0_count : packoffset(c0.y);
};
[numthreads(64, 1, 1)]
void main(uint3 gid : SV_DispatchThreadID, uint3 lid : SV_GroupThreadID, uint lidx : SV_GroupIndex, uint3 grp : SV_GroupID) {
	cs(make_ComputeInput(int(gid.x), int(gid.y), int(gid.z), int(lid.x), int(lid.y), int(lid.z), int(lidx), int(grp.x), int(grp.y), int(grp.z), int(lidx) & 3, 4, int(lidx) >> 2, 16), make_MoveStep(u_0_dt, u_0_count));
}
