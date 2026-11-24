package helder.markdown;

import helder.markdown.Doc;
import helder.markdown.Inlines.Ref;
import helder.markdown.Scan.*;

using StringTools;

// CommonMark's block structure (commonmark.js's algorithm): each line
// matched against the open blocks' continuations (a quote's ">", an item's
// indentation...), then new blocks' starts, then the rest added to the
// deepest block that takes lines or as a paragraph's lazy continuation.
// Columns count tabs to 4, a tab partly consumed by an indentation given
// back as spaces. GFM's tables: a delimiter row under a paragraph's last
// line with as many cells makes that line a table's header, rows following
// until a blank line or another block's start. When the lines are done the
// paragraphs' reference definitions are known, and every block's inlines
// are parsed with all of them.
class Blocks {
	final doc = new BNode(KDoc, 0);
	var tip:BNode;
	var oldtip:BNode;
	var lastMatched:BNode;
	var line = "";
	var lineNumber = 0;
	var offset = 0;
	var column = 0;
	var nextNonspace = 0;
	var nextNonspaceColumn = 0;
	var indent = 0;
	var indented = false;
	var blank = false;
	var partialTab = false;
	var allClosed = true;
	final refs = new Map<String, Ref>();
	final inlines:Inlines;
	final ids = new Map<String, Int>();

	public function new() {
		tip = oldtip = lastMatched = doc;
		inlines = new Inlines(refs);
	}

	public function parse(text:String):Array<Block> {
		var i = 0, n = text.length;
		while (i < n) {
			var j = i;
			while (j < n) {
				var c = text.fastCodeAt(j);
				if (c == 10 || c == 13) break;
				j++;
			}
			add(text.substring(i, j));
			if (j < n && text.fastCodeAt(j) == 13 && j + 1 < n && text.fastCodeAt(j + 1) == 10) j++;
			i = j + 1;
		}
		while (tip != null)
			finalize(tip);
		return blocks(doc);
	}

	// --- the line's position

	function findNextNonspace() {
		var i = offset, cols = column, c = -1;
		while (i < line.length) {
			c = line.fastCodeAt(i);
			if (c == 32) {
				i++;
				cols++;
			} else if (c == 9) {
				i++;
				cols += 4 - cols % 4;
			} else break;
		}
		blank = i >= line.length;
		nextNonspace = i;
		nextNonspaceColumn = cols;
		indent = cols - column;
		indented = indent >= 4;
	}

	function advanceNextNonspace() {
		offset = nextNonspace;
		column = nextNonspaceColumn;
		partialTab = false;
	}

	function advance(count:Int, columns:Bool) {
		while (count > 0 && offset < line.length) {
			if (line.fastCodeAt(offset) == 9) {
				var toTab = 4 - column % 4;
				if (columns) {
					partialTab = toTab > count;
					var step = toTab > count ? count : toTab;
					column += step;
					if (!partialTab) offset++;
					count -= step;
				} else {
					partialTab = false;
					column += toTab;
					offset++;
					count--;
				}
			} else {
				partialTab = false;
				offset++;
				column++;
				count--;
			}
		}
	}

	function addLine() {
		var prefix = "";
		if (partialTab) {
			offset++;
			prefix = "".lpad(" ", 4 - column % 4);
		}
		tip.lines.push(prefix + line.substr(offset));
	}

	function addChild(kind:BKind, at:Int):BNode {
		while (!canContain(tip.kind, kind))
			finalize(tip);
		var b = new BNode(kind, lineNumber);
		tip.append(b);
		tip = b;
		return b;
	}

	function closeUnmatched() {
		if (allClosed) return;
		while (oldtip != lastMatched) {
			var parent = oldtip.parent;
			finalize(oldtip);
			oldtip = parent;
		}
		allClosed = true;
	}

	static function canContain(parent:BKind, child:BKind):Bool
		return switch parent {
			case KDoc | KQuote: child != KItem;
			case KItem: child != KItem;
			case KList: child == KItem;
			case _: false;
		}

	static function acceptsLines(k:BKind):Bool
		return k == KPara || k == KCode || k == KHtml || k == KTable;

	// --- a line

	function add(text:String) {
		var container = doc;
		oldtip = tip;
		offset = column = 0;
		blank = partialTab = false;
		lineNumber++;
		line = text.indexOf("\x00") >= 0 ? text.replace("\x00", "\u{FFFD}") : text;
		var matched = true;
		while (container.children.length > 0) {
			var last = container.children[container.children.length - 1];
			if (!last.open) break;
			container = last;
			findNextNonspace();
			switch continues(container) {
				case 0:
				case 1:
					matched = false;
				case _:
					return;
			}
			if (!matched) {
				container = container.parent;
				break;
			}
		}
		allClosed = container == oldtip;
		lastMatched = container;
		var leaf = container.kind != KPara && container.kind != KTable && acceptsLines(container.kind);
		while (!leaf) {
			findNextNonspace();
			if (!indented && !maybeSpecial(at(line, nextNonspace))) {
				advanceNextNonspace();
				break;
			}
			var r = start(container);
			if (r == 0) {
				advanceNextNonspace();
				break;
			}
			container = tip;
			if (r == 2) leaf = true;
		}
		if (!allClosed && !blank && tip.kind == KPara) {
			addLine();
			return;
		}
		closeUnmatched();
		if (blank && container.children.length > 0) container.children[container.children.length - 1].lastLineBlank = true;
		var t = container.kind;
		// (a quote's lines are never blank; a fence's blanks and an empty item's first line do not make a list loose)
		var lastBlank = blank && !(t == KQuote || (t == KCode && container.fenced) || (t == KItem && container.children.length == 0 && container.startLine == lineNumber));
		var c = container;
		while (c != null) {
			c.lastLineBlank = lastBlank;
			c = c.parent;
		}
		if (acceptsLines(t)) {
			if (t == KTable && offset >= line.length) return;
			addLine();
			if (t == KHtml && container.htmlType >= 1 && container.htmlType <= 5 && htmlCloses(container.htmlType, line.substr(offset))) finalize(container);
		} else if (offset < line.length && !blank) {
			addChild(KPara, offset);
			advanceNextNonspace();
			addLine();
		}
	}

	static inline function maybeSpecial(c:Int):Bool
		return c == "#".code || c == "`".code || c == "~".code || c == "*".code || c == "+".code || c == "_".code || c == "=".code || c == "<".code
			|| c == ">".code || c == "-".code || c == "|".code || c == ":".code || isDigit(c);

	// 0: matched, 1: not, 2: the line is done (a fence closed)
	function continues(b:BNode):Int {
		switch b.kind {
			case KQuote:
				if (!indented && at(line, nextNonspace) == ">".code) {
					advanceNextNonspace();
					advance(1, false);
					if (isSpaceOrTab(at(line, offset))) advance(1, true);
					return 0;
				}
				return 1;
			case KItem:
				if (blank) {
					if (b.children.length == 0) return 1;
					advanceNextNonspace();
				} else if (indent >= b.markerOffset + b.padding) advance(b.markerOffset + b.padding, true);
				else return 1;
				return 0;
			case KCode:
				if (b.fenced) {
					if (indent <= 3 && at(line, nextNonspace) == b.fenceChar) {
						var j = nextNonspace;
						while (at(line, j) == b.fenceChar)
							j++;
						var k = j;
						while (isSpaceOrTab(at(line, k)))
							k++;
						if (j - nextNonspace >= b.fenceLength && k >= line.length) {
							finalize(b);
							return 2;
						}
					}
					var i = b.fenceOffset;
					while (i > 0 && isSpaceOrTab(at(line, offset))) {
						advance(1, true);
						i--;
					}
					return 0;
				}
				if (indent >= 4) advance(4, true) else if (blank) advanceNextNonspace() else return 1;
				return 0;
			case KHtml:
				return blank && (b.htmlType == 6 || b.htmlType == 7) ? 1 : 0;
			case KPara | KTable:
				return blank ? 1 : 0;
			case KList | KDoc:
				return 0;
			case _:
				return 1;
		}
	}

	// a block's start at the line: 0 none, 1 a container (look for more), 2 a leaf
	function start(container:BNode):Int {
		var c = at(line, nextNonspace);
		var deep = container.depth >= Markdown.MAX_NESTING;
		if (!indented) {
			if (c == ">".code && !deep) {
				advanceNextNonspace();
				advance(1, false);
				if (isSpaceOrTab(at(line, offset))) advance(1, true);
				closeUnmatched();
				addChild(KQuote, nextNonspace);
				return 1;
			}
			if (c == "#".code && atx()) return 2;
			if ((c == "`".code || c == "~".code) && fence()) return 2;
			if (c == "<".code && htmlStart(container)) return 2;
			if (container.kind == KPara && (c == "=".code || c == "-".code) && setext(container)) return 2;
			if (container.kind == KPara && table(container)) return 2;
			if ((c == "*".code || c == "_".code || c == "-".code) && rule()) return 2;
		}
		if ((!indented || container.kind == KList) && !deep && itemStart(container)) return 1;
		if (indented && tip.kind != KPara && !blank) {
			advance(4, true);
			closeUnmatched();
			addChild(KCode, offset);
			return 2;
		}
		return 0;
	}

	function atx():Bool {
		var j = nextNonspace, level = 0;
		while (at(line, j) == "#".code)
			j++;
		level = j - nextNonspace;
		if (level > 6 || (j < line.length && !isSpaceOrTab(at(line, j)))) return false;
		advanceNextNonspace();
		advance(level, false);
		closeUnmatched();
		var h = addChild(KHeading, nextNonspace);
		h.level = level;
		// (the closing #s: after a space, or all there is)
		var t = line.substr(offset).trim();
		var e = t.length;
		while (e > 0 && t.fastCodeAt(e - 1) == "#".code)
			e--;
		if (e == 0) t = "" else if (e < t.length && isSpaceOrTab(t.fastCodeAt(e - 1))) t = t.substr(0, e).rtrim();
		h.text = t;
		advance(line.length - offset, false);
		return true;
	}

	function fence():Bool {
		var c = at(line, nextNonspace), j = nextNonspace;
		while (at(line, j) == c)
			j++;
		var n = j - nextNonspace;
		if (n < 3) return false;
		// (a backtick fence's info has no backtick)
		if (c == "`".code && line.indexOf("`", j) >= 0) return false;
		closeUnmatched();
		var b = addChild(KCode, nextNonspace);
		b.fenced = true;
		b.fenceChar = c;
		b.fenceLength = n;
		b.fenceOffset = indent;
		advanceNextNonspace();
		advance(n, false);
		return true;
	}

	function rule():Bool {
		var c = at(line, nextNonspace), count = 0;
		for (j in nextNonspace...line.length) {
			var d = line.fastCodeAt(j);
			if (d == c) count++ else if (!isSpaceOrTab(d)) return false;
		}
		if (count < 3) return false;
		closeUnmatched();
		addChild(KRule, nextNonspace);
		advance(line.length - offset, false);
		return true;
	}

	function setext(para:BNode):Bool {
		var c = at(line, nextNonspace), j = nextNonspace;
		while (at(line, j) == c)
			j++;
		while (isSpaceOrTab(at(line, j)))
			j++;
		if (j < line.length) return false;
		closeUnmatched();
		var text = takeRefs(para.lines.join("\n"));
		if (text == "") return false;
		var h = new BNode(KHeading, para.startLine);
		h.level = c == "=".code ? 1 : 2;
		h.text = text.trim();
		para.parent.replace(para, h);
		tip = h;
		advance(line.length - offset, false);
		return true;
	}

	// a paragraph's start's reference definitions taken (refs), the rest returned
	function takeRefs(text:String):String {
		var at = 0;
		while (Scan.at(text, at) == "[".code) {
			var end = inlines.reference(text, at);
			if (end == at) break;
			at = end;
		}
		return at == 0 ? text : text.substr(at);
	}

	function table(para:BNode):Bool {
		var row = line.substr(nextNonspace);
		var aligns = delimiterRow(row);
		if (aligns == null) return false;
		var header = para.lines[para.lines.length - 1];
		var cells = splitRow(header);
		if (cells.length != aligns.length || (row.indexOf("|") < 0 && header.indexOf("|") < 0)) return false;
		closeUnmatched();
		var parent = para.parent;
		para.lines.pop();
		if (para.lines.length > 0) finalize(para) else {
			parent.children.remove(para);
			tip = parent;
		}
		var t = addChild(KTable, nextNonspace);
		t.aligns = aligns;
		t.head = cells;
		advance(line.length - offset, false);
		return true;
	}

	// a delimiter row's alignments (null: not one)
	static function delimiterRow(row:String):Null<Array<TableAlign>> {
		var cells = splitRow(row);
		if (cells.length == 0) return null;
		var out:Array<TableAlign> = [];
		for (c in cells) {
			var left = c.startsWith(":"), right = c.endsWith(":") && c.length > 1;
			var inner = c.substring(left ? 1 : 0, right ? c.length - 1 : c.length);
			if (inner.length == 0) return null;
			for (k in 0...inner.length)
				if (inner.fastCodeAt(k) != "-".code) return null;
			out.push(left && right ? Center : left ? Left : right ? Right : Auto);
		}
		return out;
	}

	// a row's cells, trimmed: split at pipes not escaped, the outer ones dropped
	static function splitRow(row:String):Array<String> {
		var r = row.trim();
		if (r.startsWith("|")) r = r.substr(1);
		var cells = [], cell = new StringBuf(), i = 0, any = false;
		while (i < r.length) {
			var c = r.fastCodeAt(i);
			if (c == "\\".code && at(r, i + 1) == "|".code) {
				cell.add("|");
				i += 2;
				any = true;
			} else if (c == "|".code) {
				cells.push(cell.toString().trim());
				cell = new StringBuf();
				any = false;
				i++;
			} else {
				cell.addChar(c);
				any = true;
				i++;
			}
		}
		if (any || cells.length == 0) {
			var last = cell.toString().trim();
			if (last != "" || cells.length == 0) cells.push(last);
		}
		return cells;
	}

	function itemStart(container:BNode):Bool {
		if (indent >= 4) return false;
		var rest = nextNonspace, c = at(line, rest);
		var ordered = false, bullet = -1, delim = -1, startNum = 1, len = 0;
		if (c == "*".code || c == "+".code || c == "-".code) {
			bullet = c;
			len = 1;
		} else if (isDigit(c)) {
			var j = rest;
			while (isDigit(at(line, j)) && j - rest < 10)
				j++;
			var d = at(line, j);
			if (j - rest > 9 || (d != ".".code && d != ")".code)) return false;
			startNum = Std.parseInt(line.substring(rest, j));
			if (container.kind == KPara && startNum != 1) return false;
			ordered = true;
			delim = d;
			len = j + 1 - rest;
		} else return false;
		var next = at(line, rest + len);
		if (!(next == -1 || isSpaceOrTab(next))) return false;
		// (one interrupting a paragraph has text)
		if (container.kind == KPara && line.substr(rest + len).trim() == "") return false;
		var markerOffset = indent;
		advanceNextNonspace();
		advance(len, true);
		var spacesCol = column, spacesOffset = offset;
		do {
			advance(1, true);
			next = at(line, offset);
		} while (column - spacesCol < 5 && isSpaceOrTab(next));
		var blankItem = at(line, offset) == -1;
		var after = column - spacesCol, padding = 0;
		if (after >= 5 || after < 1 || blankItem) {
			padding = len + 1;
			column = spacesCol;
			offset = spacesOffset;
			if (isSpaceOrTab(at(line, offset))) advance(1, true);
		} else padding = len + after;
		closeUnmatched();
		if (tip.kind != KList || tip.ordered != ordered || tip.delim != delim || tip.bullet != bullet) {
			var l = addChild(KList, nextNonspace);
			l.ordered = ordered;
			l.delim = delim;
			l.bullet = bullet;
			l.start = startNum;
		}
		var item = addChild(KItem, nextNonspace);
		item.markerOffset = markerOffset;
		item.padding = padding;
		return true;
	}

	// --- HTML blocks

	static final RAW = ["script", "pre", "textarea", "style"];
	static final BLOCK_TAGS = [
		"address", "article", "aside", "base", "basefont", "blockquote", "body", "caption", "center", "col", "colgroup", "dd", "details", "dialog", "dir", "div",
		"dl", "dt", "fieldset", "figcaption", "figure", "footer", "form", "frame", "frameset", "h1", "h2", "h3", "h4", "h5", "h6", "head", "header", "hr",
		"html", "iframe", "legend", "li", "link", "main", "menu", "menuitem", "nav", "noframes", "ol", "optgroup", "option", "p", "param", "search",
		"section", "summary", "table", "tbody", "td", "tfoot", "th", "thead", "title", "tr", "track", "ul"
	];

	function htmlStart(container:BNode):Bool {
		var s = line.substr(nextNonspace);
		var type = htmlType(s, container.kind == KPara || (!allClosed && !blank && tip.kind == KPara));
		if (type == 0) return false;
		closeUnmatched();
		var b = addChild(KHtml, offset);
		b.htmlType = type;
		return true;
	}

	// which of CommonMark's seven kinds of HTML block s starts (0: none; the 7th cannot interrupt a paragraph)
	static function htmlType(s:String, inPara:Bool):Int {
		var lower = s.toLowerCase();
		var name = tagName(lower, 1);
		if (RAW.contains(name) && tagEnds(lower, 1 + name.length, false)) return 1;
		if (s.startsWith("<!--")) return 2;
		if (s.startsWith("<?")) return 3;
		if (s.startsWith("<!") && isAlpha(at(s, 2))) return 4;
		if (s.startsWith("<![CDATA[")) return 5;
		var close = at(s, 1) == "/".code;
		var block = tagName(lower, close ? 2 : 1);
		if (BLOCK_TAGS.contains(block) && tagEnds(lower, (close ? 2 : 1) + block.length, true)) return 6;
		if (inPara) return 0;
		var end = close ? closeTag(s, 0) : openTag(s, 0);
		if (end < 0 || RAW.contains(name)) return 0;
		return s.substr(end).trim() == "" ? 7 : 0;
	}

	static function tagName(s:String, from:Int):String {
		var j = from;
		while (isAlnum(at(s, j)))
			j++;
		return s.substring(from, j);
	}

	static function tagEnds(s:String, at:Int, slash:Bool):Bool {
		var c = Scan.at(s, at);
		return c == -1 || isSpaceOrTab(c) || c == ">".code || (slash && c == "/".code && Scan.at(s, at + 1) == ">".code);
	}

	static function htmlCloses(type:Int, s:String):Bool {
		var lower = s.toLowerCase();
		return switch type {
			case 1: lower.indexOf("</script>") >= 0 || lower.indexOf("</pre>") >= 0 || lower.indexOf("</textarea>") >= 0 || lower.indexOf("</style>") >= 0;
			case 2: s.indexOf("-->") >= 0;
			case 3: s.indexOf("?>") >= 0;
			case 4: s.indexOf(">") >= 0;
			case _: s.indexOf("]]>") >= 0;
		}
	}

	// --- closing blocks

	function finalize(b:BNode) {
		var above = b.parent;
		b.open = false;
		switch b.kind {
			case KPara:
				b.text = takeRefs(b.lines.join("\n"));
				if (b.text.trim() == "") above.children.remove(b);
			case KCode:
				if (b.fenced) {
					b.info = unescape(b.lines.length > 0 ? b.lines[0].trim() : "");
					b.text = [for (k in 1...b.lines.length) b.lines[k] + "\n"].join("");
				} else {
					var n = b.lines.length;
					while (n > 0 && b.lines[n - 1].trim() == "")
						n--;
					b.text = [for (k in 0...n) b.lines[k] + "\n"].join("");
				}
			case KHtml:
				b.text = b.lines.join("\n");
			case KList:
				b.tight = true;
				for (k in 0...b.children.length) {
					var item = b.children[k], lastItem = k == b.children.length - 1;
					if (endsWithBlank(item) && !lastItem) {
						b.tight = false;
						break;
					}
					var loose = false;
					for (j in 0...item.children.length)
						if (endsWithBlank(item.children[j]) && (!lastItem || j < item.children.length - 1)) {
							loose = true;
							break;
						}
					if (loose) {
						b.tight = false;
						break;
					}
				}
			case _:
		}
		tip = above;
	}

	static function endsWithBlank(b:BNode):Bool {
		var x = b;
		while (x != null) {
			if (x.lastLineBlank) return true;
			if (!x.lastLineChecked && (x.kind == KList || x.kind == KItem)) {
				x.lastLineChecked = true;
				x = x.children.length > 0 ? x.children[x.children.length - 1] : null;
			} else {
				x.lastLineChecked = true;
				break;
			}
		}
		return false;
	}

	// --- the document's blocks

	function blocks(b:BNode):Array<Block> {
		var out:Array<Block> = [];
		for (c in b.children) {
			var block = convert(c);
			if (block != null) out.push(block);
		}
		return out;
	}

	function convert(b:BNode):Null<Block> {
		return switch b.kind {
			case KPara: Paragraph(inlines.parse(b.text.trim()));
			case KHeading:
				var content = inlines.parse(b.text);
				Heading(b.level, unique(Markdown.slug(Markdown.plain(content))), content);
			case KCode: Code(b.info, b.text);
			case KHtml: Block.Html(b.text);
			case KRule: Rule;
			case KQuote: Quote(blocks(b));
			case KList: List(b.ordered, b.start, b.tight, [for (item in b.children) listItem(item)]);
			case KTable:
				var n = b.aligns.length;
				var rows = [
					for (l in b.lines) {
						var cells = splitRow(l);
						[for (k in 0...n) inlines.parse(k < cells.length ? cells[k] : "")];
					}
				];
				Table(b.aligns, [for (h in b.head) inlines.parse(h)], rows);
			case _: null;
		}
	}

	function listItem(item:BNode):ListItem {
		var task:Null<Bool> = null;
		var first = item.children.length > 0 ? item.children[0] : null;
		if (first != null && first.kind == KPara) {
			var t = first.text;
			if (t.length >= 4 && t.fastCodeAt(0) == "[".code && t.fastCodeAt(2) == "]".code && isSpaceOrTab(t.fastCodeAt(3))) {
				var m = t.fastCodeAt(1);
				if (m == " ".code || m == "x".code || m == "X".code) {
					task = m != " ".code;
					first.text = t.substr(4);
				}
			}
		}
		return {blocks: blocks(item), task: task};
	}

	function unique(id:String):String {
		var n = ids.exists(id) ? ids.get(id) : 0;
		ids.set(id, n + 1);
		return n == 0 ? id : '$id-$n';
	}
}

private enum abstract BKind(Int) {
	var KDoc;
	var KQuote;
	var KList;
	var KItem;
	var KPara;
	var KHeading;
	var KCode;
	var KHtml;
	var KRule;
	var KTable;
}

// (a block being parsed)
private class BNode {
	public final kind:BKind;
	public final startLine:Int;
	public var parent:Null<BNode> = null;
	public var depth = 0;
	public final children:Array<BNode> = [];
	public var open = true;
	public var lastLineBlank = false;
	public var lastLineChecked = false;
	public final lines:Array<String> = [];
	public var text = "";
	public var level = 0;
	public var info = "";
	// (a fence's)
	public var fenced = false;
	public var fenceChar = 0;
	public var fenceLength = 0;
	public var fenceOffset = 0;
	public var htmlType = 0;
	// (a list's and an item's)
	public var ordered = false;
	public var bullet = -1;
	public var delim = -1;
	public var start = 1;
	public var tight = true;
	public var markerOffset = 0;
	public var padding = 0;
	// (a table's)
	public var aligns:Array<TableAlign> = [];
	public var head:Array<String> = [];

	public function new(kind:BKind, startLine:Int) {
		this.kind = kind;
		this.startLine = startLine;
	}

	public function append(c:BNode) {
		c.parent = this;
		c.depth = depth + 1;
		children.push(c);
	}

	public function replace(old:BNode, by:BNode) {
		by.parent = this;
		by.depth = depth + 1;
		children[children.indexOf(old)] = by;
	}
}
