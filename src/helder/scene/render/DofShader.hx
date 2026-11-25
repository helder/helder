package helder.scene.render;

import helder.math.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.EffectShaders;
import helder.scene.render.PostShader;

// Dof's blur (EffectShaders' notes), a module of its own: linked only with Dof.
final DofShader = shader({
	vertex: function(v:PostVertex):PostVaryings
		return fullscreen(v),
	fragment: function(i:PostVaryings, params:{fx:CompositeFx, d:DofParams, scene:Texture2D, viewDepth:Texture2D}):Vec4 {
		var fx = params.fx;
		var focus = focusOf(fx, params.viewDepth);
		var at = viewTexel(i.uv, params.d.size.xy, params.d.views.xy);
		var zc = viewDepthAt(fx.inverseProjection, at, sampleLevel(params.viewDepth, at, 0).x);
		var radius = cocOf(fx.dof, focus, zc);
		var c = sampleLevel(params.scene, i.uv, 0);
		var texel = 1 / params.d.size.y;
		if (radius > texel * 0.5) {
			var n = params.d.size.w;
			var turn = ign(floor(i.uv * params.d.size.xy)) * 6.2831853;
			var sum = c;
			var weights = 1.0;
			var k = 0.0;
			while (k < n) {
				var r = sqrt((k + 0.5) / n) * radius;
				var angle = k * 2.3999632 + turn;
				var at = i.uv + vec2(cos(angle) / params.d.size.z, sin(angle)) * r;
				var z = viewDepthAt(fx.inverseProjection, at, sampleLevel(params.viewDepth, at, 0).x);
				var w = 1.0;
				if (z < zc * 0.98) w = clamp((cocOf(fx.dof, focus, z) - r) / texel + 1, 0, 1);
				sum += clamp(sampleLevel(params.scene, at, 0), 0, 256) * w;
				weights += w;
				k += 1;
			}
			c = sum / weights;
		}
		return c;
	}
});
