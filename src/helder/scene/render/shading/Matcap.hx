package helder.scene.render.shading;

import helder.math.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.MaterialShader;
import helder.scene.render.PbrShader;
import helder.scene.render.shading.Unlit;

// A matcap (three's MeshMatcapMaterial): the colour of a lit sphere's
// picture (its image, sRGB) where the normal points, seen from the eye: the
// surface's normal in view space, turned about the direction to the eye
// (three's lookup), times the base colour and its texture. No light of the
// scene's: the light is the picture's. One texture read a pixel. The image
// is the material's emissiveTexture (an unlit material emits nothing
// else): Material.matcap's matcap.

// the picture's colour at the normal (its uvs: right and up in it, v down the image)
function matcapColor(s:PbrSurface, p:{frame:PbrFrame, emissiveTexture:Texture2D}):Vec3 {
	var n = normalize(toView(p.frame, s.normal));
	var e = normalize(toView(p.frame, p.frame.eye.xyz - s.world));
	var x = normalize(vec3(e.z, 0, -e.x));
	var y = cross(e, x);
	var at = vec2(dot(x, n), dot(y, n)) * 0.495 + 0.5;
	return s.baseColor.xyz * pow(sample(p.emissiveTexture, vec2(at.x, 1 - at.y)).xyz, vec3(2.2));
}

final matcap = unlit.with({color: matcapColor});

final MatcapShader = MaterialShader.material(matcap);
