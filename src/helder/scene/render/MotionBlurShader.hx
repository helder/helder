package helder.scene.render;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.EffectShaders;
import helder.scene.render.PostShader;

// Motion blur's shaders (MotionBlur, MotionBlurPass), a module of their
// own: McGuire et al.'s reconstruction ("A Reconstruction Filter for
// Plausible Motion Blur", 2012), simplified, in five passes:
//
//   MotionPrepShader      each texel of the view buffers' size: its motion
//                         (motionAt: theirs where a surface wrote it, else
//                         the camera's from depth) times the shutter, at
//                         most the longest blur; xy in uv, z its length in
//                         the frame's pixels
//   MotionTileShader      a texel a tile of 8 x 8 of those: the longest
//   MotionNeighbourShader a tile's and its 8 neighbours' longest: the line
//                         a pixel there gathers along (a still background
//                         beside a moving object takes the object's smear,
//                         not only the object its own edges)
//   MotionBlurShader      each pixel of a target half the frame's size:
//                         taps along its tile's
//                         line (every other one along the pixel's own
//                         motion, when it moves at least half as fast: McGuire's 2014 variant, so a
//                         turning wheel keeps its arcs), each counting where its own motion reaches
//                         the pixel or the pixel's reaches the tap (both
//                         centred), the pixel itself always; turned by
//                         interleaved gradient noise (no bands); under half a
//                         pixel of motion about it, the pixel as it is
//   MotionMixShader       each pixel of the frame: its light, mixed
//                         towards the blur where its tile's longest motion
//                         is over a pixel (as depth of field's blur is
//                         mixed in: what moves is soft, what is still keeps
//                         its pixels)
// Texels read at their centres by index (the frame's pixel's, its tile's),
// the motion between them filtered: no texel's edge that back ends round
// apart (a tile's side: 8 texels). p: x the shutter's share, y the taps, w the longest blur (a share
// of the height); size: the pass's target, then what it reads

final MotionPrepShader = shader({
	vertex: function(v:PostVertex):PostVaryings
		return fullscreen(v),
	fragment: function(i:PostVaryings, params:{m:MotionParams, motion:Texture2D, depth:Texture2D}):Vec4 {
		var m = params.m;
		var at = (floor(i.uv * m.size.xy) + 0.5) / m.size.xy;
		var v = motionAt(m, params.motion, params.depth, at, at, at) * m.p.x;
		var span = length(v * vec2(m.q.y, 1));
		if (span > m.p.w) v = v * (m.p.w / span);
		return vec4(v, length(v * m.q.zw), 1);
	}
});

final MotionTileShader = shader({
	vertex: function(v:PostVertex):PostVaryings
		return fullscreen(v),
	fragment: function(i:PostVaryings, params:{m:MotionParams, prep:Texture2D}):Vec4 {
		var m = params.m;
		var base = floor(i.uv * m.size.xy) * 8.0;
		var best = vec4(0);
		var y = 0.0;
		while (y < 8.0) {
			var x = 0.0;
			while (x < 8.0) {
				var at = base + vec2(x, y);
				if (at.x < m.size.z && at.y < m.size.w) {
					var t = sampleLevel(params.prep, (at + 0.5) / m.size.zw, 0);
					if (t.z > best.z) best = t;
				}
				x += 1;
			}
			y += 1;
		}
		return best;
	}
});

final MotionNeighbourShader = shader({
	vertex: function(v:PostVertex):PostVaryings
		return fullscreen(v),
	fragment: function(i:PostVaryings, params:{m:MotionParams, tiles:Texture2D}):Vec4 {
		var m = params.m;
		var px = floor(i.uv * m.size.xy);
		var best = vec4(0);
		var y = -1.0;
		while (y < 1.5) {
			var x = -1.0;
			while (x < 1.5) {
				var t = sampleLevel(params.tiles, (clamp(px + vec2(x, y), vec2(0), m.size.xy - 1) + 0.5) / m.size.xy, 0);
				if (t.z > best.z) best = t;
				x += 1;
			}
			y += 1;
		}
		return best;
	}
});

// (whether a motion of length l, in pixels, centred, reaches d pixels)
function reaches(d:Float, l:Float):Float
	return clamp(1 - (d - l * 0.5), 0, 1);

// size: xy the target's pixels (half the frame's), zw the tiles'; q: z
// the view buffers' share of the target
final MotionBlurShader = shader({
	vertex: function(v:PostVertex):PostVaryings
		return fullscreen(v),
	fragment: function(i:PostVaryings, params:{m:MotionParams, scene:Texture2D, prep:Texture2D, neighbours:Texture2D}):Vec4 {
		var m = params.m;
		var px = floor(i.uv * m.size.xy);
		var uv = (px + 0.5) / m.size.xy;
		var c = sampleLevel(params.scene, uv, 0);
		// (its tile's: the pixel's view buffers' texel, by index, over the tile's side)
		var tile = (floor(floor(px * m.q.z) / 8.0) + 0.5) / m.size.zw;
		var most = sampleLevel(params.neighbours, tile, 0);
		var out = c;
		if (most.z > 0.5) {
			var own = sampleLevel(params.prep, uv, 0);
			var mine = own.z;
			var n = m.p.y;
			var turn = ign(px);
			var sum = clamp(c, 0, 256);
			var weights = 1.0;
			var t = 0.0;
			while (t < n) {
				var f = (t + turn) / n - 0.5;
				// (every other tap along the pixel's own motion, when it is at least half the longest about it: a turning wheel's arcs; a still background takes the smear whole)
				var along = most;
				if (mine > 0.5 && mine > most.z * 0.5 && t - floor(t / 2) * 2 > 0.5) along = own;
				var at = uv - along.xy * f;
				var d = abs(f) * along.z;
				var w = max(reaches(d, sampleLevel(params.prep, at, 0).z), reaches(d, mine));
				sum += clamp(sampleLevel(params.scene, at, 0), 0, 256) * w;
				weights += w;
				t += 1;
			}
			out = sum / weights;
		}
		return out;
	}
});

// size: xy the frame's pixels, zw the tiles'; q: z the view buffers' share of the frame
final MotionMixShader = shader({
	vertex: function(v:PostVertex):PostVaryings
		return fullscreen(v),
	fragment: function(i:PostVaryings, params:{m:MotionParams, scene:Texture2D, blur:Texture2D, neighbours:Texture2D}):Vec4 {
		var m = params.m;
		var px = floor(i.uv * m.size.xy);
		var uv = (px + 0.5) / m.size.xy;
		var c = sampleLevel(params.scene, uv, 0);
		var tile = (floor(floor(px * m.q.z) / 8.0) + 0.5) / m.size.zw;
		var most = sampleLevel(params.neighbours, tile, 0).z;
		var out = c;
		if (most > 0.5) out = mix(c, sampleLevel(params.blur, uv, 0), smoothstep(0.5, 1.5, most));
		return out;
	}
});
