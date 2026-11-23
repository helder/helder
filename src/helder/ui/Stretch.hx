package helder.ui;

// A touch's drag past a scroller's end stretching it, as Android 12's
// EdgeEffect does, ported as Flutter's StretchingOverscrollIndicator ports
// it (Ui.stretch: UiWindow's on Android): the push past the end over the
// view's length (d, at most 1) stretches it by 0.016 (d + 1 - e^(-d e /
// 0.33)), drawn as a scale along its axis anchored at that end; pulled back,
// the stretch gives first; let go, or a fling into the end (its speed
// absorbed), it springs back (natural frequency 24.657, damping 0.98, its
// time 0.8 of the spring's: Android's). TouchScroll's drag and glide go
// through it.
@:allow(helder.ui)
@:access(helder.ui.Ui)
class Stretch {
	static inline var INTENSITY = 0.016;
	static final SCALAR = Math.exp(1) / 0.33;
	static inline var FLING_FRICTION = 1 / 6000;
	static inline var ABSORB_FRICTION = 1 / 3000;
	static inline var MAX_FLING = 0.5;
	static inline var MAX_ABSORB = 1.25;
	static inline var FREQUENCY = 24.657;
	static inline var DAMPING = 0.98;
	static inline var TIME = 0.8;

	final ui:Ui;
	// the scroller stretched, on which axis, the push past its end (points, the scroll's way), its stretch
	var node:Null<Node> = null;
	var alongX = false;
	var pushed = 0.0;
	var amount = 0.0;
	// a spring back: from when, from where, at what speed
	var springAt = -1.0;
	var from = 0.0;
	var speed = 0.0;
	var springing = false;

	function new(ui:Ui)
		this.ui = ui;

	// how far n is stretched along axis x (signed: past its start negative)
	function of(n:Node, x:Bool):Float
		return n == node && x == alongX ? amount : 0;

	// a drag's move by dx, dy at x, y (the scroll's way): a stretch held
	// pulled back first, then the scroll, what it could not scroll pushing
	// past the end
	function drag(x:Float, y:Float, dx:Float, dy:Float) {
		springing = false;
		if (node != null && pushed != 0) {
			var d = alongX ? dx : dy;
			if (d * pushed < 0) {
				var left = pushed + d;
				if (left * pushed > 0) {
					set(left);
					if (alongX) dx = 0 else dy = 0;
				} else {
					set(0);
					if (alongX) dx = left else dy = left;
				}
			}
		}
		ui.wheelNow(x, y, dx, dy, false);
		var over = ui.overNode;
		if (over == null) return;
		var sideways = Math.abs(dx) > Math.abs(dy), e = sideways ? ui.overX : ui.overY;
		if (e == 0) return;
		if (node != over || alongX != sideways) {
			node = over;
			alongX = sideways;
			pushed = 0;
		}
		set(pushed + e);
	}

	// (the push past the end set, the stretch from it: Flutter's pull)
	function set(p:Float) {
		pushed = p;
		var n = node;
		if (n == null) return;
		var view = Scrolling.viewSize(n, alongX);
		var d = Math.min(1, Math.abs(p) / Math.max(1, view));
		var s = INTENSITY * d + INTENSITY * (1 - Math.exp(-d * SCALAR));
		amount = p < 0 ? -s : p > 0 ? s : 0;
		// (its scale drawn where the scroller is, in its parent's layer)
		n.layerChanged();
		ui.requestFrame();
	}

	// whether a drag holds a stretch (let go, it springs back: no fling)
	function held():Bool
		return node != null && pushed != 0;

	// let go at speed (points a second, the scroll's way, along the stretch's axis)
	function release(v:Float) {
		if (node == null) return;
		pushed = 0;
		spring(Math.max(-MAX_FLING, Math.min(MAX_FLING, v * FLING_FRICTION)));
	}

	// a glide's move: whether it goes on (into an end, its speed absorbed: no)
	function glide(x:Float, y:Float, dx:Float, dy:Float, vx:Float, vy:Float):Bool {
		ui.wheelNow(x, y, dx, dy, false);
		var over = ui.overNode, along = Math.abs(dx) > Math.abs(dy), e = along ? ui.overX : ui.overY;
		if (over == null || e == 0) return true;
		node = over;
		alongX = along;
		pushed = 0;
		var v = along ? vx : vy;
		spring(Math.max(-MAX_ABSORB, Math.min(MAX_ABSORB, v * ABSORB_FRICTION)));
		return false;
	}

	// the spring back from the stretch, at speed v (stretch a second)
	function spring(v:Float) {
		if (amount == 0 && v == 0) {
			node = null;
			return;
		}
		from = amount;
		speed = v * TIME;
		springAt = Ui.now();
		if (springing) return;
		springing = true;
		Clock.addTo(ui.context, t -> {
			if (!springing || node == null) return springing = false;
			var w0 = FREQUENCY * TIME, z = DAMPING, wd = w0 * Math.sqrt(1 - z * z), dt = Ui.now() - springAt;
			var a = Math.exp(-z * w0 * dt), s = a * (from * Math.cos(wd * dt) + (speed + z * w0 * from) / wd * Math.sin(wd * dt));
			node.layerChanged();
			ui.requestFrame();
			if (dt > 0.05 && Math.abs(s) < 1e-4) {
				amount = 0;
				node = null;
				return springing = false;
			}
			amount = s;
			return true;
		});
	}

	// (n leaving the tree)
	function reset() {
		springing = false;
		node = null;
		amount = pushed = 0;
	}
}
