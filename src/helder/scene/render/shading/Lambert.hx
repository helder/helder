package helder.scene.render.shading;

import helder.math.*;
import helder.gfx.shader.*;
import helder.scene.render.MaterialShader;
import helder.scene.render.PbrShader;

// Lambert's shading (three's MeshLambertMaterial): each light's diffuse
// alone, n.l, no specular lobe; the ambient's diffuse share alone, no
// reflections. The cheap lit model for phones: a dot a light against GGX,
// Smith and Schlick, its shadows, lights, fog and normal maps pbr's.
// Material.lambert's shader (LambertShader); lambert.with({...}) a
// material of one's own on it.

// a light's diffuse (its colour times n.l, over pi: the standard
// material's diffuse, without its Fresnel)
function lambertDirect(s:LitSurface, l:LightSample, p:{}):Vec3
	return s.albedo * l.radiance * (l.ndotl / 3.14159265);

// the ambient's diffuse share, occluded
function lambertIndirect(s:LitSurface, env:IndirectLight, p:{}):Vec3
	return env.irradiance * s.albedo * env.occlusion;

final lambert = pbr.with({direct: lambertDirect, indirect: lambertIndirect});

final LambertShader = MaterialShader.material(lambert);
