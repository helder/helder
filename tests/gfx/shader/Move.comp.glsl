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
struct MoveStep {
	float dt;
	int count;
};
struct Particle {
	vec4 pos;
	vec4 vel;
};
layout(std430, binding = 0) buffer sb_1_block {
	Particle data[];
} sb_1;
layout(std430, binding = 1) buffer sb_2_block {
	vec4 data[];
} sb_2;
layout(std430, binding = 2) buffer sb_3_block {
	int data[];
} sb_3;
void cs(ComputeInput id, MoveStep step_2) {
	if (id.x >= step_2.count) {
		return;
	}
	Particle q = sb_1.data[id.x];
	Particle moved = Particle(vec4(q.pos.xyz + (q.vel.xyz * step_2.dt), q.pos.w), q.vel);
	int t0 = id.x;
	sb_1.data[t0] = moved;
	if (moved.pos.w > 0.5) {
		int k = atomicAdd(sb_3.data[1], 1);
		vec4 t1 = moved.pos;
		sb_2.data[k] = t1;
	}
}
layout(std140, binding = 0) uniform MoveStep_block {
	float dt;
	int count;
} u_0;
void main() {
	cs(ComputeInput(int(gl_GlobalInvocationID.x), int(gl_GlobalInvocationID.y), int(gl_GlobalInvocationID.z), int(gl_LocalInvocationID.x), int(gl_LocalInvocationID.y), int(gl_LocalInvocationID.z), int(gl_LocalInvocationIndex), int(gl_WorkGroupID.x), int(gl_WorkGroupID.y), int(gl_WorkGroupID.z), int(gl_LocalInvocationIndex) & 3, 4, int(gl_LocalInvocationIndex) >> 2, 16), MoveStep(u_0.dt, u_0.count));
}
