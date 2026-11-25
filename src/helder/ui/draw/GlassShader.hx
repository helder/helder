package helder.ui.draw;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// Liquid Glass drawn (GlassPass): what is behind the glass (its backdrop,
// captured: Backdrop) brought down to a half or a quarter of its size by a
// box filter (GlassDown: each texel the mean of the block it stands for, so
// that nothing aliases), blurred there along x, then y (GlassBlur, a
// Gaussian), then the glass itself (GlassShader) over its box and its
// shadow's margin: its shape a rounded box's exact distance (Inigo Quilez's
// sdRoundBox; a group's blended by a smooth minimum within its spacing),
// what is behind it read a little further in near its rim (a lens: within a
// bevel at most half the shape's thickness, the reading moved at most 0.45
// of the bevel, so that it never folds; along the normal of a rounder box,
// whose corners are the bevel's at least, so that the normal never jumps
// across a diagonal), blurred (regular) or sharp but for its rim (clear),
// frosted, its saturation and brightness, washed toward its tint (in a key
// window only, as the system's), lit along its rim, a soft shadow under
// it, a press's glow, a dither of a level against banding. All in the
// frame's pixels; colours premultiplied. Its edge a darker line.

@:structInit @:publicFields class GlassVertex {
	var pos:Vec2;
}

@:structInit @:publicFields class GlassVaryings {
	var clip:Vec4;
	var uv:Vec2; // 0, 0 the target's top left
}

@:structInit @:publicFields class DownParams {
	var map:Vec4; // the source's uv at the target's: xy + uv * zw
	var step:Vec4; // xy: a texel of the source, in its uv; z: taps along each axis (1: a 2x2 block, 2: a 4x4 one)
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
	var state:Vec4; // x: the window key (1) or not (0), y: the tint's share, z: the frost added when not key, w: the dither's levels
	var edge:Vec4; // x: the edge's darkening (a share, over the rim light's width)
	@:length(8) var rects:Array<Vec4>; // each shape: x0, y0, x1, y1 in the frame's pixels
	@:length(8) var radii:Array<Vec4>; // each shape's corners' radius (x)
}

function glassVertex(v:GlassVertex):GlassVaryings
	return {clip: position(vec4(v.pos, 0, 1)), uv: vec2(v.pos.x * 0.5 + 0.5, 0.5 - v.pos.y * 0.5)};

final GlassDown = shader({
	vertex: function(v:GlassVertex):GlassVaryings return glassVertex(v),
	fragment: function(i:GlassVaryings, p:{down:DownParams, source:Texture2D}):Vec4 {
		var uv = p.down.map.xy + i.uv * p.down.map.zw;
		var n = p.down.step.z > 1.5 ? 2 : 1;
		var sum = vec4(0, 0, 0, 0);
		// (each tap between four texels: one the mean of a 2x2 block, four of a 4x4 one)
		for (a in 0...2)
			for (b in 0...2)
				if (a < n && b < n) {
					var o = n > 1 ? vec2(a * 2.0 - 1.0, b * 2.0 - 1.0) : vec2(0, 0);
					sum = sum + sampleLevel(p.source, uv + p.down.step.xy * o, 0);
				}
		return sum / (n * n * 1.0);
	}
});

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

// (a rectangle's with rounded corners (Inigo Quilez's sdRoundBox): its
// signed distance, the corners' radius r, at most its half size)
function glassBox(p:Vec2, rect:Vec4, r:Float):Float {
	var half = (rect.zw - rect.xy) * 0.5;
	var rr = min(r, min(half.x, half.y));
	var q = abs(p - (rect.xy + half)) - half + vec2(rr, rr);
	return length(max(q, vec2(0, 0))) + min(max(q.x, q.y), 0) - rr;
}

// (the shapes' distance: the smooth minimum of theirs within k; round: the
// corners' radii at least that)
function glassField(p:Vec2, g:GlassParams, round:Float):Float {
	var d = 1e9;
	var k = max(g.shape.y, 0.001);
	for (j in 0...8)
		if (j < Std.int(g.shape.x + 0.5)) {
			var e = glassBox(p, g.rects[j], max(g.radii[j].x, round));
			var h = clamp(0.5 + 0.5 * (e - d) / k, 0, 1);
			d = j == 0 ? e : mix(e, d, h) - k * h * (1 - h);
		}
	return d;
}

// (the thinnest of the shapes' half sizes: the bevel at most)
function glassThin(g:GlassParams):Float {
	var t = 1e9;
	for (j in 0...8)
		if (j < Std.int(g.shape.x + 0.5)) {
			var r = g.rects[j];
			t = min(t, min(r.z - r.x, r.w - r.y) * 0.5);
		}
	return t;
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
		var d = glassField(px, g, 0);
		// (the shadow under it, off its shape moved down)
		var sd = glassField(px - vec2(0, g.shadow.z), g, 0);
		var sb = max(g.shadow.y, 0.5);
		// (the rim's light and the shadow a key window's: the system's glass has neither in another)
		var shade = g.shadow.x * g.state.x * exp(-max(sd, 0) * max(sd, 0) / (2 * sb * sb)) * clamp(0.5 + sd, 0, 1);
		var cover = clamp(0.5 - d, 0, 1);
		if (cover <= 0) return vec4(0, 0, 0, shade);
		// (the lens: within the bevel, bending most at the edge, never folding)
		var b = max(min(g.lens.y, glassThin(g) * 0.5), 1);
		var t = max(-d, 0);
		var k = clamp(1 - t / b, 0, 1);
		var bend = min(g.lens.x, b * 0.45) * k * k;
		var n = vec2(0, 0);
		if (bend > 0.001) {
			var e = 0.5;
			n = vec2(glassField(px + vec2(e, 0), g, b) - glassField(px - vec2(e, 0), g, b), glassField(px + vec2(0, e), g, b) - glassField(px - vec2(0, e), g, b));
			var nl = length(n);
			n = nl > 0.0001 ? n / nl : vec2(0, 0);
		}
		var q = px - n * bend;
		var cuv = (q - g.capture.xy) / g.capture.zw;
		var buv = (q - g.capture.xy) / (g.blurred.zw * g.blurred.xy);
		var sharp = sampleLevel(p.backdrop, cuv, 0);
		var soft = sampleLevel(p.blurred, buv, 0);
		var clear = g.shape.z;
		var active = g.state.x;
		// (the clear glass sharp but where its rim bends what it reads)
		var base = mix(soft.xyz, mix(sharp.xyz, soft.xyz, min(g.tone.w + k * k * 0.5, 1)), clear);
		// (frosted toward white, or a dark grey, as light or dark, more when not key; saturated; its brightness)
		var frost = g.shape.w > 0.5 ? vec3(0.11, 0.11, 0.12) : vec3(1, 1, 1);
		var c = mix(base, frost, min(g.tone.x + (1 - active) * g.state.z, 1));
		c = glassSaturate(c, g.tone.y) * g.tone.z;
		// (washed toward its tint, its alpha how far, in a key window)
		c = mix(c, g.tint.xyz, g.tint.w * g.state.y * active);
		// (the rim's light: from the top left and, less, the bottom right)
		var rim = clamp(1 - t / max(g.lens.z, 0.5), 0, 1);
		var e2 = 0.5;
		var rn = vec2(glassField(px + vec2(e2, 0), g, 0) - glassField(px - vec2(e2, 0), g, 0), glassField(px + vec2(0, e2), g, 0) - glassField(px - vec2(0, e2), g, 0));
		var rl = length(rn);
		rn = rl > 0.0001 ? rn / rl : vec2(0, 0);
		var lit = dot(rn, vec2(-0.7071, -0.7071));
		var light = max(lit, 0) + max(-lit, 0) * g.shadow.w;
		c = c + vec3(1, 1, 1) * g.lens.w * active * rim * rim * (0.25 + 0.75 * light * light);
		// (its edge a line a little darker, as the system's)
		c = c * (1 - g.edge.x * rim);
		// (a press: a glow about the pointer)
		var r = max(g.press.w, 1);
		var dp = px - g.press.xy;
		c = c + vec3(1, 1, 1) * g.press.z * 0.18 * exp(-dot(dp, dp) / (2 * r * r));
		// (a dither of a level: no bands in what the blur makes smooth)
		var cell = floor(px);
		var noise = fract(52.9829189 * fract(0.06711056 * cell.x + 0.00583715 * cell.y)) - 0.5;
		c = clamp(c + vec3(noise, noise, noise) * (g.state.w / 255), vec3(0, 0, 0), vec3(1, 1, 1));
		return vec4(c * cover, cover) + vec4(0, 0, 0, shade) * (1 - cover);
	}
});
