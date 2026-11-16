package helder.gfx;

// A resource a shader reads at a slot, set at draw time (Encoder.setUniforms,
// setTexture; a compute stage's setStorage, setStorageTexture too): name is
// the GLSL's (a uniform block's or a sampler2D's), since GLSL ES 3.00 has no
// layout(binding) and the GL back end binds them by name
// (glUniformBlockBinding, glUniform1i; a compute stage's GLSL ES 3.10 has
// layout(binding)); WebGPU makes its bind group layout of the kinds. A
// shader definition lists them in ShaderCode.bindings.
typedef ShaderBinding = {
	name:String,
	slot:Int,
	kind:BindingKind,
	// a uniform block's size in bytes (std140); a storage buffer's stride
	?size:Int,
	// (a compute stage's) where the back end binds it when that is not its
	// slot: a storage buffer's binding in GL (the written ones first), a
	// written buffer's or storage texture's UAV register in D3D11, a storage
	// texture's image unit in GL
	?index:Int,
	// a storage texture's TextureFormat
	?format:Int,
	// a texture's: 0 (or none) a 2D texture (Texture2D), 1 a cube
	// (TextureCube), 2 a 2D array (Texture2DArray); WebGPU's view dimension
	?dimension:Int
}

enum abstract BindingKind(Int) {
	var Uniform;
	// a texture and its sampler
	var Texture;
	// (compute) a storage buffer the stage reads
	var Storage;
	// (compute) a storage buffer the stage reads and writes
	var StorageWrite;
	// (compute) a storage texture the stage writes
	var StorageTexture;
}
