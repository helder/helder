package helder.scene.render;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import helder.definition.HaxeAdapter;
import helder.definition.Kernel;
import helder.gfx.shader.Ir;
import helder.gfx.shader.ShaderDefinition;
import helder.gfx.shader.SlotsMacro;
#end

// A material's own shader (DESIGN.md 3 in src/helder/compiler): pbr (the
// standard material, PbrShader) with some of its slots replaced, compiled
// at build time into the variants the renderer draws with (plain, normal
// mapped, skinned, instanced, instanced and normal mapped), set on a
// Material (material.shader) as the shader its primitives are drawn with.
// Another slot object of the renderer's vertex and parameters (shading's
// unlit) works too: one without pbr's normalMap option has no normal-mapped
// variants (null; its primitives drawn without their normal maps):
//
//   final Glow = MaterialShader.material(pbr.with({
//     emissive: function(s, p:{glow:GlowParams}):Vec3 return p.glow.color.xyz * (0.5 + 0.5 * sin(p.glow.time.x)),
//     color: function(s, p:{}):Vec3 return s.baseColor.xyz * 1.5
//   }));
//   material.shader = Glow;
//   material.uniforms = ["glow" => bytes];   // its own block: Glow.params.glow.write(...)
//
// A slot's parameters are the stage's of the same names (the material's
// block and textures, the frame's); the others are uniform blocks of the
// material's own, bound from material.uniforms by their parameter's name
// (params: the plain variant's writers, typed; the class is the material's
// own, made beside its module). A material that replaces the position,
// normal, roughness or alpha slot also gets the view buffers' prepass
// variants (prepass, prepassInstanced: ViewBuffers); one that replaces none
// is drawn there by the standard material's, which is the same.
class MaterialShader {
	@:typescript public final plain:AnyShader;
	@:typescript public final normalMapped:Null<AnyShader>;
	@:typescript public final skinned:AnyShader;
	@:typescript public final instanced:AnyShader;
	@:typescript public final instancedNormalMapped:Null<AnyShader>;
	// the view buffers' (ViewBuffers): plain and instanced; null, the
	// standard material's (its position, normal, roughness and alpha slots
	// as they are)
	@:typescript public final prepass:Null<AnyShader>;
	@:typescript public final prepassInstanced:Null<AnyShader>;
	// the blocks of the material's own: its parameter's name, its slot, in
	// each variant (in the order above; -1: not in it)
	@:typescript public final blocks:Array<{name:String, bindings:Array<Int>}>;

	public function new(plain, normalMapped, skinned, instanced, instancedNormalMapped, blocks, ?prepass, ?prepassInstanced) {
		this.plain = plain;
		this.normalMapped = normalMapped;
		this.skinned = skinned;
		this.instanced = instanced;
		this.instancedNormalMapped = instancedNormalMapped;
		this.blocks = blocks;
		this.prepass = prepass;
		this.prepassInstanced = prepassInstanced;
	}

	// the slots whose replacement the view buffers' prepass draws (the others' are not read there)
	public static final PREPASS_SLOTS = ["position", "normal", "roughness", "alpha"];

	// a TypeScript program's material (helder/scene's material(pbr.with({...})),
	// a definition: helder.typescript.lower's Definitions compiles the same
	// variants and passes them here, JSON)
	@:typescript public static function script(json:String):MaterialShader {
		var d:Dynamic = haxe.Json.parse(json);
		var vs:Array<Dynamic> = d.variants;
		var s = [for (v in vs) v == null ? null : shaderOf(v)];
		var bs:Array<Dynamic> = d.blocks;
		return new MaterialShader(s[0], s[1], s[2], s[3], s[4], [for (b in bs) {name: (b.name : String), bindings: [for (x in (b.bindings : Array<Dynamic>)) (x : Int)]}],
			s.length > 5 ? s[5] : null, s.length > 6 ? s[6] : null);
	}

	static function shaderOf(v:Dynamic):AnyShader {
		function code(c:Dynamic):helder.gfx.ShaderCode {
			var bs:Array<Dynamic> = c.bindings;
			return {
				glsl: c.glsl,
				msl: c.msl,
				hlsl: c.hlsl,
				wgsl: c.wgsl,
				bindings: [
					for (b in bs)
						{name: (b.name : String), slot: (b.slot : Int), kind: (cast(b.kind : Int) : helder.gfx.ShaderBinding.BindingKind), size: (b.size : Null<Int>)}
				]
			};
		}
		var ls:Array<Dynamic> = v.layout, us:Array<Dynamic> = v.uniforms, ts:Array<Dynamic> = v.textures;
		var layout:Array<helder.gfx.VertexBufferLayout> = [
			for (l in ls) {
				var as:Array<Dynamic> = l.attributes;
				{stride: (l.stride : Int), attributes: [for (a in as) {location: (a.location : Int), format: (cast(a.format : Int) : helder.gfx.VertexFormat), offset: (a.offset : Int)}]};
			}
		];
		return new helder.gfx.shader.Shader<Dynamic, Dynamic>(code(v.vertexCode), code(v.fragmentCode), layout,
			[for (u in us) {name: (u.name : String), binding: (u.binding : Int), size: (u.size : Int)}], [for (t in ts) {name: (t.name : String), binding: (t.binding : Int)}],
			_ -> throw "MaterialShader: a TypeScript material's vertices are the renderer's", null);
	}

	// the material's variants of a slot object made from pbr (pbr.with({...}))
	public static macro function material(def:Expr):Expr {
		var pos = Context.currentPos();
		var a = new HaxeAdapter("material");
		var typed = Context.typeExpr(def);
		var kinds:Array<Array<String>> = [[], ["normalMap"], ["skinned"], ["instanced"], ["instanced", "normalMap"], ["prepass"], ["prepass", "instanced"]];
		// (the kinds of draw its options have: a slot object without normalMap, none normal mapped)
		var first = SlotsMacro.resolve(typed, new helder.gfx.shader.Lower(), a);
		var options = first.def.options;
		// (the prepass's variants only when a slot it reads is replaced)
		var replaced = false;
		for (s in PREPASS_SLOTS)
			if (first.def.slots.exists(s) && first.def.slots.get(s) != first.defaults.get(s)) replaced = true;
		if (!replaced) kinds = kinds.slice(0, 5);
		var standard = ["PbrFrame", "PbrObject", "PbrMaterial", "PbrSkinInfo", "PbrPrepass"];
		var textures = [
			"baseColorTexture", "metallicRoughnessTexture", "emissiveTexture", "occlusionTexture", "shadowMap", "shadowMapFar", "environmentMap", "normalTexture",
			"jointMatrices", "aoMap"
		];
		var shaders = [], blocks = new Map<String, Array<Int>>(), order = [];
		for (k in 0...kinds.length) {
			if (!Lambda.foreach(kinds[k], o -> options.exists(o))) {
				shaders.push(null);
				continue;
			}
			var lower = new helder.gfx.shader.Lower();
			var r = SlotsMacro.resolve(typed, lower, a);
			var given = new KNode(KObject([for (o in kinds[k]) {name: o, node: new KNode(KBool(true), pos)}]), pos);
			var out = new ShaderDefinition().variant(r.def, given, lower, pos);
			for (p in out.params)
				switch p.resource {
					case RUniform(u) if (!standard.contains(u.struct.name)):
						if (!blocks.exists(p.name)) {
							blocks.set(p.name, [for (_ in 0...7) -1]);
							order.push(p.name);
						}
						blocks.get(p.name)[k] = u.binding;
					case RTexture(t) if (!textures.contains(p.name)):
						Context.error('material: the texture ${p.name} is not one the renderer binds (a slot\'s textures are the material\'s: ' + textures.join(", ") + ")", pos);
					case _:
				}
			// (drawn on the GPU only: no CPU stages, none of their code linked;
			// the plain variant's params the writers, the others' none)
			shaders.push(SlotsMacro.build(r, r.def.values(given, a), out, lower, false, k > 0));
		}
		var bs = [for (n in order) macro {name: $v{n}, bindings: $v{blocks.get(n)}}];
		// (its own class: params, the plain variant's, typed)
		var pt = Context.toComplexType(Context.typeof(macro ${shaders[0]}.params));
		var module = Context.getLocalModule(), field = Context.getLocalMethod() ?? "material";
		var pack = module.split(".");
		var base = pack.pop() + "_" + field + "_material";
		var cls = macro class Material extends helder.scene.render.MaterialShader {
			public final params:$pt;

			public function new(params:$pt, plain, normalMapped, skinned, instanced, instancedNormalMapped, blocks, ?prepass, ?prepassInstanced) {
				super(plain, normalMapped, skinned, instanced, instancedNormalMapped, blocks, prepass, prepassInstanced);
				this.params = params;
			}
		};
		var name = base + "_" + haxe.crypto.Md5.encode(new haxe.macro.Printer().printTypeDefinition(cls)).substr(0, 8);
		cls.name = name;
		cls.pack = pack;
		cls.pos = pos;
		cls.meta = [{name: ":noCompletion", pos: pos}];
		var exists = try Context.getType(pack.concat([name]).join(".")) != null catch (_:Dynamic) false;
		if (!exists) Context.defineType(cls, module);
		var tp:TypePath = {pack: pack, name: name};
		function shader(i:Int):Expr
			return shaders[i] == null ? macro null : macro(cast ${shaders[i]} : helder.scene.render.MaterialShader.AnyShader);
		var any = [for (i in 1...5) shader(i)];
		var pre = [for (i in 5...shaders.length) shader(i)];
		var made:Expr = {
			expr: ENew(tp, [macro plain.params, macro(cast plain : helder.scene.render.MaterialShader.AnyShader)].concat(any).concat([macro [$a{bs}]]).concat(pre)),
			pos: pos
		};
		return macro {
			var plain = ${shaders[0]};
			$made;
		};
	}
}

typedef AnyShader = helder.gfx.shader.Shader<Dynamic, Dynamic>;
