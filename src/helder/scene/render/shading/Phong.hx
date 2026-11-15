package helder.scene.render.shading;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.MaterialShader;
import helder.scene.render.PbrShader;

// Blinn-Phong shading (three's MeshPhongMaterial, for ports): each light's
// Lambert diffuse and a Blinn-Phong highlight (three's normalised lobe,
// Schlick's Fresnel of the surface's reflectance), its shininess from the
// material's roughness (Material.phong sets the roughness from three's
// shininess); the ambient and reflections pbr's. A pow a light, no GGX or
// Smith. Material.phong's shader (PhongShader).

// a light's diffuse and highlight, times n.l
function phongDirect(s:LitSurface, l:LightSample, p:{material:PbrMaterial}):Vec3 {
	var h = normalize(l.direction + s.view);
	var nh = max(dot(s.normal, h), 0);
	var vh = max(dot(s.view, h), 0);
	var shininess = phongShininess(s.roughness);
	var f0 = reflectance(s, p.material);
	var fresnel = f0 + (1 - f0) * pow(1 - vh, 5);
	var highlight = fresnel * (0.25 * (shininess * 0.5 + 1) / 3.14159265 * pow(nh, shininess));
	return (s.albedo * (1 - s.metalness) / 3.14159265 + highlight) * l.radiance * l.ndotl;
}

// the Blinn-Phong exponent of a roughness (r^4 as GGX's a^2: 2 / a^2 - 2,
// Walter's match of the two lobes), 1 to 4096
function phongShininess(roughness:Float):Float {
	var a = roughness * roughness;
	return clamp(2 / max(a * a, 0.0001) - 2, 1, 4096);
}

final phong = pbr.with({direct: phongDirect});

final PhongShader = MaterialShader.material(phong);
