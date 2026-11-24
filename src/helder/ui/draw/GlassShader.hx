package helder.ui.draw;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// Liquid Glass drawn (GlassPass): what is behind the glass (its backdrop,
// captured: Backdrop) blurred at half size in two passes (GlassBlur, a
// Gaussian along x then y), then the glass itself (GlassShader) over its
// box and its shadow's margin: its shape a distance field (rectangles with
// rounded corners, those of a group blended into one by a smooth minimum
// within its spacing), what is behind it read through a lens at its rim
// (read from further in along the field's normal, more the nearer the
// edge, as a rounded slab of glass bends light), blurred (regular) or
// sharp but at its rim (clear), frosted toward white (dark: grey), its saturation raised and
// its brightness kept, tinted, lit along its rim from the top left and the
// bottom right, a soft shadow under it, a press's glow. All in the
// frame's pixels; colours premultiplied.

@:structInit @:publicFields class GlassVertex {
	var pos:Vec2;
}

@:structInit @:publicFields class GlassVaryings {
	var clip:Vec4;
	var uv:Vec2; // 0, 0 the target's top left
}

@:structInit @:publicFields class BlurParams {
	var map:Vec4; // the source's uv at the target's: xy + uv * zw
	var step:Vec4; // xy: a texel of the source along the blur's axis, in its uv; z: sigma in its texels
}

@:structInit @:publicFields class GlassParams {
	var out:Vec4; // the target: its top left in the frame's pixels, its size
	var capture:Vec4; // the backdrop's: its top left in the frame's pixels, its texture's size
	var blurred:Vec4; // the blurred backdrop's texture's size, the backdrop's pixels a texel of it
	var shape:Vec4; // x: shapes, y: their smooth minimum's reach (pixels), z: clear (1) or regular (0), w: dark (1)
	var tint:Vec4; // its colour, straight alpha: how far
	var lens:Vec4; // x: the rim's displacement at most (pixels), y: the bevel's width (pixels), z: the rim light's width (pixels), w: its strength
	var tone:Vec4; // x: the frost's share, y: saturation, z: brightness, w: the clear glass's blur share
	var shadow:Vec4; // x: its alpha, y: its blur (pixels), z: its offset down (pixels), w: the light's dark-side share
	var press:Vec4; // x, y: the pointer in the frame's pixels, z: pressed (0 to 1), w: the glow's radius (pixels)
	@:length(8) var rects:Array<Vec4>; // each shape: x0, y0, x1, y1 in the frame's pixels
	@:length(8) var radii:Array<Vec4>; // each shape's corners' radius (x)
}

function glassVertex(v:GlassVertex):GlassVaryings
	return {clip: position(vec4(v.pos, 0, 1)), uv: vec2(v.pos.x * 0.5 + 0.5, 0.5 - v.pos.y * 0.5)};

final GlassBlur = shader({
	vertex: function(v:GlassVertex):GlassVaryings return glassVertex(v),
	fragment: function(i:GlassVaryings, p:{blur:BlurParams, source:Texture2D}):Vec4 {
		var uv = p.blur.map.xy + i.uv * p.blur.map.zw;
		var s = max(p.blur.step.z, 0.5);
		var sum = vec4(0, 0, 0, 0);
		var total = 0.0;
		// (taps two texels apart, each read between two (the sampler's
		// filtering averages them): 3 sigmas each way at most)
		for (k in 0...25) {
			var x = k * 2.0 - 24.0;
			if (abs(x) <= s * 3 + 1) {
				var w = exp(-x * x / (2 * s * s));
				sum = sum + sampleLevel(p.source, uv + p.blur.step.xy * (x + 0.5), 0) * w;
				total = total + w;
			}
		}
		return sum / total;
	}
});

// (a rectangle's with rounded corners: its signed distance, the corner's radius r)
function glassBox(p:Vec2, rect:Vec4, r:Float):Float {
	var half = (rect.zw - rect.xy) * 0.5;
	var q = abs(p - (rect.xy + half)) - half + vec2(r, r);
	return length(max(q, vec2(0, 0))) + min(max(q.x, q.y), 0) - r;
}

// (the shapes' distance: the smooth minimum of theirs within k)
function glassField(p:Vec2, g:GlassParams):Float {
	var d = 1e9;
	var k = max(g.shape.y, 0.001);
	for (j in 0...8)
		if (j < Std.int(g.shape.x + 0.5)) {
			var e = glassBox(p, g.rects[j], g.radii[j].x);
			var h = clamp(0.5 + 0.5 * (e - d) / k, 0, 1);
			d = j == 0 ? e : mix(e, d, h) - k * h * (1 - h);
		}
	return d;
}

function glassSaturate(c:Vec3, s:Float):Vec3 {
	var l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	return clamp(vec3(l, l, l) + (c - vec3(l, l, l)) * s, vec3(0, 0, 0), vec3(1, 1, 1));
}

final GlassShader = shader({
	vertex: function(v:GlassVertex):GlassVaryings return glassVertex(v),
	fragment: function(i:GlassVaryings, p:{glass:GlassParams, backdrop:Texture2D, blurred:Texture2D}):Vec4 {
		var g = p.glass;
		var px = g.out.xy + i.uv * g.out.zw;
		var d = glassField(px, g);
		// (the shadow under it, off its shape moved down)
		var sd = glassField(px - vec2(0, g.shadow.z), g);
		var sb = max(g.shadow.y, 0.5);
		var shade = g.shadow.x * exp(-max(sd, 0) * max(sd, 0) / (2 * sb * sb)) * clamp(0.5 + sd, 0, 1);
		var cover = clamp(0.5 - d, 0, 1);
		if (cover <= 0) return vec4(0, 0, 0, shade);
		// (the field's normal, outward)
		var e = 0.5;
		var n = vec2(glassField(px + vec2(e, 0), g) - glassField(px - vec2(e, 0), g), glassField(px + vec2(0, e), g) - glassField(px - vec2(0, e), g));
		var nl = length(n);
		n = nl > 0.0001 ? n / nl : vec2(0, 0);
		// (the lens: a rounded rim, bending most at the edge)
		var t = max(-d, 0);
		var b = max(g.lens.y, 1);
		var k = clamp(1 - t / b, 0, 1);
		var bend = g.lens.x * k * k;
		var q = px - n * bend;
		var cuv = (q - g.capture.xy) / g.capture.zw;
		var buv = (q - g.capture.xy) / (g.blurred.zw * g.blurred.xy);
		var sharp = sampleLevel(p.backdrop, cuv, 0);
		var soft = sampleLevel(p.blurred, buv, 0);
		var clear = g.shape.z;
		// (the clear glass sharp but where its rim bends what it reads)
		var base = mix(soft.xyz, mix(sharp.xyz, soft.xyz, max(g.tone.w, k * k)), clear);
		// (frosted toward white, or a dark grey, as light or dark; saturated; its brightness kept)
		var frost = g.shape.w > 0.5 ? vec3(0.11, 0.11, 0.12) : vec3(1, 1, 1);
		var c = mix(base, frost, g.tone.x);
		c = glassSaturate(c, g.tone.y) * g.tone.z;
		// (tinted: its colour over the light behind it)
		var lum = dot(base, vec3(0.2126, 0.7152, 0.0722));
		c = mix(c, g.tint.xyz * (0.55 + 0.6 * lum), g.tint.w);
		// (the rim's light: from the top left and, less, the bottom right)
		var rim = clamp(1 - t / max(g.lens.z, 0.5), 0, 1);
		var lit = dot(n, vec2(-0.7071, -0.7071));
		var light = max(lit, 0) + max(-lit, 0) * g.shadow.w;
		c = c + vec3(1, 1, 1) * g.lens.w * rim * rim * (0.25 + 0.75 * light * light);
		// (a press: a glow about the pointer)
		var r = max(g.press.w, 1);
		var dp = px - g.press.xy;
		c = c + vec3(1, 1, 1) * g.press.z * 0.18 * exp(-dot(dp, dp) / (2 * r * r));
		c = clamp(c, vec3(0, 0, 0), vec3(1, 1, 1));
		return vec4(c * cover, cover) + vec4(0, 0, 0, shade) * (1 - cover);
	}
});
