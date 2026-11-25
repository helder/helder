enable subgroups;
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
fn cs(id: ComputeInput) {
	let i: i32 = id.localIndex;
	let t0: i32 = id.subgroupLane;
	wg_0[i] = t0;
	let t1: i32 = id.subgroupIndex;
	wg_1[i] = t1;
	let first: i32 = subgroupBroadcast(i, u32(0));
	let other: i32 = subgroupShuffle(i, u32(id.subgroupLane ^ 1));
	let back: i32 = subgroupShuffle(other, u32(id.subgroupLane ^ 1));
	let pair: vec2f = subgroupShuffle(vec2f(f32(i), 1.0), u32(id.subgroupLane ^ 1));
	let count: vec2f = subgroupAdd(vec2f(1.0, 0.0));
	workgroupBarrier();
	let ok: bool = ((((((((wg_0[first] == 0) && (wg_1[first] == id.subgroupIndex)) && (wg_0[other] == (id.subgroupLane ^ 1))) && (wg_1[other] == id.subgroupIndex)) && (back == i)) && (i32(pair.x) == other)) && (i32(count.x) == id.subgroupSize)) && (((id.subgroupIndex * id.subgroupSize) + id.subgroupLane) == i)) && ((id.subgroups * id.subgroupSize) == 64);
	let t2: i32 = id.x;
	let t3: i32 = select(0, 1, ok);
	atomicStore(&sb_0[t2], t3);
}
@compute @workgroup_size(64, 1, 1) fn main(@builtin(global_invocation_id) gid: vec3u, @builtin(local_invocation_id) lid: vec3u, @builtin(local_invocation_index) lidx: u32, @builtin(workgroup_id) grp: vec3u, @builtin(subgroup_invocation_id) sgl: u32, @builtin(subgroup_size) sgs: u32) {
	cs(ComputeInput(i32(gid.x), i32(gid.y), i32(gid.z), i32(lid.x), i32(lid.y), i32(lid.z), i32(lidx), i32(grp.x), i32(grp.y), i32(grp.z), i32(sgl), i32(sgs), i32(lidx / sgs), i32((64u + sgs - 1u) / sgs)));
}
