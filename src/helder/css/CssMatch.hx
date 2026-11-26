package helder.css;

using Lambda;

import helder.css.CssCalc;
import helder.css.CssGrammar;
import helder.css.CssTerm;
import helder.css.CssToken;

// Component values matched against a grammar (CSS Values 4 §2), by
// backtracking: each node offers its matches to what follows it, so a
// `||` or a repetition gives back values a later term needs. Whitespace
// only separates (calc() reads its own). The primitive types (Values 4's
// numbers and dimensions, strings, identifiers, url(), `<color>`, the
// math functions wherever a number or dimension may be) are matched here,
// the rest by their definitions in CssData.
class CssMatch {
	static final WIDE = ["initial", "inherit", "unset", "revert", "revert-layer", "revert-rule", "default"];
	static final excludedCache = new Map<String, Map<String, Bool>>();

	final items:Array<CssValue>;
	// (each item's index in the values with whitespace, for raw text)
	final at:Array<Int>;
	final all:Array<CssValue>;
	final excluded:Map<String, Bool>;
	// (a shorthand's match: its properties' and types' matches tagged as Parts)
	var tag = false;
	var steps = 0;

	function new(values:Array<CssValue>, excluded:Map<String, Bool>) {
		all = values;
		items = [];
		at = [];
		for (k in 0...values.length) if (!space(values[k])) {
			items.push(values[k]);
			at.push(k);
		}
		this.excluded = excluded;
	}

	// The terms of values matched against a property's grammar, null when they don't match.
	public static function property(name:String, values:Array<CssValue>):Null<Array<CssTerm>> {
		var p = CssGrammars.property(name);
		if (p == null) return null;
		return match(CssGrammars.of(p.syntax), values, [name], excludedOf(name, p.syntax), CssShorthands.isShorthand(name));
	}

	public static function match(g:CssGrammar, values:Array<CssValue>, context:Array<String>, ?excluded:Map<String, Bool>, tag = false):Null<Array<CssTerm>> {
		var m = new CssMatch(values, excluded ?? new Map());
		m.tag = tag;
		var out:Null<Array<CssTerm>> = null;
		try {
			m.node(g, 0, context, (i, terms) -> {
				if (i != m.items.length) return false;
				out = terms;
				return true;
			});
		} catch (e:TooLong) return null;
		return out;
	}

	// (the keywords a property's grammar has, which its custom idents can't be)
	static function excludedOf(name:String, syntax:String):Map<String, Bool> {
		var e = excludedCache.get(name);
		if (e != null) return e;
		e = new Map();
		var seen = new Map<String, Bool>();
		function walk(g:CssGrammar, context:Array<String>)
			switch g {
				case Keyword(k): e.set(Css.lower(k), true);
				case Named(n, _) if (!StringTools.endsWith(n, "()") && !seen.exists(n)):
					seen.set(n, true);
					var t = CssGrammars.type(n, context);
					if (t != null && t.syntax != null) walk(CssGrammars.of(t.syntax), context.concat(['<$n>']));
				case Sequence(xs) | All(xs) | Any(xs) | One(xs): for (x in xs) walk(x, context);
				case Repeat(x, _, _, _) | Required(x): walk(x, context);
				case _:
			}
		walk(CssGrammars.of(syntax), [name]);
		excludedCache.set(name, e);
		return e;
	}

	function node(g:CssGrammar, i:Int, ctx:Array<String>, k:(Int, Array<CssTerm>) -> Bool):Bool {
		// (a bound on the search: a grammar of many || and repetitions over many values)
		if (++steps > 200000) throw new TooLong();
		return switch g {
			case Keyword(name):
				var w = ident(i);
				w != null && Css.lower(w) == Css.lower(name) && k(i + 1, [Keyword(Css.lower(name))]);
			case Delim(text): delim(i, text) && k(i + 1, [Delim(text)]);
			case Named(name, range): named(name, range, i, ctx, k);
			case Prop(name):
				var p = CssGrammars.property(name);
				var syntax = p != null ? p.syntax : {
					var t = CssGrammars.type('\'$name\'', ctx);
					t == null ? null : t.syntax;
				}
				syntax != null && node(CssGrammars.of(syntax), i, ctx.concat([name]), tag ? (j, terms) -> k(j, [Part(name, terms)]) : k);
			case Func(name, args):
				i < items.length && switch items[i] {
					case Function(f, values, _, _) if (Css.lower(f) == Css.lower(name)):
						var inner = inside(values, args, ctx);
						inner != null && k(i + 1, [Func(Css.lower(name), inner)]);
					case _: false;
				}
			case Block(open, inner):
				i < items.length && switch items[i] {
					case CssValue.Block(o, values, _) if (opens(o, open)):
						var terms = inside(values, inner, ctx);
						terms != null && k(i + 1, [Brackets(open, terms)]);
					case _: false;
				}
			case Sequence(xs): sequence(xs, 0, i, [], ctx, k);
			case One(xs):
				// (a unitless 0 is a number where a number may be, before a length;
				// a math function known now tries the range that holds it first, as a grid line's)
				for (x in inRangeFirst(numbersFirst(xs), i)) if (node(x, i, ctx, k)) return true;
				false;
			case Any(xs): some(xs, [for (_ in xs) false], i, [], ctx, false, k);
			case All(xs): some(xs, [for (_ in xs) false], i, [], ctx, true, k);
			case Repeat(x, min, max, comma): repeat(x, min, max, comma, 0, i, [], ctx, k);
			case Required(x): node(x, i, ctx, (j, terms) -> j > i && k(j, terms));
		}
	}

	function inRangeFirst(xs:Array<CssGrammar>, i:Int):Array<CssGrammar> {
		if (i >= items.length || !xs.exists(x -> x.match(Named(_, {min: _})))) return xs;
		var value = switch items[i] {
			case Function(f, _, _, _) if (CssCalc.isMath(f)):
				var c = CssCalc.parse(items[i]);
				c == null ? null : switch CssCalc.simplify(c) {
					case Value(v, _): v;
					case _: null;
				}
			case _: null;
		}
		if (value == null) return xs;
		var holds = xs.filter(x -> switch x {
			case Named(_, r) if (r != null): Math.fround(value) >= r.min && Math.fround(value) <= r.max;
			case _: false;
		});
		return holds.concat(xs.filter(x -> !holds.contains(x)));
	}

	static function numbersFirst(xs:Array<CssGrammar>):Array<CssGrammar> {
		var n = xs.filter(x -> x.match(Named("number" | "integer", _)));
		return n.length == 0 || n.length == xs.length ? xs : n.concat(xs.filter(x -> !x.match(Named("number" | "integer", _))));
	}

	// (a function's or block's values matched whole against its grammar)
	function inside(values:Array<CssValue>, g:CssGrammar, ctx:Array<String>):Null<Array<CssTerm>> {
		var m = new CssMatch(values, excluded);
		m.steps = steps;
		m.tag = tag;
		var out:Null<Array<CssTerm>> = null;
		m.node(g, 0, ctx, (j, terms) -> {
			if (j != m.items.length) return false;
			out = terms;
			return true;
		});
		steps = m.steps;
		return out;
	}

	// (a comma beside a term that matched nothing is left out too, Values 4 §2.6)
	function sequence(xs:Array<CssGrammar>, n:Int, i:Int, acc:Array<CssTerm>, ctx:Array<String>, k:(Int, Array<CssTerm>) -> Bool, empty = true,
			skipped = false):Bool {
		if (n == xs.length) return !skipped && k(i, acc);
		if (xs[n].match(Delim(",")) && empty && n > 0) return sequence(xs, n + 1, i, acc, ctx, k, true, false);
		if (xs[n].match(Delim(",")) && n + 1 < xs.length && sequence(xs, n + 1, i, acc, ctx, k, false, true)) return true;
		return node(xs[n], i, ctx, (j, terms) -> {
			if (skipped && j != i) return false;
			return sequence(xs, n + 1, j, acc.concat(terms), ctx, k, j == i);
		});
	}

	// || (all: &&): each at most once, in any order; the terms in the grammar's order
	function some(xs:Array<CssGrammar>, used:Array<Bool>, i:Int, parts:Array<{n:Int, terms:Array<CssTerm>}>, ctx:Array<String>, all:Bool,
			k:(Int, Array<CssTerm>) -> Bool):Bool {
		for (n in 0...xs.length) {
			if (used[n]) continue;
			var ok = node(xs[n], i, ctx, (j, terms) -> {
				// (an empty match, as a `?` makes, counts only where all must be there)
				if (j == i && !all) return false;
				var p = parts.concat([{n: n, terms: terms}]);
				var u = used.copy();
				u[n] = true;
				if (some(xs, u, j, p, ctx, all, k)) return true;
				return (!all || p.length == xs.length) && k(j, ordered(p));
			});
			if (ok) return true;
		}
		return false;
	}

	static function ordered(parts:Array<{n:Int, terms:Array<CssTerm>}>):Array<CssTerm> {
		var p = parts.copy();
		p.sort((a, b) -> a.n - b.n);
		return [for (x in p) for (t in x.terms) t];
	}

	function repeat(x:CssGrammar, min:Int, max:Int, comma:Bool, n:Int, i:Int, acc:Array<CssTerm>, ctx:Array<String>, k:(Int, Array<CssTerm>) -> Bool):Bool {
		if (max == -1 || n < max) {
			var start = i;
			if (comma && n > 0) start = delim(i, ",") ? i + 1 : -1;
			if (start >= 0 && node(x, start, ctx, (j, terms) -> {
				if (j == i) return false;
				return repeat(x, min, max, comma, n + 1, j, n > 0 && comma ? acc.concat([Delim(",")]).concat(terms) : acc.concat(terms), ctx, k);
			})) return true;
		}
		return n >= min && k(i, acc);
	}

	// ---- the primitive types

	function named(name:String, range:Null<CssRange>, i:Int, ctx:Array<String>, k:(Int, Array<CssTerm>) -> Bool):Bool {
		var v = i < items.length ? items[i] : null;
		switch name {
			case "length" | "percentage" | "length-percentage" | "number" | "integer" | "angle" | "angle-percentage" | "time" | "time-percentage" | "frequency"
				| "frequency-percentage" | "resolution" | "flex" | "dimension":
				var t = v == null ? null : numeric(name, v, range);
				return t != null && k(i + 1, [t]);
			case "zero":
				return switch tokenOf(v) {
					case Number(0, _, _): k(i + 1, [Number(0, true)]);
					case _: false;
				}
			case "string":
				return switch tokenOf(v) {
					case Str(s): k(i + 1, [Str(s)]);
					case _: false;
				}
			case "ident" | "ident-token":
				var w = ident(i);
				return w != null && k(i + 1, [Ident(w)]);
			case "custom-ident":
				var w = ident(i);
				return w != null && !WIDE.contains(Css.lower(w)) && !excluded.exists(Css.lower(w)) && k(i + 1, [Ident(w)]);
			case "dashed-ident":
				var w = ident(i);
				return w != null && StringTools.startsWith(w, "--") && k(i + 1, [Ident(w)]);
			case "url" | "url-token":
				switch v {
					case Token(t): switch t.kind {
							case Url(u): return k(i + 1, [Url(u, [])]);
							case _:
						}
					case Function(f, values, _, _) if (name == "url" && (Css.lower(f) == "url" || Css.lower(f) == "src")):
						var s = [for (x in values) if (!space(x)) x];
						if (s.length >= 1) switch tokenOf(s[0]) {
							case Str(u):
								var modifiers = [];
								for (m in s.slice(1)) switch m {
									case Token(t) if (t.kind.match(Ident(_))): modifiers.push(Css.serialize([m]));
									case Function(_, _, _, _): modifiers.push(Css.serialize([m]));
									case _: return false;
								}
								return k(i + 1, [Url(u, modifiers)]);
							case _:
						}
					case _:
				}
				return false;
			case "hash-token":
				return switch tokenOf(v) {
					case Hash(h, _): k(i + 1, [Raw("#" + h)]);
					case _: false;
				}
			case "number-token":
				return switch tokenOf(v) {
					case Number(n, int, _): k(i + 1, [Number(n, int)]);
					case _: false;
				}
			case "unicode-range-token":
				return switch tokenOf(v) {
					case UnicodeRange(_, _): k(i + 1, [Raw(Css.serialize([v]))]);
					case _: false;
				}
			case "declaration-value" | "any-value":
				var j = items.length;
				while (j > i) {
					if (k(j, [Raw(raw(i, j))])) return true;
					j--;
				}
				return false;
			case "url-modifier":
				return switch v {
					case Token(t) if (t.kind.match(Ident(_))): k(i + 1, [Raw(Css.serialize([v]))]);
					case Function(_, _, _, _): k(i + 1, [Raw(Css.serialize([v]))]);
					case _: false;
				}
			case "color" if (v != null && CssColors.handles(v)):
				var c = CssColors.parse(v);
				return c != null && k(i + 1, [Color(c)]);
			case _:
		}
		var t = CssGrammars.type(name, ctx);
		if (t == null || t.syntax == null) return false;
		var label = StringTools.endsWith(name, "()") ? name : '<$name>';
		return node(CssGrammars.of(t.syntax), i, ctx.concat([label]), tag ? (j, terms) -> k(j, [Part(label, terms)]) : k);
	}

	// A number or dimension of the type, a math function of it, or null.
	function numeric(name:String, v:CssValue, range:Null<CssRange>):Null<CssTerm> {
		var dim = switch name {
			case "length" | "length-percentage": 0;
			case "angle" | "angle-percentage": 1;
			case "time" | "time-percentage": 2;
			case "frequency" | "frequency-percentage": 3;
			case "resolution": 4;
			case "flex": 5;
			case "dimension": 99;
			case _: -2;
		}
		var percent = name == "percentage" || StringTools.endsWith(name, "-percentage");
		inline function within(x:Float, unit:String):Bool {
			if (range == null) return true;
			var c = range.unit == "" ? {value: x, unit: unit} : CssCalc.canonical(x, unit);
			var lo = range.min, hi = range.max;
			if (range.unit != "") {
				var l = CssCalc.canonical(lo, range.unit), h = CssCalc.canonical(hi, range.unit);
				if (l != null) lo = l.value;
				if (h != null) hi = h.value;
			}
			return c != null && c.value >= lo && c.value <= hi;
		}
		switch v {
			case Token(t):
				switch t.kind {
					case Number(n, int, _):
						if (name == "number" && within(n, "")) return Number(n, false);
						if (name == "integer" && int && within(n, "")) return Number(n, true);
						// (a unitless 0 is a length, never another dimension)
						if (n == 0 && dim == 0) return Dimension(0, "px");
						return null;
					case Percentage(n, _, _): return percent && within(n, "") ? Percentage(n) : null;
					case Dimension(n, _, _, unit):
						var u = Css.lower(unit), b = CssCalc.base(u);
						if (dim == 99 || b == dim && dim >= 0) return within(n, u) ? Dimension(n, u) : null;
						return null;
					case _: return null;
				}
			case Function(f, _, _, _) if (CssCalc.isMath(f)):
				var c = CssCalc.parse(v);
				// (a percentage where none may be is invalid, even inside sign())
				if (c == null || !percent && CssCalc.hasPercent(c)) return null;
				var type = CssCalc.type(c, percent && dim >= 0 ? dim : -1);
				if (type == null) return null;
				var ok = switch name {
					case "number" | "integer": CssCalc.isNumber(type);
					case "percentage": CssCalc.isBase(type, 6);
					case "dimension": !CssCalc.isNumber(type);
					case _: CssCalc.isBase(type, dim) || percent && CssCalc.isBase(type, 6);
				}
				return ok ? Calc(CssCalc.simplify(c), name, range) : null;
			case _: return null;
		}
	}

	// ---- items

	function tokenOf(v:Null<CssValue>):Null<CssTokenKind>
		return switch v {
			case Token(t): t.kind;
			case _: null;
		}

	function ident(i:Int):Null<String>
		return i >= items.length ? null : switch items[i] {
			case Token(t): switch t.kind {
					case Ident(w): w;
					case _: null;
				}
			case _: null;
		}

	function delim(i:Int, text:String):Bool
		return i < items.length && switch items[i] {
			case Token(t): switch t.kind {
					case Comma: text == ",";
					case Colon: text == ":";
					case Semicolon: text == ";";
					case Delim(d): d == text;
					case _: false;
				}
			case _: false;
		}

	static function opens(t:CssToken, open:String):Bool
		return switch t.kind {
			case OpenSquare: open == "[";
			case OpenParen: open == "(";
			case OpenCurly: open == "{";
			case _: false;
		}

	function raw(i:Int, j:Int):String
		return StringTools.trim(Css.serialize(all.slice(at[i], at[j - 1] + 1)));

	static function space(v:CssValue):Bool
		return switch v {
			case Token(t): t.kind.match(Whitespace);
			case _: false;
		}
}

private class TooLong extends haxe.Exception {
	public function new()
		super("the match took too long");
}
