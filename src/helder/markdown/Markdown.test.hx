package helder.markdown;

import helder.markdown.Doc;
import helder.test.Gen;
import helder.test.Test;

using StringTools;

// helder.markdown against CommonMark's spec (0.31.2, spec.commonmark.org,
// CC BY-SA 4.0): SPEC is 215 of its 652 examples, about a third of each
// section's, and all pass; of the whole suite 646 do, the other six on
// purpose: a "---" first line is front matter (96, 98) and GFM's extended
// autolinks link a bare URL or address (606, 608, 611, 612). GFM holds
// cmark-gfm's examples of its extensions (tables, task lists,
// strikethrough, autolinks; its tag filter is moot, raw HTML being text).
// Each rendered to HTML as commonmark.js renders it (Html, below). Then
// the tree itself, and pathological inputs parsed in linear time; then
// properties: any text (Markdown's marks and runs of them, any characters)
// parses within a bound of steps a character, and plain text's paragraph
// is that text.
function tests() {
	describe("Markdown", () -> {
		test("CommonMark's examples", () -> equals([for (c in SPEC) if (Html.render(Markdown.parse(c[1])) != c[2]) c[0]], []));
		test("GFM's examples", () -> equals([for (c in GFM) if (Html.render(Markdown.parse(c[1])) != c[2]) c[0]], []));
		test("headings' ids", () -> {
			var doc = Markdown.parse("# Set up, again!\n\n## Set up, again\n\nSet *up*\n---\n");
			equals([for (b in doc.blocks) switch b {
				case Heading(_, id, _): id;
				case _: "";
			}], ["set-up-again", "set-up-again-1", "set-up"]);
		});
		test("front matter", () -> {
			var doc = Markdown.parse("---\ntitle: A\n---\n# A\n");
			equals(doc.frontMatter, "title: A\n");
			equals(doc.blocks.length, 1);
			equals(Markdown.parse("# A\n---\nb\n---\n").frontMatter, null);
		});
		test("tasks, tables, links", () -> {
			switch Markdown.parse("- [x] done\n- [ ] not\n- plain\n").blocks[0] {
				case List(false, _, true, items): equals([for (i in items) i.task], [true, false, null]);
				case b: fail('a list: $b');
			}
			switch Markdown.parse("| a | b |\n|:--|--:|\n| 1 |\n").blocks[0] {
				case Table(align, head, rows):
					equals(align, [Left, Right]);
					equals(head.length, 2);
					equals(rows[0][1].length, 0);
				case b: fail('a table: $b');
			}
			switch Markdown.parse("[a](my%20file.md \"t\") ![b *c*](x&amp;y.png)").blocks[0] {
				case Paragraph([Link(href, title, _), Text(" "), Image(src, alt, _)]):
					equals(href, "my%20file.md");
					equals(title, "t");
					equals(src, "x&y.png");
					equals(alt, "b c");
				case b: fail('links: $b');
			}
			equals(Markdown.plain(switch Markdown.parse("*a* `b` <i>c</i>").blocks[0] {
				case Paragraph(c): c;
				case _: [];
			}), "a b <i>c</i>");
		});
		test("pathological inputs stay linear", () -> {
			// (each at a quarter of its size and whole, n: the parsers' loop
			// turns, Scan.steps, a character's the same at both; quadratic
			// work in the input's length is 4 times as many)
			var inputs:Map<String, Int->String> = [
				"nested quotes" => n -> "".lpad(">", 250 * n) + " a\n",
				"nested lists" => n -> [for (k in 0...75 * n) "".lpad(" ", k * 2) + "- a"].join("\n"),
				"stars" => n -> "".lpad("*", 2500 * n),
				"star words" => n -> [for (_ in 0...2500 * n) "*a"].join(" "),
				"underscores" => n -> [for (_ in 0...2500 * n) "_a"].join(""),
				"strong openers" => n -> [for (_ in 0...1250 * n) "**a"].join(" ") + [for (_ in 0...1250 * n) "a**"].join(" "),
				"brackets" => n -> "".lpad("[", 2500 * n) + "".lpad("]", 2500 * n),
				"open links" => n -> [for (_ in 0...2500 * n) "[a]("].join(""),
				"images" => n -> [for (_ in 0...2500 * n) "![a"].join(""),
				"backticks" => n -> [for (k in 1...500 * n) "".lpad("`", k % 50 + 1) + "a"].join(""),
				"comments" => n -> [for (_ in 0...2500 * n) "<!--"].join(""),
				"tags" => n -> [for (_ in 0...2500 * n) "<a "].join(""),
				"references" => n -> [for (k in 0...1250 * n) '[$k]: /u$k'].join("\n") + "\n\n" + [for (k in 0...1250 * n) '[$k]'].join(" "),
				"table" => n -> "a|b\n-|-\n" + [for (_ in 0...2500 * n) "c|d"].join("\n"),
				"autolinks" => n -> [for (_ in 0...2500 * n) "www.a.b@"].join(" ")
			];
			function perChar(text:String) {
				var from = Scan.steps;
				Markdown.parse(text);
				return (Scan.steps - from) / text.length;
			}
			var superlinear = [];
			for (name => make in inputs) {
				var small = perChar(make(1)), whole = perChar(make(4));
				if (whole > small * 1.5) superlinear.push('$name: ${Math.round(small)} to ${Math.round(whole)} steps a character');
			}
			equals(superlinear, []);
		});
		// (the property's shrunk case: each ")" cut off counted the link's parentheses again)
		test("an autolink's run of closing parentheses: counted once", () -> {
			var text = "http://a.b/c" + "".lpad(")", 400), from = Scan.steps;
			Markdown.parse(text);
			assert(Scan.steps - from <= 40 * text.length + 400, '${Scan.steps - from} steps for ${text.length} characters');
		});
		// (the property's shrunk case: each item's marker scanned the line's rest for a rule again)
		test("nested items on one line: each marker's rule scan once", () -> {
			var text = [for (_ in 0...77) "- "].join("") + "*", from = Scan.steps;
			Markdown.parse(text);
			assert(Scan.steps - from <= 40 * text.length + 400, '${Scan.steps - from} steps for ${text.length} characters');
		});
	});
	describe("properties", () -> {
		test("any text parses, in steps bounded by its length", () -> property(MARKDOWN, text -> {
			var from = Scan.steps;
			var doc = Markdown.parse(text);
			var steps = Scan.steps - from;
			// (a bound of steps, the same anywhere: a character's, and each
			// line's walk of the containers open, as CommonMark's algorithm
			// does: blank or lazy lines in nested lists)
			assert(steps <= 40 * text.length + 5 * lines(text) * depth(doc.blocks) + 400, '$steps steps for ${text.length} characters');
		}, {cases: 300, limit: 10}));
		test("the repository's documents mutated parse, in steps bounded by their length", () -> property(mutated(documents()), b -> {
			// (a byte a character: a mutated file is seldom UTF-8, and Eval refuses a string that is not)
			var text = [for (i in 0...b.length) String.fromCharCode(b.get(i))].join(""), from = Scan.steps;
			var doc = Markdown.parse(text);
			var steps = Scan.steps - from;
			assert(steps <= 40 * text.length + 5 * lines(text) * depth(doc.blocks) + 400, '$steps steps for ${text.length} characters');
		}, {cases: 100, seconds: 3, limit: 10, memory: 256}));
		test("plain text's paragraph: that text", () -> property(PLAIN, text -> switch Markdown.parse(text).blocks {
			case [Paragraph(content)]: equals(Markdown.plain(content), text);
			case b: fail('not a paragraph: $b');
		}));
	});
}

// (Markdown's marks, a mark's runs (nesting, openers left open), words and any characters, NUL included)
private final MARKS = [
	"*", "_", "**", "__", "~~", "`", "```", "~~~", "[", "]", "(", ")", "![", "](", "]: ", "<", ">", "<!--", "-->", "<a ", "</a>", "<?", "<![CDATA[",
	"#", "# ", "###### ", "- ", "* ", "+ ", "1. ", "9) ", "> ", "\n", "\n\n", "    ", "\t", "  \n", "|", "| - |", "|:-:|", "---", "===", "\\",
	"&amp;", "&#", "&#x", ";", "http://a.b/c", "www.a.b", "a@b.c", "[x]: /u", "[x]", "- [ ] ", "- [x] ", "\r\n", "\r", "a", " ", "foo", "\"", "'"
];

private final MARKDOWN:Gen<String> = array(oneOf([
	pick(MARKS),
	string(char(true), 1, 6),
	c -> StringTools.lpad("", c.draw(pick(MARKS)), c.draw(int(1, 400))),
	c -> [for (k in 0...c.draw(int(1, 60))) StringTools.lpad("", " ", k * c.draw(int(0, 4))) + c.draw(pick(["- a", "> a", "1. a", "* a"]))].join("\n")
]), 0, 200).map(p -> p.join(""));

// (words of letters and digits, other scripts' and emoji's, a space apart: no markup)
private final PLAIN:Gen<String> = array(string(oneOf([
	pick("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".split("")),
	pick(["é", "ß", "中", "א", "ا", "ж", "😀", "👍🏽", "e\u0301"])
]), 1, 12), 1, 30).map(w -> w.join(" "));

// CommonMark's examples: name, Markdown, HTML
final SPEC:Array<Array<String>> = [
	["Tabs 1", "\tfoo\tbaz\t\tbim\n", "<pre><code>foo\tbaz\t\tbim\n</code></pre>\n"],
	["Tabs 4", "  - foo\n\n\tbar\n", "<ul>\n<li>\n<p>foo</p>\n<p>bar</p>\n</li>\n</ul>\n"],
	["Tabs 8", "    foo\n\tbar\n", "<pre><code>foo\nbar\n</code></pre>\n"],
	["Backslash escapes 12", "\\!\\\"\\#\\$\\%\\&\\'\\(\\)\\*\\+\\,\\-\\.\\/\\:\\;\\<\\=\\>\\?\\@\\[\\\\\\]\\^\\_\\`\\{\\|\\}\\~\n", "<p>!&quot;#$%&amp;'()*+,-./:;&lt;=&gt;?@[\\]^_`{|}~</p>\n"],
	["Backslash escapes 15", "\\\\*emphasis*\n", "<p>\\<em>emphasis</em></p>\n"],
	["Backslash escapes 18", "    \\[\\]\n", "<pre><code>\\[\\]\n</code></pre>\n"],
	["Backslash escapes 21", "<a href=\"/bar\\/)\">\n", "<a href=\"/bar\\/)\">\n"],
	["Entity and numeric character references 25", "&nbsp; &amp; &copy; &AElig; &Dcaron;\n&frac34; &HilbertSpace; &DifferentialD;\n&ClockwiseContourIntegral; &ngE;\n", "<p>  &amp; © Æ Ď\n¾ ℋ ⅆ\n∲ ≧̸</p>\n"],
	["Entity and numeric character references 28", "&nbsp &x; &#; &#x;\n&#87654321;\n&#abcdef0;\n&ThisIsNotDefined; &hi?;\n", "<p>&amp;nbsp &amp;x; &amp;#; &amp;#x;\n&amp;#87654321;\n&amp;#abcdef0;\n&amp;ThisIsNotDefined; &amp;hi?;</p>\n"],
	["Entity and numeric character references 31", "<a href=\"&ouml;&ouml;.html\">\n", "<a href=\"&ouml;&ouml;.html\">\n"],
	["Entity and numeric character references 35", "`f&ouml;&ouml;`\n", "<p><code>f&amp;ouml;&amp;ouml;</code></p>\n"],
	["Entity and numeric character references 38", "&#42; foo\n\n* foo\n", "<p>* foo</p>\n<ul>\n<li>foo</li>\n</ul>\n"],
	["Precedence 42", "- `one\n- two`\n", "<ul>\n<li>`one</li>\n<li>two`</li>\n</ul>\n"],
	["Thematic breaks 43", "***\n---\n___\n", "<hr />\n<hr />\n<hr />\n"],
	["Thematic breaks 46", "--\n**\n__\n", "<p>--\n**\n__</p>\n"],
	["Thematic breaks 49", "Foo\n    ***\n", "<p>Foo\n***</p>\n"],
	["Thematic breaks 52", " **  * ** * ** * **\n", "<hr />\n"],
	["Thematic breaks 55", "_ _ _ _ a\n\na------\n\n---a---\n", "<p>_ _ _ _ a</p>\n<p>a------</p>\n<p>---a---</p>\n"],
	["Thematic breaks 58", "Foo\n***\nbar\n", "<p>Foo</p>\n<hr />\n<p>bar</p>\n"],
	["ATX headings 62", "# foo\n## foo\n### foo\n#### foo\n##### foo\n###### foo\n", "<h1>foo</h1>\n<h2>foo</h2>\n<h3>foo</h3>\n<h4>foo</h4>\n<h5>foo</h5>\n<h6>foo</h6>\n"],
	["ATX headings 65", "\\## foo\n", "<p>## foo</p>\n"],
	["ATX headings 68", " ### foo\n  ## foo\n   # foo\n", "<h3>foo</h3>\n<h2>foo</h2>\n<h1>foo</h1>\n"],
	["ATX headings 71", "## foo ##\n  ###   bar    ###\n", "<h2>foo</h2>\n<h3>bar</h3>\n"],
	["ATX headings 74", "### foo ### b\n", "<h3>foo ### b</h3>\n"],
	["ATX headings 77", "****\n## foo\n****\n", "<hr />\n<h2>foo</h2>\n<hr />\n"],
	["Setext headings 80", "Foo *bar*\n=========\n\nFoo *bar*\n---------\n", "<h1>Foo <em>bar</em></h1>\n<h2>Foo <em>bar</em></h2>\n"],
	["Setext headings 83", "Foo\n-------------------------\n\nFoo\n=\n", "<h2>Foo</h2>\n<h1>Foo</h1>\n"],
	["Setext headings 86", "Foo\n   ----      \n", "<h2>Foo</h2>\n"],
	["Setext headings 89", "Foo  \n-----\n", "<h2>Foo</h2>\n"],
	["Setext headings 92", "> Foo\n---\n", "<blockquote>\n<p>Foo</p>\n</blockquote>\n<hr />\n"],
	["Setext headings 95", "Foo\nBar\n---\n", "<h2>Foo\nBar</h2>\n"],
	["Setext headings 100", "    foo\n---\n", "<pre><code>foo\n</code></pre>\n<hr />\n"],
	["Setext headings 103", "Foo\n\nbar\n---\nbaz\n", "<p>Foo</p>\n<h2>bar</h2>\n<p>baz</p>\n"],
	["Indented code blocks 107", "    a simple\n      indented code block\n", "<pre><code>a simple\n  indented code block\n</code></pre>\n"],
	["Indented code blocks 110", "    <a/>\n    *hi*\n\n    - one\n", "<pre><code>&lt;a/&gt;\n*hi*\n\n- one\n</code></pre>\n"],
	["Indented code blocks 113", "Foo\n    bar\n\n", "<p>Foo\nbar</p>\n"],
	["Indented code blocks 116", "        foo\n    bar\n", "<pre><code>    foo\nbar\n</code></pre>\n"],
	["Fenced code blocks 119", "```\n<\n >\n```\n", "<pre><code>&lt;\n &gt;\n</code></pre>\n"],
	["Fenced code blocks 122", "```\naaa\n~~~\n```\n", "<pre><code>aaa\n~~~\n</code></pre>\n"],
	["Fenced code blocks 125", "~~~~\naaa\n~~~\n~~~~\n", "<pre><code>aaa\n~~~\n</code></pre>\n"],
	["Fenced code blocks 128", "> ```\n> aaa\n\nbbb\n", "<blockquote>\n<pre><code>aaa\n</code></pre>\n</blockquote>\n<p>bbb</p>\n"],
	["Fenced code blocks 131", " ```\n aaa\naaa\n```\n", "<pre><code>aaa\naaa\n</code></pre>\n"],
	["Fenced code blocks 135", "```\naaa\n  ```\n", "<pre><code>aaa\n</code></pre>\n"],
	["Fenced code blocks 138", "``` ```\naaa\n", "<p><code> </code>\naaa</p>\n"],
	["Fenced code blocks 141", "foo\n---\n~~~\nbar\n~~~\n# baz\n", "<h2>foo</h2>\n<pre><code>bar\n</code></pre>\n<h1>baz</h1>\n"],
	["Fenced code blocks 144", "````;\n````\n", "<pre><code class=\"language-;\"></code></pre>\n"],
	["HTML blocks 148", "<table><tr><td>\n<pre>\n**Hello**,\n\n_world_.\n</pre>\n</td></tr></table>\n", "<table><tr><td>\n<pre>\n**Hello**,\n<p><em>world</em>.\n</pre></p>\n</td></tr></table>\n"],
	["HTML blocks 151", "</div>\n*foo*\n", "</div>\n*foo*\n"],
	["HTML blocks 154", "<div id=\"foo\" class=\"bar\n  baz\">\n</div>\n", "<div id=\"foo\" class=\"bar\n  baz\">\n</div>\n"],
	["HTML blocks 157", "<div class\nfoo\n", "<div class\nfoo\n"],
	["HTML blocks 160", "<table><tr><td>\nfoo\n</td></tr></table>\n", "<table><tr><td>\nfoo\n</td></tr></table>\n"],
	["HTML blocks 163", "<Warning>\n*bar*\n</Warning>\n", "<Warning>\n*bar*\n</Warning>\n"],
	["HTML blocks 166", "<del>\n*foo*\n</del>\n", "<del>\n*foo*\n</del>\n"],
	["HTML blocks 170", "<script type=\"text/javascript\">\n// JavaScript example\n\ndocument.getElementById(\"demo\").innerHTML = \"Hello JavaScript!\";\n</script>\nokay\n", "<script type=\"text/javascript\">\n// JavaScript example\n\ndocument.getElementById(\"demo\").innerHTML = \"Hello JavaScript!\";\n</script>\n<p>okay</p>\n"],
	["HTML blocks 173", "<style\n  type=\"text/css\">\n\nfoo\n", "<style\n  type=\"text/css\">\n\nfoo\n"],
	["HTML blocks 176", "<style>p{color:red;}</style>\n*foo*\n", "<style>p{color:red;}</style>\n<p><em>foo</em></p>\n"],
	["HTML blocks 179", "<!-- Foo\n\nbar\n   baz -->\nokay\n", "<!-- Foo\n\nbar\n   baz -->\n<p>okay</p>\n"],
	["HTML blocks 182", "<![CDATA[\nfunction matchwo(a,b)\n{\n  if (a < b && a < 0) then {\n    return 1;\n\n  } else {\n\n    return 0;\n  }\n}\n]]>\nokay\n", "<![CDATA[\nfunction matchwo(a,b)\n{\n  if (a < b && a < 0) then {\n    return 1;\n\n  } else {\n\n    return 0;\n  }\n}\n]]>\n<p>okay</p>\n"],
	["HTML blocks 185", "Foo\n<div>\nbar\n</div>\n", "<p>Foo</p>\n<div>\nbar\n</div>\n"],
	["HTML blocks 188", "<div>\n\n*Emphasized* text.\n\n</div>\n", "<div>\n<p><em>Emphasized</em> text.</p>\n</div>\n"],
	["Link reference definitions 192", "[foo]: /url \"title\"\n\n[foo]\n", "<p><a href=\"/url\" title=\"title\">foo</a></p>\n"],
	["Link reference definitions 195", "[Foo bar]:\n<my url>\n'title'\n\n[Foo bar]\n", "<p><a href=\"my%20url\" title=\"title\">Foo bar</a></p>\n"],
	["Link reference definitions 198", "[foo]:\n/url\n\n[foo]\n", "<p><a href=\"/url\">foo</a></p>\n"],
	["Link reference definitions 201", "[foo]: <bar>(baz)\n\n[foo]\n", "<p>[foo]: <bar>(baz)</p>\n<p>[foo]</p>\n"],
	["Link reference definitions 204", "[foo]\n\n[foo]: first\n[foo]: second\n", "<p><a href=\"first\">foo</a></p>\n"],
	["Link reference definitions 207", "[foo]: /url\n", ""],
	["Link reference definitions 210", "[foo]: /url\n\"title\" ok\n", "<p>&quot;title&quot; ok</p>\n"],
	["Link reference definitions 213", "Foo\n[bar]: /baz\n\n[bar]\n", "<p>Foo\n[bar]: /baz</p>\n<p>[bar]</p>\n"],
	["Link reference definitions 216", "[foo]: /url\n===\n[foo]\n", "<p>===\n<a href=\"/url\">foo</a></p>\n"],
	["Paragraphs 219", "aaa\n\nbbb\n", "<p>aaa</p>\n<p>bbb</p>\n"],
	["Paragraphs 221", "aaa\n\n\nbbb\n", "<p>aaa</p>\n<p>bbb</p>\n"],
	["Paragraphs 224", "   aaa\nbbb\n", "<p>aaa\nbbb</p>\n"],
	["Blank lines 227", "  \n\naaa\n  \n\n# aaa\n\n  \n", "<p>aaa</p>\n<h1>aaa</h1>\n"],
	["Block quotes 228", "> # Foo\n> bar\n> baz\n", "<blockquote>\n<h1>Foo</h1>\n<p>bar\nbaz</p>\n</blockquote>\n"],
	["Block quotes 231", "    > # Foo\n    > bar\n    > baz\n", "<pre><code>&gt; # Foo\n&gt; bar\n&gt; baz\n</code></pre>\n"],
	["Block quotes 234", "> foo\n---\n", "<blockquote>\n<p>foo</p>\n</blockquote>\n<hr />\n"],
	["Block quotes 237", "> ```\nfoo\n```\n", "<blockquote>\n<pre><code></code></pre>\n</blockquote>\n<p>foo</p>\n<pre><code></code></pre>\n"],
	["Block quotes 240", ">\n>  \n> \n", "<blockquote>\n</blockquote>\n"],
	["Block quotes 243", "> foo\n> bar\n", "<blockquote>\n<p>foo\nbar</p>\n</blockquote>\n"],
	["Block quotes 246", "> aaa\n***\n> bbb\n", "<blockquote>\n<p>aaa</p>\n</blockquote>\n<hr />\n<blockquote>\n<p>bbb</p>\n</blockquote>\n"],
	["Block quotes 249", "> bar\n>\nbaz\n", "<blockquote>\n<p>bar</p>\n</blockquote>\n<p>baz</p>\n"],
	["List items 253", "A paragraph\nwith two lines.\n\n    indented code\n\n> A block quote.\n", "<p>A paragraph\nwith two lines.</p>\n<pre><code>indented code\n</code></pre>\n<blockquote>\n<p>A block quote.</p>\n</blockquote>\n"],
	["List items 256", "- one\n\n  two\n", "<ul>\n<li>\n<p>one</p>\n<p>two</p>\n</li>\n</ul>\n"],
	["List items 259", "   > > 1.  one\n>>\n>>     two\n", "<blockquote>\n<blockquote>\n<ol>\n<li>\n<p>one</p>\n<p>two</p>\n</li>\n</ol>\n</blockquote>\n</blockquote>\n"],
	["List items 262", "- foo\n\n\n  bar\n", "<ul>\n<li>\n<p>foo</p>\n<p>bar</p>\n</li>\n</ul>\n"],
	["List items 265", "123456789. ok\n", "<ol start=\"123456789\">\n<li>ok</li>\n</ol>\n"],
	["List items 268", "003. ok\n", "<ol start=\"3\">\n<li>ok</li>\n</ol>\n"],
	["List items 271", "  10.  foo\n\n           bar\n", "<ol start=\"10\">\n<li>\n<p>foo</p>\n<pre><code>bar\n</code></pre>\n</li>\n</ol>\n"],
	["List items 274", "1.      indented code\n\n   paragraph\n\n       more code\n", "<ol>\n<li>\n<pre><code> indented code\n</code></pre>\n<p>paragraph</p>\n<pre><code>more code\n</code></pre>\n</li>\n</ol>\n"],
	["List items 277", "-  foo\n\n   bar\n", "<ul>\n<li>\n<p>foo</p>\n<p>bar</p>\n</li>\n</ul>\n"],
	["List items 280", "-\n\n  foo\n", "<ul>\n<li></li>\n</ul>\n<p>foo</p>\n"],
	["List items 283", "1. foo\n2.\n3. bar\n", "<ol>\n<li>foo</li>\n<li></li>\n<li>bar</li>\n</ol>\n"],
	["List items 286", " 1.  A paragraph\n     with two lines.\n\n         indented code\n\n     > A block quote.\n", "<ol>\n<li>\n<p>A paragraph\nwith two lines.</p>\n<pre><code>indented code\n</code></pre>\n<blockquote>\n<p>A block quote.</p>\n</blockquote>\n</li>\n</ol>\n"],
	["List items 289", "    1.  A paragraph\n        with two lines.\n\n            indented code\n\n        > A block quote.\n", "<pre><code>1.  A paragraph\n    with two lines.\n\n        indented code\n\n    &gt; A block quote.\n</code></pre>\n"],
	["List items 292", "> 1. > Blockquote\ncontinued here.\n", "<blockquote>\n<ol>\n<li>\n<blockquote>\n<p>Blockquote\ncontinued here.</p>\n</blockquote>\n</li>\n</ol>\n</blockquote>\n"],
	["List items 295", "- foo\n - bar\n  - baz\n   - boo\n", "<ul>\n<li>foo</li>\n<li>bar</li>\n<li>baz</li>\n<li>boo</li>\n</ul>\n"],
	["List items 298", "- - foo\n", "<ul>\n<li>\n<ul>\n<li>foo</li>\n</ul>\n</li>\n</ul>\n"],
	["Lists 301", "- foo\n- bar\n+ baz\n", "<ul>\n<li>foo</li>\n<li>bar</li>\n</ul>\n<ul>\n<li>baz</li>\n</ul>\n"],
	["Lists 304", "The number of windows in my house is\n14.  The number of doors is 6.\n", "<p>The number of windows in my house is\n14.  The number of doors is 6.</p>\n"],
	["Lists 307", "- foo\n  - bar\n    - baz\n\n\n      bim\n", "<ul>\n<li>foo\n<ul>\n<li>bar\n<ul>\n<li>\n<p>baz</p>\n<p>bim</p>\n</li>\n</ul>\n</li>\n</ul>\n</li>\n</ul>\n"],
	["Lists 310", "- a\n - b\n  - c\n   - d\n  - e\n - f\n- g\n", "<ul>\n<li>a</li>\n<li>b</li>\n<li>c</li>\n<li>d</li>\n<li>e</li>\n<li>f</li>\n<li>g</li>\n</ul>\n"],
	["Lists 314", "- a\n- b\n\n- c\n", "<ul>\n<li>\n<p>a</p>\n</li>\n<li>\n<p>b</p>\n</li>\n<li>\n<p>c</p>\n</li>\n</ul>\n"],
	["Lists 317", "- a\n- b\n\n  [ref]: /url\n- d\n", "<ul>\n<li>\n<p>a</p>\n</li>\n<li>\n<p>b</p>\n</li>\n<li>\n<p>d</p>\n</li>\n</ul>\n"],
	["Lists 320", "* a\n  > b\n  >\n* c\n", "<ul>\n<li>a\n<blockquote>\n<p>b</p>\n</blockquote>\n</li>\n<li>c</li>\n</ul>\n"],
	["Lists 323", "- a\n  - b\n", "<ul>\n<li>a\n<ul>\n<li>b</li>\n</ul>\n</li>\n</ul>\n"],
	["Inlines 327", "`hi`lo`\n", "<p><code>hi</code>lo`</p>\n"],
	["Code spans 328", "`foo`\n", "<p><code>foo</code></p>\n"],
	["Code spans 331", "`  ``  `\n", "<p><code> `` </code></p>\n"],
	["Code spans 334", "` `\n`  `\n", "<p><code> </code>\n<code>  </code></p>\n"],
	["Code spans 337", "`foo   bar \nbaz`\n", "<p><code>foo   bar  baz</code></p>\n"],
	["Code spans 340", "` foo `` bar `\n", "<p><code>foo `` bar</code></p>\n"],
	["Code spans 343", "`<a href=\"`\">`\n", "<p><code>&lt;a href=&quot;</code>&quot;&gt;`</p>\n"],
	["Code spans 346", "<https://foo.bar.`baz>`\n", "<p><a href=\"https://foo.bar.%60baz\">https://foo.bar.`baz</a>`</p>\n"],
	["Emphasis and strong emphasis 350", "*foo bar*\n", "<p><em>foo bar</em></p>\n"],
	["Emphasis and strong emphasis 353", "* a *\n", "<p>* a *</p>\n"],
	["Emphasis and strong emphasis 356", "5*6*78\n", "<p>5<em>6</em>78</p>\n"],
	["Emphasis and strong emphasis 359", "a_\"foo\"_\n", "<p>a_&quot;foo&quot;_</p>\n"],
	["Emphasis and strong emphasis 362", "пристаням_стремятся_\n", "<p>пристаням_стремятся_</p>\n"],
	["Emphasis and strong emphasis 365", "_foo*\n", "<p>_foo*</p>\n"],
	["Emphasis and strong emphasis 368", "*(*foo)\n", "<p>*(*foo)</p>\n"],
	["Emphasis and strong emphasis 371", "_foo bar _\n", "<p>_foo bar _</p>\n"],
	["Emphasis and strong emphasis 374", "_foo_bar\n", "<p>_foo_bar</p>\n"],
	["Emphasis and strong emphasis 377", "_(bar)_.\n", "<p><em>(bar)</em>.</p>\n"],
	["Emphasis and strong emphasis 380", "a**\"foo\"**\n", "<p>a**&quot;foo&quot;**</p>\n"],
	["Emphasis and strong emphasis 383", "__ foo bar__\n", "<p>__ foo bar__</p>\n"],
	["Emphasis and strong emphasis 386", "foo__bar__\n", "<p>foo__bar__</p>\n"],
	["Emphasis and strong emphasis 389", "__foo, __bar__, baz__\n", "<p><strong>foo, <strong>bar</strong>, baz</strong></p>\n"],
	["Emphasis and strong emphasis 392", "**(**foo)\n", "<p>**(**foo)</p>\n"],
	["Emphasis and strong emphasis 395", "**foo \"*bar*\" foo**\n", "<p><strong>foo &quot;<em>bar</em>&quot; foo</strong></p>\n"],
	["Emphasis and strong emphasis 398", "__(__foo)\n", "<p>__(__foo)</p>\n"],
	["Emphasis and strong emphasis 401", "__пристаням__стремятся\n", "<p>__пристаням__стремятся</p>\n"],
	["Emphasis and strong emphasis 404", "*foo [bar](/url)*\n", "<p><em>foo <a href=\"/url\">bar</a></em></p>\n"],
	["Emphasis and strong emphasis 407", "_foo _bar_ baz_\n", "<p><em>foo <em>bar</em> baz</em></p>\n"],
	["Emphasis and strong emphasis 410", "*foo **bar** baz*\n", "<p><em>foo <strong>bar</strong> baz</em></p>\n"],
	["Emphasis and strong emphasis 413", "***foo** bar*\n", "<p><em><strong>foo</strong> bar</em></p>\n"],
	["Emphasis and strong emphasis 416", "foo***bar***baz\n", "<p>foo<em><strong>bar</strong></em>baz</p>\n"],
	["Emphasis and strong emphasis 419", "*foo [*bar*](/url)*\n", "<p><em>foo <a href=\"/url\"><em>bar</em></a></em></p>\n"],
	["Emphasis and strong emphasis 422", "**foo [bar](/url)**\n", "<p><strong>foo <a href=\"/url\">bar</a></strong></p>\n"],
	["Emphasis and strong emphasis 425", "__foo __bar__ baz__\n", "<p><strong>foo <strong>bar</strong> baz</strong></p>\n"],
	["Emphasis and strong emphasis 428", "**foo *bar* baz**\n", "<p><strong>foo <em>bar</em> baz</strong></p>\n"],
	["Emphasis and strong emphasis 431", "**foo *bar***\n", "<p><strong>foo <em>bar</em></strong></p>\n"],
	["Emphasis and strong emphasis 434", "__ is not an empty emphasis\n", "<p>__ is not an empty emphasis</p>\n"],
	["Emphasis and strong emphasis 437", "foo *\\**\n", "<p>foo <em>*</em></p>\n"],
	["Emphasis and strong emphasis 440", "foo **\\***\n", "<p>foo <strong>*</strong></p>\n"],
	["Emphasis and strong emphasis 443", "*foo**\n", "<p><em>foo</em>*</p>\n"],
	["Emphasis and strong emphasis 446", "**foo***\n", "<p><strong>foo</strong>*</p>\n"],
	["Emphasis and strong emphasis 449", "foo _\\__\n", "<p>foo <em>_</em></p>\n"],
	["Emphasis and strong emphasis 452", "foo __\\___\n", "<p>foo <strong>_</strong></p>\n"],
	["Emphasis and strong emphasis 455", "_foo__\n", "<p><em>foo</em>_</p>\n"],
	["Emphasis and strong emphasis 458", "__foo___\n", "<p><strong>foo</strong>_</p>\n"],
	["Emphasis and strong emphasis 461", "*_foo_*\n", "<p><em><em>foo</em></em></p>\n"],
	["Emphasis and strong emphasis 464", "****foo****\n", "<p><strong><strong>foo</strong></strong></p>\n"],
	["Emphasis and strong emphasis 467", "***foo***\n", "<p><em><strong>foo</strong></em></p>\n"],
	["Emphasis and strong emphasis 470", "*foo __bar *baz bim__ bam*\n", "<p><em>foo <strong>bar *baz bim</strong> bam</em></p>\n"],
	["Emphasis and strong emphasis 473", "*[bar*](/url)\n", "<p>*<a href=\"/url\">bar*</a></p>\n"],
	["Emphasis and strong emphasis 476", "**<a href=\"**\">\n", "<p>**<a href=\"**\"></p>\n"],
	["Emphasis and strong emphasis 479", "_a `_`_\n", "<p><em>a <code>_</code></em></p>\n"],
	["Links 482", "[link](/uri \"title\")\n", "<p><a href=\"/uri\" title=\"title\">link</a></p>\n"],
	["Links 485", "[link]()\n", "<p><a href=\"\">link</a></p>\n"],
	["Links 488", "[link](/my uri)\n", "<p>[link](/my uri)</p>\n"],
	["Links 491", "[link](<foo\nbar>)\n", "<p>[link](<foo\nbar>)</p>\n"],
	["Links 494", "[a](<b)c\n[a](<b)c>\n[a](<b>c)\n", "<p>[a](&lt;b)c\n[a](&lt;b)c&gt;\n[a](<b>c)</p>\n"],
	["Links 497", "[link](foo(and(bar))\n", "<p>[link](foo(and(bar))</p>\n"],
	["Links 500", "[link](foo\\)\\:)\n", "<p><a href=\"foo):\">link</a></p>\n"],
	["Links 503", "[link](foo%20b&auml;)\n", "<p><a href=\"foo%20b%C3%A4\">link</a></p>\n"],
	["Links 506", "[link](/url \"title \\\"&quot;\")\n", "<p><a href=\"/url\" title=\"title &quot;&quot;\">link</a></p>\n"],
	["Links 509", "[link](/url 'title \"and\" title')\n", "<p><a href=\"/url\" title=\"title &quot;and&quot; title\">link</a></p>\n"],
	["Links 512", "[link [foo [bar]]](/uri)\n", "<p><a href=\"/uri\">link [foo [bar]]</a></p>\n"],
	["Links 515", "[link \\[bar](/uri)\n", "<p><a href=\"/uri\">link [bar</a></p>\n"],
	["Links 518", "[foo [bar](/uri)](/uri)\n", "<p>[foo <a href=\"/uri\">bar</a>](/uri)</p>\n"],
	["Links 521", "*[foo*](/uri)\n", "<p>*<a href=\"/uri\">foo*</a></p>\n"],
	["Links 524", "[foo <bar attr=\"](baz)\">\n", "<p>[foo <bar attr=\"](baz)\"></p>\n"],
	["Links 527", "[foo][bar]\n\n[bar]: /url \"title\"\n", "<p><a href=\"/url\" title=\"title\">foo</a></p>\n"],
	["Links 530", "[link *foo **bar** `#`*][ref]\n\n[ref]: /uri\n", "<p><a href=\"/uri\">link <em>foo <strong>bar</strong> <code>#</code></em></a></p>\n"],
	["Links 533", "[foo *bar [baz][ref]*][ref]\n\n[ref]: /uri\n", "<p>[foo <em>bar <a href=\"/uri\">baz</a></em>]<a href=\"/uri\">ref</a></p>\n"],
	["Links 536", "[foo <bar attr=\"][ref]\">\n\n[ref]: /uri\n", "<p>[foo <bar attr=\"][ref]\"></p>\n"],
	["Links 539", "[foo][BaR]\n\n[bar]: /url \"title\"\n", "<p><a href=\"/url\" title=\"title\">foo</a></p>\n"],
	["Links 542", "[foo] [bar]\n\n[bar]: /url \"title\"\n", "<p>[foo] <a href=\"/url\" title=\"title\">bar</a></p>\n"],
	["Links 545", "[bar][foo\\!]\n\n[foo!]: /url\n", "<p>[bar][foo!]</p>\n"],
	["Links 548", "[[[foo]]]\n\n[[[foo]]]: /url\n", "<p>[[[foo]]]</p>\n<p>[[[foo]]]: /url</p>\n"],
	["Links 551", "[]\n\n[]: /uri\n", "<p>[]</p>\n<p>[]: /uri</p>\n"],
	["Links 554", "[*foo* bar][]\n\n[*foo* bar]: /url \"title\"\n", "<p><a href=\"/url\" title=\"title\"><em>foo</em> bar</a></p>\n"],
	["Links 557", "[foo]\n\n[foo]: /url \"title\"\n", "<p><a href=\"/url\" title=\"title\">foo</a></p>\n"],
	["Links 560", "[[bar [foo]\n\n[foo]: /url\n", "<p>[[bar <a href=\"/url\">foo</a></p>\n"],
	["Links 563", "\\[foo]\n\n[foo]: /url \"title\"\n", "<p>[foo]</p>\n"],
	["Links 566", "[foo][]\n\n[foo]: /url1\n", "<p><a href=\"/url1\">foo</a></p>\n"],
	["Links 569", "[foo][bar][baz]\n\n[baz]: /url\n", "<p>[foo]<a href=\"/url\">bar</a></p>\n"],
	["Images 572", "![foo](/url \"title\")\n", "<p><img src=\"/url\" alt=\"foo\" title=\"title\" /></p>\n"],
	["Images 575", "![foo [bar](/url)](/url2)\n", "<p><img src=\"/url2\" alt=\"foo bar\" /></p>\n"],
	["Images 578", "![foo](train.jpg)\n", "<p><img src=\"train.jpg\" alt=\"foo\" /></p>\n"],
	["Images 581", "![](/url)\n", "<p><img src=\"/url\" alt=\"\" /></p>\n"],
	["Images 584", "![foo][]\n\n[foo]: /url \"title\"\n", "<p><img src=\"/url\" alt=\"foo\" title=\"title\" /></p>\n"],
	["Images 587", "![foo] \n[]\n\n[foo]: /url \"title\"\n", "<p><img src=\"/url\" alt=\"foo\" title=\"title\" />\n[]</p>\n"],
	["Images 590", "![[foo]]\n\n[[foo]]: /url \"title\"\n", "<p>![[foo]]</p>\n<p>[[foo]]: /url &quot;title&quot;</p>\n"],
	["Autolinks 594", "<http://foo.bar.baz>\n", "<p><a href=\"http://foo.bar.baz\">http://foo.bar.baz</a></p>\n"],
	["Autolinks 597", "<MAILTO:FOO@BAR.BAZ>\n", "<p><a href=\"MAILTO:FOO@BAR.BAZ\">MAILTO:FOO@BAR.BAZ</a></p>\n"],
	["Autolinks 600", "<https://../>\n", "<p><a href=\"https://../\">https://../</a></p>\n"],
	["Autolinks 603", "<https://example.com/\\[\\>\n", "<p><a href=\"https://example.com/%5C%5B%5C\">https://example.com/\\[\\</a></p>\n"],
	["Autolinks 607", "<>\n", "<p>&lt;&gt;</p>\n"],
	["Raw HTML 613", "<a><bab><c2c>\n", "<p><a><bab><c2c></p>\n"],
	["Raw HTML 616", "<a foo=\"bar\" bam = 'baz <em>\"</em>'\n_boolean zoop:33=zoop:33 />\n", "<p><a foo=\"bar\" bam = 'baz <em>\"</em>'\n_boolean zoop:33=zoop:33 /></p>\n"],
	["Raw HTML 619", "<a h*#ref=\"hi\">\n", "<p>&lt;a h*#ref=&quot;hi&quot;&gt;</p>\n"],
	["Raw HTML 623", "</a></foo >\n", "<p></a></foo ></p>\n"],
	["Raw HTML 626", "foo <!--> foo -->\n\nfoo <!---> foo -->\n", "<p>foo <!--> foo --&gt;</p>\n<p>foo <!---> foo --&gt;</p>\n"],
	["Raw HTML 629", "foo <![CDATA[>&<]]>\n", "<p>foo <![CDATA[>&<]]></p>\n"],
	["Hard line breaks 633", "foo  \nbaz\n", "<p>foo<br />\nbaz</p>\n"],
	["Hard line breaks 636", "foo  \n     bar\n", "<p>foo<br />\nbar</p>\n"],
	["Hard line breaks 639", "*foo\\\nbar*\n", "<p><em>foo<br />\nbar</em></p>\n"],
	["Hard line breaks 642", "<a href=\"foo  \nbar\">\n", "<p><a href=\"foo  \nbar\"></p>\n"],
	["Hard line breaks 645", "foo  \n", "<p>foo</p>\n"],
	["Soft line breaks 648", "foo\nbaz\n", "<p>foo\nbaz</p>\n"],
	["Soft line breaks 649", "foo \n baz\n", "<p>foo\nbaz</p>\n"],
	["Textual content 650", "hello $.;'there\n", "<p>hello $.;'there</p>\n"],
	["Textual content 651", "Foo χρῆν\n", "<p>Foo χρῆν</p>\n"],
	["Textual content 652", "Multiple     spaces\n", "<p>Multiple     spaces</p>\n"]
];

// GFM's extensions' examples (cmark-gfm's test/spec.txt)
final GFM:Array<Array<String>> = [
	["Tables", "| foo | bar |\n| --- | --- |\n| baz | bim |\n", "<table>\n<thead>\n<tr>\n<th>foo</th>\n<th>bar</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>baz</td>\n<td>bim</td>\n</tr>\n</tbody>\n</table>\n"],
	["Tables", "| abc | defghi |\n:-: | -----------:\nbar | baz\n", "<table>\n<thead>\n<tr>\n<th align=\"center\">abc</th>\n<th align=\"right\">defghi</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td align=\"center\">bar</td>\n<td align=\"right\">baz</td>\n</tr>\n</tbody>\n</table>\n"],
	["Tables", "| f\\|oo  |\n| ------ |\n| b `\\|` az |\n| b **\\|** im |\n", "<table>\n<thead>\n<tr>\n<th>f|oo</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>b <code>|</code> az</td>\n</tr>\n<tr>\n<td>b <strong>|</strong> im</td>\n</tr>\n</tbody>\n</table>\n"],
	["Tables", "| abc | def |\n| --- | --- |\n| bar | baz |\n> bar\n", "<table>\n<thead>\n<tr>\n<th>abc</th>\n<th>def</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>bar</td>\n<td>baz</td>\n</tr>\n</tbody>\n</table>\n<blockquote>\n<p>bar</p>\n</blockquote>\n"],
	["Tables", "| abc | def |\n| --- | --- |\n| bar | baz |\nbar\n\nbar\n", "<table>\n<thead>\n<tr>\n<th>abc</th>\n<th>def</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>bar</td>\n<td>baz</td>\n</tr>\n<tr>\n<td>bar</td>\n<td></td>\n</tr>\n</tbody>\n</table>\n<p>bar</p>\n"],
	["Tables", "| abc | def |\n| --- |\n| bar |\n", "<p>| abc | def |\n| --- |\n| bar |</p>\n"],
	["Tables", "| abc | def |\n| --- | --- |\n| bar |\n| bar | baz | boo |\n", "<table>\n<thead>\n<tr>\n<th>abc</th>\n<th>def</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>bar</td>\n<td></td>\n</tr>\n<tr>\n<td>bar</td>\n<td>baz</td>\n</tr>\n</tbody>\n</table>\n"],
	["Tables", "| abc | def |\n| --- | --- |\n", "<table>\n<thead>\n<tr>\n<th>abc</th>\n<th>def</th>\n</tr>\n</thead>\n</table>\n"],
	["Task list items", "- [ ] foo\n- [x] bar\n", "<ul>\n<li><input disabled=\"\" type=\"checkbox\"> foo</li>\n<li><input checked=\"\" disabled=\"\" type=\"checkbox\"> bar</li>\n</ul>\n"],
	["Task list items", "- [x] foo\n  - [ ] bar\n  - [x] baz\n- [ ] bim\n", "<ul>\n<li><input checked=\"\" disabled=\"\" type=\"checkbox\"> foo\n<ul>\n<li><input disabled=\"\" type=\"checkbox\"> bar</li>\n<li><input checked=\"\" disabled=\"\" type=\"checkbox\"> baz</li>\n</ul>\n</li>\n<li><input disabled=\"\" type=\"checkbox\"> bim</li>\n</ul>\n"],
	["Strikethrough", "~~Hi~~ Hello, world!\n", "<p><del>Hi</del> Hello, world!</p>\n"],
	["Strikethrough", "This ~~has a\n\nnew paragraph~~.\n", "<p>This ~~has a</p>\n<p>new paragraph~~.</p>\n"],
	["Autolinks", "www.commonmark.org\n", "<p><a href=\"http://www.commonmark.org\">www.commonmark.org</a></p>\n"],
	["Autolinks", "Visit www.commonmark.org/help for more information.\n", "<p>Visit <a href=\"http://www.commonmark.org/help\">www.commonmark.org/help</a> for more information.</p>\n"],
	["Autolinks", "Visit www.commonmark.org.\n\nVisit www.commonmark.org/a.b.\n", "<p>Visit <a href=\"http://www.commonmark.org\">www.commonmark.org</a>.</p>\n<p>Visit <a href=\"http://www.commonmark.org/a.b\">www.commonmark.org/a.b</a>.</p>\n"],
	["Autolinks", "www.google.com/search?q=Markup+(business)\n\nwww.google.com/search?q=Markup+(business)))\n\n(www.google.com/search?q=Markup+(business))\n\n(www.google.com/search?q=Markup+(business)\n", "<p><a href=\"http://www.google.com/search?q=Markup+(business)\">www.google.com/search?q=Markup+(business)</a></p>\n<p><a href=\"http://www.google.com/search?q=Markup+(business)\">www.google.com/search?q=Markup+(business)</a>))</p>\n<p>(<a href=\"http://www.google.com/search?q=Markup+(business)\">www.google.com/search?q=Markup+(business)</a>)</p>\n<p>(<a href=\"http://www.google.com/search?q=Markup+(business)\">www.google.com/search?q=Markup+(business)</a></p>\n"],
	["Autolinks", "www.google.com/search?q=(business))+ok\n", "<p><a href=\"http://www.google.com/search?q=(business))+ok\">www.google.com/search?q=(business))+ok</a></p>\n"],
	["Autolinks", "www.google.com/search?q=commonmark&hl=en\n\nwww.google.com/search?q=commonmark&hl;\n", "<p><a href=\"http://www.google.com/search?q=commonmark&amp;hl=en\">www.google.com/search?q=commonmark&amp;hl=en</a></p>\n<p><a href=\"http://www.google.com/search?q=commonmark\">www.google.com/search?q=commonmark</a>&amp;hl;</p>\n"],
	["Autolinks", "www.commonmark.org/he<lp\n", "<p><a href=\"http://www.commonmark.org/he\">www.commonmark.org/he</a>&lt;lp</p>\n"],
	["Autolinks", "http://commonmark.org\n\n(Visit https://encrypted.google.com/search?q=Markup+(business))\n\nAnonymous FTP is available at ftp://foo.bar.baz.\n", "<p><a href=\"http://commonmark.org\">http://commonmark.org</a></p>\n<p>(Visit <a href=\"https://encrypted.google.com/search?q=Markup+(business)\">https://encrypted.google.com/search?q=Markup+(business)</a>)</p>\n<p>Anonymous FTP is available at <a href=\"ftp://foo.bar.baz\">ftp://foo.bar.baz</a>.</p>\n"],
	["Autolinks", "foo@bar.baz\n", "<p><a href=\"mailto:foo@bar.baz\">foo@bar.baz</a></p>\n"],
	["Autolinks", "hello@mail+xyz.example isn't valid, but hello+xyz@mail.example is.\n", "<p>hello@mail+xyz.example isn't valid, but <a href=\"mailto:hello+xyz@mail.example\">hello+xyz@mail.example</a> is.</p>\n"],
	["Autolinks", "a.b-c_d@a.b\n\na.b-c_d@a.b.\n\na.b-c_d@a.b-\n\na.b-c_d@a.b_\n", "<p><a href=\"mailto:a.b-c_d@a.b\">a.b-c_d@a.b</a></p>\n<p><a href=\"mailto:a.b-c_d@a.b\">a.b-c_d@a.b</a>.</p>\n<p>a.b-c_d@a.b-</p>\n<p>a.b-c_d@a.b_</p>\n"]
];

// commonmark.js's HTML for a Doc (the spec's examples' form)
private class Html {
	var out = new StringBuf();
	var last = "\n";
	public function new() {}
	public static function render(doc:Doc):String {
		var h = new Html();
		h.blocks(doc.blocks, false);
		return h.out.toString();
	}
	function lit(s:String) { if (s.length > 0) { out.add(s); last = s.charAt(s.length - 1); } }
	function cr() if (last != "\n") lit("\n");
	public static function esc(s:String):String return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;");
	static function url(s:String):String {
		var b = new StringBuf();
		var bytes = haxe.io.Bytes.ofString(s);
		var keep = ";/?:@&=+$,-_.!~*'()#";
		var i = 0;
		while (i < bytes.length) {
			var c = bytes.get(i);
			if (c == "%".code && i + 2 < bytes.length && isHex(bytes.get(i + 1)) && isHex(bytes.get(i + 2))) { b.addChar(c); i++; continue; }
			if ((c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || keep.indexOf(String.fromCharCode(c)) >= 0) b.addChar(c);
			else b.add("%" + StringTools.hex(c, 2));
			i++;
		}
		return b.toString();
	}
	static function isHex(c:Int) return (c >= 48 && c <= 57) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102);
	function blocks(bs:Array<Block>, tight:Bool) for (b in bs) block(b, tight);
	function block(b:Block, tight:Bool) {
		switch b {
			case Paragraph(c):
				if (tight) inl(c) else { cr(); lit("<p>"); inl(c); lit("</p>"); cr(); }
			case Heading(l, _, c): cr(); lit('<h$l>'); inl(c); lit('</h$l>'); cr();
			case Code(info, text):
				cr();
				var w = info.split(" ")[0].split("\t")[0];
				lit("<pre><code" + (w != "" ? ' class="language-${esc(w)}"' : "") + ">");
				lit(esc(text)); lit("</code></pre>"); cr();
			case Rule: cr(); lit("<hr />"); cr();
			case Quote(bs): cr(); lit("<blockquote>"); cr(); blocks(bs, false); cr(); lit("</blockquote>"); cr();
			case List(ordered, start, t, items):
				var tag = ordered ? "ol" : "ul";
				cr(); lit("<" + tag + (ordered && start != 1 ? ' start="$start"' : "") + ">"); cr();
				for (it in items) {
					lit("<li>");
					if (it.task != null) lit("<input " + (it.task ? 'checked="" ' : "") + 'disabled="" type="checkbox"> ');
					blocks(it.blocks, t); lit("</li>"); cr();
				}
				cr(); lit("</" + tag + ">"); cr();
			case Table(al, head, rows):
				cr(); lit("<table>\n<thead>\n<tr>\n");
				for (k in 0...head.length) { lit("<th" + a(al[k]) + ">"); inl(head[k]); lit("</th>\n"); }
				lit("</tr>\n</thead>\n");
				if (rows.length > 0) {
					lit("<tbody>\n");
					for (r in rows) { lit("<tr>\n"); for (k in 0...r.length) { lit("<td" + a(al[k]) + ">"); inl(r[k]); lit("</td>\n"); } lit("</tr>\n"); }
					lit("</tbody>\n");
				}
				lit("</table>\n");
			case Html(t): cr(); lit(t); cr();
		}
	}
	static function a(al:TableAlign):String return al == Auto ? "" : ' align="${(al : String)}"';
	function inl(c:Array<Inline>) for (i in c) switch i {
		case Text(t): lit(esc(t));
		case Emphasis(c): lit("<em>"); inl(c); lit("</em>");
		case Strong(c): lit("<strong>"); inl(c); lit("</strong>");
		case Strike(c): lit("<del>"); inl(c); lit("</del>");
		case CodeSpan(t): lit("<code>" + esc(t) + "</code>");
		case Link(h, t, c): lit('<a href="${esc(url(h))}"' + (t != "" ? ' title="${esc(t)}"' : "") + ">"); inl(c); lit("</a>");
		case Image(s, alt, t): lit('<img src="${esc(url(s))}" alt="${esc(alt)}"' + (t != "" ? ' title="${esc(t)}"' : "") + " />");
		case Autolink(h, t): lit('<a href="${esc(url(h))}">${esc(t)}</a>');
		case SoftBreak: lit("\n");
		case HardBreak: lit("<br />\n");
		case Html(t): lit(t);
	}
}


// (the docs' and the packages' READMEs, up to 16 KB each: the robustness property's seeds)
private function documents():Map<String, haxe.io.Bytes> {
	var out = new Map<String, haxe.io.Bytes>();
	function walk(dir:String)
		for (f in sys.FileSystem.readDirectory(dir)) {
			var p = '$dir/$f';
			if (sys.FileSystem.isDirectory(p)) walk(p);
			else if (f.endsWith(".md") && sys.FileSystem.stat(p).size <= 16384) out.set(p, sys.io.File.getBytes(p));
		}
	walk("docs");
	walk("src/helder");
	return out;
}

private function lines(text:String):Int
	return ~/\r\n?|\n/g.split(text).length;

// (the deepest container: a list's item two, a quote one)
private function depth(blocks:Array<Block>):Int {
	var most = 0;
	for (b in blocks) {
		var d = switch b {
			case List(_, _, _, items):
				var inner = 0;
				for (i in items) inner = Std.int(Math.max(inner, depth(i.blocks)));
				2 + inner;
			case Quote(inner): 1 + depth(inner);
			case _: 0;
		}
		if (d > most) most = d;
	}
	return most;
}
