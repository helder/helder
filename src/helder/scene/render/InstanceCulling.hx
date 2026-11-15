package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Mat4;
import helder.gfx.shader.Vec4;
import helder.scene.render.CullShader;

// Instanced sets culled one instance at a time, opted in
// (renderer.use(new InstanceCulling(device))): each InstancedMesh's
// instances tested against the view (their mesh's bounds' sphere through
// each one's matrix) and each kept one drawn at its level (the set's
// levels: Lod's thresholds, a share of the view's height; without, its
// mesh), so a set of a hundred thousand rocks draws the few thousand in
// view, the far ones coarse. Where the device has compute and indirect
// draws (Device.has(Compute), has(Indirect)) it runs on the GPU
// (CullShader: a dispatch a set, the kept matrices appended to a buffer the
// draws read, their counts into indirect draws' arguments: no readback),
// else on the CPU (the same test, the kept ones' matrices uploaded by
// level). A set it does not take is drawn whole, as without it: one with
// custom data (its second buffer is not culled with it), a see-through one
// (its order is its own: Sprites), more than four levels or four
// primitives a level. Shadows draw every instance at the set's mesh.
// Nothing is allocated a frame but a set's buffers when first seen or
// grown.
class InstanceCulling implements RenderFeature implements RenderFeature.CullSource {
	public static inline var MAX_LEVELS = 4;
	public static inline var MAX_PRIMITIVES = 4;

	public final device:Device;
	// whether it culls on the GPU (else the CPU)
	public final gpu:Bool;
	// the last frame's instances kept and culled (the CPU's: the GPU's are
	// on the GPU), and its dispatches
	public var kept(default, null) = 0;
	public var culled(default, null) = 0;
	public var dispatches(default, null) = 0;

	var pipeline:Null<ComputePipeline> = null;
	final states = new Map<InstancedMesh, CullState>();
	final viewBytes = Bytes.alloc(CullInstances.params.view.block.size);
	final viewBlock:CullView = {
		planes: Filled.vec4s(6),
		depthRow: new Vec4(0, 0, 0, 0),
		sphere: new Vec4(0, 0, 0, 0),
		until: new Vec4(0, 0, 0, 0),
		scale: new Vec4(0, 0, 0, 0),
		count: 0,
		levels: 0,
		capacity: 0
	};
	final planes:Array<Float> = Filled.floats(24, 0.0);

	// gpu false: on the CPU even where the device has compute
	public function new(device:Device, gpu = true) {
		this.device = device;
		this.gpu = gpu && device.has(Compute) && device.has(Indirect);
		if (this.gpu) {
			pipeline = device.createComputePipeline(CullInstances.pipeline());
			InstancedMesh.storage = true;
		}
	}

	public function attach(renderer:Renderer)
		@:privateAccess renderer.cullSource = this;

	@:noCompletion public function takes(set:InstancedMesh):Bool {
		if (set.custom > 0 || Std.isOfType(set, Sprites)) return false;
		var levels = set.levels;
		if (levels != null && levels.length > MAX_LEVELS) return false;
		for (l in 0...(levels != null ? levels.length : 1)) {
			var mesh = levels != null ? levels[l].mesh : set.mesh;
			if (mesh.primitives.length > MAX_PRIMITIVES) return false;
			for (p in mesh.primitives)
				if (p.material.blend || p.skinned) return false;
		}
		return true;
	}

	@:noCompletion public function cull(enc:Encoder, renderer:Renderer, frame:Renderer.FrameInfo) {
		kept = culled = dispatches = 0;
		var vp = frame.viewProj;
		FrameLights.planesOf(vp, planes);
		var any = false;
		var sets = @:privateAccess renderer.sets, n = @:privateAccess renderer.setCount;
		for (k in 0...n) {
			var s = sets[k];
			if (!takes(s)) continue;
			var st = state(s);
			st.prepare(s, device);
			if (gpu) {
				if (!any) {
					// (the views' blocks first: they go into the frame's ring as the pass records)
					enc.beginCompute();
					enc.setComputePipeline(pipeline);
					any = true;
				}
				var v = viewBlock;
				v.depthRow = new Vec4(vp.c0.w, vp.c1.w, vp.c2.w, vp.c3.w);
				v.sphere = st.sphere;
				v.until = st.until;
				v.scale = new Vec4(Math.sqrt(vp.c0.y * vp.c0.y + vp.c1.y * vp.c1.y + vp.c2.y * vp.c2.y), 0, 0, 0);
				v.count = s.count;
				v.levels = st.levels;
				v.capacity = st.capacity;
				CullInstances.params.view.write(v, viewBytes);
				// (the planes into the block's first six vectors: an Array<Vec4> would box what it holds)
				for (i in 0...24)
					viewBytes.setFloat(i * 4, planes[i]);
				enc.setUniforms(CullInstances.params.view.block.binding, viewBytes);
				enc.setStorage(CullInstances.params.instances.binding, s.buffer);
				enc.setStorage(CullInstances.params.out.binding, st.out);
				enc.setStorage(CullInstances.params.args.binding, st.args);
				enc.dispatch(CullInstances.groups(s.count));
				dispatches++;
			} else
				cullCpu(s, st, vp);
		}
		if (any) enc.endCompute();
	}

	// (a set's instances culled and sorted by level on the CPU: CullShader's work)
	function cullCpu(s:InstancedMesh, st:CullState, vp:Mat4) {
		var data = s.data;
		var sx = st.sphere.x, sy = st.sphere.y, sz = st.sphere.z, sr = st.sphere.w;
		var scale = Math.sqrt(vp.c0.y * vp.c0.y + vp.c1.y * vp.c1.y + vp.c2.y * vp.c2.y);
		for (l in 0...MAX_LEVELS)
			st.counts[l] = 0;
		for (i in 0...s.count) {
			var o = i * InstancedMesh.STRIDE;
			var m00 = data.getFloat(o), m01 = data.getFloat(o + 4), m02 = data.getFloat(o + 8);
			var m10 = data.getFloat(o + 16), m11 = data.getFloat(o + 20), m12 = data.getFloat(o + 24);
			var m20 = data.getFloat(o + 32), m21 = data.getFloat(o + 36), m22 = data.getFloat(o + 40);
			var cx = m00 * sx + m10 * sy + m20 * sz + data.getFloat(o + 48);
			var cy = m01 * sx + m11 * sy + m21 * sz + data.getFloat(o + 52);
			var cz = m02 * sx + m12 * sy + m22 * sz + data.getFloat(o + 56);
			var r = sr * Math.sqrt(Math.max(m00 * m00 + m01 * m01 + m02 * m02, Math.max(m10 * m10 + m11 * m11 + m12 * m12, m20 * m20 + m21 * m21 + m22 * m22)));
			var inside = true;
			for (k in 0...6)
				if (planes[k * 4] * cx + planes[k * 4 + 1] * cy + planes[k * 4 + 2] * cz + planes[k * 4 + 3] < -r) {
					inside = false;
					break;
				}
			if (!inside) {
				culled++;
				continue;
			}
			var w = vp.c0.w * cx + vp.c1.w * cy + vp.c2.w * cz + vp.c3.w;
			var cover = w > 0.0001 ? r * scale / w : 1e9;
			var level = cover >= st.until.x ? 0 : cover >= st.until.y ? 1 : cover >= st.until.z ? 2 : cover >= st.until.w ? 3 : 4;
			if (level >= st.levels) {
				culled++;
				continue;
			}
			st.cpu.blit((level * st.capacity + st.counts[level]) * InstancedMesh.STRIDE, data, o, InstancedMesh.STRIDE);
			st.counts[level]++;
			kept++;
		}
		for (l in 0...st.levels)
			if (st.counts[l] > 0)
				device.writeBuffer(st.out, l * st.capacity * InstancedMesh.STRIDE, st.cpu, l * st.capacity * InstancedMesh.STRIDE, st.counts[l] * InstancedMesh.STRIDE);
	}

	@:noCompletion public function draw(enc:Encoder, set:InstancedMesh, primitive:Int, level:Int, slot:Int):Int {
		var st = states.get(set);
		if (st == null || level >= st.levels) return 0;
		enc.setVertexBuffer(slot, st.out, level * st.capacity * InstancedMesh.STRIDE);
		var p = (set.levels != null ? set.levels[level].mesh : set.mesh).primitives[primitive];
		if (gpu) {
			enc.drawIndexedIndirect(st.args, (level * MAX_PRIMITIVES + primitive) * 20);
			return 1;
		}
		if (st.counts[level] == 0) return 0;
		enc.drawIndexed(p.count, st.counts[level]);
		return 1;
	}

	function state(s:InstancedMesh):CullState {
		var st = states.get(s);
		if (st == null) states.set(s, st = new CullState());
		return st;
	}

	public function dispose() {
		for (st in states)
			st.dispose(device);
		states.clear();
	}
}

// (a set's culling: its output buffer (MAX_LEVELS parts of capacity
// instances), its draws' arguments, its levels' thresholds and its mesh's
// sphere; the CPU's counts and bytes)
class CullState {
	public var capacity = 0;
	public var levels = 1;
	public var out:Buffer = Buffer.NONE;
	public var args:Buffer = Buffer.NONE;
	public var argBytes = Bytes.alloc(InstanceCulling.MAX_LEVELS * InstanceCulling.MAX_PRIMITIVES * 20);
	public var cpu = Bytes.alloc(0);
	public final counts:Array<Int> = Filled.ints(InstanceCulling.MAX_LEVELS, 0);
	public var sphere = new Vec4(0, 0, 0, 0);
	public var until = new Vec4(0, 0, 0, 0);
	var device:Null<Device> = null;

	public function new() {}

	// its buffers for the set (made or grown to its capacity), its levels',
	// its draws' arguments reset (the GPU's: before the compute pass)
	public function prepare(s:InstancedMesh, device:Device) {
		var gpu = device.has(Compute) && device.has(Indirect) && InstancedMesh.storage;
		if (capacity < s.capacity || this.device != device) {
			dispose(device);
			this.device = device;
			capacity = s.capacity;
			var size = InstanceCulling.MAX_LEVELS * capacity * InstancedMesh.STRIDE;
			out = device.createBuffer({size: size, usage: gpu ? Storage : Vertex});
			if (gpu) args = device.createBuffer({size: argBytes.length, usage: Indirect}) else cpu = Bytes.alloc(size);
		}
		var ls = s.levels;
		levels = ls != null ? ls.length : 1;
		var b = (ls != null ? ls[0].mesh : s.mesh).bounds;
		if (b.isEmpty()) sphere = new Vec4(0, 0, 0, 1e9) else {
			var hx = (b.max.x - b.min.x) / 2, hy = (b.max.y - b.min.y) / 2, hz = (b.max.z - b.min.z) / 2;
			sphere = new Vec4((b.min.x + b.max.x) / 2, (b.min.y + b.max.y) / 2, (b.min.z + b.max.z) / 2, Math.sqrt(hx * hx + hy * hy + hz * hz));
		}
		until = new Vec4(untilOf(ls, 0), untilOf(ls, 1), untilOf(ls, 2), untilOf(ls, 3));
		if (gpu) {
			for (l in 0...InstanceCulling.MAX_LEVELS)
				for (j in 0...InstanceCulling.MAX_PRIMITIVES) {
					var o = (l * InstanceCulling.MAX_PRIMITIVES + j) * 20;
					var mesh = ls != null ? (l < ls.length ? ls[l].mesh : null) : (l == 0 ? s.mesh : null);
					argBytes.setInt32(o, mesh != null && j < mesh.primitives.length ? mesh.primitives[j].count : 0);
					argBytes.setInt32(o + 4, 0);
					argBytes.setInt32(o + 8, 0);
					argBytes.setInt32(o + 12, 0);
					argBytes.setInt32(o + 16, 0);
				}
			device.writeBuffer(args, 0, argBytes);
		}
	}

	// (level k's threshold: its until, 0 the last's by default; past the levels -1, never)
	static function untilOf(ls:Null<Array<Lod.LodLevel>>, k:Int):Float
		return ls == null ? (k == 0 ? 0 : -1) : k < ls.length ? Lod.untilOf(ls[k]) : -1;

	public function dispose(device:Device) {
		if (capacity > 0 && this.device != null) {
			this.device.destroyBuffer(out);
			if (args != Buffer.NONE) this.device.destroyBuffer(args);
		}
		args = Buffer.NONE;
		capacity = 0;
	}
}
