package helder.css;

import helder.css.CssTerm;

// An easing function (Easing 1, 2): a progress through a transition
// turned into the progress of its value. The keywords, cubic-bezier()
// (its curve solved for x), steps() (jump-start, -end, -none, -both;
// before the start, a jump-start step not yet taken), linear() (its
// points, a missing input spread between its neighbours').
//
//   var e = CssEasing.of(style.terms(TransitionTimingFunction));
//   e.at(0.5);  // 0.8024 for ease
class CssEasing {
	public static final LINEAR = new CssEasing(Linear([{x: 0, y: 0}, {x: 1, y: 1}]));
	public static final EASE = bezier(0.25, 0.1, 0.25, 1);

	final kind:Kind;

	function new(kind:Kind)
		this.kind = kind;

	// One easing function's computed terms; linear for what isn't one.
	public static function of(t:Array<CssTerm>):CssEasing
		return switch t {
			case [Keyword("linear")]: LINEAR;
			case [Keyword("ease")]: EASE;
			case [Keyword("ease-in")]: bezier(0.42, 0, 1, 1);
			case [Keyword("ease-out")]: bezier(0, 0, 0.58, 1);
			case [Keyword("ease-in-out")]: bezier(0.42, 0, 0.58, 1);
			case [Keyword("step-start")]: new CssEasing(Steps(1, "start"));
			case [Keyword("step-end")]: new CssEasing(Steps(1, "end"));
			case [Func("cubic-bezier", args)]:
				var n = numbers(args);
				n.length == 4 ? bezier(n[0], n[1], n[2], n[3]) : LINEAR;
			case [Func("steps", args)]:
				var n = numbers(args);
				var position = "end";
				for (a in args) switch a {
					case Keyword(k): position = k == "start" ? "jump-start" : k == "end" ? "jump-end" : k;
					case _:
				}
				n.length >= 1 ? new CssEasing(Steps(Std.int(n[0]), position)) : LINEAR;
			case [Func("linear", args)]: linear(args);
			case _: LINEAR;
		}

	public static function bezier(x1:Float, y1:Float, x2:Float, y2:Float):CssEasing
		return new CssEasing(Bezier(x1, y1, x2, y2));

	// The output progress for an input progress (before: the input comes
	// from before the transition's start, for steps' jump-start).
	public function at(x:Float, before = false):Float
		return switch kind {
			case Linear(points): piecewise(points, x);
			case Bezier(x1, y1, x2, y2): curve(x1, y1, x2, y2, x);
			case Steps(n, position): steps(n, position, x, before);
		}

	// (Easing 1 §2.3.2: the curve's y for x, past 0 and 1 along its end tangents)
	static function curve(x1:Float, y1:Float, x2:Float, y2:Float, x:Float):Float {
		if (x < 0) {
			var slope = x1 > 0 ? y1 / x1 : x2 > 0 && y1 == 0 ? y2 / x2 : 0;
			return slope * x;
		}
		if (x > 1) {
			var slope = x2 < 1 ? (y2 - 1) / (x2 - 1) : x1 < 1 && y2 == 1 ? (y1 - 1) / (x1 - 1) : 0;
			return 1 + slope * (x - 1);
		}
		inline function bx(s:Float):Float
			return 3 * x1 * s * (1 - s) * (1 - s) + 3 * x2 * s * s * (1 - s) + s * s * s;
		inline function by(s:Float):Float
			return 3 * y1 * s * (1 - s) * (1 - s) + 3 * y2 * s * s * (1 - s) + s * s * s;
		inline function dx(s:Float):Float
			return 3 * x1 * (1 - s) * (1 - s) + 6 * (x2 - x1) * s * (1 - s) + 3 * (1 - x2) * s * s;
		// (Newton's method, then halving where it doesn't converge)
		var s = x;
		for (_ in 0...8) {
			var e = bx(s) - x;
			if (Math.abs(e) < 1e-7) return by(s);
			var d = dx(s);
			if (Math.abs(d) < 1e-6) break;
			s -= e / d;
		}
		var lo = 0.0, hi = 1.0;
		s = x;
		for (_ in 0...60) {
			var v = bx(s);
			if (Math.abs(v - x) < 1e-7) break;
			if (v < x) lo = s else hi = s;
			s = (lo + hi) / 2;
		}
		return by(s);
	}

	// (Easing 1 §2.4: the step the input is on; jumps at the start, the end, both or neither)
	static function steps(n:Int, position:String, x:Float, before:Bool):Float {
		var current = Math.floor(x * n);
		if (position == "jump-start" || position == "jump-both") current++;
		if (before && Math.floor(x * n) == x * n) current--;
		if (x >= 0 && current < 0) current = 0;
		var jumps = switch position {
			case "jump-none": n - 1;
			case "jump-both": n + 1;
			case _: n;
		}
		if (x <= 1 && current > jumps) current = jumps;
		return jumps == 0 ? 0 : current / jumps;
	}

	// (Easing 2 §2.2: linear()'s points; the first and last inputs 0 and 1
	// when left out, one below its predecessor's raised to it, a run of
	// missing ones spread evenly)
	static function linear(args:Array<CssTerm>):CssEasing {
		var points:Array<{y:Float, x:Null<Float>}> = [];
		var item:Array<CssTerm> = [];
		function flush() {
			var y:Null<Float> = null, xs = [];
			for (t in item) switch t {
				case Number(v, _): if (y == null) y = v else xs.push(v * 100);
				case Percentage(p): xs.push(p);
				case _:
			}
			if (y != null) {
				if (xs.length == 0) points.push({y: y, x: null});
				for (x in xs) points.push({y: y, x: x / 100});
			}
			item = [];
		}
		for (a in args) if (a.match(Delim(","))) flush() else item.push(a);
		flush();
		if (points.length < 2) return LINEAR;
		if (points[0].x == null) points[0].x = 0;
		if (points[points.length - 1].x == null) points[points.length - 1].x = 1;
		var largest = points[0].x;
		for (p in points) if (p.x != null) {
			if (p.x < largest) p.x = largest;
			largest = p.x;
		}
		var k = 0;
		while (k < points.length) {
			if (points[k].x != null) {
				k++;
				continue;
			}
			var start = k - 1, end = k;
			while (points[end].x == null) end++;
			var from = points[start].x, to = points[end].x;
			for (j in start + 1...end) points[j].x = from + (to - from) * (j - start) / (end - start);
			k = end;
		}
		return new CssEasing(Linear([for (p in points) {x: p.x, y: p.y}]));
	}

	static function piecewise(points:Array<{x:Float, y:Float}>, x:Float):Float {
		var n = points.length;
		// (past either end: the first or last two points' line)
		var a = 0;
		if (x >= points[n - 1].x) a = n - 2 else while (a < n - 2 && points[a + 1].x <= x) a++;
		var p = points[a], q = points[a + 1];
		if (x < points[0].x) {
			p = points[0];
			q = points[1];
		}
		if (q.x == p.x) return x < q.x ? p.y : q.y;
		return p.y + (q.y - p.y) * (x - p.x) / (q.x - p.x);
	}

	static function numbers(args:Array<CssTerm>):Array<Float>
		return [for (a in args) switch a {
			case Number(v, _): v;
			case _: Math.NaN;
		}].filter(v -> !Math.isNaN(v));
}

private enum Kind {
	Linear(points:Array<{x:Float, y:Float}>);
	Bezier(x1:Float, y1:Float, x2:Float, y2:Float);
	Steps(n:Int, position:String);
}
