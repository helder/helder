package viewer;

import helder.markdown.Doc;
import helder.markdown.Markdown;
import helder.markdown.MarkdownView;
import helder.ui.Node;
import helder.view.graph.Graph;

using StringTools;

// A Markdown document shown full size (MarkdownPage): its text parsed, its
// words and headings counted, whether its source is shown, and the node
// that scrolls (the document's column, or the source's CodeView) for the
// keys: a screen (seven eighths of the view), a line, the top, the end.
class MarkdownDoc {
	public static inline var LINE = 40.0;
	static inline var SCREEN = 0.875;

	public final path:String;
	public final text:String;
	public final doc:Doc;
	public final words:Int;
	public final headings:Int;
	// its size in bytes (UTF-8)
	public final size:Int;
	// the source shown instead of the document
	public final source = Graph.signal(false);
	// the page's nodes once made: the document's view, the source's
	public var view:Null<MarkdownView> = null;
	public var code:Null<helder.ui.code.CodeView> = null;
	// a heading to show first ("#id" of the link that opened it)
	public var anchor:Null<String> = null;
	// its pictures of its folder (local's paths, each once), and the sizes
	// their headers say, read before it is shown (Viewer.measure): each laid
	// out at its size before it is decoded
	public final pictures:Array<String> = [];
	public final sizes = new Map<String, {width:Int, height:Int}>();

	public function new(path:String, text:String) {
		this.path = path;
		this.text = text;
		doc = Markdown.parse(text);
		var c = count(doc);
		words = c.words;
		headings = c.headings;
		size = haxe.io.Bytes.ofString(text).length;
		function inlines(is:Array<Inline>)
			for (i in is) switch i {
				case Image(src, _, _):
					var p = local(src);
					if (p != null && !pictures.contains(p)) pictures.push(p);
				case Emphasis(c) | Strong(c) | Strike(c) | Link(_, _, c): inlines(c);
				case _:
			}
		function blocks(bs:Array<Block>)
			for (b in bs) switch b {
				case Paragraph(c): inlines(c);
				case List(_, _, _, items): for (i in items) blocks(i.blocks);
				case Quote(inner): blocks(inner);
				case _:
			}
		blocks(doc.blocks);
	}

	// a picture's path in its folder (null: remote, a data: URL, none)
	public function local(src:String):Null<String> {
		var s = src.trim();
		if (s == "" || s.indexOf("://") >= 0 || s.startsWith("data:") || s.startsWith("//")) return null;
		if (s.indexOf("#") >= 0) s = s.substr(0, s.indexOf("#"));
		if (s.indexOf("?") >= 0) s = s.substr(0, s.indexOf("?"));
		return Explorer.resolve(Browser.parent(path) ?? "", unescape(s));
	}

	// (a link's "#Set%20up": the heading's id; a picture's "my%20photo.png")
	public static function unescape(s:String):String
		return try StringTools.urlDecode(s) catch (_:Dynamic) s;

	// a document's words (its text's, code's not) and headings
	public static function count(doc:Doc):{words:Int, headings:Int} {
		var words = 0, headings = 0;
		function text(s:String) {
			var inWord = false;
			for (i in 0...s.length) {
				var c = s.fastCodeAt(i);
				var space = c == 32 || c == 9 || c == 10 || c == 13;
				if (!space && !inWord) words++;
				inWord = !space;
			}
		}
		function blocks(bs:Array<Block>)
			for (b in bs) switch b {
				case Heading(_, _, c):
					headings++;
					text(Markdown.plain(c));
				case Paragraph(c): text(Markdown.plain(c));
				case List(_, _, _, items): for (i in items) blocks(i.blocks);
				case Quote(inner): blocks(inner);
				case Table(_, head, rows):
					for (h in head) text(Markdown.plain(h));
					for (r in rows) for (c in r) text(Markdown.plain(c));
				case _:
			}
		blocks(doc.blocks);
		return {words: words, headings: headings};
	}

	// the first heading's text (a tile's title; null: none)
	public static function title(doc:Doc):Null<String> {
		for (b in doc.blocks)
			switch b {
				case Heading(_, _, c): return Markdown.plain(c).trim();
				case _:
			}
		return null;
	}

	// what scrolls now: the source's or the document's
	public function scroller():Null<Node>
		return source.peek() ? code : view?.scroller;

	public function screens(n:Float) {
		var c = code;
		if (source.peek() && c != null) {
			c.scrollTo(c.scrollLeft, c.scrollTop + n * c.height * SCREEN);
			return;
		}
		var s = scroller();
		if (s != null) by(s, n * s.height * SCREEN);
	}

	public function lines(n:Float) {
		var c = code;
		if (source.peek() && c != null) {
			c.scrollTo(c.scrollLeft, c.scrollTop + n * c.lineHeight);
			return;
		}
		var s = scroller();
		if (s != null) by(s, n * LINE);
	}

	// the top (-1) or the end (1)
	public function end(dir:Int) {
		var c = code;
		if (source.peek() && c != null) {
			c.scrollTo(c.scrollLeft, dir < 0 ? 0 : c.model.lineCount * c.lineHeight);
			return;
		}
		var v = view;
		if (v == null || v.scroller == null) return;
		var s = v.scroller;
		if (Std.isOfType(s, helder.ui.VirtualScroll)) {
			var list:helder.ui.VirtualScroll = cast s;
			if (list.count > 0) list.scrollToIndex(dir < 0 ? 0 : list.count - 1, dir < 0 ? "start" : "end");
			return;
		}
		by(s, dir < 0 ? -s.scrollY : 1e9);
	}

	// (eased, as the window's own scrolling keys; no window: at once)
	static function by(s:Node, dy:Float) {
		if (s.ui != null) s.ui.scrollBy(s, 0, dy) else s.scrollY = Math.max(0, s.scrollY + dy);
	}
}
