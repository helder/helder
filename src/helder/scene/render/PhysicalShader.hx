package helder.scene.render;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

// The physical materials' shaders (DESIGN-3D.md 1.3): pbr with the glTF
// material extensions a material uses as its options (PbrOptions' sheen,
// specular, clearcoat, transmission, iridescence, anisotropy), its direct
// and indirect slots the physical ones (PbrShader's physicalDirect and
// physicalIndirect, which read the layers the options fill), compiled at
// build time into the renderer's variants (a MaterialShader, its
// extensions set: Material.extensions' flags):
//
//   material.shader = PhysicalShader.of({sheen: true, clearcoat: true});
//
// Each set of options is its own module (helder.scene.render.physical.
// Physical<flags>), made once a build however often it is named, linked
// only where it is: Model.of names the sets its file's materials use, so a
// game links the extensions its models have and no others; a model loaded
// at run time (Model.load) is drawn by Physical's, every extension's.
class PhysicalShader {
	// the extensions' names, in their flags' order (Material.SHEEN ...)
	public static final NAMES = ["sheen", "specular", "clearcoat", "transmission", "iridescence", "anisotropy", "uvSets"];

	// every extension's (Physical's)
	public static inline var ALL = 127;

	// the shader of a set of extensions, an object of them ({sheen: true, ...})
	public static macro function of(options:Expr):Expr {
		var flags = 0;
		switch options.expr {
			case EObjectDecl(fs):
				for (f in fs) {
					var k = NAMES.indexOf(f.field);
					if (k < 0) Context.error('PhysicalShader: ${f.field} is not an extension (' + NAMES.join(", ") + ")", f.expr.pos);
					switch f.expr.expr {
						case EConst(CIdent("true")): flags |= 1 << k;
						case EConst(CIdent("false")):
						case _: Context.error("PhysicalShader: an extension is true or false, a constant", f.expr.pos);
					}
				}
			case _:
				Context.error("PhysicalShader.of: an object of the extensions ({sheen: true})", options.pos);
		}
		if (flags == 0) Context.error("PhysicalShader.of: no extension (the standard shader is null's)", options.pos);
		return shader(flags);
	}

	#if macro
	// the shader of a set of extensions' flags: its module made the first time
	public static function shader(flags:Int):Expr {
		var name = "Physical" + flags;
		var path = "helder.scene.render.physical." + name;
		var exists = try Context.getType(path) != null catch (_:Dynamic) false;
		if (!exists) {
			var pos = Context.currentPos();
			var fields:Array<ObjectField> = [for (k in 0...NAMES.length) {field: NAMES[k], expr: (flags & (1 << k)) != 0 ? macro true : macro false}];
			var options:Expr = {expr: EObjectDecl(fields), pos: pos};
			// (uvSets: the metallic-roughness and emissive maps at their own uvs)
			var slots = (flags & 64) != 0 ? macro {
				direct: helder.scene.render.PbrShader.physicalDirect,
				indirect: helder.scene.render.PbrShader.physicalIndirect,
				metalness: helder.scene.render.PbrShader.physicalMetalness,
				roughness: helder.scene.render.PbrShader.physicalRoughness,
				emissive: helder.scene.render.PbrShader.physicalEmissive
			} : macro {
				direct: helder.scene.render.PbrShader.physicalDirect,
				indirect: helder.scene.render.PbrShader.physicalIndirect
			};
			var cls = macro class $name {
				// (the variants: pbr's with the physical slots, these extensions on)
				public static final shader:helder.scene.render.MaterialShader = {
					var s = helder.scene.render.MaterialShader.material(helder.scene.render.PbrShader.pbr.with($slots), $options);
					s.extensions = $v{flags};
					s.layers = helder.scene.render.PhysicalLayers.INSTANCE;
					s;
				};
			};
			cls.pack = ["helder", "scene", "render", "physical"];
			cls.meta = [{name: ":noCompletion", pos: pos}];
			Context.defineModule(path, [cls]);
		}
		var parts = path.split(".");
		return macro @:pos(Context.currentPos()) $p{parts.concat(["shader"])};
	}

	// the flags of a glTF file's materials' extensions (Model.of's), as the
	// materials made of them have (Material.extensions)
	public static function flagsOfFile(bytes:haxe.io.Bytes):Array<Int> {
		var root:Dynamic = haxe.Json.parse(helder.scene.gltf.GltfFile.split(bytes).json);
		var ms:Dynamic = Reflect.field(root, "materials");
		if (!Std.isOfType(ms, Array)) return [];
		function obj(o:Dynamic, f:String):Dynamic
			return o == null ? null : Reflect.field(o, f);
		function num(o:Dynamic, f:String, d:Float):Float {
			var v:Dynamic = obj(o, f);
			return Std.isOfType(v, Float) || Std.isOfType(v, Int) ? (v : Float) : d;
		}
		function rgb(o:Dynamic, f:String, d:Float):Array<Float> {
			var v:Dynamic = obj(o, f);
			return Std.isOfType(v, Array) && v.length == 3 ? [for (x in (v : Array<Dynamic>)) (x : Float)] : [d, d, d];
		}
		return [
			for (m in (ms : Array<Dynamic>)) {
				// (Gltf.read's defaults)
				var e = obj(m, "extensions");
				var sheen = rgb(obj(e, "KHR_materials_sheen"), "sheenColorFactor", 0);
				var sp = obj(e, "KHR_materials_specular");
				var spc = rgb(sp, "specularColorFactor", 1);
				var pbr = obj(m, "pbrMetallicRoughness");
				var maps:Array<Null<Array<Float>>> = [
					for (t in [obj(pbr, "baseColorTexture"), obj(pbr, "metallicRoughnessTexture"), obj(m, "normalTexture"), obj(m, "occlusionTexture"), obj(m, "emissiveTexture")]) {
						if (t == null) null else {
							var x = obj(obj(t, "extensions"), "KHR_texture_transform");
							var o:Dynamic = obj(x, "offset"), s:Dynamic = obj(x, "scale");
							var two = (v:Dynamic, k:Int, d:Float) -> Std.isOfType(v, Array) && v.length == 2 ? (v[k] : Float) : d;
							[num(x, "texCoord", num(t, "texCoord", 0)), two(o, 0, 0), two(o, 1, 0), num(x, "rotation", 0), two(s, 0, 1), two(s, 1, 1)];
						}
					}
				];
				flags(sheen[0], sheen[1], sheen[2], num(obj(e, "KHR_materials_ior"), "ior", 1.5), num(sp, "specularFactor", 1), spc[0], spc[1], spc[2],
					obj(sp, "specularTexture") != null || obj(sp, "specularColorTexture") != null, num(obj(e, "KHR_materials_clearcoat"), "clearcoatFactor", 0),
					num(obj(e, "KHR_materials_transmission"), "transmissionFactor", 0), num(obj(e, "KHR_materials_iridescence"), "iridescenceFactor", 0),
					num(obj(e, "KHR_materials_anisotropy"), "anisotropyStrength", 0), uvSets(maps));
			}
		];
	}
	#end

	// whether a material's core maps need their own uvs (uvSets: one of
	// them on the second uvs, or with a transform not the first's): each
	// map present its texCoord, offset, rotation and scale
	public static function uvSets(maps:Array<Null<Array<Float>>>):Bool {
		var first:Null<Array<Float>> = null;
		for (m in maps) {
			if (m == null) continue;
			if (m[0] != 0) return true;
			if (first == null) first = m;
			else for (k in 1...6)
				if (m[k] != first[k]) return true;
		}
		return false;
	}

	// the flags of a material's extensions from its values (Material.extensions)
	public static function flags(sheenR:Float, sheenG:Float, sheenB:Float, ior:Float, specularFactor:Float, specularR:Float, specularG:Float,
			specularB:Float, specularMaps:Bool, clearcoat:Float, transmission:Float, iridescence:Float, anisotropy:Float, uvSets:Bool):Int {
		var e = 0;
		if (sheenR > 0 || sheenG > 0 || sheenB > 0) e |= 1;
		if (ior != 1.5 || specularFactor != 1 || specularR != 1 || specularG != 1 || specularB != 1 || specularMaps) e |= 2;
		if (clearcoat > 0) e |= 4;
		if (transmission > 0) e |= 8;
		if (iridescence > 0) e |= 16;
		if (anisotropy > 0) e |= 32;
		if (uvSets) e |= 64;
		return e;
	}
}
