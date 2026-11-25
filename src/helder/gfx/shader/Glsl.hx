package helder.gfx.shader;

import helder.gfx.shader.Ir;

// GLSL ES 3.00 (GL and WebGL2). Vertex attributes at
// `layout(location = n) in`, varyings matched by name (v_<field>), the
// colour out_color; a uniform block is `layout(std140) uniform
// <Struct>_block`, a texture `uniform sampler2D tex_<slot>` (highp), their
// slots set through the API by those names (ES 3.00 has no
// layout(binding): ShaderCode.bindings). The conventions are the other
// languages' (Shaders): clip z from 0 to w (GL's from -w: the vertex stage
// maps it), the fragment position from the top left (GL's gl_FragCoord.y
// is from the bottom: flipped with the frame's height) and a texture's
// first row its top (in a pass into a texture, the position's y is
// flipped instead): u_target, which the back end sets, is (height, -1) in
// the frame, (0, 1) in a texture.
//
// A compute stage is GLSL ES 3.10 (GL ES 3.1's: `#version 310 es`, which
// has layout(binding)): its uniform blocks and textures at their slots'
// bindings and units, a storage buffer `layout(std430, binding = n)
// buffer sb_<slot>_block { T data[]; } sb_<slot>` (n: its index, the
// written ones first: GL ES 3.1 has 4 bindings at least), a storage
// texture `layout(binding = n, <format>) writeonly uniform highp image2D
// img_<slot>` (n: its image unit); its workgroup memory `shared T
// wg_<k>[n]`; its subgroups GL_KHR_shader_subgroup's (the extensions of the
// operations it calls, gl_SubgroupInvocationID and the others).
class Glsl extends Emit {
	// structs made through make_<Struct> functions instead of their
	// constructors (as Hlsl): the shader compiler of Android's emulator
	// (its GLES translator) rejects a struct constructor whose argument is a
	// constructor call ("Structure constructor arguments do not match
	// structure fields"); for the Android targets
	final makers:Bool;

	public function new(makers = false) {
		super();
		this.makers = makers;
	}

	override function struct(s:SStruct) {
		super.struct(s);
		if (!makers) return;
		line('${s.name} make_${s.name}(' + [for (i in 0...s.fields.length) type(s.fields[i].type) + " f" + i].join(", ") + ") {");
		line('\t${s.name} s;');
		for (i in 0...s.fields.length)
			line('\ts.${s.fields[i].name} = f$i;');
		line("\treturn s;");
		line("}");
	}

	override function construct(t:SType, args:Array<SExpr>):String
		return switch t {
			case TStruct(s) if (makers): 'make_${s.name}(' + [for (a in args) expr(a)].join(", ") + ")";
			case _: super.construct(t, args);
		}

	// a struct's constructor in the entry point
	inline function make(name:String):String
		return makers ? "make_" + name : name;

	override function header(e:SEntry) {
		line("#version 300 es");
		if (e.stage == Fragment) {
			line("precision highp float;");
			line("precision highp int;");
		}
		if (e.textures.length > 0) line("precision highp sampler2D;");
		precisions(e);
	}

	// (cubes and 2D arrays: samplerCube's default is lowp, sampler2DArray has none)
	function precisions(e:SEntry) {
		if (Lambda.exists(e.textures, t -> t.dimension == 1)) line("precision highp samplerCube;");
		if (Lambda.exists(e.textures, t -> t.dimension == 2)) line("precision highp sampler2DArray;");
	}

	override function type(t:SType):String
		return switch t {
			case TVoid: "void";
			case TBool: "bool";
			case TInt: "int";
			case TFloat: "float";
			case TVec(n): 'vec$n';
			case TMat4: "mat4";
			case TTexture: "sampler2D";
			case TTextureCube: "samplerCube";
			case TTextureArray: "sampler2DArray";
			case TStruct(s): s.name;
			case TArray(t, n): type(t) + "[" + n + "]";
			case TStorage(t, _): type(t);
			case TImage(_): "image2D";
			case TWorkgroup(t): type(t);
		}

	override function builtin(name:String, args:Array<SExpr>, t:SType):String
		return switch name {
			case "sample" | "sampleLevel" if (args[0].t == TTextureArray):
				// (a 2D array's uv and layer: one vec3)
				var at = "vec3(" + expr(args[1]) + ", " + expr(args[2]) + ")";
				name == "sampleLevel" ? "textureLod(" + expr(args[0]) + ", " + at + ", " + expr(args[3]) + ")" : fragment ? "texture(" + expr(args[0]) + ", " + at
					+ ")" : "textureLod(" + expr(args[0]) + ", " + at + ", 0.0)";
			case "sample" if (fragment): super.builtin("texture", args, t);
			case "sample": "textureLod(" + expr(args[0]) + ", " + expr(args[1]) + ", 0.0)";
			case "sampleLevel": super.builtin("textureLod", args, t);
			// (GLSL's two-argument atan)
			case "atan2": super.builtin("atan", args, t);
			case "atomicAdd" | "atomicMin" | "atomicMax": name + "(" + load(args[0], args[1]) + ", " + expr(args[2]) + ")";
			case "textureStore": "imageStore(" + expr(args[0]) + ", ivec2(" + expr(args[1]) + ", " + expr(args[2]) + "), " + expr(args[3]) + ")";
			// (the shared memory's writes made visible, then the workgroup waits)
			case "barrier": "memoryBarrierShared(); barrier()";
			case "subgroupBroadcast" | "subgroupShuffle": name + "(" + expr(args[0]) + ", uint(" + expr(args[1]) + "))";
			case _: super.builtin(name, args, t);
		}

	override function load(b:SExpr, i:SExpr):String
		return b.t.match(TWorkgroup(_)) ? super.load(b, i) : operand(b) + ".data[" + expr(i) + "]";

	override function store(b:SExpr, i:SExpr, v:SExpr):String
		return b.t.match(TWorkgroup(_)) ? super.store(b, i, v) : operand(b) + ".data[" + expr(i) + "] = " + expr(v) + ";";

	override function computeHeader(c:SCompute) {
		line("#version 310 es");
		if (native()) {
			var ops = Subgroups.used(c.entry.fn).ops;
			line("#extension GL_KHR_shader_subgroup_basic : require");
			for (x in [
				{ext: "vote", ops: ["subgroupAll", "subgroupAny"]},
				{ext: "arithmetic", ops: ["subgroupAdd", "subgroupMin", "subgroupMax"]},
				{ext: "ballot", ops: ["subgroupBroadcast"]},
				{ext: "shuffle", ops: ["subgroupShuffle"]}
			])
				if (Lambda.exists(x.ops, o -> ops.contains(o))) line('#extension GL_KHR_shader_subgroup_${x.ext} : require');
		}
		line('layout(local_size_x = ${c.size[0]}, local_size_y = ${c.size[1]}, local_size_z = ${c.size[2]}) in;');
		line("precision highp float;");
		line("precision highp int;");
		if (c.entry.textures.length > 0) line("precision highp sampler2D;");
		precisions(c.entry);
		if (c.images.length > 0) line("precision highp image2D;");
	}

	override function workgroup(c:SCompute)
		for (s in c.shared)
			line('shared ${type(s.element)} wg_${s.index}[${s.length}];');

	static function imageFormat(f:Int):String
		return f == 4 ? "rgba16f" : f == 5 ? "r32f" : "rgba8";

	override function storage(c:SCompute) {
		for (s in c.storage) {
			line('layout(std430, binding = ${s.index}) ' + (s.write ? "" : "readonly ") + 'buffer sb_${s.slot}_block {');
			line('\t${type(s.element)} data[];');
			line('} sb_${s.slot};');
		}
		for (m in c.images)
			line('layout(binding = ${m.index}, ${imageFormat(m.format)}) writeonly uniform highp image2D img_${m.slot};');
	}

	override function computeEntry(c:SCompute) {
		var e = c.entry;
		for (u in e.uniforms) {
			line('layout(std140, binding = ${u.binding}) uniform ${u.struct.name}_block {');
			for (f in u.struct.fields)
				line('\t${type(f.type)} ${f.name};');
			line('} u_${u.binding};');
		}
		for (t in e.textures)
			line('layout(binding = ${t.slot}) uniform ${type(Emit.textureType(t))} tex_${t.slot};');
		var args = Emit.computeArgs(e, u -> make(u.struct.name) + "(" + [for (f in u.struct.fields) 'u_${u.binding}.${f.name}'].join(", ") + ")", t -> 'tex_${t.slot}', s -> null, m -> null);
		var ids = "int(gl_GlobalInvocationID.x), int(gl_GlobalInvocationID.y), int(gl_GlobalInvocationID.z), int(gl_LocalInvocationID.x), int(gl_LocalInvocationID.y), int(gl_LocalInvocationID.z), int(gl_LocalInvocationIndex), int(gl_WorkGroupID.x), int(gl_WorkGroupID.y), int(gl_WorkGroupID.z)"
			+ subgroupIds(native() ? ["int(gl_SubgroupInvocationID)", "int(gl_SubgroupSize)", "int(gl_SubgroupID)", "int(gl_NumSubgroups)"] : null, "int(gl_LocalInvocationIndex)");
		line("void main() {");
		line('\t${e.fn.name}(' + [make(e.input.name) + "(" + ids + ")"].concat(args).join(", ") + ");");
		line("}");
	}

	override function entry(p:SProgram, e:SEntry) {
		for (u in e.uniforms) {
			line('layout(std140) uniform ${u.struct.name}_block {');
			for (f in u.struct.fields)
				line('\t${type(f.type)} ${f.name};');
			line('} u_${u.binding};');
		}
		for (t in e.textures)
			line('uniform ${type(Emit.textureType(t))} tex_${t.slot};');
		var args = [
			for (r in e.resources)
				switch r {
					case RUniform(u): make(u.struct.name) + "(" + [for (f in u.struct.fields) 'u_${u.binding}.${f.name}'].join(", ") + ")";
					case RTexture(t): 'tex_${t.slot}';
					case RStorage(_) | RImage(_): throw "a render stage's storage";
				}
		];
		if (e.stage == Vertex) {
			for (i in 0...e.input.fields.length) {
				var f = e.input.fields[i];
				line('layout(location = $i) in ${type(f.type)} in_${f.name};');
			}
			for (f in Emit.varyings(p))
				line('out ${type(f.type)} v_${f.name};');
			line("uniform vec2 u_target;");
			line("void main() {");
			args.unshift(make(e.input.name) + "(" + [for (f in e.input.fields) 'in_${f.name}'].join(", ") + ")");
			line('\t${p.varyings.name} r = ${e.fn.name}(${args.join(", ")});');
			// (clip z from 0..w to GL's -w..w; y upside down into a texture)
			var pos = 'r.${Emit.position(p).name}';
			line('\tgl_Position = vec4($pos.x, -u_target.y * $pos.y, 2.0 * $pos.z - $pos.w, $pos.w);');
			for (f in Emit.varyings(p))
				line('\tv_${f.name} = r.${f.name};');
			line("}");
		} else {
			for (f in Emit.varyings(p))
				line('in ${type(f.type)} v_${f.name};');
			line("uniform vec2 u_target;");
			line("out vec4 out_color;");
			line("void main() {");
			args.unshift(make(e.input.name) + "(" + [for (f in e.input.fields) f.position ? "vec4(gl_FragCoord.x, u_target.x + u_target.y * gl_FragCoord.y, gl_FragCoord.zw)" : 'v_${f.name}'].join(", ") + ")");
			line('\tout_color = ${e.fn.name}(${args.join(", ")});');
			line("}");
		}
	}
}
