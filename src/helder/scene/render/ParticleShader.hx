package helder.scene.render;

import helder.math.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.GpuParticleShader;
import helder.scene.render.PbrShader.output;
import helder.scene.render.PbrShader.fogAmount;

// Particles' (simulated) particles drawn where they are: GpuParticleShader's
// quads, streaks and fades, its position and velocity the step's (start:
// the position now, w its birth; velocity: its velocity now, w its life),
// not of its birth's time. The same instance layout and view block.
final ParticleShader = shader({
	vertex: function(v:GpuParticleVertex, params:{view:GpuParticleView}):GpuParticleVaryings {
		var age = params.view.up.w - v.start.w, life = v.velocity.w;
		var t = age / max(life, 0.0001);
		var alive = step(0.0, age) * step(t, 1.0);
		var p = v.start.xyz, now = v.velocity.xyz;
		var size = mix(v.shape.x, v.shape.y, t) * alive;
		var speed = length(now);
		var dir = now / max(speed, 0.0001);
		var across = cross(dir, params.view.forward.xyz);
		var l = length(across);
		var s = step(0.0001, v.shape.z) * step(0.0001, speed) * step(0.0001, l);
		var axis = mix(params.view.right.xyz, dir, s);
		var side = mix(params.view.up.xyz, across / max(l, 0.0001), s);
		var len = s * speed * v.shape.z;
		var q = p - axis * (len * 0.5 * (1.0 - v.corner.x)) + axis * (v.corner.x * size) + side * (v.corner.y * size);
		var fade = (1.0 - t) * min(1.0, t * 12.0 + 0.2);
		var hot = 1.0 + v.shape.w * (1.0 - t) * (1.0 - t) * 3.0;
		fade *= 1.0 - fogAmount(params.view.fog, params.view.fogShape, params.view.eye.xyz, p);
		return {clip: position(params.view.viewProj * vec4(q, 1)), corner: v.corner, color: vec4(v.color.xyz * hot, v.color.w * fade * alive)};
	},
	fragment: function(i:GpuParticleVaryings, p:{view:GpuParticleView}):Vec4 {
		var d = 1 - smoothstep(0.15, 1, length(i.corner));
		var c = output(i.color.xyz * (i.color.w * d), p.view.right.w);
		var cover = p.view.right.w > 0.5 ? 0.0 : min(1.0, max(c.x, max(c.y, c.z)));
		return vec4(c, cover);
	}
});
