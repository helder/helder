package helder.scene.render;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.Equirect;

// The environment's prefilter (Prefilter): a column of an octahedral atlas
// (RGBA16F) filled from a source, an equirectangular image (mip-mapped) or
// a cube (a reflection probe's capture, mip-mapped), each texel's
// direction its place in its cell (octDirection, its gutter folded back).
// The cells of rows 0 to levels - 1 hold the light along a reflection for
// a roughness of row / (levels - 1): the source convolved with GGX's lobe
// (the split sum's first half, N = V = R), by importance samples read at
// the mip level their share of the sphere covers (Karis' filtered
// importance sampling; the first row the source itself); the last row the
// irradiance over pi, from the spherical harmonics given (an Environment's:
// Sh.pack) or cosine-weighted samples. As a fragment pass into the column
// (the fallback: GL ES 3.0, WebGL2) or a compute dispatch writing it (a
// storage texture: Device.has(Compute)); the same function either way.
@:structInit @:publicFields class PrefilterParams {
	// x: the column's first texel, y: a cell's size in texels, z: the rows of
	// roughness (levels), w: importance samples a texel
	var cell:Vec4;
	// x: 1 a cube, 0 an equirectangular image; y: its mip levels below the
	// first; z: its first level's texels (a texel's share of the sphere:
	// 4 pi / z); w: the light's scale (its intensity)
	var source:Vec4;
	// x: 1 the irradiance row from sh, else sampled; y: 1 the source's
	// colours sRGB-encoded (an image's RGBA8: decoded, c^2.2); z and w (the
	// fragment pass's): the column's left edge and width in clip space
	var options:Vec4;
	// the irradiance's polynomial (Sh.pack)
	@:length(7) var sh:Array<Vec4>;
}

typedef PrefilterVertex = {pos:Vec2};
typedef PrefilterVaryings = {clip:Vec4};

// the source's light along a direction at a mip level
function sourceAt(p:PrefilterParams, equirectMap:Texture2D, cubeMap:TextureCube, d:Vec3, lod:Float):Vec3 {
	var c = vec3(0);
	if (p.source.x > 0.5) c = sampleLevel(cubeMap, d, lod).xyz;
	else c = sampleLevel(equirectMap, equirect(d), lod).xyz;
	if (p.options.y > 0.5) c = pow(c, vec3(2.2));
	return c * p.source.w;
}

// the irradiance's polynomial at a unit normal (Sh.pack's seven vectors), over pi
function shIrradiance(sh0:Vec4, sh1:Vec4, sh2:Vec4, sh3:Vec4, sh4:Vec4, sh5:Vec4, sh6:Vec4, n:Vec3):Vec3 {
	var n4 = vec4(n, 1);
	var b = vec4(n.x * n.y, n.y * n.z, n.z * n.z, n.z * n.x);
	var c = n.x * n.x - n.y * n.y;
	var e = vec3(dot(sh0, n4), dot(sh1, n4), dot(sh2, n4)) + vec3(dot(sh3, b), dot(sh4, b), dot(sh5, b)) + sh6.xyz * c;
	return max(e, vec3(0));
}

// the texel (x, y) of the column (x across a cell, y down the column): its
// cell's row, its direction, its light
function prefilterTexel(x:Float, y:Float, p:PrefilterParams, equirectMap:Texture2D, cubeMap:TextureCube):Vec4 {
	var size = p.cell.y;
	var levels = p.cell.z;
	var row = floor(y / size);
	var t = vec2(x, y - row * size);
	// (the cell's inner texels -1 to 1, its gutter past them)
	var uv = (t + 0.5 - 1) / (size - 2) * 2 - 1;
	var n = octDirection(uv);
	var up = abs(n.y) < 0.999 ? vec3(0, 1, 0) : vec3(1, 0, 0);
	var tx = normalize(cross(up, n));
	var ty = cross(n, tx);
	// (a sample's share of the sphere against a texel's: its mip level)
	var texel = 12.566371 / p.source.z;
	var samples = p.cell.w;
	var color = vec3(0);
	if (row >= levels) {
		// (the irradiance over pi: the harmonics', or cosine-weighted samples)
		if (p.options.x > 0.5) color = shIrradiance(p.sh[0], p.sh[1], p.sh[2], p.sh[3], p.sh[4], p.sh[5], p.sh[6], n);
		else {
			var sum = vec3(0);
			var k = 0.0;
			while (k < samples) {
				var u = (k + 0.5) / samples;
				var phi = 6.2831853 * fract(k * 0.618034);
				var r = sqrt(u);
				var l = tx * (r * cos(phi)) + ty * (r * sin(phi)) + n * sqrt(1 - u);
				var pdf = sqrt(1 - u) / 3.1415927;
				var lod = clamp(0.5 * log(1 / (samples * pdf * texel)) / 0.6931472 + 1, 0, p.source.y);
				sum += sourceAt(p, equirectMap, cubeMap, l, lod);
				k += 1;
			}
			color = sum / samples;
		}
	} else if (row < 0.5) color = sourceAt(p, equirectMap, cubeMap, n, 0);
	else {
		// (GGX's lobe about n, seen along n: each half vector's reflection,
		// weighted by n.l)
		var rough = row / max(levels - 1, 1);
		var a = rough * rough;
		var a2 = a * a;
		var sum = vec3(0);
		var weight = 0.0;
		var k = 0.0;
		while (k < samples) {
			var u = (k + 0.5) / samples;
			var phi = 6.2831853 * fract(k * 0.618034);
			var ch = sqrt((1 - u) / (1 + (a2 - 1) * u));
			var st = sqrt(1 - ch * ch);
			var h = tx * (st * cos(phi)) + ty * (st * sin(phi)) + n * ch;
			var l = h * (2 * ch) - n;
			var nl = dot(n, l);
			if (nl > 0) {
				var dd = ch * ch * (a2 - 1) + 1;
				var pdf = a2 / (3.1415927 * dd * dd) * 0.25;
				var lod = clamp(0.5 * log(1 / (samples * pdf * texel)) / 0.6931472 + 1, 0, p.source.y);
				sum += sourceAt(p, equirectMap, cubeMap, l, lod) * nl;
				weight += nl;
			}
			k += 1;
		}
		color = sum / max(weight, 0.0001);
	}
	return vec4(color, 1);
}

// (the fallback) a quad over the column, each fragment its texel
final PrefilterPass = shader({
	vertex: function(v:PrefilterVertex, p:{prefilter:PrefilterParams}):PrefilterVaryings
		return {clip: position(vec4(p.prefilter.options.z + (v.pos.x * 0.5 + 0.5) * p.prefilter.options.w, v.pos.y, 0, 1))},
	fragment: function(i:PrefilterVaryings, p:{prefilter:PrefilterParams, equirectMap:Texture2D, cubeMap:TextureCube}):Vec4
		return prefilterTexel(floor(i.clip.x) - p.prefilter.cell.x, floor(i.clip.y), p.prefilter, p.equirectMap, p.cubeMap)
});

// (the compute path) an invocation a texel of the column
final PrefilterDispatch = compute({
	size: [8, 8],
	main: function(id:ComputeInput, p:{var prefilter:PrefilterParams; var equirectMap:Texture2D; var cubeMap:TextureCube; @:format(RGBA16F) var atlas:StorageTexture;}) {
		var size = Std.int(p.prefilter.cell.y);
		if (id.x >= size || id.y >= size * (Std.int(p.prefilter.cell.z) + 1)) return;
		textureStore(p.atlas, Std.int(p.prefilter.cell.x) + id.x, id.y, prefilterTexel(id.x, id.y, p.prefilter, p.equirectMap, p.cubeMap));
	}
});
