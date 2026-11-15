using StringTools;

// The docs pages' Markdown (docs/<section>/<page>.md): the CommonMark that
// the pages use, parsed into blocks and inlines that Docs.hx renders with
// helder.web's static renderer. Blocks: ATX headings, paragraphs, fenced
// code (```lang, or ```lang title: a file's name shown above it), lists (- or 1., nested by indentation), pipe tables,
// block quotes, rules, and components: a line that is a capitalised tag
// alone (`<Example id="scene-nodes"/>`), its attributes strings. Inlines:
// `code`, **strong**, *em* or _em_, [links](url), backslash escapes. No raw
// HTML, no setext headings, no reference links: a page that needs more
// than this is a sign it wants a component.
enum Block {
	Heading(level:Int, id:String, content:Array<Inline>);
	Para(content:Array<Inline>);
	Code(lang:String, title:String, text:String);
	List(ordered:Bool, items:Array<Array<Block>>);
	Table(head:Array<Array<Inline>>, rows:Array<Array<Array<Inline>>>);
	Quote(blocks:Array<Block>);
	Rule;
	Component(name:String, attrs:Map<String, String>);
}

enum Inline {
	Text(text:String);
	CodeSpan(text:String);
	Strong(content:Array<Inline>);
	Em(content:Array<Inline>);
	Link(href:String, content:Array<Inline>);
}

class Markdown {
	static final HEADING = ~/^(#{1,6})\s+(.*?)\s*#*\s*$/;
	static final FENCE = ~/^(\s*)(```+|~~~+)\s*([^`\s]*)\s*([^`]*?)\s*$/;
	static final BULLET = ~/^(\s*)([-*+]|\d+[.)])(\s+|$)/;
	static final COMPONENT = ~/^<([A-Z][A-Za-z0-9]*)((?:\s+[a-zA-Z-]+="[^"]*")*)\s*\/>\s*$/;
	static final ATTR = ~/([a-zA-Z-]+)="([^"]*)"/;
	static final RULE = ~/^\s*(-{3,}|\*{3,}|_{3,})\s*$/;

	// a page's blocks; the headings' ids unique within it
	public static function parse(text:String):Array<Block> {
		var ids = new Map<String, Int>();
		return blocks(text.replace("\r\n", "\n").split("\n"), ids);
	}

	static function blocks(lines:Array<String>, ids:Map<String, Int>):Array<Block> {
		var out:Array<Block> = [];
		var i = 0;
		while (i < lines.length) {
			var line = lines[i];
			if (line.trim() == "") {
				i++;
				continue;
			}
			if (FENCE.match(line)) {
				var indent = FENCE.matched(1).length, mark = FENCE.matched(2), lang = FENCE.matched(3), title = FENCE.matched(4);
				var body = [];
				i++;
				while (i < lines.length && !lines[i].trim().startsWith(mark))
					body.push(dedent(lines[i++], indent));
				i++;
				out.push(Code(lang, title, body.join("\n")));
				continue;
			}
			if (HEADING.match(line)) {
				var level = HEADING.matched(1).length, content = inlines(HEADING.matched(2));
				out.push(Heading(level, unique(slug(plain(content)), ids), content));
				i++;
				continue;
			}
			if (COMPONENT.match(line.trim())) {
				var name = COMPONENT.matched(1), rest = COMPONENT.matched(2);
				var attrs = new Map<String, String>();
				while (ATTR.match(rest)) {
					attrs.set(ATTR.matched(1), ATTR.matched(2));
					rest = ATTR.matchedRight();
				}
				out.push(Component(name, attrs));
				i++;
				continue;
			}
			if (RULE.match(line)) {
				out.push(Rule);
				i++;
				continue;
			}
			if (line.trim().startsWith(">")) {
				var body = [];
				while (i < lines.length && lines[i].trim().startsWith(">")) {
					var l = lines[i++].trim().substr(1);
					body.push(l.startsWith(" ") ? l.substr(1) : l);
				}
				out.push(Quote(blocks(body, ids)));
				continue;
			}
			if (line.trim().startsWith("|") && i + 1 < lines.length && ~/^\s*\|?\s*:?-+/.match(lines[i + 1])) {
				var head = cells(line);
				var rows = [];
				i += 2;
				while (i < lines.length && lines[i].trim().startsWith("|"))
					rows.push(cells(lines[i++]));
				out.push(Table(head, rows));
				continue;
			}
			if (BULLET.match(line)) {
				var indent = BULLET.matched(1).length;
				var ordered = !~/[-*+]/.match(BULLET.matched(2));
				var items:Array<Array<Block>> = [];
				while (i < lines.length && BULLET.match(lines[i]) && BULLET.matched(1).length == indent) {
					var inner = indent + BULLET.matched(2).length + BULLET.matched(3).length;
					var body = [BULLET.matchedRight()];
					i++;
					// (the item's lines: indented past its marker, or a paragraph's lazy continuation)
					while (i < lines.length) {
						var l = lines[i];
						if (l.trim() == "") {
							if (i + 1 < lines.length && indentOf(lines[i + 1]) > indent && lines[i + 1].trim() != "") {
								body.push("");
								i++;
								continue;
							}
							break;
						}
						if (indentOf(l) > indent) {
							body.push(dedent(l, inner));
							i++;
							continue;
						}
						if (BULLET.match(l) || HEADING.match(l) || FENCE.match(l) || l.trim().startsWith("|") || COMPONENT.match(l.trim()))
							break;
						body.push(l);
						i++;
					}
					items.push(blocks(body, ids));
					// (a blank line between items keeps the list)
					var j = i;
					while (j < lines.length && lines[j].trim() == "")
						j++;
					if (j > i && j < lines.length && BULLET.match(lines[j]) && BULLET.matched(1).length == indent) i = j;
				}
				out.push(List(ordered, items));
				continue;
			}
			// a paragraph: until a blank line or another block
			var body = [line.trim()];
			i++;
			while (i < lines.length) {
				var l = lines[i];
				if (l.trim() == "" || HEADING.match(l) || FENCE.match(l) || BULLET.match(l) || l.trim().startsWith(">") || COMPONENT.match(l.trim())
					|| (l.trim().startsWith("|") && i + 1 < lines.length && ~/^\s*\|?\s*:?-+/.match(lines[i + 1])))
					break;
				body.push(l.trim());
				i++;
			}
			out.push(Para(inlines(body.join("\n"))));
		}
		return out;
	}

	static function indentOf(l:String):Int {
		var n = 0;
		while (n < l.length && (l.charAt(n) == " " || l.charAt(n) == "\t"))
			n++;
		return n;
	}

	static function dedent(l:String, n:Int):String {
		var k = 0;
		while (k < n && k < l.length && (l.charAt(k) == " " || l.charAt(k) == "\t"))
			k++;
		return l.substr(k);
	}

	static function cells(line:String):Array<Array<Inline>> {
		var s = line.trim();
		if (s.startsWith("|")) s = s.substr(1);
		if (s.endsWith("|")) s = s.substr(0, s.length - 1);
		// (a pipe inside a code span stays in its cell)
		var parts = [], cur = new StringBuf(), code = false;
		for (k in 0...s.length) {
			var c = s.charAt(k);
			if (c == "`") code = !code;
			if (c == "|" && !code && (k == 0 || s.charAt(k - 1) != "\\")) {
				parts.push(cur.toString());
				cur = new StringBuf();
			} else
				cur.add(c);
		}
		parts.push(cur.toString());
		return [for (p in parts) inlines(p.trim())];
	}

	// a span's inlines
	public static function inlines(s:String):Array<Inline> {
		var out:Array<Inline> = [];
		var text = new StringBuf();
		function flush() {
			var t = text.toString();
			if (t != "") out.push(Text(t));
			text = new StringBuf();
		}
		var i = 0;
		while (i < s.length) {
			var c = s.charAt(i);
			if (c == "\\" && i + 1 < s.length && ~/[\\`*_\[\]()#+\-.!<>|{}]/.match(s.charAt(i + 1))) {
				text.add(s.charAt(i + 1));
				i += 2;
				continue;
			}
			if (c == "`") {
				var n = 0;
				while (i + n < s.length && s.charAt(i + n) == "`")
					n++;
				var mark = s.substr(i, n);
				var end = s.indexOf(mark, i + n);
				if (end > 0) {
					flush();
					var code = s.substring(i + n, end).replace("\n", " ");
					if (code.startsWith(" ") && code.endsWith(" ") && code.trim() != "") code = code.substr(1, code.length - 2);
					out.push(CodeSpan(code));
					i = end + n;
					continue;
				}
				text.add(mark);
				i += n;
				continue;
			}
			if (c == "*" && s.charAt(i + 1) == "*") {
				var end = s.indexOf("**", i + 2);
				if (end > i + 2) {
					flush();
					out.push(Strong(inlines(s.substring(i + 2, end))));
					i = end + 2;
					continue;
				}
			}
			if ((c == "*" || c == "_") && i + 1 < s.length && s.charAt(i + 1) != " " && s.charAt(i + 1) != c
				&& (c == "*" || i == 0 || !~/[A-Za-z0-9]/.match(s.charAt(i - 1)))) {
				var end = i + 1;
				while (true) {
					end = s.indexOf(c, end);
					if (end < 0 || s.charAt(end - 1) != " " && (c == "*" || end + 1 >= s.length || !~/[A-Za-z0-9]/.match(s.charAt(end + 1)))) break;
					end++;
				}
				if (end > i + 1) {
					flush();
					out.push(Em(inlines(s.substring(i + 1, end))));
					i = end + 1;
					continue;
				}
			}
			if (c == "[") {
				var close = matching(s, i, "[", "]");
				if (close > 0 && s.charAt(close + 1) == "(") {
					var end = matching(s, close + 1, "(", ")");
					if (end > 0) {
						flush();
						out.push(Link(s.substring(close + 2, end).trim(), inlines(s.substring(i + 1, close))));
						i = end + 1;
						continue;
					}
				}
			}
			text.add(c);
			i++;
		}
		flush();
		return out;
	}

	// (the index of the bracket closing the one at i, nested ones and code spans skipped; -1: none)
	static function matching(s:String, i:Int, open:String, close:String):Int {
		var depth = 0, k = i;
		while (k < s.length) {
			var c = s.charAt(k);
			if (c == "\\") {
				k += 2;
				continue;
			}
			if (c == "`") {
				var end = s.indexOf("`", k + 1);
				if (end < 0) return -1;
				k = end + 1;
				continue;
			}
			if (c == open) depth++;
			if (c == close && --depth == 0) return k;
			k++;
		}
		return -1;
	}

	// an inline's text alone (a heading's for its id, the search index's)
	public static function plain(content:Array<Inline>):String {
		var b = new StringBuf();
		for (n in content)
			switch n {
				case Text(t) | CodeSpan(t): b.add(t);
				case Strong(c) | Em(c) | Link(_, c): b.add(plain(c));
			}
		return b.toString();
	}

	// GitHub's heading ids: lower case, punctuation dropped, spaces as dashes
	public static function slug(s:String):String {
		var b = new StringBuf();
		for (k in 0...s.length) {
			var c = s.charAt(k).toLowerCase();
			if (~/[a-z0-9_-]/.match(c)) b.add(c) else if (c == " ") b.add("-");
		}
		return b.toString();
	}

	static function unique(id:String, ids:Map<String, Int>):String {
		var n = ids.exists(id) ? ids.get(id) : 0;
		ids.set(id, n + 1);
		return n == 0 ? id : id + "-" + n;
	}

	// every block's text, for the search index
	public static function text(blocks:Array<Block>):String {
		var b = [];
		for (x in blocks)
			switch x {
				case Heading(_, _, c) | Para(c): b.push(plain(c));
				case List(_, items): for (it in items) b.push(text(it));
				case Quote(bs): b.push(text(bs));
				case Table(head, rows):
					for (c in head) b.push(plain(c));
					for (r in rows) for (c in r) b.push(plain(c));
				case Code(_) | Rule | Component(_):
			}
		return b.join(" ");
	}
}
