package helder.scene.render;

import helder.math.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.PbrShader;

// The shadow atlas' pass (Shadows): each caster seen from a light into its
// tile, its depth (0 near the light, 1 far: the clip space's z over w at
// the fragment, exact for a perspective tile too) written to the R32F
// atlas; what falls outside the tile's rectangle (the caster's rect, in
// the atlas' clip space: its view-projection maps the light's view into
// it) dropped. A slot object of options only, shadowCaster, whose variants
// are the plain caster's (ShadowShader), a skinned one's
// (ShadowSkinnedShader: the vertex moved by its joints as pbr's skinned
// variant moves it) and an instanced set's (ShadowInstancedShader: each
// instance's world matrix from the instance buffer, pbr's instanced
// layout; the caster's block the light's view-projection alone). The
// vertex is pbr's, laid out as each reads it.
typedef ShadowVaryings = {
	var clip:Vec4;
	var at:Vec4;
}

typedef ShadowCaster = {
	var mvp:Mat4; // the tile's view-projection (into the atlas' clip space) times the node's world matrix
	var rect:Vec4; // the tile in the atlas' clip space: x, y its least corner, z, w its greatest
}

typedef ShadowParams = {
	var caster:ShadowCaster;
	@:optional var skin:PbrSkinInfo;
	@:optional var jointMatrices:Texture2D;
}

typedef ShadowOptions = {skinned:Bool, instanced:Bool};
typedef Shadow = {options:ShadowOptions};

final shadowCaster = slots({
	options: {skinned: false, instanced: false},
	vertex: function(v:PbrVertex, p:ShadowParams, m:Shadow):ShadowVaryings {
		var pos = v.pos;
		if (m.options.skinned) {
			var j0 = joint(p.jointMatrices, v.joints.x, p.skin.rows.x), j1 = joint(p.jointMatrices, v.joints.y, p.skin.rows.x);
			var j2 = joint(p.jointMatrices, v.joints.z, p.skin.rows.x), j3 = joint(p.jointMatrices, v.joints.w, p.skin.rows.x);
			var q = vec4(v.pos, 1);
			pos = ((j0 * q) * v.weights.x + (j1 * q) * v.weights.y + (j2 * q) * v.weights.z + (j3 * q) * v.weights.w).xyz;
		}
		var clip = m.options.instanced ? p.caster.mvp * (mat4(vec4(v.m0.xyz, 0), vec4(v.m1.xyz, 0), vec4(v.m2.xyz, 0), vec4(v.m3.xyz, 1)) * vec4(pos, 1)) : p.caster.mvp * vec4(pos, 1);
		return {clip: position(clip), at: clip};
	},
	fragment: function(i:ShadowVaryings, p:ShadowParams, m:Shadow):Vec4 {
		var xy = i.at.xy / i.at.w;
		if (xy.x < p.caster.rect.x || xy.y < p.caster.rect.y || xy.x > p.caster.rect.z || xy.y > p.caster.rect.w) discard();
		return vec4(i.at.z / i.at.w, 0, 0, 1);
	}
});

final ShadowShader = shadowCaster.gpuVariant();

typedef ShadowClearVertex = {
	var corner:Vec2;
}

typedef ShadowClearVaryings = {
	var clip:Vec4;
}

// a tile of the atlas cleared (Shadows, when other tiles are kept): its
// rectangle (rect, as the casters') drawn at the far depth, 1
final ShadowClearShader = shader({
	vertex: function(v:ShadowClearVertex, p:{caster:ShadowCaster}):ShadowClearVaryings
		return {clip: position(vec4(mix(p.caster.rect.x, p.caster.rect.z, v.corner.x), mix(p.caster.rect.y, p.caster.rect.w, v.corner.y), 1, 1))},
	fragment: function(i:ShadowClearVaryings):Vec4
		return vec4(1, 0, 0, 1)
});
