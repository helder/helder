import helder.dom.*;

using StringTools;

// A tree in html5lib's format (the tree construction tests'): "| " and two
// spaces a level, attributes sorted, namespaces as svg and math.
class Dump {
	// the tree in the tests' format: "| " and two spaces a level
	public static function tree(root:Node):String {
		var out = [];
		function walk(n:Node, depth:Int) {
			var pad = "| " + "".lpad(" ", depth * 2);
			switch n.nodeType {
				case Node.ELEMENT_NODE:
					var e:Element = cast n;
					var ns = switch e.namespaceURI {
						case Namespaces.SVG: "svg ";
						case Namespaces.MATHML: "math ";
						case _: "";
					}
					out.push(pad + "<" + ns + e.localName + ">");
					var attrs = [];
					for (a in e.attributes) {
						var name = switch a.namespaceURI {
							case Namespaces.XLINK: "xlink " + a.localName;
							case Namespaces.XML: "xml " + a.localName;
							case Namespaces.XMLNS: "xmlns " + a.localName;
							case _: a.localName;
						}
						attrs.push(name + "=\"" + a.value + "\"");
					}
					attrs.sort(Reflect.compare);
					for (a in attrs)
						out.push(pad + "  " + a);
					if (e is HTMLTemplateElement) {
						out.push(pad + "  content");
						var c = (cast e : HTMLTemplateElement).content.firstChild;
						while (c != null) {
							walk(c, depth + 2);
							c = c.nextSibling;
						}
					}
				case Node.TEXT_NODE:
					out.push(pad + "\"" + (cast n : Text).data + "\"");
				case Node.COMMENT_NODE:
					out.push(pad + "<!-- " + (cast n : Comment).data + " -->");
				case Node.PROCESSING_INSTRUCTION_NODE:
					var pi:ProcessingInstruction = cast n;
					out.push(pad + "<?" + pi.target + " " + pi.data + "?>");
				case Node.DOCUMENT_TYPE_NODE:
					var d:DocumentType = cast n;
					out.push(pad + "<!DOCTYPE " + d.name + (d.publicId != "" || d.systemId != "" ? ' "${d.publicId}" "${d.systemId}"' : "") + ">");
				case _:
			}
			var c = n.firstChild;
			while (c != null) {
				walk(c, depth + 1);
				c = c.nextSibling;
			}
		}
		var c = root.firstChild;
		while (c != null) {
			walk(c, 0);
			c = c.nextSibling;
		}
		return out.join("\n");
	}
}
