package helder.ui.box;

// Counter styles (Counter Styles 3's predefined ones that CSS 2.1 names):
// a counter's value as text, and a list marker's.
class Counters {
	public static function text(style:String, v:Int):String
		return switch style {
			case "none": "";
			case "disc": "•";
			case "circle": "◦";
			case "square": "▪";
			case "decimal-leading-zero": (v < 10 && v > -10 ? (v < 0 ? "-0" : "0") + Std.string(v < 0 ? -v : v) : Std.string(v));
			case "lower-roman": roman(v).toLowerCase();
			case "upper-roman": roman(v);
			case "lower-alpha" | "lower-latin": alphabetic(v, "abcdefghijklmnopqrstuvwxyz");
			case "upper-alpha" | "upper-latin": alphabetic(v, "ABCDEFGHIJKLMNOPQRSTUVWXYZ");
			case "lower-greek": alphabetic(v, "αβγδεζηθικλμνξοπρστυφχψω");
			case _: Std.string(v);
		}

	// a marker's text: a symbol and a space, or the number and ". "
	public static function marker(style:String, v:Int):Null<String>
		return switch style {
			case "none": null;
			case "disc" | "circle" | "square": text(style, v) + " ";
			case _: text(style, v) + ". ";
		}

	static final VALUES = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
	static final NUMERALS = ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"];

	static function roman(v:Int):String {
		if (v <= 0 || v >= 4000) return Std.string(v);
		var out = "";
		for (k in 0...VALUES.length)
			while (v >= VALUES[k]) {
				out += NUMERALS[k];
				v -= VALUES[k];
			}
		return out;
	}

	static function alphabetic(v:Int, letters:String):String {
		if (v <= 0) return Std.string(v);
		var out = "", n = letters.length;
		while (v > 0) {
			v--;
			out = letters.charAt(v % n) + out;
			v = Std.int(v / n);
		}
		return out;
	}
}
