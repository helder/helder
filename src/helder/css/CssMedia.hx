package helder.css;

import helder.css.CssToken;

using StringTools;

// What @media and media="" queries are evaluated against: a printed page.
// width and height: the page's (px; the viewport's for vw and vh too),
// resolution in dppx; color: bits per component (0: monochrome).
typedef CssMediaContext = {
	type:String,
	width:Float,
	height:Float,
	?resolution:Float,
	?color:Int
}

// A media query list (Media Queries 4): parsed from component values,
// evaluated against a context. Types, `not` and `only`, `and`, `or`,
// `not` of a condition, features in plain and range form (`(width >=
// 600px)`, `(400px < width < 800px)`); an unknown feature or a malformed
// query is false (`not` of it too, as §3.2 says of the latter).
class CssMedia {
	public static final PRINT:CssMediaContext = {type: "print", width: 793.7, height: 1122.5, resolution: 1, color: 8};

	final queries:Array<Query>;

	function new(queries:Array<Query>)
		this.queries = queries;

	// An empty list matches everything.
	public static function parse(values:Array<CssValue>):CssMedia {
		var out = [];
		for (q in split(values)) out.push(try query(new Reader(q)) catch (e:Bad) Never);
		return new CssMedia(out);
	}

	public static function text(s:String):CssMedia
		return parse(Css.values(s));

	public function matches(ctx:CssMediaContext):Bool {
		if (queries.length == 0) return true;
		for (q in queries) if (eval(q, ctx)) return true;
		return false;
	}

	static function split(values:Array<CssValue>):Array<Array<CssValue>> {
		var out = [], cur = [], any = false;
		for (v in values) switch v {
			case Token(t) if (t.kind.match(Comma)):
				out.push(cur);
				cur = [];
				any = true;
			case _: cur.push(v);
		}
		if (any || [for (v in cur) if (!isSpace(v)) v].length > 0) out.push(cur);
		return out;
	}

	static function query(r:Reader):Query {
		r.space();
		var w = r.ident();
		if (w != null) {
			var lw = Css.lower(w);
			if (lw == "not" || lw == "only") {
				r.next();
				r.space();
				var t = r.ident();
				if (t == null) {
					if (lw == "only") throw new Bad();
					// `not (condition)`
					var c = Negate(condition(r));
					r.end();
					return Condition(c);
				}
				r.next();
				var c = rest(r);
				return Typed(Css.lower(t), lw == "not", c);
			}
			if (lw == "and" || lw == "or") throw new Bad();
			r.next();
			return Typed(lw, false, rest(r));
		}
		var c = condition(r);
		r.end();
		return Condition(c);
	}

	// (`and <condition-without-or>` after a type)
	static function rest(r:Reader):Null<Cond> {
		r.space();
		if (r.done()) return null;
		var w = r.ident();
		if (w == null || Css.lower(w) != "and") throw new Bad();
		r.next();
		var c = condition(r, false);
		r.end();
		return c;
	}

	static function condition(r:Reader, ors = true):Cond {
		r.space();
		var w = r.ident();
		if (w != null && Css.lower(w) == "not") {
			r.next();
			return Negate(inParens(r));
		}
		var first = inParens(r);
		r.space();
		var op = r.ident();
		if (op == null) return first;
		var l = Css.lower(op);
		if (l != "and" && (l != "or" || !ors)) throw new Bad();
		var items = [first];
		while (true) {
			r.space();
			var o = r.ident();
			if (o == null || Css.lower(o) != l) break;
			r.next();
			items.push(inParens(r));
		}
		return l == "and" ? And(items) : Or(items);
	}

	static function inParens(r:Reader):Cond {
		r.space();
		return switch r.peek() {
			case Block(open, values, _) if (open.kind.match(OpenParen)):
				r.next();
				var inner = new Reader(values);
				inner.space();
				// (a nested condition, else a feature)
				var nested = inner.peek() != null && (inner.peek().match(Block(_.kind => OpenParen, _, _)) || inner.ident() != null && Css.lower(inner.ident()) == "not");
				if (nested) {
					var c = condition(inner);
					inner.end();
					c;
				} else try feature(values) catch (e:Bad) Unknown;
			case Function(_, _, _, _):
				// (general-enclosed: false, not invalid)
				r.next();
				Unknown;
			case _: throw new Bad();
		}
	}

	// (name), (name: value), (name op value), (value op name), (value op name op value)
	static function feature(values:Array<CssValue>):Cond {
		var items = [for (v in values) if (!isSpace(v)) v];
		if (items.length == 1) return switch items[0] {
			case Token(_.kind => Ident(n)): Feature(Css.lower(n), null, null);
			case _: throw new Bad();
		}
		var colon = -1;
		for (k in 0...items.length) if (items[k].match(Token(_.kind => Colon))) colon = k;
		if (colon == 1) return switch items[0] {
			case Token(_.kind => Ident(n)): Feature(Css.lower(n), "=", items.slice(2));
			case _: throw new Bad();
		}
		// (range form: operators are delims, `<=` two of them)
		var parts:Array<Dynamic> = [];
		var k = 0;
		while (k < items.length) {
			var op = delim(items[k]);
			if (op == "<" || op == ">" || op == "=") {
				var o = op;
				if (op != "=" && k + 1 < items.length && delim(items[k + 1]) == "=") {
					o += "=";
					k++;
				}
				parts.push(o);
				k++;
				continue;
			}
			var group = [];
			while (k < items.length && !["<", ">", "="].contains(delim(items[k]))) group.push(items[k++]);
			parts.push(group);
		}
		inline function name(p:Dynamic):Null<String>
			return Std.isOfType(p, Array) && (p : Array<CssValue>).length == 1 ? switch (p : Array<CssValue>)[0] {
				case Token(_.kind => Ident(n)): Css.lower(n);
				case _: null;
			} : null;
		if (parts.length == 3) {
			var n = name(parts[0]);
			if (n != null) return Feature(n, parts[1], parts[2]);
			n = name(parts[2]);
			if (n != null) return Feature(n, flip(parts[1]), parts[0]);
			throw new Bad();
		}
		if (parts.length == 5) {
			var n = name(parts[2]);
			if (n == null) throw new Bad();
			return And([Feature(n, flip(parts[1]), parts[0]), Feature(n, parts[3], parts[4])]);
		}
		throw new Bad();
	}

	static function flip(op:String):String
		return switch op {
			case "<": ">";
			case "<=": ">=";
			case ">": "<";
			case ">=": "<=";
			case o: o;
		}

	static function delim(v:CssValue):Null<String>
		return switch v {
			case Token(_.kind => Delim(d)): d;
			case _: null;
		}

	// ---- evaluation

	static function eval(q:Query, ctx:CssMediaContext):Bool
		return switch q {
			case Never: false;
			case Typed(type, not, c):
				var ok = (type == "all" || type == ctx.type) && (c == null || cond(c, ctx) == 1);
				not ? !ok : ok;
			case Condition(c): cond(c, ctx) == 1;
		}

	// (three values: 1 true, 0 false, -1 unknown)
	static function cond(c:Cond, ctx:CssMediaContext):Int
		return switch c {
			case Unknown: -1;
			case Negate(x):
				var v = cond(x, ctx);
				v == -1 ? -1 : 1 - v;
			case And(xs):
				var out = 1;
				for (x in xs) {
					var v = cond(x, ctx);
					if (v == 0) return 0;
					if (v == -1) out = -1;
				}
				out;
			case Or(xs):
				var out = 0;
				for (x in xs) {
					var v = cond(x, ctx);
					if (v == 1) return 1;
					if (v == -1) out = -1;
				}
				out;
			case Feature(name, op, value): feature_(name, op, value, ctx);
		}

	static function feature_(name:String, op:Null<String>, value:Null<Array<CssValue>>, ctx:CssMediaContext):Int {
		var prefix = name.startsWith("min-") ? "min" : name.startsWith("max-") ? "max" : null;
		var base = prefix == null ? name : name.substr(4);
		if (prefix != null && op != "=") return -1;
		var o = prefix == "min" ? ">=" : prefix == "max" ? "<=" : op;
		inline function compare(actual:Float, wanted:Null<Float>):Int {
			if (wanted == null) return -1;
			return (switch o {
				case "=": Math.abs(actual - wanted) < 1e-6;
				case "<": actual < wanted;
				case "<=": actual <= wanted + 1e-6;
				case ">": actual > wanted;
				case ">=": actual >= wanted - 1e-6;
				case _: false;
			}) ? 1 : 0;
		}
		var resolution = ctx.resolution ?? 1, color = ctx.color ?? 8;
		return switch base {
			case "width" | "device-width": o == null ? (ctx.width != 0 ? 1 : 0) : compare(ctx.width, length(value));
			case "height" | "device-height": o == null ? (ctx.height != 0 ? 1 : 0) : compare(ctx.height, length(value));
			case "aspect-ratio" | "device-aspect-ratio": o == null ? 1 : compare(ctx.width / ctx.height, ratio(value));
			case "orientation" if (o == "=" && prefix == null):
				var w = word(value);
				w == null ? -1 : (w == (ctx.height >= ctx.width ? "portrait" : "landscape")) ? 1 : 0;
			case "resolution" | "-webkit-device-pixel-ratio": o == null ? 1 : compare(resolution, base == "resolution" ? dppx(value) : number(value));
			case "color": o == null ? (color > 0 ? 1 : 0) : compare(color, number(value));
			case "monochrome": o == null ? (color == 0 ? 1 : 0) : compare(color == 0 ? 8 : 0, number(value));
			case "color-index": o == null ? 0 : compare(0, number(value));
			case "grid": o == null ? 0 : compare(0, number(value));
			// (a printed page: no hovering, no pointer, no updates, no scripts, light, as it is)
			case "hover" | "any-hover" | "pointer" | "any-pointer" | "update" | "scripting" | "overflow-inline":
				o == null ? 0 : keyword(value, "none");
			case "overflow-block": o == null ? 1 : keyword(value, "paged");
			case "prefers-color-scheme": o == null ? 1 : keyword(value, "light");
			case "prefers-reduced-motion" | "prefers-reduced-transparency" | "prefers-reduced-data" | "prefers-contrast" | "forced-colors" | "inverted-colors":
				o == null ? 0 : keyword(value, base == "prefers-contrast" ? "no-preference" : base == "forced-colors" || base == "inverted-colors" ? "none" : "no-preference");
			case "color-gamut": o == null ? 1 : keyword(value, "srgb");
			case "dynamic-range" | "video-dynamic-range": o == null ? 1 : keyword(value, "standard");
			case "scan": o == null ? 0 : 0;
			case _: -1;
		}
	}

	static function keyword(value:Null<Array<CssValue>>, actual:String):Int {
		var w = word(value);
		return w == null ? -1 : w == actual ? 1 : 0;
	}

	static function items(value:Null<Array<CssValue>>):Array<CssValue>
		return value == null ? [] : [for (v in value) if (!isSpace(v)) v];

	static function word(value:Null<Array<CssValue>>):Null<String>
		return switch items(value) {
			case [Token(_.kind => Ident(w))]: Css.lower(w);
			case _: null;
		}

	static function number(value:Null<Array<CssValue>>):Null<Float>
		return switch items(value) {
			case [Token(_.kind => Number(n, _, _))]: n;
			case _: null;
		}

	// (a length in px: em and rem against 16px, the initial font size)
	static function length(value:Null<Array<CssValue>>):Null<Float>
		return switch items(value) {
			case [Token(_.kind => Number(0, _, _))]: 0;
			case [Token(_.kind => Dimension(n, _, _, unit))]:
				var c = CssCalc.canonical(n, Css.lower(unit), {fontSize: 16, rootFontSize: 16});
				c == null || c.unit != "px" ? null : c.value;
			case [v = Function(_, _, _, _)]:
				var c = CssCalc.parse(v);
				c == null ? null : switch CssCalc.simplify(c, {fontSize: 16, rootFontSize: 16}) {
					case Value(x, "px"): x;
					case _: null;
				}
			case _: null;
		}

	static function dppx(value:Null<Array<CssValue>>):Null<Float>
		return switch items(value) {
			case [Token(_.kind => Dimension(n, _, _, unit))]:
				var c = CssCalc.canonical(n, Css.lower(unit));
				c == null || c.unit != "dppx" ? null : c.value;
			case _: null;
		}

	static function ratio(value:Null<Array<CssValue>>):Null<Float>
		return switch items(value) {
			case [Token(_.kind => Number(a, _, _))]: a;
			case [Token(_.kind => Number(a, _, _)), Token(_.kind => Delim("/")), Token(_.kind => Number(b, _, _))]: b == 0 ? null : a / b;
			case _: null;
		}

	static function isSpace(v:CssValue):Bool
		return switch v {
			case Token(t): t.kind.match(Whitespace);
			case _: false;
		}
}

private enum Query {
	Never;
	// type, `not`, the condition after `and`
	Typed(type:String, not:Bool, condition:Null<Cond>);
	Condition(c:Cond);
}

private enum Cond {
	Feature(name:String, op:Null<String>, value:Null<Array<CssValue>>);
	Negate(c:Cond);
	And(items:Array<Cond>);
	Or(items:Array<Cond>);
	// general-enclosed and unknown features
	Unknown;
}

private class Bad extends haxe.Exception {
	public function new()
		super("not a media query");
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

	public function space()
		while (i < values.length && switch values[i] {
			case Token(t): t.kind.match(Whitespace);
			case _: false;
		}) i++;

	public function ident():Null<String>
		return switch peek() {
			case Token(_.kind => Ident(w)): w;
			case _: null;
		}

	public function end() {
		space();
		if (!done()) throw new Bad();
	}
}
