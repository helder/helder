package helder.ui;

// A scroll glided to rather than jumped to: a mouse wheel's notches where
// the platform glides them (Event.eased: macOS, a browser's page) and the
// keys' scrolls, as a scroller's (Scrolling) and a node that scrolls itself
// (DataGrid, CodeView). As Chromium's (ScrollOffsetAnimationCurve): a glide
// takes 12 frames (at 60 a second) for 120 points or less, down to 6 for
// 480 or more; a notch while gliding goes on from its speed to the new end
// (the curve starting at that speed, easing to rest), its time running on
// from the last frame's, so that a wheel turned on (a notch every frame)
// flows; from rest it eases in and out. It runs on the node's screen's
// clock and starts at its first tick (Clock.now is the last tick's, long
// ago when the window was idle).
//
//   var glide = new ScrollGlide(node, (x, y) -> scrollTo(x, y));
//   onWheel = e -> if (e.eased) glide.to(left, top, glide.heading(left, top, e.deltaX, e.deltaY, maxLeft, maxTop));
class ScrollGlide {
	public var gliding(default, null) = false;
	// where it is heading
	public var toX(default, null) = 0.0;
	public var toY(default, null) = 0.0;
	// a glide's own length (seconds; 0: by its distance, Chromium's)
	public var fixed = 0.0;

	final node:Node;
	final set:(x:Float, y:Float) -> Void;
	var fromX = 0.0;
	var fromY = 0.0;
	// (its start, its length, its curve's slope at the start; the last tick's time)
	var at = -1.0;
	var length = 0.2;
	var slope = 0.0;
	var lastTick = -1.0;

	public function new(node:Node, set:(x:Float, y:Float) -> Void) {
		this.node = node;
		this.set = set;
	}

	// a glide's length for a distance (points): Chromium's 12 frames for 120 or less, 6 for 480 or more
	public static function duration(distance:Float):Float {
		var frames = 12 + (Math.abs(distance) - 120) * (6 - 12) / (480 - 120);
		return Math.max(6, Math.min(12, frames)) / 60;
	}

	// the curve, 0 to 1 over k (0 to 1), starting at slope s (s = 0: from rest), ending at rest
	public static inline function ease(k:Float, s:Float):Float
		return s * k * (1 - k) * (1 - k) + k * k * (3 - 2 * k);

	// (its slope at k)
	static inline function rate(k:Float, s:Float):Float
		return s * (1 - k) * (1 - 3 * k) + 6 * k * (1 - k);

	// a notch's end: dx, dy on from where it is (x, y) or where it heads, within 0 to max
	public function heading(x:Float, y:Float, dx:Float, dy:Float, maxX:Float, maxY:Float):{x:Float, y:Float} {
		var tx = (gliding ? toX : x) + dx, ty = (gliding ? toY : y) + dy;
		return {x: tx < 0 ? 0 : tx > maxX ? maxX : tx, y: ty < 0 ? 0 : ty > maxY ? maxY : ty};
	}

	// glides from x, y to an end: whether it moves
	public function to(x:Float, y:Float, end:{x:Float, y:Float}):Bool {
		if (!gliding && end.x == x && end.y == y) return false;
		// (its speed now, points a second, carried into the new curve)
		var vx = 0.0, vy = 0.0;
		if (gliding && at >= 0 && lastTick >= 0) {
			var k = Math.min(1, Math.max(0, (lastTick - at) / length)), r = rate(k, slope) / length;
			vx = (toX - fromX) * r;
			vy = (toY - fromY) * r;
		}
		var dx = end.x - x, dy = end.y - y, d2 = dx * dx + dy * dy;
		length = fixed > 0 ? fixed : duration(Math.max(Math.abs(dx), Math.abs(dy)));
		slope = d2 > 0 ? Math.max(0, Math.min(3, (vx * dx + vy * dy) / d2 * length)) : 0;
		fromX = x;
		fromY = y;
		toX = end.x;
		toY = end.y;
		// (gliding: on from the last frame's time, else from the first tick)
		at = gliding ? lastTick : -1;
		if (!gliding) {
			gliding = true;
			Clock.addFor(node, step);
		}
		if (node.ui != null) node.ui.requestFrame();
		return true;
	}

	// stopped where it is (a press, a key, a scroll of another kind)
	public function stop()
		gliding = false;

	function step(t:Float):Bool {
		if (!gliding) return false;
		if (at < 0) at = t;
		lastTick = t;
		var k = Math.min(1, Math.max(0, (t - at) / length)), e = ease(k, slope);
		set(fromX + (toX - fromX) * e, fromY + (toY - fromY) * e);
		if (k < 1) return true;
		gliding = false;
		return false;
	}
}
