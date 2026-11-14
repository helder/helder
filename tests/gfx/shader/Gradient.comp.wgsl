struct ComputeInput {
	x: i32,
	y: i32,
	z: i32,
	localX: i32,
	localY: i32,
	localZ: i32,
	localIndex: i32,
	groupX: i32,
	groupY: i32,
	groupZ: i32,
}
struct GradientSize {
	width: i32,
	height: i32,
}
@group(0) @binding(1) var img_1: texture_storage_2d<rgba8unorm, write>;
fn cs(id: ComputeInput, size: GradientSize) {
	if ((id.x >= size.width) || (id.y >= size.height)) {
		return;
	}
	textureStore(img_1, vec2i(id.x, id.y), vec4f(f32(id.x * 8) / 255.0, f32(id.y * 8) / 255.0, 0.5, 1.0));
}
@group(0) @binding(0) var<uniform> u_0: GradientSize;
@compute @workgroup_size(8, 8, 1) fn main(@builtin(global_invocation_id) gid: vec3u, @builtin(local_invocation_id) lid: vec3u, @builtin(local_invocation_index) lidx: u32, @builtin(workgroup_id) grp: vec3u) {
	cs(ComputeInput(i32(gid.x), i32(gid.y), i32(gid.z), i32(lid.x), i32(lid.y), i32(lid.z), i32(lidx), i32(grp.x), i32(grp.y), i32(grp.z)), u_0);
}
