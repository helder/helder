package helder.scene.render.shading;

import helder.math.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.MaterialShader;
import helder.scene.render.PbrShader;
import helder.scene.render.shading.Unlit;

// The view's depth as a grey (three's MeshDepthMaterial): white at the
// material's near distance (Material.depthNear) down the camera's view,
// black at its far one (depthFar), linear between: the distance along the
// view, not the depth buffer's curve. A debug view: Material.depth is not
// tone mapped.

function depthColor(s:PbrSurface, p:{frame:PbrFrame, material:PbrMaterial}):Vec3 {
	var d = -toView(p.frame, s.world - p.frame.eye.xyz).z;
	var near = p.material.model.z;
	var far = p.material.model.w;
	return vec3(1 - clamp((d - near) / max(far - near, 0.0001), 0, 1));
}

final depth = unlit.with({color: depthColor});

final DepthShader = MaterialShader.material(depth);
