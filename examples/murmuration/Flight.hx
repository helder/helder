import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;

// What moves by the clock alone: the roost the flock keeps to (wandering,
// its size and its wheeling changing), the hawk's passes through it, and
// the camera's flight about the flock: wide views and close ones, now and
// then through it. A drag turns the camera from its path, which it
// drifts back to when let go.
class Flight {
	static inline var PASS = 13.0;
	static inline var DIVE = 70.0;
	// the sun's bearing
	public static inline var SUN = -0.35;

	public var roost = new Vec3(0, 75, 0);
	public var radius = 40.0;
	public var flat = 1.0;
	public var armA = new Vec3(0, 0, 0);
	public var armB = new Vec3(0, 0, 0);
	public var heading = new Vec3(10, 0, 0);
	public var hawk = new Vec3(0, -1000, 0);
	public var hawkVel = new Vec3(1, 0, 0);
	public var reach = 0.0;
	public var eye = new Vec3(0, 60, 200);
	public var target = new Vec3(0, 75, 0);
	// (the drag's turn and the scroll's zoom, and how long since)
	public var yaw = 0.0;
	public var pitch = 0.0;
	public var zoom = 1.0;
	public var idle = 99.0;
	// (the flock's size against the whole one's: its roost and the camera's distances by it)
	public var scale = 1.0;
	var centre:Null<Vec3> = null;

	public function new() {}

	public function update(t:Float, dt:Float) {
		roost = at(t);
		heading = (at(t + 0.5) - at(t - 0.5));
		// (the roost's arms, back and ahead along its way: their lengths and
		// bends change, so the flock it holds is a ball, a long ribbon, a hook)
		radius = (28 + 6 * Math.sin(0.031 * t)) * scale;
		flat = 1.4 + 0.5 * Math.sin(0.053 * t + 2);
		var way = Math.atan2(heading.z, heading.x), tilt = 0.35 * Math.sin(0.019 * t);
		armA = arm(way + Math.PI + 0.9 * Math.sin(0.023 * t + 1), -tilt, (15 + 100 * (0.5 + 0.5 * Math.sin(0.041 * t))) * scale);
		armB = arm(way + 0.9 * Math.sin(0.029 * t + 4), tilt, (15 + 110 * (0.5 + 0.5 * Math.sin(0.033 * t + 2))) * scale);
		// (a pass every PASS seconds, each from another side, stooping through the roost)
		var k = Math.floor(t / PASS), u = t / PASS - k;
		var turn = k * 2.399 + 0.6, dive = 0.18 + 0.12 * Math.sin(k * 1.7);
		var dir = new Vec3(Math.cos(turn) * Math.cos(dive), -Math.sin(dive), Math.sin(turn) * Math.cos(dive));
		var off = 8 * Math.sin(k * 3.1);
		var side = new Vec3(-dir.z, 0, dir.x);
		hawk = roost + (armA + armB) * 0.25 + dir * ((u - 0.5) * 400) + side * off + new Vec3(0, 6 * Math.sin(k * 2.3), 0);
		hawkVel = dir * (400 / PASS);
		reach = k < 1 ? 0 : 32 * (1 - smooth(0.25, 0.45, Math.abs(u - 0.5)));
		// (the camera about where the flock is: the roost, slowly followed)
		var c = centre == null ? roost : centre + (roost - centre) * Math.min(1, dt / 1.5);
		centre = c;
		// (mostly looking west, the flock against the afterglow; now and then round to the east)
		var around = SUN + Math.PI + 1.25 * Math.sin(0.031 * t + 0.3) + 0.5 * Math.sin(0.013 * t) + yaw;
		// (and every DIVE seconds a pass through the flock)
		var dive = (t + 25) % DIVE - DIVE / 2;
		var dist = Math.max(8, (210 + 60 * Math.sin(0.047 * t + 1.6) + 40 * Math.sin(0.019 * t + 0.4) - 290 * Math.exp(-dive * dive / 30)) * Math.max(0.45, scale));
		// (low over the water, rising to the flock's height when close)
		var low = 4 + 10 * (0.5 + 0.5 * Math.sin(0.033 * t + 0.5));
		var rise = c.y + (low - c.y) * smooth(30, 110, dist) - c.y;
		var up = Math.max(-0.6, Math.min(1.3, Math.atan2(rise, dist) + pitch));
		var r = Math.sqrt(dist * dist + rise * rise) * zoom;
		eye = c + new Vec3(Math.cos(around) * Math.cos(up), Math.sin(up), Math.sin(around) * Math.cos(up)) * r;
		if (eye.y < 3) eye = new Vec3(eye.x, 3, eye.z);
		target = c;
		if (idle > 3) {
			var back = Math.min(1, dt * 0.4);
			yaw -= yaw * back;
			pitch -= pitch * back;
			zoom += (1 - zoom) * back;
		}
		idle += dt;
	}

	// a drag of dx, dy points, a scroll of dz
	public function turnBy(dx:Float, dy:Float) {
		yaw += dx * 0.005;
		pitch += dy * 0.004;
		idle = 0;
	}

	public function zoomBy(dz:Float) {
		zoom = Math.max(0.15, Math.min(3, zoom * Math.pow(1.0015, dz)));
		idle = 0;
	}

	static function arm(bearing:Float, pitch:Float, length:Float):Vec3
		return new Vec3(Math.cos(bearing) * Math.cos(pitch), Math.sin(pitch), Math.sin(bearing) * Math.cos(pitch)) * length;

	// the roost's wandering: about as fast as the birds, turning this way and that
	static function at(t:Float):Vec3
		return new Vec3(500 * Math.sin(0.014 * t) + 150 * Math.sin(0.043 * t + 1), 58 + 12 * Math.sin(0.043 * t),
			400 * Math.sin(0.017 * t + 2) + 120 * Math.cos(0.051 * t));

	static inline function smooth(a:Float, b:Float, x:Float):Float {
		var t = Math.max(0, Math.min(1, (x - a) / (b - a)));
		return t * t * (3 - 2 * t);
	}
}
