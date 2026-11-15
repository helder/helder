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
};
struct ScanStep {
	int offset;
	int count;
};
layout(std430, binding = 1) readonly buffer sb_1_block {
	int data[];
} sb_1;
layout(std430, binding = 0) buffer sb_2_block {
	int data[];
} sb_2;
void cs(ComputeInput id, ScanStep step_2) {
	int i = id.x;
	if (i >= step_2.count) {
		return;
	}
	int v = sb_1.data[i];
	if (i >= step_2.offset) {
		v += sb_1.data[i - step_2.offset];
	}
	sb_2.data[i] = v;
}
layout(std140, binding = 0) uniform ScanStep_block {
	int offset;
	int count;
} u_0;
void main() {
	cs(ComputeInput(int(gl_GlobalInvocationID.x), int(gl_GlobalInvocationID.y), int(gl_GlobalInvocationID.z), int(gl_LocalInvocationID.x), int(gl_LocalInvocationID.y), int(gl_LocalInvocationID.z), int(gl_LocalInvocationIndex), int(gl_WorkGroupID.x), int(gl_WorkGroupID.y), int(gl_WorkGroupID.z)), ScanStep(u_0.offset, u_0.count));
}
