package helder.ui.draw;

import helder.gfx.shader.Shader;
import helder.gfx.shader.ShaderMath.*;
import helder.math.Vec2;
import helder.math.Vec4;

// A part drawn by a shader of its own (a recipe's draw, PartShader.of: an
// escape hatch; a function, and outside helder.ui.controls, so that a
// program without one links no GPU code, a TypeScript one either):
// its fragment stage runs over a texture of the part's size, before the
// window's pass, and the part shows that texture under its children. The
// stage is given the part's size, the look's colours it names and the
// control's eased states (DrawParams). Every such part costs a pass of its
// own and splits the window's one draw (a texture of its own bound between
// quads: helder.ui.draw.Renderer), so the default look has none; a whole
// screen of controls stays one pipeline and one draw without them.
//
//   final Glow = shader({
//     vertex: function(v:DrawVertex):DrawVaryings return drawVertex(v),
//     fragment: function(i:DrawVaryings, p:{part:DrawParams}):Vec4 return ...
//   });
//   Look.base.with({button: t -> {root: {draw: PartShader.of(Glow)}}})
class PartShader {
	// a part's draw: its shader's node, made where the part is bound
	public static function of(shader:DrawShader):helder.ui.controls.Recipe.PartDraw
		return (eased, look) -> new PartShaderNode(shader, eased, look);
}

// the vertex stage every part's shader takes: a triangle over the part
function drawVertex(v:DrawVertex):DrawVaryings
	return {clip: position(vec4(v.pos, 0, 1)), uv: vec2(v.pos.x * 0.5 + 0.5, 0.5 - v.pos.y * 0.5)};

typedef DrawShader = Shader<DrawVertex, {part:helder.gfx.shader.Shader.UniformWriter<DrawParams>}>;

@:structInit @:publicFields class DrawVertex {
	var pos:Vec2;
}

@:structInit @:publicFields class DrawVaryings {
	var clip:Vec4;
	var uv:Vec2; // 0, 0 the part's top left
}

@:structInit @:publicFields class DrawParams {
	var size:Vec4; // x, y: the part in pixels, z: pixels a point, w: seconds
	var states:Vec4; // hover, pressed, checked, focus: 0 to 1, eased
	var more:Vec4; // x: open, y: disabled
	var accent:Vec4; // the look's accent, rgba (light or dark, as the window is)
	var fg:Vec4; // its text colour
	var surface:Vec4; // what the part rests on
}
