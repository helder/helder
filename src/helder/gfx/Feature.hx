package helder.gfx;

// What a device has beyond the render stages every back end has
// (Device.has): the compute tier. WebGPU, Metal, D3D11 (feature level
// 11_0: cs_5_0) and GL ES 3.1 (Android's floor) have the first three, and
// some of them Subgroups; WebGL2 and a GL ES 3.0 context none, the render
// stages' path (helder.scene's fallbacks) staying theirs.
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
	// a compute stage's subgroup operations as the GPU's own (Metal's
	// simd_*, WebGPU's subgroups feature, GL's GL_KHR_shader_subgroup;
	// the CPU back end's lanes): where a device has none (D3D11, WebGPU or
	// GL without them) a stage using them takes its second form, made of
	// workgroup memory and barriers (ShaderCode.emulated), with the same
	// results
	var Subgroups = "subgroups";

	@:noCompletion @:from static macro function ofString(e:haxe.macro.Expr.ExprOf<String>):haxe.macro.Expr
		return helder.os.Literal.of(e);
}
