package helder.gfx;

// What a device has beyond the render stages every back end has
// (Device.has): the compute tier. WebGPU, Metal, D3D11 (feature level
// 11_0: cs_5_0) and GL ES 3.1 (Android's floor) have all three; WebGL2 and
// a GL ES 3.0 context none, the render stages' path (helder.scene's
// fallbacks) staying theirs.
enum abstract Feature(String) {
	// compute stages (ShaderMath.compute, Device.createComputePipeline,
	// Encoder.beginCompute ... dispatch), storage buffers (BufferUsage.Storage,
	// Encoder.setStorage) and Device.readBuffer
	var Compute = "compute";
	// storage textures a compute stage writes (TextureDesc.storage,
	// Encoder.setStorageTexture): RGBA8, RGBA16F, R32F
	var StorageTextures = "storage-textures";
	// draws and dispatches whose counts a buffer holds (BufferUsage.Indirect:
	// Encoder.drawIndirect, drawIndexedIndirect, dispatchIndirect), written
	// by a compute stage
	var Indirect = "indirect";
}
