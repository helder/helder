package helder.scene.render;

import helder.math.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.EffectShaders;
import helder.scene.render.PostShader;

// God rays (GodRays, GodRaysPass), a module of its own: from each pixel of
// a target a quarter of the frame's size, taps towards the sun's place on
// the screen, each the scene's light where the view buffers' depth is the
// sky's (the far plane), weighted by its nearness to the sun (falloff) and
// fading by decay a tap (each at most 4: the sun's disc does not speckle
// the shafts); their mean, times the sun's fade (1 on the
// screen, less beyond its edges, 0 behind the camera).
@:structInit @:publicFields class GodRaysParams {
	var sun:Vec4; // xy the sun's uv, z its fade (0 none), w the frame's aspect
	var p:Vec4; // x taps, y density, z decay, w falloff
	var size:Vec4; // xy the target's pixels, zw the view buffers'
}

final GodRaysShader = shader({
	vertex: function(v:PostVertex):PostVaryings
		return fullscreen(v),
	fragment: function(i:PostVaryings, params:{g:GodRaysParams, scene:Texture2D, depth:Texture2D}):Vec4 {
		var g = params.g;
		var sun = g.sun.xy;
		var n = g.p.x;
		var step = (i.uv - sun) * (g.p.y / n);
		var at = i.uv - step * ign(floor(i.uv * g.size.xy));
		var weight = 1.0;
		var sum = vec3(0);
		var k = 0.0;
		while (k < n) {
			var views = (floor(clamp(at, 0, 0.99999) * g.size.zw) + 0.5) / g.size.zw;
			var sky = sampleLevel(params.depth, views, 0).x >= 0.99999 ? 1.0 : 0.0;
			var near = exp(-length((at - sun) * vec2(g.sun.w, 1)) * g.p.w);
			sum += clamp(sampleLevel(params.scene, at, 0).xyz, 0, 4) * (sky * near * weight);
			weight *= g.p.z;
			at -= step;
			k += 1;
		}
		return vec4(sum * (g.sun.z / n), 1);
	}
});
