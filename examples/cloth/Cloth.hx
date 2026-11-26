import helder.gfx.Buffer;
import helder.gfx.Device;
import helder.gfx.shader.ShaderMath.*;
import helder.math.Vec4;
import helder.parallel.Items;
import helder.parallel.On;
import helder.parallel.Parallel;

// A point of the cloth: pos.xyz its place, pos.w its inverse mass (0:
// pinned), prev.xyz its place a step before (Verlet: the velocity is the
// difference)
@:structInit @:publicFields class ClothPoint {
	var pos:Vec4;
	var prev:Vec4;
}

// a step's motion: gravity and wind, damped, for the points not pinned
final Integrate = kernel(function(i:Int, p:{points:Items<ClothPoint>, gravity:Float, wind:Vec4, dt:Float, damping:Float}) {
	var q = p.points[i];
	if (q.pos.w == 0) return;
	var x = q.pos.xyz;
	var next = x + (x - q.prev.xyz) * p.damping + (vec3(0, -p.gravity, 0) + p.wind.xyz) * (p.dt * p.dt);
	p.points[i] = {pos: vec4(next, q.pos.w), prev: vec4(x, 0)};
});

// one Jacobi iteration: each point moved by the mean of its corrections
// against its 8 neighbours (the grid's edges and diagonals), from the
// places before (from) into to, so that the points are independent
final Solve = kernel(function(i:Int, p:{from:Items<ClothPoint>, to:Items<ClothPoint>, width:Int, height:Int, rest:Float, omega:Float}) {
	var q = p.from[i];
	var x = q.pos.xyz, w = q.pos.w;
	var col = i % p.width, row = Std.int(i / p.width);
	var d = vec3(0);
	var n = 0.0;
	for (k in 0...8) {
		var dx = k == 0 ? -1 : k == 1 ? 1 : k < 4 ? 0 : k % 2 == 0 ? -1 : 1;
		var dy = k < 2 ? 0 : k == 2 ? -1 : k == 3 ? 1 : k < 6 ? -1 : 1;
		var c = col + dx, r = row + dy;
		if (c >= 0 && c < p.width && r >= 0 && r < p.height) {
			var o = p.from[r * p.width + c];
			var sum = w + o.pos.w;
			var e = x - o.pos.xyz;
			var l = length(e);
			if (sum > 0 && l > 1e-6) {
				var rest = k < 4 ? p.rest : p.rest * 1.41421356;
				d -= e * ((l - rest) / l * w / sum);
				n += 1;
			}
		}
	}
	var moved = n > 0 ? x + d * (p.omega / n) : x;
	p.to[i] = {pos: vec4(moved, w), prev: q.prev};
});

// A sheet of width x height points, spacing apart, hanging from pinned
// points: stepped at a fixed timestep (advance), each step Integrate then
// iterations of Solve, ping-ponged between two Items (an even count: the
// points end where they began, the Items drawn). Where it runs: on, or
// Auto (the GPU once drawn: buffer(device))
class Cloth {
	public static inline var DT = 1 / 120;

	public final width:Int;
	public final height:Int;
	public final spacing:Float;
	public final points:Items<ClothPoint>;
	public var iterations = 16;
	public var gravity = 9.8;
	public var wind = vec4(0);
	public var damping = 0.995;
	public var omega = 1.5;
	public var on = On.Auto;

	final spare:Items<ClothPoint>;
	var left = 0.0;

	// a sheet level at y, its corners pinned (and every pins-th point of its first row)
	public function new(width:Int, height:Int, spacing:Float, y = 0.0, pins = 0) {
		if (width < 2 || height < 2) throw "Cloth: 2 by 2 points at least";
		this.width = width;
		this.height = height;
		this.spacing = spacing;
		points = new Items<ClothPoint>(width * height);
		spare = new Items<ClothPoint>(width * height);
		var x0 = -(width - 1) * spacing / 2;
		for (r in 0...height)
			for (c in 0...width) {
				var at = vec4(x0 + c * spacing, y, r * spacing - (height - 1) * spacing / 2, 1);
				var pinned = r == 0 && (c == 0 || c == width - 1 || (pins > 0 && c % pins == 0));
				points[r * width + c] = {pos: vec4(at.xyz, pinned ? 0 : 1), prev: vec4(at.xyz, 0)};
			}
	}

	// the points' GPU buffer, drawn from (both Items there: the steps from now on the GPU's)
	public function buffer(device:Device):Buffer {
		spare.buffer(device);
		return points.buffer(device);
	}

	// one step of DT
	public function step() {
		Integrate.run(points.length, {points: points, gravity: gravity, wind: wind, dt: DT, damping: damping}, on);
		for (_ in 0...(iterations + 1) >> 1) {
			Solve.run(points.length, {from: points, to: spare, width: width, height: height, rest: spacing, omega: omega}, on);
			Solve.run(points.length, {from: spare, to: points, width: width, height: height, rest: spacing, omega: omega}, on);
		}
	}

	// the steps of DT in seconds (and those left over before), 8 at most
	public function advance(seconds:Float) {
		left = Math.min(left + seconds, 8 * DT);
		while (left >= DT) {
			step();
			left -= DT;
		}
	}

	public function dispose() {
		points.dispose();
		spare.dispose();
	}
}
