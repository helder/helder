package helder.dom;

import helder.test.Gen;
import helder.test.Test;

using StringTools;

// helder.dom's XML parser: namespaces, references, sections, the XHTML
// entities, templates, well-formedness errors (its trees against expat's
// are tests/dom's XmlCheck); then properties: a generated tree written as
// XML parses back to that tree, and mutated documents never throw.
function tests() {
	describe("parseXml", () -> {
		test("namespaces", () -> {
			var doc = Dom.parseXml('<a xmlns="urn:a" xmlns:b="urn:b"><b:c b:d="1" e="2"/><f xmlns=""/></a>');
			var a = doc.documentElement;
			equals([a.namespaceURI, a.localName, a.prefix], ["urn:a", "a", null]);
			var c = a.firstElementChild;
			equals([c.namespaceURI, c.prefix, c.localName, c.tagName], ["urn:b", "b", "c", "b:c"]);
			equals(c.getAttributeNS("urn:b", "d"), "1");
			equals(c.getAttributeNode("e").namespaceURI, null);
			equals(a.lastElementChild.namespaceURI, null);
			equals(a.getAttributeNodeNS(Namespaces.XMLNS, "b").value, "urn:b");
			equals(c.lookupNamespaceURI("b"), "urn:b");
			equals(doc.contentType, "application/xml");
		});
		test("references, sections, instructions", () -> {
			var doc = Dom.parseXml('<?xml version="1.0"?><?style href="a.css"?><!DOCTYPE a [<!ENTITY e "x &#38;#38; y"><!ENTITY m "<b>&e;</b>">]><a t="&lt;&e;&#x41;"> &amp;&#169; &e;<![CDATA[<b>]]>&m;<!--c--></a>');
			var a = doc.documentElement;
			equals(a.getAttribute("t"), "<x & yA");
			equals(a.firstChild.nodeValue, " &\u{A9} x & y");
			equals(a.childNodes.item(1).nodeType, Node.CDATA_SECTION_NODE);
			equals((cast a.childNodes.item(1) : CDATASection).data, "<b>");
			equals(a.childNodes.item(2).textContent, "x & y");
			equals(a.lastChild.nodeType, Node.COMMENT_NODE);
			var pi:ProcessingInstruction = cast doc.firstChild;
			equals([pi.target, pi.getAttribute("href")], ["style", "a.css"]);
			equals(doc.doctype.name, "a");
		});
		test("XHTML: its entities, a template's contents", () -> {
			var doc = Dom.parseXml('<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">'
				+ '<html xmlns="http://www.w3.org/1999/xhtml"><body><p>&nbsp;&mdash;</p><template><i>x</i></template></body></html>');
			equals(doc.getElementsByTagName("p").item(0).textContent, "\u{A0}\u{2014}");
			var t:HTMLTemplateElement = cast doc.getElementsByTagName("template").item(0);
			equals(t.firstChild, null);
			equals(t.content.firstElementChild.localName, "i");
			equals(doc.body.localName, "body");
		});
		test("line ends and attribute white space", () -> {
			var doc = Dom.parseXml('<a b="x\ty\r\nz&#10;w">1\r\n2\r3</a>');
			equals(doc.documentElement.getAttribute("b"), "x y z\nw");
			equals(doc.documentElement.textContent, "1\n2\n3");
		});
		test("source offsets", () -> {
			var src = '<a><b x="1">t</b><!--c--></a>';
			var b = Dom.parseXml(src).documentElement.firstElementChild;
			equals(src.substring(b.start, b.end), '<b x="1">t</b>');
			equals(src.substring(b.firstChild.start, b.firstChild.end), "t");
		});
		test("well-formedness errors stop the parse", () -> {
			function code(xml:String):String {
				var errors = [];
				Dom.parseXml(xml, errors);
				return errors.length == 0 ? "" : errors[0].code;
			}
			equals(code("<a><b></a>"), "mismatched-end-tag");
			equals(code("<a><p:b/></a>"), "unbound-prefix");
			equals(code('<a x="1" x="2"/>'), "duplicate-attribute");
			equals(code("<a>&nbsp;</a>"), "undefined-entity");
			equals(code('<!DOCTYPE a [<!ENTITY e "&e;">]><a>&e;</a>'), "recursive-entity");
			equals(code("<a/>x"), "content-after-root");
			equals(code("<a>]]></a>"), "cdata-end-in-text");
			equals(code("<a><!-- -- --></a>"), "double-hyphen-in-comment");
			equals(code(""), "missing-root");
			var doc = Dom.parseXml("<a><b>kept</b><c></a>");
			equals(doc.documentElement.firstElementChild.textContent, "kept");
		});
		test("an entity's expansions are bounded", () -> {
			var lol = '<!DOCTYPE a [<!ENTITY a "aaaaaaaaaa">' + [for (k in 1...8) '<!ENTITY ${String.fromCharCode(97 + k)} "${[for (_ in 0...10) "&" + String.fromCharCode(96 + k) + ";"].join("")}">'].join("")
				+ ']><a>&h;</a>';
			var errors = [];
			Dom.parseXml(lol, errors);
			equals(errors[0].code, "entity-expansion-limit");
		});
	});
	describe("properties", () -> {
		test("a generated tree written as XML parses back to it", () -> property(TREE, xml -> {
			var errors = [];
			var doc = Dom.parseXml(xml, errors);
			equals(errors, []);
			equals(write(doc.documentElement), xml);
		}, {cases: 300}));
		test("mutated documents never throw", () -> property(mutated(SEEDS), b -> {
			var text = [for (i in 0...b.length) String.fromCharCode(b.get(i))].join("");
			Dom.parseXml(text, []);
		}, {cases: 200, seconds: 5, limit: 10, memory: 256}));
	});
}

// (an element tree as this writer writes it: the parser must give the same back)
private function write(e:Element):String {
	var b = new StringBuf();
	b.add("<" + e.tagName);
	for (a in e.attributes)
		b.add(' ${a.name}="${escape(a.value, true)}"');
	if (e.firstChild == null) {
		b.add("/>");
		return b.toString();
	}
	b.add(">");
	var c = e.firstChild;
	while (c != null) {
		switch c.nodeType {
			case Node.ELEMENT_NODE: b.add(write(cast c));
			case Node.TEXT_NODE: b.add(escape((cast c : Text).data, false));
			case Node.CDATA_SECTION_NODE: b.add("<![CDATA[" + (cast c : Text).data + "]]>");
			case Node.COMMENT_NODE: b.add("<!--" + (cast c : Comment).data + "-->");
			case Node.PROCESSING_INSTRUCTION_NODE: b.add("<?" + (cast c : ProcessingInstruction).target + " " + (cast c : ProcessingInstruction).data + "?>");
			case _:
		}
		c = c.nextSibling;
	}
	b.add("</" + e.tagName + ">");
	return b.toString();
}

private function escape(s:String, attribute:Bool):String {
	var r = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;");
	return attribute ? r.replace("\"", "&quot;").replace("\t", "&#9;").replace("\n", "&#10;") : r;
}

private final NAME:Gen<String> = pick(["a", "b", "x-y", "p:q", "r:s", "\u{E9}t\u{E9}", "_u", "v.w"]);
private final TEXT:Gen<String> = pick(["", "text", " ", "a < b", "&", "\"q\"", "\u{1F600}", "x\ny", "]]", ">"]);

// (an element tree with namespaces declared for its prefixes, written by write)
private final TREE:Gen<String> = c -> {
	function element(depth:Int):String {
		var n = c.draw(NAME);
		var attrs = new Map<String, Bool>();
		var b = new StringBuf();
		b.add("<" + n);
		b.add(' xmlns:p="urn:p" xmlns:r="urn:r"');
		for (_ in 0...c.draw(int(0, 3))) {
			var a = c.draw(pick(["id", "class", "p:z", "r:z", "t"]));
			if (attrs.exists(a)) continue;
			attrs.set(a, true);
			b.add(' $a="${escape(c.draw(TEXT), true)}"');
		}
		var kids = depth < 3 ? c.draw(int(0, 3)) : 0;
		if (kids == 0) {
			b.add("/>");
			return b.toString();
		}
		b.add(">");
		var last = "";
		for (_ in 0...kids) {
			var kind = c.draw(int(0, 4));
			// (no two texts in a row: they would be one node)
			if (kind == 1 && last == "text") kind = 0;
			switch kind {
				case 0: b.add(element(depth + 1));
				case 1:
					var t = c.draw(TEXT);
					if (t == "") continue;
					b.add(escape(t, false));
				case 2: b.add("<![CDATA[" + c.draw(TEXT).replace("]]", "]") + "]]>");
				case 3: b.add("<!--" + c.draw(TEXT).replace("-", "") + "-->");
				// (the white space after a target is all its: data starts after it)
				case _: b.add("<?pi " + StringTools.ltrim(c.draw(TEXT).replace("?", "")) + "?>");
			}
			last = kind == 1 ? "text" : "";
		}
		b.add("</" + n + ">");
		return b.toString();
	}
	element(0);
};

private final SEEDS:Map<String, haxe.io.Bytes> = [
	"xhtml" => haxe.io.Bytes.ofString('<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "x.dtd"><html xmlns="http://www.w3.org/1999/xhtml"><head><title>t &amp; &nbsp;</title><style><![CDATA[p{}]]></style></head><body><p class="a">x<svg xmlns="http://www.w3.org/2000/svg"><circle r="1"/></svg></p></body></html>'),
	"subset" => haxe.io.Bytes.ofString('<?xml version="1.0"?><!DOCTYPE a [<!ENTITY e "x"><!ENTITY m "<b>&e;</b>"><!ATTLIST a b CDATA "d">]><a xmlns:p="urn:p" p:b="&e;">&m;<?pi d?><!--c--></a>')
];
