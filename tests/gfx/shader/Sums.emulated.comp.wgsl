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
struct Count {
	n: i32,
}
@group(0) @binding(1) var<storage, read> sb_1: array<f32>;
@group(0) @binding(2) var<storage, read_write> sb_2: array<f32>;
var<workgroup> wg_0: array<f32, 256>;
var<workgroup> wg_1: array<f32, 256>;
fn cs(id: ComputeInput, count: Count) {
	var v: f32 = select(0.0, sb_1[id.x], id.x < count.n);
	wg_1[id.localIndex] = v;
	workgroupBarrier();
	let sg_0: f32 = ((wg_1[id.localIndex & (-4)] + wg_1[(id.localIndex & (-4)) + 1]) + wg_1[(id.localIndex & (-4)) + 2]) + wg_1[(id.localIndex & (-4)) + 3];
	workgroupBarrier();
	v = sg_0;
	if (id.subgroupLane == 0) {
		let t0: i32 = id.subgroupIndex;
		wg_0[t0] = v;
	}
	workgroupBarrier();
	if (id.localIndex == 0) {
		var s: f32 = 0.0;
		var t: i32 = 0;
		let t_2: i32 = id.subgroups;
		while (t < t_2) {
			let k: i32 = t;
			t += 1;
			s += wg_0[k];
		}
		let t1: i32 = id.groupX;
		sb_2[t1] = s;
	}
}
@group(0) @binding(0) var<uniform> u_0: Count;
@compute @workgroup_size(256, 1, 1) fn main(@builtin(global_invocation_id) gid: vec3u, @builtin(local_invocation_id) lid: vec3u, @builtin(local_invocation_index) lidx: u32, @builtin(workgroup_id) grp: vec3u) {
	cs(ComputeInput(i32(gid.x), i32(gid.y), i32(gid.z), i32(lid.x), i32(lid.y), i32(lid.z), i32(lidx), i32(grp.x), i32(grp.y), i32(grp.z), i32(lidx) & 3, 4, i32(lidx) >> 2, 64), u_0);
}
