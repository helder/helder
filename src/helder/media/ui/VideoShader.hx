package helder.media.ui;

import helder.math.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// A video frame's planes (helder.media.VideoFrame: luma, and chroma at
// half its size, NV12's or P010's) into RGB, turned upright: a triangle
// over the target, each pixel's place in the frame turned by the
// rotation (turn.x: quarter turns clockwise), chroma read where it is
// sited (turn.y: its offset across, the frame's width's share: MPEG-2's
// left siting), Y'CbCr times a matrix of the range's offsets and scales
// and the colours' coefficients (r, g, b: the rows over Y', Cb, Cr, 1);
// in a browser and on Android the frame is RGB already (turn.z 1), only
// turned, read in the share of its texture the picture is (turn.y, turn.w:
// an Android buffer's crop)
@:structInit @:publicFields class VideoVertex {
	var pos:Vec2;
}

@:structInit @:publicFields class VideoVaryings {
	var clip:Vec4;
	var uv:Vec2;
}

@:structInit @:publicFields class VideoParams {
	var r:Vec4;
	var g:Vec4;
	var b:Vec4;
	var turn:Vec4;
}

final VideoShader = shader({
	vertex: function(v:VideoVertex):VideoVaryings
		return {clip: position(vec4(v.pos, 0, 1)), uv: vec2(v.pos.x * 0.5 + 0.5, 0.5 - v.pos.y * 0.5)},
	fragment: function(i:VideoVaryings, p:{video:VideoParams, luma:Texture2D, chroma:Texture2D}):Vec4 {
		var t = p.video.turn.x, uv = i.uv;
		var st = t < 0.5 ? uv : t < 1.5 ? vec2(uv.y, 1 - uv.x) : t < 2.5 ? vec2(1 - uv.x, 1 - uv.y) : vec2(1 - uv.y, uv.x);
		var uv2 = sample(p.chroma, st + vec2(p.video.turn.y, 0));
		var y = sample(p.luma, st * mix(vec2(1, 1), vec2(p.video.turn.y, p.video.turn.w), p.video.turn.z));
		var c = vec4(y.x, uv2.x, uv2.y, 1);
		// (turn.z 1: luma is the picture in RGB already, the browser's, Android's)
		return p.video.turn.z > 0.5 ? vec4(y.x, y.y, y.z, 1) : vec4(clamp(dot(c, p.video.r), 0, 1), clamp(dot(c, p.video.g), 0, 1), clamp(dot(c,
			p.video.b), 0, 1), 1);
	}
});
