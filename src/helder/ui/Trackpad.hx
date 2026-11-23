package helder.ui;

import helder.os.ScrollPhase;

// A trackpad's scrolling as macOS's own views do it (Ui.elastic): a
// gesture's scrolls go to one scroller, latched at its first move (the
// nearest around the pointer that can move that way, else the innermost
// that scrolls on that axis: its edge stretches) until its momentum ends;
// past an end it stretches, (1 - 1 / (x * c / d + 1)) * d for x pushed
// over a view d long (AppKit's hyperbolic curve, c its trackpad's 0.075:
// _NSHyperbolicElasticDeltaForReboundDelta and
// NSScrollingBehaviorHyperbolicCoefficientTrackpad, measured), on one axis
// at a time (the move's larger, one that scrolls) and only once 10 points
// past it (AppKit's, as WebKit and Chromium have them), and let go it
// springs back as AppKit's rubber band does: (s + v * t * 0.31) *
// e^(-20 t / 1.6) (Chromium's, which _NSElasticDeltaForTimeDelta matches). The momentum is the system's (its
// events' deltas), replayed at the frames' times, interpolated a frame
// behind (the system sends it at 60 a second, whatever the display's
// rate: applied as it comes it judders), from the gesture's last move on;
// one reaching an end bounces there
// (the rest of it dropped), as WebKit's and Chromium's.
@:allow(helder.ui)
@:access(helder.ui.Ui)
@:access(helder.ui.ScrollHost)
class Trackpad {
	static inline var C = 0.075;
	// (a push past an end under this: kept, no stretch yet)
	static inline var MIN_STRETCH = 10.0;
	static inline var AMPLITUDE = 0.31;
	static inline var STIFFNESS = 20.0;
	static inline var PERIOD = 1.6;

	final ui:ScrollHost;
	// the scroller the gesture is latched to (null: none yet, or none there)
	var node:Null<Node> = null;
	var latching = false;
	// what was pushed past each end, and the speed (points a second, the scroll's way) at the last move
	var forceX = 0.0;
	var forceY = 0.0;
	var pendX = 0.0;
	var pendY = 0.0;
	var vx = 0.0;
	var vy = 0.0;
	var lastAt = -1.0;
	// the momentum's samples (times, seconds on Ui.now's clock; the scroll added up), how much of it is applied
	final times:Array<Float> = [];
	final sumX:Array<Float> = [];
	final sumY:Array<Float> = [];
	var usedX = 0.0;
	var usedY = 0.0;
	var momentumEnded = false;
	var replaying = false;
	// a spring back: from when, its stretch and speed then
	var springAt = -1.0;
	var springX = 0.0;
	var springY = 0.0;
	var springVX = 0.0;
	var springVY = 0.0;
	var springing = false;
	// (which end each axis springs back to: its sign)
	var edgeX = 0.0;
	var edgeY = 0.0;
	var hitX = false;
	var hitY = false;

	function new(ui:ScrollHost)
		this.ui = ui;

	// a Scroll of a trackpad's at x, y (its deltas: the scroll's way) in its
	// phases, at time (Ui.now's clock): whether it was taken
	function scroll(x:Float, y:Float, dx:Float, dy:Float, phase:Int, momentum:Int, time:Float):Bool {
		// (fingers moving with no Began before: a gesture begins, as Wayland's touchpads give none)
		if (phase == ScrollPhase.Changed && !inGesture) scroll(x, y, 0, 0, ScrollPhase.Began, 0, time);
		if (phase == ScrollPhase.Began) {
			inGesture = true;
			history.resize(0);
			stopKinetic();
			stopMomentum();
			// (a spring back caught: its stretch pushed on from where it is)
			if (springing && node != null) {
				springing = false;
				forceX = unstretch(stretchX(node), viewSize(node, true));
				forceY = unstretch(stretchY(node), viewSize(node, false));
			}
			node = null;
			latching = true;
			pendX = pendY = 0;
			vx = vy = 0;
			lastAt = -1;
			return true;
		}
		if (phase == ScrollPhase.Changed) {
			if (latching && node == null && (dx != 0 || dy != 0)) node = latch(x, y, dx, dy);
			latching = false;
			if (node == null) return false;
			track(dx, dy, time);
			push(node, dx, dy);
			return true;
		}
		if (phase == ScrollPhase.Ended || phase == ScrollPhase.Cancelled) {
			inGesture = false;
			if (node != null && (stretchX(node) != 0 || stretchY(node) != 0)) springBack(time);
			// (no momentum of the system's: the glide ours, GTK's)
			else if (node != null && ui.kinetic && phase == ScrollPhase.Ended) kinetic(time);
			return node != null;
		}
		if (momentum == ScrollPhase.Began) {
			if (node == null || springing) return node != null;
			times.resize(0);
			sumX.resize(0);
			sumY.resize(0);
			usedX = usedY = 0;
			momentumEnded = false;
			// (from the gesture's last move: the replay goes on from the fingers, no frame standing still between)
			if (lastAt >= 0 && lastAt < time) sample(lastAt, 0, 0);
			sample(time, dx, dy);
			replay();
			return true;
		}
		if (momentum == ScrollPhase.Changed) {
			if (node == null || springing || !replaying) return node != null;
			sample(time, dx, dy);
			return true;
		}
		if (momentum == ScrollPhase.Ended || momentum == ScrollPhase.Cancelled) {
			momentumEnded = true;
			return node != null;
		}
		return false;
	}

	// the gesture's scroller: the nearest around x, y that can move by dx,
	// dy, else the innermost that scrolls on the gesture's axis
	function latch(x:Float, y:Float, dx:Float, dy:Float):Null<Node> {
		var n = ui.hit(x, y), first:Null<Node> = null, alongX = Math.abs(dx) > Math.abs(dy);
		while (n != null) {
			if (n.style.overflow == Scroll) {
				if (Scrolling.canScroll(n, dx, true) || Scrolling.canScroll(n, dy, false)) return n;
				if (first == null && (alongX ? n.style.overflowX == Scroll && Scrolling.maxScroll(n, true) > 0 : n.style.overflowY == Scroll
					&& Scrolling.maxScroll(n, false) > 0)) first = n;
			}
			n = n.parent;
		}
		return first;
	}

	// the speed (points a second) from the gesture's moves, smoothed; their
	// last 150 ms kept (GTK's kinetic glide's speed)
	function track(dx:Float, dy:Float, time:Float) {
		history.push(time);
		history.push(dx);
		history.push(dy);
		if (lastAt >= 0) {
			var dt = Math.max(0.001, time - lastAt);
			vx = 0.8 * (dx / dt) + 0.2 * vx;
			vy = 0.8 * (dy / dt) + 0.2 * vy;
		}
		lastAt = time;
	}

	// n scrolled by dx, dy: within its extent as far as it goes, the rest
	// pushing past its end (stretching); a stretch pulled back first
	function push(n:Node, dx:Float, dy:Float) {
		// (the move's larger axis may stretch, the other only scrolls; an axis with nothing to scroll neither)
		var alongY = Math.abs(dy) >= Math.abs(dx);
		if (Scrolling.maxScroll(n, true) <= 0) dx = 0;
		if (Scrolling.maxScroll(n, false) <= 0) dy = 0;
		var x = axis(n, true, dx, !alongY && ui.elastic), y = axis(n, false, dy, alongY && ui.elastic);
		Scrolling.moved(ui, n, x - Scrolling.scrollStart(n, true), y);
	}

	// one axis's new offset (absolute: scrollX's or scrollY's)
	function axis(n:Node, x:Bool, d:Float, stretches:Bool):Float {
		var lo = Scrolling.scrollStart(n, x), max = Scrolling.maxScroll(n, x), view = viewSize(n, x);
		var v = x ? n.scrollX : n.scrollY;
		if (d == 0 || (x ? n.style.overflowX : n.style.overflowY) != Scroll) return v;
		var f = x ? forceX : forceY;
		// (stretched: the push on the stretch first, the rest back into the extent)
		if (f != 0) {
			var nf = f + d;
			if (nf * f > 0) {
				setForce(x, nf);
				return (f < 0 ? lo : lo + max) + stretch(nf, view);
			}
			setForce(x, 0);
			d = nf;
			v = f < 0 ? lo : lo + max;
		}
		var t = v + d;
		if (t >= lo && t <= lo + max) {
			if (x) pendX = 0 else pendY = 0;
			return t;
		}
		var edge = t < lo ? lo : lo + max;
		if (!stretches) return edge;
		// (the push past the end added up: no stretch until it is 10 points)
		var over = t - edge + (x ? pendX : pendY);
		if (Math.abs(over) < MIN_STRETCH) {
			if (x) pendX = over else pendY = over;
			return edge;
		}
		if (x) pendX = 0 else pendY = 0;
		setForce(x, over);
		return edge + stretch(over, view);
	}

	inline function setForce(x:Bool, f:Float)
		if (x) forceX = f else forceY = f;

	// the stretch shown for force pushed past an end of a view that long (signed)
	static function stretch(force:Float, view:Float):Float {
		if (view <= 0) return 0;
		var a = Math.abs(force), s = (1 - 1 / (a * C / view + 1)) * view;
		return force < 0 ? -s : s;
	}

	// (its inverse: the force a stretch takes)
	static function unstretch(s:Float, view:Float):Float {
		if (view <= 0 || s == 0) return 0;
		var a = Math.min(Math.abs(s), view * 0.999), f = view / C * (1 / (1 - a / view) - 1);
		return s < 0 ? -f : f;
	}

	// how far n is past its ends now (signed: past its start negative)
	static function stretchX(n:Node):Float {
		var lo = Scrolling.scrollStart(n, true), hi = lo + Scrolling.maxScroll(n, true);
		return n.scrollX < lo ? n.scrollX - lo : n.scrollX > hi ? n.scrollX - hi : 0;
	}

	static function stretchY(n:Node):Float {
		var hi = Scrolling.maxScroll(n, false);
		return n.scrollY < 0 ? n.scrollY : n.scrollY > hi ? n.scrollY - hi : 0;
	}

	static inline function viewSize(n:Node, x:Bool):Float
		return Scrolling.viewSize(n, x);

	// ---- the momentum, replayed a frame behind

	function sample(time:Float, dx:Float, dy:Float) {
		var n = times.length;
		// (two at once: the second a hair later, so that the interpolation has a span)
		if (n > 0 && time <= times[n - 1]) time = times[n - 1] + 0.001;
		times.push(time);
		sumX.push((n > 0 ? sumX[n - 1] : 0) + dx);
		sumY.push((n > 0 ? sumY[n - 1] : 0) + dy);
		ui.requestFrame();
	}

	function replay() {
		if (replaying) return;
		replaying = true;
		ui.animate(t -> {
			if (!replaying || node == null) return replaying = false;
			var n = times.length, at = ui.clock() - 1 / 60;
			var tx:Float, ty:Float;
			if (n == 0 || at <= times[0]) {
				tx = ty = 0;
			} else if (at >= times[n - 1]) {
				tx = sumX[n - 1];
				ty = sumY[n - 1];
			} else {
				var i = 1;
				while (times[i] < at)
					i++;
				var k = (at - times[i - 1]) / (times[i] - times[i - 1]);
				tx = sumX[i - 1] + (sumX[i] - sumX[i - 1]) * k;
				ty = sumY[i - 1] + (sumY[i] - sumY[i - 1]) * k;
			}
			var dx = tx - usedX, dy = ty - usedY;
			usedX = tx;
			usedY = ty;
			if (dx != 0 || dy != 0) {
				var target = node;
				var wasX = stretchX(target), wasY = stretchY(target);
				push(target, dx, dy);
				// (an end reached: a bounce at the speed it came with, the rest of the momentum dropped)
				if ((wasX == 0 && stretchX(target) != 0) || (wasY == 0 && stretchY(target) != 0)) {
					var dt = n > 1 ? Math.max(0.001, times[n - 1] - times[n - 2]) : 1 / 60;
					vx = n > 1 ? (sumX[n - 1] - sumX[n - 2]) / dt : 0;
					vy = n > 1 ? (sumY[n - 1] - sumY[n - 2]) / dt : 0;
					replaying = false;
					springBack(ui.clock());
					return false;
				}
			}
			if (momentumEnded && at >= times[n - 1]) return replaying = false;
			return true;
		});
	}

	function stopMomentum() {
		replaying = false;
		times.resize(0);
		sumX.resize(0);
		sumY.resize(0);
	}

	// ---- the spring back

	function springBack(time:Float) {
		var n = node;
		if (n == null) return;
		// (held still a while before letting go: no speed, as Chromium zeroes it after 100 ms)
		if (!replaying && !fromGlide && lastAt >= 0 && time - lastAt > 0.1) vx = vy = 0;
		springAt = time;
		springX = stretchX(n);
		springY = stretchY(n);
		// (its speed only on the stretched axes, outwards or back as it was)
		// (a glide into an end: from that end, out at its speed, on the axes it hit)
		springVX = springX != 0 || fromGlide && hitX ? vx : 0;
		springVY = springY != 0 || fromGlide && hitY ? vy : 0;
		edgeX = springX != 0 ? springX : springVX;
		edgeY = springY != 0 ? springY : springVY;
		fromGlide = false;
		forceX = forceY = 0;
		if (springing) return;
		springing = true;
		ui.animate(t -> {
			var n = node;
			if (!springing || n == null) return springing = false;
			var dt = Math.max(0, ui.clock() - springAt), damp = Math.exp(-dt * STIFFNESS / PERIOD);
			var sx = (springX + springVX * dt * AMPLITUDE) * damp, sy = (springY + springVY * dt * AMPLITUDE) * damp;
			// (GTK's overshoot where it is not AppKit's: critically damped, OVERSHOOT its friction)
			if (!ui.elastic) {
				var h = OVERSHOOT / 2, g = Math.exp(-h * dt);
				sx = g * (springX + (springVX + h * springX) * dt);
				sy = g * (springY + (springVY + h * springY) * dt);
			}
			if (Math.abs(sx) < 0.5) sx = 0;
			if (Math.abs(sy) < 0.5) sy = 0;
			var lo = Scrolling.scrollStart(n, true), maxX = Scrolling.maxScroll(n, true), maxY = Scrolling.maxScroll(n, false);
			var x = edgeX < 0 ? lo + sx : edgeX > 0 ? lo + maxX + sx : n.scrollX;
			var y = edgeY < 0 ? sy : edgeY > 0 ? maxY + sy : n.scrollY;
			Scrolling.moved(ui, n, x - lo, y);
			if (sx == 0 && sy == 0 && dt > 0) return springing = false;
			return true;
		});
	}

	// (whether n is stretched or springing back by it: not clamped by a layout meanwhile)
	function holds(n:Node):Bool
		return n == node && (springing || forceX != 0 || forceY != 0);

	// ---- the kinetic glide, ours where the system has no momentum (Linux:
	// GTK's, gtkkineticscrolling.c: the speed of the last 150 ms of moves,
	// x(t) = v / 4 (1 - e^(-4 t)), over under 1 point a second; an end
	// reached bouncing past it, GTK's overshoot)

	var inGesture = false;
	// (a spring back from a glide into an end: its speed the glide's)
	var fromGlide = false;
	final history:Array<Float> = [];
	var kineticAt = -1.0;
	var kineticVX = 0.0;
	var kineticVY = 0.0;
	var kineticDoneX = 0.0;
	var kineticDoneY = 0.0;
	var gliding = false;

	static inline var DECELERATION = 4.0;
	static inline var OVERSHOOT = 20.0;

	function kinetic(time:Float) {
		var sx = 0.0, sy = 0.0, first = time;
		var i = 0;
		while (i < history.length) {
			if (time - history[i] <= 0.15) {
				first = Math.min(first, history[i]);
				sx += history[i + 1];
				sy += history[i + 2];
			}
			i += 3;
		}
		var span = Math.max(1 / 60, time - first);
		kineticVX = sx / span;
		kineticVY = sy / span;
		if (Math.sqrt(kineticVX * kineticVX + kineticVY * kineticVY) < 1) return;
		kineticAt = time;
		kineticDoneX = kineticDoneY = 0;
		if (gliding) return;
		gliding = true;
		ui.animate(t -> {
			var n = node;
			if (!gliding || n == null) return gliding = false;
			var dt = Math.max(0, ui.clock() - kineticAt), e = Math.exp(-DECELERATION * dt);
			var ox = kineticVX / DECELERATION * (1 - e), oy = kineticVY / DECELERATION * (1 - e);
			var dx = ox - kineticDoneX, dy = oy - kineticDoneY;
			kineticDoneX = ox;
			kineticDoneY = oy;
			var bx = n.scrollX, by = n.scrollY;
			push(n, dx, dy);
			// (an end reached: GTK's overshoot, past it at the speed it came with and back)
			hitX = Math.abs(n.scrollX - bx - dx) > 0.5;
			hitY = Math.abs(n.scrollY - by - dy) > 0.5;
			if (hitX || hitY) {
				vx = kineticVX * e;
				vy = kineticVY * e;
				fromGlide = true;
				gliding = false;
				springBack(ui.clock());
				return false;
			}
			if (Math.abs(kineticVX * e) < 1 && Math.abs(kineticVY * e) < 1) return gliding = false;
			return true;
		});
	}

	function stopKinetic()
		gliding = false;

	// (a node leaving the tree, the platform's own scrolling taking over: let go)
	function reset() {
		stopKinetic();
		stopMomentum();
		springing = false;
		node = null;
		forceX = forceY = 0;
	}
}
