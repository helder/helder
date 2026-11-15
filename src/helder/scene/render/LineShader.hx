package helder.scene.render;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.PbrShader.aces;
import helder.scene.render.PbrShader.encode;
import helder.scene.render.PbrShader.fogAmount;

// Lines with width (Lines, drawn by LineRenderer): each segment one
// instance, a quad across it and two fans of 8 triangles at its ends (Lines.FAN), all
// placed on the screen in pixels (three's Line2, Babylon's GreasedLine). The
// segment's ends and their neighbours come from four views of the same
// point buffer (the previous point, the segment's two, the next), so a
// point is written once. The quad's sides are half the width from the
// segment on the screen (a width in pixels, or in the world's units: its
// pixels at the end's depth). The fan at the segment's start draws the
// line's start cap (Round), the one at its end the join with the next
// segment (on the turn's outer side: Round's arc, Bevel's triangle,
// Miter's point up to 4 half widths out, else bevelled) or the line's end
// cap; a square cap moves the quad's end out by half the width. A
// neighbour at its point (the line's first and last) is none. A segment
// crossing the near plane is cut at it. Dashes (in the world's units along
// the line: each point's distance from the first) are dropped fragments.
// Fogged, then tone mapped and encoded into an 8-bit target unless asked
// not to (toneMapped off: debug colours), as they are into HDR.
@:structInit @:publicFields class LineVertex {
	// per vertex: x the piece (0 the quad, 1 the start's fan, 2 the end's),
	// y the quad's end (0, 1) or the fan's point (-1 its centre, 0 to FAN
	// round its arc: Lines.FAN), z the quad's side (-1, 1)
	var corner:Vec4;
	// per instance: the point before the segment's (xyz, w its distance
	// along the line), the segment's two with their colours, the one after
	var prev:Vec4;
	var a:Vec4;
	var colorA:Vec4;
	var b:Vec4;
	var colorB:Vec4;
	var next:Vec4;
}

@:structInit @:publicFields class LineVaryings {
	var clip:Vec4;
	var color:Vec4;
	// x: the distance along the line
	var along:Vec2;
}

@:structInit @:publicFields class LineView {
	var viewProj:Mat4;
	var model:Mat4;
	// x, y the target's size in pixels, z the projection's vertical scale
	// (a world width's pixels at depth w: width z y / 2 w), w 1 into an HDR target
	var viewport:Vec4;
	// x the half width, y 1: the width in the world's units, z the join (0
	// miter, 1 round, 2 bevel), w the caps (0 butt, 1 round, 2 square)
	var style:Vec4;
	// x the dash's length (0: none), y the gap's, z the dashes' offset, w 1: tone mapped
	var dash:Vec4;
	var fog:Vec4;
	var fogShape:Vec4;
	var eye:Vec4;
}


// (a point's clip position, cut at the near plane towards other)
function nearCut(p:Vec4, other:Vec4):Vec4 {
	var result = p;
	var eps = 0.0001;
	if (p.w < eps) {
		var t = (eps - p.w) / max(other.w - p.w, 0.000001);
		result = mix(p, other, clamp(t, 0, 1));
	}
	return result;
}

function toPixels(c:Vec4, size:Vec2):Vec2
	return c.xy / max(c.w, 0.0001) * size * 0.5;

function perp(d:Vec2):Vec2
	return vec2(-d.y, d.x);

function unit2(d:Vec2, fallback:Vec2):Vec2 {
	var l = length(d);
	var result = fallback;
	if (l > 0.000001) result = d / l;
	return result;
}

// (v turned by angle radians, counter-clockwise)
function turn(v:Vec2, angle:Float):Vec2 {
	var c = cos(angle), s = sin(angle);
	return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

final LineShader = shader({
	vertex: function(v:LineVertex, params:{view:LineView}):LineVaryings {
		var view = params.view;
		var vp = view.viewProj * view.model;
		var size = view.viewport.xy;
		var ca0 = vp * vec4(v.a.xyz, 1), cb0 = vp * vec4(v.b.xyz, 1);
		var cp = vp * vec4(v.prev.xyz, 1), cn = vp * vec4(v.next.xyz, 1);
		var ca = nearCut(ca0, cb0), cb = nearCut(cb0, ca0);
		var pa = toPixels(ca, size), pb = toPixels(cb, size);
		var dir = unit2(pb - pa, vec2(1, 0));
		var n = perp(dir);
		// (neighbours: none where one is the segment's own point)
		var hasPrev = step(0.000001, length(v.prev.xyz - v.a.xyz));
		var hasNext = step(0.000001, length(v.next.xyz - v.b.xyz));
		// (half the width in pixels at each end)
		var hw = view.style.x;
		var worldA = view.style.x * view.viewport.z * size.y * 0.5 / max(ca.w, 0.0001);
		var worldB = view.style.x * view.viewport.z * size.y * 0.5 / max(cb.w, 0.0001);
		var hwA = mix(hw, worldA, view.style.y), hwB = mix(hw, worldB, view.style.y);
		var piece = v.corner.x, k = v.corner.y;
		var atB = 0.0;
		var offset = vec2(0, 0);
		var cap = view.style.w, join = view.style.z;
		if (piece < 0.5) {
			// (the quad: an end, a side; a square cap's end moved out)
			atB = v.corner.y;
			var w = mix(hwA, hwB, atB);
			offset = n * (v.corner.z * w);
			var square = step(1.5, cap) * mix(1.0 - hasPrev, 1.0 - hasNext, atB);
			offset = offset + dir * (w * square * (atB * 2.0 - 1.0));
		} else if (piece < 1.5) {
			// (the start's round cap, from n round the back to -n; none else)
			var on = (1.0 - hasPrev) * step(0.5, cap) * (1.0 - step(1.5, cap));
			var angle = 3.14159265 * 0.5 + 3.14159265 * max(k, 0.0) / 8.0;
			offset = (dir * cos(angle) + n * sin(angle)) * (hwA * on * step(-0.5, k));
		} else {
			atB = 1.0;
			if (hasNext < 0.5) {
				// (the end's round cap, from -n round the front to n)
				var on = step(0.5, cap) * (1.0 - step(1.5, cap));
				var angle = -3.14159265 * 0.5 + 3.14159265 * max(k, 0.0) / 8.0;
				offset = (dir * cos(angle) + n * sin(angle)) * (hwB * on * step(-0.5, k));
			} else {
				// (the join, on the turn's outer side: from this segment's side to the next one's)
				var cn2 = nearCut(cn, cb0);
				var d2 = unit2(toPixels(cn2, size) - pb, dir);
				var bend = dir.x * d2.y - dir.y * d2.x;
				var side = 1.0 - 2.0 * step(0.0, bend);
				var v1 = n * side, v2 = perp(d2) * side;
				var angle = atan2(v1.x * v2.y - v1.y * v2.x, dot(v1, v2));
				var round = turn(v1, angle * max(k, 0.0) / 8.0);
				var m = unit2(v1 + v2, v1);
				var reach = 1.0 / max(dot(m, v1), 0.0001);
				var bevel = mix(v1, v2, step(0.5, k));
				var miter = bevel;
				if (k > 0.5 && k < 7.5) miter = m * reach;
				if (reach > 4.0) miter = bevel;
				var shaped = miter;
				if (join > 0.5) shaped = round;
				if (join > 1.5) shaped = bevel;
				offset = shaped * (hwB * step(-0.5, k));
			}
		}
		var c = mix(ca, cb, atB);
		var p = mix(pa, pb, atB) + offset;
		var clip = vec4(p / (size * 0.5) * c.w, c.z, c.w);
		var color = mix(v.colorA, v.colorB, atB);
		var at = view.model * vec4(mix(v.a.xyz, v.b.xyz, atB), 1);
		var f = fogAmount(view.fog, view.fogShape, view.eye.xyz, at.xyz);
		color = vec4(mix(color.xyz, view.fog.xyz, f), color.w);
		// (a segment wholly behind the eye: nothing)
		var behind = step(ca0.w, 0.0) * step(cb0.w, 0.0);
		clip = mix(clip, vec4(0, 0, -2, 1), behind);
		return {clip: position(clip), color: color, along: vec2(mix(v.a.w, v.b.w, atB), 0)};
	},
	fragment: function(i:LineVaryings, p:{view:LineView}):Vec4 {
		var dash = p.view.dash;
		if (dash.x > 0) {
			var period = dash.x + dash.y;
			var m = fract((i.along.x + dash.z) / period) * period;
			if (m > dash.x) discard();
		}
		var c = i.color.xyz;
		if (p.view.viewport.w < 0.5) {
			if (dash.w > 0.5) c = encode(aces(c)) else c = encode(c);
		}
		// (blended: premultiplied by its alpha; opaque: alpha ignored)
		var a = mix(1.0, i.color.w, p.view.eye.w);
		return vec4(c * a, a);
	}
});
