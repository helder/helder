package helder.gfx;

// a pass's colour target: the frame's, or a render target
// (TextureDesc.renderTarget) of the pipelines' colorFormat; a multisampled
// texture (TextureDesc.samples) resolved at the pass's end into resolve, a
// single-sampled render target of its size and format
typedef ColorTarget = {
	load:LoadOp,
	?clear:Color,
	?texture:Texture,
	?resolve:Texture,
	// the layer of texture drawn into (default 0): a cube's face (0 to 5:
	// +x, -x, +y, -y, +z, -z) or a 2D array's layer; its first mip level
	?layer:Int,
	// a multisampled texture's samples kept past the resolve, to be drawn
	// into again (load Load); else they may be let go (Metal's)
	?keep:Bool
}
