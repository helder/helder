package helder.gfx;

import helder.gfx.shader.Vec4;

// a pass's colour target: the frame's, or a render target
// (TextureDesc.renderTarget) of the pipelines' colorFormat; a multisampled
// texture (TextureDesc.samples) resolved at the pass's end into resolve, a
// single-sampled render target of its size and format; clear's the raw
// values the format stores (linear, any range)
typedef ColorTarget = {
	load:LoadOp,
	?clear:Vec4,
	?texture:Texture,
	?resolve:Texture,
	// the layer of texture drawn into (default 0): a cube's face (0 to 5:
	// +x, -x, +y, -y, +z, -z) or a 2D array's layer; its first mip level
	?layer:Int
}

class ClearValue {
	// t's clear (r, g, b, a), a new value only when it changed: a frame's
	// passes set again without allocating
	public static function set(t:ColorTarget, r:Float, g:Float, b:Float, a:Float) {
		var k = t.clear;
		if (k == null || k.x != r || k.y != g || k.z != b || k.w != a) t.clear = new Vec4(r, g, b, a);
	}
}
