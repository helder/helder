package helder.gfx;

// Records a frame's passes: one per device, reused (no allocation per frame).
// What it records is counted in FrameCounts.
final class Encoder {
	final impl:Impl;

	@:allow(helder.gfx.Device) function new(impl:Impl)
		this.impl = impl;

	public inline function beginPass(p:PassDesc) {
		FrameCounts.passes++;
		impl.beginPass(p);
	}

	public inline function setPipeline(p:Pipeline) {
		FrameCounts.pipelines++;
		impl.setPipeline(p.id());
	}

	public inline function setVertexBuffer(slot:Int, b:Buffer, offset = 0) {
		FrameCounts.buffers++;
		impl.setVertexBuffer(slot, b.id(), offset);
	}

	// the indices of drawIndexed, from offset bytes into b
	public inline function setIndexBuffer(b:Buffer, format:IndexFormat, offset = 0)
		impl.setIndexBuffer(b.id(), format, offset);

	// a uniform block's contents for the next draws, at its slot (a shader
	// class's uniforms: binding; its write<Block> fills the bytes): size bytes
	// of data from offset (default: the rest), copied into the frame's
	// uniform ring (at most UNIFORM_RING bytes a frame, each block 256-byte
	// aligned; Metal: at most 4 KB a block)
	public inline function setUniforms(slot:Int, data:haxe.io.Bytes, offset = 0, size = -1)
		impl.setUniforms(slot, data, offset, size < 0 ? data.length - offset : size);

	// a texture and the sampler that reads it, at its slot (a shader class's textures: binding)
	public inline function setTexture(slot:Int, t:Texture, s:Sampler) {
		FrameCounts.textures++;
		impl.setTexture(slot, t.id(), s.id());
	}

	public inline function draw(vertices:Int, instances = 1, firstVertex = 0) {
		FrameCounts.draws++;
		FrameCounts.instances += instances;
		impl.draw(vertices, instances, firstVertex);
	}

	// count indices of the index buffer from firstIndex, each plus baseVertex
	public inline function drawIndexed(count:Int, instances = 1, firstIndex = 0, baseVertex = 0) {
		FrameCounts.draws++;
		FrameCounts.instances += instances;
		impl.drawIndexed(count, instances, firstIndex, baseVertex);
	}

	public inline function endPass()
		impl.endPass();

	// the draws until endQuery counted by query k of the pass's set
	// (PassDesc.queries; one query at a time, each at most once a pass)
	public inline function beginQuery(k:Int)
		impl.beginQuery(k);

	public inline function endQuery()
		impl.endQuery();

	// ---- the compute tier (Device.has(Compute))
	//
	// A compute pass, between render passes (not in one): its dispatches run
	// in order, each seeing what the ones before wrote, and the draws after
	// it see what they wrote (as vertex, index or indirect buffers, sampled
	// textures; GL: glMemoryBarrier after each dispatch, D3D11: its storage
	// unbound at endCompute, Metal: a compute encoder of serial dispatches,
	// WebGPU: its passes' usage scopes). setUniforms and setTexture bind the
	// stage's uniform blocks and textures in it, as they do the draws'.
	public inline function beginCompute() {
		FrameCounts.passes++;
		impl.beginCompute();
	}

	public inline function setComputePipeline(p:ComputePipeline) {
		FrameCounts.pipelines++;
		impl.setComputePipeline(p.id());
	}

	// a storage buffer (BufferUsage.Storage or Indirect), all of it, at its
	// slot (a ComputeShader's params.<name>.binding)
	public inline function setStorage(slot:Int, b:Buffer) {
		FrameCounts.buffers++;
		impl.setStorage(slot, b.id());
	}

	// a storage texture (TextureDesc.storage) the stage writes, at its slot
	// (Device.has(StorageTextures))
	public inline function setStorageTexture(slot:Int, t:Texture) {
		FrameCounts.textures++;
		impl.setStorageTexture(slot, t.id());
	}

	// x * y * z workgroups of the pipeline's size (ComputeShader.groups)
	public inline function dispatch(x:Int, y = 1, z = 1) {
		FrameCounts.dispatches++;
		impl.dispatch(x, y, z);
	}

	// the workgroups three UInt32s of b at offset (a multiple of 4) say:
	// x, y, z (Device.has(Indirect))
	public inline function dispatchIndirect(b:Buffer, offset = 0) {
		FrameCounts.dispatches++;
		impl.dispatchIndirect(b.id(), offset);
	}

	public inline function endCompute()
		impl.endCompute();

	// in a render pass, a draw whose counts four UInt32s of b at offset say
	// (a multiple of 4): vertices, instances, the first vertex, the first
	// instance (0: GL ES and WebGPU without indirect-first-instance have no
	// other) (Device.has(Indirect))
	public inline function drawIndirect(b:Buffer, offset = 0) {
		FrameCounts.draws++;
		impl.drawIndirect(b.id(), offset);
	}

	// ... of the index buffer (set at offset 0 on GL): five UInt32s, the
	// indices, instances, the first index, the base vertex (an Int32), the
	// first instance (0)
	public inline function drawIndexedIndirect(b:Buffer, offset = 0) {
		FrameCounts.draws++;
		impl.drawIndexedIndirect(b.id(), offset);
	}

	// the uniform ring's size per frame in flight
	public static inline var UNIFORM_RING = 256 * 1024;
}
