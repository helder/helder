package helder.css;

// Syntax 3's code point classes (§4.2), for the tokenizer and the
// serializer: a program that only serializes links no tokenizer.
class CssChars {
	public static inline function isDigit(c:Int):Bool
		return c >= "0".code && c <= "9".code;

	public static inline function isHex(c:Int):Bool
		return isDigit(c) || (c >= "a".code && c <= "f".code) || (c >= "A".code && c <= "F".code);

	public static inline function isIdentStart(c:Int):Bool
		return c < 0x80 ? (c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code) || c == "_".code : nonAscii(c);

	public static inline function isIdent(c:Int):Bool
		return c < 0x80 ? (c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code) || c == "_".code || c == "-".code
			|| isDigit(c) : nonAscii(c);

	// (§4.2's non-ASCII ident code points: HTML's custom element names')
	public static function nonAscii(c:Int):Bool
		return c == 0xB7 || (c >= 0xC0 && c <= 0xD6) || (c >= 0xD8 && c <= 0xF6) || (c >= 0xF8 && c <= 0x37D) || (c >= 0x37F && c <= 0x1FFF)
			|| c == 0x200C || c == 0x200D || c == 0x203F || c == 0x2040 || (c >= 0x2070 && c <= 0x218F) || (c >= 0x2C00 && c <= 0x2FEF)
			|| (c >= 0x3001 && c <= 0xD7FF) || (c >= 0xF900 && c <= 0xFDCF) || (c >= 0xFDF0 && c <= 0xFFFD) || c >= 0x10000;

	public static inline function isNonPrintable(c:Int):Bool
		return (c >= 0 && c <= 8) || c == 0xB || (c >= 0xE && c <= 0x1F) || c == 0x7F;
}
