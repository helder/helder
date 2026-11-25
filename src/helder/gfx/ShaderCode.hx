package helder.gfx;

// The shader's source for each kind of back end: emitted by a shader
// definition (helder.gfx.shader.Shader: its vertexCode and fragmentCode, in
// the target's languages only), or written by hand. GL (also on
// WebGL2): GLSL ES 3.00 (`#version 300 es`), vertex inputs at
// `layout(location = n)`. Metal: MSL, the entry point named main0 (as
// SPIRV-Cross names it), vertex inputs `[[attribute(n)]]` of a
// `[[stage_in]]` struct. D3D11: HLSL (shader model 5.0, or 4.0 on older
// devices), the entry point named main, vertex inputs at semantic
// `TEXCOORD<n>` (as SPIRV-Cross names them). WebGPU: WGSL, the entry point
// named main, vertex inputs at `@location(n)`.
//
// Slots (Encoder.setUniforms, setTexture): a uniform block at slot n is
// GLSL's block named in bindings, MSL's [[buffer(n)]], HLSL's register(bn)
// and WGSL's @group(0) @binding(n); a texture at slot n is GLSL's sampler2D
// named in bindings (texture unit n), MSL's [[texture(n)]] and
// [[sampler(n)]], HLSL's register(tn) and register(sn), WGSL's @binding(n)
// (the texture) and @binding(16 + n) (its sampler).
//
// A compute stage (Stage.Compute): GLSL ES 3.10 (`#version 310 es`), MSL's
// kernel main0, HLSL's cs_5_0 main, WGSL's @compute main; its workgroup's
// size in workgroupSize (Metal gives it at each dispatch). A storage buffer
// at slot n is GLSL's buffer block at binding index (ShaderBinding.index),
// MSL's [[buffer(n)]], HLSL's register(tn) read or register(u<index>)
// written, WGSL's @binding(n); a storage texture GLSL's image unit index,
// MSL's [[texture(n)]], HLSL's register(u<index>), WGSL's @binding(n).
// A stage using subgroups has a second form, emulated: its subgroup
// operations made of workgroup memory and barriers, for the devices
// without them (Feature.Subgroups: Device.createShader takes it there;
// D3D11's cs_5_0 has only that one, its hlsl; on the CPU the same).
typedef ShaderCode = {
	?glsl:String,
	?msl:String,
	?hlsl:String,
	?wgsl:String,
	?bindings:Array<ShaderBinding>,
	// (a compute stage's) its workgroup's size: x, y, z
	?workgroupSize:Array<Int>,
	// (a compute stage's using subgroups) its texts without them
	// (emulatedForm: its code; its bindings and size the same)
	?emulated:{?glsl:String, ?msl:String, ?hlsl:String, ?wgsl:String}
	#if helder.soft
	// (the CPU back end's: -D helder.soft builds alone, where the shader
	// definitions emit it)
	, ?soft:SoftCode
	#end
}

// a compute stage's code in its second form (emulated's texts, the rest
// the same), else the code itself
function emulatedForm(c:ShaderCode):ShaderCode {
	var e = c.emulated;
	if (e == null) return c;
	return {
		glsl: e.glsl,
		msl: e.msl,
		hlsl: e.hlsl,
		wgsl: e.wgsl,
		bindings: c.bindings,
		workgroupSize: c.workgroupSize
		#if helder.soft
		, soft: c.soft
		#end
	};
}
