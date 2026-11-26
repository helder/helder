package helder.dom;

using StringTools;

// The HTML fragment serialization algorithm (HTML 13.3), without recursion:
// a parser's tree can be as deep as its input is long.
@:noCompletion class Serializer {
	// a node's children (innerHTML; a template's: its contents')
	public static function children(node:Node):String {
		if (node.nodeType == Node.ELEMENT_NODE && isVoid(cast node)) return "";
		var buf = new StringBuf();
		write(buf, first(node), false);
		return buf.toString();
	}

	// the node with its own markup (outerHTML; a document or fragment: its children)
	public static function node(node:Node):String {
		if (node.nodeType == Node.DOCUMENT_NODE || node.nodeType == Node.DOCUMENT_FRAGMENT_NODE) return children(node);
		var buf = new StringBuf();
		write(buf, node, true);
		return buf.toString();
	}

	static inline function first(n:Node):Null<Node>
		return n.nodeType == Node.ELEMENT_NODE && (cast n : Element).isHTML(Tags.TEMPLATE) ? (cast n : HTMLTemplateElement).content.firstChild : n.firstChild;

	static function isVoid(e:Element):Bool
		return e.ns == Element.HTML && switch e.tag {
			case Tags.AREA | Tags.BASE | Tags.BR | Tags.COL | Tags.EMBED | Tags.HR | Tags.IMG | Tags.INPUT | Tags.LINK | Tags.META | Tags.SOURCE | Tags.TRACK
				| Tags.WBR | Tags.BASEFONT | Tags.BGSOUND | Tags.FRAME | Tags.KEYGEN | Tags.PARAM: true;
			case _: false;
		}

	static function tagName(e:Element):String
		return e.ns == Element.OTHER ? e.qualifiedName() : e.localName;

	static function write(buf:StringBuf, from:Null<Node>, single:Bool) {
		var open:Array<Element> = [];
		var n = from;
		while (n != null) {
			var into:Null<Node> = null;
			switch n.nodeType {
				case Node.ELEMENT_NODE:
					var e:Element = cast n;
					var name = tagName(e);
					buf.add("<");
					buf.add(name);
					for (a in e.attrList()) {
						buf.add(" ");
						buf.add(attrName(a));
						buf.add("=\"");
						buf.add(escape(a.data, true));
						buf.add("\"");
					}
					buf.add(">");
					if (!isVoid(e)) {
						into = first(e);
						if (into == null) {
							buf.add("</");
							buf.add(name);
							buf.add(">");
						} else {
							open.push(e);
							n = into;
							continue;
						}
					}
				case Node.TEXT_NODE | Node.CDATA_SECTION_NODE:
					var parent = n.parentNode;
					var raw = parent != null && parent.nodeType == Node.ELEMENT_NODE && (cast parent : Element).ns == Element.HTML && switch (cast parent : Element).tag {
						case Tags.STYLE | Tags.SCRIPT | Tags.XMP | Tags.IFRAME | Tags.NOEMBED | Tags.NOFRAMES | Tags.PLAINTEXT: true;
						case _: false;
					}
					buf.add(raw ? (cast n : Text).data : escape((cast n : Text).data, false));
				case Node.COMMENT_NODE:
					buf.add("<!--");
					buf.add((cast n : Comment).data);
					buf.add("-->");
				case Node.PROCESSING_INSTRUCTION_NODE:
					buf.add("<?");
					buf.add((cast n : ProcessingInstruction).target);
					buf.add(" ");
					buf.add((cast n : ProcessingInstruction).data);
					buf.add("?>");
				case Node.DOCUMENT_TYPE_NODE:
					buf.add("<!DOCTYPE ");
					buf.add((cast n : DocumentType).name);
					buf.add(">");
				case _:
			}
			// the next node: a sibling, else the open elements' ends up to one with a sibling
			while (true) {
				if (open.length == 0) {
					n = single ? null : n.nextSibling;
					break;
				}
				if (n.nextSibling != null) {
					n = n.nextSibling;
					break;
				}
				var e = open.pop();
				buf.add("</");
				buf.add(tagName(e));
				buf.add(">");
				n = e;
			}
		}
	}

	static function attrName(a:Attr):String
		return switch a.namespaceURI {
			case null: a.localName;
			case Namespaces.XML: "xml:" + a.localName;
			case Namespaces.XMLNS: a.localName == "xmlns" ? "xmlns" : "xmlns:" + a.localName;
			case Namespaces.XLINK: "xlink:" + a.localName;
			case _: a.qualifiedName();
		}

	public static function escape(s:String, attribute:Bool):String {
		var i = 0, n = s.length;
		while (i < n) {
			var c = s.fastCodeAt(i);
			if (c == "&".code || c == "<".code || c == ">".code || c == 0xA0 || attribute && c == "\"".code) break;
			i++;
		}
		if (i == n) return s;
		var buf = new StringBuf();
		buf.addSub(s, 0, i);
		while (i < n) {
			var c = s.fastCodeAt(i++);
			switch c {
				case "&".code: buf.add("&amp;");
				case "<".code: buf.add("&lt;");
				case ">".code: buf.add("&gt;");
				case 0xA0: buf.add("&nbsp;");
				case "\"".code if (attribute): buf.add("&quot;");
				case _: buf.addChar(c);
			}
		}
		return buf.toString();
	}
}
