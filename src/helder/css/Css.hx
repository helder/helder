package helder.css;

import haxe.io.Bytes;

// CSS Syntax 3's entry points (§5.4) on text: what the rest of helder.css
// and the values above it read stylesheets, declarations and values with.
// Nothing throws: what is not one is null (the spec's syntax error) or
// left out.
class Css {
	// (§4: every token; ranges: unicode-range tokens, the unicode-range descriptor's tokenizing)
	public static function tokens(text:String, ranges = false):Array<CssToken>
		return Tokenizer.tokenize(text, ranges);

	// parse a stylesheet (and a stylesheet's contents: the same on text)
	public static function sheet(text:String):Array<CssRule>
		return new Parser(text).sheet();

	// a stylesheet's bytes as text (§3.2): the encoding a BOM, the
	// protocol's label (Content-Type's charset), the "@charset" bytes or the
	// environment's says, else UTF-8; encoding: its WHATWG name
	public static function decode(bytes:Bytes, ?protocol:String, ?environment:String):{text:String, encoding:String}
		return Encoding.decode(bytes, protocol, environment);

	// parse a rule: one, whitespace around it
	public static function rule(text:String):Null<CssRule> {
		var p = new Parser(text);
		p.whitespace();
		if (p.empty()) return null;
		var r = p.atKeyword() ? p.atRule(false) : p.qualified(false, false);
		if (r == null) return null;
		p.whitespace();
		return p.empty() ? r : null;
	}

	// parse a declaration: one, whitespace around it ("a: b", @supports' condition)
	public static function declaration(text:String):Null<CssDeclaration> {
		var p = new Parser(text);
		p.whitespace();
		if (p.empty()) return null;
		var d = p.declaration(false);
		if (d == null) return null;
		p.whitespace();
		return p.empty() ? d : null;
	}

	// parse a list of declarations: a style attribute's, at-rules left out
	public static function declarations(text:String):Array<CssDeclaration>
		return new Parser(text).declarationList();

	// a block's contents (§5.5.5) as text: declarations, nested rules and at-rules
	public static function block(text:String):Array<CssRule>
		return new Parser(text).contents();

	// parse a component value: one, whitespace around it
	public static function value(text:String):Null<CssValue> {
		var p = new Parser(text);
		p.whitespace();
		if (p.empty()) return null;
		var v = p.value();
		p.whitespace();
		return p.empty() ? v : null;
	}

	// parse a list of component values
	public static function values(text:String):Array<CssValue>
		return new Parser(text).values(Parser.NONE, false, false);

	// parse a comma-separated list of component values: the values between top-level commas
	public static function list(text:String):Array<Array<CssValue>>
		return new Parser(text).commaList();

	// text that tokenizes to these tokens again (§9)
	public static function serialize(values:Array<CssValue>):String
		return Serializer.values(values);

	public static function serializeTokens(tokens:Array<CssToken>):String
		return Serializer.tokens(tokens);

	// ASCII lowercase: CSS's keywords match ASCII case-insensitively, so
	// "İmportant" is not "important" (String.toLowerCase folds U+0130 to "i")
	public static function lower(s:String):String {
		for (k in 0...s.length) {
			var c = StringTools.fastCodeAt(s, k);
			if (c >= "A".code && c <= "Z".code) {
				var b = new StringBuf();
				b.addSub(s, 0, k);
				for (j in k...s.length) {
					var d = StringTools.fastCodeAt(s, j);
					b.addChar(d >= "A".code && d <= "Z".code ? d + 32 : d);
				}
				return b.toString();
			}
		}
		return s;
	}
}
