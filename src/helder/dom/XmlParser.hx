package helder.dom;

using StringTools;

private class WellFormedness {
	public final code:String;
	public final offset:Int;

	public function new(code:String, offset:Int) {
		this.code = code;
		this.offset = offset;
	}
}

// An XML parser (XML 1.0, Namespaces in XML 1.0, HTML 14.2): a document
// entity's tree, the DOM's nodes made as the HTML Standard says (a
// template's children in its contents, select's and option's steps run).
// Not validating, and no external entity is read: the internal subset's
// general entities are, and the XHTML and MathML DTDs' public identifiers
// the HTML Standard lists stand for its named character references. The
// first well-formedness error stops the parse: the document is what came
// before it.
@:noCompletion class XmlParser {
	static final HTML_ENTITIES = [
		"-//W3C//DTD XHTML 1.0 Transitional//EN", "-//W3C//DTD XHTML 1.1//EN", "-//W3C//DTD XHTML 1.0 Strict//EN", "-//W3C//DTD XHTML 1.0 Frameset//EN",
		"-//W3C//DTD XHTML Basic 1.0//EN", "-//W3C//DTD XHTML 1.1 plus MathML 2.0//EN", "-//W3C//DTD XHTML 1.1 plus MathML 2.0 plus SVG 1.1//EN",
		"-//W3C//DTD MathML 2.0//EN", "-//WAPFORUM//DTD XHTML Mobile 1.0//EN", "-//WAPFORUM//DTD XHTML Mobile 1.1//EN", "-//WAPFORUM//DTD XHTML Mobile 1.2//EN"
	];

	// (an entity's expansions past these many characters: an error, as a billion laughs is)
	static inline var EXPANSION_LIMIT = 10000000;
	static inline var NESTING_LIMIT = 64;

	final doc:Document;
	var s:String;
	var pos = 0;
	var len:Int;
	// (inside an entity's replacement text: where its reference began, the offset of what it makes)
	var at = -1;

	var stack:Array<Element> = [];
	// namespace bindings: prefix, URI pairs, each element's from its mark
	var bindings = ["xml", Namespaces.XML, "xmlns", Namespaces.XMLNS];
	var marks:Array<Int> = [];
	var entities = new Map<String, String>();
	var htmlEntities = false;
	var expanding:Array<String> = [];
	var expanded = 0;

	// pending text: its parent and data, from where
	var textParent:Null<Node> = null;
	var textBuf:Null<StringBuf> = null;
	var textFirst = "";
	var textStart = 0;

	function new(doc:Document, xml:String) {
		this.doc = doc;
		s = xml;
		len = xml.length;
	}

	public static function document(xml:String, errors:Null<Array<ParseError>>):Document {
		var doc = new Document();
		doc.parsing++;
		var p = new XmlParser(doc, xml);
		try p.parse() catch (e:WellFormedness) {
			p.flushText();
			if (errors != null) errors.push({code: e.code, offset: e.offset});
		}
		doc.parsing--;
		doc.checkpoint();
		return doc;
	}

	inline function fail(code:String, ?offset:Int):Dynamic
		throw new WellFormedness(code, offset ?? pos);

	inline function code(i:Int):Int
		return i < len ? s.fastCodeAt(i) : -1;

	inline function here():Int
		return at >= 0 ? at : pos;

	function lookingAt(w:String):Bool {
		if (pos + w.length > len) return false;
		for (k in 0...w.length)
			if (s.fastCodeAt(pos + k) != w.fastCodeAt(k)) return false;
		return true;
	}

	function expect(w:String, what:String) {
		if (!lookingAt(w)) fail(what);
		pos += w.length;
	}

	static inline function isWs(c:Int):Bool
		return c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

	function skipWs():Bool {
		var start = pos;
		while (pos < len && isWs(s.fastCodeAt(pos)))
			pos++;
		return pos > start;
	}

	function requireWs(what:String)
		if (!skipWs()) fail(what);

	static inline function nameChar(c:Int):Bool
		return c >= "a".code && c <= "z".code || c >= "A".code && c <= "Z".code || c >= "0".code && c <= "9".code || c == ":".code || c == "_".code
			|| c == "-".code || c == ".".code || c >= 0x80;

	// a Name (XML's production)
	function name():String {
		var start = pos;
		while (pos < len && nameChar(s.fastCodeAt(pos)))
			pos++;
		var n = s.substring(start, pos);
		if (!Names.isXmlName(n)) fail("invalid-name", start);
		return n;
	}

	// a Char of XML's (no controls but tab, LF and CR; no U+FFFE, U+FFFF or lone surrogate)
	function checkChars(from:Int, to:Int) {
		for (i in from...to) {
			var c = s.fastCodeAt(i);
			if (c < 0x20 && c != 9 && c != 10 && c != 13 || c == 0xFFFE || c == 0xFFFF) fail("invalid-character", i);
			if (c >= 0xD800 && c <= 0xDBFF) {
				var d = code(i + 1);
				if (!(d >= 0xDC00 && d <= 0xDFFF)) fail("invalid-character", i);
			} else if (c >= 0xDC00 && c <= 0xDFFF) {
				var d = i > 0 ? s.fastCodeAt(i - 1) : 0;
				if (!(d >= 0xD800 && d <= 0xDBFF)) fail("invalid-character", i);
			}
		}
	}

	function parse() {
		if (code(0) == 0xFEFF) pos = 1;
		if (lookingAt("<?xml") && isWs(code(pos + 5))) declaration();
		misc();
		if (lookingAt("<!DOCTYPE")) {
			doctype();
			misc();
		}
		if (code(pos) != "<".code) fail(pos >= len ? "missing-root" : "text-before-root");
		content(0);
		misc();
		if (pos < len) fail("content-after-root");
	}

	// the XML declaration: its version, encoding and standalone (read, none kept)
	function declaration() {
		var start = pos;
		var end = s.indexOf("?>", pos);
		if (end < 0) fail("unclosed-declaration");
		if (!~/^<\?xml\s+version\s*=\s*("1\.[0-9]+"|'1\.[0-9]+')/.match(s.substring(start, end))) fail("bad-declaration");
		pos = end + 2;
	}

	// comments, processing instructions and white space (outside the root: the document's)
	function misc()
		while (true) {
			skipWs();
			if (lookingAt("<!--")) comment(doc);
			else if (lookingAt("<?")) pi(doc);
			else return;
		}

	function quoted(what:String):String {
		var q = code(pos);
		if (q != "\"".code && q != "'".code) fail(what);
		var end = s.indexOf(String.fromCharCode(q), pos + 1);
		if (end < 0) fail(what);
		var v = s.substring(pos + 1, end);
		pos = end + 1;
		return v;
	}

	function doctype() {
		var start = pos;
		pos += 9;
		requireWs("bad-doctype");
		var n = name();
		var publicId = "", systemId = "";
		var spaced = skipWs();
		if (lookingAt("PUBLIC")) {
			if (!spaced) fail("bad-doctype");
			pos += 6;
			requireWs("bad-doctype");
			publicId = quoted("bad-doctype");
			if (!~/^[ \r\na-zA-Z0-9\-'()+,.\/:=?;!*#@$_%]*$/.match(publicId)) fail("bad-public-id");
			requireWs("bad-doctype");
			systemId = quoted("bad-doctype");
			skipWs();
		} else if (lookingAt("SYSTEM")) {
			if (!spaced) fail("bad-doctype");
			pos += 6;
			requireWs("bad-doctype");
			systemId = quoted("bad-doctype");
			skipWs();
		}
		htmlEntities = HTML_ENTITIES.contains(publicId);
		if (code(pos) == "[".code) {
			pos++;
			subset();
			skipWs();
		}
		expect(">", "bad-doctype");
		var d = new DocumentType(doc, n, publicId, systemId);
		d.start = start;
		d.end = pos;
		Node.insert(d, doc, null);
	}

	// the internal subset: its general entities kept, every other declaration read past
	function subset()
		while (true) {
			skipWs();
			if (pos >= len) fail("unclosed-doctype");
			var c = s.fastCodeAt(pos);
			if (c == "]".code) {
				pos++;
				return;
			}
			if (lookingAt("<!ENTITY")) entityDeclaration();
			else if (lookingAt("<!--")) {
				var end = s.indexOf("-->", pos + 4);
				if (end < 0) fail("unclosed-comment");
				pos = end + 3;
			} else if (lookingAt("<?")) {
				var end = s.indexOf("?>", pos + 2);
				if (end < 0) fail("unclosed-pi");
				pos = end + 2;
			} else if (lookingAt("<!ELEMENT") || lookingAt("<!ATTLIST") || lookingAt("<!NOTATION")) declarationEnd();
			else if (c == "%".code) {
				pos++;
				name();
				expect(";", "bad-reference");
			} else fail("bad-doctype");
		}

	// past a markup declaration's ">" (its quoted literals skipped whole)
	function declarationEnd()
		while (true) {
			if (pos >= len) fail("unclosed-doctype");
			var c = s.fastCodeAt(pos);
			if (c == "\"".code || c == "'".code) quoted("bad-doctype") else {
				pos++;
				if (c == ">".code) return;
			}
		}

	function entityDeclaration() {
		pos += 8;
		requireWs("bad-entity");
		var parameter = false;
		if (code(pos) == "%".code) {
			parameter = true;
			pos++;
			requireWs("bad-entity");
		}
		var n = name();
		requireWs("bad-entity");
		var c = code(pos);
		if (c == "\"".code || c == "'".code) {
			var value = entityValue(quoted("bad-entity"));
			if (!parameter && !entities.exists(n)) entities.set(n, value);
			skipWs();
			expect(">", "bad-entity");
		} else declarationEnd();
	}

	// an entity's value: its character references read, its entity references kept for its use
	function entityValue(v:String):String {
		if (v.indexOf("&#") < 0) return v;
		return ~/&#(x[0-9a-fA-F]+|[0-9]+);/g.map(v, r -> {
			var m = r.matched(1);
			var n = m.charAt(0) == "x" ? Std.parseInt("0x" + m.substr(1)) : Std.parseInt(m);
			var b = new StringBuf();
			b.addChar(n);
			b.toString();
		});
	}

	// --- content: elements and their children, until the stack is back at depth

	function current():Node {
		if (stack.length == 0) return doc;
		var e = stack[stack.length - 1];
		return e.isHTML(Tags.TEMPLATE) ? (cast e : HTMLTemplateElement).content : e;
	}

	function content(depth:Int) {
		do {
			if (pos >= len) {
				if (stack.length > depth) fail(at >= 0 ? "unbalanced-entity" : "unclosed-element");
				return;
			}
			var c = s.fastCodeAt(pos);
			if (c == "<".code) {
				var d = code(pos + 1);
				if (d == "/".code) endTag(depth);
				else if (d == "!".code) {
					if (lookingAt("<!--")) comment(current());
					else if (lookingAt("<![CDATA[")) cdata();
					else fail("bad-markup");
				} else if (d == "?".code) pi(current());
				else startTag();
			} else if (c == "&".code) reference();
			else text();
		} while (stack.length > depth || at >= 0 && pos < len);
	}

	function text() {
		var start = pos;
		while (pos < len) {
			var end = Scan.stop(s, pos, len, "<".code, "&".code);
			checkChars(pos, end);
			var run = s.substring(pos, end);
			if (run.indexOf("]]>") >= 0) fail("cdata-end-in-text", pos + run.indexOf("]]>"));
			addText(run, start);
			pos = end;
			var c = code(pos);
			if (c == 13) {
				addText("\n", pos);
				pos += code(pos + 1) == 10 ? 2 : 1;
			} else if (c == 0) fail("invalid-character");
			else break;
		}
	}

	function addText(t:String, start:Int) {
		if (t == "") return;
		if (stack.length == 0) {
			for (i in 0...t.length)
				if (!isWs(t.fastCodeAt(i))) fail("text-outside-root", start);
			return;
		}
		var parent = current();
		if (textParent != parent) {
			flushText();
			textParent = parent;
			textFirst = t;
			textBuf = null;
			textStart = at >= 0 ? at : start;
			return;
		}
		if (textBuf == null) {
			textBuf = new StringBuf();
			textBuf.add(textFirst);
		}
		textBuf.add(t);
	}

	function flushText() {
		var parent = textParent;
		if (parent == null) return;
		textParent = null;
		var data = textBuf == null ? textFirst : textBuf.toString();
		textBuf = null;
		var t = new Text(parent.doc, data);
		t.start = textStart;
		t.end = here();
		Node.insert(t, parent, null);
	}

	// a character or entity reference in content (an entity's text parsed as content)
	function reference() {
		var start = pos;
		pos++;
		if (code(pos) == "#".code) {
			addText(charRef(start), start);
			return;
		}
		var n = name();
		expect(";", "bad-reference");
		var value = predefined(n);
		if (value != null) {
			addText(value, start);
			return;
		}
		var text = entities.get(n);
		if (text == null) {
			var html = htmlEntities ? Entities.get(n + ";") : null;
			if (html == null) fail("undefined-entity", start);
			addText(html, start);
			return;
		}
		if (text.indexOf("<") < 0 && text.indexOf("&") < 0 && text.indexOf("\r") < 0) {
			expand(text.length, n, start);
			addText(text, start);
			return;
		}
		expand(text.length, n, start);
		if (expanding.contains(n)) fail("recursive-entity", start);
		if (expanding.length >= NESTING_LIMIT) fail("entity-nesting-limit", start);
		// (the replacement text parsed in place: elements in it must close in it)
		expanding.push(n);
		var savedS = s, savedPos = pos, savedLen = len, savedAt = at;
		s = text;
		pos = 0;
		len = text.length;
		if (at < 0) at = start;
		content(stack.length);
		s = savedS;
		pos = savedPos;
		len = savedLen;
		at = savedAt;
		expanding.pop();
	}

	function expand(n:Int, name:String, start:Int) {
		expanded += n;
		if (expanded > EXPANSION_LIMIT) fail("entity-expansion-limit", start);
	}

	static function predefined(n:String):Null<String>
		return switch n {
			case "amp": "&";
			case "lt": "<";
			case "gt": ">";
			case "quot": "\"";
			case "apos": "'";
			case _: null;
		}

	// &#n; or &#xn; (pos at the "#"): its character
	function charRef(start:Int):String {
		pos++;
		var hex = code(pos) == "x".code;
		if (hex) pos++;
		var digits = pos;
		while (pos < len && (hex ? isHex(s.fastCodeAt(pos)) : s.fastCodeAt(pos) >= "0".code && s.fastCodeAt(pos) <= "9".code))
			pos++;
		if (pos == digits || pos - digits > 8) fail("bad-reference", start);
		var n = Std.parseInt((hex ? "0x" : "") + s.substring(digits, pos));
		expect(";", "bad-reference");
		if (!(n == 9 || n == 10 || n == 13 || n >= 0x20 && n <= 0xD7FF || n >= 0xE000 && n <= 0xFFFD || n >= 0x10000 && n <= 0x10FFFF))
			fail("invalid-character-reference", start);
		var b = new StringBuf();
		b.addChar(n);
		return b.toString();
	}

	static inline function isHex(c:Int):Bool
		return c >= "0".code && c <= "9".code || c >= "a".code && c <= "f".code || c >= "A".code && c <= "F".code;

	function comment(parent:Node) {
		flushText();
		var start = pos;
		pos += 4;
		var end = s.indexOf("--", pos);
		if (end < 0) fail("unclosed-comment", start);
		if (code(end + 2) != ">".code) fail("double-hyphen-in-comment", end);
		checkChars(pos, end);
		var c = new Comment(parent.doc, newlines(s.substring(pos, end)));
		pos = end + 3;
		c.start = at >= 0 ? at : start;
		c.end = here();
		Node.insert(c, parent, null);
	}

	function pi(parent:Node) {
		flushText();
		var start = pos;
		pos += 2;
		var target = name();
		if (target.toLowerCase() == "xml") fail("reserved-pi-target", start);
		var data = "";
		if (lookingAt("?>")) pos += 2 else {
			requireWs("bad-pi");
			var end = s.indexOf("?>", pos);
			if (end < 0) fail("unclosed-pi", start);
			checkChars(pos, end);
			data = newlines(s.substring(pos, end));
			pos = end + 2;
		}
		var p = new ProcessingInstruction(parent.doc, target, data);
		p.start = at >= 0 ? at : start;
		p.end = here();
		Node.insert(p, parent, null);
	}

	function cdata() {
		flushText();
		var start = pos;
		pos += 9;
		var end = s.indexOf("]]>", pos);
		if (end < 0) fail("unclosed-cdata", start);
		checkChars(pos, end);
		var parent = current();
		var c = new CDATASection(parent.doc, newlines(s.substring(pos, end)));
		pos = end + 3;
		c.start = at >= 0 ? at : start;
		c.end = here();
		Node.insert(c, parent, null);
	}

	static function newlines(t:String):String
		return t.indexOf("\r") < 0 ? t : t.replace("\r\n", "\n").replace("\r", "\n");

	// a qualified name's prefix and local name (one colon at most, neither side empty)
	function split(qname:String, at:Int):Array<Null<String>> {
		var colon = qname.indexOf(":");
		if (colon < 0) return [null, qname];
		if (colon == 0 || colon == qname.length - 1 || qname.indexOf(":", colon + 1) >= 0) fail("bad-qualified-name", at);
		return [qname.substr(0, colon), qname.substr(colon + 1)];
	}

	function resolve(prefix:Null<String>, at:Int):Null<String> {
		var key = prefix ?? "";
		var i = bindings.length - 2;
		while (i >= 0) {
			if (bindings[i] == key) {
				var uri = bindings[i + 1];
				return uri == "" ? null : uri;
			}
			i -= 2;
		}
		if (prefix != null) fail("unbound-prefix", at);
		return null;
	}

	function startTag() {
		flushText();
		var start = pos;
		pos++;
		var qname = name();
		var names = [], values = [], offsets = [];
		while (true) {
			var spaced = skipWs();
			var c = code(pos);
			if (c == ">".code || c == "/".code) break;
			if (!spaced) fail("bad-tag");
			var at = pos;
			var n = name();
			skipWs();
			expect("=", "bad-attribute");
			skipWs();
			if (names.contains(n)) fail("duplicate-attribute", at);
			names.push(n);
			values.push(attrValue());
			offsets.push(at);
		}
		var empty = code(pos) == "/".code;
		if (empty) pos++;
		expect(">", "bad-tag");
		// (the namespaces declared on it, then its own names resolved)
		marks.push(bindings.length);
		for (k in 0...names.length) {
			var n = names[k], v = values[k];
			if (n == "xmlns") {
				if (v == Namespaces.XML || v == Namespaces.XMLNS) fail("reserved-namespace", offsets[k]);
				bindings.push("");
				bindings.push(v);
			} else if (n.startsWith("xmlns:")) {
				var p = n.substr(6);
				if (p == "xmlns" || p == "xml" && v != Namespaces.XML || p != "xml" && v == Namespaces.XML || v == Namespaces.XMLNS || v == "")
					fail("reserved-namespace", offsets[k]);
				split(p, offsets[k]);
				bindings.push(p);
				bindings.push(v);
			}
		}
		var parts = split(qname, start + 1);
		var ns = resolve(parts[0], start + 1);
		var parent = current();
		var e = Element.create(parent.doc, parts[1], ns, parts[0]);
		e.start = at >= 0 ? at : start;
		var seen = [];
		for (k in 0...names.length) {
			var n = names[k], v = values[k];
			var a:Attr;
			if (n == "xmlns") a = new Attr(e.doc, "xmlns", v, Namespaces.XMLNS);
			else if (n.startsWith("xmlns:")) a = new Attr(e.doc, n.substr(6), v, Namespaces.XMLNS, "xmlns");
			else {
				var p = split(n, offsets[k]);
				a = new Attr(e.doc, p[1], v, p[0] == null ? null : resolve(p[0], offsets[k]), p[0]);
			}
			var key = (a.namespaceURI ?? "") + " " + a.localName;
			if (seen.contains(key)) fail("duplicate-attribute", offsets[k]);
			seen.push(key);
			e.appendAttr(a);
		}
		Node.insert(e, parent, null);
		if (empty) {
			e.end = here();
			bindings.splice(marks.pop(), bindings.length);
			e.childrenParsed();
		} else stack.push(e);
	}

	// an attribute's value: references read, white space as spaces (a reference's character kept)
	function attrValue():String {
		var q = code(pos);
		if (q != "\"".code && q != "'".code) fail("bad-attribute");
		pos++;
		var buf:Null<StringBuf> = null, start = pos;
		while (true) {
			var end = Scan.stop(s, pos, len, q, "&".code);
			var lt = s.indexOf("<", pos);
			if (lt >= 0 && lt < end) fail("lt-in-attribute", lt);
			checkChars(pos, end);
			if (end >= len) fail("unclosed-attribute", start - 1);
			var c = s.fastCodeAt(end);
			if (c == q && buf == null) {
				var v = s.substring(start, end);
				pos = end + 1;
				return spaces(v);
			}
			if (buf == null) buf = new StringBuf();
			buf.add(spaces(s.substring(pos, end)));
			pos = end;
			if (c == q) {
				pos++;
				return buf.toString();
			}
			if (c == 13) {
				buf.add(" ");
				pos += code(pos + 1) == 10 ? 2 : 1;
			} else if (c == 0) fail("invalid-character");
			else attrReference(buf);
		}
	}

	static function spaces(v:String):String {
		for (i in 0...v.length) {
			var c = v.fastCodeAt(i);
			if (c == 9 || c == 10 || c == 13) return v.replace("\r\n", " ").replace("\t", " ").replace("\n", " ").replace("\r", " ");
		}
		return v;
	}

	function attrReference(buf:StringBuf) {
		var start = pos;
		pos++;
		if (code(pos) == "#".code) {
			buf.add(charRef(start));
			return;
		}
		var n = name();
		expect(";", "bad-reference");
		var value = predefined(n);
		if (value != null) {
			buf.add(value);
			return;
		}
		var text = entities.get(n);
		if (text == null) {
			var html = htmlEntities ? Entities.get(n + ";") : null;
			if (html == null) fail("undefined-entity", start);
			buf.add(html);
			return;
		}
		if (expanding.contains(n)) fail("recursive-entity", start);
		if (expanding.length >= NESTING_LIMIT) fail("entity-nesting-limit", start);
		expand(text.length, n, start);
		if (text.indexOf("<") >= 0) fail("lt-in-attribute", start);
		// (its own references read, its white space as spaces)
		expanding.push(n);
		var savedS = s, savedPos = pos, savedLen = len;
		s = text;
		pos = 0;
		len = text.length;
		while (pos < len) {
			var c = s.fastCodeAt(pos);
			if (c == "&".code) attrReference(buf) else {
				buf.addChar(isWs(c) ? " ".code : c);
				pos++;
			}
		}
		s = savedS;
		pos = savedPos;
		len = savedLen;
		expanding.pop();
	}

	function endTag(depth:Int) {
		flushText();
		pos += 2;
		var start = pos;
		var qname = name();
		skipWs();
		expect(">", "bad-end-tag");
		if (stack.length <= depth) fail(at >= 0 ? "unbalanced-entity" : "unexpected-end-tag", start);
		var e = stack[stack.length - 1];
		if (e.qualifiedName() != qname) fail("mismatched-end-tag", start);
		stack.pop();
		bindings.splice(marks.pop(), bindings.length);
		e.end = here();
		e.childrenParsed();
	}
}
