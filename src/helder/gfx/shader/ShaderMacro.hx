package helder.gfx.shader;

#if macro
import helder.math.*;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import helder.compiler.HaxeAdapter;
import helder.gfx.shader.Ir;
import helder.gfx.shader.ShaderDefinition;

using haxe.macro.Tools;

// shader({...}) in Haxe (ShaderMath.shader forwards here): the argument's
// kernel tree (HaxeAdapter), the handler (ShaderDefinition) with Lower as
// its adapter, and the handler's output as the expression of a Shader: the
// text and layouts as literals, the writers as code storing each field,
// the stage functions as they are (CPU code).
class ShaderMacro {
	public static function shader(def:Expr):Expr {
		var arg = new HaxeAdapter("shader").node(def);
		var lower = new Lower();
		var out = new ShaderDefinition().generate(arg, lower);
		var stages = switch def.expr {
			case EObjectDecl(fs): fs;
			case _: [];
		}
		function stage(name:String):Expr {
			var e = Lambda.find(stages, f -> f.field == name).expr;
			// (the fragment function's varyings when not written)
			return switch e.expr {
				case EFunction(k, f) if (name == "fragment" && f.args.length > 0 && f.args[0].type == null):
					var g = Reflect.copy(f);
					g.args = [Reflect.copy(f.args[0])].concat(f.args.slice(1));
					g.args[0].type = lower.haxeType(out.program.varyings).toComplexType();
					{expr: EFunction(k, g), pos: e.pos};
				case _: e;
			}
		}
		return build(out, lower, {
			vertex: stage("vertex"),
			fragment: stage("fragment"),
			vertexType: lower.stageTypes.get("vs").toComplexType(),
			fragmentType: lower.stageTypes.get("fs").toComplexType()
		});
	}

	// the expression of a Shader: the handler's output as literals and
	// writers, the stages' CPU code as given (with their types)
	// (lean: its code, layout, blocks and textures alone, no params' writers
	// nor vertexBytes: a variant drawn as another's twin, its writers the
	// other's: helder.scene's MaterialShader)
	public static function build(out:ShaderOutput, lower:Lower, stages:{vertex:Expr, fragment:Expr, vertexType:ComplexType, fragmentType:ComplexType}, lean = false):Expr {
		var p = out.program;
		var pos = Context.currentPos();
		// (-D helder.soft: the stages' form for the CPU back end too, Soft)
		var soft = Soft.enabled() ? new Soft(p, softPrefix(out), Context.getLocalModule().split(".").slice(0, -1), Context.getLocalModule()) : null;
		var softCode = soft == null ? null : soft.stages();
		function code(s:StageCode, ?cpu:Expr):Expr {
			var fields:Array<ObjectField> = [for (c in s.code) {field: c.language, expr: macro $v{c.text}}];
			if (cpu != null) fields.push({field: "soft", expr: cpu});
			var bindings = [
				for (b in s.bindings)
					b.uniform ? macro {name: $v{b.name}, slot: $v{b.slot}, kind: helder.gfx.ShaderBinding.BindingKind.Uniform, size: $v{b.size}} : b.dimension == 0 ? macro {
						name: $v{b.name},
						slot: $v{b.slot},
						kind: helder.gfx.ShaderBinding.BindingKind.Texture
					} : macro {
						name: $v{b.name},
						slot: $v{b.slot},
						kind: helder.gfx.ShaderBinding.BindingKind.Texture,
						dimension: $v{b.dimension}
					}
			];
			fields.push({field: "bindings", expr: macro [$a{bindings}]});
			return {expr: EObjectDecl(fields), pos: pos};
		}
		var attrs = [
			for (i in 0...out.attributes.length) {
				var a = out.attributes[i], fmt = "Float" + a.components;
				macro {location: $v{i}, format: helder.gfx.VertexFormat.$fmt, offset: $v{a.offset}};
			}
		];
		var layout = macro ([{stride: $v{out.stride}, attributes: [$a{attrs}]}] : Array<helder.gfx.VertexBufferLayout>);
		var uniforms = macro ([$a{[for (u in p.uniforms) macro {name: $v{u.struct.name}, binding: $v{u.binding}, size: $v{u.size}}]}] : Array<helder.gfx.shader.Shader.UniformBlock>);
		var textures = macro ([$a{[for (t in p.textures) macro {name: $v{t.name}, binding: $v{t.slot}}]}] : Array<helder.gfx.shader.Shader.TextureBinding>);
		// the vertices, packed as layout says (Float32 each)
		var vt = lower.haxeType(p.vertex.input).toComplexType(), stores = [];
		for (a in out.attributes) {
			var n = a.field;
			var v = macro v.$n;
			for (k in components(a.components)) {
				var x = k == null ? v : macro $v.$k;
				stores.push(macro bytes.setFloat(o + $v{a.offset + 4 * (k == null ? 0 : "xyzw".indexOf(k))}, $x));
			}
		}
		var writeVertices = macro function(vs:Array<$vt>):haxe.io.Bytes {
			var bytes = haxe.io.Bytes.alloc($v{out.stride} * vs.length);
			for (i in 0...vs.length) {
				var v = vs[i], o = i * $v{out.stride};
				$b{stores};
			}
			return bytes;
		};
		// the parameters: a writer per uniform block, a slot per texture
		var params:Array<ObjectField> = [];
		for (b in out.params) {
			var u = switch b.resource {
				case RUniform(u): u;
				case RTexture(t):
					params.push({field: b.name, expr: macro new helder.gfx.shader.Shader.TextureSlot($v{t.name}, $v{t.slot})});
					continue;
				case RStorage(_) | RImage(_): throw "a render stage's storage";
			}
			params.push({field: b.name, expr: uniformWriter(u, lower, b.name)});
		}
		// the shader's own class (its stages' exact types: hxmc calls a function
		// of struct values only as such), named after its module, its field and
		// a hash of its content: a compilation server's cached one is the same
		var module = Context.getLocalModule(), field = Context.getLocalMethod() ?? "shader";
		var pack = module.split(".");
		var base = pack.pop() + "_" + field;
		var vt = stages.vertexType, ft = stages.fragmentType;
		var vti = lower.haxeType(p.vertex.input).toComplexType();
		var paramsExpr:Expr = lean ? macro null : {expr: EObjectDecl(params), pos: pos};
		var pt = lean ? macro :Dynamic : Context.toComplexType(Context.typeof(paramsExpr));
		if (lean) writeVertices = macro null;
		var cls = macro class Shader extends helder.gfx.shader.Shader<$vti, $pt> {
			public final vertex:$vt;
			public final fragment:$ft;

			public function new(vertex:$vt, fragment:$ft) {
				super(${code(out.vertex, softCode?.vertex)}, ${code(out.fragment, softCode?.fragment)}, $layout, $uniforms, $textures, $writeVertices, $paramsExpr);
				this.vertex = vertex;
				this.fragment = fragment;
			}
		};
		// (the uniform(...)s' block: written from their values now, bound at its slot)
		if (out.uniforms != null) {
			var u = out.uniforms;
			var values:Expr = {expr: EObjectDecl([for (r in lower.uniformRefs) {field: r.field, expr: macro ${r.expr}.value}]), pos: pos};
			cls.fields = cls.fields.concat((macro class {
				final uniformValues = haxe.io.Bytes.alloc($v{u.size});

				override public function uniformBytes():Null<haxe.io.Bytes> {
					params.uniforms.write($values, uniformValues);
					return uniformValues;
				}
			}).fields);
			for (f in cls.fields)
				if (f.name == "new") switch f.kind {
					case FFun(fn): fn.expr = macro {${fn.expr}; uniformBinding = $v{u.binding};};
					case _:
				}
			// (bind: a GPU's target's, helder.gfx's Encoder)
			if (Context.definedValue("target.name") == "hxmc") cls.fields = cls.fields.concat((macro class {
				public function bind(encoder:helder.gfx.Encoder)
					encoder.setUniforms(uniformBinding, uniformBytes());
			}).fields);
		}
		var name = base + "_" + haxe.crypto.Md5.encode(new haxe.macro.Printer().printTypeDefinition(cls)).substr(0, 8);
		if (soft != null) {
			cls.fields = cls.fields.concat(soft.fields);
			if (Context.defined("helder.soft.print")) for (f in soft.fields) Sys.println(new haxe.macro.Printer().printField(f));
		}
		cls.name = name;
		cls.pack = pack;
		cls.pos = pos;
		cls.meta = [{name: ":noCompletion", pos: pos}];
		var exists = try Context.getType(pack.concat([name]).join(".")) != null catch (_:Dynamic) false;
		if (!exists) Context.defineType(cls, module);
		var tp:TypePath = {pack: pack, name: name};
		return macro new $tp(${stages.vertex}, ${stages.fragment});
	}

	// (the CPU form's types' names: the module's, its field's and the stages' text)
	static function softPrefix(out:ShaderOutput):String {
		var module = Context.getLocalModule(), field = Context.getLocalMethod() ?? "shader";
		var text = [for (s in [out.vertex, out.fragment]) for (c in s.code) c.text].join("");
		return module.split(".").pop() + "_" + field + "_" + haxe.crypto.Md5.encode(text).substr(0, 8);
	}

	// a uniform block's writer (UniformWriter): each field stored at its std140 offset
	// a block's writer: a class of its own (write overridden, no closure: a
	// closure through a field of the generic type boxes its call on hxmc, a
	// write per draw allocating), named after the module, its field and its
	// content; typed as the base, UniformWriter<T>, so that shaders of one
	// slot object are of one type
	static function uniformWriter(u:SUniform, lower:Lower, name:String):Expr {
		var ut = lower.haxeType(u.struct).toComplexType(), stores = [];
		for (i in 0...u.struct.fields.length) {
			var f = u.struct.fields[i], off = u.offsets[i];
			var n = f.field;
			var v = macro u.$n;
			switch f.type {
				case TArray(t, len):
					// (its elements, as many as it has up to its length; zeros after)
					var size = t == TMat4 ? 64 : 16;
					var each = t == TMat4 ? [
						for (c in 0...4) for (k in 0...4) {
							var col = "c" + c, comp = "xyzw".charAt(k);
							macro b.setFloat(at + $v{16 * c + 4 * k}, x.$col.$comp);
						}
					] : [for (k in 0...4) {
						var comp = "xyzw".charAt(k);
						macro b.setFloat(at + $v{4 * k}, x.$comp);
					}];
					stores.push(macro {
						var a = $v, m = 0;
						if (a != null) m = a.length < $v{len} ? a.length : $v{len};
						for (j in 0...m) {
							var x = a[j], at = o + $v{off} + $v{size} * j;
							$b{each};
						}
						b.fill(o + $v{off} + $v{size} * m, $v{size} * ($v{len} - m), 0);
					});
				case TInt: stores.push(macro b.setInt32(o + $v{off}, $v));
				case TMat4: stores.push(macro helder.gfx.shader.Shader.UniformWriter.mat4(b, o + $v{off}, $v));
				case TVec(4): stores.push(macro helder.gfx.shader.Shader.UniformWriter.vec4(b, o + $v{off}, $v));
				case t:
					var k = 0;
					for (c in components(switch t {
						case TVec(n): n;
						case _: 1;
					}))
						stores.push(macro b.setFloat(o + $v{off + 4 * k++}, ${c == null ? v : macro $v.$c}));
			}
		}
		var block = macro {name: $v{u.struct.name}, binding: $v{u.binding}, size: $v{u.size}};
		var writer = macro class UniformWriter extends helder.gfx.shader.Shader.UniformWriter<$ut> {
			public function new()
				super($block);

			override public function write(u:$ut, b:haxe.io.Bytes, o = 0) {
				$b{stores};
			}
		};
		var pos = Context.currentPos();
		var module = Context.getLocalModule(), pack = module.split(".");
		var base = pack.pop() + "_" + (Context.getLocalMethod() ?? "shader") + "_" + name;
		writer.name = base + "_" + haxe.crypto.Md5.encode(new haxe.macro.Printer().printTypeDefinition(writer)).substr(0, 8);
		writer.pack = pack;
		writer.pos = pos;
		writer.meta = [{name: ":noCompletion", pos: pos}];
		var exists = try Context.getType(pack.concat([writer.name]).join(".")) != null catch (_:Dynamic) false;
		if (!exists) Context.defineType(writer, module);
		var tp:TypePath = {pack: pack, name: writer.name};
		return macro(new $tp() : helder.gfx.shader.Shader.UniformWriter<$ut>);
	}

	// compute({size, main}) in Haxe (ShaderMath.compute forwards here): the
	// handler's compute (ShaderDefinition), the ComputeShader of its output
	public static function compute(def:Expr):Expr {
		var arg = new HaxeAdapter("compute").node(def);
		var lower = new Lower();
		var out = new ShaderDefinition().compute(arg, lower);
		var c = out.program;
		var pos = Context.currentPos();
		var fields = switch def.expr {
			case EObjectDecl(fs): fs;
			case _: [];
		}
		var main = Lambda.find(fields, f -> f.field == "main").expr;
		var mainType = [for (t in lower.stageTypes) t][0].toComplexType();
		var codeFields:Array<ObjectField> = [for (x in out.code) {field: x.language, expr: macro $v{x.text}}];
		var bindings = macro [
				$a{
					[
						for (b in out.bindings)
							macro {
								name: $v{b.name},
								slot: $v{b.slot},
								kind: (cast $v{b.kind} : helder.gfx.ShaderBinding.BindingKind),
								size: $v{b.size},
								index: $v{b.index},
								format: $v{b.format},
								dimension: $v{b.dimension}
							}
					]
				}
			];
		codeFields.push({field: "bindings", expr: bindings});
		codeFields.push({field: "workgroupSize", expr: macro $v{c.size}});
		// (its subgroups made of workgroup memory, for the devices without them)
		if (out.emulated != null)
			codeFields.push({field: "emulated", expr: {expr: EObjectDecl([for (x in out.emulated) {field: x.language, expr: macro $v{x.text}}]), pos: pos}});
		// (-D helder.soft: the stage's form for the CPU back end, Soft)
		var softForm = Soft.enabled() ? Soft.compute(c, Context.getLocalModule().split(".").pop() + "_" + (Context.getLocalMethod() ?? "compute") + "_"
			+ haxe.crypto.Md5.encode([for (x in out.code) x.text].join("")).substr(0, 8),
			Context.getLocalModule().split(".").slice(0, -1), Context.getLocalModule()) : null;
		if (softForm != null) codeFields.push({field: "soft", expr: softForm.code});
		var code:Expr = {expr: EObjectDecl(codeFields), pos: pos};
		var uniforms = macro ([$a{[for (u in c.entry.uniforms) macro {name: $v{u.struct.name}, binding: $v{u.binding}, size: $v{u.size}}]}] : Array<helder.gfx.shader.Shader.UniformBlock>);
		var textures = macro ([$a{[for (t in c.entry.textures) macro {name: $v{t.name}, binding: $v{t.slot}}]}] : Array<helder.gfx.shader.Shader.TextureBinding>);
		var module = Context.getLocalModule(), field = Context.getLocalMethod() ?? "compute";
		var pack = module.split(".");
		var base = pack.pop() + "_" + field;
		var params:Array<ObjectField> = [];
		for (b in out.params)
			params.push({
				field: b.name,
				expr: switch b.resource {
					case RUniform(u): uniformWriter(u, lower, b.name);
					case RTexture(t): macro new helder.gfx.shader.Shader.TextureSlot($v{t.name}, $v{t.slot});
					case RStorage(s): storageSlot(s, lower, module, pack, base);
					case RImage(m): macro new helder.gfx.shader.ComputeShader.StorageTextureSlot($v{m.name}, $v{m.slot}, cast $v{m.format});
				}
			});
		var paramsExpr:Expr = {expr: EObjectDecl(params), pos: pos};
		var pt = Context.toComplexType(Context.typeof(paramsExpr));
		var cls = macro class ComputeShader extends helder.gfx.shader.ComputeShader<$pt> {
			public final main:$mainType;

			public function new(main:$mainType) {
				super($code, $v{c.size}, $uniforms, $textures, $paramsExpr);
				this.main = main;
			}
		};
		if (out.uniforms != null) {
			var u = out.uniforms;
			var values:Expr = {expr: EObjectDecl([for (r in lower.uniformRefs) {field: r.field, expr: macro ${r.expr}.value}]), pos: pos};
			cls.fields = cls.fields.concat((macro class {
				final uniformValues = haxe.io.Bytes.alloc($v{u.size});

				override public function uniformBytes():Null<haxe.io.Bytes> {
					params.uniforms.write($values, uniformValues);
					return uniformValues;
				}
			}).fields);
			for (f in cls.fields)
				if (f.name == "new") switch f.kind {
					case FFun(fn): fn.expr = macro {${fn.expr}; uniformBinding = $v{u.binding};};
					case _:
				}
			if (Context.definedValue("target.name") == "hxmc") cls.fields = cls.fields.concat((macro class {
				public function bind(encoder:helder.gfx.Encoder)
					encoder.setUniforms(uniformBinding, uniformBytes());
			}).fields);
		}
		var name = base + "_" + haxe.crypto.Md5.encode(new haxe.macro.Printer().printTypeDefinition(cls)).substr(0, 8);
		if (softForm != null) cls.fields = cls.fields.concat(softForm.soft.fields);
		cls.name = name;
		cls.pack = pack;
		cls.pos = pos;
		cls.meta = [{name: ":noCompletion", pos: pos}];
		var exists = try Context.getType(pack.concat([name]).join(".")) != null catch (_:Dynamic) false;
		if (!exists) Context.defineType(cls, module);
		var tp:TypePath = {pack: pack, name: name};
		return macro new $tp($main);
	}

	// a storage buffer's slot (StorageSlot): a class of its own (its element's
	// exact type: hxmc calls a function of struct values only as such), its
	// elements stored and loaded at their std430 offsets
	static function storageSlot(s:SStorage, lower:Lower, module:String, pack:Array<String>, base:String):Expr {
		var et = elementType(s.element, lower);
		function stores(t:SType, v:Expr, off:Int):Array<Expr>
			return switch t {
				case TFloat: [macro b.setFloat(o + $v{off}, $v)];
				case TInt: [macro b.setInt32(o + $v{off}, $v)];
				case TVec(n): [for (k in 0...n) {
						var c = "xyzw".charAt(k);
						macro b.setFloat(o + $v{off + 4 * k}, $v.$c);
					}];
				case TMat4: [for (c in 0...4) for (k in 0...4) {
						var col = "c" + c, comp = "xyzw".charAt(k);
						macro b.setFloat(o + $v{off + 16 * c + 4 * k}, $v.$col.$comp);
					}];
				case TStruct(st): [for (i in 0...st.fields.length) for (x in stores(st.fields[i].type, {
						var n = st.fields[i].field;
						macro $v.$n;
					}, off + s.offsets[i])) x];
				case _: throw "storage";
			}
		function load(t:SType, off:Int):Expr
			return switch t {
				case TFloat: macro b.getFloat(o + $v{off});
				case TInt: macro b.getInt32(o + $v{off});
				case TVec(2): macro new helder.math.Vec2(b.getFloat(o + $v{off}), b.getFloat(o + $v{off + 4}));
				case TVec(4): macro new helder.math.Vec4(b.getFloat(o + $v{off}), b.getFloat(o + $v{off + 4}), b.getFloat(o + $v{off + 8}), b.getFloat(o + $v{off + 12}));
				case TMat4:
					var cols = [for (c in 0...4) load(TVec(4), off + 16 * c)];
					macro new helder.math.Mat4($a{cols});
				case TStruct(st):
					var obj:Expr = {
						expr: EObjectDecl([for (i in 0...st.fields.length) {field: st.fields[i].field, expr: load(st.fields[i].type, s.offsets[i])}]),
						pos: Context.currentPos()
					};
					macro($obj : $et);
				case _: throw "storage";
			}
		var stride = s.stride;
		var cls = macro class StorageSlot extends helder.gfx.shader.ComputeShader.StorageSlot {
			public function new()
				super($v{s.name}, $v{s.slot}, $v{s.stride}, $v{s.write});

			// the elements from offset (bytes.length >= offset + values.length * stride)
			public function store(values:Array<$et>, b:haxe.io.Bytes, offset = 0)
				for (i in 0...values.length)
					storeAt(values[i], b, offset + i * $v{stride});

			// one element at o
			public function storeAt(v:$et, b:haxe.io.Bytes, o:Int):Void
				$b{stores(s.element, macro v, 0)};

			// the element i of b from offset
			public function load(b:haxe.io.Bytes, i:Int, offset = 0):$et {
				var o = offset + i * $v{stride};
				return ${load(s.element, 0)};
			}

			// the elements as a buffer's bytes (BufferDesc.data)
			public function bytesOf(values:Array<$et>):haxe.io.Bytes {
				var b = haxe.io.Bytes.alloc(values.length * $v{stride});
				store(values, b);
				return b;
			}
		};
		var name = base + "_" + s.name + "_" + haxe.crypto.Md5.encode(new haxe.macro.Printer().printTypeDefinition(cls)).substr(0, 8);
		cls.name = name;
		cls.pack = pack;
		cls.pos = Context.currentPos();
		cls.meta = [{name: ":noCompletion", pos: cls.pos}];
		var exists = try Context.getType(pack.concat([name]).join(".")) != null catch (_:Dynamic) false;
		if (!exists) Context.defineType(cls, module);
		var tp:TypePath = {pack: pack, name: name};
		return macro new $tp();
	}

	static function elementType(t:SType, lower:Lower):ComplexType
		return switch t {
			case TFloat: macro :Float;
			case TInt: macro :Int;
			case TVec(2): macro :helder.math.Vec2;
			case TVec(4): macro :helder.math.Vec4;
			case TMat4: macro :helder.math.Mat4;
			case TStruct(s): lower.haxeType(s).toComplexType();
			case _: throw "storage";
		}

	static function components(n:Int):Array<Null<String>>
		return n == 1 ? [null] : [for (i in 0...n) "xyzw".charAt(i)];
}
#end
