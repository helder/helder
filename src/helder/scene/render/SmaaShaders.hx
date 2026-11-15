package helder.scene.render;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.EffectShaders;
import helder.scene.render.PostShader;

// SMAA's first two passes (post.antialias Smaa: SmaaPass; Jimenez, Echevarria,
// Sousa, Gutierrez, "SMAA: Enhanced Subpixel Morphological Antialiasing",
// 2012), its third, the blending, in the composite (PostShader's
// smaaBlend). A module of its own.
//
//   SmaaEdgeShader    the edges: x where a pixel's luma (of its light, tone
//                     mapped, its square root: perceptual) differs from its
//                     left neighbour's by more than the threshold, y from its
//                     top one's, each kept where it is at least half the
//                     strongest edge about it (SMAA's local contrast
//                     adaptation: an edge beside a stronger one is not one)
//   SmaaWeightShader  for each pixel on an edge's lower or right side, the
//                     edge's run searched both ways (16 pixels at most each
//                     way), the edges that cross it at its two ends found,
//                     and from those the line a silhouette took through the
//                     staircase (MLAA's patterns: L, Z and U shapes, the
//                     line from an end's crossing to the run's middle or to
//                     the other end), the share of the pixel and of its
//                     neighbour across the edge the line covers: how much
//                     of each other's colour each takes. Its areas are
//                     worked out, not looked up (SMAA's area texture is a
//                     table of these; its diagonal and corner patterns are
//                     not built: SMAA's medium preset)
// Every texel read at its centre: the pixel's index, not its uv floored.
@:structInit @:publicFields class SmaaParams {
	var size:Vec4; // xy the target's pixels, z the edges' threshold, w the search's length (pixels)
}

// (perceptual luma of light: tone mapped, square rooted)
function smaaLuma(c:Vec4):Float
	return sqrt(fxaaLuma(c));

final SmaaEdgeShader = shader({
	vertex: function(v:PostVertex):PostVaryings
		return fullscreen(v),
	fragment: function(i:PostVaryings, params:{s:SmaaParams, scene:Texture2D}):Vec4 {
		var t = 1 / params.s.size.xy;
		var uv = (floor(i.uv * params.s.size.xy) + 0.5) * t;
		var l = smaaLuma(sampleLevel(params.scene, uv, 0));
		var left = smaaLuma(sampleLevel(params.scene, uv - vec2(t.x, 0), 0));
		var top = smaaLuma(sampleLevel(params.scene, uv - vec2(0, t.y), 0));
		var delta = vec2(abs(l - left), abs(l - top));
		var edges = vec2(delta.x > params.s.size.z ? 1.0 : 0.0, delta.y > params.s.size.z ? 1.0 : 0.0);
		if (edges.x + edges.y > 0.5) {
			// (the strongest edge about it: right, bottom, and the next ones left and up)
			var right = smaaLuma(sampleLevel(params.scene, uv + vec2(t.x, 0), 0));
			var bottom = smaaLuma(sampleLevel(params.scene, uv + vec2(0, t.y), 0));
			var left2 = smaaLuma(sampleLevel(params.scene, uv - vec2(t.x * 2, 0), 0));
			var top2 = smaaLuma(sampleLevel(params.scene, uv - vec2(0, t.y * 2), 0));
			var most = max(max(max(delta.x, delta.y), max(abs(l - right), abs(l - bottom))), max(abs(left - left2), abs(top - top2)));
			if (delta.x * 2 < most) edges = vec2(0, edges.y);
			if (delta.y * 2 < most) edges = vec2(edges.x, 0);
		}
		return vec4(edges, 0, 1);
	}
});

// the area between a line from (x0, y0) to (x1, y1) and the edge (y 0)
// over x from a to b: x the part on the positive side, y the negative
function lineArea(x0:Float, y0:Float, x1:Float, y1:Float, a:Float, b:Float):Vec2 {
	var lo = max(a, x0);
	var hi = min(b, x1);
	var out = vec2(0);
	if (hi > lo) {
		var ya = y0 + (y1 - y0) * (lo - x0) / (x1 - x0);
		var yb = y0 + (y1 - y0) * (hi - x0) / (x1 - x0);
		if (ya >= 0 && yb >= 0) out = vec2((ya + yb) * 0.5 * (hi - lo), 0);
		else if (ya <= 0 && yb <= 0) out = vec2(0, -(ya + yb) * 0.5 * (hi - lo));
		else {
			var xc = lo + (hi - lo) * ya / (ya - yb);
			var first = abs(ya) * (xc - lo) * 0.5;
			var second = abs(yb) * (hi - xc) * 0.5;
			out = ya > 0 ? vec2(first, second) : vec2(second, first);
		}
	}
	return out;
}

// a run's area over the pixel at x (0 its first pixel) of d pixels, the
// crossings at its ends (yl, yr: +0.5 on the positive side, -0.5 the
// negative, 0 none): Z (opposite sides) the line end to end, U (the same
// side) two lines to the middle, L (one end) one to the middle
function runArea(x:Float, d:Float, yl:Float, yr:Float):Vec2 {
	var out = vec2(0);
	if (yl != 0 && yr != 0 && yl * yr < 0) out = lineArea(0, yl, d, yr, x, x + 1);
	else {
		if (yl != 0) out += lineArea(0, yl, d * 0.5, 0, x, x + 1);
		if (yr != 0) out += lineArea(d * 0.5, 0, d, yr, x, x + 1);
	}
	return out;
}

// (an end's crossing: +0.5 when it is on the positive side alone and the
// edge goes on a pixel over that way (a step of a staircase, not a T where
// another edge meets this one: SMAA's corner detection, kept simple), -0.5
// the negative's, 0 neither or both)
function crossing(positive:Float, negative:Float, onPositive:Float, onNegative:Float):Float {
	var c = 0.0;
	if (positive > 0.5 && negative < 0.5 && onPositive > 0.5) c = 0.5;
	if (negative > 0.5 && positive < 0.5 && onNegative > 0.5) c = -0.5;
	return c;
}

final SmaaWeightShader = shader({
	vertex: function(v:PostVertex):PostVaryings
		return fullscreen(v),
	fragment: function(i:PostVaryings, params:{s:SmaaParams, edges:Texture2D}):Vec4 {
		var t = 1 / params.s.size.xy;
		var uv = (floor(i.uv * params.s.size.xy) + 0.5) * t;
		var e = sampleLevel(params.edges, uv, 0);
		var limit = params.s.size.w;
		var out = vec4(0);
		var dx = vec2(t.x, 0);
		var dy = vec2(0, t.y);
		if (e.y > 0.5) {
			// (the edge on top of this pixel: its run along the row, left and right)
			var l = 0.0;
			while (l < limit && sampleLevel(params.edges, uv - dx * (l + 1), 0).y > 0.5)
				l += 1;
			var r = 0.0;
			while (r < limit && sampleLevel(params.edges, uv + dx * (r + 1), 0).y > 0.5)
				r += 1;
			// (the crossings: the vertical edges at the run's first pixel's
			// left and past its last, on the row above (positive) or this one)
			var first = uv - dx * l;
			var past = uv + dx * (r + 1);
			var yl = crossing(sampleLevel(params.edges, first - dy, 0).x, sampleLevel(params.edges, first, 0).x, sampleLevel(params.edges, first - dx - dy, 0).y,
				sampleLevel(params.edges, first - dx + dy, 0).y);
			var yr = crossing(sampleLevel(params.edges, past - dy, 0).x, sampleLevel(params.edges, past, 0).x, sampleLevel(params.edges, past - dy, 0).y,
				sampleLevel(params.edges, past + dy, 0).y);
			var a = runArea(l, l + r + 1, yl, yr);
			// (r: this pixel towards the one above; g: that one towards this)
			out = vec4(a.y, a.x, out.z, out.w);
		}
		if (e.x > 0.5) {
			// (the edge on this pixel's left: its run down the column, up and down)
			var u = 0.0;
			while (u < limit && sampleLevel(params.edges, uv - dy * (u + 1), 0).x > 0.5)
				u += 1;
			var d = 0.0;
			while (d < limit && sampleLevel(params.edges, uv + dy * (d + 1), 0).x > 0.5)
				d += 1;
			var first = uv - dy * u;
			var past = uv + dy * (d + 1);
			var yl = crossing(sampleLevel(params.edges, first - dx, 0).y, sampleLevel(params.edges, first, 0).y, sampleLevel(params.edges, first - dy - dx, 0).x,
				sampleLevel(params.edges, first - dy + dx, 0).x);
			var yr = crossing(sampleLevel(params.edges, past - dx, 0).y, sampleLevel(params.edges, past, 0).y, sampleLevel(params.edges, past - dx, 0).x,
				sampleLevel(params.edges, past + dx, 0).x);
			var a = runArea(u, u + d + 1, yl, yr);
			// (b: this pixel towards the left one; a: that one towards this)
			out = vec4(out.x, out.y, a.y, a.x);
		}
		return out;
	}
});
