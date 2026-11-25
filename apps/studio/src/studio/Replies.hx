package studio;

import helder.markdown.Doc;
import helder.markdown.Markdown;

using StringTools;

// An agent's reply as the chat shows it: its Markdown, where a link the
// studio knows is a chip ("studio:screen/<name>", "studio:frame/<file>#<name>",
// "studio:group/<file>#<title>": a place on the canvas, the camera flies there; a file of the project, "path", "path:12", "path#L12",
// "file://…": a file's, the code panel opens at its line), a code span
// naming a file of the project a file's chip too; the files it changed, the
// last few shown, the ones before folded into one line.
class Replies {
	public static inline var SCREEN = "studio:screen/";
	public static inline var FRAME = "studio:frame/";
	public static inline var GROUP = "studio:group/";
	// the lines shown before the rest fold
	public static inline var SHOWN = 3;

	// a link's chip slot (null: a plain link)
	public static function chip(href:String, dir:Null<String>):Null<String> {
		if (href.startsWith(SCREEN) || href.startsWith(FRAME)) return "chip-screen";
		if (href.startsWith(GROUP)) return "chip-group";
		return dir != null && FileLink.parse(href, dir) != null ? "chip-file" : null;
	}

	// a place chip's place (null: not one): a screen by name, a design file's frame or group
	public static function place(href:String):Null<Spot> {
		function decode(s:String):String
			return try s.urlDecode() catch (_:Dynamic) s;
		if (href.startsWith(SCREEN)) return Screen(decode(href.substr(SCREEN.length)));
		for (prefix in [FRAME, GROUP]) {
			if (!href.startsWith(prefix)) continue;
			var rest = href.substr(prefix.length), hash = rest.indexOf("#");
			if (hash <= 0) return null;
			var file = decode(rest.substr(0, hash)), name = decode(rest.substr(hash + 1));
			return prefix == FRAME ? Frame(file, name) : Group(file, name);
		}
		return null;
	}

	// the reply parsed, a code span naming a file of the project (exists: the
	// studio's) a link to it, a link's code a chip's text
	public static function parse(text:String, dir:Null<String>, exists:String->Bool):Doc {
		var d = Markdown.parse(text);
		if (dir == null) return d;
		function inl(content:Array<Inline>):Array<Inline>
			return [
				for (i in content)
					switch i {
						case CodeSpan(t):
							var l = FileLink.parse(t, dir);
							l != null && !t.contains(" ") && exists(l.path) ? Link(t, "", [Text(t)]) : i;
						case Link(href, title, [CodeSpan(t)]): Link(href, title, [Text(t)]);
						case Link(href, title, c): Link(href, title, inl(c));
						case Emphasis(c): Emphasis(inl(c));
						case Strong(c): Strong(inl(c));
						case Strike(c): Strike(inl(c));
						case _: i;
					}
			];
		function blocks(bs:Array<Block>):Array<Block>
			return [
				for (b in bs)
					switch b {
						case Heading(l, id, c): Heading(l, id, inl(c));
						case Paragraph(c): Paragraph(inl(c));
						case List(o, s, t, items): List(o, s, t, [for (it in items) {blocks: blocks(it.blocks), task: it.task}]);
						case Quote(q): Quote(blocks(q));
						case Table(a, h, rows): Table(a, [for (c in h) inl(c)], [for (r in rows) [for (c in r) inl(c)]]);
						case _: b;
					}
			];
		return {blocks: blocks(d.blocks), frontMatter: d.frontMatter};
	}

	// lines as shown: the last SHOWN (all of them when open), how many folded before them
	public static function fold<T>(all:Array<T>, open:Bool):{folded:Int, shown:Array<T>} {
		if (open || all.length <= SHOWN + 1) return {folded: 0, shown: all};
		return {folded: all.length - SHOWN, shown: all.slice(all.length - SHOWN)};
	}
}

// a place on the canvas a chip names
enum Spot {
	Screen(name:String);
	Frame(file:String, name:String);
	Group(file:String, title:String);
}
