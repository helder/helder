package helder.gfx;

// Records a frame's passes: one per device, reused (no allocation per frame),
// into the device's commands, run at each pass's end (Device). What it
// records is counted in FrameCounts.
@:hxmc.unsafe(gc)
final class Encoder {
	final device:Device;

	@:allow(helder.gfx.Device) function new(device:Device)
		this.device = device;

	public function beginPass(p:PassDesc) {
		FrameCounts.passes++;
		var c = device.commands, k = p.colors[0], d = p.depth, clear = k.clear;
		c.begin(Replay.BEGIN_PASS);
		c.int((clear != null ? 1 : 0) | (d != null ? 2 : 0) | (d != null && d.clear != null ? 4 : 0));
		c.int(cast k.load);
		if (clear != null) {
			c.float(clear.r);
			c.float(clear.g);
			c.float(clear.b);
			c.float(clear.a);
		}
		c.int(k.texture == null ? 0 : k.texture.id());
		c.int(k.resolve == null ? 0 : k.resolve.id());
		c.int(k.layer == null ? Replay.NONE : k.layer);
		if (d != null) {
			c.int(cast d.load);
			if (d.clear != null) c.float(d.clear);
			c.int(d.texture == null ? 0 : d.texture.id());
		}
		c.int(p.queries == null ? 0 : p.queries.id());
		c.end();
	}

	public function setPipeline(p:Pipeline) {
		FrameCounts.pipelines++;
		two(Replay.SET_PIPELINE, p.id());
	}

	public function setVertexBuffer(slot:Int, b:Buffer, offset = 0) {
		FrameCounts.buffers++;
		three(Replay.SET_VERTEX_BUFFER, slot, b.id(), offset);
	}

	// the indices of drawIndexed, from offset bytes into b
	public function setIndexBuffer(b:Buffer, format:IndexFormat, offset = 0)
		three(Replay.SET_INDEX_BUFFER, b.id(), cast format, offset);

	// a uniform block's contents for the next draws, at its slot (a shader
	// class's uniforms: binding; its write<Block> fills the bytes): size bytes
	// of data from offset (default: the rest), copied into the frame's
	// uniform ring (at most UNIFORM_RING bytes a frame, each block 256-byte
	// aligned; Metal: at most 4 KB a block)
	public function setUniforms(slot:Int, data:haxe.io.Bytes, offset = 0, size = -1) {
		if (size < 0) size = data.length - offset;
		if (offset < 0 || size < 0 || offset + size > data.length) throw "helder.gfx: setUniforms: outside the data";
		var c = device.commands;
		c.begin(Replay.SET_UNIFORMS);
		c.int(slot);
		c.bytes(data, offset, size);
		c.end();
	}

	// a texture and the sampler that reads it, at its slot (a shader class's textures: binding)
	public function setTexture(slot:Int, t:Texture, s:Sampler) {
		FrameCounts.textures++;
		three(Replay.SET_TEXTURE, slot, t.id(), s.id());
	}

	public function draw(vertices:Int, instances = 1, firstVertex = 0) {
		FrameCounts.draws++;
		FrameCounts.instances += instances;
		three(Replay.DRAW, vertices, instances, firstVertex);
	}

	// count indices of the index buffer from firstIndex, each plus baseVertex
	public function drawIndexed(count:Int, instances = 1, firstIndex = 0, baseVertex = 0) {
		FrameCounts.draws++;
		FrameCounts.instances += instances;
		var c = device.commands;
		c.begin(Replay.DRAW_INDEXED);
		c.int(count);
		c.int(instances);
		c.int(firstIndex);
		c.int(baseVertex);
		c.end();
	}

	// (inline: run now; a render thread: handed what the pass recorded if it is free)
	public function endPass() {
		one(Replay.END_PASS);
		device.flush(true);
	}

	// the draws until endQuery counted by query k of the pass's set
	// (PassDesc.queries; one query at a time, each at most once a pass)
	public function beginQuery(k:Int)
		two(Replay.BEGIN_QUERY, k);

	public function endQuery()
		one(Replay.END_QUERY);

	// ---- the compute tier (Device.has(Compute))
	//
	// A compute pass, between render passes (not in one): its dispatches run
	// in order, each seeing what the ones before wrote, and the draws after
	// it see what they wrote (as vertex, index or indirect buffers, sampled
	// textures; GL: glMemoryBarrier after each dispatch, D3D11: its storage
	// unbound at endCompute, Metal: a compute encoder of serial dispatches,
	// WebGPU: its passes' usage scopes). setUniforms and setTexture bind the
	// stage's uniform blocks and textures in it, as they do the draws'.
	public function beginCompute() {
		FrameCounts.passes++;
		one(Replay.BEGIN_COMPUTE);
	}

	public function setComputePipeline(p:ComputePipeline) {
		FrameCounts.pipelines++;
		two(Replay.SET_COMPUTE_PIPELINE, p.id());
	}

	// a storage buffer (BufferUsage.Storage or Indirect), all of it, at its
	// slot (a ComputeShader's params.<name>.binding)
	public function setStorage(slot:Int, b:Buffer) {
		FrameCounts.buffers++;
		pair(Replay.SET_STORAGE, slot, b.id());
	}

	// a storage texture (TextureDesc.storage) the stage writes, at its slot
	// (Device.has(StorageTextures))
	public function setStorageTexture(slot:Int, t:Texture) {
		FrameCounts.textures++;
		pair(Replay.SET_STORAGE_TEXTURE, slot, t.id());
	}

	// x * y * z workgroups of the pipeline's size (ComputeShader.groups)
	public function dispatch(x:Int, y = 1, z = 1) {
		FrameCounts.dispatches++;
		three(Replay.DISPATCH, x, y, z);
	}

	// the workgroups three UInt32s of b at offset (a multiple of 4) say:
	// x, y, z (Device.has(Indirect))
	public function dispatchIndirect(b:Buffer, offset = 0) {
		FrameCounts.dispatches++;
		pair(Replay.DISPATCH_INDIRECT, b.id(), offset);
	}

	public function endCompute() {
		one(Replay.END_COMPUTE);
		device.flush(true);
	}

	// in a render pass, a draw whose counts four UInt32s of b at offset say
	// (a multiple of 4): vertices, instances, the first vertex, the first
	// instance (0: GL ES and WebGPU without indirect-first-instance have no
	// other) (Device.has(Indirect))
	public function drawIndirect(b:Buffer, offset = 0) {
		FrameCounts.draws++;
		pair(Replay.DRAW_INDIRECT, b.id(), offset);
	}

	// ... of the index buffer (set at offset 0 on GL): five UInt32s, the
	// indices, instances, the first index, the base vertex (an Int32), the
	// first instance (0)
	public function drawIndexedIndirect(b:Buffer, offset = 0) {
		FrameCounts.draws++;
		pair(Replay.DRAW_INDEXED_INDIRECT, b.id(), offset);
	}

	inline function one(op:Int) {
		var c = device.commands;
		c.begin(op);
		c.end();
	}

	inline function two(op:Int, a:Int) {
		var c = device.commands;
		c.begin(op);
		c.int(a);
		c.end();
	}

	inline function pair(op:Int, a:Int, b:Int) {
		var c = device.commands;
		c.begin(op);
		c.int(a);
		c.int(b);
		c.end();
	}

	inline function three(op:Int, a:Int, b:Int, d:Int) {
		var c = device.commands;
		c.begin(op);
		c.int(a);
		c.int(b);
		c.int(d);
		c.end();
	}

	// the uniform ring's size per frame in flight
	public static inline var UNIFORM_RING = 256 * 1024;
}
