package helder.os;

// A drag's glide as Android's views fling (helder.ui's TouchScroll on
// Android, UiWindow's native scrolling), its physics ported as Chromium
// (ui/events/mobile_scroller.cc, Android's OverScroller) and Flutter
// (ClampingScrollSimulation) port them rather than calling into Java: the
// drag's speed a least-squares fit of its last moves (a quadratic over the
// last 100 ms, none once it stood still 40 ms: Chromium's VelocityTracker,
// LSQ2, as Android's), a fling past 50 points a second (capped at 8000:
// ViewConfiguration's) gliding along OverScroller's spline (friction
// 0.015, its deceleration ln 0.78 / ln 0.9, inflexion 0.35, Earth's gravity
// at 160 points an inch times 0.84) for the time and distance it gives.
// Units the caller's points, times ms.
class AndroidFling extends Glide {
	static inline var FRICTION = 0.015;
	static inline var DECELERATION = 2.3582018;
	static inline var INFLEXION = 0.35;
	static inline var MIN_FLING = 50.0;
	static inline var MAX_FLING = 8000.0;
	static inline var HORIZON = 100.0;
	static inline var STOPPED = 40.0;
	static inline var HISTORY = 20;
	static inline var SAMPLES = 100;

	// (OverScroller's spline: distance a fraction of the way through its time)
	static var spline:Null<Array<Float>> = null;
	// (g, inches a meter, points an inch, its tuning)
	static final COEFF = 9.80665 * 39.37 * 160 * 0.84;

	// the drag's moves: times and positions (the scroll's way)
	final times:Array<Float> = [];
	final xs:Array<Float> = [];
	final ys:Array<Float> = [];
	var px = 0.0;
	var py = 0.0;
	// a fling: its start, length (ms), distance on each axis, what of it was applied
	var flingAt = -1.0;
	var flingMs = 0.0;
	var distX = 0.0;
	var distY = 0.0;
	var doneX = 0.0;
	var doneY = 0.0;
	var flinging = false;
	// (its speed now, points a second: a fling's into an end)
	public var speedX(default, null) = 0.0;
	public var speedY(default, null) = 0.0;

	public function new() {
		super();
		if (spline == null) spline = makeSpline();
	}

	override function get_gliding():Bool
		return flinging;

	override public function start(time:Float) {
		stop();
		times.resize(0);
		xs.resize(0);
		ys.resize(0);
		px = py = 0;
		add(time);
	}

	override public function move(dx:Float, dy:Float, time:Float) {
		px += dx;
		py += dy;
		add(time);
	}

	function add(time:Float) {
		times.push(time);
		xs.push(px);
		ys.push(py);
		if (times.length > HISTORY) {
			times.shift();
			xs.shift();
			ys.shift();
		}
	}

	// the drag's speed now (points a second): the slope at its last move of a
	// quadratic fit to the moves within the horizon (a line under three), 0
	// once it stood still
	public function velocity(time:Float):{x:Float, y:Float} {
		var n = times.length;
		if (n < 2 || time - times[n - 1] > STOPPED) return {x: 0, y: 0};
		var t0 = times[n - 1], from = n - 1;
		while (from > 0 && t0 - times[from - 1] <= HORIZON)
			from--;
		return {x: fit(xs, from, n, t0), y: fit(ys, from, n, t0)};
	}

	// (the least squares fit's slope at t0, a second's worth)
	function fit(v:Array<Float>, from:Int, n:Int, t0:Float):Float {
		var m = n - from;
		if (m < 2) return 0;
		var s0 = 0.0, s1 = 0.0, s2 = 0.0, s3 = 0.0, s4 = 0.0, b0 = 0.0, b1 = 0.0, b2 = 0.0;
		for (i in from...n) {
			var t = (times[i] - t0) / 1000, y = v[i];
			s0 += 1;
			s1 += t;
			s2 += t * t;
			s3 += t * t * t;
			s4 += t * t * t * t;
			b0 += y;
			b1 += t * y;
			b2 += t * t * y;
		}
		if (m < 3) {
			var d = s0 * s2 - s1 * s1;
			return Math.abs(d) < 1e-12 ? 0 : (s0 * b1 - s1 * b0) / d;
		}
		// (y = a + b t + c t^2 by Cramer's rule: b, the slope at t = 0)
		var det = s0 * (s2 * s4 - s3 * s3) - s1 * (s1 * s4 - s3 * s2) + s2 * (s1 * s3 - s2 * s2);
		if (Math.abs(det) < 1e-12) {
			var d = s0 * s2 - s1 * s1;
			return Math.abs(d) < 1e-12 ? 0 : (s0 * b1 - s1 * b0) / d;
		}
		return (s0 * (b1 * s4 - s3 * b2) - b0 * (s1 * s4 - s3 * s2) + s2 * (s1 * b2 - b1 * s2)) / det;
	}

	override public function release(time:Float):Bool {
		var v = velocity(time);
		var speed = Math.sqrt(v.x * v.x + v.y * v.y);
		if (speed < MIN_FLING) return false;
		if (speed > MAX_FLING) {
			v.x *= MAX_FLING / speed;
			v.y *= MAX_FLING / speed;
			speed = MAX_FLING;
		}
		var l = Math.log(INFLEXION * speed / (FRICTION * COEFF));
		flingMs = Math.exp(l / (DECELERATION - 1)) * 1000;
		var distance = FRICTION * COEFF * Math.exp(DECELERATION / (DECELERATION - 1) * l);
		distX = distance * v.x / speed;
		distY = distance * v.y / speed;
		doneX = doneY = 0;
		flingAt = -1;
		flinging = true;
		return true;
	}

	override public function step(now:Float):Bool {
		if (!flinging) return false;
		if (flingAt < 0) flingAt = now - Glide.FRAME;
		var k = Math.min(1, (now - flingAt) / flingMs), i = Math.floor(k * SAMPLES), d:Float, rate:Float;
		if (i >= SAMPLES) {
			d = 1;
			rate = 0;
		} else {
			rate = (spline[i + 1] - spline[i]) * SAMPLES;
			d = spline[i] + (k - i / SAMPLES) * rate;
		}
		var sx = distX * d - doneX, sy = distY * d - doneY;
		doneX += sx;
		doneY += sy;
		speedX = distX * rate / (flingMs / 1000);
		speedY = distY * rate / (flingMs / 1000);
		if (k >= 1) flinging = false;
		if (sx == 0 && sy == 0) return false;
		dx = sx;
		dy = sy;
		return true;
	}

	override public function stop() {
		super.stop();
		flinging = false;
		speedX = speedY = 0;
	}

	// OverScroller's spline (its tensions 0.5 and 1, inflexion 0.35), sampled
	static function makeSpline():Array<Float> {
		var p1 = 0.5 * INFLEXION, p2 = 1 - (1 - INFLEXION), out = [];
		var xMin = 0.0;
		for (i in 0...SAMPLES) {
			var alpha = i / SAMPLES, xMax = 1.0, x = 0.0, coef = 0.0;
			while (true) {
				x = xMin + (xMax - xMin) / 2;
				coef = 3 * x * (1 - x);
				var tx = coef * ((1 - x) * p1 + x * p2) + x * x * x;
				if (Math.abs(tx - alpha) < 1e-5) break;
				if (tx > alpha) xMax = x else xMin = x;
			}
			out.push(coef * ((1 - x) * 0.5 + x) + x * x * x);
		}
		out.push(1);
		return out;
	}
}
