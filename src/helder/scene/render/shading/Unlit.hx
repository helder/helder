package helder.scene.render.shading;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.MaterialShader;
import helder.scene.render.PbrShader;

// The shader of the materials no light reaches (three's MeshBasicMaterial,
// and below it MeshMatcapMaterial, MeshNormalMaterial, MeshDepthMaterial):
// a slot object of its own, unlit, not pbr with its light taken away. Its
// slots are pbr's color, alpha and position (a PbrSurface, a PbrPoint);
// nothing is summed per light, no shadow map, environment or light of the
// frame's block is read (pbr's blocks and textures are its parameters, so
// the renderer draws it as any material's own shader). Its colour is the
// color slot's, tinted, fogged (Material.fog), then tone mapped as the
// target takes it (Material.toneMapped false: only encoded, a debug
// view's colours as they are); a cutout (alphaCutoff) and the blend modes
// as pbr's. Its variants are the renderer's but the normal-mapped ones
// (it has no normalMap option: a normal map is not drawn): plain, skinned,
// instanced (InstancedMesh, Sprites).
//
//   unlit                    Material.unlit: the base colour times its texture
//   matcap (Matcap.hx)       Material.matcap: a sphere's picture by the normal in view space
//   normals (Normals.hx)     Material.normals: the normal in view space as a colour
//   depth (Depth.hx)         Material.depth: the view's depth, white near, black far

typedef UnlitOptions = {skinned:Bool, instanced:Bool};

// the slot object (the stages' third parameter): its options, its slots
typedef Unlit = {
	options:UnlitOptions,
	color:(PbrSurface, PbrFragmentParams) -> Vec3,
	alpha:(PbrSurface, PbrFragmentParams) -> Float,
	position:(PbrPoint, PbrVertexParams) -> Vec3
}

// the camera's axes in the world (its view-projection's first three rows:
// a symmetric projection's right and up scaled, the third its back, -z,
// scaled by a negative factor) and a direction d in them: d in view space
function toView(frame:PbrFrame, d:Vec3):Vec3 {
	var vp = frame.viewProj;
	var right = normalize(vec3(vp.c0.x, vp.c1.x, vp.c2.x));
	var up = normalize(vec3(vp.c0.y, vp.c1.y, vp.c2.y));
	var back = -normalize(vec3(vp.c0.z, vp.c1.z, vp.c2.z));
	return vec3(dot(d, right), dot(d, up), dot(d, back));
}

// an unlit colour (linear) and alpha as the fragment's: fogged, shown as
// the target takes it (display), the cutout and the additive blend's fade
function unlitShade(color:Vec3, baseAlpha:Float, world:Vec3, frame:PbrFrame, material:PbrMaterial):Vec4 {
	var c = color * frame.exposure.x;
	var mist = fogAmount(frame.fog, frame.fogShape, frame.eye.xyz, world) * material.ground.w;
	c = mix(c, material.uvV.w > 0 ? vec3(0) : frame.fog.xyz * frame.exposure.x, mist);
	var shown = display(c, frame, material);
	var alpha = baseAlpha;
	if (material.layers.w > 0) {
		if (alpha < material.layers.w) discard();
		alpha = 1;
	}
	if (material.uvV.w > 0) shown = shown * alpha;
	return vec4(shown, alpha);
}

final unlit = slots({
	options: {skinned: false, instanced: false},
	vertex: function(v:PbrVertex, p:PbrVertexParams, m:Unlit):PbrVaryings {
		var pos = m.position({pos: v.pos, normal: v.normal, uv: v.uv}, p);
		var nr = v.normal;
		if (m.options.skinned) {
			// (moved by its four joints' matrices, weighted)
			var j0 = joint(p.jointMatrices, v.joints.x, p.skin.rows.x), j1 = joint(p.jointMatrices, v.joints.y, p.skin.rows.x);
			var j2 = joint(p.jointMatrices, v.joints.z, p.skin.rows.x), j3 = joint(p.jointMatrices, v.joints.w, p.skin.rows.x);
			var q = vec4(pos, 1), n4 = vec4(v.normal, 0);
			pos = ((j0 * q) * v.weights.x + (j1 * q) * v.weights.y + (j2 * q) * v.weights.z + (j3 * q) * v.weights.w).xyz;
			nr = ((j0 * n4) * v.weights.x + (j1 * n4) * v.weights.y + (j2 * n4) * v.weights.z + (j3 * n4) * v.weights.w).xyz;
		}
		var model = m.options.instanced ? mat4(vec4(v.m0.xyz, 0), vec4(v.m1.xyz, 0), vec4(v.m2.xyz, 0), vec4(v.m3.xyz, 1)) : p.object.model;
		var world = model * vec4(pos, 1);
		return {
			clip: position(p.frame.viewProj * world),
			world: world.xyz,
			normal: m.options.instanced ? instanceNormal(v.m0.xyz, v.m1.xyz, v.m2.xyz, nr) : (p.object.normalMatrix * vec4(nr, 0)).xyz,
			uv: m.options.instanced ? instanceUv(v.uv, v.m3.w) : v.uv,
			up: m.options.instanced ? v.m1.xyz : (model * vec4(0, 1, 0, 0)).xyz,
			tint: m.options.instanced ? vec3(1 + v.m0.w, 1 + v.m1.w, 1 + v.m2.w) : p.object.tint.xyz
		};
	},
	fragment: function(i:PbrVaryings, p:PbrFragmentParams, m:Unlit):Vec4 {
		var uv = uvOf(p.material, i.uv);
		var texel = sample(p.baseColorTexture, uv);
		var s:PbrSurface = {
			world: i.world,
			normal: normalize(i.normal),
			uv: uv,
			up: normalize(i.up),
			baseColor: vec4(p.material.baseColor.xyz * pow(texel.xyz, vec3(2.2)), p.material.baseColor.w * texel.w)
		};
		return unlitShade(m.color(s, p) * i.tint, m.alpha(s, p), i.world, p.frame, p.material);
	},
	color: pbrColor,
	alpha: pbrAlpha,
	position: pbrPosition
});

final UnlitShader = MaterialShader.material(unlit);
