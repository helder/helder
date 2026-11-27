package helder.css;

import helder.css.CssToken;

// CSS Values 4's math functions (§10): calc(), min(), max(), clamp(),
// round(), mod(), rem(), the trigonometric and exponential ones, abs(),
// sign(); their trees typed (§10.8), simplified (§10.10) and serialized
// (§10.12). A value is its number and unit: "" a number, "%" a
// percentage, else a dimension's unit, ASCII lowercase.
enum CssCalcNode {
	Value(value:Float, unit:String);
	Sum(items:Array<CssCalcNode>);
	Product(items:Array<CssCalcNode>);
	Negate(item:CssCalcNode);
	Invert(item:CssCalcNode);
	Fn(name:String, args:Array<CssCalcNode>);
	// a keyword argument: round()'s strategy, clamp()'s none
	Word(name:String);
}

// What is known when computing: lengths' relative units in px.
typedef CssCalcContext = {
	?fontSize:Float,
	?rootFontSize:Float,
	// (lh's and rlh's: the line height in px; null for normal)
	?lineHeight:Float,
	?rootLineHeight:Float,
	?viewport:{width:Float, height:Float},
	// (ex, ch, cap and ic: the first available font's; rex, rch, rcap, ric: the root's)
	?metrics:CssFontMetrics,
	?rootMetrics:CssFontMetrics
}

class CssCalc {
	public static final FUNCTIONS = [
		"calc", "min", "max", "clamp", "round", "mod", "rem", "sin", "cos", "tan", "asin", "acos", "atan", "atan2", "pow", "sqrt", "hypot", "log", "exp",
		"abs", "sign"
	];
	// (base types: length, angle, time, frequency, resolution, flex, percent)
	static inline var BASES = 7;
	static inline var PERCENT = 6;

	public static function isMath(name:String):Bool
		return FUNCTIONS.contains(Css.lower(name));

	// A math function's tree, null when it is not one (a syntax error).
	public static function parse(v:CssValue):Null<CssCalcNode> {
		return switch v {
			case Function(name, values, _, _) if (isMath(name)): try function_(Css.lower(name), values) catch (e:Bad) null;
			case _: null;
		}
	}

	static function function_(name:String, values:Array<CssValue>):CssCalcNode {
		if (name == "calc") return sum(new Reader(values), true);
		var args = [];
		var r = new Reader(values);
		r.space();
		if (r.done()) throw new Bad();
		while (true) {
			r.space();
			var w = r.word();
			if (w != null) {
				var lw = Css.lower(w);
				if (name == "round" && args.length == 0 && ["nearest", "up", "down", "to-zero", "line-width"].contains(lw)) {
					args.push(Word(lw));
					r.next();
				} else if (name == "clamp" && lw == "none" && (args.length == 0 || args.length == 2)) {
					args.push(Word("none"));
					r.next();
				} else args.push(sum(r, false));
			} else args.push(sum(r, false));
			r.space();
			if (r.done()) break;
			if (!r.comma()) throw new Bad();
		}
		var n = args.length, words = args.filter(a -> a.match(Word(_))).length;
		var ok = switch name {
			case "min" | "max" | "hypot": n >= 1;
			case "clamp": n == 3;
			case "round": n - (args[0].match(Word(_)) ? 1 : 0) >= 1 && n - (args[0].match(Word(_)) ? 1 : 0) <= 2;
			case "mod" | "rem" | "atan2" | "pow": n == 2;
			case "log": n == 1 || n == 2;
			case _: n == 1;
		}
		if (!ok || name != "round" && name != "clamp" && words > 0) throw new Bad();
		return Fn(name, args);
	}

	// <calc-sum>: whitespace required around + and -
	static function sum(r:Reader, whole:Bool):CssCalcNode {
		var items = [product(r)];
		while (true) {
			var spaced = r.space();
			if (r.done() || r.isComma()) break;
			var op = r.delim();
			if (op != "+" && op != "-") {
				if (!spaced && !whole) throw new Bad();
				throw new Bad();
			}
			r.next();
			if (!spaced || !r.space()) throw new Bad();
			var p = product(r);
			items.push(op == "-" ? Negate(p) : p);
		}
		if (whole && !r.done()) throw new Bad();
		return items.length == 1 ? items[0] : Sum(items);
	}

	static function product(r:Reader):CssCalcNode {
		var items = [value(r)];
		while (true) {
			var mark = r.mark();
			r.space();
			var op = r.delim();
			if (op != "*" && op != "/") {
				r.reset(mark);
				break;
			}
			r.next();
			r.space();
			var v = value(r);
			items.push(op == "/" ? Invert(v) : v);
		}
		return items.length == 1 ? items[0] : Product(items);
	}

	static function value(r:Reader):CssCalcNode {
		r.space();
		var v = r.peek();
		if (v == null) throw new Bad();
		r.next();
		return switch v {
			case Token(t):
				switch t.kind {
					case Number(n, _, _): Value(n, "");
					case Percentage(n, _, _): Value(n, "%");
					case Dimension(n, _, _, unit): Value(n, Css.lower(unit));
					case Ident(name):
						switch Css.lower(name) {
							case "e": Value(Math.exp(1), "");
							case "pi": Value(Math.PI, "");
							case "infinity": Value(Math.POSITIVE_INFINITY, "");
							case "-infinity": Value(Math.NEGATIVE_INFINITY, "");
							case "nan": Value(Math.NaN, "");
							case _: throw new Bad();
						}
					case _: throw new Bad();
				}
			case Block(open, values, _) if (open.kind.match(OpenParen)): sum(new Reader(values), true);
			case Function(name, values, _, _) if (isMath(name)):
				var n = Css.lower(name);
				n == "calc" ? sum(new Reader(values), true) : function_(n, values);
			case _: throw new Bad();
		}
	}

	// ---- types (§10.8): exponents of the base types; pct: the base a percentage resolves against, -1 its own

	public static function base(unit:String):Int
		return switch unit {
			case "": -2;
			case "%": PERCENT;
			case "px" | "cm" | "mm" | "q" | "in" | "pt" | "pc" | "em" | "rem" | "ex" | "rex" | "cap" | "rcap" | "ch" | "rch" | "ic" | "ric" | "lh" | "rlh" | "vw" | "vh" | "vi" | "vb" | "vmin" | "vmax" | "svw" | "svh" | "svi" | "svb" | "svmin" | "svmax" | "lvw" | "lvh" | "lvi" | "lvb" | "lvmin" | "lvmax" | "dvw" | "dvh" | "dvi" | "dvb" | "dvmin" | "dvmax" | "cqw" | "cqh" | "cqi" | "cqb" | "cqmin" | "cqmax": 0;
			case "deg" | "grad" | "rad" | "turn": 1;
			case "s" | "ms": 2;
			case "hz" | "khz": 3;
			case "dpi" | "dpcm" | "dppx" | "x": 4;
			case "fr": 5;
			case _: -1;
		}

	// The tree's type, null when it has none (adding a length to an angle); pct: what a percentage is.
	public static function type(n:CssCalcNode, pct:Int):Null<Array<Int>> {
		inline function none()
			return [for (_ in 0...BASES) 0];
		return switch n {
			case Value(_, unit):
				var b = base(unit), t = none();
				if (b == -1) return null;
				if (b == PERCENT && pct >= 0) b = pct;
				if (b >= 0) t[b] = 1;
				t;
			case Word(_): none();
			case Negate(x): type(x, pct);
			case Invert(x):
				var t = type(x, pct);
				t == null ? null : [for (e in t) -e];
			case Sum(xs): same([for (x in xs) type(x, pct)]);
			case Product(xs):
				var t = none();
				for (x in xs) {
					var u = type(x, pct);
					if (u == null) return null;
					for (k in 0...BASES) t[k] += u[k];
				}
				t;
			case Fn(name, args):
				var ts = [for (a in args) if (!a.match(Word(_))) type(a, pct)];
				if (ts.contains(null)) return null;
				switch name {
					// (round() without a step: of a number only)
					case "round" if (ts.length == 1): ts[0] != null && isNumber(ts[0]) ? ts[0] : null;
					case "min" | "max" | "clamp" | "hypot" | "abs" | "round" | "mod" | "rem": same(ts);
					case "sign": same(ts) == null ? null : none();
					case "sin" | "cos" | "tan":
						var t = ts[0];
						isNumber(t) || isBase(t, 1) ? none() : null;
					case "asin" | "acos" | "atan":
						if (!isNumber(ts[0])) null else {
							var t = none();
							t[1] = 1;
							t;
						}
					case "atan2":
						if (same(ts) == null) null else {
							var t = none();
							t[1] = 1;
							t;
						}
					case "pow" | "sqrt" | "exp" | "log": ts.filter(t -> !isNumber(t)).length == 0 ? none() : null;
					case _: null;
				}
		}
	}

	static function same(ts:Array<Null<Array<Int>>>):Null<Array<Int>> {
		var first = ts[0];
		if (first == null) return null;
		for (t in ts) {
			if (t == null) return null;
			for (k in 0...BASES) if (t[k] != first[k]) return null;
		}
		return first;
	}

	public static function isNumber(t:Array<Int>):Bool {
		for (e in t) if (e != 0) return false;
		return true;
	}

	public static function isBase(t:Array<Int>, b:Int):Bool {
		for (k in 0...BASES) if (t[k] != (k == b ? 1 : 0)) return false;
		return true;
	}

	// (a percentage in this tree, after the hint)
	public static function hasPercent(n:CssCalcNode):Bool
		return switch n {
			case Value(_, "%"): true;
			case Value(_, _) | Word(_): false;
			case Negate(x) | Invert(x): hasPercent(x);
			case Sum(xs) | Product(xs) | Fn(_, xs): Lambda.exists(xs, hasPercent);
		}

	// ---- simplification (§10.10)

	// Units to their canonical one where the conversion is fixed (lengths
	// to px, angles to deg, times to s, frequencies to hz, resolutions to
	// dppx); a context resolves relative lengths too.
	public static function canonical(value:Float, unit:String, ?ctx:CssCalcContext):Null<{value:Float, unit:String}> {
		inline function to(f:Float, u:String)
			return {value: value * f, unit: u};
		return switch unit {
			case "px" | "deg" | "s" | "hz" | "dppx" | "" | "%": {value: value, unit: unit};
			case "cm": to(96 / 2.54, "px");
			case "mm": to(96 / 25.4, "px");
			case "q": to(96 / 101.6, "px");
			case "in": to(96, "px");
			case "pt": to(4 / 3, "px");
			case "pc": to(16, "px");
			case "rad": to(180 / Math.PI, "deg");
			case "grad": to(0.9, "deg");
			case "turn": to(360, "deg");
			case "ms": to(0.001, "s");
			case "khz": to(1000, "hz");
			case "dpi": to(1 / 96, "dppx");
			case "dpcm": to(2.54 / 96, "dppx");
			case "x": to(1, "dppx");
			case "em" if (ctx != null && ctx.fontSize != null): to(ctx.fontSize, "px");
			case "rem" if (ctx != null && ctx.rootFontSize != null): to(ctx.rootFontSize, "px");
			case "lh" if (ctx != null && ctx.lineHeight != null): to(ctx.lineHeight, "px");
			case "rlh" if (ctx != null && ctx.rootLineHeight != null): to(ctx.rootLineHeight, "px");
			case "ex" if (ctx != null && ctx.metrics != null): to(ctx.metrics.ex, "px");
			case "ch" if (ctx != null && ctx.metrics != null): to(ctx.metrics.ch, "px");
			case "cap" if (ctx != null && ctx.metrics != null): to(ctx.metrics.cap, "px");
			case "ic" if (ctx != null && ctx.metrics != null): to(ctx.metrics.ic, "px");
			case "rex" if (ctx != null && ctx.rootMetrics != null): to(ctx.rootMetrics.ex, "px");
			case "rch" if (ctx != null && ctx.rootMetrics != null): to(ctx.rootMetrics.ch, "px");
			case "rcap" if (ctx != null && ctx.rootMetrics != null): to(ctx.rootMetrics.cap, "px");
			case "ric" if (ctx != null && ctx.rootMetrics != null): to(ctx.rootMetrics.ic, "px");
			case "vw" | "svw" | "lvw" | "dvw" | "vi" | "svi" | "lvi" | "dvi" if (ctx != null && ctx.viewport != null): to(ctx.viewport.width / 100, "px");
			case "vh" | "svh" | "lvh" | "dvh" | "vb" | "svb" | "lvb" | "dvb" if (ctx != null && ctx.viewport != null): to(ctx.viewport.height / 100, "px");
			case "vmin" | "svmin" | "lvmin" | "dvmin" if (ctx != null && ctx.viewport != null): to(Math.min(ctx.viewport.width, ctx.viewport.height) / 100, "px");
			case "vmax" | "svmax" | "lvmax" | "dvmax" if (ctx != null && ctx.viewport != null): to(Math.max(ctx.viewport.width, ctx.viewport.height) / 100, "px");
			case _: null;
		}
	}

	public static function simplify(n:CssCalcNode, ?ctx:CssCalcContext, ?percent:Float):CssCalcNode {
		return switch n {
			case Value(v, "%") if (percent != null): Value(v * percent / 100, "px");
			case Value(v, unit):
				var c = canonical(v, unit, ctx);
				c == null ? n : Value(c.value, c.unit);
			case Word(_): n;
			case Negate(x):
				switch simplify(x, ctx, percent) {
					case Value(v, u): Value(-v, u);
					case Negate(y): y;
					case y: Negate(y);
				}
			case Invert(x):
				switch simplify(x, ctx, percent) {
					case Value(v, ""): Value(1 / v, "");
					case Invert(y): y;
					case y: Invert(y);
				}
			case Sum(xs):
				var flat = [];
				for (x in xs) switch simplify(x, ctx, percent) {
					case Sum(ys): for (y in ys) flat.push(y);
					case y: flat.push(y);
				}
				// (values of a unit added up, in the order the units came)
				var out:Array<CssCalcNode> = [], at = new Map<String, Int>();
				for (y in flat) switch y {
					case Value(v, u) if (at.exists(u)):
						switch out[at[u]] {
							case Value(w, _): out[at[u]] = Value(w + v, u);
							case _:
						}
					case Value(_, u):
						at[u] = out.length;
						out.push(y);
					case _: out.push(y);
				}
				out.length == 1 ? out[0] : Sum(sort(out));
			case Product(xs):
				var flat = [];
				for (x in xs) switch simplify(x, ctx, percent) {
					case Product(ys): for (y in ys) flat.push(y);
					case y: flat.push(y);
				}
				var number = 1.0, rest = [];
				for (y in flat) switch y {
					case Value(v, ""): number *= v;
					case _: rest.push(y);
				}
				// (one dimension times numbers: that dimension; a sum of values times a number: each term)
				if (rest.length == 0) Value(number, "") else if (rest.length == 1) switch rest[0] {
					case Value(v, u): Value(v * number, u);
					case Sum(ys) if (Lambda.foreach(ys, y -> y.match(Value(_, _)))): Sum([for (y in ys) switch y {
						case Value(v, u): Value(v * number, u);
						case _: y;
					}]);
					case Invert(Value(v, u)) if (number != 1 && u != ""): Product([Value(number, ""), Invert(Value(v, u))]);
					case r: number == 1 ? r : Product([Value(number, ""), r]);
				} else {
					var units = multiply(rest);
					// (values before the rest, as a sum's)
					if (units != null) units else if (number == 1) Product(sort(rest)) else Product([Value(number, "")].concat(sort(rest)));
				}
			case Fn(name, args):
				var as = [for (a in args) simplify(a, ctx, percent)];
				// (Values 5: clamp() with a none bound is min() or max())
				if (name == "clamp" && as[0].match(Word("none")) && as[2].match(Word("none"))) return as[1];
				if (name == "clamp" && as[0].match(Word("none"))) return simplify(Fn("min", [as[1], as[2]]), ctx, percent);
				if (name == "clamp" && as[2].match(Word("none"))) return simplify(Fn("max", [as[0], as[1]]), ctx, percent);
				var r = evaluate(name, as);
				r == null ? Fn(name, as) : r;
		}
	}

	// (dimensions multiplied and divided down to one unit or a number: 1px / 1px)
	static function multiply(xs:Array<CssCalcNode>):Null<CssCalcNode> {
		var num = [], den = [], value = 1.0;
		for (x in xs) switch x {
			case Value(v, u):
				value *= v;
				num.push(u);
			case Invert(Value(v, u)) if (u != ""):
				value /= v;
				den.push(u);
			case _: return null;
		}
		for (u in den) {
			var k = num.indexOf(u);
			if (k < 0) return null;
			num.splice(k, 1);
		}
		return num.length == 0 ? Value(value, "") : num.length == 1 ? Value(value, num[0]) : null;
	}

	// a function of values in one unit, else null (kept to compute later)
	static function evaluate(name:String, args:Array<CssCalcNode>):Null<CssCalcNode> {
		var strategy = "nearest", vals = [], unit:Null<String> = null, clampNone = [];
		for (a in args) switch a {
			case Word("none"):
				clampNone.push(vals.length);
				vals.push(Math.NaN);
			case Word(w): strategy = w;
			case Value(v, u):
				if (unit == null || unit == "" && name == "pow") unit = u;
				// (args of several units: mixed only for the trigonometric ones' numbers and angles)
				else if (u != unit) return null;
				vals.push(v);
			case _: return null;
		}
		if (unit == null) unit = "";
		inline function num(v:Float)
			return Value(v, "");
		inline function same(v:Float)
			return Value(v, unit);
		inline function radians(v:Float)
			return unit == "deg" ? v * Math.PI / 180 : v;
		inline function angle(v:Float)
			return Value(v * 180 / Math.PI, "deg");
		return switch name {
			case "min":
				var m = vals[0];
				for (v in vals) if (v < m || Math.isNaN(v)) m = v;
				same(m);
			case "max":
				var m = vals[0];
				for (v in vals) if (v > m || Math.isNaN(v)) m = v;
				same(m);
			case "clamp":
				var lo = vals[0], v = vals[1], hi = vals[2];
				if (clampNone.contains(1)) return null;
				var r = v;
				if (!Math.isNaN(hi) && r > hi) r = hi;
				if (!Math.isNaN(lo) && r < lo) r = lo;
				same(r);
			case "abs": same(Math.abs(vals[0]));
			case "sign": num(vals[0] > 0 ? 1 : vals[0] < 0 ? -1 : vals[0]);
			case "hypot":
				var s = 0.0;
				for (v in vals) s += v * v;
				same(Math.sqrt(s));
			case "round":
				var a = vals[0], b = vals.length > 1 ? vals[1] : 1;
				if (vals.length == 1 && unit != "") return null;
				same(switch strategy {
					case "up": Math.ceil(a / b) * b;
					case "down": Math.floor(a / b) * b;
					case "to-zero": (a < 0 ? Math.ceil(a / b) : Math.floor(a / b)) * b;
					case _:
						var lo = Math.floor(a / b) * b, hi = Math.ceil(a / b) * b;
						a - lo < hi - a ? lo : hi;
				});
			case "mod":
				var a = vals[0], b = vals[1];
				same(a - b * Math.floor(a / b));
			case "rem":
				var a = vals[0], b = vals[1];
				same(a % b);
			case "sin": num(Math.sin(radians(vals[0])));
			case "cos": num(Math.cos(radians(vals[0])));
			case "tan": num(Math.tan(radians(vals[0])));
			case "asin": angle(Math.asin(vals[0]));
			case "acos": angle(Math.acos(vals[0]));
			case "atan": angle(Math.atan(vals[0]));
			case "atan2": angle(Math.atan2(vals[0], vals[1]));
			case "pow": num(Math.pow(vals[0], vals[1]));
			case "sqrt": num(Math.sqrt(vals[0]));
			case "exp": num(Math.exp(vals[0]));
			case "log": num(vals.length == 2 ? Math.log(vals[0]) / Math.log(vals[1]) : Math.log(vals[0]));
			case _: null;
		}
	}

	// §10.10's order of a sum's terms: numbers, percentages, dimensions by unit, then the rest
	static function sort(xs:Array<CssCalcNode>):Array<CssCalcNode> {
		function rank(x:CssCalcNode):Int
			return switch x {
				case Value(_, ""): 0;
				case Value(_, "%"): 1;
				case Value(_, _): 2;
				case _: 3;
			}
		var indexed = [for (k in 0...xs.length) {x: xs[k], k: k}];
		indexed.sort((a, b) -> {
			var ra = rank(a.x), rb = rank(b.x);
			if (ra != rb) return ra - rb;
			if (ra == 2) switch [a.x, b.x] {
				case [Value(_, u), Value(_, w)] if (u != w): return u < w ? -1 : 1;
				case _:
			}
			return a.k - b.k;
		});
		return [for (i in indexed) i.x];
	}

	// ---- serialization (§10.12)

	// A math function's text: a lone value in calc(), as a specified value has it.
	public static function serialize(n:CssCalcNode):String
		return switch n {
			case Fn(name, _) if (name != "calc"): node(n, true);
			case Value(v, u) if (!Math.isFinite(v)): 'calc(${node(n, true)})';
			case _: 'calc(${node(n, true)})';
		}

	static function node(n:CssCalcNode, top:Bool):String
		return switch n {
			case Value(v, u):
				if (!Math.isFinite(v)) {
					var w = Math.isNaN(v) ? "NaN" : v > 0 ? "infinity" : "-infinity";
					u == "" ? w : '$w * 1$u';
				} else CssNumber.format(v) + u;
			case Word(w): w;
			case Sum(xs):
				var b = new StringBuf();
				for (k in 0...xs.length) {
					var x = xs[k];
					if (k == 0) b.add(node(x, false)) else switch x {
						case Negate(y): b.add(" - " + node(y, false));
						case Value(v, u) if (v < 0): b.add(" - " + node(Value(-v, u), false));
						case _: b.add(" + " + node(x, false));
					}
				}
				top ? b.toString() : '(${b.toString()})';
			case Product(xs):
				var b = new StringBuf();
				for (k in 0...xs.length) switch xs[k] {
					case Invert(y): b.add((k == 0 ? "1" : "") + " / " + node(y, false));
					case x: b.add((k == 0 ? "" : " * ") + node(x, false));
				}
				top ? b.toString() : '(${b.toString()})';
			case Negate(x): '-1 * ${node(x, false)}';
			case Invert(x): '1 / ${node(x, false)}';
			case Fn(name, args): '$name(${[for (a in args) node(a, true)].join(", ")})';
		}
}

private class Bad extends haxe.Exception {
	public function new()
		super("not a math function");
}

private class Reader {
	final values:Array<CssValue>;
	var i = 0;

	public function new(values:Array<CssValue>)
		this.values = values;

	public function done():Bool
		return i >= values.length;

	public function peek():Null<CssValue>
		return i < values.length ? values[i] : null;

	public function next()
		i++;

	public function mark():Int
		return i;

	public function reset(m:Int)
		i = m;

	// skips whitespace; true when there was some
	public function space():Bool {
		var start = i;
		while (i < values.length && switch values[i] {
			case Token(t): t.kind.match(Whitespace);
			case _: false;
		}) i++;
		return i > start;
	}

	public function delim():Null<String>
		return switch peek() {
			case Token(t): switch t.kind {
					case Delim(d): d;
					case _: null;
				}
			case _: null;
		}

	public function word():Null<String>
		return switch peek() {
			case Token(t): switch t.kind {
					case Ident(w): w;
					case _: null;
				}
			case _: null;
		}

	public function isComma():Bool
		return switch peek() {
			case Token(t): t.kind.match(Comma);
			case _: false;
		}

	public function comma():Bool {
		if (!isComma()) return false;
		i++;
		return true;
	}
}
