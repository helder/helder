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
struct GradientSize {
	int width;
	int height;
};
GradientSize make_GradientSize(int f0, int f1) {
	GradientSize s;
	s.width = f0;
	s.height = f1;
	return s;
}
RWTexture2D<float4> img_1 : register(u0);
void cs(ComputeInput id, GradientSize size) {
	if ((id.x >= size.width) || (id.y >= size.height)) {
		return;
	}
	img_1[uint2(id.x, id.y)] = float4(float(id.x * 8) / 255.0, float(id.y * 8) / 255.0, 0.5, 1.0);
}
cbuffer GradientSize_block : register(b0) {
	int u_0_width : packoffset(c0);
	int u_0_height : packoffset(c0.y);
};
[numthreads(8, 8, 1)]
void main(uint3 gid : SV_DispatchThreadID, uint3 lid : SV_GroupThreadID, uint lidx : SV_GroupIndex, uint3 grp : SV_GroupID) {
	cs(make_ComputeInput(int(gid.x), int(gid.y), int(gid.z), int(lid.x), int(lid.y), int(lid.z), int(lidx), int(grp.x), int(grp.y), int(grp.z)), make_GradientSize(u_0_width, u_0_height));
}
