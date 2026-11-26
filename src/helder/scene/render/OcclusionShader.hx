package helder.scene.render;

import helder.math.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// Occlusion's boxes (Occlusion), a module of its own: a unit cube (0..1 on
// each axis) turned into a tested node's bounds in the world by its
// instance's matrix (the bounds' corner and sides, the node's world
// matrix), drawn after the opaque surfaces depth tested and not written,
// its colour white multiplied into the target (nothing changed): each
// box's samples that pass counted by its query.
@:structInit @:publicFields class OcclusionVertex {
	var pos:Vec3;
	var m0:Vec4;
	var m1:Vec4;
	var m2:Vec4;
	var m3:Vec4;
}

@:structInit @:publicFields class OcclusionVaryings {
	var clip:Vec4;
}

@:structInit @:publicFields class OcclusionView {
	var viewProj:Mat4;
}

final OcclusionShader = shader({
	vertex: function(v:OcclusionVertex, params:{view:OcclusionView}):OcclusionVaryings
		return {clip: position(params.view.viewProj * (mat4(v.m0, v.m1, v.m2, v.m3) * vec4(v.pos, 1)))},
	fragment: function(i:OcclusionVaryings, params:{}):Vec4
		return vec4(1)
});
