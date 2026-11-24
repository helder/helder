#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
#end

// (SoftShaderTest's) every shader src/helder defines: its modules' statics
// (module-level finals) of a Shader, and a MaterialShader's variants
class SoftShaders {
	public static macro function all():Expr {
		var out:Array<Expr> = [], pos = Context.currentPos();
		function walk(dir:String) {
			for (f in sys.FileSystem.readDirectory(dir)) {
				var p = '$dir/$f';
				if (sys.FileSystem.isDirectory(p)) {
					if (f != "typescript" && p != "src/helder/gfx/shader") walk(p);
					continue;
				}
				if (!StringTools.endsWith(f, ".hx") || StringTools.endsWith(f, ".test.hx")) continue;
				if (!~/= (shader|slots)\(|\.(gpuVariant|variant)\(|MaterialShader\.material\(|pbr\.with\(/.match(sys.io.File.getContent(p))) continue;
				var module = p.substr(4, p.length - 7).split("/").join(".");
				var types = try Context.getModule(module) catch (_:Dynamic) [];
				for (t in types)
					switch t {
						case TInst(c, _):
							var cl = c.get();
							for (field in cl.statics.get()) {
								// (a module-level final: by its module's path)
								var path = StringTools.endsWith(cl.name, "_Fields_") ? module.split(".").concat([field.name]) : cl.pack.concat([cl.name, field.name]);
								var e = macro $p{path};
								var name = module + "." + field.name;
								if (Context.unify(field.type, Context.getType("helder.gfx.shader.Shader")))
									out.push(macro {name: $v{name}, shader: (cast $e : helder.gfx.shader.Shader<Dynamic, Dynamic>)});
								else if (Context.unify(field.type, Context.getType("helder.scene.render.MaterialShader")))
									for (v in ["plain", "normalMapped", "skinned", "instanced", "instancedNormalMapped", "prepass", "prepassInstanced"])
										out.push(macro {name: $v{name + "." + v}, shader: (cast $e.$v : helder.gfx.shader.Shader<Dynamic, Dynamic>)});
							}
						case _:
					}
			}
		}
		walk("src/helder");
		return macro [$a{out}];
	}
}
