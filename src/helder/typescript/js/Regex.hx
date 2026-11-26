package helder.typescript.js;

import helder.typescript.js.Values;
import helder.typescript.js.Lib.*;

enum RxNode {
	RChar(c:Int);
	RAny;
	// (ranges: inclusive pairs)
	RSet(ranges:Array<Int>, negated:Bool);
	RStart;
	REnd;
	RWord(negated:Bool);
	RGroup(index:Int, node:RxNode);
	RLook(behind:Bool, negated:Bool, node:RxNode);
	RBackref(index:Int);
	RNamedBackref(name:String);
	RRepeat(node:RxNode, min:Int, max:Int, greedy:Bool, firstGroup:Int, lastGroup:Int);
	RSeq(items:Array<RxNode>);
	RAlt(options:Array<RxNode>);
}

// (a pattern's syntax error: a SyntaxError at run time, a diagnostic when
// the frontend checks a literal: check)
class RegexSyntax {
	public final message:String;

	public function new(message:String) this.message = message;
}

class JsRegExp extends JsObject {
	public var source:String;
	public var flags:String;
	public var program:RxNode;
	public var groupCount:Int;
	public var groupNames:Array<String>;
	// (shared by the RegExps of one source and flags: Regex.compile)
	public var compiled:Compiled;
	// (the matcher of the last string searched, kept for the next exec on it)
	public var matcher:Regex = null;
	override public function tag():String return "RegExp";
}

// A pattern parsed, with what its matches need: the flags as bits, the code
// units a match can start with (inclusive pairs; null: any, or the empty
// string matches), whether it starts at a line's start.
class Compiled {
	public final program:RxNode;
	public final groups:Int;
	public final names:Array<String>;
	public final bits:Int;
	public final flags:String;
	public final first:Array<Int>;
	public final anchored:Bool;

	public function new(program:RxNode, groups:Int, names:Array<String>, bits:Int, flags:String, first:Array<Int>, anchored:Bool) {
		this.program = program;
		this.groups = groups;
		this.names = names;
		this.bits = bits;
		this.flags = flags;
		this.first = first;
		this.anchored = anchored;
	}
}

// Regular expressions: a parser for JavaScript pattern syntax and a
// backtracking matcher (continuation passing), with the RegExp built-ins.
class Regex {
	public static var RegExpProto:JsObject;
	public static function isRegExp(v:Dynamic):Bool return Std.isOfType(v, JsRegExp);

	// flags as bits
	static inline var GLOBAL = 1;
	static inline var IGNORE_CASE = 2;
	static inline var MULTILINE = 4;
	static inline var DOT_ALL = 8;
	static inline var UNICODE = 16; // u or v
	static inline var STICKY = 32;
	static inline var INDICES = 64;

	// Parsing.
	var p:String;
	var i = 0;
	var unicode:Bool;
	var groups = 0;
	var names:Array<String> = [];
	var hasNamed = false;
	function new(p:String, unicode:Bool) {
		this.p = p;
		this.unicode = unicode;
	}

	function fail(message:String):Dynamic throw new RegexSyntax(message);

	function peek():Int return i < p.length ? code(i) : -1;

	function code(at:Int):Int {
		var c = p.charCodeAt(at);
		if (unicode && c >= 0xd800 && c <= 0xdbff && at + 1 < p.length) {
			var d = p.charCodeAt(at + 1);
			if (d >= 0xdc00 && d <= 0xdfff) return (c - 0xd800) * 1024 + (d - 0xdc00) + 0x10000;
		}
		return c;
	}

	function next():Int {
		var c = code(i);
		i += c > 0xffff ? 2 : 1;
		return c;
	}

	function eat(c:Int):Bool {
		if (peek() == c) {
			i++;
			return true;
		}
		return false;
	}

	function disjunction():RxNode {
		var options = [sequence()];
		while (eat("|".code)) options.push(sequence());
		return options.length == 1 ? options[0] : RAlt(options);
	}

	function sequence():RxNode {
		var items:Array<RxNode> = [];
		while (i < p.length && peek() != "|".code && peek() != ")".code) {
			var groupStart = groups;
			var atom = term();
			if (atom == null) continue;
			items.push(quantified(atom, groupStart));
		}
		return items.length == 1 ? items[0] : RSeq(items);
	}

	function quantified(atom:RxNode, groupStart:Int):RxNode {
		var min = -1, max = -1;
		var c = peek();
		if (c == "*".code) {
			i++;
			min = 0;
			max = -1;
		}
		else if (c == "+".code) {
			i++;
			min = 1;
			max = -1;
		}
		else if (c == "?".code) {
			i++;
			min = 0;
			max = 1;
		}
		else if (c == "{".code) {
			var save = i;
			i++;
			var a = number();
			if (a < 0) {
				i = save;
				if (unicode) fail("Incomplete quantifier");
				return atom;
			}
			min = a;
			max = a;
			if (eat(",".code)) {
				max = peek() == "}".code ? -1 : number();
			}
			if (!eat("}".code)) {
				i = save;
				if (unicode) fail("Incomplete quantifier");
				min = -1;
				return atom;
			}
			if (max >= 0 && max < min) fail("numbers out of order in {} quantifier");
		}
		else return atom;
		switch (atom) {
			case RStart | REnd | RWord(_): fail("Nothing to repeat");
			case RLook(true, _, _): fail("Invalid quantifier");
			case _:
		}
		var greedy = !eat("?".code);
		return RRepeat(atom, min, max, greedy, groupStart + 1, groups);
	}

	function number():Int {
		var start = i;
		var n = 0;
		while (i < p.length && peek() >= 48 && peek() <= 57) {
			n = Std.int(Math.min(n * 10 + (peek() - 48), 2147483647));
			i++;
		}
		return i == start ? -1 : n;
	}

	function term():RxNode {
		var c = next();
		switch (c) {
			case "^".code: return RStart;
			case "$".code: return REnd;
			case ".".code: return RAny;
			case "(".code:
				if (eat("?".code)) {
					var k = next();
					if (k == ":".code) {
						var n = disjunction();
						if (!eat(")".code)) fail("Unterminated group");
						return RGroup(-1, n);
					}
					if (k == "=".code || k == "!".code) {
						var n = disjunction();
						if (!eat(")".code)) fail("Unterminated group");
						return RLook(false, k == "!".code, n);
					}
					if (k == "<".code) {
						if (eat("=".code) || peek() == "!".code && eat("!".code)) {
							var negated = p.charCodeAt(i - 1) == "!".code;
							var n = disjunction();
							if (!eat(")".code)) fail("Unterminated group");
							return RLook(true, negated, n);
						}
						var close = p.indexOf(">", i);
						if (close < 0) fail("Invalid capture group name");
						var name = p.substring(i, close);
						i = close + 1;
						if (names.indexOf(name) >= 0) fail("Duplicate capture group name");
						var index = ++groups;
						while (names.length < index) names.push(null);
						names[index - 1] = name;
						hasNamed = true;
						var n = disjunction();
						if (!eat(")".code)) fail("Unterminated group");
						return RGroup(index, n);
					}
					return fail("Invalid group");
				}
				var index = ++groups;
				while (names.length < index) names.push(null);
				var n = disjunction();
				if (!eat(")".code)) fail("Unterminated group");
				return RGroup(index, n);
			case ")".code: return fail("Unmatched ')'");
			case "[".code: return characterClass();
			case "*".code | "+".code | "?".code: return fail("Nothing to repeat");
			case "{".code:
				if (unicode) fail("Lone quantifier brackets");
				return RChar(c);
			case "}".code | "]".code:
				if (unicode) fail("Lone quantifier brackets");
				return RChar(c);
			case "\\".code: return atomEscape();
			case _: return RChar(c);
		}
	}
	static var digitRanges = [48, 57];
	static var wordRanges = [48, 57, 65, 90, 95, 95, 97, 122];
	static var spaceRanges = [9, 13, 32, 32, 160, 160, 0x1680, 0x1680, 0x2000, 0x200a, 0x2028, 0x2029, 0x202f, 0x202f, 0x205f, 0x205f, 0x3000, 0x3000, 0xfeff, 0xfeff];
	function atomEscape():RxNode {
		if (i >= p.length) fail("\\ at end of pattern");
		var c = peek();
		if (c == "b".code) {
			i++;
			return RWord(false);
		}
		if (c == "B".code) {
			i++;
			return RWord(true);
		}
		if (c >= "1".code && c <= "9".code) {
			var n = number();
			return RBackref(n);
		}
		if (c == "k".code && (unicode || hasNamedAhead())) {
			i++;
			if (!eat("<".code)) fail("Invalid named reference");
			var close = p.indexOf(">", i);
			if (close < 0) fail("Invalid named reference");
			var name = p.substring(i, close);
			i = close + 1;
			return RNamedBackref(name);
		}
		var set = classEscape();
		if (set != null) return set;
		return RChar(characterEscape());
	}

	function hasNamedAhead():Bool return p.indexOf("(?<") >= 0 && p.indexOf("(?<=") != p.indexOf("(?<") || hasNamed;

	// (\d \D \w \W \s \S \p{...}: a set, else null)
	function classEscape():RxNode {
		var c = peek();
		switch (c) {
			case "d".code | "D".code:
				i++;
				return RSet(digitRanges, c == "D".code);
			case "w".code | "W".code:
				i++;
				return RSet(wordRanges, c == "W".code);
			case "s".code | "S".code:
				i++;
				return RSet(spaceRanges, c == "S".code);
			case "p".code | "P".code if (unicode):
				i++;
				if (!eat("{".code)) fail("Invalid property name");
				var close = p.indexOf("}", i);
				if (close < 0) fail("Invalid property name");
				var name = p.substring(i, close);
				i = close + 1;
				return RSet(property(name), c == "P".code);
			case _: return null;
		}
	}

	// the code points of \p{name}: UnicodeProperties.lookup, which a program
	// whose patterns name properties installs (lower.Features)
	public static var properties:Null<String->Null<Array<Int>>> = null;

	function property(name:String):Array<Int> {
		var ranges = properties == null ? null : properties(name);
		return ranges ?? fail("Invalid property name");
	}

	function characterEscape():Int {
		var c = next();
		return switch (c) {
			case "n".code: 10;
			case "r".code: 13;
			case "t".code: 9;
			case "v".code: 11;
			case "f".code: 12;
			case "0".code if (!(peek() >= 48 && peek() <= 57)): 0;
			case "c".code:
				var l = peek();
				if (l >= 65 && l <= 90 || l >= 97 && l <= 122) {
					i++;
					l % 32;
				} else {
					i--;
					92;
				}
			case "x".code:
				var h = hex(2);
				if (h < 0) {
					if (unicode) fail("Invalid escape");
					"x".code;
				} else h;
			case "u".code:
				if (unicode && eat("{".code)) {
					var close = p.indexOf("}", i);
					var v = Std.parseInt("0x" + p.substring(i, close));
					i = close + 1;
					if (v == null || v > 0x10ffff) fail("Invalid Unicode escape");
					v;
				}
				else {
					var h = hex(4);
					if (h < 0) {
						if (unicode) fail("Invalid Unicode escape");
						"u".code;
					}
					else if (unicode && h >= 0xd800 && h <= 0xdbff && p.substr(i, 2) == "\\u") {
						var save = i;
						i += 2;
						var l = hex(4);
						if (l >= 0xdc00 && l <= 0xdfff) (h - 0xd800) * 1024 + (l - 0xdc00) + 0x10000; else {
							i = save;
							h;
						}
					}
					else h;
				}
			case _:
				if (unicode && !(c == "^".code || c == "$".code || c == "\\".code || c == ".".code || c == "*".code || c == "+".code || c == "?".code || c == "(".code || c == ")".code || c == "[".code || c == "]".code || c == "{".code || c == "}".code || c == "|".code || c == "/".code || c == "-".code)) fail("Invalid escape");
				c;
		};
	}

	function hex(n:Int):Int {
		var v = 0;
		for (k in 0...n) {
			if (i + k >= p.length) return -1;
			var c = p.charCodeAt(i + k);
			var d = c >= 48 && c <= 57 ? c - 48 : c >= 65 && c <= 70 ? c - 55 : c >= 97 && c <= 102 ? c - 87 : -1;
			if (d < 0) return -1;
			v = v * 16 + d;
		}
		i += n;
		return v;
	}

	function characterClass():RxNode {
		var negated = eat("^".code);
		var ranges:Array<Int> = [];
		while (true) {
			if (i >= p.length) fail("Unterminated character class");
			if (eat("]".code)) break;
			var lo = classAtom(ranges);
			if (lo < 0) continue;
			if (peek() == "-".code && i + 1 < p.length && p.charCodeAt(i + 1) != "]".code) {
				i++;
				var hi = classAtom(ranges);
				if (hi < 0) {
					if (unicode) fail("Invalid character class");
					ranges.push(lo);
					ranges.push(lo);
					ranges.push(45);
					ranges.push(45);
					continue;
				}
				if (hi < lo) fail("Range out of order in character class");
				ranges.push(lo);
				ranges.push(hi);
			}
			else {
				ranges.push(lo);
				ranges.push(lo);
			}
		}
		return RSet(UnicodeProperties.normalize(ranges), negated);
	}

	// (a class member: a character, or -1 after adding an escape set's ranges)
	function classAtom(ranges:Array<Int>):Int {
		var c = next();
		if (c != "\\".code) return c;
		var e = peek();
		if (e == "b".code) {
			i++;
			return 8;
		}
		if (e == "-".code) {
			i++;
			return 45;
		}
		var set = classEscape();
		if (set != null) {
			switch (set) {
				case RSet(rs, false): for (r in rs) ranges.push(r);
				case RSet(rs, true):
					var prev = 0;
					var k = 0;
					while (k < rs.length) {
						if (rs[k] > prev) {
							ranges.push(prev);
							ranges.push(rs[k] - 1);
						}
						prev = rs[k + 1] + 1;
						k += 2;
					}
					if (prev <= 0x10ffff) {
						ranges.push(prev);
						ranges.push(0x10ffff);
					}
				case _:
			}
			return -1;
		}
		return characterEscape();
	}

	static function resolveNames(n:RxNode, names:Array<String>, groups:Int):RxNode {
		return switch (n) {
			case RNamedBackref(name):
				var k = names.indexOf(name);
				if (k < 0) throw new RegexSyntax("Invalid named capture referenced");
				RBackref(k + 1);
			case RBackref(k) if (k > groups): RBackref(-k);
			case RGroup(i, x): RGroup(i, resolveNames(x, names, groups));
			case RLook(b, neg, x): RLook(b, neg, resolveNames(x, names, groups));
			case RRepeat(x, a, z, g, f, l): RRepeat(resolveNames(x, names, groups), a, z, g, f, l);
			case RSeq(xs): RSeq([for (x in xs) resolveNames(x, names, groups)]);
			case RAlt(xs): RAlt([for (x in xs) resolveNames(x, names, groups)]);
			case _: n;
		};
	}
	static function parse(source:String, flags:String):{program:RxNode, groups:Int, names:Array<String>} {
		var parser = new Regex(source, flags.indexOf("u") >= 0 || flags.indexOf("v") >= 0);
		var program = parser.disjunction();
		if (parser.i < source.length) parser.fail("Unmatched ')'");
		return {program: resolveNames(program, parser.names, parser.groups), groups: parser.groups, names: parser.names};
	}

	// A literal's pattern as the runtime would parse it: its syntax error, else
	// null (helder's compiler, for a diagnostic at the literal's line)
	public static function check(source:String, flags:String):Null<String> {
		if (properties == null) properties = UnicodeProperties.lookup;
		return try {
			parse(source, flags);
			null;
		} catch (e:RegexSyntax) e.message;
	}

	// (patterns are parsed once per source and flags: by flags, then source)
	static var cache:Map<String, Map<String, Compiled>> = [];

	public static function compile(source:String, flags:String):JsRegExp {
		var sources = cache.get(flags);
		if (sources == null) {
			for (k in 0...flags.length) {
				var f = flags.charAt(k);
				if ("dgimsuvy".indexOf(f) < 0 || flags.indexOf(f) != k) error("SyntaxError", "Invalid flags supplied to RegExp constructor '" + flags + "'");
			}
			cache.set(flags, sources = []);
		}
		var compiled = sources.get(source);
		if (compiled == null) {
			var bits = 0;
			for (k in 0...flags.length) bits |= switch (flags.charAt(k)) {
				case "g": GLOBAL;
				case "i": IGNORE_CASE;
				case "m": MULTILINE;
				case "s": DOT_ALL;
				case "u" | "v": UNICODE;
				case "y": STICKY;
				case _: INDICES;
			}
			var parsed = try parse(source, flags) catch (e:RegexSyntax) error("SyntaxError", "Invalid regular expression: /" + source + "/" + flags + ": " + e.message);
			var text = "";
			for (f in ["d", "g", "i", "m", "s", "u", "v", "y"]) if (flags.indexOf(f) >= 0) text += f;
			compiled = new Compiled(parsed.program, parsed.groups, parsed.names, bits, text, firsts(parsed.program, bits & IGNORE_CASE != 0, bits & UNICODE != 0), anchored(parsed.program));
			sources.set(source, compiled);
		}
		var r = new JsRegExp(RegExpProto);
		r.source = source;
		r.flags = flags;
		r.compiled = compiled;
		r.groupCount = compiled.groups;
		r.groupNames = compiled.names;
		r.program = compiled.program;
		r.setOwn("lastIndex", 0.0, Attr.HIDDEN | Attr.LOCKED);
		return r;
	}

	// (the code units a match of n starts with, as inclusive pairs; null when
	// any can, or n matches the empty string)
	static function firsts(n:RxNode, fold:Bool, unicode:Bool):Array<Int> {
		return switch (n) {
			case RChar(c) if (c >= 0xd800 && (unicode || c > 0xffff)): null;
			case RChar(c) if (!fold): [c, c];
			// (ignoring case, an ASCII letter matches its other case only: Regex.canonical)
			case RChar(c) if (c >= 65 && c <= 90 || c >= 97 && c <= 122): [c & ~32, c & ~32, c | 32, c | 32];
			case RChar(c) if (c < 128): [c, c];
			case RSet(ranges, false) if (!fold && !(unicode && ranges.filter(r -> r >= 0xd800).length > 0)): ranges;
			case RGroup(_, x): firsts(x, fold, unicode);
			case RSeq(items) if (items.length > 0): firsts(items[0], fold, unicode);
			case RRepeat(x, min, _, _, _, _) if (min > 0): firsts(x, fold, unicode);
			case RAlt(options):
				var out = [];
				for (o in options) {
					var f = firsts(o, fold, unicode);
					if (f == null) return null;
					out = out.concat(f);
				}
				out;
			case _: null;
		};
	}

	// (a match of n starts where a line starts: at 0, or after a line terminator if multiline)
	static function anchored(n:RxNode):Bool {
		return switch (n) {
			case RStart: true;
			case RGroup(_, x): anchored(x);
			case RSeq(items): items.length > 0 && anchored(items[0]);
			case RAlt(options): options.length > 0 && options.filter(o -> !anchored(o)).length == 0;
			case _: false;
		};
	}

	// Matching.
	var s:String;
	var caps:Array<Int>;
	var ignoreCase:Bool;
	var multiline:Bool;
	var dotAll:Bool;
	var steps = 0;
	var compiled:Compiled;
	var end = -1;
	var accept:Int->Bool;
	function at(k:Int):Int {
		var c = s.charCodeAt(k);
		if (unicode && c >= 0xd800 && c <= 0xdbff && k + 1 < s.length) {
			var d = s.charCodeAt(k + 1);
			if (d >= 0xdc00 && d <= 0xdfff) return (c - 0xd800) * 1024 + (d - 0xdc00) + 0x10000;
		}
		return c;
	}

	static inline function width(c:Int):Int return c > 0xffff ? 2 : 1;

	static function lineTerminator(c:Int):Bool return c == 10 || c == 13 || c == 0x2028 || c == 0x2029;

	function wordAt(k:Int):Bool {
		if (k < 0 || k >= s.length) return false;
		var c = s.charCodeAt(k);
		return c >= 48 && c <= 57 || c >= 65 && c <= 90 || c >= 97 && c <= 122 || c == 95;
	}

	static function canonical(c:Int):Int {
		if (c < 128) return c >= 97 && c <= 122 ? c - 32 : c;
		if (c > 0xffff) return c;
		var u = String.fromCharCode(c).toUpperCase();
		return u.length == 1 && u.charCodeAt(0) >= 128 ? u.charCodeAt(0) : c;
	}

	function inSet(c:Int, ranges:Array<Int>):Bool {
		if (contains(c, ranges)) return true;
		if (ignoreCase && c < 128) {
			var x = c >= 65 && c <= 90 || c >= 97 && c <= 122 ? c ^ 32 : c;
			return x != c && contains(x, ranges);
		}
		else if (ignoreCase) {
			var alternatives = [String.fromCharCode(c).toLowerCase(), String.fromCharCode(c).toUpperCase()];
			for (a in alternatives) if (a.length == 1) {
				var x = a.charCodeAt(0);
				if (x != c && contains(x, ranges)) return true;
			}
		}
		return false;
	}

	// (ranges sorted and disjoint: a property's run to thousands)
	static function contains(c:Int, ranges:Array<Int>):Bool {
		var lo = 0, hi = (ranges.length >> 1) - 1;
		while (lo <= hi) {
			var mid = (lo + hi) >> 1;
			if (c < ranges[2 * mid]) hi = mid - 1;
			else if (c > ranges[2 * mid + 1]) lo = mid + 1;
			else return true;
		}
		return false;
	}

	// (one single-character node at position k: the next position, or -1)
	function single(n:RxNode, k:Int):Int {
		if (k >= s.length) return -1;
		var c = at(k);
		return switch (n) {
			case RChar(x): (c == x || ignoreCase && canonical(c) == canonical(x)) ? k + width(c) : -1;
			case RAny: (dotAll || !lineTerminator(c)) ? k + width(c) : -1;
			case RSet(r, neg): inSet(c, r) != neg ? k + width(c) : -1;
			case _: -1;
		};
	}

	function match(n:RxNode, k:Int, next:Int->Bool):Bool {
		if (++steps > 50000000) error("RangeError", "Maximum regular expression backtracking exceeded");
		switch (n) {
			case RChar(_) | RAny | RSet(_, _):
				var j = single(n, k);
				return j >= 0 && next(j);
			case RStart: return (k == 0 || multiline && lineTerminator(s.charCodeAt(k - 1))) && next(k);
			case REnd: return (k == s.length || multiline && lineTerminator(s.charCodeAt(k))) && next(k);
			case RWord(neg): return (wordAt(k - 1) != wordAt(k)) != neg && next(k);
			case RGroup(-1, x): return match(x, k, next);
			case RGroup(g, x):
				var ps = caps[2 * g], pe = caps[2 * g + 1];
				if (match(x, k, j -> {
					var qs = caps[2 * g], qe = caps[2 * g + 1];
					caps[2 * g] = k;
					caps[2 * g + 1] = j;
					if (next(j)) return true;
					caps[2 * g] = qs;
					caps[2 * g + 1] = qe;
					return false;})) return true;
				caps[2 * g] = ps;
				caps[2 * g + 1] = pe;
				return false;
			case RLook(behind, neg, x):
				var saved = caps.copy();
				var found = false;
				if (behind) {
					var start = k;
					while (start >= 0 && !found) {
						if (match(x, start, j -> j == k)) found = true; else start--;
					}
				}
				else found = match(x, k, _ -> true);
				if (neg) {
					caps = saved;
					return !found && next(k);
				}
				if (!found) {
					caps = saved;
					return false;
				}
				if (next(k)) return true;
				caps = saved;
				return false;
			case RBackref(g):
				if (g < 0 || caps[2 * g] < 0) return next(k);
				var sub = s.substring(caps[2 * g], caps[2 * g + 1]);
				if (k + sub.length > s.length) return false;
				var here = s.substr(k, sub.length);
				if (here != sub && !(ignoreCase && here.toUpperCase() == sub.toUpperCase())) return false;
				return next(k + sub.length);
			case RSeq(items): return matchSequence(items, 0, k, next);
			case RAlt(options):
				for (o in options) if (match(o, k, next)) return true;
				return false;
			case RRepeat(x, min, max, greedy, first, last):
				switch (x) {
					case RChar(_) | RAny | RSet(_, _) if (!unicode):
						// (single code units: the positions are k + count)
						var j = k, count = 0;
						while (max < 0 || count < max) {
							var nj = single(x, j);
							if (nj < 0) break;
							j = nj;
							count++;
						}
						if (count < min) return false;
						if (greedy) {
							var c = count;
							while (c >= min) {
								if (next(k + c)) return true;
								c--;
							}
						}
						else for (c in min...count + 1) if (next(k + c)) return true;
						return false;
					case RChar(_) | RAny | RSet(_, _):
						// (single characters: positions found iteratively)
						var positions = [k];
						var j = k;
						while (max < 0 || positions.length - 1 < max) {
							var nj = single(x, j);
							if (nj < 0) break;
							positions.push(nj);
							j = nj;
						}
						if (positions.length - 1 < min) return false;
						if (greedy) {
							var c = positions.length - 1;
							while (c >= min) {
								if (next(positions[c])) return true;
								c--;
							}
						}
						else for (c in min...positions.length) if (next(positions[c])) return true;
						return false;
					case _: return repeat(x, min, max, greedy, first, last, 0, k, next);
				}
			case RNamedBackref(_): return false;
		}
	}

	function matchSequence(items:Array<RxNode>, index:Int, k:Int, next:Int->Bool):Bool {
		// (single characters match one way only: in a loop, without a continuation each)
		while (index < items.length) {
			switch (items[index]) {
				case RChar(_) | RAny | RSet(_, _):
					if (++steps > 50000000) error("RangeError", "Maximum regular expression backtracking exceeded");
					k = single(items[index], k);
					if (k < 0) return false;
					index++;
				case _: break;
			}
		}
		if (index == items.length) return next(k);
		return match(items[index], k, j -> matchSequence(items, index + 1, j, next));
	}

	function repeat(x:RxNode, min:Int, max:Int, greedy:Bool, first:Int, last:Int, count:Int, k:Int, next:Int->Bool):Bool {
		if (count >= min && !greedy && next(k)) return true;
		if (max < 0 || count < max) {
			// (captures inside the quantified atom restart each iteration)
			var saved = caps.slice(2 * first, 2 * last + 2);
			for (g in first...last + 1) {
				caps[2 * g] = -1;
				caps[2 * g + 1] = -1;
			}
			if (match(x, k, j -> j == k && count >= min ? false : repeat(x, min, max, greedy, first, last, count + 1, j, next))) return true;
			for (t in 0...saved.length) caps[2 * first + t] = saved[t];
		}
		return count >= min && greedy && next(k);
	}

	// (one matcher for every start position in s)
	static function matcher(r:JsRegExp, s:String):Regex {
		var c = r.compiled;
		if (r.matcher != null && Lib.same(r.matcher.s, s) && r.matcher.compiled == c) return r.matcher;
		var m = new Regex(r.source, c.bits & UNICODE != 0);
		m.s = s;
		m.compiled = c;
		m.ignoreCase = c.bits & IGNORE_CASE != 0;
		m.multiline = c.bits & MULTILINE != 0;
		m.dotAll = c.bits & DOT_ALL != 0;
		m.caps = [];
		m.accept = j -> {
			m.end = j;
			return true;
		};
		return r.matcher = m;
	}

	// (a match can start at k: its first code unit is one it can start with, and a line starts there if it must)
	function possible(k:Int):Bool {
		if (compiled.anchored && k > 0 && !(multiline && lineTerminator(StringTools.fastCodeAt(s, k - 1)))) return false;
		var first = compiled.first;
		if (first == null) return true;
		if (k >= s.length) return false;
		var c = StringTools.fastCodeAt(s, k), i = 0;
		while (i < first.length) {
			if (c >= first[i] && c <= first[i + 1]) return true;
			i += 2;
		}
		return false;
	}

	// A match starting exactly at k: captures (start/end pairs, group 0 first), or null.
	function attempt(k:Int):Array<Int> {
		if (!possible(k)) return null;
		var n = 2 * (compiled.groups + 1);
		if (caps.length != n) caps = [for (_ in 0...n) -1]; else for (g in 0...n) caps[g] = -1;
		steps = 0;
		if (!match(compiled.program, k, accept)) return null;
		var found = caps;
		found[0] = k;
		found[1] = end;
		// (the next attempt's own: this one is the caller's)
		caps = [];
		return found;
	}

	public static function matchAt(r:JsRegExp, s:String, k:Int):Array<Int> return matcher(r, s).attempt(k);

	// RegExpBuiltinExec: the match object (array with index, input, groups), or null.
	public static function exec(r:JsRegExp, s:String):Dynamic {
		var bits = r.compiled.bits;
		var global = bits & GLOBAL != 0, sticky = bits & STICKY != 0;
		var lastIndex = toLength(get(r, "lastIndex"));
		if (!global && !sticky) lastIndex = 0;
		if (lastIndex > s.length) {
			if (global || sticky) put(r, "lastIndex", 0);
			return null;
		}
		var k = Std.int(lastIndex);
		var caps:Array<Int> = null;
		var m = matcher(r, s);
		var unicode = bits & UNICODE != 0;
		while (k <= s.length) {
			caps = m.attempt(k);
			if (caps != null || sticky) break;
			k = advance(s, k, unicode);
		}
		if (caps == null) {
			if (global || sticky) put(r, "lastIndex", 0);
			return null;
		}
		if (global || sticky) put(r, "lastIndex", caps[1]);
		return result(r, s, caps);
	}

	static function result(r:JsRegExp, s:String, caps:Array<Int>):Dynamic {
		var items:Array<Dynamic> = [for (g in 0...r.groupCount + 1) caps[2 * g] < 0 ? undef() : s.substring(caps[2 * g], caps[2 * g + 1])];
		var a:JsArray = cast array(items);
		a.setOwn("index", caps[0]);
		a.setOwn("input", s);
		var groups:Dynamic = undef();
		if (r.groupNames.filter(n -> n != null).length > 0) {
			var g = new JsObject(null);
			for (k in 0...r.groupNames.length) if (r.groupNames[k] != null) g.setOwn(r.groupNames[k], items[k + 1]);
			groups = g;
		}
		a.setOwn("groups", groups);
		if (r.compiled.bits & INDICES != 0) {
			var indices:JsArray = cast array([for (g in 0...r.groupCount + 1) caps[2 * g] < 0 ? undef() : array([caps[2 * g], caps[2 * g + 1]])]);
			var ig:Dynamic = undef();
			if (groups != undef()) {
				var g = new JsObject(null);
				for (k in 0...r.groupNames.length) if (r.groupNames[k] != null) g.setOwn(r.groupNames[k], get(indices, k + 1));
				ig = g;
			}
			indices.setOwn("groups", ig);
			a.setOwn("indices", indices);
		}
		return a;
	}

	static function toLength(v:Dynamic):Float {
		var n = toIntegerOrInfinity(v);
		return n < 0 ? 0 : Math.min(n, 9007199254740991.0);
	}

	static function advance(s:String, k:Int, unicode:Bool):Int {
		if (unicode && k + 1 < s.length) {
			var c = s.charCodeAt(k);
			if (c >= 0xd800 && c <= 0xdbff) {
				var d = s.charCodeAt(k + 1);
				if (d >= 0xdc00 && d <= 0xdfff) return k + 2;
			}
		}
		return k + 1;
	}

	// (exec through a possibly overridden exec method, as RegExpExec does)
	static function regExpExec(r:Dynamic, s:String):Dynamic {
		var f = get(r, "exec");
		if (Std.isOfType(f, JsFunction) && (f : JsFunction).native != null && Std.isOfType(r, JsRegExp)) return exec(r, s);
		if (isCallable(f)) {
			var v = call(f, r, [s]);
			if (v != null && !isObject(v)) error("TypeError", "exec result must be an object or null");
			return v;
		}
		return exec(thisRegExp(r, "exec"), s);
	}

	static function thisRegExp(t:Dynamic, name:String):JsRegExp {
		if (!Std.isOfType(t, JsRegExp)) error("TypeError", "RegExp.prototype." + name + " requires that 'this' be a RegExp object");
		return t;
	}

	public static function create(source:String, flags:String):Dynamic return compile(source, flags);

	public static function setup():Void {
		RegExpProto = new JsObject(Builtins.ObjectProto);
		var ctor = Builtins.nativeFunction("RegExp", 2, (_, a, nt) -> {
			var pattern = arg(a, 0), flags = arg(a, 1);
			if (nt == undef() && Std.isOfType(pattern, JsRegExp) && flags == undef()) return pattern;
			var source = Std.isOfType(pattern, JsRegExp) ? (pattern : JsRegExp).source : pattern == undef() ? "(?:)" : Seed.text(pattern);
			var f = flags == undef() ? (Std.isOfType(pattern, JsRegExp) ? (pattern : JsRegExp).flags : "") : Seed.text(flags);
			var r = compile(source == "" ? "(?:)" : source, f);
			if (nt != undef()) r.proto = protoFrom(nt, RegExpProto);
			return r;
		}, true);
		ctor.setOwn("prototype", RegExpProto, Attr.HIDDEN | Attr.READONLY | Attr.LOCKED);
		RegExpProto.setOwn("constructor", ctor, Attr.HIDDEN);
		Builtins.globals.set("RegExp", ctor);
		(Builtins.globals.get("globalThis") : JsObject).setOwn("RegExp", ctor, Attr.HIDDEN);
		function method(name:String, arity:Int, fn:(Dynamic, Array<Dynamic>, Dynamic) -> Dynamic) RegExpProto.setOwn(name, Builtins.nativeFunction(Symbols.functionName(name), arity, fn), Attr.HIDDEN);
		function getter(name:String, fn:JsRegExp->Dynamic) RegExpProto.setOwn(name, new Accessor(Builtins.nativeFunction("get " + name, 0, (t, _, _) -> t == RegExpProto ? (name == "source" ? "(?:)" : name == "flags" ? "" : undef()) : fn(thisRegExp(t, name))), null), Attr.HIDDEN);
		getter("source", r -> escapeSource(r.source));
		getter("flags", r -> r.compiled.flags);
		for (pair in [["global", "g"], ["ignoreCase", "i"], ["multiline", "m"], ["dotAll", "s"], ["unicode", "u"], ["unicodeSets", "v"], ["sticky", "y"], ["hasIndices", "d"]]) getter(pair[0], r -> r.flags.indexOf(pair[1]) >= 0);
		method("exec", 1, (t, a, _) -> exec(thisRegExp(t, "exec"), Seed.text(arg(a, 0))));
		method("test", 1, (t, a, _) -> regExpExec(t, Seed.text(arg(a, 0))) != null);
		method("toString", 0, (t, _, _) -> "/" + Seed.text(get(t, "source")) + "/" + Seed.text(get(t, "flags")));
		method("compile", 2, (t, a, _) -> {
			var r = thisRegExp(t, "compile");
			var c = compile(arg(a, 0) == undef() ? "(?:)" : Seed.text(arg(a, 0)), arg(a, 1) == undef() ? "" : Seed.text(arg(a, 1)));
			r.source = c.source;
			r.flags = c.flags;
			r.program = c.program;
			r.groupCount = c.groupCount;
			r.groupNames = c.groupNames;
			r.compiled = c.compiled;
			r.matcher = null;
			put(r, "lastIndex", 0);
			return r;});
		method("\x00@@match", 1, (t, a, _) -> {
			var s = Seed.text(arg(a, 0));
			var flags = Seed.text(get(t, "flags"));
			if (flags.indexOf("g") < 0) return regExpExec(t, s);
			put(t, "lastIndex", 0);
			var out:Array<Dynamic> = [];
			while (true) {
				var m = regExpExec(t, s);
				if (m == null) break;
				var text = Seed.text(get(m, 0));
				out.push(text);
				if (text == "") put(t, "lastIndex", advance(s, Std.int(toLength(get(t, "lastIndex"))), flags.indexOf("u") >= 0));
			}
			return out.length == 0 ? null : array(out);
		});
		method("\x00@@matchAll", 1, (t, a, _) -> {
			var s = Seed.text(arg(a, 0));
			var flags = Seed.text(get(t, "flags"));
			var r = compile((t : JsRegExp).source, flags);
			put(r, "lastIndex", get(t, "lastIndex"));
			var done = false;
			var global = flags.indexOf("g") >= 0;
			var it = new JsObject(Builtins.IteratorProto);
			it.setOwn("next", Builtins.nativeFunction("next", 0, (_, _, _) -> {
				if (done) return object(["value", "done"], [undef(), true]);
				var m = exec(r, s);
				if (m == null) {
					done = true;
					return object(["value", "done"], [undef(), true]);
				}
				if (!global) done = true;
				else if (Seed.text(get(m, 0)) == "") put(r, "lastIndex", advance(s, Std.int(toLength(get(r, "lastIndex"))), flags.indexOf("u") >= 0));
				return object(["value", "done"], [m, false]);
			}), Attr.HIDDEN);
			it.setOwn(Symbols.toStringTag, "RegExp String Iterator", Attr.HIDDEN);
			return it;
		});
		method("\x00@@search", 1, (t, a, _) -> {
			var s = Seed.text(arg(a, 0));
			var previous = get(t, "lastIndex");
			put(t, "lastIndex", 0);
			var m = regExpExec(t, s);
			put(t, "lastIndex", previous);
			return m == null ? -1 : get(m, "index");
		});
		method("\x00@@split", 2, (t, a, _) -> {
			var s = Seed.text(arg(a, 0));
			var limit = arg(a, 1) == undef() ? 4294967295.0 : toUint32(arg(a, 1));
			var r:JsRegExp = thisRegExp(t, "split");
			var unicode = r.flags.indexOf("u") >= 0;
			var out:Array<Dynamic> = [];
			if (limit == 0) return array(out);
			var m = matcher(r, s);
			if (s.length == 0) return array(m.attempt(0) != null ? [] : [s]);
			var p = 0, q = 0;
			while (q < s.length) {
				var caps = m.attempt(q);
				if (caps == null || caps[1] == p || caps[1] > s.length) {
					q = advance(s, q, unicode);
					continue;
				}
				out.push(s.substring(p, q));
				if (out.length >= limit) return array(out);
				for (g in 1...r.groupCount + 1) {
					out.push(caps[2 * g] < 0 ? undef() : s.substring(caps[2 * g], caps[2 * g + 1]));
					if (out.length >= limit) return array(out);
				}
				p = caps[1];
				q = p;
			}
			out.push(s.substr(p));
			return array(out);
		});
		method("\x00@@replace", 2, (t, a, _) -> {
			var s = Seed.text(arg(a, 0));
			var replaceValue = arg(a, 1);
			var functional = isCallable(replaceValue);
			var template = functional ? "" : Seed.text(replaceValue);
			var flags = Seed.text(get(t, "flags"));
			var global = flags.indexOf("g") >= 0;
			if (global) put(t, "lastIndex", 0);
			var results:Array<Dynamic> = [];
			while (true) {
				var m = regExpExec(t, s);
				if (m == null) break;
				results.push(m);
				if (!global) break;
				if (Seed.text(get(m, 0)) == "") put(t, "lastIndex", advance(s, Std.int(toLength(get(t, "lastIndex"))), flags.indexOf("u") >= 0));
			}
			var out = new StringBuf();
			var next = 0;
			for (m in results) {
				var matched = Seed.text(get(m, 0));
				var position = Std.int(Math.max(Math.min(toIntegerOrInfinity(get(m, "index")), s.length), 0));
				var n = Std.int(Arrays.lengthOf(m));
				var captures:Array<Dynamic> = [for (k in 1...n) {
					var c = get(m, k);
					c == undef() ? c : Seed.text(c);
				}];
				var groups = get(m, "groups");
				var replacement = functional ? Seed.text(call(replaceValue, undef(), ([matched] : Array<Dynamic>).concat(captures).concat([position, s]).concat(groups == undef() ? [] : [groups]))) : expand(template, matched, s, position, captures, groups == undef() ? null : toObject(groups));
				if (position >= next) {
					out.add(s.substring(next, position));
					out.add(replacement);
					next = position + matched.length;
				}
			}
			out.add(s.substr(next));
			return out.toString();
		});
	}

	static function escapeSource(source:String):String {
		var out = new StringBuf();
		var inClass = false;
		var k = 0;
		while (k < source.length) {
			var c = source.charAt(k);
			if (c == "\\") {
				out.add(c);
				if (k + 1 < source.length) out.add(source.charAt(k + 1));
				k += 2;
				continue;
			}
			if (c == "[") inClass = true; else if (c == "]") inClass = false;
			if (c == "/" && !inClass) out.add("\\/"); else if (c == "\n") out.add("\\n"); else if (c == "\r") out.add("\\r"); else out.add(c);
			k++;
		}
		return out.toString();
	}

	// GetSubstitution: $$, $&, $`, $', $n, $nn and $<name> in a replacement string.
	public static function expand(replacement:String, matched:String, str:String, position:Int, captures:Array<Dynamic>, named:Dynamic):String {
		if (replacement.indexOf("$") < 0) return replacement;
		var out = new StringBuf();
		var i = 0;
		var m = captures.length;
		while (i < replacement.length) {
			var c = replacement.charAt(i);
			if (c != "$" || i + 1 >= replacement.length) {
				out.add(c);
				i++;
				continue;
			}
			var next = replacement.charAt(i + 1);
			switch (next) {
				case "$":
					out.add("$");
					i += 2;
				case "&":
					out.add(matched);
					i += 2;
				case "`":
					out.add(str.substr(0, position));
					i += 2;
				case "'":
					out.add(str.substr(Std.int(Math.min(position + matched.length, str.length))));
					i += 2;
				case "<":
					if (named == null || named == undef()) {
						out.add("$<");
						i += 2;
						continue;
					}
					var close = replacement.indexOf(">", i + 2);
					if (close < 0) {
						out.add("$<");
						i += 2;
						continue;
					}
					var v = get(named, replacement.substring(i + 2, close));
					if (v != undef()) out.add(Seed.text(v));
					i = close + 1;
				case _:
					var d1 = next.charCodeAt(0) - 48;
					if (d1 < 0 || d1 > 9) {
						out.add("$");
						i++;
						continue;
					}
					var d2 = i + 2 < replacement.length ? replacement.charCodeAt(i + 2) - 48 : -1;
					if (d2 >= 0 && d2 <= 9 && d1 * 10 + d2 >= 1 && d1 * 10 + d2 <= m) {
						var v = captures[d1 * 10 + d2 - 1];
						if (v != undef()) out.add(Seed.text(v));
						i += 3;
						continue;
					}
					if (d1 >= 1 && d1 <= m) {
						var v = captures[d1 - 1];
						if (v != undef()) out.add(Seed.text(v));
						i += 2;
						continue;
					}
					out.add("$");
					i++;
			}
		}
		return out.toString();
	}
}
