package helder.ui.draw;

// What changed on screen in a frame (Ui.paint's: a window's Renderer draws
// only that into the frame it keeps, Renderer.keep), or in a layer as it
// is recorded again: a few rectangles (x0, y0, x1, y1 each), merged where
// they meet, the two that grow least merged past MAX; or all of it
class Damage {
	public static inline var MAX = 8;

	public var all(default, null) = false;
	public var count(default, null) = 0;

	final rects:Array<Float> = [];

	public function new() {}

	public function clear() {
		all = false;
		count = 0;
	}

	public function everything()
		all = true;

	public inline function x0(i:Int):Float
		return rects[4 * i];

	public inline function y0(i:Int):Float
		return rects[4 * i + 1];

	public inline function x1(i:Int):Float
		return rects[4 * i + 2];

	public inline function y1(i:Int):Float
		return rects[4 * i + 3];

	public function add(x0:Float, y0:Float, x1:Float, y1:Float) {
		// (empty, or NaN: nothing)
		if (all || !(x1 > x0 && y1 > y0)) return;
		var i = 0;
		while (i < count) {
			var r = rects, k = 4 * i;
			if (x0 <= r[k + 2] && x1 >= r[k] && y0 <= r[k + 3] && y1 >= r[k + 1]) {
				x0 = Math.min(x0, r[k]);
				y0 = Math.min(y0, r[k + 1]);
				x1 = Math.max(x1, r[k + 2]);
				y1 = Math.max(y1, r[k + 3]);
				take(i);
				i = 0;
			} else i++;
		}
		if (count == MAX) {
			var best = 0, grows = Math.POSITIVE_INFINITY;
			for (i in 0...count) {
				var g = grown(i, x0, y0, x1, y1);
				if (g < grows) {
					grows = g;
					best = i;
				}
			}
			var r = rects, k = 4 * best;
			x0 = Math.min(x0, r[k]);
			y0 = Math.min(y0, r[k + 1]);
			x1 = Math.max(x1, r[k + 2]);
			y1 = Math.max(y1, r[k + 3]);
			take(best);
			return add(x0, y0, x1, y1);
		}
		put(x0, y0, x1, y1);
	}

	// its rectangles rounded out to whole pixels at scale k, within a target
	// of w x h of them (all of it: one rectangle, the target)
	public function round(k:Float, w:Int, h:Int) {
		if (all) {
			count = 0;
			put(0, 0, w / k, h / k);
			return;
		}
		var n = count;
		count = 0;
		for (i in 0...n) {
			var x0 = Math.max(0, Math.floor(this.x0(i) * k)), y0 = Math.max(0, Math.floor(this.y0(i) * k));
			var x1 = Math.min(w, Math.ceil(this.x1(i) * k)), y1 = Math.min(h, Math.ceil(this.y1(i) * k));
			if (x1 > x0 && y1 > y0) put(x0 / k, y0 / k, x1 / k, y1 / k);
		}
	}

	inline function put(x0:Float, y0:Float, x1:Float, y1:Float) {
		var k = 4 * count++;
		rects[k] = x0;
		rects[k + 1] = y0;
		rects[k + 2] = x1;
		rects[k + 3] = y1;
	}

	// the area covered (all: NaN)
	public function area():Float {
		if (all) return Math.NaN;
		var a = 0.0;
		for (i in 0...count)
			a += (x1(i) - x0(i)) * (y1(i) - y0(i));
		return a;
	}

	// (how much the union with rectangle i is larger than both)
	inline function grown(i:Int, x0:Float, y0:Float, x1:Float, y1:Float):Float {
		var a = this.x0(i), b = this.y0(i), c = this.x1(i), d = this.y1(i);
		return (Math.max(c, x1) - Math.min(a, x0)) * (Math.max(d, y1) - Math.min(b, y0)) - (c - a) * (d - b) - (x1 - x0) * (y1 - y0);
	}

	// (rectangle i taken out: the last in its place)
	function take(i:Int) {
		var r = rects, k = 4 * i, l = 4 * --count;
		r[k] = r[l];
		r[k + 1] = r[l + 1];
		r[k + 2] = r[l + 2];
		r[k + 3] = r[l + 3];
	}
}
