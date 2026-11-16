package helder.gfx.shader;

import helder.gfx.shader.Ir;

// HLSL (D3D11, shader model 4.0 and 5.0). Entry points named main: vertex
// attributes at TEXCOORD<n>, the varyings TEXCOORD<n> but the position
// (SV_Position), the colour SV_Target; a uniform block is a cbuffer at
// register(b<n>), its fields u_<n>_<field> at their std140 offsets; a
// texture at slot n `Texture2D tex_<n> : register(t<n>)` and its
// `SamplerState smp_<n> : register(s<n>)`. HLSL
// has no struct constructors: make_<Struct> functions. A matrix is stored
// transposed (float4x4's rows are the columns: row_major in a cbuffer), so
// that the columns' memory order is GLSL's: m * v is mul(v, m), a * b is
// mul(b, a), a column is m[i].
//
// A compute stage's entry point is `[numthreads(x, y, z)] void main` (cs_5_0);
// a storage buffer at slot n is `ByteAddressBuffer sb_<n> : register(tn)`
// (read) or `RWByteAddressBuffer sb_<n> : register(uk)` (written: a UAV, k
// its index among the stage's UAVs), its elements loaded and stored at
// their std430 offsets by sb_<n>_load and sb_<n>_store (asfloat, asuint),
// its Ints' atomics sb_<n>_atomicAdd ... (Interlocked*); a storage texture
// `RWTexture2D<float4> img_<n> : register(uk)` (R32F: float).
class Hlsl extends Emit {
	override function type(t:SType):String
		return switch t {
			case TVoid: "void";
			case TBool: "bool";
			case TInt: "int";
			case TFloat: "float";
			case TVec(n): 'float$n';
			case TMat4: "float4x4";
			case TTexture: "Texture2D";
			case TTextureCube: "TextureCube";
			case TTextureArray: "Texture2DArray";
			case TStruct(s): s.name;
			case TArray(t, _): type(t);
			case TStorage(_, w): w ? "RWByteAddressBuffer" : "ByteAddressBuffer";
			case TImage(f): f == 5 ? "RWTexture2D<float>" : "RWTexture2D<float4>";
		}

	override function load(b:SExpr, i:SExpr):String
		return operand(b) + "_load(" + expr(i) + ")";

	override function store(b:SExpr, i:SExpr, v:SExpr):String
		return operand(b) + "_store(" + expr(i) + ", " + expr(v) + ");";

	override function computeHeader(c:SCompute) {}

	// each storage buffer and its element's loads and stores (and atomics: written Ints)
	override function storage(c:SCompute) {
		for (s in c.storage) {
			var b = 'sb_${s.slot}';
			line(s.write ? 'RWByteAddressBuffer $b : register(u${s.index});' : 'ByteAddressBuffer $b : register(t${s.slot});');
			var fields:Array<{name:Null<String>, type:SType, offset:Int}> = switch s.element {
				case TStruct(st): [for (i in 0...st.fields.length) {name: st.fields[i].name, type: st.fields[i].type, offset: s.offsets[i]}];
				case t: [{name: null, type: t, offset: 0}];
			}
			function loadOf(t:SType, at:String):String
				return switch t {
					case TInt: 'asint($b.Load($at))';
					case TFloat: 'asfloat($b.Load($at))';
					case TVec(2): 'asfloat($b.Load2($at))';
					case TVec(4): 'asfloat($b.Load4($at))';
					case TMat4: "float4x4(" + [for (k in 0...4) 'asfloat($b.Load4($at + ${16 * k}))'].join(", ") + ")";
					case _: throw "storage";
				}
			function storeOf(t:SType, at:String, v:String):Array<String>
				return switch t {
					case TInt | TFloat: ['$b.Store($at, asuint($v));'];
					case TVec(2): ['$b.Store2($at, asuint($v));'];
					case TVec(4): ['$b.Store4($at, asuint($v));'];
					case TMat4: [for (k in 0...4) '$b.Store4($at + ${16 * k}, asuint($v[$k]));'];
					case _: throw "storage";
				}
			var et = type(s.element);
			line('$et ${b}_load(int i) {');
			line('\tuint at = uint(i) * ${s.stride}u;');
			line(switch s.element {
				case TStruct(st): '\treturn make_${st.name}(' + [for (f in fields) loadOf(f.type, 'at + ${f.offset}u')].join(", ") + ");";
				case t: '\treturn ' + loadOf(t, "at") + ";";
			});
			line("}");
			if (!s.write) continue;
			line('void ${b}_store(int i, $et v) {');
			line('\tuint at = uint(i) * ${s.stride}u;');
			for (f in fields)
				for (st in storeOf(f.type, 'at + ${f.offset}u', f.name == null ? "v" : 'v.${f.name}'))
					line('\t$st');
			line("}");
			if (s.element == TInt)
				for (op in ["Add", "Min", "Max"]) {
					line('int ${b}_atomic$op(int i, int v) {');
					line("\tint o;");
					line('\t$b.Interlocked$op(uint(i) * 4u, v, o);');
					line("\treturn o;");
					line("}");
				}
		}
		for (m in c.images)
			line('${type(TImage(m.format))} img_${m.slot} : register(u${m.uav});');
	}

	override function computeEntry(c:SCompute) {
		var e = c.entry;
		for (u in e.uniforms) {
			line('cbuffer ${u.struct.name}_block : register(b${u.binding}) {');
			for (i in 0...u.struct.fields.length) {
				var f = u.struct.fields[i], o = u.offsets[i];
				line('\t' + (f.type.match(TMat4 | TArray(TMat4, _)) ? "row_major " : "") + decl(f.type, 'u_${u.binding}_${f.name}') + ' : packoffset(c${o >> 4}' + (o & 15 == 0 ? "" : "." + "xyzw".charAt((o & 15) >> 2)) + ");");
			}
			line("};");
		}
		for (t in e.textures) {
			line('${type(Emit.textureType(t))} tex_${t.slot} : register(t${t.slot});');
			line('SamplerState smp_${t.slot} : register(s${t.slot});');
		}
		var args = Emit.computeArgs(e, u -> 'make_${u.struct.name}(' + [for (f in u.struct.fields) 'u_${u.binding}_${f.name}'].join(", ") + ")", t -> 'tex_${t.slot}, smp_${t.slot}', s -> null, m -> null);
		var ids = "int(gid.x), int(gid.y), int(gid.z), int(lid.x), int(lid.y), int(lid.z), int(lidx), int(grp.x), int(grp.y), int(grp.z)";
		line('[numthreads(${c.size.join(", ")})]');
		line("void main(uint3 gid : SV_DispatchThreadID, uint3 lid : SV_GroupThreadID, uint lidx : SV_GroupIndex, uint3 grp : SV_GroupID) {");
		line('\t${e.fn.name}(' + ['make_${e.input.name}($ids)'].concat(args).join(", ") + ");");
		line("}");
	}

	override function decl(t:SType, name:String):String
		return switch t {
			case TArray(e, n): type(e) + " " + name + "[" + n + "]";
			case _: super.decl(t, name);
		}

	override function struct(s:SStruct) {
		super.struct(s);
		line('${s.name} make_${s.name}(' + [for (i in 0...s.fields.length) decl(s.fields[i].type, "f" + i)].join(", ") + ") {");
		line('\t${s.name} s;');
		for (i in 0...s.fields.length)
			line('\ts.${s.fields[i].name} = f$i;');
		line("\treturn s;");
		line("}");
	}

	override function param(v:SVar):String
		return type(v.type) + " " + v.name + (Textures.isTexture(v.type) ? ", SamplerState " + v.name + "_smp" : "");

	override function arg(e:SExpr):String
		return Textures.isTexture(e.t) ? expr(e) + ", " + expr(e) + "_smp" : expr(e);

	override function construct(t:SType, args:Array<SExpr>):String
		return switch [t, args] {
			case [TStruct(s), _]: 'make_${s.name}(' + [for (a in args) expr(a)].join(", ") + ")";
			// (one scalar for every component)
			case [TVec(_), [a]] if (a.t == TFloat): "((" + type(t) + ")" + operand(a) + ")";
			case _: super.construct(t, args);
		}

	override function binary(op:SBinop, a:SExpr, b:SExpr):String
		return switch [op, a.t, b.t] {
			case [Mul, TMat4, TVec(4)]: "mul(" + expr(b) + ", " + expr(a) + ")";
			case [Mul, TMat4, TMat4]: "mul(" + expr(b) + ", " + expr(a) + ")";
			case _: super.binary(op, a, b);
		}

	override function builtin(name:String, args:Array<SExpr>, t:SType):String
		return switch name {
			case "fract": super.builtin("frac", args, t);
			case "mix": super.builtin("lerp", args, t);
			case "inversesqrt": super.builtin("rsqrt", args, t);
			case "sample" | "sampleLevel" if (args[0].t == TTextureArray):
				// (a 2D array's uv and layer: one float3)
				var at = "float3(" + expr(args[1]) + ", " + expr(args[2]) + ")";
				operand(args[0]) + (name == "sampleLevel" ? ".SampleLevel(" + expr(args[0]) + "_smp, " + at + ", " + expr(args[3]) + ")" : fragment ? ".Sample(" + expr(args[0])
					+ "_smp, " + at + ")" : ".SampleLevel(" + expr(args[0]) + "_smp, " + at + ", 0.0)");
			case "sample" if (fragment): operand(args[0]) + ".Sample(" + expr(args[0]) + "_smp, " + expr(args[1]) + ")";
			case "sample": operand(args[0]) + ".SampleLevel(" + expr(args[0]) + "_smp, " + expr(args[1]) + ", 0.0)";
			case "sampleLevel": operand(args[0]) + ".SampleLevel(" + expr(args[0]) + "_smp, " + expr(args[1]) + ", " + expr(args[2]) + ")";
			case "atomicAdd" | "atomicMin" | "atomicMax": operand(args[0]) + "_" + name + "(" + expr(args[1]) + ", " + expr(args[2]) + ")";
			case "textureStore":
				operand(args[0]) + "[uint2(" + expr(args[1]) + ", " + expr(args[2]) + ")] = " + (args[0].t.match(TImage(5)) ? operand(args[3]) + ".x" : expr(args[3]));
			// (an int: back to floats)
			case "sign": "((" + type(t) + ")" + super.builtin("sign", args, t) + ")";
			case _: super.builtin(name, args, t);
		}

	override function entry(p:SProgram, e:SEntry) {
		for (u in e.uniforms) {
			line('cbuffer ${u.struct.name}_block : register(b${u.binding}) {');
			for (i in 0...u.struct.fields.length) {
				var f = u.struct.fields[i], o = u.offsets[i];
				line('\t' + (f.type.match(TMat4 | TArray(TMat4, _)) ? "row_major " : "") + decl(f.type, 'u_${u.binding}_${f.name}') + ' : packoffset(c${o >> 4}' + (o & 15 == 0 ? "" : "." + "xyzw".charAt((o & 15) >> 2)) + ");");
			}
			line("};");
		}
		for (t in e.textures) {
			line('${type(Emit.textureType(t))} tex_${t.slot} : register(t${t.slot});');
			line('SamplerState smp_${t.slot} : register(s${t.slot});');
		}
		var args = [
			for (r in e.resources)
				switch r {
					case RUniform(u): 'make_${u.struct.name}(' + [for (f in u.struct.fields) 'u_${u.binding}_${f.name}'].join(", ") + ")";
					case RTexture(t): 'tex_${t.slot}, smp_${t.slot}';
					case RStorage(_) | RImage(_): throw "a render stage's storage";
				}
		];
		var vs = Emit.varyings(p), pos = Emit.position(p);
		var input = 'make_${e.input.name}(' + [for (f in e.input.fields) 'i.${f.name}'].join(", ") + ")";
		if (e.stage == Vertex) {
			line("struct StageIn {");
			for (i in 0...e.input.fields.length) {
				var f = e.input.fields[i];
				line('\t${type(f.type)} ${f.name} : TEXCOORD$i;');
			}
			line("};");
			stageOut(p);
			line("StageOut main(StageIn i) {");
			line('\t${p.varyings.name} r = ${e.fn.name}(' + [input].concat(args).join(", ") + ");");
			line("\tStageOut o;");
			for (f in [pos].concat(vs))
				line('\to.${f.name} = r.${f.name};');
			line("\treturn o;");
			line("}");
		} else {
			stageOut(p);
			line("float4 main(StageOut i) : SV_Target {");
			line('\treturn ${e.fn.name}(' + [input].concat(args).join(", ") + ");");
			line("}");
		}
	}

	function stageOut(p:SProgram) {
		var vs = Emit.varyings(p), pos = Emit.position(p);
		line("struct StageOut {");
		line('\tfloat4 ${pos.name} : SV_Position;');
		for (i in 0...vs.length)
			line('\t${type(vs[i].type)} ${vs[i].name} : TEXCOORD$i;');
		line("};");
	}
}
