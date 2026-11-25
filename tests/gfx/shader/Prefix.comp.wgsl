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
@group(0) @binding(1) var<storage, read> sb_1: array<i32>;
@group(0) @binding(2) var<storage, read_write> sb_2: array<atomic<i32>>;
var<workgroup> wg_0: array<i32, 256>;
fn cs(id: ComputeInput, count: Count) {
	let i: i32 = id.localIndex;
	let t0: i32 = select(0, sb_1[id.x], id.x < count.n);
	wg_0[i] = t0;
	workgroupBarrier();
	var offset: i32 = 1;
	while (offset < 256) {
		var v: i32 = wg_0[i];
		if (i >= offset) {
			v += wg_0[i - offset];
		}
		workgroupBarrier();
		wg_0[i] = v;
		workgroupBarrier();
		offset *= 2;
	}
	if (id.x < count.n) {
		let t1: i32 = id.x;
		let t2: i32 = wg_0[i];
		atomicStore(&sb_2[t1], t2);
	}
}
@group(0) @binding(0) var<uniform> u_0: Count;
@compute @workgroup_size(256, 1, 1) fn main(@builtin(global_invocation_id) gid: vec3u, @builtin(local_invocation_id) lid: vec3u, @builtin(local_invocation_index) lidx: u32, @builtin(workgroup_id) grp: vec3u) {
	cs(ComputeInput(i32(gid.x), i32(gid.y), i32(gid.z), i32(lid.x), i32(lid.y), i32(lid.z), i32(lidx), i32(grp.x), i32(grp.y), i32(grp.z), i32(lidx) & 3, 4, i32(lidx) >> 2, 64), u_0);
}
