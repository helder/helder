import helder.scene.render.shading.Lambert;
import helder.scene.render.shading.Toon;
import helder.scene.render.shading.Phong;
import helder.scene.render.shading.Unlit;
import helder.scene.render.shading.Matcap;
import helder.scene.render.shading.Normals;
import helder.scene.render.shading.Depth;

// helder.scene's shading models (helder.scene.render.shading), their
// variants as shading.ts prints TypeScript's (src/helder/scene/shading.ts);
// each a module-level final made by pbr.with or unlit.with (SlotsMacro's
// resolve: its initializer typed in its module).
class Shading {
	static function main() {
		var vs:Array<helder.gfx.shader.Shader<Dynamic, Dynamic>> = [
			cast lambert.variant(), cast toon.variant(), cast toon.variant({instanced: true}), cast phong.variant(), cast unlit.variant(),
			cast unlit.variant({instanced: true}), cast unlit.variant({skinned: true}), cast matcap.variant(), cast normals.variant(), cast depth.variant()
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
