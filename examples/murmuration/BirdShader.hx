import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import FlockShaders;
import SkyShader;

// A bird: its few triangles turned along its velocity, banked, the wings
// beating by its phase. One too far to cover a pixel or so is drawn that
// big and as much fainter (its coverage in its alpha), so the far flock is
// a smoke that thickens and thins without flicker. Far ones fade into the
// haze behind them.
// Mirrored in the still water too: some of them, bigger, fainter.
@:structInit @:publicFields class BirdVertex {
	var shape:Vec4; // x right, y up, z ahead (a wingspan of 1); w: how much of the beat it takes
	var pos:Vec4;
	var vel:Vec4;
	var mood:Vec4;
}

@:structInit @:publicFields class BirdVaryings {
	var pos:Vec4;
	var color:Vec4;
}

@:structInit @:publicFields class BirdView {
	var viewProj:Mat4;
	var eye:Vec4; // w: pixels a radian
	var sun:Vec4;
	var size:Vec4; // x: the wingspan (m), y: the fewest pixels drawn, z: -1 mirrored in the water, w: the opacity
}

final BirdShader = shader({
	vertex: function(v:BirdVertex, p:{view:BirdView}):BirdVaryings {
		var f = normalize(v.vel.xyz);
		var r0 = rightOf(f);
		var u0 = cross(r0, f);
		var cb = cos(v.vel.w), sb = sin(v.vel.w);
		var r = r0 * cb - u0 * sb;
		var u = cross(r, f);
		var s = sin(v.pos.w);
		var beat = v.shape.w * v.mood.y;
		var banked = smoothstep(0.77, 1.15, abs(v.vel.w)) * smoothstep(0.08, 0.65, v.mood.z);
		var x = v.shape.x * (1 - 0.3 * beat * abs(s)) * (1 - 0.50 * banked);
		var y = v.shape.y + abs(v.shape.x) * (beat * 0.9 * s + v.shape.w * 0.12);
		var flip = vec3(1, p.view.size.z, 1);
		var at = v.pos.xyz * flip;
		var to = at - p.view.eye.xyz;
		var dist = length(to);
		var px = p.view.size.x * p.view.eye.w / max(dist, 0.01);
		var grow = max(1.0, p.view.size.y / px);
		var world = at + (r * x + u * y + f * v.shape.z) * flip * p.view.size.x * grow;
		var view = to / max(dist, 0.01);
		var sun = p.view.sun.xyz;
		// (dark feathers: the sun's low light on the wings' faces, the sky's from above, a glow through them against the sun)
		var c = vec3(0.012, 0.011, 0.012) + SUN * 0.006 * abs(dot(u, sun)) + vec3(0.02, 0.022, 0.04) * (0.5 + 0.5 * u.y);
		c += SUN * 0.006 * pow(max(dot(view, sun), 0.0), 24.0);
		var underside = smoothstep(-0.03, 0.28, dot(u * flip, view));
		var lit = smoothstep(0.0, 0.38, -dot(u, sun)) * (1 - smoothstep(0.38, 0.89, dot(view, sun)));
		c = mix(c, vec3(0.48, 0.39, 0.32), banked * underside * lit);
		c = mix(c, haze(view, sun), 1 - exp(-dist * FOG * 0.4));
		var alpha = p.view.size.w * (1 - 0.67 * banked) / (grow * grow);
		return {pos: position(p.view.viewProj * vec4(world, 1)), color: vec4(c * alpha, alpha)};
	},
	fragment: function(i:BirdVaryings):Vec4 return i.color
});
