package helder.markdown;

import helder.markdown.Doc;

using StringTools;

// Markdown as CommonMark reads it (0.31: its block structure, inline
// rules, entities, reference definitions) with GFM's tables, task list
// items, strikethrough and extended autolinks; raw HTML kept as text
// (Html blocks and inlines), a front matter's text taken off the top.
//
//   var doc = Markdown.parse(File.getContent("README.md"));
//   for (b in doc.blocks) switch b {
//     case Heading(level, id, content): trace(level, Markdown.plain(content));
//     case _:
//   }
class Markdown {
	// containers (quotes, lists' items) and inlines nested deeper are text (markdown-it's limit too)
	public static inline var MAX_NESTING = 100;

	public static function parse(text:String):Doc {
		var body = text.startsWith("\u{FEFF}") ? text.substr(1) : text;
		var front:Null<String> = null;
		var top = firstLine(body);
		if (body.substr(0, top).rtrim() == "---") {
			var i = next(body, top);
			while (Scan.tick() && i < body.length) {
				var e = firstLineFrom(body, i), l = body.substring(i, e).rtrim();
				if (l == "---" || l == "...") {
					front = body.substring(next(body, top), i);
					body = body.substr(next(body, e));
					break;
				}
				i = next(body, e);
			}
		}
		return {blocks: new Blocks().parse(body), frontMatter: front};
	}

	// the text of inlines, without their markup (an image's its alt)
	public static function plain(content:Array<Inline>):String {
		var out = new StringBuf();
		addPlain(content, out);
		return out.toString();
	}

	static function addPlain(content:Array<Inline>, out:StringBuf)
		for (i in content) switch i {
			case Text(t) | CodeSpan(t) | Html(t): out.add(t);
			case Emphasis(c) | Strong(c) | Strike(c) | Link(_, _, c): addPlain(c, out);
			case Image(_, alt, _): out.add(alt);
			case Autolink(_, t): out.add(t);
			case SoftBreak | HardBreak: out.add(" ");
		}

	// a heading's id from its text, as GitHub makes it: lower case, spaces as
	// hyphens, punctuation but - and _ left out ("Set up, again!" is set-up-again)
	public static function slug(text:String):String {
		var out = new StringBuf(), lower = text.trim().toLowerCase();
		for (k in 0...lower.length) {
			Scan.tick();
			var c = lower.fastCodeAt(k);
			if (c == " ".code || c == "\t".code) out.add("-");
			else if (c == "-".code || c == "_".code || !Scan.isPunct(c) && c > 32) out.addChar(c);
		}
		return out.toString();
	}

	static function firstLine(s:String):Int
		return firstLineFrom(s, 0);

	static function firstLineFrom(s:String, i:Int):Int {
		var j = i;
		while (Scan.tick() && j < s.length && s.fastCodeAt(j) != 10 && s.fastCodeAt(j) != 13)
			j++;
		return j;
	}

	// (past the line end at i)
	static function next(s:String, i:Int):Int
		return i < s.length && s.fastCodeAt(i) == 13 && i + 1 < s.length && s.fastCodeAt(i + 1) == 10 ? i + 2 : i + 1;
}
