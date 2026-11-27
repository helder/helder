package helder.css;

import helder.css.CssCounterAlgorithms;
import helder.css.CssSheet;

using StringTools;

// A document's counter styles (Counter Styles 3): the predefined ones
// (ua/counter-styles.css's rules and the CJK and Ethiopic longhand
// algorithms) and its @counter-style rules, a later rule of a name over
// an earlier one and over a predefined style. A number is formatted by
// its style's system, within its range (else by its fallback), with its
// negative sign and pad; a marker adds the prefix and suffix.
//
//   var styles = new CssCounterStyles(cssStyles.counterStyles);
//   styles.format(14, "lower-roman");  // "xiv"
//   styles.marker(3, "decimal");       // "3. "
class CssCounterStyles {
	final defined = new Map<String, Style>();

	public function new(?rules:Array<CssCounterStyle>) {
		for (r in predefined()) defined.set(r.name, r);
		for (r in rules ?? []) {
			var s = compile(r.name, r.descriptors);
			if (s != null) defined.set(r.name, s);
		}
	}

	// Whether the name is a counter style here (a predefined one in any case).
	public function exists(name:String):Bool
		return find(name) != null;

	// The number's representation in the style (counter()'s), no prefix nor suffix.
	public function format(value:Int, name:String):String
		return represent(value, find(name) ?? find("decimal"), 0, this);

	// The number as a list item's marker: the prefix, the representation, the suffix.
	public function marker(value:Int, name:String):String {
		var s = find(name) ?? find("decimal");
		return s.prefix + represent(value, s, 0, this) + s.suffix;
	}

	// symbols()'s anonymous style (Counter Styles 3 §9): a system (symbolic when
	// left out) and its symbols; a space after it as a marker.
	public static function symbols(system:String, list:Array<String>, value:Int, asMarker:Bool):String {
		var s = new Style("");
		s.system = switch system {
			case "cyclic": Cyclic;
			case "numeric": Numeric;
			case "alphabetic": Alphabetic;
			case "fixed": Fixed(1);
			case _: Symbolic;
		}
		s.symbols = list;
		s.suffix = " ";
		if (!valid(s)) return asMarker ? "" : "";
		var text = represent(value, s, 0, null);
		return asMarker ? s.prefix + text + s.suffix : text;
	}

	function find(name:String):Null<Style> {
		var s = defined.get(name);
		if (s != null) return resolved(s, 0);
		// (the predefined names, in any case)
		var lower = Css.lower(name);
		return lower != name && PREDEFINED_NAMES.contains(lower) ? resolved(defined.get(lower), 0) : null;
	}

	// (extends: the extended style's system and symbols, this one's other
	// descriptors over its; a loop, or a style that isn't there, decimal's)
	function resolved(s:Null<Style>, depth:Int, ?seen:Array<String>):Null<Style> {
		if (s == null) return null;
		switch s.system {
			case Extends(base):
				// (a style in a loop of extends extends decimal, Counter Styles 3 §3.1.7)
				var chain = (seen ?? []).concat([s.name]);
				var inLoop = loops(s.name);
				var next = defined.get(base) ?? (PREDEFINED_NAMES.contains(Css.lower(base)) ? defined.get(Css.lower(base)) : null);
				var b = inLoop || chain.contains(base) || depth > 32 ? null : resolved(next, depth + 1, chain);
				if (b == null) b = defined.get("decimal");
				var out = new Style(s.name);
				out.system = b.system;
				out.symbols = b.symbols;
				out.additive = b.additive;
				out.algorithm = b.algorithm;
				out.negative = s.has("negative") ? s.negative : b.negative;
				out.prefix = s.has("prefix") ? s.prefix : b.prefix;
				out.suffix = s.has("suffix") ? s.suffix : b.suffix;
				out.range = s.has("range") ? s.range : b.range;
				out.pad = s.has("pad") ? s.pad : b.pad;
				out.fallback = s.has("fallback") ? s.fallback : b.fallback;
				out.given = s.given;
				return out;
			case _: return s;
		}
	}

	// (whether following the name's extends comes back to it)
	function loops(name:String):Bool {
		var at = name, seen = [name];
		while (true) {
			var s = defined.get(at);
			if (s == null) return false;
			switch s.system {
				case Extends(base):
					if (base == name) return true;
					// (into a loop it isn't in)
					if (seen.contains(base)) return false;
					seen.push(base);
					at = base;
				case _: return false;
			}
		}
	}

	// (Counter Styles 3 §4: in range, the system's text, else the fallback's;
	// the negative sign around it and the pad within)
	static function represent(value:Int, s:Style, depth:Int, styles:Null<CssCounterStyles>):String {
		inline function fallback():String {
			var f = styles == null || depth > 32 ? null : styles.find(s.fallback);
			return f == null || f == s ? decimal(value, s) : represent(value, f, depth + 1, styles);
		}
		if (!inRange(value, s)) return fallback();
		var negative = value < 0 && usesNegative(s);
		var text = system(negative ? -value : value, s);
		if (text == null) return fallback();
		if (!negative && value < 0 && !usesNegative(s) && text == null) return fallback();
		var before = negative ? s.negative[0] : "", after = negative ? s.negative[1] : "";
		if (s.pad != null) {
			var length = graphemes(before) + graphemes(text) + graphemes(after);
			if (length < s.pad.length) text = [for (_ in 0...s.pad.length - length) s.pad.symbol].join("") + text;
		}
		return before + text + after;
	}

	// (decimal's, when nothing else can: what every fallback chain ends in)
	static function decimal(value:Int, s:Style):String
		return Std.string(value);

	static function usesNegative(s:Style):Bool
		return switch s.system {
			case Symbolic | Alphabetic | Numeric | Additive: true;
			case Algorithm(_): s.algorithm != null && s.algorithm.negative;
			case _: false;
		}

	static function inRange(value:Int, s:Style):Bool {
		if (s.range == null) return switch s.system {
			case Alphabetic | Symbolic: value >= 1;
			case Additive: value >= 0;
			case Algorithm(_): s.algorithm == null || value >= s.algorithm.min && value <= s.algorithm.max;
			case _: true;
		}
		for (r in s.range) if (value >= r.lo && value <= r.hi) return true;
		return false;
	}

	// (the system's text for a value in range, the negative sign apart; null: it has none)
	static function system(value:Int, s:Style):Null<String> {
		var symbols = s.symbols, n = symbols.length;
		return switch s.system {
			case Cyclic: symbols[mod(value - 1, n)];
			case Fixed(first): value >= first && value - first < n ? symbols[value - first] : null;
			case Symbolic:
				if (value < 1) return null;
				var sym = symbols[mod(value - 1, n)], count = Std.int(Math.ceil(value / n));
				[for (_ in 0...count) sym].join("");
			case Alphabetic:
				if (value < 1) return null;
				var out = "", v = value;
				while (v != 0) {
					v--;
					out = symbols[v % n] + out;
					v = Std.int(v / n);
				}
				out;
			case Numeric:
				if (value == 0) return symbols[0];
				var out = "", v = value;
				while (v != 0) {
					out = symbols[v % n] + out;
					v = Std.int(v / n);
				}
				out;
			case Additive:
				var tuples = s.additive;
				if (value == 0) {
					for (t in tuples) if (t.weight == 0) return t.symbol;
					return null;
				}
				var out = new StringBuf(), v = value;
				for (t in tuples) {
					if (t.weight == 0 || t.weight > v) continue;
					var reps = Std.int(v / t.weight);
					for (_ in 0...reps) out.add(t.symbol);
					v -= reps * t.weight;
					if (v == 0) return out.toString();
				}
				v == 0 ? out.toString() : null;
			case Algorithm(name): CssCounterAlgorithms.format(name, value);
			case Extends(_): null;
		}
	}

	static inline function mod(a:Int, n:Int):Int {
		var r = a % n;
		return r < 0 ? r + n : r;
	}

	// (grapheme clusters, near enough: code points but combining marks, joiners and variation selectors)
	static function graphemes(s:String):Int {
		var n = 0;
		var k = 0;
		while (k < s.length) {
			var c = StringTools.fastCodeAt(s, k);
			var cp = c;
			if (c >= 0xD800 && c <= 0xDBFF && k + 1 < s.length) {
				cp = ((c - 0xD800) << 10) + (StringTools.fastCodeAt(s, k + 1) - 0xDC00) + 0x10000;
				k++;
			}
			k++;
			if (!(cp >= 0x300 && cp <= 0x36F || cp >= 0x1AB0 && cp <= 0x1AFF || cp >= 0x1DC0 && cp <= 0x1DFF || cp >= 0x20D0 && cp <= 0x20FF
				|| cp >= 0xFE20 && cp <= 0xFE2F || cp >= 0xFE00 && cp <= 0xFE0F || cp == 0x200D))
				n++;
		}
		return n;
	}

	// ---- the rules

	static var PREDEFINED:Null<Array<Style>>;
	public static final PREDEFINED_NAMES:Array<String> = [];

	static function predefined():Array<Style> {
		if (PREDEFINED != null) return PREDEFINED;
		var out = [];
		#if !macro
		// (ua/counter-styles.css's styles, compiled at build time and read
		// back: no parser linked, nor a sheet's decoder)
		var r = new CssPacked(packed());
		for (_ in 0...r.uint()) {
			var s = new Style(r.str());
			s.system = switch r.uint() {
				case 0: Cyclic;
				case 1: Numeric;
				case 2: Alphabetic;
				case 3: Symbolic;
				case 4: Additive;
				case 5: Fixed(r.int());
				case 6: Extends(r.str());
				case _: Algorithm(r.str());
			}
			s.symbols = r.strs();
			s.additive = r.list(() -> {
				var w = r.int();
				{weight: w, symbol: r.str()};
			});
			s.negative = r.strs();
			s.prefix = r.str();
			s.suffix = r.str();
			s.range = r.nlist(() -> {
				var lo = r.int();
				({lo: lo, hi: r.int()} : CssCounterRange);
			});
			if (r.bool()) {
				var length = r.int();
				s.pad = {length: length, symbol: r.str()};
			}
			s.fallback = r.str();
			for (k in r.strs()) s.given.set(k, true);
			out.push(s);
		}
		#end
		for (a in CssCounterAlgorithms.STYLES) {
			var s = new Style(a.name);
			s.system = Algorithm(a.name);
			s.algorithm = a;
			s.suffix = a.suffix;
			s.negative = [a.minus, ""];
			s.fallback = a.fallback;
			out.push(s);
		}
		for (s in out) PREDEFINED_NAMES.push(s.name);
		return PREDEFINED = out;
	}

	// (ua/counter-styles.css's @counter-style rules, parsed and compiled when
	// the program is: CssPacked's string, read by predefined)
	static macro function packed():haxe.macro.Expr {
		var file = haxe.io.Path.join([haxe.io.Path.directory(haxe.macro.Context.getPosInfos(haxe.macro.Context.currentPos()).file), "ua/counter-styles.css"]);
		haxe.macro.Context.registerModuleDependency(haxe.macro.Context.getLocalModule(), file);
		var styles = [];
		for (r in CssSheet.parse(sys.io.File.getContent(file), UserAgent).rules) switch r {
			case CounterStyle(c):
				var s = compile(c.name, c.descriptors);
				if (s != null) styles.push(s);
			case _:
		}
		var w = new CssPackedWriter();
		w.list(styles, s -> {
			w.str(s.name);
			switch s.system {
				case Cyclic: w.uint(0);
				case Numeric: w.uint(1);
				case Alphabetic: w.uint(2);
				case Symbolic: w.uint(3);
				case Additive: w.uint(4);
				case Fixed(first):
					w.uint(5);
					w.int(first);
				case Extends(name):
					w.uint(6);
					w.str(name);
				case Algorithm(name):
					w.uint(7);
					w.str(name);
			}
			w.list(s.symbols, w.str);
			w.list(s.additive, a -> {
				w.int(a.weight);
				w.str(a.symbol);
			});
			w.list(s.negative, w.str);
			w.str(s.prefix);
			w.str(s.suffix);
			w.nlist(s.range, x -> {
				w.int(x.lo);
				w.int(x.hi);
			});
			w.bool(s.pad != null);
			if (s.pad != null) {
				w.int(s.pad.length);
				w.str(s.pad.symbol);
			}
			w.str(s.fallback);
			w.list([for (k in s.given.keys()) k], w.str);
		});
		return macro $v{w.toString()};
	}

	// A rule's style; null when it doesn't define one (a system without the
	// symbols it needs, extends with symbols, a name that can't be one).
	public static function compile(name:String, descriptors:Array<CssDeclaration>):Null<Style> {
		var s = new Style(name);
		for (d in descriptors) {
			var key = Css.lower(d.name);
			var v = CssCounterDescriptors.parse(key, d.value);
			if (v == null) continue;
			s.given.set(key, true);
			switch v {
				case System(x): s.system = x;
				case Symbols(x): s.symbols = x;
				case AdditiveSymbols(x): s.additive = x;
				case Negative(a, b): s.negative = [a, b];
				case Prefix(x): s.prefix = x;
				case Suffix(x): s.suffix = x;
				case Range(x): s.range = x;
				case Pad(n, symbol): s.pad = {length: n, symbol: symbol};
				case Fallback(x): s.fallback = x;
				case SpeakAs:
			}
		}
		return valid(s) ? s : null;
	}

	// (Counter Styles 3 §3.1: the symbols each system needs; extends takes none)
	static function valid(s:Style):Bool
		return switch s.system {
			case Cyclic | Fixed(_) | Symbolic: s.symbols.length >= 1 && !s.has("additive-symbols");
			case Alphabetic | Numeric: s.symbols.length >= 2 && !s.has("additive-symbols");
			case Additive: s.additive.length >= 1 && !s.has("symbols");
			case Extends(_): !s.has("symbols") && !s.has("additive-symbols");
			case Algorithm(_): true;
		}
}

enum CssCounterSystem {
	Cyclic;
	Numeric;
	Alphabetic;
	Symbolic;
	Additive;
	Fixed(first:Int);
	Extends(name:String);
	// a predefined style's algorithm (the CJK and Ethiopic longhands)
	Algorithm(name:String);
}

typedef CssCounterRange = {lo:Int, hi:Int}

@:allow(helder.css)
private class Style {
	public final name:String;
	public var system:CssCounterSystem = Symbolic;
	public var symbols:Array<String> = [];
	public var additive:Array<{weight:Int, symbol:String}> = [];
	public var negative = ["-", ""];
	public var prefix = "";
	public var suffix = ". ";
	public var range:Null<Array<CssCounterRange>> = null;
	public var pad:Null<{length:Int, symbol:String}> = null;
	public var fallback = "decimal";
	public var algorithm:Null<CssCounterAlgorithm> = null;
	public var given = new Map<String, Bool>();

	public function new(name:String)
		this.name = name;

	public inline function has(d:String):Bool
		return given.exists(d);
}
