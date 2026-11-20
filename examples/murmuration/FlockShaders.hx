import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// The flock's compute stages (Flock.hx): Clear
// empties the grid, Insert copies every bird into its cell (a hashed grid,
// a few slots a cell: in a crowd the first few in, enough for a bird that
// heeds its nearest seven or so; copies, so that a cell's neighbours are
// read together, not from all over the flock), Steer moves each bird by
// the neighbours in the eight cells about it, the roost and the hawk; and
// Spread, which doubles the flock. Without compute (WebGL2) Insert and
// Steer run on the CPU over fewer birds.
@:structInit @:publicFields class Bird {
	var pos:Vec4; // w: the wings' phase
	var vel:Vec4; // w: the bank, radians
	var mood:Vec4; // alarm, flap, wave strength
}

// a bird as its cell keeps it: where (w: alarm), how fast
@:structInit @:publicFields class Mate {
	var pos:Vec4;
	var vel:Vec4;
}

@:structInit @:publicFields class FlockStep {
	var dt:Float;
	var time:Float;
	var count:Int;
	var cells:Int; // the grid's cells, a power of two
	var roost:Vec4; // w: its radius
	var heading:Vec4; // the roost's velocity: the way they lean to go; w: how flat the roost is
	var armA:Vec4; // the roost's two arms from its centre: a ball, a ribbon, a bent one
	var armB:Vec4;
	var hawk:Vec4; // w: how near it scares
	var hawkVel:Vec4;
	var wave:Vec4; // inward, scaled by the extent; w: front along that axis
}

final CELL = 3.0;
final SLOTS = 8;
final SEPARATION = 1.1;
final REACH = 3.0;
final CRUISE = 12.0;
final DENSITY = 0.45;

function cell(x:Int, y:Int, z:Int, cells:Int):Int
	return ((x * 73856093) ^ (y * 19349663) ^ (z * 83492791)) & (cells - 1);

function cellOf(q:Vec3, cells:Int):Int {
	var g = floor(q / CELL);
	return cell(Std.int(g.x), Std.int(g.y), Std.int(g.z), cells);
}

// the point of the segment from a to b nearest q
function nearest(q:Vec3, a:Vec3, b:Vec3):Vec3 {
	var ab = b - a;
	return a + ab * clamp(dot(q - a, ab) / max(dot(ab, ab), 0.0001), 0, 1);
}

// the bird's right, level (its bank comes after)
function rightOf(f:Vec3):Vec3 {
	var r = cross(f, vec3(0, 1, 0));
	return length(r) < 0.001 ? vec3(1, 0, 0) : normalize(r);
}

final Clear = compute({
	size: [64],
	main: function(id:ComputeInput, p:{step:FlockStep, counts:RWStorage<Int>}) {
		if (id.x >= p.step.cells) return;
		p.counts[id.x] = 0;
	}
});

final Insert = compute({
	size: [64],
	main: function(id:ComputeInput, p:{step:FlockStep, birds:Storage<Bird>, counts:RWStorage<Int>, mates:RWStorage<Mate>}) {
		if (id.x >= p.step.count) return;
		var b = p.birds[id.x];
		var c = cellOf(b.pos.xyz, p.step.cells);
		var k = atomicAdd(p.counts, c, 1);
		if (k < SLOTS) {
			var m:Mate = {pos: vec4(b.pos.xyz, b.mood.x), vel: vec4(b.vel.xyz, 0)};
			p.mates[c * SLOTS + k] = m;
		}
	}
});

// the first count birds copied after themselves, a little apart: the flock
// doubled where it is (Flock.grow)
final Spread = compute({
	size: [64],
	main: function(id:ComputeInput, p:{step:FlockStep, birds:RWStorage<Bird>}) {
		if (id.x >= p.step.count) return;
		var b = p.birds[id.x];
		var n:Float = id.x;
		var aside = (fract(vec3(n * 0.618034, n * 0.7548777, n * 0.5698403)) - vec3(0.5)) * 1.6;
		var copy:Bird = {pos: vec4(b.pos.xyz + aside, fract(b.pos.w / 6.2831853 + 0.37) * 6.2831853), vel: b.vel, mood: b.mood};
		p.birds[id.x + p.step.count] = copy;
	}
});

final Steer = compute({
	size: [64],
	main: function(id:ComputeInput, p:{step:FlockStep, birds:Storage<Bird>, counts:Storage<Int>, mates:Storage<Mate>, next:RWStorage<Bird>}) {
		if (id.x >= p.step.count) return;
		var b = p.birds[id.x];
		var q = b.pos.xyz, v = b.vel.xyz;
		var dt = p.step.dt;
		// (the 2x2x2 cells nearest: every neighbour within half a cell, most within one)
		var g = floor(q / CELL - vec3(0.5));
		var gx = Std.int(g.x), gy = Std.int(g.y), gz = Std.int(g.z);
		var sep = vec3(0), ali = vec3(0), coh = vec3(0);
		var n = 0.0, alarm = 0.0;
		// (a cell keeps a few of its birds, but counts them all: what it kept
		// stands for the rest in the push apart, and the crowd's lean says
		// which way it is thicker)
		var crowd = vec3(0);
		var total = 0.0;
		for (k in 0...8) {
			var c = cell(gx + (k & 1), gy + ((k >> 1) & 1), gz + (k >> 2), p.step.cells);
			var all = p.counts[c];
			var m = all;
			if (m > SLOTS) m = SLOTS;
			var many:Float = all, kept:Float = m;
			var sx:Float = (k & 1) * 2 - 1, sy:Float = ((k >> 1) & 1) * 2 - 1, sz:Float = (k >> 2) * 2 - 1;
			crowd += vec3(sx, sy, sz) * many;
			total += many;
			var weight = many / max(kept, 1.0);
			for (s in 0...m) {
				var o = p.mates[c * SLOTS + s];
				var d = o.pos.xyz - q;
				var d2 = dot(d, d);
				if (d2 < REACH * REACH && d2 > 0.000001) {
					if (d2 < SEPARATION * SEPARATION) sep -= d / d2 * weight;
					ali += o.vel.xyz;
					coh += d;
					alarm += o.pos.w;
					n += 1;
				}
			}
		}
		var speed = length(v);
		var f = v / max(speed, 0.001);
		// (towards the crowd where it is thin, away where it is thick: an even
		// density inside, a sharp edge outside)
		var pressure = clamp(total / (8 * CELL * CELL * CELL) / DENSITY - 1, -0.8, 2);
		var acc = sep * 3.0 - crowd / max(total, 1.0) * 14 * pressure;
		if (n > 0) {
			acc += (ali / n - v) * 3.0 + coh / n * 1.2;
			alarm /= n;
		}
		// (the roost: a soft, flattened tube about its two arms they keep to as it wanders)
		var c = p.step.roost.xyz, flat = vec3(1, p.step.heading.w, 1);
		var toA = nearest(q, c + p.step.armA.xyz, c) - q, toB = nearest(q, c, c + p.step.armB.xyz) - q;
		var fa = length(toA * flat), fb = length(toB * flat);
		var to = fa < fb ? toA : toB;
		var far = min(fa, fb);
		var r = p.step.roost.w;
		acc += to / max(far, 0.001) * 14 * smoothstep(0.5 * r, 1.4 * r, far);
		acc += (p.step.heading.xyz - v) * 0.35;
		// (a slow flow that differs across the flock: its parts drift apart, stretch and fold)
		var t = p.step.time;
		acc += vec3(sin(q.z * 0.031 + t * 0.21), 0.4 * sin(q.x * 0.027 - t * 0.17), cos(q.x * 0.029 + q.y * 0.02 - t * 0.19)) * 1.3;
		acc += vec3(0, max(22 - q.y, 0.0) * 1.2, 0);
		// (the hawk: those near it flee, most of all away from its line)
		var dh = q - p.step.hawk.xyz;
		var dist = length(dh);
		var hd = normalize(p.step.hawkVel.xyz + vec3(0, 0.0001, 0));
		var ahead = dot(dh, hd);
		var aside = dh - hd * ahead;
		var clearance = length(aside);
		var danger = length(vec2(clearance, ahead * (ahead > 0 ? 0.65 : 1.5)));
		var threat = clamp(1 - danger / max(p.step.hawk.w, 0.001), 0, 1);
		acc += (dh / max(dist, 0.1) * 0.3 + aside / max(clearance, 0.1)) * threat * 130;
		// (alarm runs through the flock from neighbour to neighbour, and they jink with it)
		var mood = b.mood.x;
		mood += (max(threat * 1.5, alarm * 0.985) - mood) * min(1, dt * 9);
		mood = max(0, mood - dt * 0.25);
		var right = rightOf(f);
		var lag = p.step.wave.w - dot(q - c, p.step.wave.xyz);
		var roll = smoothstep(0.0, 0.025, lag) * (1 - smoothstep(0.12, 0.25, lag));
		var turn = dot(p.step.wave.xyz, right) < 0 ? -1.0 : 1.0;
		acc += right * (turn * roll * 5.0);
		acc += right * sin(t * 5 + dot(q, vec3(0.07, 0.05, 0.06))) * mood * 16;
		acc += f * (CRUISE + mood * 7 - speed) * 1.5;
		var a = length(acc);
		var most = 40 + 40 * threat;
		if (a > most) acc *= most / a;
		v += acc * dt;
		speed = length(v);
		v *= clamp(speed, 7, 22) / max(speed, 0.001);
		// (banked into the turn: the lateral pull's angle against gravity)
		var bank = b.vel.w;
		var lean = clamp(atan2(dot(acc, right), 9.8), -1.2, 1.2);
		bank += (mix(lean, turn * 1.29, roll) - bank) * min(1, dt * (6 + roll * 20));
		// (harder up a climb, when slow or alarmed; a glide down)
		var flap = b.mood.y;
		var beat = clamp(0.45 + v.y * 0.12 + (CRUISE - speed) * 0.15 + mood, 0.1, 1);
		flap += (mix(beat, 0.18, roll) - flap) * min(1, dt * (3 + roll * 12));
		var phase = b.pos.w + dt * (11 + 4 * flap) * 6.2831853;
		if (phase > 6.2831853) phase -= 6.2831853;
		var moved:Bird = {pos: vec4(q + v * dt, phase), vel: vec4(v, bank), mood: vec4(mood, flap, roll, 0)};
		p.next[id.x] = moved;
	}
});
