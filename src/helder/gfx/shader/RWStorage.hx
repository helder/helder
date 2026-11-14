package helder.gfx.shader;

// A storage buffer a compute stage reads and writes (p.particles[i] = v;
// Storage's otherwise): GLSL's buffer block, WGSL's var<storage,
// read_write>, MSL's device T*, HLSL's RWByteAddressBuffer (a UAV). Of
// Ints: atomicAdd, atomicMin, atomicMax (ShaderMath) and plain reads and
// writes (WGSL and MSL: atomic<i32>, read and written atomically, relaxed).
// The writes of a dispatch are seen by the next dispatches, draws (as a
// vertex, index or indirect buffer) and Device.readBuffer: the back end
// puts the barriers between them (GL's glMemoryBarrier).
abstract RWStorage<T>(Array<T>) from Array<T> to Array<T> {
	public var length(get, never):Int;

	inline function get_length()
		return this.length;

	@:arrayAccess public inline function get(i:Int):T
		return this[i];

	@:arrayAccess public inline function set(i:Int, v:T):T
		return this[i] = v;
}
