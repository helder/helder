import helder.math.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// The layers frame's shaders (Layers.hx): a screen of tiles, each a cube's
// face read along the directions through it (TextureCube), or a 2D array's
// layer (Texture2DArray); and the mark drawn into a cube's face
@:structInit @:publicFields class LayersVertex {
	var pos:Vec2;
}

@:structInit @:publicFields class LayersVaryings {
	var pos:Vec4;
	var uv:Vec2;
}

// the direction through a face's uv (0 to 5: +x, -x, +y, -y, +z, -z; v down
// the face), as the APIs read a cube's faces
function faceDirection(face:Float, uv:Vec2):Vec3 {
	var s = uv.x * 2 - 1, t = uv.y * 2 - 1;
	var d = vec3(-s, -t, -1);
	if (face < 0.5) d = vec3(1, -t, -s);
	else if (face < 1.5) d = vec3(-1, -t, s);
	else if (face < 2.5) d = vec3(s, 1, t);
	else if (face < 3.5) d = vec3(s, -1, -t);
	else if (face < 4.5) d = vec3(s, -t, 1);
	return d;
}

final LayersShader = shader({
	vertex: function(v:LayersVertex):LayersVaryings
		return {pos: position(vec4(v.pos, 0, 1)), uv: vec2(v.pos.x * 0.5 + 0.5, 0.5 - v.pos.y * 0.5)},
	fragment: function(i:LayersVaryings, p:{faces:TextureCube, drawn:TextureCube, layers:Texture2DArray, drawnLayers:Texture2DArray}):Vec4 {
		// (three rows: the uploaded cube's faces, the drawn cube's, then the arrays' layers)
		var row = floor(i.uv.y * 3);
		var v = i.uv.y * 3 - row;
		var c = vec4(0);
		if (row < 1.5) {
			var face = floor(i.uv.x * 6);
			var d = faceDirection(face, vec2(i.uv.x * 6 - face, v));
			c = row < 0.5 ? sample(p.faces, d) : sampleLevel(p.drawn, d, 0);
		} else {
			var k = floor(i.uv.x * 4);
			var uv = vec2(i.uv.x * 4 - k, v);
			c = k < 0.5 ? sample(p.layers, uv, 0) : k < 1.5 ? sample(p.layers, uv, 1) : k < 2.5 ? sampleLevel(p.drawnLayers, uv, 0, 0) : sample(p.drawnLayers, uv, 1);
		}
		return vec4(c.xyz, 1);
	}
});

final MarkShader = shader({
	vertex: function(v:LayersVertex):LayersVaryings
		return {pos: position(vec4(v.pos, 0, 1)), uv: v.pos},
	fragment: function(i:LayersVaryings):Vec4
		return vec4(1, 1, 1, 1)
});
