package helder.scene.render;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.PbrShader.aces;
import helder.scene.render.PbrShader.encode;

// The post-process chain's shaders (PostProcess): each a triangle over the
// whole target, reading the pass before.
//
//   BloomDownShader   a level of the bloom's chain from the one above:
//                     Jimenez's 13 taps (Call of Duty: Advanced Warfare,
//                     "Next generation post processing", 2014), the
//                     first level's in Karis' average (each group of four
//                     weighted by 1 / (1 + its luma): no fireflies)
//   BloomUpShader     the level below's tent filter (3x3) added to a level
//                     (additive blending), up the chain
//   composite         the frame (a slot object: CompositeShader, with FXAA,
//                     with the effects: PostEffects): the scene and its bloom mixed (energy
//                     kept: the scene less what bloom spreads), exposed,
//                     tone mapped (AgX, or ACES as the 8-bit path's), graded (saturation,
//                     contrast, lift and gain), vignetted, grain added
//                     (and dithered), encoded for an 8-bit target
@:structInit @:publicFields class PostVertex {
	var pos:Vec2; // clip space
}

@:structInit @:publicFields class PostVaryings {
	var clip:Vec4;
	var uv:Vec2;
}

// a bloom pass: x, y a texel of the source, z the up filter's radius (in
// its texels), w 1 for the first level down (Karis' average)
@:structInit @:publicFields class BloomParams {
	var texel:Vec4;
}

@:structInit @:publicFields class CompositeParams {
	var exposure:Vec4; // x: exposure, y: bloom's share, z: the tone curve (0 AgX, 1 ACES, 2 none), w: time (the grain's)
	var grade:Vec4; // x: saturation, y: contrast, z: vignette, w: grain
	var lift:Vec4; // rgb: added to the shadows (graded, display values); w: 1 / the bloom's levels
	var gain:Vec4; // rgb: times the colour
	var size:Vec4; // xy: the target's size in pixels, z: its aspect, w: the scene's alpha kept (1) or opaque (0)
}

// (a target's uv at a corner of the triangle over it: its top left 0, 0)
function fullscreen(v:PostVertex):PostVaryings
	return {clip: position(vec4(v.pos, 0, 1)), uv: vec2(v.pos.x * 0.5 + 0.5, 0.5 - v.pos.y * 0.5)};

// (a texel's colour, past a ceiling no bright speck reaches: half floats'
// infinities and NaNs kept out)
function tap(t:Texture2D, uv:Vec2):Vec3
	return clamp(sampleLevel(t, uv, 0).xyz, 0, 256);

function luma(c:Vec3):Float
	return dot(c, vec3(0.2126, 0.7152, 0.0722));

final BloomDownShader = shader({
	vertex: function(v:PostVertex):PostVaryings
		return fullscreen(v),
	fragment: function(i:PostVaryings, params:{p:BloomParams, source:Texture2D}):Vec4 {
		var t = params.p.texel.xy;
		var uv = i.uv;
		var a = tap(params.source, uv + t * vec2(-2, -2));
		var b = tap(params.source, uv + t * vec2(0, -2));
		var c = tap(params.source, uv + t * vec2(2, -2));
		var d = tap(params.source, uv + t * vec2(-2, 0));
		var e = tap(params.source, uv);
		var f = tap(params.source, uv + t * vec2(2, 0));
		var g = tap(params.source, uv + t * vec2(-2, 2));
		var h = tap(params.source, uv + t * vec2(0, 2));
		var k = tap(params.source, uv + t * vec2(2, 2));
		var j = tap(params.source, uv + t * vec2(-1, -1));
		var l = tap(params.source, uv + t * vec2(1, -1));
		var m = tap(params.source, uv + t * vec2(-1, 1));
		var n = tap(params.source, uv + t * vec2(1, 1));
		// (the five groups of four: the centre's 0.5, the corners' 0.125 each)
		var g0 = (j + l + m + n) * 0.25;
		var g1 = (a + b + d + e) * 0.25;
		var g2 = (b + c + e + f) * 0.25;
		var g3 = (d + e + g + h) * 0.25;
		var g4 = (e + f + h + k) * 0.25;
		var w0 = 0.5;
		var w1 = 0.125;
		var w2 = 0.125;
		var w3 = 0.125;
		var w4 = 0.125;
		if (params.p.texel.w > 0.5) {
			w0 = 0.5 / (1 + luma(g0));
			w1 = 0.125 / (1 + luma(g1));
			w2 = 0.125 / (1 + luma(g2));
			w3 = 0.125 / (1 + luma(g3));
			w4 = 0.125 / (1 + luma(g4));
		}
		var sum = g0 * w0 + g1 * w1 + g2 * w2 + g3 * w3 + g4 * w4;
		return vec4(sum / (w0 + w1 + w2 + w3 + w4), 1);
	}
});

final BloomUpShader = shader({
	vertex: function(v:PostVertex):PostVaryings
		return fullscreen(v),
	fragment: function(i:PostVaryings, params:{p:BloomParams, source:Texture2D}):Vec4 {
		var t = params.p.texel.xy * params.p.texel.z;
		var uv = i.uv;
		var sum = sampleLevel(params.source, uv, 0).xyz * 4
			+ (sampleLevel(params.source, uv + t * vec2(0, -1), 0).xyz + sampleLevel(params.source, uv + t * vec2(-1, 0), 0).xyz
				+ sampleLevel(params.source, uv + t * vec2(1, 0), 0).xyz + sampleLevel(params.source, uv + t * vec2(0, 1), 0).xyz) * 2
			+ sampleLevel(params.source, uv + t * vec2(-1, -1), 0).xyz + sampleLevel(params.source, uv + t * vec2(1, -1), 0).xyz
			+ sampleLevel(params.source, uv + t * vec2(-1, 1), 0).xyz + sampleLevel(params.source, uv + t * vec2(1, 1), 0).xyz;
		return vec4(sum / 16, 1);
	}
});

// (a pixel's random value in 0..1)
function hash(p:Vec2):Float {
	var q = fract(p * vec2(0.1031, 0.1030));
	var d = dot(q, vec2(q.y + 33.33, q.x + 33.33));
	q = q + vec2(d, d);
	return fract((q.x + q.y) * q.x);
}

// AgX (Sobotka's; Wrensch's fit of its sigmoid): the colour into AgX's
// inset primaries, its log2 between -12.47 and 4.03 stops, the curve,
// back out: highlights desaturate towards white as film does, hues
// stay; display values (sRGB's encoding), 0..1
function agx(c:Vec3):Vec3 {
	var v = vec3(dot(c, vec3(0.842479062253094, 0.0784335999999992, 0.0792237451477643)),
		dot(c, vec3(0.0423282422610123, 0.878468636469772, 0.0791661274605434)),
		dot(c, vec3(0.0423756549057051, 0.0784336, 0.879142973793104)));
	var lo = -12.47393;
	var hi = 4.026069;
	v = clamp(log(max(v, vec3(0.0000001))) * 1.4426950, lo, hi);
	v = (v - lo) / (hi - lo);
	var v2 = v * v;
	var v4 = v2 * v2;
	v = 15.5 * v4 * v2 - 40.14 * v4 * v + 31.96 * v4 - 6.868 * v2 * v + 0.4298 * v2 + 0.1191 * v - 0.00232;
	// (the inset's inverse)
	var o = vec3(dot(v, vec3(1.19687900512017, -0.0980208811401368, -0.0990297440797205)),
		dot(v, vec3(-0.0528968517574562, 1.15190312990417, -0.0989611768448433)),
		dot(v, vec3(-0.0529716355144438, -0.0980434501171241, 1.15107367264116)));
	return clamp(o, 0, 1);
}


// the composite's inputs: its block, the scene's light, the bloom; with
// the effects (option effects: PostEffects) their block, the view buffers'
// depth and normals (their w the selection group), depth of field's blur,
// the LUT's strip and the outline groups' colours and widths
typedef CompositeInputs = {
	var p:CompositeParams;
	var scene:Texture2D;
	var bloom:Texture2D;
	@:optional var fx:CompositeFx;
	@:optional var viewDepth:Texture2D;
	@:optional var viewNormals:Texture2D;
	@:optional var blur:Texture2D;
	@:optional var lut:Texture2D;
	@:optional var groups:Texture2D;
	@:optional var rays:Texture2D;
	@:optional var weights:Texture2D;
}

// the effects folded into the composite (PostEffects: those set on the
// PostProcess, each off while its x is 0)
@:structInit @:publicFields class CompositeFx {
	var dof:Vec4; // x: 0 off, 1 focus, 2 tilt-shift; y, z, w: cocOf's (the distance or the band, the aperture or the falloff, the most blur: a share of the height)
	var dofFocus:Vec4; // x: tilt-shift's focus (metres; 0: the depth at the band's centre, y its uv's v), z: the blur's texels in the target's (2: half size), w unused
	var outline:Vec4; // x: 1 on, y: the widest group's width (pixels), zw: a pixel of the target (uv)
	var lut:Vec4; // x: its size (16, 32; 0 off), y: its strength (0..1)
	var rays:Vec4; // x: 1 god rays on, y: their intensity
	var smaa:Vec4; // xy: a pixel of the target (uv), the weights' (smaa's variant)
	var inverseProjection:Mat4; // the view buffers' (a texel's depth to view space)
}

// (smaa: SMAA's blending, with the effects: SmaaPass's weights)
typedef CompositeOptions = {fxaa:Bool, effects:Bool, smaa:Bool};
typedef Composite = {options:CompositeOptions};

// a point's distance in front of the camera (metres) from the view
// buffers' depth d at uv (inverse: their inverse projection)
function viewDepthAt(inverse:Mat4, uv:Vec2, d:Float):Float {
	var p = inverse * vec4(uv.x * 2 - 1, 1 - uv.y * 2, d, 1);
	return -p.z / p.w;
}

// depth of field's circle of confusion at a view depth z (metres), as a
// share of the frame's height: focus (dof.x 1), by a thin lens (the
// aperture's blur at infinity, none at the distance, at most the most);
// tilt-shift (2), by z's distance from the focus relative to it (sharp
// within the band, the most blur past the falloff)
function cocOf(dof:Vec4, focus:Float, z:Float):Float {
	var c = 0.0;
	if (dof.x > 1.5) c = dof.w * smoothstep(dof.y, dof.y + dof.z, abs(z - focus) / max(focus, 0.0001));
	else if (dof.x > 0.5) c = min(dof.z * abs(z - dof.y) / max(z, 0.0001), dof.w);
	return c;
}

// the depth in focus: tilt-shift's, the depth under the band's centre
// unless given; focus', its distance
function focusOf(fx:CompositeFx, depth:Texture2D):Float {
	var f = fx.dof.y;
	if (fx.dof.x > 1.5) {
		f = fx.dofFocus.x;
		if (f <= 0) f = min(viewDepthAt(fx.inverseProjection, vec2(0.5, fx.dofFocus.y), sampleLevel(depth, vec2(0.5, fx.dofFocus.y), 0).x), 1000);
	}
	return f;
}

// (FXAA's luma of light: roughly the tone mapped one's)
function fxaaLuma(c:Vec4):Float {
	var y = luma(clamp(c.xyz, 0, 256));
	return y / (1 + y);
}

// FXAA (Lottes' FXAA 3, its console pass): the scene's light read along
// the edge through the pixel, found from its four diagonal neighbours'
// lumas, blended in linear light before the curve; t a texel of the scene
function fxaa(scene:Texture2D, uv:Vec2, t:Vec2):Vec4 {
	var c = sampleLevel(scene, uv, 0);
	var nw = fxaaLuma(sampleLevel(scene, uv + t * vec2(-1, -1), 0));
	var ne = fxaaLuma(sampleLevel(scene, uv + t * vec2(1, -1), 0));
	var sw = fxaaLuma(sampleLevel(scene, uv + t * vec2(-1, 1), 0));
	var se = fxaaLuma(sampleLevel(scene, uv + t * vec2(1, 1), 0));
	var m = fxaaLuma(c);
	var lo = min(m, min(min(nw, ne), min(sw, se)));
	var hi = max(m, max(max(nw, ne), max(sw, se)));
	var result = c;
	// (a contrast below an eighth of the brightest, or nearly black: no edge)
	if (hi - lo > max(0.0312, hi * 0.125)) {
		var dir = vec2((sw + se) - (nw + ne), (nw + sw) - (ne + se));
		var reduce = max((nw + ne + sw + se) * 0.03125, 0.0078125);
		var scale = 1 / (min(abs(dir.x), abs(dir.y)) + reduce);
		dir = clamp(dir * scale, -8, 8) * t;
		var a = (sampleLevel(scene, uv + dir * -0.1666667, 0) + sampleLevel(scene, uv + dir * 0.1666667, 0)) * 0.5;
		var b = a * 0.5 + (sampleLevel(scene, uv + dir * -0.5, 0) + sampleLevel(scene, uv + dir * 0.5, 0)) * 0.25;
		var lb = fxaaLuma(b);
		result = b;
		if (lb < lo || lb > hi) result = a;
	}
	return result;
}

// a display colour through a LUT's strip (size cubed as size slices of size by
// size side by side: red across a slice, green down it, blue by slice)
function lutOf(lut:Texture2D, c:Vec3, size:Float):Vec3 {
	var x = clamp(c, 0, 1) * (size - 1);
	var slice = floor(x.z);
	var f = x.z - slice;
	var u = (x.x + 0.5) / (size * size);
	var v = (x.y + 0.5) / size;
	var a = sampleLevel(lut, vec2(u + slice / size, v), 0).xyz;
	var b = sampleLevel(lut, vec2(u + min(slice + 1, size - 1) / size, v), 0).xyz;
	return mix(a, b, f);
}

// the outline over a pixel (rgb its group's colour, a its cover): the edge
// of a selection group within its width of the pixel, the pixel itself not
// of it (the groups' colours in groups' first row, their widths in pixels
// over 255 in its second's red: Outline)
function outlineAt(fx:CompositeFx, normals:Texture2D, groups:Texture2D, uv:Vec2):Vec4 {
	var own = floor(sampleLevel(normals, uv, 0).w * 255 + 0.5);
	var widest = fx.outline.y;
	var px = fx.outline.zw;
	var found = 0.0;
	var hits = 0.0;
	var k = 0.0;
	// (16 taps: 8 directions at the widest width and at half of it)
	while (k < 16) {
		var angle = k * 0.7853982;
		var r = widest;
		if (k > 7.5) r = widest * 0.5;
		var g = floor(sampleLevel(normals, uv + vec2(cos(angle), sin(angle)) * px * r, 0).w * 255 + 0.5);
		if (g > 0.5 && abs(g - own) > 0.5) {
			var w = sampleLevel(groups, vec2((g + 0.5) / 256, 0.75), 0).x * 255;
			if (r <= w + 0.5) {
				if (found < 0.5) found = g;
				if (abs(g - found) < 0.5) hits += 1;
			}
		}
		k += 1;
	}
	var color = vec4(0);
	if (found > 0.5) {
		var c = sampleLevel(groups, vec2((found + 0.5) / 256, 0.25), 0);
		color = vec4(c.xyz, c.w * smoothstep(0, 3, hits));
	}
	return color;
}

// SMAA's blending (its third pass, Jimenez et al.'s neighbourhood
// blending): the pixel mixed towards each neighbour across an edge by the
// share the edge's line covers of it (SmaaPass's weights: r towards the
// pixel above, b towards the left one, from the pixel's own texel; g and a
// of the one below and the one to the right, theirs towards this one)
function smaaBlend(scene:Texture2D, weights:Texture2D, uv:Vec2, t:Vec2):Vec4 {
	var w = sampleLevel(weights, uv, 0);
	var down = sampleLevel(weights, uv + vec2(0, t.y), 0).y;
	var right = sampleLevel(weights, uv + vec2(t.x, 0), 0).w;
	var c = sampleLevel(scene, uv, 0);
	var sum = w.x + w.z + down + right;
	if (sum > 0.0001) {
		var k = 1 / max(sum, 1);
		c = c * (1 - min(sum, 1)) + (sampleLevel(scene, uv - vec2(0, t.y), 0) * w.x + sampleLevel(scene, uv - vec2(t.x, 0), 0) * w.z
			+ sampleLevel(scene, uv + vec2(0, t.y), 0) * down + sampleLevel(scene, uv + vec2(t.x, 0), 0) * right) * k;
	}
	return c;
}

final composite = slots({
	options: {fxaa: false, effects: false, smaa: false},
	vertex: function(v:PostVertex, p:{}, m:Composite):PostVaryings
		return fullscreen(v),
	fragment: function(i:PostVaryings, params:CompositeInputs, m:Composite):Vec4 {
		var s = sampleLevel(params.scene, i.uv, 0);
		if (m.options.fxaa) s = fxaa(params.scene, i.uv, vec2(1 / params.p.size.x, 1 / params.p.size.y));
		if (m.options.smaa) s = smaaBlend(params.scene, params.weights, i.uv, vec2(1 / params.p.size.x, 1 / params.p.size.y));
		if (m.options.effects) {
			if (params.fx.dof.x > 0.5) {
				// (depth of field: the half-size blur where the circle is wider than its texels)
				var z = viewDepthAt(params.fx.inverseProjection, i.uv, sampleLevel(params.viewDepth, i.uv, 0).x);
				var coc = cocOf(params.fx.dof, focusOf(params.fx, params.viewDepth), z) * params.p.size.y;
				s = mix(s, sampleLevel(params.blur, i.uv, 0), smoothstep(0.5, params.fx.dofFocus.z * 1.5, coc));
			}
			// (god rays: the sky's light streaming towards the sun, added)
			if (params.fx.rays.x > 0.5) s = vec4(s.xyz + sampleLevel(params.rays, i.uv, 0).xyz * params.fx.rays.y, s.w);
		}
		var hdr = clamp(s.xyz, 0, 65000);
		var spread = sampleLevel(params.bloom, i.uv, 0).xyz * params.p.lift.w;
		var color = mix(hdr, spread, params.p.exposure.y) * params.p.exposure.x;
		var curve = params.p.exposure.z;
		var mapped = encode(clamp(color, 0, 1));
		if (curve < 1.5) mapped = encode(aces(color));
		if (curve < 0.5) mapped = agx(color);
		// (the grade, on display values)
		var y = dot(mapped, vec3(0.2126, 0.7152, 0.0722));
		mapped = mix(vec3(y), mapped, params.p.grade.x);
		mapped = (mapped - 0.5) * params.p.grade.y + 0.5;
		mapped = clamp(mapped * params.p.gain.xyz + params.p.lift.xyz * (1 - mapped), 0, 1);
		if (m.options.effects) {
			// (the LUT, after the curve and the grade: display values in and out)
			if (params.fx.lut.x > 0.5) mapped = mix(mapped, lutOf(params.lut, mapped, params.fx.lut.x), params.fx.lut.y);
		}
		// (the vignette: the corners darker, by the target's shape)
		var at = (i.uv - 0.5) * vec2(params.p.size.z, 1);
		var r = length(at) / length(vec2(params.p.size.z, 1) * 0.5);
		mapped *= 1 - params.p.grade.z * smoothstep(0.35, 1.05, r);
		// (alpha: the scene's coverage, or bloom's light where nothing was drawn)
		var alpha = 1.0;
		if (params.p.size.w > 0.5) alpha = clamp(max(s.w, max(mapped.x, max(mapped.y, mapped.z))), 0, 1);
		if (m.options.effects) {
			// (the selection's outlines, over everything: see-through surfaces too)
			if (params.fx.outline.x > 0.5) {
				var o = outlineAt(params.fx, params.viewNormals, params.groups, i.uv);
				mapped = mix(mapped, o.xyz, o.w);
				alpha = max(alpha, o.w);
			}
		}
		// (grain, most in the middle tones, and a dither below an 8-bit step)
		var px = floor(i.uv * params.p.size.xy);
		var noise = hash(px + vec2(fract(params.p.exposure.w * 0.61) * 1931, fract(params.p.exposure.w * 0.37) * 727)) - 0.5;
		var mid = 1 - abs(y * 2 - 1);
		mapped += vec3(noise * (params.p.grade.w * (0.35 + 0.65 * mid) + 1.0 / 255)) * alpha;
		return vec4(clamp(mapped, 0, 1), alpha);
	}
});

// the composite (PostProcess): the scene and its bloom, the curve and the
// grade; with FXAA, CompositeFxaaShader (post.antialias Fxaa), and the
// effects' variants, CompositeFxShader (PostFx's), are modules of their
// own: linked only by a program that sets them
final CompositeShader = composite.gpuVariant();
