package helder.scene.math;

import helder.gfx.shader.Vec3;

// A curve in space, an immutable value (three's Curve and its kinds): a
// cubic Bezier, a Catmull-Rom spline through points (open or closed), a
// straight line, or a path of curves end to end. It is read by a parameter
// t from 0 to 1 (point, tangent: a path's t runs by length across its
// curves), or by a distance along it (pointAt, tangentAt: its length
// tabulated once, when made, over 200 steps as three's arcLengthDivisions).
// frames(n) gives n + 1 frames along it by length that turn as little as
// they can (parallel transport, three's computeFrenetFrames): a tube's
// rings (Geometry.tube), a camera on rails.
//
//   var rail = Curve3.catmullRom([a, b, c, d], true);
//   var p = rail.pointAt(rail.length * 0.25);
class Curve3 {
	// (the arc length table's steps)
	static inline var DIVISIONS = 200;

	final kind:CurveKind;
	final points:Array<Vec3>;
	final closed:Bool;
	final tension:Float;
	final parts:Array<Curve3>;
	// (the length from the start at t = k / DIVISIONS)
	final lengths:Array<Float>;

	// the curve's length (scene units)
	public final length:Float;

	function new(kind:CurveKind, points:Array<Vec3>, closed = false, tension = 0.5, ?parts:Array<Curve3>) {
		this.kind = kind;
		this.points = points;
		this.closed = closed;
		this.tension = tension;
		this.parts = parts ?? [];
		lengths = [0.0];
		var last = point(0), sum = 0.0;
		for (k in 1...DIVISIONS + 1) {
			var p = point(k / DIVISIONS);
			sum += distance(p, last);
			lengths.push(sum);
			last = p;
		}
		length = sum;
	}

	// a cubic Bezier from a to d, its handles b and c (three's CubicBezierCurve3)
	public static function bezier(a:Vec3, b:Vec3, c:Vec3, d:Vec3):Curve3
		return new Curve3(Bezier, [a, b, c, d]);

	// a straight line from a to b (three's LineCurve3)
	public static function line(a:Vec3, b:Vec3):Curve3
		return new Curve3(Line, [a, b]);

	// a Catmull-Rom spline through points (two at least), back to the
	// first when closed; tension 0.5 the classic spline (three's
	// CatmullRomCurve3 of type "catmullrom")
	public static function catmullRom(points:Array<Vec3>, closed = false, tension = 0.5):Curve3 {
		if (points.length < 2) throw "helder.scene: Curve3.catmullRom: two points at least";
		return new Curve3(CatmullRom, points.copy(), closed, tension);
	}

	// curves end to end (three's CurvePath), t by length across them
	public static function path(curves:Array<Curve3>):Curve3 {
		if (curves.length == 0) throw "helder.scene: Curve3.path: a curve at least";
		return new Curve3(Path, [], false, 0.5, curves.copy());
	}

	// the point at t (0 to 1)
	public function point(t:Float):Vec3 {
		t = t < 0 ? 0 : t > 1 ? 1 : t;
		return switch kind {
			case Line: points[0] + (points[1] - points[0]) * t;
			case Bezier:
				var u = 1 - t;
				points[0] * (u * u * u) + points[1] * (3 * u * u * t) + points[2] * (3 * u * t * t) + points[3] * (t * t * t);
			case CatmullRom: spline(t);
			case Path:
				var d = t * total(), k = 0;
				while (k < parts.length - 1 && d > parts[k].length) {
					d -= parts[k].length;
					k++;
				}
				parts[k].pointAt(d);
		}
	}

	// the unit tangent at t (its derivative's direction)
	public function tangent(t:Float):Vec3 {
		var h = 0.0001;
		var a = t - h < 0 ? 0 : t - h, b = t + h > 1 ? 1 : t + h;
		var d = point(b) - point(a);
		var l = Math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z);
		return l > 0 ? d / l : new Vec3(0, 0, 1);
	}

	// the point at a distance along it from the start (0 to length)
	public function pointAt(distance:Float):Vec3
		return point(paramAt(distance));

	// the unit tangent at a distance along it
	public function tangentAt(distance:Float):Vec3
		return tangent(paramAt(distance));

	// the parameter t at a distance along it (the table searched, linear between its steps)
	public function paramAt(distance:Float):Float {
		if (distance <= 0) return 0;
		if (distance >= length) return 1;
		var lo = 0, hi = DIVISIONS;
		while (hi - lo > 1) {
			var mid = (lo + hi) >> 1;
			if (lengths[mid] < distance) lo = mid else hi = mid;
		}
		var span = lengths[hi] - lengths[lo];
		return (lo + (span > 0 ? (distance - lengths[lo]) / span : 0)) / DIVISIONS;
	}

	// n + 1 frames at equal lengths along it (n at least 1): each a unit
	// tangent, normal and binormal (tangent x normal), the normal carried
	// from one to the next by the turn between their tangents (no flips at
	// inflections, unlike Frenet's); closed, the twist between the last and
	// the first spread over them, so the ends meet
	public function frames(n:Int, closed = false):Frames {
		if (n < 1) n = 1;
		var tangents = [for (i in 0...n + 1) tangentAt(length * i / n)];
		var t0 = tangents[0];
		// (the first normal: at right angles to the tangent, about its smallest axis)
		var ax = Math.abs(t0.x), ay = Math.abs(t0.y), az = Math.abs(t0.z);
		var axis = ax <= ay && ax <= az ? new Vec3(1, 0, 0) : ay <= az ? new Vec3(0, 1, 0) : new Vec3(0, 0, 1);
		var v = unit(cross(t0, axis));
		var normals = [cross(t0, v)], binormals = [cross(t0, cross(t0, v))];
		for (i in 1...n + 1) {
			var a = tangents[i - 1], b = tangents[i], nr = normals[i - 1];
			var c = cross(a, b), l = Math.sqrt(dot(c, c));
			if (l > 1e-12) {
				var theta = Math.acos(clamp(dot(a, b)));
				nr = Quat.axisAngle(c / l, theta).rotate(nr);
			}
			normals.push(unit(nr));
			binormals.push(cross(b, normals[i]));
		}
		if (closed) {
			var theta = Math.acos(clamp(dot(normals[0], normals[n]))) / n;
			if (dot(tangents[0], cross(normals[0], normals[n])) > 0) theta = -theta;
			for (i in 1...n + 1) {
				normals[i] = unit(Quat.axisAngle(tangents[i], theta * i).rotate(normals[i]));
				binormals[i] = cross(tangents[i], normals[i]);
			}
		}
		return {tangents: tangents, normals: normals, binormals: binormals};
	}

	// (a path's: its curves' lengths summed)
	function total():Float {
		var s = 0.0;
		for (p in parts)
			s += p.length;
		return s;
	}

	// (three's CatmullRomCurve3, "catmullrom": a cubic between each two
	// points, its tangents tension times the next point less the last's;
	// the ends' outer points mirrored, a closed one's wrapped)
	function spline(t:Float):Vec3 {
		var l = points.length;
		var p = (l - (closed ? 0 : 1)) * t;
		var i = Math.floor(p), w = p - i;
		if (closed) i += i > 0 ? 0 : (Math.floor(Math.abs(i) / l) + 1) * l;
		else if (w == 0 && i == l - 1) {
			i = l - 2;
			w = 1;
		}
		var p0 = closed || i > 0 ? points[(i - 1 + l) % l] : points[0] - (points[1] - points[0]);
		var p1 = points[i % l], p2 = points[(i + 1) % l];
		var p3 = closed || i + 2 < l ? points[(i + 2) % l] : points[l - 1] - (points[l - 2] - points[l - 1]);
		var t0 = (p2 - p0) * tension, t1 = (p3 - p1) * tension;
		var w2 = w * w, w3 = w2 * w;
		return p1 * (2 * w3 - 3 * w2 + 1) + t0 * (w3 - 2 * w2 + w) + p2 * (-2 * w3 + 3 * w2) + t1 * (w3 - w2);
	}

	static inline function dot(a:Vec3, b:Vec3):Float
		return a.x * b.x + a.y * b.y + a.z * b.z;

	static inline function cross(a:Vec3, b:Vec3):Vec3
		return new Vec3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);

	static inline function unit(a:Vec3):Vec3 {
		var l = Math.sqrt(dot(a, a));
		return l > 0 ? a / l : a;
	}

	static inline function distance(a:Vec3, b:Vec3):Float {
		var d = a - b;
		return Math.sqrt(dot(d, d));
	}

	static inline function clamp(x:Float):Float
		return x < -1 ? -1 : x > 1 ? 1 : x;
}

// a curve's frames (Curve3.frames): as many tangents, normals and binormals
typedef Frames = {tangents:Array<Vec3>, normals:Array<Vec3>, binormals:Array<Vec3>};

enum abstract CurveKind(Int) {
	var Line;
	var Bezier;
	var CatmullRom;
	var Path;
}
