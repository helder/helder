package helder.css;

import haxe.io.Bytes;

using StringTools;

// A stylesheet's bytes as text (§3.2): the BOM, else the fallback
// encoding (the protocol's label, the "@charset" bytes, the
// environment's, UTF-8), decoded as WHATWG Encoding does. UTF-8, UTF-16
// and the single-byte encodings decode; the multi-byte CJK ones (GBK,
// gb18030, Big5, EUC-JP, ISO-2022-JP, Shift_JIS, EUC-KR) do not, so their
// labels count as unknown ones.
class Encoding {
	// an encoding's name from a label (WHATWG's get an encoding), null for none this decodes
	public static function get(label:String):Null<String> {
		var name = EncodingData.name(Css.lower(label.trim()));
		if (name == null) return null;
		return name == "utf-8" || name == "utf-16le" || name == "utf-16be" || name == "replacement" || name == "x-user-defined"
			|| EncodingData.single(name) != null ? name : null;
	}

	// (§3.2's determine the fallback encoding)
	public static function fallback(bytes:Bytes, ?protocol:String, ?environment:String):String {
		var e = protocol == null ? null : get(protocol);
		if (e != null) return e;
		var label = charset(bytes);
		e = label == null ? null : get(label);
		if (e == "utf-16be" || e == "utf-16le") return "utf-8";
		if (e != null) return e;
		e = environment == null ? null : get(environment);
		return e ?? "utf-8";
	}

	// (the label of an "@charset "...";" the bytes start with, in their first 1024)
	static function charset(bytes:Bytes):Null<String> {
		var prefix = '@charset "', start = prefix.length, n = bytes.length < 1024 ? bytes.length : 1024;
		if (n <= start) return null;
		for (k in 0...start)
			if (bytes.get(k) != prefix.fastCodeAt(k)) return null;
		var k = start;
		while (k < n && bytes.get(k) != '"'.code && bytes.get(k) <= 0x7F && bytes.get(k) >= 1)
			k++;
		if (k + 1 >= n || bytes.get(k) != '"'.code || bytes.get(k + 1) != ";".code) return null;
		return bytes.getString(start, k - start);
	}

	// (WHATWG's decode: a BOM first, then the fallback encoding. One
	// function, not a small one calling fallback: hxmc inlines a small
	// function holding a reference across a call, and two copies of it in
	// one caller lost the second's shadow-stack frame, its bytes overwritten)
	public static function decode(bytes:Bytes, ?protocol:String, ?environment:String):{text:String, encoding:String} {
		var n = bytes.length;
		if (n >= 3 && bytes.get(0) == 0xEF && bytes.get(1) == 0xBB && bytes.get(2) == 0xBF) return {text: utf8(bytes, 3), encoding: "utf-8"};
		if (n >= 2 && bytes.get(0) == 0xFE && bytes.get(1) == 0xFF) return {text: utf16(bytes, 2, true), encoding: "utf-16be"};
		if (n >= 2 && bytes.get(0) == 0xFF && bytes.get(1) == 0xFE) return {text: utf16(bytes, 2, false), encoding: "utf-16le"};
		var encoding = fallback(bytes, protocol, environment);
		var text = switch encoding {
			case "utf-8": utf8(bytes, 0);
			case "utf-16be": utf16(bytes, 0, true);
			case "utf-16le": utf16(bytes, 0, false);
			case "replacement": n == 0 ? "" : "\u{FFFD}";
			case "x-user-defined": single(bytes, null);
			default: single(bytes, EncodingData.single(encoding));
		}
		return {text: text, encoding: encoding};
	}

	static function utf8(bytes:Bytes, from:Int):String {
		var b = new StringBuf(), need = 0, seen = 0, cp = 0, lower = 0x80, upper = 0xBF, k = from, n = bytes.length;
		while (k < n) {
			var c = bytes.get(k++);
			if (need == 0) {
				if (c < 0x80) b.addChar(c) else if (c >= 0xC2 && c <= 0xDF) {
					need = 1;
					cp = c & 0x1F;
				} else if (c >= 0xE0 && c <= 0xEF) {
					if (c == 0xE0) lower = 0xA0;
					if (c == 0xED) upper = 0x9F;
					need = 2;
					cp = c & 0xF;
				} else if (c >= 0xF0 && c <= 0xF4) {
					if (c == 0xF0) lower = 0x90;
					if (c == 0xF4) upper = 0x8F;
					need = 3;
					cp = c & 0x7;
				} else b.addChar(0xFFFD);
				continue;
			}
			if (c < lower || c > upper) {
				need = seen = cp = 0;
				lower = 0x80;
				upper = 0xBF;
				b.addChar(0xFFFD);
				k--;
				continue;
			}
			lower = 0x80;
			upper = 0xBF;
			cp = (cp << 6) | (c & 0x3F);
			if (++seen == need) {
				b.addChar(cp);
				need = seen = cp = 0;
			}
		}
		if (need != 0) b.addChar(0xFFFD);
		return b.toString();
	}

	static function utf16(bytes:Bytes, from:Int, big:Bool):String {
		var b = new StringBuf(), k = from, n = bytes.length, lead = -1;
		while (k + 1 < n) {
			var u = big ? (bytes.get(k) << 8) | bytes.get(k + 1) : bytes.get(k) | (bytes.get(k + 1) << 8);
			k += 2;
			if (lead >= 0) {
				var l = lead;
				lead = -1;
				if (u >= 0xDC00 && u <= 0xDFFF) {
					b.addChar(0x10000 + ((l - 0xD800) << 10) + (u - 0xDC00));
					continue;
				}
				b.addChar(0xFFFD);
			}
			if (u >= 0xD800 && u <= 0xDBFF) lead = u else if (u >= 0xDC00 && u <= 0xDFFF) b.addChar(0xFFFD) else b.addChar(u);
		}
		if (lead >= 0 || k < n) b.addChar(0xFFFD);
		return b.toString();
	}

	// (table: bytes 0x80 to 0xFF; null: x-user-defined's U+F780 up)
	static function single(bytes:Bytes, table:Null<String>):String {
		var b = new StringBuf();
		for (k in 0...bytes.length) {
			var c = bytes.get(k);
			b.addChar(c < 0x80 ? c : table == null ? 0xF780 + c - 0x80 : table.fastCodeAt(c - 0x80));
		}
		return b.toString();
	}
}
