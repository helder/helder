#version 310 es
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
precision highp float;
precision highp int;
precision highp image2D;
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
struct GradientSize {
	int width;
	int height;
};
layout(binding = 0, rgba8) writeonly uniform highp image2D img_1;
void cs(ComputeInput id, GradientSize size) {
	if ((id.x >= size.width) || (id.y >= size.height)) {
		return;
	}
	imageStore(img_1, ivec2(id.x, id.y), vec4(float(id.x * 8) / 255.0, float(id.y * 8) / 255.0, 0.5, 1.0));
}
layout(std140, binding = 0) uniform GradientSize_block {
	int width;
	int height;
} u_0;
void main() {
	cs(ComputeInput(int(gl_GlobalInvocationID.x), int(gl_GlobalInvocationID.y), int(gl_GlobalInvocationID.z), int(gl_LocalInvocationID.x), int(gl_LocalInvocationID.y), int(gl_LocalInvocationID.z), int(gl_LocalInvocationIndex), int(gl_WorkGroupID.x), int(gl_WorkGroupID.y), int(gl_WorkGroupID.z), int(gl_LocalInvocationIndex) & 3, 4, int(gl_LocalInvocationIndex) >> 2, 16), GradientSize(u_0.width, u_0.height));
}
