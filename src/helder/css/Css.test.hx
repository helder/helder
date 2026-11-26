package helder.css;

import haxe.io.Bytes;
import helder.css.CssToken.CssTokenKind;
import helder.test.Gen;
import helder.test.Test;

using StringTools;

// helder.css's syntax: examples beside tests/css's conformance check
// (css-parsing-tests), and its properties: tokens printed tokenize the
// same, offsets cover the text, any text and mutated stylesheets parse
// without throwing in bounded time
function tests() {
	describe("tokens", () -> {
		test("kinds", () -> equals(kinds("a:b 1.5em 50% #x 'q' url(u) @m ,;"), [
			Ident("a"), Colon, Ident("b"), Whitespace, Dimension(1.5, false, "1.5", "em"), Whitespace, Percentage(50, true, "50"), Whitespace,
			Hash("x", true), Whitespace, Str("q"), Whitespace, Url("u"), Whitespace, AtKeyword("m"), Whitespace, Comma, Semicolon
		]));
		test("offsets: the text's, comments between", () -> {
			var ts = Css.tokens("a /* c */ b");
			equals([for (t in ts) [t.start, t.end]], [[0, 1], [1, 2], [9, 10], [10, 11]]);
		});
		test("a surrogate pair is one code point: an ident's", () -> {
			var text = "a\u{1F600}b \u{1F600}";
			equals(kinds(text), [Ident("a\u{1F600}b"), Whitespace, Ident("\u{1F600}")]);
			equals(Css.tokens(text)[2].end, text.length);
		});
		test("filtered as read: CR LF one newline, NUL U+FFFD", () -> {
			equals(kinds("'a\\\r\nb'"), [Str("ab")]);
			equals(kinds("\\61\r\nb"), [Ident("ab")]);
			equals(kinds("a\x00"), [Ident("a\u{FFFD}")]);
			equals(kinds("url(\x00)"), [Url("\u{FFFD}")]);
		});
		test("a lone surrogate is U+FFFD", () -> {
			var text = "a" + String.fromCharCode(0xD800);
			// (Eval's strings are code points: a surrogate there is its own)
			if (text.length == 2) equals(kinds(text), [Ident("a\u{FFFD}")]);
		});
		test("U+0080 is not an ident code point (HTML's custom element names')", () -> equals(kinds("\u{80}a"), [Delim("\u{80}"), Ident("a")]));
		test("unicode ranges where allowed", () -> {
			equals(kinds("U+0-7F"), [Ident("U"), Number(0, true, "+0"), Dimension(-7, true, "-7", "F")]);
			equals([for (t in Css.tokens("U+0-7F, u+4??", true)) t.kind], [UnicodeRange(0, 0x7F), Comma, Whitespace, UnicodeRange(0x400, 0x4FF)]);
		});
	});
	describe("rules", () -> {
		test("a style rule's declarations and nested rules, in order", () -> switch Css.sheet("a { color: red; &:hover { color: blue } b: c !important }") {
			case [Qualified(prelude, [d], [Qualified(_, [hover], []), Declarations([e])])]:
				equals(Css.serialize(prelude), "a ");
				equals([d.name, Css.serialize(d.value)], ["color", "red"]);
				equals(Css.serialize(hover.value), "blue");
				equals([e.name, Css.serialize(e.value), Std.string(e.important)], ["b", "c", "true"]);
			case r: fail('$r');
		});
		test("at-rules: a statement's prelude, a block's contents", () -> switch Css.sheet("@import 'a.css' screen; @media print { p { x: y } }") {
			case [At("import", _, null), At("media", prelude, [Qualified(_, [d], [])])]:
				equals(Css.serialize(prelude), " print ");
				equals(d.name, "x");
			case r: fail('$r');
		});
		test("a declaration's run after a nested rule: a nested declarations rule", () -> switch Css.block("a: b; c {} d: e") {
			case [Declarations([a]), Qualified(_, [], []), Declarations([d])]: equals([a.name, d.name], ["a", "d"]);
			case r: fail('$r');
		});
		test("a custom property keeps its text, blocks and all", () -> {
			var d = require(Css.declaration("--x:  { a: b } c /* d */ !important"));
			equals([d.text, Std.string(d.important)], ["{ a: b } c", "true"]);
		});
		test("a custom property's look-alike rule is dropped", () -> equals(Css.sheet("--x:hover { a: b } p {}").length, 1));
		test("unicode-range's value is tokenized with ranges", () -> switch Css.declarations("unicode-range: U+0-7F, u+4??; x: U+1") {
			case [ur, x]:
				equals([for (v in ur.value) switch v {
					case Token(t): t.kind;
					default: null;
				}], [UnicodeRange(0, 0x7F), Comma, Whitespace, UnicodeRange(0x400, 0x4FF)]);
				equals(x.value.length, 2);
			case r: fail('$r');
		});
		test("a style attribute's declarations: at-rules and bad ones left out", () -> equals([for (d in Css.declarations("color: red; @x y; 1: 2; margin:0 !IMPORTANT")) d.name + "=" + Css.serialize(d.value) + d.important], ["color=redfalse", "margin=0true"]));
		test("!İmportant is not !important (ASCII case-insensitive)", () -> equals(require(Css.declaration("a: b !\u{130}mportant")).important, false));
		test("offsets of a declaration", () -> {
			var d = require(Css.declaration("  color : red "));
			equals([d.start, d.end], [2, 13]);
		});
		test("entry points' syntax errors are null", () -> {
			equals(Css.rule("a {} b {}"), null);
			equals(Css.declaration("a: b; c: d"), null);
			equals(Css.value("a b"), null);
		});
		test("a comma-separated list", () -> equals([for (g in Css.list("a, b c ,d")) Css.serialize(g)], ["a", " b c ", "d"]));
		test("10,000 nested blocks, functions and rules: read without recursion or past the limit", () -> {
			var deep = [for (_ in 0...10000) "a{"].join("") + [for (_ in 0...10000) "("].join("") + "f(" + [for (_ in 0...10000) "["].join("");
			equals(Css.sheet(deep).length, 1);
			equals(Css.serialize(Css.values(deep)), deep);
		});
	});
	describe("serialize", () -> {
		test("comments where two tokens would read as one", () -> {
			for (s in ["a/**/b", "1/**/2", "#a/**/-b", "<!/**/--x", "<!/**/-->", "--/**/>", "a/**/(", "1/**/%", "\\\n", "//**/*"]) {
				var ts = Css.tokens(s);
				equals(kinds(Css.serializeTokens(ts)), [for (t in ts) t.kind], s);
			}
		});
		test("escapes: a digit first, e as a unit, a string's quote", () -> {
			equals(Css.serializeTokens([new CssToken(Ident("1a"), 0, 0)]), "\\31 a");
			equals(Css.serializeTokens([new CssToken(Dimension(1, true, "1", "e3"), 0, 0)]), "1\\65 3");
			equals(Css.serializeTokens([new CssToken(Str('a"\n'), 0, 0)]), '"a\\"\\a "');
			equals(Css.serializeTokens([new CssToken(Ident("-"), 0, 0)]), "\\-");
		});
	});
	describe("An+B", () -> {
		test("parsed", () -> equals([for (s in ["odd", "-n+3", "2n - 1", "+n", "5", "3n-", "n- 2"]) {
			var r = CssAnB.parse(Css.values(s));
			r == null ? "null" : r.toString();
		}], ["2n+1", "-n+3", "2n-1", "n", "5", "null", "n-2"]));
		test("matches", () -> {
			var odd = new CssAnB(2, 1), first3 = new CssAnB(-1, 3);
			equals([for (k in 1...7) odd.matches(k)], [true, false, true, false, true, false]);
			equals([for (k in 1...5) first3.matches(k)], [true, true, true, false]);
		});
	});
	describe("decode", () -> {
		test("a BOM, then @charset, then the environment", () -> {
			equals(Css.decode(Bytes.ofHex("fffe40")).encoding, "utf-16le");
			var b = Bytes.ofString('@charset "windows-1252"; ?');
			b.set(b.length - 1, 0x80);
			equals(Css.decode(b).text.charCodeAt(25), 0x20AC);
			equals(Css.decode(Bytes.ofHex("e9"), null, "latin1").text, "\u{E9}");
		});
	});
	describe("properties", () -> {
		test("tokens printed tokenize the same (whitespace runs one)", () -> property(CSS, text -> {
			var ts = Css.tokens(text);
			equals(collapse(kinds(Css.serializeTokens(ts))), collapse([for (t in ts) t.kind]));
		}, {cases: 500}));
		test("tokens' offsets: in order, only comments between them", () -> property(CSS, text -> {
			var at = 0;
			for (t in Css.tokens(text)) {
				var gap = text.substring(at, t.start);
				assert(at <= t.start && t.start < t.end, 'token at $at: ${t.start}...${t.end}');
				assert(gap == "" || ~/^(\/\*([^*]|\*+[^*\/])*\*+\/)+$/.match(gap), 'between tokens: ${gap}');
				at = t.end;
			}
			var rest = text.substring(at);
			assert(rest == "" || rest.startsWith("/*"), 'after the last token: $rest');
		}, {cases: 300}));
		test("any text parses as a stylesheet, its values print and read back", () -> property(CSS, text -> {
			Css.sheet(text);
			Css.block(text);
			Css.declarations(text);
			var vs = Css.values(text);
			equals(collapse(kinds(Css.serialize(vs))), collapse([for (t in Css.tokens(text)) t.kind]));
		}, {cases: 300, limit: 10}));
		test("mutated stylesheets parse and print back", () -> property(mutated(sheets()), b -> {
			// (a byte a character: a mutated file is seldom UTF-8)
			var text = [for (i in 0...b.length) String.fromCharCode(b.get(i))].join("");
			Css.sheet(text);
			var ts = Css.tokens(text);
			equals(collapse(kinds(Css.serializeTokens(ts))), collapse([for (t in ts) t.kind]));
		}, {cases: 100, seconds: 3, limit: 10, memory: 256}));
	});
}

private function kinds(text:String):Array<CssTokenKind>
	return [for (t in Css.tokens(text)) t.kind];

private function collapse(ks:Array<CssTokenKind>):Array<CssTokenKind> {
	var out:Array<CssTokenKind> = [];
	for (k in ks)
		if (!(k.match(Whitespace) && out.length > 0 && out[out.length - 1].match(Whitespace))) out.push(k);
	return out;
}

// (the site's sheet and the conformance fixtures' inputs: the robustness property's seeds)
private function sheets():Map<String, Bytes> {
	var out = ["site/site.css" => sys.io.File.getBytes("site/site.css")];
	var dir = "tests/css/fixtures/css-parsing-tests";
	for (f in sys.FileSystem.readDirectory(dir))
		if (f.endsWith(".json")) out.set('$dir/$f', sys.io.File.getBytes('$dir/$f'));
	return out;
}

// (CSS's pieces, escapes and their edges, and any characters, NUL included)
private final PIECES = [
	"a", "-", "--", "_", "\\", "\\\n", "\\31 ", "\\e9", "\\\r\n", "\"", "'", "url(", "url( '", "URL(", "u+", "U+1?", "U+0-7F", "#", "#1", "@", "@media", ".",
	"+", "5", "1.5", "1e3", "e", "E-", "%", "px", "/*", "*/", "/", "*", "<!--", "-->", "<!", "<", ">", "{", "}", "(", ")", "[", "]", ";", ":", ",",
	"!", "important", "!important", "--x:", "&", " ", "\n", "\r\n", "\r", "\t", "\x0C", "\x00", "\u{E9}", "\u{1F600}", "\u{80}", "\u{130}", "n", "2n+1",
	"var(--x)", "@import 'a';", "a { b: c }", ""
];

private final CSS:Gen<String> = array(oneOf([pick(PIECES), char(true)]), 0, 60).map(a -> a.join(""));
