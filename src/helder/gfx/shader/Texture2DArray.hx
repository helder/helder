package helder.gfx.shader;

import helder.math.*;
import haxe.io.Bytes;

// A 2D array texture and the sampler that reads it, as a shader's
// parameter (Texture2D's rules: a slot of its own, set with
// Encoder.setTexture; passed on to other functions only), read with
// ShaderMath's sample(t, uv, layer) (the layer rounded to the nearest, held
// in the array): GLSL's sampler2DArray, WGSL's texture_2d_array<f32>, MSL's
// texture2d_array<float>, HLSL's Texture2DArray. Its layers are a texture
// made with TextureDesc.layers. In CPU code: layers of width x height RGBA8
// texels, one after another, rows top to bottom, read at the nearest texel,
// repeating.
class Texture2DArray {
	public final width:Int;
	public final height:Int;
	public final layers:Int;
	public final texels:Bytes;

	public function new(width:Int, height:Int, layers:Int, texels:Bytes) {
		this.width = width;
		this.height = height;
		this.layers = layers;
		this.texels = texels;
	}

	// the texel at uv of a layer, its channels 0..1 (sample on the CPU)
	public function read(uv:Vec2, layer:Float):Vec4 {
		var x = Std.int((uv.x - Math.ffloor(uv.x)) * width), y = Std.int((uv.y - Math.ffloor(uv.y)) * height);
		var l = Std.int(Math.min(Math.max(Math.fround(layer), 0), layers - 1));
		var p = 4 * ((l * height + y) * width + x);
		return new Vec4(texels.get(p) / 255, texels.get(p + 1) / 255, texels.get(p + 2) / 255, texels.get(p + 3) / 255);
	}
}
