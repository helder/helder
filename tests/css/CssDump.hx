import helder.css.Css;
import helder.css.CssToken;
import helder.css.CssValue;
import sys.io.File;

// helder.css's reading of stylesheets for tests/css/differential.mjs:
// each file's tokens (comments are none) and its component values' tree,
// a line each, in the form the script writes @csstools' in.
//
//   CssDump <out dir> <sheet.css>...
class CssDump {
	static function main() {
		var args = Sys.args(), out = args.shift();
		for (path in args) {
			var text = Css.decode(File.getBytes(path)).text, name = haxe.io.Path.withoutDirectory(path);
			var tokens = Css.tokens(text), b = new StringBuf();
			for (t in tokens) {
				b.add(token(t));
				b.add("\n");
			}
			File.saveContent('$out/$name.tokens', b.toString());
			var v = new StringBuf();
			values(v, Css.values(text));
			File.saveContent('$out/$name.values', v.toString());
		}
	}

	static function token(t:CssToken):String {
		var head = '${t.start}\t${t.end - 1}\t';
		return head + switch t.kind {
			case Ident(v): 'ident-token\t${q(v)}';
			case Function(v): 'function-token\t${q(v)}';
			case AtKeyword(v): 'at-keyword-token\t${q(v)}';
			case Hash(v, id): 'hash-token\t${q(v)}\t${id ? "id" : "unrestricted"}';
			case Str(v): 'string-token\t${q(v)}';
			case BadString: "bad-string-token";
			case Url(v): 'url-token\t${q(v)}';
			case BadUrl: "bad-url-token";
			case Delim(v): 'delim-token\t${q(v)}';
			case Number(v, integer, text): 'number-token\t${num(v)}\t${integer ? "integer" : "number"}\t${sign(text)}';
			case Percentage(v, _, text): 'percentage-token\t${num(v)}\t${sign(text)}';
			case Dimension(v, integer, text, unit): 'dimension-token\t${num(v)}\t${integer ? "integer" : "number"}\t${sign(text)}\t${q(unit)}';
			case UnicodeRange(s, e): 'unicode-range-token\t$s\t$e';
			case Whitespace: "whitespace-token";
			case Cdo: "CDO-token";
			case Cdc: "CDC-token";
			case Colon: "colon-token";
			case Semicolon: "semicolon-token";
			case Comma: "comma-token";
			case OpenSquare: "[-token";
			case CloseSquare: "]-token";
			case OpenParen: "(-token";
			case CloseParen: ")-token";
			case OpenCurly: "{-token";
			case CloseCurly: "}-token";
		}
	}

	// (a tree's lines: F/B and its open token's start, its children, E and its close's start or "open")
	static function values(b:StringBuf, list:Array<CssValue>)
		for (v in list)
			switch v {
				case Token(t):
					b.add('t\t${t.start}\n');
				case Function(name, vs, open, close):
					b.add('F\t${open.start}\t${q(name)}\n');
					values(b, vs);
					b.add('E\t${close == null ? "open" : Std.string(close.start)}\n');
				case Block(open, vs, close):
					b.add('B\t${open.start}\n');
					values(b, vs);
					b.add('E\t${close == null ? "open" : Std.string(close.start)}\n');
			}

	static function sign(text:String):String {
		var c = text.charAt(0);
		return c == "+" || c == "-" ? c : "";
	}

	// (as JavaScript's String(n): -0 is 0)
	static function num(v:Float):String
		return v == 0 ? "0" : Std.string(v);

	// (as JSON.stringify writes it)
	static function q(s:String):String {
		var b = new StringBuf();
		b.add('"');
		for (k in 0...s.length) {
			var c = StringTools.fastCodeAt(s, k);
			if (c == '"'.code || c == "\\".code) {
				b.add("\\");
				b.addChar(c);
			} else if (c < 0x20) b.add(switch c {
				case 8: "\\b";
				case 9: "\\t";
				case 10: "\\n";
				case 12: "\\f";
				case 13: "\\r";
				default: "\\u" + StringTools.hex(c, 4).toLowerCase();
			}) else b.addChar(c);
		}
		b.add('"');
		return b.toString();
	}
}
