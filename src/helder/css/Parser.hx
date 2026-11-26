package helder.css;

import helder.css.CssToken.CssTokenKind;
import helder.css.CssValue;
import helder.css.CssRule;

using StringTools;

// Syntax 3's parser (§5) over a token stream: the tokens of a text, the
// text kept for a declaration's original text. Every rule is valid in
// its context here: validity is the grammar's above it (selectors, the
// at-rules' own), so no invalid rule error is ever returned.
class Parser {
	// (rules nested deeper are read past as values, not parsed: the
	// parser recurses for rules, and a stack has a limit)
	public static inline var DEPTH = 256;

	final tokens:Array<CssToken>;
	final n:Int;
	final source:String;
	var i = 0;
	var depth = 0;

	public function new(source:String, ?tokens:Array<CssToken>) {
		this.source = source;
		this.tokens = tokens ?? Tokenizer.tokenize(source);
		n = this.tokens.length;
	}

	public inline function empty():Bool
		return i >= n;

	public function whitespace() {
		while (i < n && tokens[i].kind.match(Whitespace))
			i++;
	}

	// (§5.5.1)
	public function sheet():Array<CssRule> {
		var rules = [];
		while (i < n) {
			switch tokens[i].kind {
				case Whitespace | Cdo | Cdc:
					i++;
				case AtKeyword(_):
					rules.push(atRule(false));
				default:
					var r = qualified(false, false);
					if (r != null) rules.push(r);
			}
		}
		return rules;
	}

	// (§5.5.2; never nothing: every at-rule is valid here)
	public function atRule(nested:Bool):CssRule {
		var name = switch tokens[i].kind {
			case AtKeyword(v): v;
			default: throw "not an at-keyword";
		}
		i++;
		var prelude = [];
		while (i < n) {
			var t = tokens[i];
			switch t.kind {
				case Semicolon:
					i++;
					return At(name, prelude, null);
				case CloseCurly if (nested):
					return At(name, prelude, null);
				case CloseCurly:
					prelude.push(Token(t));
					i++;
				case OpenCurly:
					return At(name, prelude, block());
				default:
					prelude.push(value());
			}
		}
		return At(name, prelude, null);
	}

	// (§5.5.3; semicolon: the stop token)
	public function qualified(semicolon:Bool, nested:Bool):Null<CssRule> {
		var prelude = [];
		while (i < n) {
			var t = tokens[i];
			switch t.kind {
				case Semicolon if (semicolon):
					return null;
				case CloseCurly if (nested):
					return null;
				case CloseCurly:
					prelude.push(Token(t));
					i++;
				case OpenCurly:
					if (custom(prelude)) {
						if (nested) bad(true) else block();
						return null;
					}
					var items = block();
					var declarations = items.length == 0 ? [] : switch items[0] {
						case Declarations(d):
							items.shift();
							d;
						default: [];
					}
					return Qualified(prelude, declarations, items);
				default:
					prelude.push(value());
			}
		}
		return null;
	}

	// (the prelude's first two non-whitespace values: an ident starting with "--" and a colon)
	static function custom(prelude:Array<CssValue>):Bool {
		var k = 0;
		for (v in prelude)
			switch v {
				case Token({kind: Whitespace}):
				case Token({kind: Ident(name)}) if (k == 0 && name.startsWith("--")):
					k++;
				case Token({kind: Colon}) if (k == 1):
					return true;
				default:
					return false;
			}
		return false;
	}

	// (§5.5.4)
	function block():Array<CssRule> {
		i++;
		if (depth >= DEPTH) {
			while (i < n && !tokens[i].kind.match(CloseCurly))
				value();
			i++;
			return [];
		}
		depth++;
		var rules = contents();
		depth--;
		i++;
		return rules;
	}

	// (§5.5.5; the ED returns rules at EOF or "}" without the last run of
	// declarations, an erratum: it is appended, as the drafts before did)
	public function contents():Array<CssRule> {
		var rules = [], decls = [];
		while (i < n) {
			var t = tokens[i];
			switch t.kind {
				case Whitespace | Semicolon:
					i++;
				case CloseCurly:
					break;
				case AtKeyword(_):
					if (decls.length > 0) {
						rules.push(Declarations(decls));
						decls = [];
					}
					rules.push(atRule(true));
				default:
					var mark = i, d = declaration(true);
					if (d != null) decls.push(d) else {
						i = mark;
						var r = qualified(true, true);
						if (r != null) {
							if (decls.length > 0) {
								rules.push(Declarations(decls));
								decls = [];
							}
							rules.push(r);
						}
					}
			}
		}
		if (decls.length > 0) rules.push(Declarations(decls));
		return rules;
	}

	// (§5.5.6; nested: the caller restores its mark on nothing, so the
	// remnants of a bad one are not read: the early exits of its
	// implementation note)
	public function declaration(nested:Bool):Null<CssDeclaration> {
		var first = tokens[i];
		var name = switch first.kind {
			case Ident(v): v;
			default: null;
		}
		if (name == null) return fail(nested);
		i++;
		whitespace();
		if (i >= n || !tokens[i].kind.match(Colon)) return fail(nested);
		var end = tokens[i].end;
		i++;
		whitespace();
		var from = i, isCustom = name.startsWith("--");
		var value = values(SEMICOLON, nested, !isCustom && nested);
		if (value == null) return null;
		var to = i;
		var last = to - 1;
		while (last >= from && tokens[last].kind.match(Whitespace))
			last--;
		if (last >= from) end = tokens[last].end;
		var important = false, last = lastSolid(value, value.length), before = last < 0 ? -1 : lastSolid(value, last);
		if (before >= 0) switch [value[before], value[last]] {
			case [Token({kind: Delim("!")}), Token({kind: Ident(v)})] if (v.length == 9 && Css.lower(v) == "important"):
				value.splice(last, 1);
				value.splice(before, 1);
				important = true;
			default:
		}
		while (value.length > 0 && value[value.length - 1].match(Token({kind: Whitespace})))
			value.pop();
		var text = null;
		if (isCustom) text = value.length == 0 ? "" : source.substring(startOf(value[0]), endOf(value[value.length - 1])) else {
			var curly = false, solid = 0;
			for (v in value)
				switch v {
					case Token({kind: Whitespace}):
					case Block({kind: OpenCurly}, _, _):
						curly = true;
						solid++;
					default:
						solid++;
				}
			if (curly && solid > 1) return null;
			if (name.length == 13 && Css.lower(name) == "unicode-range" && to > from) {
				var p = new Parser(source, Tokenizer.tokenize(source, true, tokens[from].start, tokens[to - 1].end));
				value = p.values(NONE, false, false);
			}
		}
		return new CssDeclaration(name, value, important, text, first.start, end);
	}

	function fail(nested:Bool):Null<CssDeclaration> {
		if (!nested) bad(false);
		return null;
	}

	static function lastSolid(value:Array<CssValue>, before:Int):Int {
		var k = before - 1;
		while (k >= 0 && value[k].match(Token({kind: Whitespace})))
			k--;
		return k;
	}

	// (§5.5.6, the remnants of a bad declaration)
	function bad(nested:Bool) {
		while (i < n) {
			switch tokens[i].kind {
				case Semicolon:
					i++;
					return;
				case CloseCurly if (nested):
					return;
				case CloseCurly:
					i++;
				default:
					value();
			}
		}
	}

	// (§5.5.7; stop: the stop token, NONE, SEMICOLON or COMMA. curly: give up
	// (null) where a declaration can no longer be one, a top-level {} block
	// being a non-custom property's whole value alone: a block after other
	// values, or anything but !important after a block)
	public function values(stop:Int, nested:Bool, curly:Bool):Null<Array<CssValue>> {
		var out = [], solid = 0, block = false;
		while (i < n) {
			var t = tokens[i];
			switch t.kind {
				case Semicolon if (stop == SEMICOLON):
					break;
				case Comma if (stop == COMMA):
					break;
				case CloseCurly if (nested):
					break;
				case CloseCurly:
					out.push(Token(t));
					i++;
				case Whitespace:
					out.push(Token(t));
					i++;
				case OpenCurly if (curly):
					if (solid > 0) return null;
					out.push(value());
					solid++;
					block = true;
				case Delim("!") if (curly && block && solid == 1):
					out.push(Token(t));
					i++;
					solid++;
				case Ident(_) if (curly && block && solid == 2):
					out.push(Token(t));
					i++;
					solid++;
				default:
					if (curly && block) return null;
					out.push(value());
					solid++;
			}
		}
		return out;
	}

	public static inline var NONE = 0;
	public static inline var SEMICOLON = 1;
	public static inline var COMMA = 2;

	// (§5.4.10)
	public function commaList():Array<Array<CssValue>> {
		var groups = [];
		while (i < n) {
			groups.push(values(COMMA, false, false));
			i++;
		}
		return groups;
	}

	// (§5.4.5)
	public function declarationList():Array<CssDeclaration> {
		var decls = [];
		while (true) {
			whitespace();
			if (i >= n) return decls;
			switch tokens[i].kind {
				case Semicolon:
					i++;
				case AtKeyword(_):
					atRule(false);
				default:
					var d = declaration(false);
					if (d != null) decls.push(d);
			}
		}
	}

	public inline function atKeyword():Bool
		return i < n && tokens[i].kind.match(AtKeyword(_));

	// (§5.5.8 to §5.5.10, without recursion: blocks and functions nest as deep as the text)
	public function value():CssValue {
		var t = tokens[i++];
		var close = closer(t.kind);
		if (close < 0) return Token(t);
		var stack:Array<Frame> = [], frame = new Frame(t, close);
		while (true) {
			if (i >= n) {
				var v = frame.value(null);
				while (stack.length > 0) {
					frame = stack.pop();
					frame.values.push(v);
					v = frame.value(null);
				}
				return v;
			}
			var u = tokens[i++];
			if (closes(u.kind, frame.close)) {
				var v = frame.value(u);
				if (stack.length == 0) return v;
				frame = stack.pop();
				frame.values.push(v);
				continue;
			}
			var c = closer(u.kind);
			if (c < 0) frame.values.push(Token(u)) else {
				stack.push(frame);
				frame = new Frame(u, c);
			}
		}
	}

	// 0: "}", 1: "]", 2: ")"; -1: not an opening token
	static inline function closer(k:CssTokenKind):Int
		return switch k {
			case OpenCurly: 0;
			case OpenSquare: 1;
			case OpenParen | Function(_): 2;
			default: -1;
		}

	static inline function closes(k:CssTokenKind, close:Int):Bool
		return switch k {
			case CloseCurly: close == 0;
			case CloseSquare: close == 1;
			case CloseParen: close == 2;
			default: false;
		}

	public static function startOf(v:CssValue):Int
		return switch v {
			case Token(t): t.start;
			case Function(_, _, open, _) | Block(open, _, _): open.start;
		}

	public static function endOf(v:CssValue):Int {
		while (true)
			switch v {
				case Token(t):
					return t.end;
				case Function(_, values, open, close) | Block(open, values, close):
					if (close != null) return close.end;
					if (values.length == 0) return open.end;
					v = values[values.length - 1];
			}
	}
}

private class Frame {
	public final open:CssToken;
	public final close:Int;
	public final values:Array<CssValue> = [];

	public function new(open:CssToken, close:Int) {
		this.open = open;
		this.close = close;
	}

	public function value(end:Null<CssToken>):CssValue
		return switch open.kind {
			case Function(name): Function(name, values, open, end);
			default: Block(open, values, end);
		}
}
