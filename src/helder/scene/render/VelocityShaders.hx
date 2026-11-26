package helder.scene.render;

import helder.math.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.EffectShaders;

// The view buffers' motion (ViewBuffers.velocity): the opaque surfaces
// drawn again, a second pass (gfx has one colour target a pass), into an
// RGBA16F target: xy how far each pixel's point moved on the screen since
// the frame before (in uv: this frame's less the last's, the jitter left
// out), z 1 where a surface wrote it (0: none drawn there, skinned or
// beyond: the camera's motion from depth, motionAt). Each point by this
// frame's and the last frame's matrices: the node's own (its world matrix
// then and now) and the camera's (their view-projections without jitter);
// rasterized by the frame's jittered one, as the view buffers are. A
// module of its own: linked by a program that asks for motion (TAA, motion
// blur by objects).
@:structInit @:publicFields class VelocityVertex {
	var pos:Vec3;
	var normal:Vec3;
	var uv:Vec2;
}

// (an instanced run's: this frame's matrix, then the last frame's, by columns)
@:structInit @:publicFields class VelocityInstanceVertex {
	var pos:Vec3;
	var normal:Vec3;
	var uv:Vec2;
	var m0:Vec4;
	var m1:Vec4;
	var m2:Vec4;
	var m3:Vec4;
	var p0:Vec4;
	var p1:Vec4;
	var p2:Vec4;
	var p3:Vec4;
}

@:structInit @:publicFields class VelocityVaryings {
	var clip:Vec4;
	var now:Vec4;
	var then:Vec4;
}

// the frame's: the jittered view-projection (where it is drawn), this
// frame's and the last frame's without jitter
@:structInit @:publicFields class VelocityFrame {
	var viewProj:Mat4;
	var current:Mat4;
	var previous:Mat4;
}

// a node's world matrix now and the frame before
@:structInit @:publicFields class VelocityObject {
	var model:Mat4;
	var previous:Mat4;
}

function velocityOut(i:VelocityVaryings):Vec4
	return vec4(clipUv(i.now) - clipUv(i.then), 1, 1);

final VelocityShader = shader({
	vertex: function(v:VelocityVertex, params:{frame:VelocityFrame, object:VelocityObject}):VelocityVaryings {
		var p = vec4(v.pos, 1);
		var world = params.object.model * p;
		return {
			clip: position(params.frame.viewProj * world),
			now: params.frame.current * world,
			then: params.frame.previous * (params.object.previous * p)
		};
	},
	fragment: function(i:VelocityVaryings, params:{}):Vec4
		return velocityOut(i)
});

final VelocityInstancedShader = shader({
	vertex: function(v:VelocityInstanceVertex, params:{frame:VelocityFrame}):VelocityVaryings {
		var p = vec4(v.pos, 1);
		var model = mat4(vec4(v.m0.xyz, 0), vec4(v.m1.xyz, 0), vec4(v.m2.xyz, 0), vec4(v.m3.xyz, 1));
		var last = mat4(vec4(v.p0.xyz, 0), vec4(v.p1.xyz, 0), vec4(v.p2.xyz, 0), vec4(v.p3.xyz, 1));
		var world = model * p;
		return {
			clip: position(params.frame.viewProj * world),
			now: params.frame.current * world,
			then: params.frame.previous * (last * p)
		};
	},
	fragment: function(i:VelocityVaryings, params:{}):Vec4
		return velocityOut(i)
});
