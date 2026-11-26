package helder.gfx.shader;

import helder.math.*;
import haxe.io.Bytes;

// A texture a compute stage writes (ShaderMath.textureStore(t, x, y, c)),
// its parameter, at a slot of its own (Encoder.setStorageTexture; the
// texture made with TextureDesc.storage), write only: GLSL's writeonly
// image2D, WGSL's texture_storage_2d<..., write>, MSL's texture2d<float,
// access::write>, HLSL's RWTexture2D<float4> (a UAV). Its format is RGBA8,
// or the one its field's @:format names (@:format(RGBA16F), @:format(R32F)):
//
//   main: function(id:ComputeInput, p:{@:format(RGBA16F) var out:StorageTexture; ...}) ...
//
// Sampled after the dispatch as any texture (the back end's barriers). On
// the CPU: RGBA8 texels, rows top to bottom, each channel 0..1 stored.
class StorageTexture {
	public final width:Int;
	public final height:Int;
	public final texels:Bytes;

	public function new(width:Int, height:Int, ?texels:Bytes) {
		this.width = width;
		this.height = height;
		this.texels = texels ?? Bytes.alloc(width * height * 4);
	}

	// (textureStore on the CPU)
	public function store(x:Int, y:Int, c:Vec4) {
		if (x < 0 || y < 0 || x >= width || y >= height) return;
		var p = 4 * (y * width + x);
		inline function byte(f:Float):Int
			return Std.int(Math.min(Math.max(f, 0), 1) * 255 + 0.5);
		texels.set(p, byte(c.x));
		texels.set(p + 1, byte(c.y));
		texels.set(p + 2, byte(c.z));
		texels.set(p + 3, byte(c.w));
	}
}
