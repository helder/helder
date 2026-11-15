package helder.scene.render;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.PbrShader.encode;

// GridHelper's infinite grid: one quad on its node's xz plane, under the
// eye and as wide as the grid fades, its lines found per fragment (a
// cell's, a major one's every tenth, the x axis red and the z axis blue)
// as wide as a pixel there: the fragment's footprint on the plane from its
// distance and the view's slant (gfx has no derivatives), the cells' lines
// faded out where they would alias, the whole faded with the distance.
// Blended over the scene, depth tested, not written.
@:structInit @:publicFields class GridVertex {
	var corner:Vec2;
}

@:structInit @:publicFields class GridVaryings {
	var clip:Vec4;
	// the plane's point (its x and z, in the node's frame) and the world's
	var local:Vec2;
	var world:Vec4;
}

@:structInit @:publicFields class GridView {
	var viewProj:Mat4;
	var model:Mat4;
	// xyz the eye (the world's), w 1 into an HDR target
	var eye:Vec4;
	// x the cell, y the cells a major line, z how far it fades out (the
	// node's units), w a pixel's angle (radians)
	var grid:Vec4;
	// xy the quad's centre on the plane (the eye's, in the node's frame), z the node's scale
	var centre:Vec4;
	var minor:Vec4;
	var major:Vec4;
}

// (how near a line, 0 to 1: d from it, w its half width)
function gridLine(d:Float, w:Float):Float
	return 1.0 - smoothstep(w * 0.5, w * 1.5, d);

function gridDistance(x:Float, cell:Float):Float
	return abs(fract(x / cell + 0.5) - 0.5) * cell;

final GridShader = shader({
	vertex: function(v:GridVertex, params:{view:GridView}):GridVaryings {
		var g = params.view;
		var p = g.centre.xy + v.corner * g.grid.z;
		var w = g.model * vec4(p.x, 0, p.y, 1);
		return {clip: position(g.viewProj * w), local: p, world: w};
	},
	fragment: function(i:GridVaryings, p:{view:GridView}):Vec4 {
		var g = p.view;
		var toEye = g.eye.xyz - i.world.xyz;
		var dist = max(length(toEye), 0.0001);
		// (the plane's normal in the world: the model's y)
		var up = normalize((g.model * vec4(0, 1, 0, 0)).xyz);
		var slant = max(abs(dot(up, toEye / dist)), 0.08);
		// (a pixel's footprint on the plane, in the node's units)
		var foot = dist * g.grid.w / slant / max(g.centre.z, 0.000001);
		var cell = g.grid.x, big = g.grid.x * g.grid.y;
		var minorLine = max(gridLine(gridDistance(i.local.x, cell), foot), gridLine(gridDistance(i.local.y, cell), foot));
		var majorLine = max(gridLine(gridDistance(i.local.x, big), foot), gridLine(gridDistance(i.local.y, big), foot));
		minorLine *= 1.0 - smoothstep(cell * 0.12, cell * 0.4, foot);
		majorLine *= 1.0 - smoothstep(big * 0.12, big * 0.4, foot);
		var xAxis = gridLine(abs(i.local.y), foot * 1.5), zAxis = gridLine(abs(i.local.x), foot * 1.5);
		var c = g.minor * minorLine;
		c = mix(c, g.major, majorLine * g.major.w);
		c = mix(c, vec4(0.9, 0.2, 0.2, 1), xAxis);
		c = mix(c, vec4(0.2, 0.4, 0.95, 1), zAxis);
		var fade = 1.0 - smoothstep(g.grid.z * 0.4, g.grid.z, length(i.local - g.centre.xy));
		var a = c.w * fade;
		var rgb = c.xyz;
		if (g.eye.w < 0.5) rgb = encode(rgb);
		return vec4(rgb, a);
	}
});
