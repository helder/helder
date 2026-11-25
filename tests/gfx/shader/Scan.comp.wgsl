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
	subgroupLane: i32,
	subgroupSize: i32,
	subgroupIndex: i32,
	subgroups: i32,
}
struct ScanStep {
	offset: i32,
	count: i32,
}
@group(0) @binding(1) var<storage, read> sb_1: array<i32>;
@group(0) @binding(2) var<storage, read_write> sb_2: array<atomic<i32>>;
fn cs(id: ComputeInput, step_2: ScanStep) {
	let i: i32 = id.x;
	if (i >= step_2.count) {
		return;
	}
	var v: i32 = sb_1[i];
	if (i >= step_2.offset) {
		v += sb_1[i - step_2.offset];
	}
	atomicStore(&sb_2[i], v);
}
@group(0) @binding(0) var<uniform> u_0: ScanStep;
@compute @workgroup_size(64, 1, 1) fn main(@builtin(global_invocation_id) gid: vec3u, @builtin(local_invocation_id) lid: vec3u, @builtin(local_invocation_index) lidx: u32, @builtin(workgroup_id) grp: vec3u) {
	cs(ComputeInput(i32(gid.x), i32(gid.y), i32(gid.z), i32(lid.x), i32(lid.y), i32(lid.z), i32(lidx), i32(grp.x), i32(grp.y), i32(grp.z), i32(lidx) & 3, 4, i32(lidx) >> 2, 16), u_0);
}
