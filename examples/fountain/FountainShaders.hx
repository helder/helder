import helder.math.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// The fountain's stages: Spray, a compute stage moving each drop (falling,
// respawned at the nozzle when it lands or grows old), and DropShader,
// each drop a small quad, its colour by its age, from the drops' buffer as
// instances. Where the device has no compute (WebGL2), Spray.main runs on
// the CPU: the same function (Fountain).
@:structInit @:publicFields class Drop {
	// xyz: where it is (clip space), w: its age in seconds
	var pos:Vec4;
	var vel:Vec4;
}

@:structInit @:publicFields class SprayStep {
	var dt:Float;
	var time:Float;
	var count:Int;
	var aspect:Float;
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

final Spray = compute({
	size: [64],
	main: function(id:ComputeInput, p:{step:SprayStep, drops:RWStorage<Drop>}) {
		if (id.x >= p.step.count) return;
		var d = p.drops[id.x];
		var age = d.pos.w + p.step.dt;
		var vel = d.vel.xyz - vec3(0, GRAVITY * p.step.dt, 0);
		var pos = d.pos.xyz + vel * p.step.dt;
		if (pos.y < -1 || age > LIFE) {
			// (born again at the nozzle, sprayed up and out; its age spread so that they do not all land at once)
			var n:Float = id.x;
			var a = (hash(n, p.step.time) - 0.5) * 0.9, s = 1.5 + 0.5 * hash(n + 0.5, p.step.time);
			pos = vec3(0, -0.85, 0);
			vel = vec3(sin(a) * s / p.step.aspect, cos(a) * s, 0);
			age = hash(n + 0.25, p.step.time) * 0.3;
		}
		var next:Drop = {pos: vec4(pos, age), vel: vec4(vel, 0)};
		p.drops[id.x] = next;
	}
});

// a drop: a quad of 4x4 pixels at its place, white-blue when young, deep blue and fading when old
final DropShader = shader({
	vertex: function(v:DropVertex):DropVaryings {
		var t = clamp(v.drop.w / LIFE, 0, 1);
		var color = mix(vec4(0.8, 0.95, 1, 0.9), vec4(0.1, 0.3, 0.9, 0), t);
		return {pos: position(vec4(v.drop.xy + v.corner, 0, 1)), color: color};
	},
	fragment: function(i:DropVaryings):Vec4 return vec4(i.color.xyz * i.color.w, i.color.w)
});
