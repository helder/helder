package helder.scene.render;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.PostShader;

// What the shaders of post's effects share (their blocks, functions), and
// the notes on them; each effect's shaders are a module of their own, so
// that a program links only those of the effects it makes (a module's
// finals are made together): AoShaders (GtaoShader, AoBlurShader: Ssao),
// DofShader (Dof), CompositeFxShader (PostFx). Each a triangle over the
// whole target, as the chain's.
//
//   GtaoShader      ambient occlusion (Jimenez et al., "Practical Real-Time
//                   Strategies for Accurate Indirect Occlusion", 2016, as
//                   Intel's XeGTAO lays it out): from the view buffers'
//                   depth and normals, slices of the hemisphere about the
//                   view (along whole texel steps, so each tap is a texel's
//                   centre on the slice), each's two horizons found to a radius,
//                   the visible arc integrated against the normal
//                   projected into the slice, as a share of the slice's
//                   arc unoccluded (so a plane is open whatever the
//                   slices: no stripes from one or two); turned and jittered by
//                   interleaved gradient noise (the next pass's blur takes
//                   it away)
//   AoBlurShader    the occlusion up to the view buffers' size, a 3x3
//                   blur of its texels weighted by their depths' match
//                   with the pixel's (bilateral: no halo across edges),
//                   its intensity applied
//   DofShader       depth of field's blur at half size: taps on a disc
//                   (Vogel's) as wide as the pixel's circle of confusion,
//                   a tap nearer than the pixel taken where its own circle
//                   reaches it (a sharp foreground does not bleed into a
//                   blurred background)
//   CompositeFxShader, CompositeFxFxaaShader  the composite with the
//                   effects folded in (PostShader's composite, effects)

// the occlusion's pass: the view buffers' inverse projection; x the radius
// (metres), y the slices, z the steps a side, w the projection's scale (a
// metre at a distance of 1, in the height's uv; 0 for an orthographic one,
// its radius's in more.w); size: xy the target's pixels, zw the view
// buffers' (their texels' centres are where depth is read); more:
// x the frame's aspect, w an orthographic view's radius in uv
@:structInit @:publicFields class AoParams {
	var inverseProjection:Mat4;
	var p:Vec4;
	var size:Vec4;
	var more:Vec4;
}

// the blur: xy a texel of the occlusion, z its intensity (a power), w unused; the inverse projection
@:structInit @:publicFields class AoBlurParams {
	var p:Vec4;
	var inverseProjection:Mat4;
}

// depth of field's blur: xy the target's pixels, z the frame's aspect, w its taps
@:structInit @:publicFields class DofParams {
	var size:Vec4;
}

// (interleaved gradient noise: Jimenez's, 0..1 by pixel)
function ign(px:Vec2):Float
	return fract(52.9829189 * fract(dot(px, vec2(0.06711056, 0.00583715))));

// a view-space point from the view buffers' depth at uv
function viewPointAt(inverse:Mat4, uv:Vec2, d:Float):Vec3 {
	var p = inverse * vec4(uv.x * 2 - 1, 1 - uv.y * 2, d, 1);
	return p.xyz / p.w;
}

// a unit vector from octEncode's two components
function octDecode(e:Vec2):Vec3 {
	var f = e * 2 - 1;
	var n = vec3(f.x, f.y, 1 - abs(f.x) - abs(f.y));
	var t = clamp(-n.z, 0, 1);
	n = vec3(n.x + (n.x >= 0 ? -t : t), n.y + (n.y >= 0 ? -t : t), n.z);
	return normalize(n);
}

// a slice's step in texels (x right, y down) by an index 0 to 7: whole
// steps over half a turn (0, 27, 45, 63, 90, 117, 135, 153 degrees)
function texelStep(k:Float):Vec2 {
	var d = vec2(1, 0);
	if (k > 0.5) d = vec2(2, 1);
	if (k > 1.5) d = vec2(1, 1);
	if (k > 2.5) d = vec2(1, 2);
	if (k > 3.5) d = vec2(0, 1);
	if (k > 4.5) d = vec2(-1, 2);
	if (k > 5.5) d = vec2(-1, 1);
	if (k > 6.5) d = vec2(-2, 1);
	return d;
}
