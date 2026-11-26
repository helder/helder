package helder.css;

import helder.css.CssToken;

// @supports' condition (Conditional 3, 4): a declaration helder.css reads
// as valid, selector() one it parses; not, and, or. font-tech(),
// font-format() and anything else unknown is false.
class CssSupports {
	public static function test(values:Array<CssValue>):Bool
		return try condition(items(values)) catch (e:Bad) false;

	public static function text(s:String):Bool
		return test(Css.values(s));

	static function condition(xs:Array<CssValue>):Bool {
		if (xs.length == 0) throw new Bad();
		var first = word(xs[0]);
		if (first == "not") {
			if (xs.length != 2) throw new Bad();
			return !inParens(xs[1]);
		}
		var op:Null<String> = null, out = inParens(xs[0]);
		var k = 1;
		while (k < xs.length) {
			var w = word(xs[k]);
			if (w != "and" && w != "or" || op != null && w != op || k + 1 >= xs.length) throw new Bad();
			op = w;
			var v = inParens(xs[k + 1]);
			out = op == "and" ? out && v : out || v;
			k += 2;
		}
		return out;
	}

	static function inParens(v:CssValue):Bool
		return switch v {
			case Block(open, values, _) if (open.kind.match(OpenParen)):
				var inner = items(values);
				if (inner.length > 0 && (inner[0].match(Block(_.kind => OpenParen, _, _)) || word(inner[0]) == "not")) condition(inner) else declaration(values);
			case Function(name, values, _, _) if (Css.lower(name) == "selector"): CssSelector.list(values) != null;
			case Function(_, _, _, _): false;
			case _: throw new Bad();
		}

	// (a declaration: its value valid for the property; a custom property's any)
	static function declaration(values:Array<CssValue>):Bool {
		var d = Css.declaration(Css.serialize(values));
		if (d == null) return false;
		if (StringTools.startsWith(d.name, "--")) return true;
		return CssValues.read(Css.lower(d.name), d.value) != null;
	}

	static function items(values:Array<CssValue>):Array<CssValue>
		return [for (v in values) if (!v.match(Token(_.kind => Whitespace))) v];

	static function word(v:CssValue):Null<String>
		return switch v {
			case Token(_.kind => Ident(w)): Css.lower(w);
			case _: null;
		}
}

private class Bad extends haxe.Exception {
	public function new()
		super("not a supports condition");
}
