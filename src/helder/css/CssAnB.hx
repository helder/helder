package helder.css;

import helder.css.CssToken.CssTokenKind;
import helder.css.Tokenizer.isDigit;

using StringTools;

// Syntax 3's An+B (§6): the An+Bth items for every n >= 0, counted from 1
class CssAnB {
	public final a:Int;
	public final b:Int;

	public function new(a:Int, b:Int) {
		this.a = a;
		this.b = b;
	}

	// whether the index (from 1) is An+B for some n >= 0
	public function matches(index:Int):Bool {
		if (a == 0) return index == b;
		var d = index - b;
		return d % a == 0 && d / a >= 0;
	}

	// (§9.1)
	public function toString():String {
		if (a == 0) return Std.string(b);
		var s = a == 1 ? "n" : a == -1 ? "-n" : a + "n";
		return b > 0 ? s + "+" + b : b < 0 ? s + b : s;
	}

	// (§6.2: the tokens of <a-n-plus-b>, whitespace around them; null when they are not)
	public static function parse(values:Array<CssValue>):Null<CssAnB> {
		var ts = [];
		for (v in values)
			switch v {
				case Token(t): ts.push(t.kind);
				default: return null;
			}
		var k = 0, n = ts.length;
		function skip()
			while (k < n && ts[k].match(Whitespace))
				k++;
		function end():Bool {
			skip();
			return k == n;
		}
		// (after An: nothing, a signed integer, or + or - and a signless one)
		function rest(a:Int):Null<CssAnB> {
			skip();
			if (k == n) return new CssAnB(a, 0);
			switch ts[k++] {
				case Number(v, true, text) if (signed(text)):
					return end() ? new CssAnB(a, int(v)) : null;
				case Delim(s) if (s == "+" || s == "-"):
					skip();
					if (k == n) return null;
					switch ts[k++] {
						case Number(v, true, text) if (!signed(text)):
							return end() ? new CssAnB(a, s == "-" ? -int(v) : int(v)) : null;
						default:
							return null;
					}
				default:
					return null;
			}
		}
		// (n, n- and n-<digits>, after A)
		function name(a:Int, s:String):Null<CssAnB> {
			var r = Css.lower(s);
			if (r == "n") return rest(a);
			if (r == "n-") {
				skip();
				if (k == n) return null;
				return switch ts[k++] {
					case Number(v, true, text) if (!signed(text)): end() ? new CssAnB(a, -int(v)) : null;
					default: null;
				}
			}
			if (r.length > 2 && r.startsWith("n-") && digits(r, 2)) return end() ? new CssAnB(a, -parseInt(r.substr(2))) : null;
			return null;
		}
		skip();
		if (k == n) return null;
		switch ts[k++] {
			case Number(v, true, _):
				return end() ? new CssAnB(0, int(v)) : null;
			case Dimension(v, true, _, unit):
				return name(int(v), unit);
			case Ident(v):
				var l = Css.lower(v);
				if (l == "odd") return end() ? new CssAnB(2, 1) : null;
				if (l == "even") return end() ? new CssAnB(2, 0) : null;
				return l.startsWith("-") ? name(-1, v.substr(1)) : name(1, v);
			case Delim("+") if (k < n):
				return switch ts[k++] {
					case Ident(v): name(1, v);
					default: null;
				}
			default:
				return null;
		}
	}

	static function signed(text:String):Bool {
		var c = text.fastCodeAt(0);
		return c == "+".code || c == "-".code;
	}

	static function digits(s:String, from:Int):Bool {
		for (k in from...s.length)
			if (!isDigit(s.fastCodeAt(k))) return false;
		return true;
	}

	// (integers past 32 bits clamped)
	static function int(v:Float):Int
		return v >= 2147483647 ? 2147483647 : v <= -2147483648 ? -2147483648 : Std.int(v);

	static function parseInt(s:String):Int
		return int(Std.parseFloat(s));
}
