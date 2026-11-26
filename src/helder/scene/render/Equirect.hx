package helder.scene.render;

import helder.math.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// Equirectangular environment maps in shader code: the environment's
// background (EnvironmentShader) and the standard material's lookups
// (PbrShader). (A module of functions only, with no static values, so that
// the shaders' modules that call it start in no particular order.)

// a unit direction's place in an equirectangular map (-z at its centre,
// up at its top)
function equirect(d:Vec3):Vec2
	return vec2(arcTan2(d.x, -d.z) * 0.15915494 + 0.5, arcCos(clamp(d.y, -1, 1)) * 0.31830989);

// a prefiltered atlas's colour (Environment.prefiltered: levels rows of
// the sphere by roughness and the irradiance's below them, all of a
// size) at a direction's place uv in its row (edge: half a texel of a
// row, kept from the next one's)
function atlas(t:Texture2D, uv:Vec2, row:Float, levels:Float, edge:Float):Vec3
	return sampleLevel(t, vec2(uv.x, (row + clamp(uv.y, edge, 1 - edge)) / (levels + 1)), 0).xyz;

// the unit direction at a place of an octahedral map (-1 to 1 each way;
// past an edge, folded back: area lights' packed normals, FrameLights')
function octDirection(p:Vec2):Vec3 {
	var uv = p;
	// (past an edge the octahedron's map mirrors: across x, y flips; across y, x)
	if (abs(uv.x) > 1) uv = vec2((uv.x > 0 ? 2.0 : -2.0) - uv.x, -uv.y);
	if (abs(uv.y) > 1) uv = vec2(-uv.x, (uv.y > 0 ? 2.0 : -2.0) - uv.y);
	var n = vec3(uv.x, 1 - abs(uv.x) - abs(uv.y), uv.y);
	if (n.y < 0) {
		var f = (1 - abs(vec2(n.z, n.x))) * vec2(n.x >= 0 ? 1.0 : -1.0, n.z >= 0 ? 1.0 : -1.0);
		n = vec3(f.x, n.y, f.y);
	}
	return normalize(n);
}

// spherical harmonics' irradiance over pi at a unit normal (Sh.pack's
// seven vectors: each channel's bands 0 and 1, their band 2, its x^2 - y^2)
function shIrradiance(sh0:Vec4, sh1:Vec4, sh2:Vec4, sh3:Vec4, sh4:Vec4, sh5:Vec4, sh6:Vec4, n:Vec3):Vec3 {
	var n4 = vec4(n, 1);
	var b = vec4(n.x * n.y, n.y * n.z, n.z * n.z, n.z * n.x);
	var c = n.x * n.x - n.y * n.y;
	var e = vec3(dot(sh0, n4), dot(sh1, n4), dot(sh2, n4)) + vec3(dot(sh3, b), dot(sh4, b), dot(sh5, b)) + sh6.xyz * c;
	return max(e, vec3(0));
}

// (the shaders have no inverse trigonometry: polynomial fits, within
// 2e-5 radians of atan2 and 7e-5 of acos)
function arcTan2(y:Float, x:Float):Float {
	var ax = abs(x), ay = abs(y);
	var a = min(ax, ay) / max(max(ax, ay), 0.000001);
	var s = a * a;
	var r = a * (0.999866 + s * (-0.3302995 + s * (0.180141 + s * (-0.085133 + s * 0.0208351))));
	if (ay > ax) r = 1.5707964 - r;
	if (x < 0) r = 3.1415927 - r;
	if (y < 0) r = -r;
	return r;
}

function arcCos(x:Float):Float {
	var ax = abs(x);
	var r = sqrt(1 - ax) * (1.5707288 + ax * (-0.2121144 + ax * (0.074261 - 0.0187293 * ax)));
	if (x < 0) r = 3.1415927 - r;
	return r;
}
