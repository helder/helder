package helder.gfx.soft;

// The context a shader's CPU form is called with (helder.gfx.shader.Soft's
// entries, whose offsets are these): the address of its input's lanes (a
// vertex's attributes, 64 bytes a location: 4 components of 4 lanes; a
// fragment's position, then each varying component's 16 bytes), of its
// output's (a vertex's position, then its varyings' components; a
// fragment's colour), the lanes to shade (bits), and the uniform blocks'
// and the texture bindings' addresses by slot. The entry returns the lanes
// left (a fragment's discarded ones taken out).
class Abi {
	public static inline var IN = 0;
	public static inline var OUT = 8;
	public static inline var MASK = 16;
	public static inline var UNIFORMS = 24;
	public static inline var TEXTURES = 24 + 8 * 16;
	public static inline var SIZE = 24 + 16 * 16;
	// the most varying components after the position a stage has here
	public static inline var MAX_VARYINGS = 60;
}
