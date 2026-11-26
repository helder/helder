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
struct MoveStep {
	dt: f32,
	count: i32,
}
struct Particle {
	pos: vec4f,
	vel: vec4f,
}
@group(0) @binding(1) var<storage, read_write> sb_1: array<Particle>;
@group(0) @binding(2) var<storage, read_write> sb_2: array<vec4f>;
@group(0) @binding(3) var<storage, read_write> sb_3: array<atomic<i32>>;
fn cs(id: ComputeInput, step_2: MoveStep) {
	if (id.x >= step_2.count) {
		return;
	}
	let q: Particle = sb_1[id.x];
	let moved: Particle = Particle(vec4f(q.pos.xyz + (q.vel.xyz * step_2.dt), q.pos.w), q.vel);
	let t0: i32 = id.x;
	sb_1[t0] = moved;
	if (moved.pos.w > 0.5) {
		let k: i32 = atomicAdd(&sb_3[1], 1);
		let t1: vec4f = moved.pos;
		sb_2[k] = t1;
	}
}
@group(0) @binding(0) var<uniform> u_0: MoveStep;
@compute @workgroup_size(64, 1, 1) fn main(@builtin(global_invocation_id) gid: vec3u, @builtin(local_invocation_id) lid: vec3u, @builtin(local_invocation_index) lidx: u32, @builtin(workgroup_id) grp: vec3u) {
	cs(ComputeInput(i32(gid.x), i32(gid.y), i32(gid.z), i32(lid.x), i32(lid.y), i32(lid.z), i32(lidx), i32(grp.x), i32(grp.y), i32(grp.z), i32(lidx) & 3, 4, i32(lidx) >> 2, 16), u_0);
}
