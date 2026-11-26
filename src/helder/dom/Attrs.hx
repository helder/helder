package helder.dom;

using StringTools;

// The parser's attributes before anyone reads them: five ints each in an
// array, read from the source when asked for (no string, no Attr node made
// while parsing). An attribute is its name (an index of Tags' table, or 0
// and its span in the source; NAME_DIRTY: ASCII upper case or NUL in it)
// and its value's span (VALUE_DIRTY: a reference, CR or NUL in it). A value
// cannot end inside a character reference, so its references are read from
// the span with the tokenizer's rules for an attribute's, as it would have.
@:noCompletion class Attrs {
	public static inline var SIZE = 5;
	public static inline var NAME_DIRTY = 1 << 16;
	public static inline var VALUE_DIRTY = 1 << 17;
	static inline var REF = 0xFFFF;

	public static function name(src:String, raw:Array<Int>, i:Int):String {
		var k = i * SIZE, ref = raw[k] & REF;
		if (ref != 0) return Tags.name(ref);
		var from = raw[k + 1], to = raw[k + 2];
		if (raw[k] & NAME_DIRTY == 0) return Tags.intern(src, from, to) ?? src.substring(from, to);
		var b = new StringBuf();
		for (j in from...to) {
			var c = src.fastCodeAt(j);
			b.addChar(c >= "A".code && c <= "Z".code ? c + 32 : c == 0 ? 0xFFFD : c);
		}
		return b.toString();
	}

	// the name is n (no string made for a clean one)
	public static function nameIs(src:String, raw:Array<Int>, i:Int, n:String):Bool {
		var k = i * SIZE, ref = raw[k] & REF;
		if (ref != 0) return Tags.name(ref) == n;
		if (raw[k] & NAME_DIRTY != 0) return name(src, raw, i) == n;
		var from = raw[k + 1], to = raw[k + 2];
		if (to - from != n.length) return false;
		for (j in 0...n.length)
			if (src.fastCodeAt(from + j) != n.fastCodeAt(j)) return false;
		return true;
	}

	public static function value(src:String, raw:Array<Int>, i:Int):String {
		var k = i * SIZE, from = raw[k + 3], to = raw[k + 4];
		if (from == to) return "";
		return raw[k] & VALUE_DIRTY == 0 ? src.substring(from, to) : decode(src, from, to);
	}

	// an attribute value's text (attribute: else a text's): references, CR and NUL as the tokenizer reads them there
	public static function decode(s:String, from:Int, to:Int, attribute = true):String {
		var b = new StringBuf(), i = from;
		while (i < to) {
			var c = s.fastCodeAt(i);
			if (c == "\r".code) {
				b.addChar("\n".code);
				i += i + 1 < to && s.fastCodeAt(i + 1) == "\n".code ? 2 : 1;
			} else if (c == 0) {
				b.addChar(0xFFFD);
				i++;
			} else if (c == "&".code) i = reference(s, i, to, b, attribute);
			else {
				b.addChar(c);
				i++;
			}
		}
		return b.toString();
	}

	static inline function isAlnum(c:Int):Bool
		return c >= "a".code && c <= "z".code || c >= "A".code && c <= "Z".code || c >= "0".code && c <= "9".code;

	static inline function isHex(c:Int):Bool
		return c >= "0".code && c <= "9".code || c >= "a".code && c <= "f".code || c >= "A".code && c <= "F".code;

	// a reference at s[at] ("&"): its text added, the index after it
	static function reference(s:String, at:Int, to:Int, b:StringBuf, attribute:Bool):Int {
		var i = at + 1;
		if (i < to && s.fastCodeAt(i) == "#".code) {
			var j = i + 1, hex = j < to && (s.fastCodeAt(j) == "x".code || s.fastCodeAt(j) == "X".code);
			if (hex) j++;
			var digits = j, code = 0;
			while (j < to && (hex ? isHex(s.fastCodeAt(j)) : s.fastCodeAt(j) >= "0".code && s.fastCodeAt(j) <= "9".code)) {
				var c = s.fastCodeAt(j);
				var d = c <= "9".code ? c - 0x30 : c <= "F".code ? c - 0x37 : c - 0x57;
				code = code * (hex ? 16 : 10) + d;
				if (code > 0x10FFFF) code = 0x110000;
				j++;
			}
			if (j == digits) {
				b.addSub(s, at, j - at);
				return j;
			}
			if (j < to && s.fastCodeAt(j) == ";".code) j++;
			b.addChar(Tokenizer.referenceCode(code));
			return j;
		}
		var start = i, k = i;
		while (k < to && k - start < Entities.LONGEST && isAlnum(s.fastCodeAt(k)))
			k++;
		if (k == start) {
			b.addChar("&".code);
			return at + 1;
		}
		var matched = -1, value:Null<String> = null;
		if (k < to && s.fastCodeAt(k) == ";".code) {
			value = Entities.get(s.substring(start, k + 1));
			if (value != null) matched = k + 1;
		}
		if (value == null) {
			var j = k;
			while (j > start) {
				value = Entities.get(s.substring(start, j));
				if (value != null) {
					matched = j;
					break;
				}
				j--;
			}
		}
		// (no reference: the "&" and the letters as they are; a legacy name before = or a letter: for historical reasons, the same)
		if (value == null) {
			b.addSub(s, at, k - at);
			return k;
		}
		var following = matched < to ? s.fastCodeAt(matched) : -1;
		if (attribute && s.fastCodeAt(matched - 1) != ";".code && (following == "=".code || isAlnum(following))) {
			b.addSub(s, at, matched - at);
			return matched;
		}
		b.add(value);
		return matched;
	}
}
