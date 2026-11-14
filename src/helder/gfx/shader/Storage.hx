package helder.gfx.shader;

// A storage buffer a compute stage reads (ShaderMath.compute): its
// parameter, at a slot of its own (Encoder.setStorage), read by index
// (p.lights[i]); GLSL's readonly buffer block (std430), WGSL's
// var<storage, read>, MSL's const device T*, HLSL's ByteAddressBuffer. Its
// elements are Float, Int, Vec2, Vec4, Mat4 or a struct of those (Vec3 is
// 16 bytes in std430 and WGSL, 12 in HLSL: pack it into a Vec4; no Bool);
// laid out as std430 on every back end (ComputeShader.storage: the stride,
// StorageSlot.write and read the CPU's bytes). Shader code reads it in the
// compute function itself (not passed on to other functions); its length
// is not known to every back end (Metal's buffers have none): pass the
// count in a uniform block. On the CPU: the elements' array.
abstract Storage<T>(Array<T>) from Array<T> to Array<T> {
	public var length(get, never):Int;

	inline function get_length()
		return this.length;

	@:arrayAccess public inline function get(i:Int):T
		return this[i];
}
