package helder.css;

import haxe.Exception;
import helder.css.CssTable;
import helder.css.CssGrammar;

using StringTools;

// The value definition syntax read and printed (CSS Values 4 §2), and the
// generated data looked up: a property's definition, a named type's in its
// context (webref's `for`: clip's rect() is not a shape's).
class CssGrammars {
	static var props:Null<Map<String, CssDefinition>>;
	static var types:Null<Map<String, Array<CssTypeDefinition>>>;
	static final parsed = new Map<String, CssGrammar>();

	public static function property(name:String):Null<CssDefinition> {
		if (props == null) props = [for (p in CssTable.properties) p.name => p];
		return props.get(name);
	}

	// (context: the property, then the `<type>`s and `name()`s the reference is inside)
	public static function type(name:String, ?context:Array<String>):Null<CssTypeDefinition> {
		if (types == null) {
			types = new Map();
			for (t in CssTable.types) types.set(t.name, (types.exists(t.name) ? types.get(t.name) : []).concat([t]));
		}
		var all = types.get(name);
		if (all == null) return null;
		if (context != null) for (t in all) for (c in t.scope) if (context.contains(c)) return t;
		for (t in all) if (t.scope.length == 0) return t;
		return all[0];
	}

	// A definition's text parsed once.
	public static function of(syntax:String):CssGrammar {
		var g = parsed.get(syntax);
		if (g == null) parsed.set(syntax, g = parse(syntax));
		return g;
	}

	public static function parse(text:String):CssGrammar {
		var p = new Reader(text);
		var g = p.one();
		p.space();
		if (!p.done()) throw p.error("unexpected");
		return g;
	}

	public static function print(g:CssGrammar):String
		return switch g {
			case Keyword(name): name;
			case Delim(text): text == "," || text == "/" ? text : '\'$text\'';
			case Named(name, null): '<$name>';
			case Named(name, r): '<$name [${bound(r.min, r.unit)},${bound(r.max, r.unit)}]>';
			case Prop(name): '<\'$name\'>';
			case Func(name, Sequence([])): '$name( )';
			case Func(name, args): '$name( ${print(args)} )';
			case Block("[", Sequence([])): "'[' ']'";
			case Block("[", inner): '\'[\' ${print(inner)} \']\'';
			case Block(_, Sequence([])): "( )";
			case Block(_, inner): '( ${print(inner)} )';
			case Sequence(items): join(items, " ", 4);
			case All(items): join(items, " && ", 3);
			case Any(items): join(items, " || ", 2);
			case One(items): join(items, " | ", 1);
			case Repeat(item, min, max, comma): group(item, 5) + multiplier(min, max, comma);
			case Required(item): '[ ${print(item)} ]!';
		}

	static function join(items:Array<CssGrammar>, sep:String, level:Int):String
		return [for (i in items) group(i, level + 1)].join(sep);

	static function group(g:CssGrammar, level:Int):String
		return precedence(g) < level ? '[ ${print(g)} ]' : print(g);

	static function precedence(g:CssGrammar):Int
		return switch g {
			case One(_): 1;
			case Any(_): 2;
			case All(_): 3;
			case Sequence(_): 4;
			case _: 5;
		}

	static function multiplier(min:Int, max:Int, comma:Bool):String
		return switch [min, max, comma] {
			case [0, 1, false]: "?";
			case [0, -1, false]: "*";
			case [1, -1, false]: "+";
			case [1, -1, true]: "#";
			case _: (comma ? "#" : "") + (min == max ? '{$min}' : max == -1 ? '{$min,}' : '{$min,$max}');
		}

	static function bound(x:Float, unit:String):String {
		if (x == Math.POSITIVE_INFINITY) return "∞";
		if (x == Math.NEGATIVE_INFINITY) return "-∞";
		return (x == Math.ffloor(x) && Math.abs(x) < 1e15 ? Std.string(Std.int(x)) : Std.string(x)) + unit;
	}
}

private class Reader {
	final text:String;
	var i = 0;

	public function new(text:String)
		this.text = text;

	public function done():Bool
		return i >= text.length;

	public function error(what:String):Exception
		return new Exception('$what at $i in "$text"');

	public function space()
		while (i < text.length && isSpace(text.fastCodeAt(i))) i++;

	function peek(s:String):Bool {
		space();
		return text.substr(i, s.length) == s;
	}

	function eat(s:String):Bool {
		if (!peek(s)) return false;
		i += s.length;
		return true;
	}

	function expect(s:String)
		if (!eat(s)) throw error('"$s" expected');

	public function one():CssGrammar {
		var items = [any()];
		while (!peek("||") && eat("|")) items.push(any());
		return items.length == 1 ? items[0] : One(items);
	}

	function any():CssGrammar {
		var items = [all()];
		while (eat("||")) items.push(all());
		return items.length == 1 ? items[0] : Any(items);
	}

	function all():CssGrammar {
		var items = [sequence()];
		while (eat("&&")) items.push(sequence());
		return items.length == 1 ? items[0] : All(items);
	}

	function sequence():CssGrammar {
		var items = [];
		while (starts()) items.push(term());
		if (items.length == 0) throw error("a term expected");
		return items.length == 1 ? items[0] : Sequence(items);
	}

	// (what may start a term: not a combinator, a closer, nor the end)
	function starts():Bool {
		space();
		if (done()) return false;
		var c = text.charAt(i);
		return c != "|" && c != "&" && c != "]" && c != ")" && text.substr(i, 3) != "']'";
	}

	// A sequence, or nothing (a function's or a block's empty arguments).
	function inner(close:String):CssGrammar {
		if (peek(close)) return Sequence([]);
		return one();
	}

	function term():CssGrammar {
		var g = atom();
		while (true) {
			space();
			var c = text.charAt(i);
			if (c == "?") g = Repeat(g, 0, 1, false);
			else if (c == "*") g = Repeat(g, 0, -1, false);
			else if (c == "+") g = Repeat(g, 1, -1, false);
			else if (c == "#") {
				i++;
				g = if (text.charAt(i) == "{") {
					var r = braces();
					Repeat(g, r.min, r.max, true);
				} else Repeat(g, 1, -1, true);
				continue;
			} else if (c == "{") {
				var r = braces();
				g = Repeat(g, r.min, r.max, false);
				continue;
			} else if (c == "!") {
				switch g {
					case Repeat(_, _, _, _) | Required(_): throw error("! after a multiplier");
					case _:
				}
				g = Required(g);
			} else break;
			i++;
		}
		return g;
	}

	function braces():{min:Int, max:Int} {
		i++;
		var min = integer(), max = min;
		if (eat(",")) max = peek("}") ? -1 : integer();
		expect("}");
		if (max != -1 && max < min) throw error("{A,B} with B < A");
		return {min: min, max: max};
	}

	function integer():Int {
		space();
		var start = i;
		while (i < text.length && isDigit(text.fastCodeAt(i))) i++;
		if (i == start) throw error("a number expected");
		return Std.parseInt(text.substring(start, i));
	}

	function atom():CssGrammar {
		space();
		var c = text.charAt(i);
		if (c == "[") {
			i++;
			var g = one();
			expect("]");
			if (text.charAt(i) == "!") {
				i++;
				return Required(g);
			}
			return g;
		}
		if (c == "(") {
			i++;
			var g = inner(")");
			expect(")");
			return Block("(", g);
		}
		if (c == "<") return angle();
		if (c == "'") {
			var end = text.indexOf("'", i + 1);
			if (end < 0) throw error("an unclosed quote");
			var s = text.substring(i + 1, end);
			i = end + 1;
			if (s == "[") {
				var g = inner("']'");
				expect("']'");
				return Block("[", g);
			}
			return isIdent(s) ? Keyword(s) : Delim(s);
		}
		var start = i;
		while (i < text.length && isNameCode(text.fastCodeAt(i))) i++;
		if (i > start) {
			var name = text.substring(start, i);
			if (text.charAt(i) == "(") {
				i++;
				var g = inner(")");
				expect(")");
				return Func(name, g);
			}
			return Keyword(name);
		}
		i++;
		return Delim(c);
	}

	// <type>, <type [min,max]>, <'property'>
	function angle():CssGrammar {
		i++;
		if (text.charAt(i) == "'") {
			var end = text.indexOf("'>", i + 1);
			if (end < 0) throw error("an unclosed <'");
			var name = text.substring(i + 1, end);
			i = end + 2;
			return Prop(name);
		}
		var start = i;
		while (i < text.length && text.charAt(i) != ">" && text.charAt(i) != "[" && !isSpace(text.fastCodeAt(i))) i++;
		var name = text.substring(start, i);
		if (name == "") throw error("a type's name expected");
		var range = null;
		if (eat("[")) {
			var min = number();
			expect(",");
			var max = number();
			expect("]");
			if (min.unit != "" && max.unit != "" && min.unit != max.unit) throw error("a range in two units");
			range = {min: min.value, max: max.value, unit: min.unit != "" ? min.unit : max.unit};
		}
		expect(">");
		return Named(name, range);
	}

	function number():{value:Float, unit:String} {
		space();
		var sign = 1.0;
		if (text.charAt(i) == "-") {
			sign = -1;
			i++;
		}
		if (text.substr(i, "∞".length) == "∞") {
			i += "∞".length;
			return {value: sign * Math.POSITIVE_INFINITY, unit: ""};
		}
		var start = i;
		while (i < text.length && (isDigit(text.fastCodeAt(i)) || text.charAt(i) == ".")) i++;
		if (i == start) throw error("a number expected");
		var value = sign * Std.parseFloat(text.substring(start, i));
		start = i;
		while (i < text.length && isLetter(text.fastCodeAt(i))) i++;
		return {value: value, unit: text.substring(start, i)};
	}

	static function isIdent(s:String):Bool {
		if (s == "" || isDigit(s.fastCodeAt(0))) return false;
		for (k in 0...s.length) if (!isNameCode(s.fastCodeAt(k))) return false;
		return s != "-";
	}

	static inline function isSpace(c:Int):Bool
		return c == " ".code || c == "\t".code || c == "\n".code || c == "\r".code;

	static inline function isDigit(c:Int):Bool
		return c >= "0".code && c <= "9".code;

	static inline function isLetter(c:Int):Bool
		return c >= "a".code && c <= "z".code || c >= "A".code && c <= "Z".code;

	static inline function isNameCode(c:Int):Bool
		return isLetter(c) || isDigit(c) || c == "-".code || c == "_".code;
}
