import helder.math.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.ui.draw.PartShader;

// A part's shader for ControlsCostCheck's escape hatch (PartShader): a glow of
// the look's accent, brighter as the control's hover eases in
final ControlsGlow = shader({
	vertex: function(v:DrawVertex):DrawVaryings return drawVertex(v),
	fragment: function(i:DrawVaryings, p:{part:DrawParams}):Vec4 {
		var d = length(i.uv - vec2(0.5, 0.5)) * 2;
		var k = clamp(1 - d, 0, 1) * (0.4 + p.part.states.x * 0.6);
		return vec4(p.part.accent.x * k, p.part.accent.y * k, p.part.accent.z * k, k);
	}
});
