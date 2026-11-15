package helder.scene.render;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.EffectShaders;
import helder.scene.render.PostShader;

// Temporal antialiasing's resolve (post.antialias Taa: TaaPass), a module
// of its own: this frame's light, jittered by a sub-pixel (Renderer.jitter),
// gathered with the history (the frames before, resolved) where this
// pixel's point was the frame before (motionAt: the view buffers' motion,
// else the camera's from depth), the history kept within this pixel's
// neighbourhood of 3x3 (its colours' mean and spread in YCoCg, inside
// their box: what was not there the frame before is let go, Salvi's
// variance clipping within Karis' clamp), in a tone mapped space (each
// colour over 1 plus its luma: a bright speck weighs as a dim one), the
// history's share 1 less MotionParams.p.x. Its own target's texels are the
// frame's and the view buffers' at the same size (TAA asks for them whole),
// read at their centres: a pixel's index, not its uv floored (viewTexel).
// p: x the new frame's share, y 1 where the history is the frame before's
// (0: the first frame, a cut: this frame alone)

// (a colour into the tone mapped space, and back)
function taaIn(c:Vec3):Vec3
	return c / (1 + luma(c));

function taaOut(c:Vec3):Vec3
	return c / max(1 - luma(c), 0.0001);

function toYCoCg(c:Vec3):Vec3
	return vec3(dot(c, vec3(0.25, 0.5, 0.25)), dot(c, vec3(0.5, 0, -0.5)), dot(c, vec3(-0.25, 0.5, -0.25)));

function fromYCoCg(c:Vec3):Vec3
	return vec3(c.x + c.y - c.z, c.x + c.z, c.x - c.y - c.z);

final TaaShader = shader({
	vertex: function(v:PostVertex):PostVaryings
		return fullscreen(v),
	fragment: function(i:PostVaryings, params:{m:MotionParams, scene:Texture2D, history:Texture2D, motion:Texture2D, depth:Texture2D}):Vec4 {
		var m = params.m;
		var px = floor(i.uv * m.size.xy);
		var t = 1 / m.size.xy;
		var uv = (px + 0.5) * t;
		var views = viewTexel(i.uv, m.size.xy, m.size.zw);
		var c = clamp(sampleLevel(params.scene, uv, 0), 0, 256);
		var mean = vec3(0);
		var square = vec3(0);
		var lo = vec3(1000);
		var hi = vec3(-1000);
		var alo = 1.0;
		var ahi = 0.0;
		var y = -1.0;
		while (y < 1.5) {
			var x = -1.0;
			while (x < 1.5) {
				var s = clamp(sampleLevel(params.scene, uv + vec2(x, y) * t, 0), 0, 256);
				var q = toYCoCg(taaIn(s.xyz));
				mean += q;
				square += q * q;
				lo = min(lo, q);
				hi = max(hi, q);
				alo = min(alo, s.w);
				ahi = max(ahi, s.w);
				x += 1;
			}
			y += 1;
		}
		mean = mean / 9;
		var spread = sqrt(max(square / 9 - mean * mean, vec3(0)));
		lo = max(lo, mean - spread * 1.25);
		hi = min(hi, mean + spread * 1.25);
		var now = toYCoCg(taaIn(c.xyz));
		var share = m.p.x;
		var was = uv - motionAt(m, params.motion, params.depth, uv, views, views);
		var out = now;
		var alpha = c.w;
		if (m.p.y > 0.5 && was.x >= 0 && was.x <= 1 && was.y >= 0 && was.y <= 1) {
			var h = sampleLevel(params.history, was, 0);
			var kept = clamp(toYCoCg(taaIn(clamp(h.xyz, 0, 256))), lo, hi);
			out = mix(kept, now, share);
			alpha = mix(clamp(h.w, alo, ahi), c.w, share);
		}
		return vec4(taaOut(max(fromYCoCg(out), vec3(0))), alpha);
	}
});
