package helder.css;

import helder.css.CssCalc;
import helder.css.CssCounterStyles;

enum CssCounterDescriptor {
	System(system:CssCounterSystem);
	Symbols(symbols:Array<String>);
	AdditiveSymbols(tuples:Array<{weight:Int, symbol:String}>);
	Negative(before:String, after:String);
	Prefix(symbol:String);
	Suffix(symbol:String);
	// null: auto
	Range(ranges:Null<Array<CssCounterRange>>);
	Pad(length:Int, symbol:String);
	Fallback(name:String);
	SpeakAs;
}

// @counter-style's descriptors read (Counter Styles 3 §3): null where a
// value is invalid, which leaves the descriptor out. A <symbol> is a
// string or an identifier (an image's is left empty: a marker's text
// can't be one); an <integer> may be a math function.
class CssCounterDescriptors {
	public static function parse(name:String, values:Array<CssValue>):Null<CssCounterDescriptor> {
		var v = [for (x in values) if (!x.match(Token(_.kind => Whitespace))) x];
		return switch name {
			case "system": system(v);
			case "symbols":
				var out = [for (x in v) symbol(x)];
				out.length > 0 && !out.contains(null) ? Symbols(out) : null;
			case "additive-symbols":
				var tuples = [];
				for (part in commas(v)) {
					var t = tuple(part);
					if (t == null || tuples.length > 0 && t.weight >= tuples[tuples.length - 1].weight) return null;
					tuples.push(t);
				}
				tuples.length > 0 ? AdditiveSymbols(tuples) : null;
			case "negative":
				var a = v.length >= 1 ? symbol(v[0]) : null, b = v.length == 2 ? symbol(v[1]) : "";
				v.length >= 1 && v.length <= 2 && a != null && b != null ? Negative(a, b) : null;
			case "prefix": v.length == 1 && symbol(v[0]) != null ? Prefix(symbol(v[0])) : null;
			case "suffix": v.length == 1 && symbol(v[0]) != null ? Suffix(symbol(v[0])) : null;
			case "range": range(v);
			case "pad":
				var t = tuple(v);
				t == null ? null : Pad(t.weight, t.symbol);
			case "fallback": v.length == 1 && styleName(v[0]) != null ? Fallback(styleName(v[0])) : null;
			case "speak-as": v.length == 1 && styleName(v[0]) != null ? SpeakAs : null;
			case _: null;
		}
	}

	static function system(v:Array<CssValue>):Null<CssCounterDescriptor> {
		var word = v.length > 0 ? ident(v[0]) : null;
		if (word == null) return null;
		return switch [Css.lower(word), v.length] {
			case ["cyclic", 1]: System(Cyclic);
			case ["numeric", 1]: System(Numeric);
			case ["alphabetic", 1]: System(Alphabetic);
			case ["symbolic", 1]: System(Symbolic);
			case ["additive", 1]: System(Additive);
			case ["fixed", 1]: System(Fixed(1));
			case ["fixed", 2]:
				var n = integer(v[1]);
				n == null ? null : System(Fixed(n));
			case ["extends", 2]:
				var n = styleName(v[1]);
				n == null ? null : System(Extends(n));
			case _: null;
		}
	}

	// ([[<integer> | infinite]{2}]# | auto: a lower bound past its upper invalidates all)
	static function range(v:Array<CssValue>):Null<CssCounterDescriptor> {
		if (v.length == 1 && ident(v[0]) != null && Css.lower(ident(v[0])) == "auto") return Range(null);
		var out = [];
		for (part in commas(v)) {
			if (part.length != 2) return null;
			var lo = bound(part[0], true), hi = bound(part[1], false);
			if (lo == null || hi == null || lo > hi) return null;
			out.push({lo: lo, hi: hi});
		}
		return out.length > 0 ? Range(out) : null;
	}

	static function bound(v:CssValue, lower:Bool):Null<Int> {
		var w = ident(v);
		if (w != null) return Css.lower(w) == "infinite" ? (lower ? MIN : MAX) : null;
		return integer(v);
	}

	public static inline var MIN = -2147483647;
	public static inline var MAX = 2147483647;

	// (<integer [0,∞]> && <symbol>: either order)
	static function tuple(part:Array<CssValue>):Null<{weight:Int, symbol:String}> {
		if (part.length != 2) return null;
		for (k in 0...2) {
			var n = integer(part[k]), s = symbol(part[1 - k]);
			if (n != null && s != null && !isInteger(part[1 - k])) return n < 0 ? null : {weight: n, symbol: s};
		}
		return null;
	}

	static function isInteger(v:CssValue):Bool
		return integer(v) != null;

	static function commas(v:Array<CssValue>):Array<Array<CssValue>> {
		var out = [[]];
		for (x in v) if (x.match(Token(_.kind => Comma))) out.push([]) else out[out.length - 1].push(x);
		return out;
	}

	// (a string, an identifier, an image: its text)
	static function symbol(v:CssValue):Null<String>
		return switch v {
			case Token(_.kind => Str(s)): s;
			case Token(_.kind => Ident(w)) if (!WIDE.contains(Css.lower(w))): w;
			case Token(_.kind => Url(_)): "";
			case Function(f, _, _, _) if (IMAGES.contains(Css.lower(f))): "";
			case _: null;
		}

	static function ident(v:CssValue):Null<String>
		return switch v {
			case Token(_.kind => Ident(w)): w;
			case _: null;
		}

	// (<counter-style-name>: a custom ident but none)
	static function styleName(v:CssValue):Null<String> {
		var w = ident(v);
		return w == null || WIDE.contains(Css.lower(w)) || Css.lower(w) == "none" ? null : w;
	}

	static function integer(v:CssValue):Null<Int>
		return switch v {
			case Token(_.kind => Number(n, true, _)): Std.int(n);
			case Function(f, _, _, _) if (CssCalc.isMath(Css.lower(f))):
				var node = CssCalc.parse(v);
				if (node == null) return null;
				switch CssCalc.simplify(node, {fontSize: 16, rootFontSize: 16}) {
					case Value(n, ""): Math.round(n);
					case _: null;
				}
			case _: null;
		}

	static final WIDE = ["initial", "inherit", "unset", "revert", "revert-layer", "default"];
	static final IMAGES = ["url", "image", "image-set", "linear-gradient", "radial-gradient", "conic-gradient", "repeating-linear-gradient",
		"repeating-radial-gradient", "repeating-conic-gradient"];

	// The descriptor as CSSOM writes it (the syntax tests'): its values as
	// written, a tuple's integer first; null when it's invalid.
	public static function text(name:String, values:Array<CssValue>):Null<String> {
		if (parse(name, values) == null) return null;
		var v = [for (x in values) if (!x.match(Token(_.kind => Whitespace))) x];
		if (name == "additive-symbols" || name == "pad")
			return [for (part in commas(v)) (isInteger(part[0]) ? part : [part[1], part[0]]).map(component).join(" ")].join(", ");
		return [for (part in commas(v)) part.map(component).join(" ")].join(", ");
	}

	static function component(v:CssValue):String
		return switch v {
			case Token(_.kind => Str(s)): CssText.string(s);
			case Token(_.kind => Url(u)): 'url(${CssText.string(u)})';
			case _: StringTools.trim(Css.serialize([v]));
		}
}
