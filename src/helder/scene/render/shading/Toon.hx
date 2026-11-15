package helder.scene.render.shading;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.MaterialShader;
import helder.scene.render.PbrShader;

// Toon shading (three's MeshToonMaterial): each light's diffuse banded into
// Material.steps bands of n.l, its shadow banded with it (a shadow is a
// band, not a gradient over the bands), the side away from every light the
// albedo times Material.shade. Unlike three's, which bands the summed
// diffuse through a ramp texture, the bands are per light: the sun's
// shadow, point and spot lights, fog and normal maps are pbr's.
// Material.toon's shader (ToonShader); toon.with({...}) a material of
// one's own on it (its own colour or emissive slot).

// a light's diffuse, n.l times its shadow banded
function toonDirect(s:LitSurface, l:LightSample, p:{material:PbrMaterial}):Vec3
	return s.albedo * l.color * (ramp(l.ndotl * l.shadow, p.material.model.x) / 3.14159265);

// the shaded side's colour: the albedo times the material's shade, occluded
function toonIndirect(s:LitSurface, env:IndirectLight, p:{material:PbrMaterial}):Vec3
	return s.albedo * p.material.shadeColor.xyz * env.occlusion;

// x (0 to 1) in steps bands: 0 below the first, 1 in the last, each band's
// edge softened over a sixteenth of it (no aliased stair at a terminator)
function ramp(x:Float, steps:Float):Float {
	var n = max(steps, 1);
	var t = clamp(x, 0, 1) * n;
	var band = floor(t);
	return min((band + smoothstep(0, 0.0625, t - band)) / n, 1);
}

final toon = pbr.with({direct: toonDirect, indirect: toonIndirect});

final ToonShader = MaterialShader.material(toon);
