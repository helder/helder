package helder.gfx.shader;

import helder.gfx.shader.Ir;

// MSL (Metal). Entry points named main0: vertex attributes at
// [[attribute(n)]] of a [[stage_in]] struct, the varyings a struct both
// stages share ([[position]], the others matched by name); a uniform block
// is `constant <Struct>_buffer& u_<n> [[buffer(n)]]` (vertex buffers are at
// 16 and up), a struct laid out as std140 (packed_float3 and padding),
// converted to the program's struct for the stage's function; a texture
// at slot n `texture2d<float> tex_<n> [[texture(n)]]` and its `sampler
// smp_<n> [[sampler(n)]]`.
//
// A compute stage's entry point is `kernel void main0` (its workgroup's
// size given at each dispatch: ShaderCode.workgroupSize); a storage buffer
// at slot n is the parameter `const device T* sb_<n> [[buffer(n)]]`
// (device T* when it is written; an RWStorage<Int> device atomic_int*,
// read and written atomically, relaxed), passed on to the stage's
// function, a storage texture `texture2d<float, access::write> img_<n>
// [[texture(n)]]`; its workgroup memory `threadgroup T wg_<k>[n]` in the
// entry point, passed on as `threadgroup T*`; its subgroups Metal's SIMD
// groups (simd_sum ..., thread_index_in_simdgroup and the others).
class Msl extends Emit {
	override function header(e:SEntry) {
		line("#include <metal_stdlib>");
		line("using namespace metal;");
	}

	override function type(t:SType):String
		return switch t {
			case TVoid: "void";
			case TBool: "bool";
			case TInt: "int";
			case TFloat: "float";
			case TVec(n): 'float$n';
			case TMat4: "float4x4";
			case TTexture: "texture2d<float>";
			case TTextureCube: "texturecube<float>";
			case TTextureArray: "texture2d_array<float>";
			case TStruct(s): s.name;
			// (metal::array: copied from the constant buffer as a value)
			case TArray(t, n): 'array<${type(t)}, $n>';
			case TStorage(TInt, true): "device atomic_int*";
			case TStorage(t, w): (w ? "device " : "const device ") + type(t) + "*";
			case TImage(_): "texture2d<float, access::write>";
			case TWorkgroup(t): "threadgroup " + type(t) + "*";
		}

	// (MSL passes its buffers on: parameters, not globals)
	override function global(t:SType):Bool
		return false;

	static function atomic(b:SExpr):Bool
		return b.t.match(TStorage(TInt, true));

	override function load(b:SExpr, i:SExpr):String
		return atomic(b) ? "atomic_load_explicit(&" + operand(b) + "[" + expr(i) + "], memory_order_relaxed)" : super.load(b, i);

	override function store(b:SExpr, i:SExpr, v:SExpr):String
		return atomic(b) ? "atomic_store_explicit(&" + operand(b) + "[" + expr(i) + "], " + expr(v) + ", memory_order_relaxed);" : super.store(b, i, v);

	override function computeHeader(c:SCompute)
		header(c.entry);

	override function computeEntry(c:SCompute) {
		var e = c.entry;
		for (u in e.uniforms)
			uniformBuffer(u);
		var params = [
			"uint3 gid [[thread_position_in_grid]]", "uint3 lid [[thread_position_in_threadgroup]]", "uint lidx [[thread_index_in_threadgroup]]",
			"uint3 grp [[threadgroup_position_in_grid]]"
		];
		for (r in e.resources)
			params.push(switch r {
				case RUniform(u): 'constant ${u.struct.name}_buffer& u_${u.binding} [[buffer(${u.binding})]]';
				case RTexture(t): '${type(Emit.textureType(t))} tex_${t.slot} [[texture(${t.slot})]], sampler smp_${t.slot} [[sampler(${t.slot})]]';
				case RStorage(s): '${type(TStorage(s.element, s.write))} sb_${s.slot} [[buffer(${s.slot})]]';
				case RImage(m): '${type(TImage(m.format))} img_${m.slot} [[texture(${m.slot})]]';
			});
		if (native())
			params = params.concat([
				"uint sgl [[thread_index_in_simdgroup]]", "uint sgs [[threads_per_simdgroup]]", "uint sgi [[simdgroup_index_in_threadgroup]]",
				"uint sgn [[simdgroups_per_threadgroup]]"
			]);
		var args = Emit.computeArgs(e, uniformValue, t -> 'tex_${t.slot}, smp_${t.slot}', s -> 'sb_${s.slot}', m -> 'img_${m.slot}').concat([for (s in c.shared) 'wg_${s.index}']);
		var ids = "int(gid.x), int(gid.y), int(gid.z), int(lid.x), int(lid.y), int(lid.z), int(lidx), int(grp.x), int(grp.y), int(grp.z)"
			+ subgroupIds(native() ? ["int(sgl)", "int(sgs)", "int(sgi)", "int(sgn)"] : null, "int(lidx)");
		line('kernel void main0(${params.join(", ")}) {');
		for (s in c.shared)
			line('\tthreadgroup ${type(s.element)} wg_${s.index}[${s.length}];');
		line('\t${e.fn.name}(' + ['${e.input.name}{$ids}'].concat(args).join(", ") + ");");
		line("}");
	}

	// a uniform block as the stage reads it: std140 (packed_float3 and padding)
	function uniformBuffer(u:SUniform) {
		line('struct ${u.struct.name}_buffer {');
		var off = 0, pad = 0;
		for (i in 0...u.struct.fields.length) {
			var f = u.struct.fields[i];
			if (u.offsets[i] > off) line('\tfloat pad${pad++}[${(u.offsets[i] - off) >> 2}];');
			line('\t' + (f.type.match(TVec(3)) ? "packed_float3" : type(f.type)) + ' ${f.name};');
			off = u.offsets[i] + switch f.type {
				case TVec(n): 4 * n;
				case TMat4: 64;
				case TArray(t, n): (t == TMat4 ? 64 : 16) * n;
				case _: 4;
			}
		}
		line("};");
	}

	// ... converted to the program's struct
	function uniformValue(u:SUniform):String
		return u.struct.name + "{" + [
			for (f in u.struct.fields)
				f.type.match(TVec(3)) ? 'float3(u_${u.binding}.${f.name})' : 'u_${u.binding}.${f.name}'
		].join(", ") + "}";

	override function param(v:SVar):String
		return type(v.type) + " " + v.name + (Textures.isTexture(v.type) ? ", sampler " + v.name + "_smp" : "");

	override function arg(e:SExpr):String
		return Textures.isTexture(e.t) ? expr(e) + ", " + expr(e) + "_smp" : expr(e);

	override function construct(t:SType, args:Array<SExpr>):String
		return switch t {
			case TStruct(s): s.name + "{" + [for (a in args) expr(a)].join(", ") + "}";
			case _: super.construct(t, args);
		}

	override function builtin(name:String, args:Array<SExpr>, t:SType):String
		return switch name {
			case "sample" | "sampleLevel" if (args[0].t == TTextureArray):
				// (a 2D array's layer: an index)
				var at = expr(args[1]) + ", uint(rint(" + expr(args[2]) + "))";
				operand(args[0]) + ".sample(" + expr(args[0]) + "_smp, " + at + (name == "sampleLevel" ? ", level(" + expr(args[3]) + "))" : fragment ? ")" : ", level(0.0))");
			case "sample" if (fragment): operand(args[0]) + ".sample(" + expr(args[0]) + "_smp, " + expr(args[1]) + ")";
			case "sample": operand(args[0]) + ".sample(" + expr(args[0]) + "_smp, " + expr(args[1]) + ", level(0.0))";
			case "sampleLevel": operand(args[0]) + ".sample(" + expr(args[0]) + "_smp, " + expr(args[1]) + ", level(" + expr(args[2]) + "))";
			case "discard": "discard_fragment()";
			case "atomicAdd" | "atomicMin" | "atomicMax":
				"atomic_fetch_" + name.substr(6).toLowerCase() + "_explicit(&" + operand(args[0]) + "[" + expr(args[1]) + "], " + expr(args[2]) + ", memory_order_relaxed)";
			case "textureStore": operand(args[0]) + ".write(" + expr(args[3]) + ", uint2(" + expr(args[1]) + ", " + expr(args[2]) + "))";
			case "barrier": "threadgroup_barrier(mem_flags::mem_threadgroup)";
			case "subgroupAdd": super.builtin("simd_sum", args, t);
			case "subgroupMin": super.builtin("simd_min", args, t);
			case "subgroupMax": super.builtin("simd_max", args, t);
			case "subgroupAll": super.builtin("simd_all", args, t);
			case "subgroupAny": super.builtin("simd_any", args, t);
			case "subgroupBroadcast" | "subgroupShuffle": (name == "subgroupBroadcast" ? "simd_broadcast(" : "simd_shuffle(") + expr(args[0]) + ", ushort(" + expr(args[1]) + "))";
			case _: super.builtin(name == "inversesqrt" ? "rsqrt" : name, args, t);
		}

	override function entry(p:SProgram, e:SEntry) {
		for (u in e.uniforms) {
			line('struct ${u.struct.name}_buffer {');
			var off = 0, pad = 0;
			for (i in 0...u.struct.fields.length) {
				var f = u.struct.fields[i];
				if (u.offsets[i] > off) line('\tfloat pad${pad++}[${(u.offsets[i] - off) >> 2}];');
				line('\t' + (f.type.match(TVec(3)) ? "packed_float3" : type(f.type)) + ' ${f.name};');
				off = u.offsets[i] + switch f.type {
					case TVec(n): 4 * n;
					case TMat4: 64;
					case TArray(t, n): (t == TMat4 ? 64 : 16) * n;
					case _: 4;
				}
			}
			line("};");
		}
		var params = [
			for (r in e.resources)
				switch r {
					case RUniform(u): 'constant ${u.struct.name}_buffer& u_${u.binding} [[buffer(${u.binding})]]';
					case RTexture(t): '${type(Emit.textureType(t))} tex_${t.slot} [[texture(${t.slot})]], sampler smp_${t.slot} [[sampler(${t.slot})]]';
					case RStorage(_) | RImage(_): throw "a render stage's storage";
				}
		];
		var args = [
			for (r in e.resources)
				switch r {
					case RUniform(u):
						u.struct.name + "{" + [
							for (f in u.struct.fields)
								f.type.match(TVec(3)) ? 'float3(u_${u.binding}.${f.name})' : 'u_${u.binding}.${f.name}'
						].join(", ") + "}";
					case RTexture(t): 'tex_${t.slot}, smp_${t.slot}';
					case RStorage(_) | RImage(_): throw "a render stage's storage";
				}
		];
		var vs = Emit.varyings(p), pos = Emit.position(p);
		var input = e.input.name + "{" + [for (f in e.input.fields) 'i.${f.name}'].join(", ") + "}";
		if (e.stage == Vertex) {
			line("struct StageIn {");
			for (i in 0...e.input.fields.length) {
				var f = e.input.fields[i];
				line('\t${type(f.type)} ${f.name} [[attribute($i)]];');
			}
			line("};");
			stageOut(p);
			line('vertex StageOut main0(' + ["StageIn i [[stage_in]]"].concat(params).join(", ") + ") {");
			line('\t${p.varyings.name} r = ${e.fn.name}(' + [input].concat(args).join(", ") + ");");
			line('\treturn StageOut{' + [for (f in [pos].concat(vs)) 'r.${f.name}'].join(", ") + "};");
			line("}");
		} else {
			stageOut(p);
			line('fragment float4 main0(' + ["StageOut i [[stage_in]]"].concat(params).join(", ") + ") {");
			var input = e.input.name + "{" + [for (f in e.input.fields) 'i.${f.name}'].join(", ") + "}";
			line('\treturn ${e.fn.name}(' + [input].concat(args).join(", ") + ");");
			line("}");
		}
	}

	function stageOut(p:SProgram) {
		var vs = Emit.varyings(p), pos = Emit.position(p);
		line("struct StageOut {");
		line('\tfloat4 ${pos.name} [[position]];');
		for (i in 0...vs.length)
			line('\t${type(vs[i].type)} ${vs[i].name} [[user(locn$i)]];');
		line("};");
	}
}
