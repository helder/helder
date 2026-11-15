package helder.scene.render;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.EffectShaders;
import helder.scene.render.PostShader;

// Motion blur (MotionBlur, MotionBlurPass), a module of its own: McGuire et
// al.'s reconstruction ("A Reconstruction Filter for Plausible Motion
// Blur", 2012), simplified. Each pixel's motion (motionAt) times the
// shutter, at most p.w of the height long; the neighbourhood's longest
// (8 taps on a ring as wide as the longest blur, and the pixel's own)
// is the line the pixel gathers along: so a still background beside a
// moving object takes the object's smear, not only the object its own
// edges. Each tap counts where its own motion reaches the pixel, or the
// pixel's reaches the tap (both centred), the pixel itself always; taps
// turned by interleaved gradient noise (no bands). Under half a pixel of
// motion about it, the pixel as it is. p: x the shutter's share, y the
// taps, w the longest blur (a share of the height)

// (a pixel's motion times the shutter, at most the longest blur; the
// view buffers' motion filtered, read where the taps fall: no texel's edge
// that back ends round apart)
function blurMotion(m:MotionParams, motion:Texture2D, depth:Texture2D, uv:Vec2):Vec2 {
	var at = clamp(uv, 0, 1);
	var views = (floor(at * m.size.zw) + 0.5) / m.size.zw;
	var v = motionAt(m, motion, depth, at, views, at) * m.p.x;
	var span = length(v * vec2(m.q.y, 1));
	if (span > m.p.w) v = v * (m.p.w / span);
	return v;
}

// (whether a motion of length l, in pixels, centred, reaches d pixels)
function reaches(d:Float, l:Float):Float
	return clamp(1 - (d - l * 0.5), 0, 1);

final MotionBlurShader = shader({
	vertex: function(v:PostVertex):PostVaryings
		return fullscreen(v),
	fragment: function(i:PostVaryings, params:{m:MotionParams, scene:Texture2D, motion:Texture2D, depth:Texture2D}):Vec4 {
		var m = params.m;
		var px = floor(i.uv * m.size.xy);
		var uv = (px + 0.5) / m.size.xy;
		var c = sampleLevel(params.scene, uv, 0);
		var own = blurMotion(m, params.motion, params.depth, uv);
		// (the longest about it)
		var most = own;
		var ring = m.p.w * 0.5;
		var k = 0.0;
		while (k < 8) {
			var angle = k * 0.7853982;
			var o = blurMotion(m, params.motion, params.depth, uv + vec2(cos(angle) / m.q.y, sin(angle)) * ring);
			if (length(o * m.size.xy) > length(most * m.size.xy)) most = o;
			k += 1;
		}
		var out = c;
		var line = length(most * m.size.xy);
		if (line > 0.5) {
			var mine = length(own * m.size.xy);
			var n = m.p.y;
			var turn = ign(px);
			var sum = clamp(c, 0, 256);
			var weights = 1.0;
			var t = 0.0;
			while (t < n) {
				var f = (t + turn) / n - 0.5;
				var at = uv - most * f;
				var d = abs(f) * line;
				var theirs = length(blurMotion(m, params.motion, params.depth, at) * m.size.xy);
				var w = max(reaches(d, theirs), reaches(d, mine));
				sum += clamp(sampleLevel(params.scene, at, 0), 0, 256) * w;
				weights += w;
				t += 1;
			}
			out = sum / weights;
		}
		return out;
	}
});
