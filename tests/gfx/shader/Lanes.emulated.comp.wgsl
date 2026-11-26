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
@group(0) @binding(0) var<storage, read_write> sb_0: array<atomic<i32>>;
var<workgroup> wg_0: array<i32, 64>;
var<workgroup> wg_1: array<i32, 64>;
var<workgroup> wg_2: array<i32, 64>;
var<workgroup> wg_3: array<vec2f, 64>;
fn cs(id: ComputeInput) {
	let i: i32 = id.localIndex;
	let t0: i32 = id.subgroupLane;
	wg_0[i] = t0;
	let t1: i32 = id.subgroupIndex;
	wg_1[i] = t1;
	wg_2[id.localIndex] = i;
	workgroupBarrier();
	let sg_0: i32 = wg_2[(id.localIndex & (-4)) + 0];
	workgroupBarrier();
	let first: i32 = sg_0;
	wg_2[id.localIndex] = i;
	workgroupBarrier();
	let sg_1: i32 = wg_2[(id.localIndex & (-4)) + ((id.subgroupLane ^ 1) & 3)];
	workgroupBarrier();
	let other: i32 = sg_1;
	wg_2[id.localIndex] = other;
	workgroupBarrier();
	let sg_2: i32 = wg_2[(id.localIndex & (-4)) + ((id.subgroupLane ^ 1) & 3)];
	workgroupBarrier();
	let back: i32 = sg_2;
	wg_3[id.localIndex] = vec2f(f32(i), 1.0);
	workgroupBarrier();
	let sg_3: vec2f = wg_3[(id.localIndex & (-4)) + ((id.subgroupLane ^ 1) & 3)];
	workgroupBarrier();
	let pair: vec2f = sg_3;
	wg_3[id.localIndex] = vec2f(1.0, 0.0);
	workgroupBarrier();
	let sg_4: vec2f = ((wg_3[id.localIndex & (-4)] + wg_3[(id.localIndex & (-4)) + 1]) + wg_3[(id.localIndex & (-4)) + 2]) + wg_3[(id.localIndex & (-4)) + 3];
	workgroupBarrier();
	let count: vec2f = sg_4;
	workgroupBarrier();
	let ok: bool = ((((((((wg_0[first] == 0) && (wg_1[first] == id.subgroupIndex)) && (wg_0[other] == (id.subgroupLane ^ 1))) && (wg_1[other] == id.subgroupIndex)) && (back == i)) && (i32(pair.x) == other)) && (i32(count.x) == id.subgroupSize)) && (((id.subgroupIndex * id.subgroupSize) + id.subgroupLane) == i)) && ((id.subgroups * id.subgroupSize) == 64);
	let t2: i32 = id.x;
	let t3: i32 = select(0, 1, ok);
	atomicStore(&sb_0[t2], t3);
}
@compute @workgroup_size(64, 1, 1) fn main(@builtin(global_invocation_id) gid: vec3u, @builtin(local_invocation_id) lid: vec3u, @builtin(local_invocation_index) lidx: u32, @builtin(workgroup_id) grp: vec3u) {
	cs(ComputeInput(i32(gid.x), i32(gid.y), i32(gid.z), i32(lid.x), i32(lid.y), i32(lid.z), i32(lidx), i32(grp.x), i32(grp.y), i32(grp.z), i32(lidx) & 3, 4, i32(lidx) >> 2, 16));
}
