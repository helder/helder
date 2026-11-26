package helder.scene.render;

import helder.math.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.EffectShaders;
import helder.scene.render.PostShader;

// Screen-space reflections' shaders (Ssr, SsrPass), a module of their own:
//
//   SsrTraceShader    each pixel's reflected ray from its view-space point
//                     (the view buffers' depth and normal at its texel),
//                     marched in steps of maxDistance / steps (the first
//                     turned by interleaved gradient noise), each projected
//                     and its depth compared with the view buffers' there:
//                     behind the surface by less than its thickness, a hit,
//                     found more closely by 4 halvings between the last two
//                     steps; rgb the scene's light at the hit, a its weight
//                     (faded towards the screen's edges, the ray's end, the
//                     roughest surface that reflects and rays towards the eye)
//   SsrResolveShader  the scene's light at the frame's size, mixed towards
//                     the reflection by Schlick's Fresnel at the view's
//                     angle (F0 0.04, a metal's 1), the reflection's weight
//                     and the intensity
@:structInit @:publicFields class SsrParams {
	var projection:Mat4; // the view buffers' (jittered: the frame's)
	var inverseProjection:Mat4;
	var p:Vec4; // x max distance (m), y thickness (m), z steps, w the roughest reflecting
	var size:Vec4; // xy the target's pixels, zw the view buffers'
	var q:Vec4; // x intensity, y the dither's turn this frame (0: still)
}

final SsrTraceShader = shader({
	vertex: function(v:PostVertex):PostVaryings
		return fullscreen(v),
	fragment: function(i:PostVaryings, params:{s:SsrParams, depth:Texture2D, normals:Texture2D, scene:Texture2D}):Vec4 {
		var s = params.s;
		var at = viewTexel(i.uv, s.size.xy, s.size.zw);
		var d = sampleLevel(params.depth, at, 0).x;
		var out = vec4(0);
		var texel = sampleLevel(params.normals, at, 0);
		var rough = roughnessOf(texel.z);
		if (d < 0.99999 && rough < s.p.w) {
			var pos = viewPointAt(s.inverseProjection, at, d);
			var n = octDecode(texel.xy);
			var view = normalize(pos);
			var r = reflect(view, n);
			var step = s.p.x / s.p.z;
			// (from a little off the surface, along the normal: not hitting itself)
			var origin = pos + n * (0.02 + 0.002 * -pos.z);
			// (the first step's dither: still, or turned each frame where TAA gathers the frames: q.y)
			var t = step * fract(ign(floor(i.uv * s.size.xy)) + s.q.y);
			var last = t;
			var hit = vec2(-1);
			var k = 0.0;
			while (k < s.p.z) {
				var p = origin + r * t;
				var uv = clipUv(s.projection * vec4(p, 1));
				if (p.z > -0.0001 || uv.x < 0 || uv.x > 1 || uv.y < 0 || uv.y > 1) break;
				var z = viewPointAt(s.inverseProjection, uv, sampleLevel(params.depth, uv, 0).x).z;
				var behind = z - p.z;
				if (behind > 0 && behind < s.p.y) {
					// (between the last step and this one: 4 halvings)
					var lo = last;
					var hi = t;
					var h = 0.0;
					while (h < 4) {
						var mid = (lo + hi) * 0.5;
						var q = origin + r * mid;
						var quv = clipUv(s.projection * vec4(q, 1));
						var qz = viewPointAt(s.inverseProjection, quv, sampleLevel(params.depth, quv, 0).x).z;
						if (qz - q.z > 0) hi = mid else lo = mid;
						h += 1;
					}
					hit = clipUv(s.projection * vec4(origin + r * hi, 1));
					t = hi;
					break;
				}
				last = t;
				t += step;
				k += 1;
			}
			if (hit.x >= 0) {
				var edge = min(min(hit.x, 1 - hit.x), min(hit.y, 1 - hit.y));
				var weight = smoothstep(0, 0.08, edge) * (1 - smoothstep(0.6, 1, t / s.p.x)) * (1 - smoothstep(0, 1, rough / s.p.w))
					* (1 - smoothstep(0.2, 0.8, r.z));
				out = vec4(clamp(sampleLevel(params.scene, hit, 0).xyz, 0, 256), weight);
			}
		}
		return out;
	}
});

final SsrResolveShader = shader({
	vertex: function(v:PostVertex):PostVaryings
		return fullscreen(v),
	fragment: function(i:PostVaryings, params:{s:SsrParams, depth:Texture2D, normals:Texture2D, scene:Texture2D, reflections:Texture2D}):Vec4 {
		var s = params.s;
		var c = sampleLevel(params.scene, i.uv, 0);
		var at = viewTexel(i.uv, s.size.xy, s.size.zw);
		var reflected = sampleLevel(params.reflections, i.uv, 0);
		var out = c;
		if (reflected.w > 0.001) {
			var texel = sampleLevel(params.normals, at, 0);
			var pos = viewPointAt(s.inverseProjection, at, sampleLevel(params.depth, at, 0).x);
			var n = octDecode(texel.xy);
			var cosine = clamp(dot(n, -normalize(pos)), 0, 1);
			var f0 = mix(0.04, 1.0, metalnessOf(texel.z));
			var fresnel = f0 + (1 - f0) * pow(1 - cosine, 5);
			out = vec4(mix(c.xyz, reflected.xyz, clamp(fresnel * reflected.w * s.q.x, 0, 1)), c.w);
		}
		return out;
	}
});
