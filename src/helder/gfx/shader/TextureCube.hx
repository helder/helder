package helder.gfx.shader;

import helder.math.*;
import haxe.io.Bytes;

// A cube texture and the sampler that reads it, as a shader's parameter
// (Texture2D's rules: a slot of its own, set with Encoder.setTexture; passed
// on to other functions only), read with ShaderMath's sample(t, dir) along
// a direction (of any length): GLSL's samplerCube, WGSL's texture_cube<f32>,
// MSL's texturecube<float>, HLSL's TextureCube. Its faces are the layers of
// a texture made with TextureDesc.cube, in the order +x, -x, +y, -y, +z, -z,
// each read as every API reads a cube's face (the face of the direction's
// largest component; on +x, u along -z and v along -y; -x: +z, -y; +y: +x,
// +z; -y: +x, -z; +z: +x, -y; -z: -x, -y; v = 0 the face's first row).
// In CPU code: six faces of size x size RGBA8 texels, one after another,
// read at the nearest texel.
class TextureCube {
	public final size:Int;
	public final texels:Bytes;

	public function new(size:Int, texels:Bytes) {
		this.size = size;
		this.texels = texels;
	}

	// the face (0 to 5) and its uv along a direction: x the face, y and z its uv
	public static function faceOf(d:Vec3):Vec3 {
		var ax = Math.abs(d.x), ay = Math.abs(d.y), az = Math.abs(d.z);
		var face = 0, sc = 0.0, tc = 0.0, ma = 1.0;
		if (ax >= ay && ax >= az) {
			ma = ax;
			if (d.x > 0) {
				face = 0;
				sc = -d.z;
			} else {
				face = 1;
				sc = d.z;
			}
			tc = -d.y;
		} else if (ay >= az) {
			ma = ay;
			sc = d.x;
			if (d.y > 0) {
				face = 2;
				tc = d.z;
			} else {
				face = 3;
				tc = -d.z;
			}
		} else {
			ma = az;
			tc = -d.y;
			if (d.z > 0) {
				face = 4;
				sc = d.x;
			} else {
				face = 5;
				sc = -d.x;
			}
		}
		if (ma == 0) ma = 1;
		return new Vec3(face, (sc / ma + 1) * 0.5, (tc / ma + 1) * 0.5);
	}

	// the texel along d, its channels 0..1 (sample on the CPU)
	public function read(d:Vec3):Vec4 {
		var f = faceOf(d);
		var x = Std.int(Math.min(f.y * size, size - 1)), y = Std.int(Math.min(f.z * size, size - 1));
		var p = 4 * ((Std.int(f.x) * size + y) * size + x);
		return new Vec4(texels.get(p) / 255, texels.get(p + 1) / 255, texels.get(p + 2) / 255, texels.get(p + 3) / 255);
	}
}
