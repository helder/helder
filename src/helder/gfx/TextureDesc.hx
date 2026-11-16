package helder.gfx;

// A 2D texture (or a 2D array, a cube: layers, cube), its rows top to bottom: the first row of data is v = 0
// (helder.gfx.shader.Texture2D), on every back end, a render target's too.
typedef TextureDesc = {
	width:Int,
	height:Int,
	// default RGBA8
	?format:TextureFormat,
	// mip levels, each half the size of the one before (default 1; 0: all of
	// them, down to 1x1); filled by Device.writeTexture or generateMips
	?mipLevels:Int,
	// a pass's colour or depth target (ColorTarget.texture,
	// DepthTarget.texture) that shaders then sample; its contents come from
	// passes and generateMips, not data (depth formats are always targets)
	?renderTarget:Bool,
	// samples a pixel: 1 (the default), or 4 for a multisampled render target
	// or depth texture (RGBA8, RGBA8Srgb, RGBA16F or a depth format; one mip
	// level, no data): drawn into by pipelines of 4 samples
	// (PipelineDesc.samples), never sampled; a pass's colour resolved into a
	// single-sampled texture at its end (ColorTarget.resolve)
	?samples:Int,
	// (Device.has(StorageTextures)) a compute stage writes it
	// (Encoder.setStorageTexture; RGBA8, RGBA16F or R32F, one level, one
	// sample), then shaders sample it
	?storage:Bool,
	// layers (default 1): a 2D array texture (Texture2DArray in shaders) of
	// layers images of the size, each with its mip levels; data and
	// Device.writeTexture fill one layer at a time; a pass draws into one
	// (ColorTarget.layer); not multisampled, not storage, not compressed
	?layers:Int,
	// a cube texture (TextureCube in shaders): six square layers, its faces
	// +x, -x, +y, -y, +z, -z (layers is 6 then, or left out); as a 2D array
	// otherwise
	?cube:Bool,
	// the first level's texels (width * height * format.texelSize bytes),
	// every layer's one after another
	?data:haxe.io.Bytes
}
