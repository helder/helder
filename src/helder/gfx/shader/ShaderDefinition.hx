package helder.gfx.shader;

import helder.definition.Kernel;
import helder.gfx.shader.Ir;

// What a shader's adapter does for the handler: a stage's function lowered
// to the IR with everything it calls (its name in the code when it has none
// of its own: vs, fs), and the locals renamed away from the globals at the
// end (Names.unhide). Lower is Haxe's; helder.typescript's lowering
// TypeScript's.
interface ShaderAdapter extends Adapter {
	function lowerStage(f:KFunction, name:String):SFunction;
	function finish():Void;
	// (a slot object's variant: the stages' third parameter the object,
	// m.options.<name> its options' values, m.<slot>(s, p) its slots'
	// functions; tests of constants folded, loops over them unrolled)
	function useSlots(use:SlotsUse):Void;
	// (the block of the uniform(...)s the stages read, made while lowering them: null, none)
	function uniforms():Null<SStruct>;
}

// shader({vertex, fragment}) (DESIGN.md 3), the handler both languages run:
// the stages' interface checked (a vertex of attributes in, the varyings
// out with exactly one position(...), the same varyings into the fragment
// stage, a colour out), the fields of each stage's object of parameters
// (the adapter flattens it: SFunction.fields) made uniform blocks (std140)
// and textures at slots in order of appearance, the stages' text printed in
// the build's languages, and what the CPU's writers store where. The
// adapter turns the output into the generated value (ShaderMacro: Haxe's
// expression of a Shader).
class ShaderDefinition implements Definition<ShaderAdapter, ShaderOutput> {
	public static inline var MAX_SLOTS = 16;

	public final name = "shader";

	public function new() {}

	public function generate(arg:KNode, a:ShaderAdapter):ShaderOutput {
		var r = new KObjectReader(arg, a, "the argument", ["vertex", "fragment"]);
		var vk = r.func("vertex"), fk = r.func("fragment");
		if (vk == null) a.error(fk == null ? "a shader needs a vertex and a fragment function" : "a shader with a fragment function needs a vertex function", arg.pos);
		if (fk == null) a.error("a shader with a vertex function needs a fragment function", arg.pos);
		return output(a, vk, fk, arg.pos, false);
	}

	// a slot object's variant (Slots): its stages with its slots' functions
	// and its options' values inlined, what they never read of the optional
	// fields (attributes, varyings, parameters) dropped
	public function variant(def:SlotsDef, options:Null<KNode>, a:ShaderAdapter, pos:KPos):ShaderOutput {
		a.useSlots({options: def.values(options, a), slots: def.slots});
		return output(a, def.vertex, def.fragment, pos, true);
	}

	function output(a:ShaderAdapter, vk:KFunction, fk:KFunction, pos:KPos, variant:Bool):ShaderOutput {
		var p = program(a, vk, fk, variant);
		var android = StringTools.startsWith(a.defined("hxmc.target") ?? "", "android");
		function stage(e:SEntry):StageCode
			return {
				code: [
					for (l in languages(a, pos))
						{
							language: l,
							text: switch l {
								// (Android: structs through make_ functions, Glsl.makers)
								case "glsl": new Glsl(android).stage(p, e);
								case "wgsl": new Wgsl().stage(p, e);
								case "msl": new Msl().stage(p, e);
								case _: new Hlsl().stage(p, e);
							}
						}
				],
				// (GL binds them by their GLSL names, WebGPU makes its bind group layout of them)
				bindings: [for (u in e.uniforms) {name: u.struct.name + "_block", slot: u.binding, uniform: true, size: u.size, dimension: 0}].concat([
					for (t in e.textures)
						{name: "tex_" + t.slot, slot: t.slot, uniform: false, size: 0, dimension: t.dimension}
				])
			};
		var attributes:Array<{field:String, components:Int, offset:Int}> = [], off = 0;
		for (f in p.vertex.input.fields) {
			var n = switch f.type {
				case TVec(n): n;
				case _: 1;
			}
			attributes.push({field: f.field, components: n, offset: off});
			off += 4 * n;
		}
		// the parameters by name (a writer per uniform block, a slot per
		// texture), the vertex stage's first; a name both stages take is one
		// resource
		var params:Array<ShaderParam> = [];
		for (s in [{e: p.vertex, k: vk}, {e: p.fragment, k: fk}])
			for (i in 0...s.e.resources.length) {
				var name = s.e.fn.fields[i], r = s.e.resources[i];
				var other = Lambda.find(params, x -> x.name == name);
				if (other == null) params.push({name: name, resource: r}) else if (!same(other.resource, r))
					a.error('the parameter $name is two resources (each stage\'s $name the same uniform block or texture)', s.k.pos);
			}
		var block = a.uniforms();
		return {
			program: p,
			vertex: stage(p.vertex),
			fragment: stage(p.fragment),
			attributes: attributes,
			stride: off,
			params: params,
			uniforms: block == null ? null : Lambda.find(p.uniforms, u -> u.struct == block)
		};
	}

	static function same(a:SResource, b:SResource):Bool
		return switch [a, b] {
			case [RUniform(x), RUniform(y)]: x == y;
			case [RTexture(x), RTexture(y)]: x == y;
			case _: false;
		}

	// compute({size, main}): the compute stage (its input a ComputeInput, its
	// result none), the fields of its object of parameters uniform blocks
	// (std140), textures, storage buffers (std430) and storage textures at
	// slots in order of appearance, its text in the build's languages
	public function compute(arg:KNode, a:ShaderAdapter):ComputeOutput {
		var r = new KObjectReader(arg, a, "the argument", ["size", "main"]);
		var mk = r.func("main");
		if (mk == null) a.error("a compute definition needs its main function", arg.pos);
		var size = [1, 1, 1];
		var sn = r.get("size");
		if (sn != null) {
			var items = switch sn.value {
				case KArray(xs) if (xs.length >= 1 && xs.length <= 3): xs;
				case KInt(_): [sn];
				case _: a.error('size is the workgroup\'s size, an array of 1 to 3 integers ([64], [8, 8]), not ${sn.describe()}', sn.pos);
			}
			for (i in 0...items.length)
				size[i] = switch items[i].value {
					case KInt(n) if (n >= 1): n;
					case KFloat(f) if (f >= 1 && Math.ffloor(f) == f): Std.int(f);
					case _: a.error('size: ${items[i].describe()} is not a positive integer', items[i].pos);
				}
		}
		// (256 invocations a workgroup at most: WebGPU's default limit; GL ES 3.1's and D3D11's are higher)
		if (size[0] * size[1] * size[2] > 256) a.error('size: ${size.join(" x ")} is more than 256 invocations a workgroup (WebGPU\'s default limit)', sn.pos);
		var f = a.lowerStage(mk, mk.name ?? "cs");
		var pos = mk.pos;
		var input = f.params.length == 0 ? null : switch f.params[0].type {
			case TStruct(s) if (s.path == "helder.gfx.shader.ComputeInput"): s;
			case _: null;
		}
		if (input == null) a.error("the compute function takes the invocation's ids first (id:ComputeInput)", pos);
		if (f.ret != TVoid) a.error('the compute function returns nothing (it writes its storage), not a ${Names.typeName(f.ret)}', pos);
		var resources:Array<SResource> = [];
		var written = 0;
		for (i in 1...f.params.length)
			switch f.params[i].type {
				case TStorage(_, true): written++;
				case _:
			}
		// (indices: a storage buffer's binding in GL, the read ones after the
		// written ones; a written buffer's or texture's u register in HLSL;
		// a storage texture's image unit in GL)
		var reads = 0, uavs = 0, images = 0;
		for (i in 1...f.params.length) {
			var p = f.params[i], name = f.fields[i - 1] ?? p.name, slot = i - 1;
			resources.push(switch p.type {
				case TStruct(s):
					for (r in resources)
						switch r {
							case RUniform(u) if (u.struct == s): a.error('the parameter $name is a second ${s.path} (a uniform block a struct: one parameter of it)', pos);
							case _:
						}
					RUniform(std140(a, s, slot, pos));
				case TTexture | TTextureCube | TTextureArray: RTexture(new STexture(p.name, slot, Textures.dimension(p.type)));
				case TStorage(e, write):
					var l = std430(a, e, name, pos);
					RStorage(new SStorage(name, slot, e, write, l.offsets, l.stride, write ? uavs++ : written + reads++));
				case TImage(format):
					RImage(new SImage(name, slot, format, images++, uavs++));
				case t: a.error('the parameter $name is a ${Names.typeName(t)}, not a uniform block (a struct), a Texture2D, TextureCube or Texture2DArray, a Storage, an RWStorage or a StorageTexture', pos);
			});
		}
		if (resources.length > MAX_SLOTS) a.error('more than $MAX_SLOTS uniform blocks, textures and storage buffers', pos);
		// (D3D11's compute stage has 8 UAVs; GL ES 3.1's devices 4 storage buffers and 4 images at least)
		if (uavs > 8) a.error('more than 8 storage buffers and textures written (D3D11\'s UAVs)', pos);
		a.finish();
		var c = new SCompute(entry(Compute, f, input, resources), size);
		var bindings = [
			for (r in resources)
				switch r {
					case RUniform(u): {name: u.struct.name + "_block", slot: u.binding, kind: 0, size: u.size, index: u.binding, format: 0, dimension: 0};
					case RTexture(t): {name: "tex_" + t.slot, slot: t.slot, kind: 1, size: 0, index: t.slot, format: 0, dimension: t.dimension};
					case RStorage(s): {name: "sb_" + s.slot, slot: s.slot, kind: s.write ? 3 : 2, size: s.stride, index: s.index, format: 0, dimension: 0};
					case RImage(m): {name: "img_" + m.slot, slot: m.slot, kind: 4, size: 0, index: m.index, format: m.format, dimension: 0};
				}
		];
		var params:Array<ShaderParam> = [for (i in 0...resources.length) {name: f.fields[i], resource: resources[i]}];
		var block = a.uniforms();
		return {
			program: c,
			code: [
				for (l in languages(a, arg.pos))
					{
						language: l,
						text: switch l {
							case "glsl": new Glsl(StringTools.startsWith(a.defined("hxmc.target") ?? "", "android")).compute(c);
							case "wgsl": new Wgsl().compute(c);
							case "msl": new Msl().compute(c);
							case _: new Hlsl().compute(c);
						}
					}
			],
			bindings: bindings,
			params: params,
			uniforms: block == null ? null : Lambda.find(c.entry.uniforms, u -> u.struct == block)
		};
	}

	// std430 (WGSL's storage layout, MSL's and C's for these types): a
	// storage buffer's element, a scalar, a Vec2, Vec4, Mat4 or a struct of
	// them, its offsets (a struct's fields) and the stride of the array
	public static function std430(a:Adapter, t:SType, name:String, pos:KPos):{offsets:Array<Int>, stride:Int} {
		function sizeAlign(t:SType, what:String):Array<Int>
			return switch t {
				case TFloat | TInt: [4, 4];
				case TVec(2): [8, 8];
				case TVec(4): [16, 16];
				case TMat4: [64, 16];
				case TVec(3): a.error('$what is a Vec3: a storage buffer has no Vec3 (16 bytes in std430 and WGSL, 12 in HLSL): pack it into a Vec4', pos);
				case t: a.error('$what is a ${Names.typeName(t)}: a storage buffer\'s elements are Float, Int, Vec2, Vec4, Mat4 or structs of those', pos);
			}
		return switch t {
			case TStruct(s):
				var off = 0, align = 4, offsets = [];
				for (f in s.fields) {
					var sa = sizeAlign(f.type, '${s.path}.${f.field}');
					off = (off + sa[1] - 1) & ~(sa[1] - 1);
					offsets.push(off);
					off += sa[0];
					if (sa[1] > align) align = sa[1];
				}
				{offsets: offsets, stride: (off + align - 1) & ~(align - 1)};
			case t:
				{offsets: [0], stride: sizeAlign(t, 'the storage $name\'s element')[0]};
		}
	}

	function program(a:ShaderAdapter, vk:KFunction, fk:KFunction, variant:Bool):SProgram {
		var vf = a.lowerStage(vk, vk.name ?? "vs"), ff = a.lowerStage(fk, fk.name ?? "fs");
		var vpos = vk.pos, fpos = fk.pos;
		if (variant) Prune.program(vf, ff);
		if (vf.params.length == 0) a.error("the vertex function takes no vertex", vpos);
		var input = switch vf.params[0].type {
			case TStruct(s): s;
			case t: a.error('the vertex function\'s vertex is a ${Names.typeName(t)}, not a struct', vpos);
		}
		for (f in input.fields)
			switch f.type {
				case TFloat | TVec(_):
				case t: a.error('the vertex function: ${input.path}.${f.field} is a ${Names.typeName(t)}: vertex attributes are Float, Vec2, Vec3 or Vec4', vpos);
			}
		var varyings = switch vf.ret {
			case TStruct(s): s;
			case t: a.error('the vertex function returns a ${Names.typeName(t)}, not a struct of varyings', vpos);
		}
		var positions = 0;
		for (f in varyings.fields)
			switch f.type {
				case TVec(4) if (f.position): positions++;
				case t if (f.position): a.error('the vertex function: the position(...) ${varyings.path}.${f.field} is a ${Names.typeName(t)}, not a Vec4', vpos);
				case TFloat | TVec(_):
				case t: a.error('the vertex function: the varying ${varyings.path}.${f.field} is a ${Names.typeName(t)}: varyings are Float, Vec2, Vec3 or Vec4', vpos);
			}
		if (positions != 1)
			a.error('the vertex function: exactly one field of ${varyings.path} is the clip-space position, marked by position(...) where it is built (it has $positions)',
				vpos);
		if (ff.params.length == 0 || !Names.same(ff.params[0].type, vf.ret))
			a.error('stage interface mismatch: the fragment function takes ' + (ff.params.length == 0 ? "nothing" : Names.typeName(ff.params[0].type))
				+ ', but the vertex function returns ${Names.typeName(vf.ret)}', fpos);
		if (!Names.same(ff.ret, TVec(4))) a.error('the fragment function returns a ${Names.typeName(ff.ret)}, not a Vec4 (the colour)', fpos);
		// resources: the further parameters, uniform blocks (a slot per struct)
		// and textures (a slot per name), slots in order of appearance
		var uniforms:Array<SUniform> = [], textures:Array<STexture> = [];
		function resources(f:SFunction, k:KFunction):Array<SResource>
			return [
				for (i in 1...f.params.length) {
					var p = f.params[i], name = f.fields[i - 1] ?? p.name;
					var slot = uniforms.length + textures.length;
					switch p.type {
						case TStruct(s):
							var u = Lambda.find(uniforms, u -> u.struct == s);
							if (u == null) {
								u = std140(a, s, slot, k.pos);
								uniforms.push(u);
							}
							RUniform(u);
						case TTexture | TTextureCube | TTextureArray:
							var t = Lambda.find(textures, t -> t.name == p.name);
							if (t == null) {
								t = new STexture(p.name, slot, Textures.dimension(p.type));
								textures.push(t);
							}
							RTexture(t);
						case t: a.error('the parameter $name is a ${Names.typeName(t)}, not a uniform block (a struct) or a texture (Texture2D, TextureCube, Texture2DArray)', k.pos);
					}
				}
			];
		var vr = resources(vf, vk), fr = resources(ff, fk);
		if (uniforms.length + textures.length > MAX_SLOTS) a.error('more than $MAX_SLOTS uniform blocks and textures', vpos);
		a.finish();
		return new SProgram(entry(Vertex, vf, input, vr), entry(Fragment, ff, varyings, fr), uniforms, textures);
	}

	// the stage's function and what it reaches, in declaration order
	static function entry(stage:SStage, f:SFunction, input:SStruct, resources:Array<SResource>):SEntry {
		var fs:Array<SFunction> = [], ss:Array<SStruct> = [];
		function ty(t:SType)
			switch t {
				case TStruct(s) if (!ss.contains(s)):
					for (f in s.fields)
						ty(f.type);
					ss.push(s);
				case TStorage(e, _): ty(e);
				case _:
			}
		function visit(f:SFunction) {
			if (fs.contains(f)) return;
			for (p in f.params)
				ty(p.type);
			ty(f.ret);
			function e(x:SExpr) {
				ty(x.t);
				switch x.e {
					case EField(a, _) | ESwizzle(a, _) | EColumn(a, _) | EUnop(_, a) | EConvert(a): e(a);
					case EIndex(a, i):
						e(a);
						e(i);
					case EBinop(_, a, b):
						e(a);
						e(b);
					case ECond(c, a, b):
						e(c);
						e(a);
						e(b);
					case ENew(args) | EBuiltin(_, args): for (a in args) e(a);
					case ECall(g, args):
						for (a in args)
							e(a);
						visit(g);
					case EFloat(_) | EInt(_) | EBool(_) | ELocal(_):
				}
			}
			function s(st:SStmt)
				switch st {
					case SDecl(v, init):
						ty(v.type);
						if (init != null) e(init);
					case SAssign(_, _, x) | SEval(x): e(x);
					case SIf(c, a, b):
						e(c);
						for (x in a)
							s(x);
						if (b != null) for (x in b)
							s(x);
					case SWhile(c, body):
						e(c);
						for (x in body)
							s(x);
					case SReturn(x): if (x != null) e(x);
					case SStore(b, i, v):
						e(b);
						e(i);
						e(v);
					case SBreak | SContinue:
				}
			for (st in f.body)
				s(st);
			fs.push(f);
		}
		visit(f);
		for (r in resources)
			switch r {
				case RUniform(u): ty(TStruct(u.struct));
				case RStorage(s): ty(s.element);
				case RTexture(_) | RImage(_):
			}
		return new SEntry(stage, f, input, resources, ss, fs);
	}

	// std140 (and WGSL's uniform layout, the same for these types)
	static function std140(a:Adapter, s:SStruct, binding:Int, pos:KPos):SUniform {
		var off = 0, offsets = [];
		for (f in s.fields) {
			var size = 0, align = 0;
			switch f.type {
				case TFloat | TInt:
					size = align = 4;
				case TVec(n):
					size = 4 * n;
					align = n == 2 ? 8 : 16;
				case TMat4:
					size = 64;
					align = 16;
				case TArray(t, n):
					size = (t == TMat4 ? 64 : 16) * n;
					align = 16;
				case t: a.error('the uniform ${s.path}.${f.field} is a ${Names.typeName(t)}: uniforms are Float, Int, vectors, Mat4 and arrays of Vec4 or Mat4', pos);
			}
			off = (off + align - 1) & ~(align - 1);
			offsets.push(off);
			off += size;
		}
		return new SUniform(s, binding, offsets, (off + 15) & ~15);
	}

	// the build's shader languages: -D helder.gfx.shaders=glsl,wgsl,msl,hlsl (or
	// all); else the target's (hxmc: -D hxmc.target or the host: GLSL on Linux,
	// MSL on macOS, HLSL on Windows, GLSL and WGSL on wasm32-wasi), and all
	// four on other targets (Eval: the tests)
	public static function languages(a:Adapter, pos:KPos):Array<String> {
		var all = ["glsl", "wgsl", "msl", "hlsl"];
		var d = a.defined("helder.gfx.shaders");
		if (d != null) {
			if (d == "all" || d == "1") return all;
			var ls = d.split(",");
			for (l in ls)
				if (!all.contains(l)) a.error('-D helder.gfx.shaders: no shader language $l (glsl, wgsl, msl, hlsl, all)', pos);
			return ls;
		}
		if (a.defined("target.name") != "hxmc") return all;
		var t = a.defined("hxmc.target");
		if (t == null) t = switch Sys.systemName() {
			case "Mac": "macos";
			case "Windows": "windows";
			case _: "linux";
		}
		return t == "wasm32-wasi" ? ["glsl", "wgsl"] : StringTools.startsWith(t, "macos")
			|| StringTools.startsWith(t, "ios") ? ["msl"] : StringTools.startsWith(t, "windows") ? ["hlsl"] : ["glsl"];
	}
}

// What the handler makes of a shader: the program, each stage's text and
// bindings, the vertex buffer's attributes (each a field of the vertex,
// Float32 components packed in order) and the parameters (the fields of
// the stages' objects of parameters: a uniform block's writer each, Ir's
// SUniform has the std140 offsets, or a texture's slot).
typedef ShaderOutput = {
	program:SProgram,
	vertex:StageCode,
	fragment:StageCode,
	attributes:Array<{field:String, components:Int, offset:Int}>,
	stride:Int,
	params:Array<ShaderParam>,
	// (the uniform(...)s' block, its fields the constants' names: params.uniforms)
	uniforms:Null<SUniform>
}

typedef ShaderParam = {
	name:String,
	resource:SResource
}

// what a slot object's variant lowers its stages with (ShaderAdapter.useSlots)
typedef SlotsUse = {
	options:Map<String, KValue>,
	slots:Map<String, KNode>
}

// A slot object's definition (Slots: slots({vertex, fragment, options,
// <slot>: ...})): its stages, which take the object as their third
// parameter, its options' defaults (literals) and its slots (functions,
// module-level ones by name); with(...) the same with some slots replaced.
class SlotsDef {
	public final vertex:KFunction;
	public final fragment:KFunction;
	public final options:Map<String, KNode>;
	public final optionOrder:Array<String>;
	public final slots:Map<String, KNode>;
	public final slotOrder:Array<String>;

	function new(vertex, fragment, options, optionOrder, slots, slotOrder) {
		this.vertex = vertex;
		this.fragment = fragment;
		this.options = options;
		this.optionOrder = optionOrder;
		this.slots = slots;
		this.slotOrder = slotOrder;
	}

	public static function read(arg:KNode, a:Adapter):SlotsDef {
		var fields = switch arg.value {
			case KObject(fs): fs;
			case _: a.error('a slot object is an object literal ({vertex, fragment, options, <slot>: ...}), not ${arg.describe()}', arg.pos);
		}
		var vertex:Null<KFunction> = null, fragment:Null<KFunction> = null;
		var options = new Map<String, KNode>(), optionOrder = [], slots = new Map<String, KNode>(), slotOrder = [];
		for (f in fields)
			switch [f.name, f.node.value] {
				case ["vertex", KFunction(k)]: vertex = k;
				case ["fragment", KFunction(k)]: fragment = k;
				case ["vertex" | "fragment", _]: a.error('${f.name} is a function, not ${f.node.describe()}', f.node.pos);
				case ["options", KObject(os)]:
					for (o in os) {
						switch o.node.value {
							case KBool(_) | KInt(_) | KFloat(_):
							case _: a.error('the option ${o.name} is a boolean or a number, not ${o.node.describe()}', o.node.pos);
						}
						options.set(o.name, o.node);
						optionOrder.push(o.name);
					}
				case ["options", _]: a.error('options is an object of booleans and numbers, not ${f.node.describe()}', f.node.pos);
				case [_, KFunction(_) | KRef(_)]:
					slots.set(f.name, f.node);
					slotOrder.push(f.name);
				case [_, _]: a.error('the slot ${f.name} is a function, not ${f.node.describe()}', f.node.pos);
			}
		if (vertex == null || fragment == null) a.error("a slot object has a vertex and a fragment function", arg.pos);
		return new SlotsDef(vertex, fragment, options, optionOrder, slots, slotOrder);
	}

	// the same with some slots' functions replaced (an object of them)
	public function with(overrides:KNode, a:Adapter):SlotsDef {
		var fields = switch overrides.value {
			case KObject(fs): fs;
			case _: a.error('with takes an object of slots\' functions, not ${overrides.describe()}', overrides.pos);
		}
		var next = new Map<String, KNode>();
		for (k => v in slots)
			next.set(k, v);
		for (f in fields) {
			if (!slots.exists(f.name)) a.error('the slot object has no slot ${f.name} (it has ' + slotOrder.join(", ") + ")", f.node.pos);
			switch f.node.value {
				case KFunction(_) | KRef(_):
				case _: a.error('the slot ${f.name} is a function, not ${f.node.describe()}', f.node.pos);
			}
			next.set(f.name, f.node);
		}
		return new SlotsDef(vertex, fragment, options, optionOrder, next, slotOrder);
	}

	// the options' values: the defaults, those given replaced
	public function values(given:Null<KNode>, a:Adapter):Map<String, KValue> {
		var out = new Map<String, KValue>();
		for (k => v in options)
			out.set(k, v.value);
		if (given == null) return out;
		var fields = switch given.value {
			case KObject(fs): fs;
			case _: a.error('a variant\'s options are an object literal, not ${given.describe()}', given.pos);
		}
		for (f in fields) {
			var d = options.get(f.name);
			if (d == null) a.error('the slot object has no option ${f.name} (it has ' + optionOrder.join(", ") + ")", f.node.pos);
			switch [d.value, f.node.value] {
				case [KBool(_), KBool(_)] | [KInt(_) | KFloat(_), KInt(_) | KFloat(_)]:
				case _: a.error('the option ${f.name} is ${d.describe()}, not ${f.node.describe()}', f.node.pos);
			}
			out.set(f.name, f.node.value);
		}
		return out;
	}
}

// What the handler makes of a compute definition: the stage, its text in
// the build's languages, its bindings (ShaderBinding's: kind 0 a uniform
// block, 1 a texture, 2 a storage buffer read, 3 one written, 4 a storage
// texture; index its binding in GL and its register in HLSL where that is
// not the slot) and its parameters.
typedef ComputeOutput = {
	program:SCompute,
	code:Array<{language:String, text:String}>,
	bindings:Array<{name:String, slot:Int, kind:Int, size:Int, index:Int, format:Int, dimension:Int}>,
	params:Array<ShaderParam>,
	uniforms:Null<SUniform>
}

typedef StageCode = {
	code:Array<{language:String, text:String}>,
	bindings:Array<{name:String, slot:Int, uniform:Bool, size:Int, dimension:Int}>
}
