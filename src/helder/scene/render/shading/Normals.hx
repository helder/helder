package helder.scene.render.shading;

import helder.math.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.MaterialShader;
import helder.scene.render.PbrShader;
import helder.scene.render.shading.Unlit;

// The normal as a colour (three's MeshNormalMaterial): the surface's unit
// normal in view space, from -1..1 to 0..1 (right red, up green, towards
// the eye blue). A debug view: Material.normals is not tone mapped.

function normalsColor(s:PbrSurface, p:{frame:PbrFrame}):Vec3
	return normalize(toView(p.frame, s.normal)) * 0.5 + 0.5;

final normals = unlit.with({color: normalsColor});

final NormalsShader = MaterialShader.material(normals);
