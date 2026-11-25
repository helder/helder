package helder.markdown;

using StringTools;

// What the block and inline parsers share: character classes (CommonMark's
// punctuation is Unicode's P and S; the ranges here are the common ones),
// backslash escapes, entities, and HTML's tags as CommonMark reads them
// (raw HTML is kept as text, but where a tag ends still decides the rest)
class Scan {
	// the parsers' loop turns, every one (the tests' measure of linear time:
	// a count, unlike a clock, the same on a loaded machine)
	@:noCompletion public static var steps = 0;

	@:noCompletion public static inline function tick():Bool {
		steps++;
		return true;
	}

	public static inline function at(s:String, i:Int):Int
		return i < s.length ? s.fastCodeAt(i) : -1;

	public static inline function isSpaceOrTab(c:Int):Bool
		return c == 32 || c == 9;

	// (-1, the subject's ends, counts as a line end: whitespace)
	public static function isWhite(c:Int):Bool
		return c == -1 || c == 32 || c == 9 || c == 10 || c == 12 || c == 13 || c == 0xA0 || c == 0x1680 || (c >= 0x2000 && c <= 0x200A) || c == 0x202F
			|| c == 0x205F || c == 0x3000;

	public static inline function isAsciiPunct(c:Int):Bool
		return (c >= 33 && c <= 47) || (c >= 58 && c <= 64) || (c >= 91 && c <= 96) || (c >= 123 && c <= 126);

	public static function isPunct(c:Int):Bool {
		if (c < 128) return isAsciiPunct(c);
		return (c >= 0xA1 && c <= 0xA9) || c == 0xAB || c == 0xAC || (c >= 0xAE && c <= 0xB1) || c == 0xB4 || (c >= 0xB6 && c <= 0xB8) || c == 0xBB
			|| c == 0xBF || c == 0xD7 || c == 0xF7 || (c >= 0x2010 && c <= 0x2027) || (c >= 0x2030 && c <= 0x205E) || (c >= 0x20A0 && c <= 0x20C0)
			|| (c >= 0x2190 && c <= 0x2BFF) || (c >= 0x3001 && c <= 0x3003) || (c >= 0x3008 && c <= 0x3011) || (c >= 0x3014 && c <= 0x301F)
			|| (c >= 0xFF01 && c <= 0xFF0F) || (c >= 0xFF1A && c <= 0xFF20) || (c >= 0xFF3B && c <= 0xFF40) || (c >= 0xFF5B && c <= 0xFF65);
	}

	public static inline function isAlpha(c:Int):Bool
		return (c >= 65 && c <= 90) || (c >= 97 && c <= 122);

	public static inline function isDigit(c:Int):Bool
		return c >= 48 && c <= 57;

	public static inline function isAlnum(c:Int):Bool
		return isAlpha(c) || isDigit(c);

	// s with its backslash escapes and entities replaced (link destinations, titles, info strings)
	public static function unescape(s:String):String {
		if (s.indexOf("\\") < 0 && s.indexOf("&") < 0) return s;
		var out = new StringBuf(), i = 0, n = s.length;
		while (Scan.tick() && i < n) {
			var c = s.fastCodeAt(i);
			if (c == "\\".code && i + 1 < n && isAsciiPunct(s.fastCodeAt(i + 1))) {
				out.addChar(s.fastCodeAt(i + 1));
				i += 2;
			} else if (c == "&".code) {
				var end = entity(s, i, out);
				if (end < 0) {
					out.addChar(c);
					i++;
				} else i = end;
			} else {
				out.addChar(c);
				i++;
			}
		}
		return out.toString();
	}

	// the entity at s[i] ("&"): its text added to out and its end, else -1 (nothing added)
	public static function entity(s:String, i:Int, out:StringBuf):Int {
		var j = i + 1;
		if (at(s, j) == "#".code) {
			j++;
			var hex = at(s, j) == "x".code || at(s, j) == "X".code;
			if (hex) j++;
			var start = j, v = 0;
			while (Scan.tick() && (j < s.length && j - start < (hex ? 6 : 7))) {
				var c = s.fastCodeAt(j), d = isDigit(c) ? c - 48 : hex && c >= 97 && c <= 102 ? c - 87 : hex && c >= 65 && c <= 70 ? c - 55 : -1;
				if (d < 0) break;
				v = v * (hex ? 16 : 10) + d;
				j++;
			}
			if (j == start || at(s, j) != ";".code) return -1;
			// (CommonMark: a code point that is none, or 0, is U+FFFD)
			if (v == 0 || v > 0x10FFFF || (v >= 0xD800 && v < 0xE000)) v = 0xFFFD;
			out.add(String.fromCharCode(v));
			return j + 1;
		}
		var start = j;
		while (Scan.tick() && j < s.length && j - start < 32 && isAlnum(s.fastCodeAt(j)))
			j++;
		if (j == start || at(s, j) != ";".code || !isAlpha(s.fastCodeAt(start))) return -1;
		var text = Entities.named(s.substring(start, j));
		if (text == null) return -1;
		out.add(text);
		return j + 1;
	}

	// --- HTML, as CommonMark reads it

	// the end of an open tag at s[i] ("<"), else -1; newlines allowed between attributes
	public static function openTag(s:String, i:Int):Int {
		var j = i + 1;
		if (!isAlpha(at(s, j))) return -1;
		while (Scan.tick() && (isAlnum(at(s, j)) || at(s, j) == "-".code))
			j++;
		while (true) {
			Scan.tick();
			var w = j;
			while (Scan.tick() && isTagSpace(at(s, j)))
				j++;
			var c = at(s, j);
			if (c == ">".code) return j + 1;
			if (c == "/".code) return at(s, j + 1) == ">".code ? j + 2 : -1;
			// an attribute needs whitespace before it
			if (j == w || !(isAlpha(c) || c == "_".code || c == ":".code)) return -1;
			while (Scan.tick() && (isAlnum(at(s, j)) || at(s, j) == "_".code || at(s, j) == ".".code || at(s, j) == ":".code || at(s, j) == "-".code))
				j++;
			var k = j;
			while (Scan.tick() && isTagSpace(at(s, k)))
				k++;
			if (at(s, k) != "=".code) continue;
			k++;
			while (Scan.tick() && isTagSpace(at(s, k)))
				k++;
			var q = at(s, k);
			if (q == "\"".code || q == "'".code) {
				var close = s.indexOf(String.fromCharCode(q), k + 1);
				if (close < 0) return -1;
				j = close + 1;
			} else {
				var v = k;
				while (Scan.tick() && k < s.length) {
					var d = s.fastCodeAt(k);
					if (d <= 32 || d == "\"".code || d == "'".code || d == "=".code || d == "<".code || d == ">".code || d == "`".code) break;
					k++;
				}
				if (k == v) return -1;
				j = k;
			}
		}
	}

	// the end of a closing tag at s[i] ("<"), else -1
	public static function closeTag(s:String, i:Int):Int {
		if (at(s, i + 1) != "/".code || !isAlpha(at(s, i + 2))) return -1;
		var j = i + 3;
		while (Scan.tick() && (isAlnum(at(s, j)) || at(s, j) == "-".code))
			j++;
		while (Scan.tick() && isTagSpace(at(s, j)))
			j++;
		return at(s, j) == ">".code ? j + 1 : -1;
	}

	static inline function isTagSpace(c:Int):Bool
		return c == 32 || c == 9 || c == 10 || c == 13 || c == 12;
}
