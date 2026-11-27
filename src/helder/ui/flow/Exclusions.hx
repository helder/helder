package helder.ui.flow;

// A block formatting context's floats (CSS 2.1 §9.5), their margin
// boxes in layout coordinates: where the next float goes (§9.5.1's
// rules), the room a line or a formatting context's root has beside
// them, where clearance puts a box (§9.5.2), how low they reach.
class Exclusions {
	final lefts:Array<Bool> = [];
	final x0s:Array<Float> = [];
	final x1s:Array<Float> = [];
	final y0s:Array<Float> = [];
	final y1s:Array<Float> = [];
	// (in a fragmentainer: a float went to the next whole, the floats after it there too, CSS 2.1 §9.5.1 rule 5)
	public var pushed = false;
	// (a float's top is no higher than an earlier one's, rule 5)
	var lastTop = Math.NEGATIVE_INFINITY;

	public function new() {}

	public var empty(get, never):Bool;

	inline function get_empty():Bool
		return lefts.length == 0;

	public var count(get, never):Int;

	inline function get_count():Int
		return lefts.length;

	// The room between the floats across y...y + h, within left...right.
	public function band(y:Float, h:Float, left:Float, right:Float):{left:Float, right:Float} {
		var l = left, r = right;
		for (k in 0...lefts.length) {
			if (y0s[k] >= y + Math.max(h, 1e-6) || y1s[k] <= y) continue;
			if (lefts[k]) l = Math.max(l, x1s[k]) else r = Math.min(r, x0s[k]);
		}
		return {left: l, right: r};
	}

	// (the next y below y where a float overlapping y...y + h ends; infinity: none)
	public function nextBelow(y:Float, h:Float):Float {
		var next = Math.POSITIVE_INFINITY;
		for (k in 0...lefts.length) if (y0s[k] < y + Math.max(h, 1e-6) && y1s[k] > y && y1s[k] < next) next = y1s[k];
		return next;
	}

	// A float of margin box w by h, at y or below, within left...right: its margin box's top left (§9.5.1).
	public function place(left:Bool, w:Float, h:Float, y:Float, cbLeft:Float, cbRight:Float):{x:Float, y:Float} {
		y = Math.max(y, lastTop);
		// (rule 7: an oversized float can pass the opposite edge only without a float on its own side)
		var oversized = w > cbRight - cbLeft;
		var sameSideBottom = oversized ? clear(left ? "left" : "right") : Math.NEGATIVE_INFINITY;
		while (true) {
			var low = cbLeft, high = cbRight;
			if (oversized && y >= sameSideBottom) {
				if (left) high = cbLeft + w else low = cbRight - w;
			}
			var b = band(y, h, low, high);
			var next = nextBelow(y, h);
			if (b.right - b.left >= w || next == Math.POSITIVE_INFINITY) {
				var x = left ? b.left : b.right - w;
				add(left, x, y, w, h);
				return {x: x, y: y};
			}
			y = next;
		}
	}

	public function add(left:Bool, x:Float, y:Float, w:Float, h:Float) {
		lefts.push(left);
		x0s.push(x);
		x1s.push(x + w);
		y0s.push(y);
		y1s.push(y + h);
		lastTop = y;
		low = Math.NaN;
	}

	// The last n floats taken out again (a line's floats placed anew).
	public function drop(n:Int) {
		var k = lefts.length - n;
		if (k < 0) k = 0;
		lefts.resize(k);
		x0s.resize(k);
		x1s.resize(k);
		y0s.resize(k);
		y1s.resize(k);
		low = Math.NaN;
		lastTop = k > 0 ? y0s[k - 1] : Math.NEGATIVE_INFINITY;
	}

	// The bottom of the floats on a side ("left", "right", "both"): where clearance puts a box's top.
	public function clear(side:String):Float {
		var bottom = Math.NEGATIVE_INFINITY;
		for (k in 0...lefts.length) {
			var hit = side == "both" || (side == "left" || side == "inline-start") == lefts[k];
			if (hit && y1s[k] > bottom) bottom = y1s[k];
		}
		return bottom;
	}

	// How low the floats reach (a formatting context's root's height takes them in, §10.6.7).
	public function lowest():Float {
		if (!Math.isNaN(low)) return low;
		var bottom = Math.NEGATIVE_INFINITY;
		for (y in y1s) if (y > bottom) bottom = y;
		return low = bottom;
	}

	// (lowest's, until the floats change)
	var low = Math.NaN;
}
