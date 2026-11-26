package helder.css;

import helder.css.CssToken.CssTokenKind;
import helder.css.CssChars.isDigit;
import helder.css.CssChars.isIdent;

using StringTools;

// Tokens and component values back to text that tokenizes to the same
// tokens (§9): whitespace as one space, an empty comment between two
// tokens that would read as one otherwise (§9's table, and the two
// pairs it leaves out: "<" "!" before an ident starting with "--" or a
// CDC, which read as a CDO, and an ident "--" before a ">", a CDC)
class Serializer {
	public static function tokens(list:Array<CssToken>):String {
		var b = new StringBuf();
		for (k in 0...list.length) {
			var t = list[k];
			if (k > 0 && comment(list[k - 1].kind, t.kind, k > 1 ? list[k - 2].kind : null)) b.add("/**/");
			add(b, t.kind);
		}
		return b.toString();
	}

	public static function values(list:Array<CssValue>):String
		return tokens(flat(list));

	// the tokens of component values, in order (a function's or block's close left out where the text had none)
	public static function flat(list:Array<CssValue>):Array<CssToken> {
		var out = [], stack = [{list: list, k: 0, close: null}];
		while (stack.length > 0) {
			var top = stack[stack.length - 1];
			if (top.k >= top.list.length) {
				stack.pop();
				if (top.close != null) out.push(top.close);
				continue;
			}
			switch top.list[top.k++] {
				case Token(t):
					out.push(t);
				case Function(_, values, open, close) | Block(open, values, close):
					out.push(open);
					stack.push({list: values, k: 0, close: close});
			}
		}
		return out;
	}

	public static function token(t:CssToken):String {
		var b = new StringBuf();
		add(b, t.kind);
		return b.toString();
	}

	static function comment(a:CssTokenKind, b:CssTokenKind, before:Null<CssTokenKind>):Bool {
		// (the column: §9's table's heading for b)
		var col = switch b {
			case Ident(v): if (a.match(Delim("!")) && before != null && before.match(Delim("<")) && v.startsWith("--")) return true; IDENT;
			case Function(_): FUNCTION;
			case Url(_) | BadUrl: URL;
			case Delim("-"): MINUS;
			case Number(_, _, _): NUMBER;
			case Percentage(_, _, _): PERCENTAGE;
			case Dimension(_, _, _, _): DIMENSION;
			case Cdc: if (a.match(Delim("!")) && before != null && before.match(Delim("<"))) return true; CDC;
			case OpenParen: PAREN;
			case Delim("*"): STAR;
			case Delim("%"): PERCENT;
			case Delim(">"): return a.match(Ident("--"));
			default: return false;
		}
		var row = switch a {
			case Ident(_): IDENT | FUNCTION | URL | MINUS | NUMBER | PERCENTAGE | DIMENSION | CDC | PAREN;
			case AtKeyword(_) | Hash(_, _) | Dimension(_, _, _, _) | Delim("#") | Delim("-"):
				IDENT | FUNCTION | URL | MINUS | NUMBER | PERCENTAGE | DIMENSION | CDC;
			case Number(_, _, _): IDENT | FUNCTION | URL | NUMBER | PERCENTAGE | DIMENSION | CDC | PERCENT;
			case Delim("@"): IDENT | FUNCTION | URL | MINUS | CDC;
			case Delim(".") | Delim("+"): NUMBER | PERCENTAGE | DIMENSION;
			case Delim("/"): STAR;
			default: 0;
		}
		return row & col != 0;
	}

	static inline var IDENT = 1;
	static inline var FUNCTION = 2;
	static inline var URL = 4;
	static inline var MINUS = 8;
	static inline var NUMBER = 16;
	static inline var PERCENTAGE = 32;
	static inline var DIMENSION = 64;
	static inline var CDC = 128;
	static inline var PAREN = 256;
	static inline var STAR = 512;
	static inline var PERCENT = 1024;

	static function add(b:StringBuf, k:CssTokenKind)
		switch k {
			case Ident(v):
				ident(b, v);
			case Function(v):
				ident(b, v);
				b.add("(");
			case AtKeyword(v):
				b.add("@");
				ident(b, v);
			case Hash(v, true):
				b.add("#");
				ident(b, v);
			case Hash(v, false):
				b.add("#");
				name(b, v, 0);
			case Str(v):
				string(b, v);
			case BadString:
				// (a newline ends it: the whitespace token after it is a newline's)
				b.add('"\n');
			case Url(v):
				b.add("url(");
				for (c in codes(v))
					if (c == '"'.code || c == "'".code || c == "(".code || c == ")".code || c == "\\".code) {
						b.add("\\");
						b.addChar(c);
					} else if (c <= 32 || c == 0x7F) hexEscape(b, c) else b.addChar(c);
				b.add(")");
			case BadUrl:
				b.add("url(()");
			case Delim("\\"):
				// (only ever before a newline's whitespace, §9)
				b.add("\\\n");
			case Delim(v):
				b.add(v);
			case Number(_, _, text):
				b.add(text);
			case Percentage(_, _, text):
				b.add(text);
				b.add("%");
			case Dimension(_, _, text, unit):
				b.add(text);
				// (a unit "e5" or "e-5" would read as an exponent)
				var c = unit.length > 0 ? unit.fastCodeAt(0) : -1, d = unit.length > 1 ? unit.fastCodeAt(1) : -1;
				if ((c == "e".code || c == "E".code) && (isDigit(d) || (d == "-".code && unit.length > 2 && isDigit(unit.fastCodeAt(2))))) {
					hexEscape(b, c);
					name(b, unit.substr(1), 0);
				} else ident(b, unit);
			case UnicodeRange(start, end):
				b.add("U+" + StringTools.hex(start));
				if (end != start) b.add("-" + StringTools.hex(end));
			case Whitespace:
				b.add(" ");
			case Cdo:
				b.add("<!--");
			case Cdc:
				b.add("-->");
			case Colon:
				b.add(":");
			case Semicolon:
				b.add(";");
			case Comma:
				b.add(",");
			case OpenSquare:
				b.add("[");
			case CloseSquare:
				b.add("]");
			case OpenParen:
				b.add("(");
			case CloseParen:
				b.add(")");
			case OpenCurly:
				b.add("{");
			case CloseCurly:
				b.add("}");
		}

	// (CSSOM's serialize an identifier, by this ED's ident code points)
	public static function ident(b:StringBuf, v:String) {
		var cs = codes(v);
		if (cs.length == 1 && cs[0] == "-".code) {
			b.add("\\-");
			return;
		}
		var start = 0;
		if (cs.length > 0 && isDigit(cs[0])) {
			hexEscape(b, cs[0]);
			start = 1;
		} else if (cs.length > 1 && cs[0] == "-".code && isDigit(cs[1])) {
			b.add("-");
			hexEscape(b, cs[1]);
			start = 2;
		}
		names(b, cs, start);
	}

	static function name(b:StringBuf, v:String, start:Int)
		names(b, codes(v), start);

	static function names(b:StringBuf, cs:Array<Int>, start:Int)
		for (k in start...cs.length) {
			var c = cs[k];
			if (c == 0) b.addChar(0xFFFD) else if (c < 0x20 || c == 0x7F) hexEscape(b, c) else if (isIdent(c)) b.addChar(c) else {
				b.add("\\");
				b.addChar(c);
			}
		}

	// (CSSOM's serialize a string)
	public static function string(b:StringBuf, v:String) {
		b.add('"');
		for (c in codes(v))
			if (c == 0) b.addChar(0xFFFD) else if (c < 0x20 || c == 0x7F) hexEscape(b, c) else if (c == '"'.code || c == "\\".code) {
				b.add("\\");
				b.addChar(c);
			} else b.addChar(c);
		b.add('"');
	}

	static function hexEscape(b:StringBuf, c:Int) {
		b.add("\\");
		b.add(StringTools.hex(c).toLowerCase());
		b.add(" ");
	}

	// the code points of a String (a surrogate pair one, natively and as wasm32-wasi)
	public static function codes(v:String):Array<Int> {
		var out = [], k = 0, n = v.length;
		while (k < n) {
			var c = v.fastCodeAt(k++);
			if (c >= 0xD800 && c < 0xDC00 && k < n) {
				var d = v.fastCodeAt(k);
				if (d >= 0xDC00 && d < 0xE000) {
					c = 0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00);
					k++;
				}
			}
			out.push(c);
		}
		return out;
	}
}
