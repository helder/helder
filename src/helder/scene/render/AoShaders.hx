package helder.scene.render;

import helder.math.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.EffectShaders;
import helder.scene.render.PostShader;

// Ssao's shaders (EffectShaders' notes): GTAO from the view buffers, its
// bilateral blur up to their size. A module of their own: a program links
// them only with Ssao (a module's finals are made together).
final GtaoShader = shader({
	vertex: function(v:PostVertex):PostVaryings
		return fullscreen(v),
	fragment: function(i:PostVaryings, params:{a:AoParams, depth:Texture2D, normals:Texture2D}):Vec4 {
		var a = params.a;
		// (the view buffers' texel under this pixel: viewTexel's, exact on
		// every back end at half their size too)
		var px = floor(i.uv * a.size.xy);
		var uv = viewTexel(i.uv, a.size.xy, a.size.zw);
		var d = sampleLevel(params.depth, uv, 0).x;
		var visibility = 1.0;
		if (d < 0.99999) {
			var pos = viewPointAt(a.inverseProjection, uv, d);
			var v = normalize(-pos);
			var n = octDecode(sampleLevel(params.normals, uv, 0).xy);
			var radius = a.p.x;
			// (the radius on the screen, in the height's uv; x by the aspect)
			var screen = a.p.w > 0 ? a.p.w * radius / max(-pos.z, 0.0001) : a.more.w;
			var noise = ign(px);
			var jitter = fract(noise * 7.13 + 0.5);
			var slices = a.p.y;
			var steps = a.p.z;
			var range = radius * 0.615;
			var falloffMul = -1 / range;
			var falloffAdd = (radius - range) / range + 1;
			var sum = 0.0;
			var weights = 0.0;
			var s = 0.0;
			while (s < slices) {
				// (along a whole texel step: every tap on a texel's centre and on the slice)
				var step = texelStep(floor(fract(noise + s / slices) * 8));
				var dv = normalize(vec3(step.x, -step.y, 0));
				var ortho = dv - v * dot(dv, v);
				var axis = normalize(cross(ortho, v));
				var pn = n - axis * dot(n, axis);
				var pl = max(length(pn), 0.0001);
				var cosN = clamp(dot(pn, v) / pl, -1, 1);
				var nAngle = (dot(ortho, pn) >= 0 ? 1 : -1) * acos(cosN);
				var low0 = cos(nAngle + 1.5707963);
				var low1 = cos(nAngle - 1.5707963);
				var h0 = low0;
				var h1 = low1;
				// (the radius in steps; each tap at least a step past the last)
				var reach = screen * a.size.w / length(step);
				var k = 0.0;
				while (k < steps) {
					var t = (k + jitter) / steps;
					var m = max(k + 1, floor(t * t * reach + 0.5));
					var off = step * m / a.size.zw;
					var u0 = uv + off;
					var u1 = uv - off;
					var d0 = viewPointAt(a.inverseProjection, u0, sampleLevel(params.depth, u0, 0).x) - pos;
					var d1 = viewPointAt(a.inverseProjection, u1, sampleLevel(params.depth, u1, 0).x) - pos;
					var l0 = max(length(d0), 0.0001);
					var l1 = max(length(d1), 0.0001);
					var w0 = clamp(l0 * falloffMul + falloffAdd, 0, 1);
					var w1 = clamp(l1 * falloffMul + falloffAdd, 0, 1);
					h0 = max(h0, mix(low0, dot(d0 / l0, v), w0));
					h1 = max(h1, mix(low1, dot(d1 / l1, v), w1));
					k += 1;
				}
				// (the horizons' angles, clamped to the hemisphere about the normal)
				var a1 = nAngle + clamp(acos(clamp(h0, -1, 1)) - nAngle, -1.5707963, 1.5707963);
				var a0 = nAngle + clamp(-acos(clamp(h1, -1, 1)) - nAngle, -1.5707963, 1.5707963);
				var sn = sin(nAngle);
				var arc0 = (cosN + 2 * a0 * sn - cos(2 * a0 - nAngle)) * 0.25;
				var arc1 = (cosN + 2 * a1 * sn - cos(2 * a1 - nAngle)) * 0.25;
				// (as a share of the slice's arc unoccluded, cos n + n sin n: a
				// plane open whatever the slice, so one or two slices do not
				// stripe it; weighted by the normal's length in the slice)
				sum += pl * (arc0 + arc1) / max(cosN + nAngle * sn, 0.0001);
				weights += pl;
				s += 1;
			}
			visibility = clamp(sum / max(weights, 0.0001), 0, 1);
		}
		return vec4(visibility, 0, 0, 1);
	}
});

final AoBlurShader = shader({
	vertex: function(v:PostVertex):PostVaryings
		return fullscreen(v),
	fragment: function(i:PostVaryings, params:{b:AoBlurParams, occlusion:Texture2D, depth:Texture2D}):Vec4 {
		var t = params.b.p.xy;
		var zc = -viewPointAt(params.b.inverseProjection, i.uv, sampleLevel(params.depth, i.uv, 0).x).z;
		var sum = 0.0;
		var weights = 0.0;
		var y = -1.0;
		while (y < 1.5) {
			var x = -1.0;
			while (x < 1.5) {
				var at = i.uv + vec2(x, y) * t;
				var z = -viewPointAt(params.b.inverseProjection, at, sampleLevel(params.depth, at, 0).x).z;
				var w = (x == 0 && y == 0 ? 2.0 : 1.0) * clamp(1 - abs(z - zc) / max(zc * 0.04, 0.01), 0.001, 1);
				sum += sampleLevel(params.occlusion, at, 0).x * w;
				weights += w;
				x += 1;
			}
			y += 1;
		}
		var ao = pow(clamp(sum / weights, 0, 1), params.b.p.z);
		return vec4(ao, 0, 0, 1);
	}
});
