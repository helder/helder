import helder.math.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// The fountain's drops (an Items<Drop>: moved by Fountain's each, falling,
// respawned at the nozzle when they land or grow old) and DropShader, each
// drop a small quad, its colour by its age, from the drops' buffer as
// instances.
@:structInit @:publicFields class Drop {
	// xyz: where it is (clip space), w: its age in seconds
	var pos:Vec4;
	var vel:Vec4;
}

@:structInit @:publicFields class DropVertex {
	var corner:Vec2;
	var drop:Vec4;
}

@:structInit @:publicFields class DropVaryings {
	var pos:Vec4;
	var color:Vec4;
}

final GRAVITY = 1.8;
final LIFE = 2.5;

// a number in 0..1 of n and the time, the same on every invocation that asks
function hash(n:Float, t:Float):Float
	return fract(sin(n * 12.9898 + t * 78.233) * 43758.5453);

// a drop: a quad of 4x4 pixels at its place, white-blue when young, deep blue and fading when old
final DropShader = shader({
	vertex: function(v:DropVertex):DropVaryings {
		var t = clamp(v.drop.w / LIFE, 0, 1);
		var color = mix(vec4(0.8, 0.95, 1, 0.9), vec4(0.1, 0.3, 0.9, 0), t);
		return {pos: position(vec4(v.drop.xy + v.corner, 0, 1)), color: color};
	},
	fragment: function(i:DropVaryings):Vec4 return vec4(i.color.xyz * i.color.w, i.color.w)
});
