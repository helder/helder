// helder.scene's standard material's variants (PbrShader.hx: the
// renderer's five, the view buffers' prepass three), then the physical
// material's (PhysicalShader: every glTF extension, normal mapped;
// sheen alone), as pbr.ts prints TypeScript's (src/helder/scene/pbr.ts).
// (A literal below 1e-4 is printed by each runtime's Std.string: Haxe's
// macros write 1e-06 where helder's compiler writes 0.000001; written here
// as pbr.ts's)
class Pbr {
	static function main() {
		var all = helder.scene.render.PhysicalShader.of({
			sheen: true,
			specular: true,
			clearcoat: true,
			transmission: true,
			iridescence: true,
			anisotropy: true,
			uvSets: true
		});
		var sheen = helder.scene.render.PhysicalShader.of({sheen: true});
		var vs:Array<helder.gfx.shader.Shader<Dynamic, Dynamic>> = [
			cast helder.scene.render.PbrShader.PbrShader,
			cast helder.scene.render.PbrNormalShader.PbrNormalShader,
			cast helder.scene.render.PbrSkinnedShader.PbrSkinnedShader,
			cast helder.scene.render.PbrInstancedShader.PbrInstancedShader,
			cast helder.scene.render.PbrInstancedNormalShader.PbrInstancedNormalShader,
			cast helder.scene.render.PbrPrepassShader.PbrPrepassShader,
			cast helder.scene.render.PbrPrepassInstancedShader.PbrPrepassInstancedShader,
			cast helder.scene.render.PbrPrepassSkinnedShader.PbrPrepassSkinnedShader,
			cast helder.scene.render.PbrProbesShader.PbrProbesShader,
			cast helder.scene.render.PbrProbesShader.PbrInstancedProbesShader,
			cast helder.scene.render.PbrAreaShader.PbrAreaShader,
			cast helder.scene.render.PbrAreaShader.PbrInstancedAreaProbesShader,
			all.normalMapped,
			sheen.plain
		];
		for (v in vs)
			Print.shader(new helder.gfx.shader.Shader<Dynamic, Dynamic>(code(v.vertexCode), code(v.fragmentCode), v.layout, v.uniforms, v.textures, null, null));
	}

	static function code(c:helder.gfx.ShaderCode):helder.gfx.ShaderCode {
		function fix(s:Null<String>):Null<String>
			return s == null ? null : StringTools.replace(s, "1e-06", "0.000001");
		return {
			glsl: fix(c.glsl),
			wgsl: fix(c.wgsl),
			msl: fix(c.msl),
			hlsl: fix(c.hlsl),
			bindings: c.bindings
		};
	}
}
