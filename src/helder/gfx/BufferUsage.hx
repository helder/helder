package helder.gfx;

enum abstract BufferUsage(Int) {
	var Vertex;
	var Index;
	var Uniform;
	// (Device.has(Compute)) a storage buffer a compute stage reads or writes
	// (Encoder.setStorage), also a vertex or index buffer of draws
	// (setVertexBuffer, setIndexBuffer: particles a compute stage moved), read
	// back by Device.readBuffer
	var Storage;
	// (Device.has(Indirect)) the arguments of indirect draws and dispatches
	// (Encoder.drawIndirect, drawIndexedIndirect, dispatchIndirect: UInt32s),
	// also a storage buffer a compute stage writes them into
	var Indirect;
}
