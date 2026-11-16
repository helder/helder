package helder.gfx.shader;

import helder.gfx.shader.Ir;

// WGSL (WebGPU). Entry points named main: vertex attributes and varyings
// at @location(n), the position @builtin(position); a uniform block is
// `@group(0) @binding(n) var<uniform> u_<n>: <Struct>` (WGSL's uniform
// layout is std140's for these types), a texture at slot n `tex_<n>:
// texture_2d<f32>` at binding n and its `smp_<n>: sampler` at 16 + n (a
// fragment stage's samples may be in non-uniform control flow: the
// derivative_uniformity diagnostic is off). Locals are let unless assigned;
// an assigned parameter is copied into a var.
//
// A compute stage's entry point is `@compute @workgroup_size(x, y, z) fn
// main`; a storage buffer at slot n is `@group(0) @binding(n)
// var<storage, read> sb_<n>: array<T>` (read_write when it is written; an
// RWStorage<Int> array<atomic<i32>>, read and written by atomicLoad and
// atomicStore), a storage texture `var img_<n>: texture_storage_2d<<format>,
// write>`.
class Wgsl extends Emit {
	override function type(t:SType):String
		return switch t {
			case TVoid: "";
			case TBool: "bool";
			case TInt: "i32";
			case TFloat: "f32";
			case TVec(n): 'vec${n}f';
			case TMat4: "mat4x4f";
			case TTexture: "texture_2d<f32>";
			case TTextureCube: "texture_cube<f32>";
			case TTextureArray: "texture_2d_array<f32>";
			case TStruct(s): s.name;
			case TArray(t, n): 'array<${type(t)}, $n>';
			case TStorage(TInt, true): "array<atomic<i32>>";
			case TStorage(t, _): 'array<${type(t)}>';
			case TImage(f): 'texture_storage_2d<${imageFormat(f)}, write>';
		}

	static function imageFormat(f:Int):String
		return f == 4 ? "rgba16float" : f == 5 ? "r32float" : "rgba8unorm";

	static function atomic(b:SExpr):Bool
		return b.t.match(TStorage(TInt, true));

	override function load(b:SExpr, i:SExpr):String
		return atomic(b) ? "atomicLoad(&" + operand(b) + "[" + expr(i) + "])" : super.load(b, i);

	override function store(b:SExpr, i:SExpr, v:SExpr):String
		return atomic(b) ? "atomicStore(&" + operand(b) + "[" + expr(i) + "], " + expr(v) + ");" : super.store(b, i, v);

	override function computeHeader(c:SCompute)
		header(c.entry);

	override function storage(c:SCompute) {
		for (s in c.storage)
			line('@group(0) @binding(${s.slot}) var<storage, ' + (s.write ? "read_write" : "read") + '> sb_${s.slot}: ${type(TStorage(s.element, s.write))};');
		for (m in c.images)
			line('@group(0) @binding(${m.slot}) var img_${m.slot}: ${type(TImage(m.format))};');
	}

	override function computeEntry(c:SCompute) {
		var e = c.entry;
		for (u in e.uniforms)
			line('@group(0) @binding(${u.binding}) var<uniform> u_${u.binding}: ${u.struct.name};');
		for (t in e.textures) {
			line('@group(0) @binding(${t.slot}) var tex_${t.slot}: ${type(Emit.textureType(t))};');
			line('@group(0) @binding(${16 + t.slot}) var smp_${t.slot}: sampler;');
		}
		var args = Emit.computeArgs(e, u -> 'u_${u.binding}', t -> 'tex_${t.slot}, smp_${t.slot}', s -> null, m -> null);
		var ids = "i32(gid.x), i32(gid.y), i32(gid.z), i32(lid.x), i32(lid.y), i32(lid.z), i32(lidx), i32(grp.x), i32(grp.y), i32(grp.z)";
		line('@compute @workgroup_size(${c.size.join(", ")}) fn main(@builtin(global_invocation_id) gid: vec3u, @builtin(local_invocation_id) lid: vec3u, @builtin(local_invocation_index) lidx: u32, @builtin(workgroup_id) grp: vec3u) {');
		line('\t${e.fn.name}(' + ['${e.input.name}($ids)'].concat(args).join(", ") + ");");
		line("}");
	}

	override function struct(s:SStruct) {
		line('struct ${s.name} {');
		for (f in s.fields)
			line('\t${f.name}: ${type(f.type)},');
		line("}");
	}

	override function func(f:SFunction) {
		var params = [for (p in f.params) if (!global(p.type)) p.assigned ? p.name + "_in: " + type(p.type) : param(p)].join(", ");
		line('fn ${f.name}($params)' + (f.ret == TVoid ? "" : " -> " + type(f.ret)) + " {");
		for (p in f.params)
			if (p.assigned) line('\tvar ${p.name}: ${type(p.type)} = ${p.name}_in;');
		body(f.body);
		line("}");
	}

	override function param(v:SVar):String
		return v.name + ": " + type(v.type) + (Textures.isTexture(v.type) ? ", " + v.name + "_smp: sampler" : "");

	override function arg(e:SExpr):String
		return Textures.isTexture(e.t) ? expr(e) + ", " + expr(e) + "_smp" : expr(e);

	override function declare(v:SVar, init:Null<SExpr>):String
		return (v.assigned || init == null ? "var " : "let ") + v.name + ": " + type(v.type) + (init == null ? "" : " = " + expr(init)) + ";";

	override function expr(e:SExpr):String
		return switch e.e {
			case EConvert(x): type(e.t) + "(" + expr(x) + ")";
			case _: super.expr(e);
		}

	override function binary(op:SBinop, a:SExpr, b:SExpr):String
		return switch op {
			// (a shift's amount is a u32)
			case Shl | Shr: operand(a) + " " + Emit.binop(op) + " u32(" + expr(b) + ")";
			case _: super.binary(op, a, b);
		}

	override function cond(c:SExpr, a:SExpr, b:SExpr):String
		return "select(" + expr(b) + ", " + expr(a) + ", " + expr(c) + ")";

	override function builtin(name:String, args:Array<SExpr>, t:SType):String
		return switch name {
			case "sample" | "sampleLevel" if (args[0].t == TTextureArray):
				// (a 2D array's layer: an index)
				var at = arg(args[0]) + ", " + expr(args[1]) + ", i32(round(" + expr(args[2]) + "))";
				name == "sampleLevel" ? "textureSampleLevel(" + at + ", " + expr(args[3]) + ")" : fragment ? "textureSample(" + at + ")" : "textureSampleLevel(" + at + ", 0.0)";
			case "sample" if (fragment): "textureSample(" + arg(args[0]) + ", " + expr(args[1]) + ")";
			case "sample": "textureSampleLevel(" + arg(args[0]) + ", " + expr(args[1]) + ", 0.0)";
			case "sampleLevel": "textureSampleLevel(" + arg(args[0]) + ", " + expr(args[1]) + ", " + expr(args[2]) + ")";
			case "atomicAdd" | "atomicMin" | "atomicMax": name + "(&" + operand(args[0]) + "[" + expr(args[1]) + "], " + expr(args[2]) + ")";
			case "textureStore": "textureStore(" + expr(args[0]) + ", vec2i(" + expr(args[1]) + ", " + expr(args[2]) + "), " + expr(args[3]) + ")";
			case _: super.builtin(name == "inversesqrt" ? "inverseSqrt" : name, args, t);
		}

	// (textureSample's derivatives are undefined in non-uniform control flow,
	// as in the other languages, rather than an error)
	override function header(e:SEntry)
		if (e.stage == Fragment && e.textures.length > 0) line("diagnostic(off, derivative_uniformity);");

	override function entry(p:SProgram, e:SEntry) {
		for (u in e.uniforms)
			line('@group(0) @binding(${u.binding}) var<uniform> u_${u.binding}: ${u.struct.name};');
		for (t in e.textures) {
			line('@group(0) @binding(${t.slot}) var tex_${t.slot}: ${type(Emit.textureType(t))};');
			line('@group(0) @binding(${16 + t.slot}) var smp_${t.slot}: sampler;');
		}
		var uniforms = [
			for (r in e.resources)
				switch r {
					case RUniform(u): 'u_${u.binding}';
					case RTexture(t): 'tex_${t.slot}, smp_${t.slot}';
					case RStorage(_) | RImage(_): throw "a render stage's storage";
				}
		];
		var vs = Emit.varyings(p), pos = Emit.position(p);
		function io(prefix:String, f:SField, loc:Int):String
			return (f.position ? "@builtin(position) " : '@location($loc) ') + prefix + f.name + ": " + type(f.type);
		if (e.stage == Vertex) {
			line("struct StageOut {");
			line('\t' + io("", pos, 0) + ",");
			for (i in 0...vs.length)
				line('\t' + io("", vs[i], i) + ",");
			line("}");
			var params = [for (i in 0...e.input.fields.length) io("in_", e.input.fields[i], i)];
			line('@vertex fn main(${params.join(", ")}) -> StageOut {');
			var args = [e.input.name + "(" + [for (f in e.input.fields) 'in_${f.name}'].join(", ") + ")"].concat(uniforms);
			line('\tlet r = ${e.fn.name}(${args.join(", ")});');
			line('\treturn StageOut(' + [for (f in [pos].concat(vs)) 'r.${f.name}'].join(", ") + ");");
			line("}");
		} else {
			var params = [io("in_", pos, 0)].concat([for (i in 0...vs.length) io("in_", vs[i], i)]);
			line('@fragment fn main(${params.join(", ")}) -> @location(0) vec4f {');
			var args = [e.input.name + "(" + [for (f in e.input.fields) 'in_${f.name}'].join(", ") + ")"].concat(uniforms);
			line('\treturn ${e.fn.name}(${args.join(", ")});');
			line("}");
		}
	}
}
