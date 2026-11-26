package helder.dom;

import helder.test.Gen;
import helder.test.Test;

using StringTools;

// helder.dom: the parser's documents and fragments (its conformance is
// tests/dom's, natively), the DOM's algorithms and their errors, the
// serialization, then properties: generated markup parsed, serialized and
// parsed again is the same tree; mutated pages parse without throwing,
// each in bounded time.
function tests() {
	describe("parse", () -> {
		test("a document", () -> {
			var doc = Dom.parse("<!doctype html><title> A  &amp;\nB </title><p class=x>Hi");
			equals(doc.mode, NoQuirks);
			equals(doc.compatMode, "CSS1Compat");
			equals(doc.doctype.name, "html");
			equals(doc.title, "A & B");
			equals(doc.head.firstElementChild.localName, "title");
			equals(doc.body.firstElementChild.className, "x");
			equals(doc.documentElement.ownerDocument, doc);
			equals(doc.ownerDocument, null);
			equals(doc.contentType, "text/html");
		});
		test("modes from the doctype", () -> {
			equals(Dom.parse("<p>").mode, Quirks);
			equals(Dom.parse('<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">').mode, Quirks);
			equals(Dom.parse('<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">').mode, LimitedQuirks);
			equals(Dom.parse("<!doctype html>").mode, NoQuirks);
		});
		test("source offsets", () -> {
			var src = "<p id=a>one <b>two</b></p><!--c-->";
			var doc = Dom.parse(src);
			var p = doc.getElementById("a");
			equals(src.substring(p.start, p.end), "<p id=a>one <b>two</b></p>");
			var b = p.lastElementChild;
			equals(src.substring(b.start, b.end), "<b>two</b>");
			var text = p.firstChild;
			equals(src.substring(text.start, text.end), "one ");
			var comment = doc.body.lastChild;
			equals(src.substring(comment.start, comment.end), "<!--c-->");
			equals(doc.createElement("div").start, -1);
		});
		test("errors when asked for", () -> {
			var errors = [];
			Dom.parse("<!doctype html><p a=1 a=2>&#0;</x>", errors);
			equals([for (e in errors) e.code].slice(0, 2), ["duplicate-attribute", "null-character-reference"]);
			equals(errors[0].offset, 23);
		});
		test("fragments in their context", () -> {
			var doc = Dom.parse("");
			var td = Dom.parseFragment("<td>a<td>b", doc.createElement("tr"));
			equals([for (c in td.children) c.localName], ["td", "td"]);
			equals(Dom.parseFragment("<option>a<option>b", doc.createElement("select")).childElementCount, 2);
			var svg = Dom.parseFragment("<circle/><foreignObject><p>x</p></foreignObject>", doc.createElementNS(Namespaces.SVG, "svg"));
			equals(svg.firstElementChild.namespaceURI, Namespaces.SVG);
			equals(svg.lastElementChild.firstElementChild.namespaceURI, Namespaces.HTML);
			equals(Dom.parseFragment("<b>x</b>", doc.createElement("title")).textContent, "<b>x</b>");
			equals(td.ownerDocument, doc);
		});
		test("foreign content's names", () -> {
			var doc = Dom.parse("<svg viewbox='0 0 1 1'><lineargradient xlink:href='#a'/></svg><math definitionurl=x></math>");
			var svg = doc.body.firstElementChild;
			equals(svg.getAttribute("viewBox"), "0 0 1 1");
			var g = svg.firstElementChild;
			equals(g.localName, "linearGradient");
			equals(g.getAttributeNS(Namespaces.XLINK, "href"), "#a");
			equals(g.attributes.item(0).prefix, "xlink");
			equals(doc.body.lastElementChild.getAttribute("definitionURL"), "x");
		});
		test("template contents", () -> {
			var doc = Dom.parse("<template id=t><td>a</td></template>");
			var t:HTMLTemplateElement = cast doc.getElementById("t");
			equals(t.firstChild, null);
			equals(t.content.firstElementChild.localName, "td");
			notEquals(t.content.ownerDocument, doc);
			equals(t.innerHTML, "<td>a</td>");
		});
		test("a template patches its markers' range", () -> {
			var doc = Dom.parse("<div id=d><?start name='a'?>old<?end?></div><template for=a><b>new</b></template>");
			equals(doc.getElementById("d").innerHTML, "<b>new</b>");
			var doc = Dom.parse("<p id=p>x<?marker name='m'?>y</p><template for=m>z</template>");
			equals(doc.getElementById("p").textContent, "xzy");
		});
		test("a select's selectedcontent shows its selected option", () -> {
			var doc = Dom.parse("<select><button><selectedcontent></selectedcontent></button><option>A<option selected>B</select>");
			var shown = doc.getElementsByTagName("selectedcontent").item(0);
			equals(shown.textContent, "B");
			doc.getElementsByTagName("option").item(0).setAttribute("selected", "");
			equals(shown.textContent, "A");
		});
		test("processing instructions' attributes", () -> {
			var pi:ProcessingInstruction = cast Dom.parse("<?start name='a&amp;b' n=\"2\"?>").firstChild;
			equals(pi.target, "start");
			equals(pi.getAttribute("name"), "a&b");
			equals(pi.getAttributeNames(), ["name", "n"]);
			pi.setAttribute("x", "<");
			equals(pi.data, "name=\"a&amp;b\" n=\"2\" x=\"&lt;\"");
			pi.data = "broken=";
			equals(pi.hasAttributes(), false);
		});
	});
	describe("tree", () -> {
		test("insert, remove, replace", () -> {
			var doc = Dom.parse("");
			var body = doc.body;
			var a = body.appendChild(doc.createElement("a"));
			var b = body.insertBefore(doc.createElement("b"), a);
			equals([for (c in body.childNodes) c.nodeName], ["B", "A"]);
			body.replaceChild(doc.createTextNode("t"), b);
			equals(body.firstChild.nodeType, Node.TEXT_NODE);
			body.removeChild(a);
			equals(a.parentNode, null);
			equals(body.childNodes.length, 1);
		});
		test("the spec's errors", () -> {
			var doc = Dom.parse("");
			var e:DOMException = throws(() -> doc.appendChild(doc.createElement("x")));
			equals(e.name, "HierarchyRequestError");
			e = throws(() -> doc.appendChild(doc.createTextNode("x")));
			equals(e.name, "HierarchyRequestError");
			e = throws(() -> doc.body.appendChild(doc.documentElement));
			equals(e.name, "HierarchyRequestError");
			e = throws(() -> doc.body.insertBefore(doc.createElement("i"), doc.head));
			equals(e.name, "NotFoundError");
			e = throws(() -> doc.body.removeChild(doc.head));
			equals(e.name, "NotFoundError");
			e = throws(() -> doc.createElement("1a"));
			equals(e.name, "InvalidCharacterError");
			e = throws(() -> doc.createElementNS(null, "x:y"));
			equals(e.name, "NamespaceError");
			e = throws(() -> doc.createCDATASection("x"));
			equals(e.name, "NotSupportedError");
			e = throws(() -> (cast doc.createTextNode("ab") : Text).splitText(3));
			equals(e.name, "IndexSizeError");
			var t:HTMLTemplateElement = cast doc.createElement("template");
			e = throws(() -> t.content.appendChild(t));
			equals(e.name, "HierarchyRequestError");
			equals(doc.createElement(":x").localName, ":x");
		});
		test("a fragment's children move", () -> {
			var doc = Dom.parse("");
			var f = doc.createDocumentFragment();
			f.append("a", doc.createElement("b"), "c");
			doc.body.appendChild(f);
			equals(f.childNodes.length, 0);
			equals(doc.body.innerHTML, "a<b></b>c");
		});
		test("adoption into another document", () -> {
			var a = Dom.parse("<p id=x title=t><template><i></i></template>"), b = Dom.parse("");
			var p = a.getElementById("x");
			b.body.appendChild(p);
			equals(p.ownerDocument, b);
			equals(p.getAttributeNode("title").ownerDocument, b);
			var t:HTMLTemplateElement = cast p.firstElementChild;
			notEquals(t.content.ownerDocument, a);
			notEquals(t.content.ownerDocument, b);
			equals(a.getElementById("x"), null);
		});
		test("clones", () -> {
			var doc = Dom.parse("<div id=a class=c><template><b>x</b></template>text</div>");
			var div = doc.getElementById("a");
			var shallow:Element = cast div.cloneNode();
			equals(shallow.childNodes.length, 0);
			equals(shallow.className, "c");
			var deep:Element = cast div.cloneNode(true);
			equals(deep.outerHTML, div.outerHTML);
			assert(deep.isEqualNode(div));
			assert(!deep.isSameNode(div));
			var other = Dom.parse("");
			var imported = other.importNode(div, true);
			equals(imported.ownerDocument, other);
			equals(div.ownerDocument, doc);
		});
		test("text", () -> {
			var doc = Dom.parse("<p id=p>a<b>b</b>c");
			var p = doc.getElementById("p");
			equals(p.textContent, "abc");
			p.appendChild(doc.createTextNode(""));
			p.appendChild(doc.createTextNode("d"));
			p.removeChild(p.childNodes.item(1));
			equals(p.childNodes.length, 4);
			p.normalize();
			equals(p.childNodes.length, 1);
			equals(p.textContent, "acd");
			var t:Text = cast p.firstChild;
			var rest = t.splitText(1);
			equals([t.data, rest.data, rest.wholeText], ["a", "cd", "acd"]);
			p.textContent = "x";
			equals(p.innerHTML, "x");
			t.appendData("!");
			t.insertData(0, "<");
			equals(t.data, "<a!");
		});
		test("positions", () -> {
			var doc = Dom.parse("<p><a></a><b><i></i></b></p>");
			var a = doc.getElementsByTagName("a").item(0), i = doc.getElementsByTagName("i").item(0), b = i.parentElement;
			equals(a.compareDocumentPosition(i), Node.DOCUMENT_POSITION_FOLLOWING);
			equals(i.compareDocumentPosition(a), Node.DOCUMENT_POSITION_PRECEDING);
			equals(i.compareDocumentPosition(b), Node.DOCUMENT_POSITION_CONTAINS | Node.DOCUMENT_POSITION_PRECEDING);
			equals(b.compareDocumentPosition(i), Node.DOCUMENT_POSITION_CONTAINED_BY | Node.DOCUMENT_POSITION_FOLLOWING);
			assert(doc.createElement("x").compareDocumentPosition(a) & Node.DOCUMENT_POSITION_DISCONNECTED != 0);
			assert(b.contains(i) && !i.contains(b) && b.contains(b));
		});
		test("ParentNode and ChildNode", () -> {
			var doc = Dom.parse("<p id=p><b></b>");
			var p = doc.getElementById("p"), b = p.firstElementChild;
			b.before("1");
			b.after(doc.createElement("i"), "2");
			p.prepend("0");
			equals(p.innerHTML, "01<b></b><i></i>2");
			b.replaceWith("x");
			equals(p.innerHTML, "01x<i></i>2");
			p.lastElementChild.remove();
			p.replaceChildren("y", doc.createElement("u"));
			equals(p.innerHTML, "y<u></u>");
			p.moveBefore(p.lastChild, p.firstChild);
			equals(p.innerHTML, "<u></u>y");
			equals(p.childElementCount, 1);
		});
	});
	describe("attributes", () -> {
		test("names and namespaces", () -> {
			var doc = Dom.parse("");
			var e = doc.createElement("div");
			e.setAttribute("DATA-X", "1");
			equals(e.getAttributeNames(), ["data-x"]);
			equals(e.getAttribute("Data-X"), "1");
			e.setAttributeNS(Namespaces.XLINK, "xlink:href", "#a");
			equals(e.getAttributeNS(Namespaces.XLINK, "href"), "#a");
			equals(e.attributes.length, 2);
			assert(e.toggleAttribute("hidden"));
			assert(!e.toggleAttribute("hidden"));
			assert(e.toggleAttribute("hidden", true));
			e.removeAttribute("data-x");
			equals(e.hasAttribute("data-x"), false);
			var a = doc.createAttribute("title");
			a.value = "t";
			equals(e.setAttributeNode(a), null);
			equals(e.getAttribute("title"), "t");
			a.value = "u";
			equals(e.getAttribute("title"), "u");
			var other = doc.createElement("p");
			var err:DOMException = throws(() -> other.setAttributeNode(a));
			equals(err.name, "InUseAttributeError");
			e.removeAttributeNode(a);
			equals(a.ownerElement, null);
			err = throws(() -> e.setAttributeNS(null, "xmlns", "x"));
			equals(err.name, "NamespaceError");
		});
		test("classList, id, className", () -> {
			var doc = Dom.parse("<p id=p class='a  b a'>");
			var p = doc.getElementById("p");
			equals(p.classList.length, 2);
			p.classList.add("c");
			p.classList.remove("a");
			equals(p.className, "b c");
			assert(!p.classList.toggle("b"));
			assert(p.classList.replace("c", "d"));
			equals(p.className, "d");
			p.id = "q";
			equals(doc.getElementById("q"), p);
			var err:DOMException = throws(() -> p.classList.add("a b"));
			equals(err.name, "InvalidCharacterError");
		});
		test("namespace lookups", () -> {
			var doc = Dom.parse("<svg xmlns:xlink='http://www.w3.org/1999/xlink'><g></g></svg>");
			var g = doc.getElementsByTagName("g").item(0);
			equals(g.lookupNamespaceURI(null), Namespaces.SVG);
			equals(g.lookupNamespaceURI("xlink"), Namespaces.XLINK);
			equals(g.lookupPrefix(Namespaces.XLINK), "xlink");
			assert(g.isDefaultNamespace(Namespaces.SVG));
			equals(doc.body.lookupNamespaceURI("xml"), Namespaces.XML);
		});
	});
	describe("collections", () -> {
		test("live", () -> {
			var doc = Dom.parse("<div class='x y'></div><p class=x></p>");
			var divs = doc.getElementsByTagName("DIV"), xs = doc.getElementsByClassName("x"), kids = doc.body.children, nodes = doc.body.childNodes;
			equals([divs.length, xs.length, kids.length, nodes.length], [1, 2, 2, 2]);
			doc.body.appendChild(doc.createElement("div"));
			doc.body.firstElementChild.className = "";
			equals([divs.length, xs.length, kids.length, nodes.length], [2, 1, 3, 3]);
			equals(doc.getElementsByClassName("x y").length, 0);
			equals(doc.getElementsByTagNameNS(Namespaces.HTML, "p").item(0).localName, "p");
			equals([for (e in kids) e.localName], ["div", "p", "div"]);
			kids.item(1).id = "n";
			equals(kids.namedItem("n"), kids.item(1));
		});
	});
	describe("serialization", () -> {
		test("the fragment serialization algorithm", () -> {
			var doc = Dom.parse("<p title='a\"b&amp;'>x&nbsp;&lt;&gt;&amp;<br><script>a<b</script><style>&amp;</style><svg><path/></svg><!--c--><?p d?>");
			equals(doc.body.innerHTML,
				'<p title="a&quot;b&amp;">x&nbsp;&lt;&gt;&amp;<br><script>a<b</script><style>&amp;</style><svg><path></path></svg><!--c--><?p d?></p>');
			equals(Dom.serialize(Dom.parse("<!doctype html>")), "<!DOCTYPE html><html><head></head><body></body></html>");
			var br = doc.createElement("br");
			br.appendChild(doc.createTextNode("x"));
			equals(br.innerHTML, "");
			equals(br.outerHTML, "<br>");
		});
		test("innerHTML and outerHTML set", () -> {
			var doc = Dom.parse("<div id=d></div>");
			var d = doc.getElementById("d");
			d.innerHTML = "<td>no<b>yes";
			equals(d.innerHTML, "no<b>yes</b>");
			d.firstElementChild.outerHTML = "<i>1</i><u>2</u>";
			equals(d.innerHTML, "no<i>1</i><u>2</u>");
			var t:HTMLTemplateElement = cast doc.createElement("template");
			t.innerHTML = "<tr><td>x";
			equals(t.content.firstElementChild.localName, "tr");
		});
	});
	describe("properties", () -> {
		test("generated markup parsed, serialized and parsed again: the same tree", () -> property(MARKUP, html -> {
			var doc = Dom.parse(html);
			// (the one place the spec's serialization leaves a tree it read
			// otherwise: a pre, textarea or listing's first newline, which the
			// parser drops and the serializer does not write back)
			assume(!leadingNewline(doc));
			var again = Dom.parse(Dom.serialize(doc));
			equals(tree(again), tree(doc));
		}, {cases: 300}));
		test("mutated pages parse without throwing, in bounded time", () -> property(mutated(pages()), b -> {
			// (a byte a character: a mutated page is seldom UTF-8)
			var html = [for (i in 0...b.length) String.fromCharCode(b.get(i))].join("");
			var t0 = haxe.Timer.stamp();
			var doc = Dom.parse(html);
			Dom.serialize(doc);
			var ms = (haxe.Timer.stamp() - t0) * 1000;
			assert(ms < 1000, '${Math.round(ms)} ms for ${html.length} characters');
		}, {cases: 100, seconds: 5}));
	});
}

// the tree as text: each node's kind, name and data, its attributes, by depth
private function tree(root:Node):String {
	var out = new StringBuf();
	var n = root.firstChild, depth = 1;
	function walk(n:Node, depth:Int) {
		out.add("".lpad(" ", depth));
		switch n.nodeType {
			case Node.ELEMENT_NODE:
				var e:Element = cast n;
				out.add('<${e.namespaceURI} ${e.localName}');
				for (a in e.attributes)
					out.add(' ${a.namespaceURI}:${a.localName}=${a.value}');
				out.add(">\n");
				if (e is HTMLTemplateElement) {
					var c = (cast e : HTMLTemplateElement).content.firstChild;
					while (c != null) {
						walk(c, depth + 2);
						c = c.nextSibling;
					}
				}
			case _:
				out.add(n.nodeName + " " + n.nodeValue + "\n");
		}
		var c = n.firstChild;
		while (c != null) {
			walk(c, depth + 1);
			c = c.nextSibling;
		}
	}
	while (n != null) {
		walk(n, depth);
		n = n.nextSibling;
	}
	return out.toString();
}

private function leadingNewline(doc:Document):Bool {
	for (name in ["pre", "textarea", "listing"])
		for (e in doc.getElementsByTagName(name))
			if (e.firstChild != null && e.firstChild.nodeType == Node.TEXT_NODE && (cast e.firstChild : Text).data.startsWith("\n")) return true;
	return false;
}

// (well-nested markup of the parser's hard parts: implied end tags,
// tables, lists, selects, raw text, foreign content, templates, comments,
// references, attributes in any case and quoting)
private final TEXT:Gen<String> = pick(["a", " ", "\n", "b c", "&amp;", "&lt;x&gt;", "&nbsp;", "&#x1F600;", "\u{E9}", "<", ">", "&", "\"", "\t"]);

private final ATTR:Gen<String> = c -> {
	var name = c.draw(pick(["id", "class", "title", "data-x", "Lang", "hidden"]));
	var value = c.draw(pick(["", "v", "a b", "x&amp;y", "\"q\"", "<>", "'"]));
	switch c.draw(int(0, 3)) {
		case 0: ' $name';
		case 1: ' $name="${value.replace("\"", "&quot;")}"';
		case 2: ' $name=\'${value.replace("'", "&#39;")}\'';
		case _: " " + name + "=" + unquotable(value);
	}
};

private function unquotable(v:String):String
	return v == "" || ~/[\s"'=<>`&]/.match(v) ? "x" : v;

private final FLOW:Gen<String> = recursive(TEXT, inner -> c -> {
	var kids = [for (_ in 0...c.draw(int(0, 3))) c.draw(inner)].join("");
	var attrs = [for (_ in 0...c.draw(int(0, 2))) c.draw(ATTR)].join("");
	switch c.draw(int(0, 13)) {
		case 0: '<div$attrs>$kids</div>';
		case 1: '<p$attrs>${c.draw(TEXT)}<b>$kids</b></p>';
		case 2: '<ul><li$attrs>$kids<li>${c.draw(TEXT)}</ul>';
		case 3: '<table$attrs><caption>${c.draw(TEXT)}</caption><tr><td>$kids<td>${c.draw(TEXT)}</table>';
		case 4: '<select$attrs><option>${c.draw(TEXT)}<option selected>${c.draw(TEXT)}</select>';
		case 5: '<span$attrs>$kids</span>';
		case 6: '<!--${c.draw(TEXT).replace("-", "")}-->';
		case 7: '<pre>x${c.draw(TEXT)}</pre>';
		case 8: '<svg viewBox="0 0 1 1"><circle r=1 /><foreignObject><div>$kids</div></foreignObject></svg>';
		case 9: '<math><mi>x</mi><mtext>$kids</mtext></math>';
		case 10: '<template><tr><td>${c.draw(TEXT)}</template>';
		case 11: '<textarea>x${c.draw(TEXT)}</textarea><script>if (a < b) x = "</p>"</script>';
		case 12: '<dl><dt>${c.draw(TEXT)}<dd>$kids</dl>';
		case _: '<a href=#$attrs>${c.draw(TEXT)}</a><em>$kids</em><br>';
	}
}, 4);

private final MARKUP:Gen<String> = c -> {
	var doctype = c.draw(pick(["", "<!doctype html>", '<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN">']));
	var head = c.draw(pick(["", "<title>t</title>", "<meta charset=utf-8><style>p{}</style>"]));
	doctype + head + [for (_ in 0...c.draw(int(0, 6))) c.draw(FLOW)].join("");
};

// (the robustness property's seeds: the repository's pages, the tree construction tests)
private function pages():Map<String, haxe.io.Bytes> {
	var out = new Map<String, haxe.io.Bytes>();
	for (p in ["src/helder/cli/page.html", "apps/studio/web/index.html"])
		if (sys.FileSystem.exists(p)) out.set(p, sys.io.File.getBytes(p));
	var dir = "tests/dom/fixtures/tree-construction";
	if (sys.FileSystem.exists(dir))
		for (f in sys.FileSystem.readDirectory(dir))
			if (sys.FileSystem.stat('$dir/$f').size <= 65536) out.set('$dir/$f', sys.io.File.getBytes('$dir/$f'));
	return out;
}
