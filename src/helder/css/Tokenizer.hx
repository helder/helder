package helder.css;

import helder.css.CssChars.*;
import helder.css.CssToken.CssTokenKind;

using StringTools;

// Syntax 3's tokenizer (§4) over a String as it is: the input's filtering
// (§3.3) done as each code point is read (CR, FF and CR LF are one LF,
// NUL and a lone surrogate U+FFFD, a surrogate pair one code point), so
// offsets are the text's own and plain values are substrings of it.
class Tokenizer {
	static inline var EOF = -1;

	static final DELIMS = [for (c in 0...128) String.fromCharCode(c)];

	final s:String;
	final n:Int;
	final ranges:Bool;
	var i = 0;

	// (from and to: a part of s alone, its offsets s's)
	public function new(s:String, ranges = false, from = 0, ?to:Int) {
		this.s = s;
		n = to ?? s.length;
		this.ranges = ranges;
		i = from;
	}

	public static function tokenize(s:String, ranges = false, from = 0, ?to:Int):Array<CssToken> {
		var t = new Tokenizer(s, ranges, from, to), out = [];
		while (true) {
			var k = t.next();
			if (k == null) return out;
			out.push(k);
		}
	}

	// the filtered code point at k
	inline function at(k:Int):Int {
		if (k >= n) return EOF;
		var c = s.fastCodeAt(k);
		return c >= 0x20 && c < 0x7F ? c : slow(k, c);
	}

	function slow(k:Int, c:Int):Int {
		if (c == 13 || c == 12) return 10;
		if (c == 0) return 0xFFFD;
		if (c >= 0xD800 && c < 0xE000) {
			if (c < 0xDC00 && k + 1 < n) {
				var d = s.fastCodeAt(k + 1);
				if (d >= 0xDC00 && d < 0xE000) return 0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00);
			}
			return 0xFFFD;
		}
		return c;
	}

	// past the code point at k (k < n)
	inline function after(k:Int):Int {
		var c = s.fastCodeAt(k);
		return c >= 0x20 && c < 0x7F ? k + 1 : wide(k, c);
	}

	function wide(k:Int, c:Int):Int {
		if (k + 1 < n) {
			var d = s.fastCodeAt(k + 1);
			if ((c == 13 && d == 10) || (c >= 0xD800 && c < 0xDC00 && d >= 0xDC00 && d < 0xE000)) return k + 2;
		}
		return k + 1;
	}

	// whether the String's unit at k is not itself the code point read there (NUL, CR, FF, a lone surrogate)
	inline function replaced(k:Int, c:Int):Bool
		return c == 0 || c == 13 || c == 12 || (c >= 0xD800 && c < 0xE000 && after(k) == k + 1);

	static inline function hex(c:Int):Int
		return c <= "9".code ? c - "0".code : (c | 0x20) - "a".code + 10;

	static inline function isWs(c:Int):Bool
		return c == 10 || c == 9 || c == 32;

	inline function valid(k:Int):Bool
		return at(k) == "\\".code && at(k + 1) != 10;

	function startsIdent(k:Int):Bool {
		var c = at(k);
		if (c == "-".code) {
			var d = at(k + 1);
			return isIdentStart(d) || d == "-".code || (d == "\\".code && at(k + 2) != 10);
		}
		if (c == "\\".code) return at(k + 1) != 10;
		return c >= 0 && isIdentStart(c);
	}

	function startsNumber(k:Int):Bool {
		var c = at(k);
		if (c == "+".code || c == "-".code) {
			var d = at(k + 1);
			return isDigit(d) || (d == ".".code && isDigit(at(k + 2)));
		}
		if (c == ".".code) return isDigit(at(k + 1));
		return isDigit(c);
	}

	inline function token(kind:CssTokenKind, start:Int):CssToken
		return new CssToken(kind, start, i);

	public function next():Null<CssToken> {
		while (at(i) == "/".code && at(i + 1) == "*".code) {
			var e = s.indexOf("*/", i + 2);
			i = e < 0 || e + 2 > n ? n : e + 2;
		}
		var start = i, c = at(i);
		if (c == EOF) return null;
		switch c {
			case 10 | 9 | 32:
				i = after(i);
				while (isWs(at(i)))
					i = after(i);
				return token(Whitespace, start);
			case '"'.code | "'".code:
				i++;
				return string(c, start);
			case "#".code:
				if (isIdent(at(i + 1)) || valid(i + 1)) {
					var id = startsIdent(i + 1);
					i++;
					return token(Hash(ident(), id), start);
				}
			case "(".code:
				i++;
				return token(OpenParen, start);
			case ")".code:
				i++;
				return token(CloseParen, start);
			case "+".code | ".".code:
				if (startsNumber(i)) return numeric(start);
			case ",".code:
				i++;
				return token(Comma, start);
			case "-".code:
				if (startsNumber(i)) return numeric(start);
				if (at(i + 1) == "-".code && at(i + 2) == ">".code) {
					i += 3;
					return token(Cdc, start);
				}
				if (startsIdent(i)) return identLike(start);
			case ":".code:
				i++;
				return token(Colon, start);
			case ";".code:
				i++;
				return token(Semicolon, start);
			case "<".code:
				if (at(i + 1) == "!".code && at(i + 2) == "-".code && at(i + 3) == "-".code) {
					i += 4;
					return token(Cdo, start);
				}
			case "@".code:
				if (startsIdent(i + 1)) {
					i++;
					return token(AtKeyword(ident()), start);
				}
			case "[".code:
				i++;
				return token(OpenSquare, start);
			case "\\".code:
				if (valid(i)) return identLike(start);
			case "]".code:
				i++;
				return token(CloseSquare, start);
			case "{".code:
				i++;
				return token(OpenCurly, start);
			case "}".code:
				i++;
				return token(CloseCurly, start);
			case "u".code | "U".code:
				if (ranges && at(i + 1) == "+".code && (at(i + 2) == "?".code || isHex(at(i + 2)))) return range(start);
				return identLike(start);
			default:
				if (isDigit(c)) return numeric(start);
				if (isIdentStart(c)) return identLike(start);
		}
		i = after(i);
		return token(Delim(c < 0x80 ? DELIMS[c] : String.fromCharCode(c)), start);
	}

	// (§4.3.12, at i)
	function ident():String {
		var from = i;
		while (i < n) {
			var c = s.fastCodeAt(i);
			if ((c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code) || c == "-".code || c == "_".code || isDigit(c)) i++ else break;
		}
		var c = at(i);
		if (c == EOF || (c != "\\".code && !isIdent(c))) return s.substring(from, i);
		var b = new StringBuf();
		b.addSub(s, from, i - from);
		while (true) {
			c = at(i);
			if (c >= 0 && isIdent(c)) {
				b.addChar(c);
				i = after(i);
			} else if (valid(i)) {
				i++;
				b.addChar(escape());
			} else return b.toString();
		}
	}

	// (§4.3.7: the backslash read, i at what follows)
	function escape():Int {
		var c = at(i);
		if (c == EOF) return 0xFFFD;
		if (isHex(c)) {
			var v = 0, k = 0;
			while (k < 6 && isHex(at(i))) {
				v = v * 16 + hex(at(i));
				i++;
				k++;
			}
			if (isWs(at(i))) i = after(i);
			return v == 0 || (v >= 0xD800 && v < 0xE000) || v > 0x10FFFF ? 0xFFFD : v;
		}
		i = after(i);
		return c;
	}

	// (§4.3.4)
	function identLike(start:Int):CssToken {
		var name = ident();
		if (at(i) != "(".code) return token(Ident(name), start);
		i++;
		if (name.length == 3 && Css.lower(name) == "url") {
			while (isWs(at(i)) && isWs(at(after(i))))
				i = after(i);
			var c = at(i), d = isWs(c) ? at(after(i)) : c;
			if (d == '"'.code || d == "'".code) return token(Function(name), start);
			return url(start);
		}
		return token(Function(name), start);
	}

	// (§4.3.5: the opening quote read)
	function string(quote:Int, start:Int):CssToken {
		var b:Null<StringBuf> = null, from = i;
		inline function value():String {
			if (b == null) return s.substring(from, i);
			b.addSub(s, from, i - from);
			return b.toString();
		}
		while (true) {
			if (i >= n) return token(Str(value()), start);
			var c = s.fastCodeAt(i);
			if (c == quote) {
				var v = value();
				i++;
				return token(Str(v), start);
			}
			if (c == 10 || c == 13 || c == 12) return token(BadString, start);
			if (c == "\\".code) {
				if (b == null) b = new StringBuf();
				b.addSub(s, from, i - from);
				i++;
				var d = at(i);
				if (d == 10) i = after(i) else if (d != EOF) b.addChar(escape());
				from = i;
			} else if (replaced(i, c)) {
				if (b == null) b = new StringBuf();
				b.addSub(s, from, i - from);
				b.addChar(0xFFFD);
				i++;
				from = i;
			} else i = c < 0xD800 ? i + 1 : after(i);
		}
	}

	// (§4.3.6: "url(" read)
	function url(start:Int):CssToken {
		while (isWs(at(i)))
			i = after(i);
		var b:Null<StringBuf> = null, from = i;
		inline function value(end:Int):String {
			if (b == null) return s.substring(from, end);
			b.addSub(s, from, end - from);
			return b.toString();
		}
		while (true) {
			if (i >= n) return token(Url(value(i)), start);
			var c = s.fastCodeAt(i);
			if (c == ")".code) {
				var v = value(i);
				i++;
				return token(Url(v), start);
			}
			if (isWs(c) || c == 13 || c == 12) {
				var end = i;
				while (isWs(at(i)))
					i = after(i);
				if (i >= n) return token(Url(value(end)), start);
				if (at(i) == ")".code) {
					var v = value(end);
					i++;
					return token(Url(v), start);
				}
				return badUrl(start);
			}
			if (c == '"'.code || c == "'".code || c == "(".code || (c != 0 && isNonPrintable(c))) return badUrl(start);
			if (c == "\\".code) {
				if (!valid(i)) return badUrl(start);
				if (b == null) b = new StringBuf();
				b.addSub(s, from, i - from);
				i++;
				b.addChar(escape());
				from = i;
			} else if (replaced(i, c)) {
				if (b == null) b = new StringBuf();
				b.addSub(s, from, i - from);
				b.addChar(0xFFFD);
				i++;
				from = i;
			} else i = c < 0xD800 ? i + 1 : after(i);
		}
	}

	// (§4.3.15)
	function badUrl(start:Int):CssToken {
		while (i < n) {
			var c = at(i);
			if (c == ")".code) {
				i++;
				break;
			}
			if (valid(i)) {
				i++;
				escape();
			} else i = after(i);
		}
		return token(BadUrl, start);
	}

	// (§4.3.3, §4.3.13)
	function numeric(start:Int):CssToken {
		var integer = true;
		if (at(i) == "+".code || at(i) == "-".code) i++;
		while (isDigit(at(i)))
			i++;
		if (at(i) == ".".code && isDigit(at(i + 1))) {
			i += 2;
			while (isDigit(at(i)))
				i++;
			integer = false;
		}
		var c = at(i);
		if (c == "e".code || c == "E".code) {
			var d = at(i + 1);
			if (isDigit(d) || ((d == "+".code || d == "-".code) && isDigit(at(i + 2)))) {
				i += isDigit(d) ? 1 : 2;
				while (isDigit(at(i)))
					i++;
				integer = false;
			}
		}
		var text = s.substring(start, i), value = Std.parseFloat(text);
		if (startsIdent(i)) return token(Dimension(value, integer, text, ident()), start);
		if (at(i) == "%".code) {
			i++;
			return token(Percentage(value, integer, text), start);
		}
		return token(Number(value, integer, text), start);
	}

	// (§4.3.14)
	function range(start:Int):CssToken {
		i += 2;
		var first = 0, digits = 0;
		while (digits < 6 && isHex(at(i))) {
			first = first * 16 + hex(at(i));
			i++;
			digits++;
		}
		var marks = 0;
		while (digits + marks < 6 && at(i) == "?".code) {
			i++;
			marks++;
		}
		if (marks > 0) {
			var low = first << (4 * marks), high = low | ((1 << (4 * marks)) - 1);
			return token(UnicodeRange(low, high), start);
		}
		if (at(i) == "-".code && isHex(at(i + 1))) {
			i++;
			var last = 0, k = 0;
			while (k < 6 && isHex(at(i))) {
				last = last * 16 + hex(at(i));
				i++;
				k++;
			}
			return token(UnicodeRange(first, last), start);
		}
		return token(UnicodeRange(first, first), start);
	}
}
