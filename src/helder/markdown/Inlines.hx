package helder.markdown;

import helder.markdown.Doc;
import helder.markdown.Scan.*;

using StringTools;

// A link reference definition's destination and title
typedef Ref = {href:String, title:String}

// CommonMark's inline rules on a block's text (commonmark.js's algorithm):
// a pass over the text making nodes, delimiter runs (* _ ~) and brackets
// on stacks, links and images matched at each "]", emphasis resolved by
// the delimiter algorithm (openers' bottoms by kind, length mod 3 and
// whether the closer opens too: linear). Code spans find their closing
// run through the runs of backticks indexed once per text, raw HTML's
// comments and the like remember a close not found, so neither rescans.
// GFM: ~strike~ and ~~strike~~ (a closer as long as its opener), and its
// extended autolinks in text outside links.
@:allow(helder.markdown)
class Inlines {
	final refs:Map<String, Ref>;
	var s = "";
	var pos = 0;
	var delims:Null<Delim> = null;
	var brackets:Null<Bracket> = null;
	// (the text's runs of backticks by length: their starts, and how far each length's list is used)
	var ticks:Null<Map<Int, Array<Int>>> = null;
	var tickNext:Map<Int, Int> = new Map();
	// (raw HTML's closes that are not in the rest of the text)
	var noComment = false;
	var noPi = false;
	var noCdata = false;
	var noDecl = false;

	public function new(refs:Map<String, Ref>)
		this.refs = refs;

	public function parse(text:String):Array<Inline> {
		s = text;
		pos = 0;
		delims = null;
		brackets = null;
		ticks = null;
		tickNext = new Map();
		noComment = noPi = noCdata = noDecl = false;
		var root = new INode(KRoot);
		while (Scan.tick() && pos < s.length)
			step(root);
		emphasis(null);
		return convert(root, false, 0);
	}

	function step(block:INode) {
		var c = s.fastCodeAt(pos);
		var ok = switch c {
			case "\n".code: newline(block);
			case "\\".code: backslash(block);
			case "`".code: backticks(block);
			case "*".code | "_".code | "~".code: delim(c, block);
			case "[".code:
				pos++;
				addBracket(block.add(INode.ofText("[")), pos - 1, false);
				true;
			case "!".code: bang(block);
			case "]".code: closeBracket(block);
			case "<".code: autolink(block) || html(block);
			case "&".code: entityAt(block);
			case _: string(block);
		}
		if (!ok) {
			block.add(INode.ofText(String.fromCharCode(c)));
			pos++;
		}
	}

	static inline function special(c:Int):Bool
		return c == "\n".code || c == "\\".code || c == "`".code || c == "*".code || c == "_".code || c == "~".code || c == "[".code || c == "]".code
			|| c == "!".code || c == "<".code || c == "&".code;

	function string(block:INode):Bool {
		var start = pos;
		while (Scan.tick() && pos < s.length && !special(s.fastCodeAt(pos)))
			pos++;
		if (pos == start) return false;
		block.add(INode.ofText(s.substring(start, pos)));
		return true;
	}

	function newline(block:INode):Bool {
		pos++;
		var last = block.last;
		if (last != null && last.kind == KText && last.text.endsWith(" ")) {
			var t = last.text, hard = t.length >= 2 && t.fastCodeAt(t.length - 2) == " ".code;
			var e = t.length;
			while (Scan.tick() && e > 0 && t.fastCodeAt(e - 1) == " ".code)
				e--;
			last.text = t.substr(0, e);
			block.add(new INode(hard ? KHard : KSoft));
		} else block.add(new INode(KSoft));
		while (Scan.tick() && pos < s.length && isSpaceOrTab(s.fastCodeAt(pos)))
			pos++;
		return true;
	}

	function backslash(block:INode):Bool {
		pos++;
		var c = at(s, pos);
		if (c == "\n".code) {
			pos++;
			block.add(new INode(KHard));
			while (Scan.tick() && pos < s.length && isSpaceOrTab(s.fastCodeAt(pos)))
				pos++;
		} else if (c >= 0 && isAsciiPunct(c)) {
			block.add(INode.ofText(String.fromCharCode(c)));
			pos++;
		} else block.add(INode.ofText("\\"));
		return true;
	}

	function backticks(block:INode):Bool {
		var start = pos;
		while (Scan.tick() && at(s, pos) == "`".code)
			pos++;
		var n = pos - start, after = pos;
		var close = closingTicks(n, after);
		if (close < 0) {
			block.add(INode.ofText(s.substring(start, after)));
			return true;
		}
		var code = s.substring(after, close).replace("\n", " ");
		// (one space stripped from each end when both have one and it is not all spaces)
		if (code.length >= 2 && code.fastCodeAt(0) == " ".code && code.fastCodeAt(code.length - 1) == " ".code && code.trim() != "")
			code = code.substr(1, code.length - 2);
		var node = new INode(KCode);
		node.text = code;
		block.add(node);
		pos = close + n;
		return true;
	}

	// the start of the next run of exactly n backticks from `from` (-1: none)
	function closingTicks(n:Int, from:Int):Int {
		if (ticks == null) {
			var m = new Map<Int, Array<Int>>();
			var i = 0;
			while (Scan.tick() && i < s.length) {
				if (s.fastCodeAt(i) == "`".code) {
					var j = i;
					while (Scan.tick() && at(s, j) == "`".code)
						j++;
					var l = j - i;
					var list = m.get(l);
					if (list == null) m.set(l, list = []);
					list.push(i);
					i = j;
				} else i++;
			}
			ticks = m;
		}
		var list = ticks.get(n);
		if (list == null) return -1;
		var k = tickNext.exists(n) ? tickNext.get(n) : 0;
		while (Scan.tick() && k < list.length && list[k] < from)
			k++;
		tickNext.set(n, k);
		return k < list.length ? list[k] : -1;
	}

	// --- emphasis

	function delim(c:Int, block:INode):Bool {
		var start = pos;
		while (Scan.tick() && at(s, pos) == c)
			pos++;
		var n = pos - start;
		var before = start == 0 ? -1 : s.fastCodeAt(start - 1), after = at(s, pos);
		var afterWhite = isWhite(after), afterPunct = after >= 0 && isPunct(after);
		var beforeWhite = isWhite(before), beforePunct = before >= 0 && isPunct(before);
		var left = !afterWhite && (!afterPunct || beforeWhite || beforePunct);
		var right = !beforeWhite && (!beforePunct || afterWhite || afterPunct);
		var open = left, close = right;
		if (c == "_".code) {
			open = left && (!right || beforePunct);
			close = right && (!left || afterPunct);
		}
		var node = block.add(INode.ofText(s.substring(start, pos)));
		// (GFM: a strike is one or two tildes)
		if (c == "~".code && n > 2) return true;
		if (open || close) {
			var d = new Delim(c, n, node, open, close);
			d.prev = delims;
			if (delims != null) delims.next = d;
			delims = d;
		}
		return true;
	}

	function removeDelim(d:Delim) {
		if (d.prev != null) d.prev.next = d.next;
		if (d.next != null) d.next.prev = d.prev;
		else delims = d.prev;
	}

	function emphasis(bottom:Null<Delim>) {
		var bottoms:Array<Null<Delim>> = [for (_ in 0...16) bottom];
		var closer = delims;
		while (Scan.tick() && closer != null && closer.prev != bottom)
			closer = closer.prev;
		while (Scan.tick() && closer != null) {
			if (!closer.close) {
				closer = closer.next;
				continue;
			}
			var cc = closer.c;
			var index = cc == "~".code ? 12 + (closer.orig == 1 ? 0 : 1) : (cc == "_".code ? 0 : 6) + (closer.open ? 3 : 0) + closer.orig % 3;
			var opener = closer.prev, found = false;
			while (Scan.tick() && opener != null && opener != bottom && opener != bottoms[index]) {
				if (opener.c == cc && opener.open) {
					if (cc == "~".code) {
						if (opener.num == closer.num) {
							found = true;
							break;
						}
					} else {
						var odd = (closer.open || opener.close) && closer.orig % 3 != 0 && (opener.orig + closer.orig) % 3 == 0;
						if (!odd) {
							found = true;
							break;
						}
					}
				}
				opener = opener.prev;
			}
			var old = closer;
			if (found) {
				var use = cc == "~".code ? closer.num : closer.num >= 2 && opener.num >= 2 ? 2 : 1;
				var on = opener.node, cn = closer.node;
				opener.num -= use;
				closer.num -= use;
				on.text = on.text.substr(0, on.text.length - use);
				cn.text = cn.text.substr(0, cn.text.length - use);
				var wrap = new INode(cc == "~".code ? KStrike : use == 1 ? KEmph : KStrong);
				var t = on.next;
				while (Scan.tick() && t != null && t != cn) {
					var next = t.next;
					t.unlink();
					wrap.add(t);
					t = next;
				}
				on.insertAfter(wrap);
				// (the delimiters between are text now)
				opener.next = closer;
				closer.prev = opener;
				if (opener.num == 0) {
					on.unlink();
					removeDelim(opener);
				}
				if (closer.num == 0) {
					cn.unlink();
					var next = closer.next;
					removeDelim(closer);
					closer = next;
				}
			} else {
				closer = closer.next;
				bottoms[index] = old.prev;
				if (!old.open) removeDelim(old);
			}
		}
		while (Scan.tick() && delims != null && delims != bottom)
			removeDelim(delims);
	}

	// --- links and images

	function addBracket(node:INode, index:Int, image:Bool) {
		if (brackets != null) brackets.bracketAfter = true;
		var b = new Bracket(node, index, image);
		b.prev = brackets;
		b.prevDelim = delims;
		brackets = b;
	}

	function bang(block:INode):Bool {
		pos++;
		if (at(s, pos) == "[".code) {
			pos++;
			addBracket(block.add(INode.ofText("![")), pos - 1, true);
		} else block.add(INode.ofText("!"));
		return true;
	}

	function closeBracket(block:INode):Bool {
		pos++;
		var start = pos;
		var opener = brackets;
		if (opener == null) {
			block.add(INode.ofText("]"));
			return true;
		}
		if (!opener.active) {
			block.add(INode.ofText("]"));
			brackets = opener.prev;
			return true;
		}
		var href:Null<String> = null, title = "", matched = false;
		var save = pos;
		if (at(s, pos) == "(".code) {
			pos++;
			spnl();
			var d = destination();
			if (d != null) {
				var w = pos;
				spnl();
				var t = pos > w ? linkTitle() : null;
				if (t != null) spnl();
				if (at(s, pos) == ")".code) {
					pos++;
					href = d;
					title = t ?? "";
					matched = true;
				}
			}
			if (!matched) pos = save;
		}
		if (!matched) {
			var beforeLabel = pos;
			var n = label();
			var raw:Null<String> = null;
			if (n > 2) raw = s.substr(beforeLabel, n) else if (!opener.bracketAfter) raw = s.substring(opener.index, start);
			if (n == 0) pos = save;
			if (raw != null) {
				var ref = refs.get(normalize(raw));
				if (ref != null) {
					href = ref.href;
					title = ref.title;
					matched = true;
				}
			}
		}
		if (!matched) {
			brackets = opener.prev;
			pos = start;
			block.add(INode.ofText("]"));
			return true;
		}
		var node = new INode(opener.image ? KImage : KLink);
		node.href = href;
		node.title = title;
		var t = opener.node.next;
		while (Scan.tick() && t != null) {
			var next = t.next;
			t.unlink();
			node.add(t);
			t = next;
		}
		block.add(node);
		emphasis(opener.prevDelim);
		brackets = opener.prev;
		opener.node.unlink();
		// (no links in links: the openers before this one are spent)
		if (!opener.image) {
			var o = brackets;
			while (Scan.tick() && o != null) {
				if (!o.image) o.active = false;
				o = o.prev;
			}
		}
		return true;
	}

	// spaces, at most one line end, spaces
	function spnl() {
		while (Scan.tick() && isSpaceOrTab(at(s, pos)))
			pos++;
		if (at(s, pos) == "\n".code) {
			pos++;
			while (Scan.tick() && isSpaceOrTab(at(s, pos)))
				pos++;
		}
	}

	// a [label]'s length at pos, brackets included (0: none)
	function label():Int {
		if (at(s, pos) != "[".code) return 0;
		var j = pos + 1;
		while (Scan.tick() && j < s.length) {
			var c = s.fastCodeAt(j);
			if (c == "\\".code && j + 1 < s.length) {
				j += 2;
				continue;
			}
			if (c == "[".code) return 0;
			if (c == "]".code) break;
			j++;
			if (j - pos > 1000) return 0;
		}
		if (j >= s.length) return 0;
		var start = pos;
		pos = j + 1;
		return pos - start;
	}

	function destination():Null<String> {
		if (at(s, pos) == "<".code) {
			var j = pos + 1;
			while (Scan.tick() && j < s.length) {
				var c = s.fastCodeAt(j);
				if (c == "\\".code && j + 1 < s.length && isAsciiPunct(s.fastCodeAt(j + 1))) {
					j += 2;
					continue;
				}
				if (c == ">".code) {
					var d = unescape(s.substring(pos + 1, j));
					pos = j + 1;
					return d;
				}
				if (c == "<".code || c == "\n".code) return null;
				j++;
			}
			return null;
		}
		var start = pos, depth = 0;
		while (Scan.tick() && pos < s.length) {
			var c = s.fastCodeAt(pos);
			if (c == "\\".code && pos + 1 < s.length && isAsciiPunct(s.fastCodeAt(pos + 1))) pos += 2;
			else if (c == "(".code) {
				// (the spec lets the nesting be limited: unclosed "[a](" runs stay linear)
				if (++depth > 32) break;
				pos++;
			} else if (c == ")".code) {
				if (depth == 0) break;
				depth--;
				pos++;
			} else if (c <= 32 || c == 127) break;
			else pos++;
		}
		if ((pos == start && at(s, pos) != ")".code) || depth != 0) {
			pos = start;
			return null;
		}
		return unescape(s.substring(start, pos));
	}

	function linkTitle():Null<String> {
		var q = at(s, pos);
		var close = q == "(".code ? ")".code : q;
		if (q != "\"".code && q != "'".code && q != "(".code) return null;
		var j = pos + 1;
		while (Scan.tick() && j < s.length) {
			var c = s.fastCodeAt(j);
			if (c == "\\".code && j + 1 < s.length) {
				j += 2;
				continue;
			}
			if (c == close) {
				var t = unescape(s.substring(pos + 1, j));
				pos = j + 1;
				return t;
			}
			if (q == "(".code && c == "(".code) return null;
			j++;
		}
		return null;
	}

	// a reference definition in text at from: its end (from: none), added to refs unless there already
	public function reference(text:String, from:Int):Int {
		s = text;
		pos = from;
		var n = label();
		if (n == 0 || at(s, pos) != ":".code) return from;
		var raw = s.substr(from, n);
		pos++;
		spnl();
		var href = destination();
		if (href == null) return from;
		var beforeTitle = pos;
		spnl();
		var title:Null<String> = pos != beforeTitle ? linkTitle() : null;
		if (title == null) pos = beforeTitle;
		if (!lineEnd()) {
			if (title == null) return from;
			// (a title not at the line's end: the definition without it, if the destination is)
			title = null;
			pos = beforeTitle;
			if (!lineEnd()) return from;
		}
		var key = normalize(raw);
		if (key == "") return from;
		if (!refs.exists(key)) refs.set(key, {href: href, title: title ?? ""});
		return pos;
	}

	function lineEnd():Bool {
		var j = pos;
		while (Scan.tick() && isSpaceOrTab(at(s, j)))
			j++;
		var c = at(s, j);
		if (c != -1 && c != "\n".code) return false;
		pos = c == -1 ? j : j + 1;
		return true;
	}

	// a label's key: inside its brackets, whitespace collapsed, case folded
	public static function normalize(raw:String):String {
		var inner = raw.substring(1, raw.length - 1).trim();
		var out = new StringBuf(), space = false;
		for (i in 0...inner.length) {
			Scan.tick();
			var c = inner.fastCodeAt(i);
			if (c == 32 || c == 9 || c == 10 || c == 13) space = true else {
				if (space) out.add(" ");
				space = false;
				out.addChar(c);
			}
		}
		// (ß folds to ss, as Unicode's case folding has it)
		return out.toString().toLowerCase().toUpperCase().replace("ẞ", "SS").replace("ß", "SS");
	}

	// --- autolinks, HTML, entities

	function autolink(block:INode):Bool {
		var j = pos + 1;
		// <scheme:...>
		if (isAlpha(at(s, j))) {
			var k = j + 1;
			while (Scan.tick() && (isAlnum(at(s, k)) || at(s, k) == "+".code || at(s, k) == ".".code || at(s, k) == "-".code))
				k++;
			if (k - j >= 2 && k - j <= 32 && at(s, k) == ":".code) {
				k++;
				while (Scan.tick() && k < s.length) {
					var c = s.fastCodeAt(k);
					if (c <= 32 || c == "<".code || c == ">".code) break;
					k++;
				}
				if (at(s, k) == ">".code) {
					var url = s.substring(j, k);
					block.add(INode.auto(url, url));
					pos = k + 1;
					return true;
				}
			}
		}
		// <me@example.com>
		var k = j;
		while (Scan.tick() && k < s.length && isEmailLocal(s.fastCodeAt(k)))
			k++;
		if (k == j || at(s, k) != "@".code) return false;
		k++;
		var labels = 0;
		while (true) {
			Scan.tick();
			var l = k;
			while (Scan.tick() && (isAlnum(at(s, k)) || at(s, k) == "-".code))
				k++;
			if (k == l || k - l > 63 || at(s, l) == "-".code || at(s, k - 1) == "-".code) return false;
			labels++;
			if (at(s, k) == ".".code) k++ else break;
		}
		if (at(s, k) != ">".code) return false;
		var address = s.substring(j, k);
		block.add(INode.auto("mailto:" + address, address));
		pos = k + 1;
		return true;
	}

	static inline function isEmailLocal(c:Int):Bool
		return isAlnum(c) || ".!#$%&'*+/=?^_`{|}~-".indexOf(String.fromCharCode(c)) >= 0;

	function html(block:INode):Bool {
		var end = htmlEnd();
		if (end < 0) return false;
		var node = new INode(KHtml);
		node.text = s.substring(pos, end);
		block.add(node);
		pos = end;
		return true;
	}

	function htmlEnd():Int {
		var c = at(s, pos + 1);
		if (isAlpha(c)) return openTag(s, pos);
		if (c == "/".code) return closeTag(s, pos);
		if (c == "?".code) return noPi ? -1 : find("?>", pos + 2, () -> noPi = true);
		if (c != "!".code) return -1;
		if (s.substr(pos + 2, 2) == "--") {
			// (<!--> and <!---> are comments too)
			if (at(s, pos + 4) == ">".code) return pos + 5;
			if (s.substr(pos + 4, 2) == "->") return pos + 6;
			return noComment ? -1 : find("-->", pos + 4, () -> noComment = true);
		}
		if (s.substr(pos + 2, 7) == "[CDATA[") return noCdata ? -1 : find("]]>", pos + 9, () -> noCdata = true);
		if (isAlpha(at(s, pos + 2))) return noDecl ? -1 : find(">", pos + 2, () -> noDecl = true);
		return -1;
	}

	function find(close:String, from:Int, none:Void->Void):Int {
		var i = s.indexOf(close, from);
		if (i < 0) {
			none();
			return -1;
		}
		return i + close.length;
	}

	function entityAt(block:INode):Bool {
		var out = new StringBuf();
		var end = entity(s, pos, out);
		if (end < 0) return false;
		block.add(INode.ofText(out.toString()));
		pos = end;
		return true;
	}

	// --- the nodes into the document's inlines

	// (nested deeper than MAX_NESTING: its text, so nothing that walks the tree runs out of stack)
	function convert(n:INode, inLink:Bool, depth:Int):Array<Inline> {
		var out:Array<Inline> = [];
		if (depth > Markdown.MAX_NESTING) {
			out.push(Text(flat(n)));
			return out;
		}
		var text = new StringBuf(), pending = false;
		inline function flush() {
			if (pending) {
				var t = text.toString();
				if (inLink) out.push(Text(t)) else Autolinks.split(t, out);
				text = new StringBuf();
				pending = false;
			}
		}
		var c = n.first;
		while (Scan.tick() && c != null) {
			switch c.kind {
				case KText:
					if (c.text != "") {
						text.add(c.text);
						pending = true;
					}
				case kind:
					flush();
					out.push(switch kind {
						case KEmph: Emphasis(convert(c, inLink, depth + 1));
						case KStrong: Strong(convert(c, inLink, depth + 1));
						case KStrike: Strike(convert(c, inLink, depth + 1));
						case KCode: CodeSpan(c.text);
						case KLink: Link(c.href, c.title, convert(c, true, depth + 1));
						case KImage: Image(c.href, Markdown.plain(convert(c, true, depth + 1)), c.title);
						case KAuto: Autolink(c.href, c.text);
						case KSoft: SoftBreak;
						case KHard: HardBreak;
						case _: Inline.Html(c.text);
					});
			}
			c = c.next;
		}
		flush();
		return out;
	}

	static function flat(n:INode):String {
		var out = new StringBuf(), stack = [n.first];
		while (Scan.tick() && stack.length > 0) {
			var c = stack.pop();
			if (c == null) continue;
			stack.push(c.next);
			if (c.first != null) stack.push(c.first) else out.add(c.kind == KSoft || c.kind == KHard ? " " : c.text);
		}
		return out.toString();
	}
}

private enum abstract IKind(Int) {
	var KRoot;
	var KText;
	var KEmph;
	var KStrong;
	var KStrike;
	var KCode;
	var KLink;
	var KImage;
	var KAuto;
	var KSoft;
	var KHard;
	var KHtml;
}

// (an inline being parsed: a node of a doubly linked tree, as emphasis and links move runs of them)
private class INode {
	public final kind:IKind;
	public var text = "";
	public var href = "";
	public var title = "";
	public var parent:Null<INode> = null;
	public var prev:Null<INode> = null;
	public var next:Null<INode> = null;
	public var first:Null<INode> = null;
	public var last:Null<INode> = null;

	public function new(kind:IKind)
		this.kind = kind;

	public static function ofText(t:String):INode {
		var n = new INode(KText);
		n.text = t;
		return n;
	}

	public static function auto(href:String, t:String):INode {
		var n = new INode(KAuto);
		n.href = href;
		n.text = t;
		return n;
	}

	public function add(c:INode):INode {
		c.parent = this;
		c.prev = last;
		c.next = null;
		if (last != null) last.next = c else first = c;
		last = c;
		return c;
	}

	public function unlink() {
		if (prev != null) prev.next = next else if (parent != null) parent.first = next;
		if (next != null) next.prev = prev else if (parent != null) parent.last = prev;
		parent = prev = next = null;
	}

	public function insertAfter(c:INode) {
		c.parent = parent;
		c.prev = this;
		c.next = next;
		if (next != null) next.prev = c else if (parent != null) parent.last = c;
		next = c;
	}
}

private class Delim {
	public final c:Int;
	public var num:Int;
	public final orig:Int;
	public final node:INode;
	public final open:Bool;
	public final close:Bool;
	public var prev:Null<Delim> = null;
	public var next:Null<Delim> = null;

	public function new(c, num, node, open, close) {
		this.c = c;
		this.num = num;
		this.orig = num;
		this.node = node;
		this.open = open;
		this.close = close;
	}
}

private class Bracket {
	public final node:INode;
	public final index:Int;
	public final image:Bool;
	public var active = true;
	public var bracketAfter = false;
	public var prev:Null<Bracket> = null;
	public var prevDelim:Null<Delim> = null;

	public function new(node, index, image) {
		this.node = node;
		this.index = index;
		this.image = image;
	}
}
