package helder.dom;

import helder.dom.Tokenizer;
import helder.dom.Tags.*;

using StringTools;

// The HTML standard's tree construction (13.2.6), mode by mode, with
// scripting off: no script runs, <noscript> is parsed as markup, nothing
// is sanitized and no shadow roots are attached (a declarative one stays a
// template). A <template for> patches its markers' range, as streaming does.
@:noCompletion class TreeBuilder implements TokenSink {
	static inline var INITIAL = 0;
	static inline var BEFORE_HTML = 1;
	static inline var BEFORE_HEAD = 2;
	static inline var IN_HEAD = 3;
	static inline var IN_HEAD_NOSCRIPT = 4;
	static inline var AFTER_HEAD = 5;
	static inline var IN_BODY = 6;
	static inline var TEXT = 7;
	static inline var IN_TABLE = 8;
	static inline var IN_TABLE_TEXT = 9;
	static inline var IN_CAPTION = 10;
	static inline var IN_COLUMN_GROUP = 11;
	static inline var IN_TABLE_BODY = 12;
	static inline var IN_ROW = 13;
	static inline var IN_CELL = 14;
	static inline var IN_TEMPLATE = 15;
	static inline var AFTER_BODY = 16;
	static inline var IN_FRAMESET = 17;
	static inline var AFTER_FRAMESET = 18;
	static inline var AFTER_AFTER_BODY = 19;
	static inline var AFTER_AFTER_FRAMESET = 20;

	static inline var SCOPE = 0;
	static inline var LIST_SCOPE = 1;
	static inline var BUTTON_SCOPE = 2;
	static inline var TABLE_SCOPE = 3;

	final doc:Document;
	final tokenizer:Tokenizer;
	final errors:Null<Array<ParseError>>;
	final length:Int;

	var mode = INITIAL;
	var original = INITIAL;
	var templateModes:Array<Int> = [];
	var stack:Array<Element> = [];
	// the list of active formatting elements (null: a marker) and each one's token
	var active:Array<Null<Element>> = [];
	var activeTags:Array<Null<Tag>> = [];
	var headElement:Null<Element> = null;
	var formElement:Null<Element> = null;
	var framesetOk = true;
	var fosterParenting = false;
	var skipNewline = false;
	var stopped = false;

	// the fragment case: the context element, the root html element and where its children go
	var context:Null<Element> = null;
	var root:Null<Element> = null;
	var target:Null<Node> = null;

	// the current token's source offsets
	var here = 0;
	var hereEnd = 0;
	var closing:Null<Tag> = null;

	// an insertion location, as the last place() or adjusted() left it
	var locParent:Node;
	var locRef:Null<Node> = null;

	// pending text: its location, data and source offsets
	var textParent:Null<Node> = null;
	var textRef:Null<Node> = null;
	var textFirst = "";
	var textBuf:Null<StringBuf> = null;
	var textStart = 0;
	var textEnd = 0;

	// the in table text mode's pending character tokens
	var tableText:Null<StringBuf> = null;
	var tableTextStart = 0;
	var tableTextEnd = 0;
	var tableTextSpaces = true;

	function new(doc:Document, html:String, errors:Null<Array<ParseError>>) {
		this.doc = doc;
		this.errors = errors;
		this.length = html.length;
		tokenizer = new Tokenizer(html, this, errors);
		locParent = doc;
	}

	public static function document(html:String, errors:Null<Array<ParseError>>):Document {
		var doc = Document.html();
		doc.parsing++;
		new TreeBuilder(doc, html, errors).tokenizer.run();
		doc.parsing--;
		doc.checkpoint();
		return doc;
	}

	// the HTML fragment parsing algorithm, context's children's place: a new fragment
	public static function fragment(html:String, context:Element, errors:Null<Array<ParseError>>):DocumentFragment {
		var temp = Document.html();
		temp.mode = context.doc.mode;
		var fragment = new DocumentFragment(context.doc);
		var b = new TreeBuilder(temp, html, errors);
		b.context = context;
		if (context.ns == Element.HTML) b.tokenizer.state = switch context.tag {
			case TITLE | TEXTAREA: Tokenizer.RCDATA;
			case STYLE | XMP | IFRAME | NOEMBED | NOFRAMES: Tokenizer.RAWTEXT;
			case SCRIPT: Tokenizer.SCRIPT_DATA;
			case PLAINTEXT: Tokenizer.PLAINTEXT;
			case _: Tokenizer.DATA;
		}
		var root = Element.create(temp, "html", Namespaces.HTML);
		Node.insert(root, temp, null);
		b.stack.push(root);
		b.root = root;
		b.target = fragment;
		if (context.isHTML(TEMPLATE)) b.templateModes.push(IN_TEMPLATE);
		b.reset();
		var e:Null<Element> = context;
		while (e != null) {
			if (e.isHTML(FORM)) {
				b.formElement = e;
				break;
			}
			e = e.parentElement;
		}
		var owner = context.doc;
		owner.parsing++;
		b.tokenizer.run();
		owner.parsing--;
		owner.checkpoint();
		return fragment;
	}

	inline function error(code:String)
		if (errors != null) errors.push({code: code, offset: here});

	// --- the stack of open elements

	inline function current():Element
		return stack[stack.length - 1];

	inline function adjustedCurrent():Null<Element>
		return context != null && stack.length == 1 ? context : stack.length == 0 ? null : current();

	inline function isHtml(e:Element, id:Int):Bool
		return e.ns == Element.HTML && e.tag == id;

	inline function currentIs(id:Int):Bool
		return isHtml(current(), id);

	// (an element leaves the stack: its end is after its end tag, else where the token closing it began)
	function popped(e:Element) {
		e.end = closing != null && e.ns == Element.HTML && e.localName == closing.name ? hereEnd : here;
		if (e.tag == OPTION) e.childrenParsed();
	}

	function pop():Element {
		var e = stack.pop();
		popped(e);
		return e;
	}

	function removeFromStack(e:Element) {
		var i = stack.lastIndexOf(e);
		if (i >= 0) {
			stack.splice(i, 1);
			popped(e);
		}
	}

	function popUntil(id:Int)
		while (stack.length > 0)
			if (isHtml(pop(), id)) return;

	function popUntilElement(e:Element)
		while (stack.length > 0)
			if (pop() == e) return;

	function hasTemplate():Bool {
		for (e in stack)
			if (isHtml(e, TEMPLATE)) return true;
		return false;
	}

	inline function parsingTemplate():Bool
		return hasTemplate() || context != null && context.isHTML(TEMPLATE);

	static function boundary(e:Element, kind:Int):Bool {
		if (kind == TABLE_SCOPE) return e.ns == Element.HTML && (e.tag == HTML || e.tag == TABLE || e.tag == TEMPLATE);
		switch e.ns {
			case Element.HTML:
				switch e.tag {
					case APPLET | CAPTION | HTML | TABLE | TD | TH | MARQUEE | OBJECT | SELECT | TEMPLATE: return true;
					case OL | UL: return kind == LIST_SCOPE;
					case BUTTON: return kind == BUTTON_SCOPE;
					case _: return false;
				}
			case Element.MATHML:
				return switch e.tag {
					case MI | MO | MN | MS | MTEXT | ANNOTATION_XML: true;
					case _: false;
				}
			case Element.SVG:
				return switch e.tag {
					case FOREIGN_OBJECT | DESC | TITLE: true;
					case _: false;
				}
			case _:
				return false;
		}
	}

	// the stack has an HTML element of that tag in the scope
	function inScope(id:Int, kind = SCOPE):Bool {
		var i = stack.length - 1;
		while (i >= 0) {
			var e = stack[i--];
			if (isHtml(e, id)) return true;
			if (boundary(e, kind)) return false;
		}
		return false;
	}

	function elementInScope(target:Element):Bool {
		var i = stack.length - 1;
		while (i >= 0) {
			var e = stack[i--];
			if (e == target) return true;
			if (boundary(e, SCOPE)) return false;
		}
		return false;
	}

	function headingInScope():Bool {
		var i = stack.length - 1;
		while (i >= 0) {
			var e = stack[i--];
			if (e.ns == Element.HTML && e.tag >= H1 && e.tag <= H6) return true;
			if (boundary(e, SCOPE)) return false;
		}
		return false;
	}

	static function isSpecial(e:Element):Bool {
		return switch e.ns {
			case Element.HTML: switch e.tag {
					case ADDRESS | APPLET | AREA | ARTICLE | ASIDE | BASE | BASEFONT | BGSOUND | BLOCKQUOTE | BODY | BR | BUTTON | CAPTION | CENTER | COL | COLGROUP | DD
						| DETAILS | DIR | DIV | DL | DT | EMBED | FIELDSET | FIGCAPTION | FIGURE | FOOTER | FORM | FRAME | FRAMESET | H1 | H2 | H3 | H4 | H5 | H6
						| HEAD | HEADER | HGROUP | HR | HTML | IFRAME | IMG | INPUT | KEYGEN | LI | LINK | LISTING | MAIN | MARQUEE | MENU | META | NAV | NOEMBED
						| NOFRAMES | NOSCRIPT | OBJECT | OL | P | PARAM | PLAINTEXT | PRE | SCRIPT | SEARCH | SECTION | SELECT | SOURCE | STYLE | SUMMARY | TABLE
						| TBODY | TD | TEMPLATE | TEXTAREA | TFOOT | TH | THEAD | TITLE | TR | TRACK | UL | WBR | XMP: true;
					case _: false;
				}
			case Element.MATHML: switch e.tag {
					case MI | MO | MN | MS | MTEXT | ANNOTATION_XML: true;
					case _: false;
				}
			case Element.SVG: switch e.tag {
					case FOREIGN_OBJECT | DESC | TITLE: true;
					case _: false;
				}
			case _: false;
		}
	}

	static inline function implied(e:Element, thorough:Bool):Bool
		return e.ns == Element.HTML && switch e.tag {
			case DD | DT | LI | OPTGROUP | OPTION | P | RB | RP | RT | RTC: true;
			case CAPTION | COLGROUP | TBODY | TD | TFOOT | TH | THEAD | TR: thorough;
			case _: false;
		}

	// generate implied end tags (except: a tag id to leave open; by name for an unknown one)
	function generateImplied(except = -1, ?exceptName:String)
		while (stack.length > 0 && implied(current(), false) && current().tag != except && current().localName != exceptName)
			pop();

	function generateAllImplied()
		while (stack.length > 0 && implied(current(), true))
			pop();

	function closeP() {
		generateImplied(P);
		if (!currentIs(P)) error("unexpected-end-tag");
		popUntil(P);
	}

	inline function closePInButtonScope()
		if (inScope(P, BUTTON_SCOPE)) closeP();

	function clearBackTo(ids:Array<Int>)
		while (!(current().ns == Element.HTML && ids.contains(current().tag)))
			pop();

	static final TABLE_CONTEXT = [TABLE, TEMPLATE, HTML];
	static final TABLE_BODY_CONTEXT = [TBODY, TFOOT, THEAD, TEMPLATE, HTML];
	static final ROW_CONTEXT = [TR, TEMPLATE, HTML];

	// reset the insertion mode appropriately
	function reset() {
		var i = stack.length - 1;
		while (i >= 0) {
			var node = stack[i], last = i == 0;
			if (last && context != null) node = context;
			if (node.ns == Element.HTML) switch node.tag {
				case TD | TH if (!last):
					mode = IN_CELL;
					return;
				case TR:
					mode = IN_ROW;
					return;
				case TBODY | THEAD | TFOOT:
					mode = IN_TABLE_BODY;
					return;
				case CAPTION:
					mode = IN_CAPTION;
					return;
				case COLGROUP:
					mode = IN_COLUMN_GROUP;
					return;
				case TABLE:
					mode = IN_TABLE;
					return;
				case TEMPLATE:
					mode = templateModes[templateModes.length - 1];
					return;
				case HEAD if (!last):
					mode = IN_HEAD;
					return;
				case BODY:
					mode = IN_BODY;
					return;
				case FRAMESET:
					mode = IN_FRAMESET;
					return;
				case HTML:
					mode = headElement == null ? BEFORE_HEAD : AFTER_HEAD;
					return;
				case _:
			}
			if (last) {
				mode = IN_BODY;
				return;
			}
			i--;
		}
	}

	// --- the list of active formatting elements

	function pushActive(e:Element, t:Tag) {
		var same = 0, earliest = -1;
		var i = active.length - 1;
		while (i >= 0) {
			var a = active[i];
			if (a == null) break;
			if (a.localName == e.localName && a.namespaceURI == e.namespaceURI && sameAttrs(activeTags[i], t)) {
				same++;
				earliest = i;
			}
			i--;
		}
		if (same >= 3) {
			active.splice(earliest, 1);
			activeTags.splice(earliest, 1);
		}
		active.push(e);
		activeTags.push(t);
	}

	static function sameAttrs(a:Tag, b:Tag):Bool {
		var x = a.attrs ?? [], y = b.attrs ?? [];
		if (x.length != y.length) return false;
		var i = 0;
		while (i < x.length) {
			if (b.attr(x[i]) != x[i + 1]) return false;
			i += 2;
		}
		return true;
	}

	function insertMarker() {
		active.push(null);
		activeTags.push(null);
	}

	function clearToMarker()
		while (active.length > 0) {
			activeTags.pop();
			if (active.pop() == null) return;
		}

	function reconstruct() {
		if (active.length == 0) return;
		var i = active.length - 1;
		var last = active[i];
		if (last == null || stack.contains(last)) return;
		while (i > 0) {
			var e = active[i - 1];
			if (e == null || stack.contains(e)) break;
			i--;
		}
		while (i < active.length) {
			var e = insertHtml(activeTags[i]);
			active[i] = e;
			i++;
		}
	}

	// --- creating and inserting nodes

	// the appropriate place for inserting a node, adjusted (locParent, locRef)
	function place(?over:Node) {
		var parent:Node = over ?? current();
		var ref:Null<Node> = null;
		if (fosterParenting && parent.nodeType == Node.ELEMENT_NODE && (cast parent : Element).ns == Element.HTML && switch (cast parent : Element).tag {
			case TABLE | TBODY | TFOOT | THEAD | TR: true;
			case _: false;
		}) {
			var i = stack.length - 1;
			while (i >= 0 && !isHtml(stack[i], TABLE) && !isHtml(stack[i], TEMPLATE))
				i--;
			if (i < 0) {
				adjusted(stack[0], null);
				return;
			}
			var last = stack[i];
			if (last.tag == TEMPLATE) parent = last else if (last.parentNode != null) {
				parent = last.parentNode;
				ref = last;
			} else parent = stack[i - 1];
		}
		if (parent.nodeType == Node.ELEMENT_NODE && (cast parent : Element).isHTML(TEMPLATE)) {
			var t:HTMLTemplateElement = cast parent;
			var patch = t.insertionTarget;
			if (patch == null) {
				parent = t.content;
				ref = null;
			} else if (t.endMarker != null && t.endMarker.parentNode == patch) {
				parent = patch;
				ref = t.endMarker;
			} else {
				parent = patch;
				ref = null;
			}
		}
		adjusted(parent, ref);
	}

	// the adjusted insertion location (the fragment's root html element: the fragment)
	inline function adjusted(parent:Node, ref:Null<Node>) {
		if (parent == root && root != null) {
			locParent = target;
			locRef = null;
		} else {
			locParent = parent;
			locRef = ref;
		}
	}

	// create an element for a token (in namespace, its attributes adjusted for it)
	function create(t:Tag, namespace:String, intendedParent:Node):Element {
		var parent = intendedParent == root && root != null ? target : intendedParent;
		var e = Element.create(parent.doc, t.name, namespace);
		e.start = t.start;
		var a = t.attrs;
		if (a != null) {
			var list = [];
			var i = 0;
			while (i < a.length) {
				var name = a[i], value = a[i + 1];
				i += 2;
				if (namespace == Namespaces.HTML) {
					list.push(new Attr(e.doc, name, value));
					continue;
				}
				if (namespace == Namespaces.MATHML && name == "definitionurl") name = "definitionURL";
				else if (namespace == Namespaces.SVG) name = SVG_ATTRS.get(name) ?? name;
				var attr = switch name {
					case "xlink:actuate" | "xlink:arcrole" | "xlink:href" | "xlink:role" | "xlink:show" | "xlink:title" | "xlink:type":
						new Attr(e.doc, name.substr(6), value, Namespaces.XLINK, "xlink");
					case "xml:lang" | "xml:space": new Attr(e.doc, name.substr(4), value, Namespaces.XML, "xml");
					case "xmlns": new Attr(e.doc, "xmlns", value, Namespaces.XMLNS);
					case "xmlns:xlink": new Attr(e.doc, "xlink", value, Namespaces.XMLNS, "xmlns");
					case _: new Attr(e.doc, name, value);
				}
				list.push(attr);
			}
			// (appended at once: no one can observe an element the parser has not inserted yet)
			for (attr in list)
				attr.ownerElement = e;
			e.attrs = list;
			e.attributesSet();
		}
		return e;
	}

	// insert an element at the adjusted insertion location (place() already run, or over)
	function insertAt(e:Element) {
		var parent = locParent, ref = locRef;
		if (e.parentNode != null || e == parent) return;
		if (e.firstChild != null && Node.hostIncludingAncestor(e, parent)) return;
		if (parent.nodeType == Node.DOCUMENT_NODE && (cast parent : Document).documentElement != null) return;
		if (ref != null && ref.parentNode != parent) return;
		Node.insert(e, parent, ref);
	}

	// insert a foreign element (an HTML one: insertHtml)
	function insertForeign(t:Tag, namespace:String):Element {
		flushText();
		place();
		var e = create(t, namespace, locParent);
		place();
		insertAt(e);
		stack.push(e);
		return e;
	}

	inline function insertHtml(t:Tag):Element
		return insertForeign(t, Namespaces.HTML);

	function insertFake(name:String):Element
		return insertHtml(new Tag(name, false, here));

	function insertChars(text:String, start:Int, end:Int) {
		if (text == "") return;
		place();
		if (textParent != null && (textParent != locParent || textRef != locRef)) flushText();
		var parent = locParent, ref = locRef;
		if (parent.nodeType == Node.DOCUMENT_NODE) return;
		if (ref != null && ref.parentNode != parent) return;
		if (textParent == null) {
			textParent = parent;
			textRef = ref;
			textFirst = text;
			textBuf = null;
			textStart = start;
		} else {
			if (textBuf == null) {
				textBuf = new StringBuf();
				textBuf.add(textFirst);
			}
			textBuf.add(text);
		}
		textEnd = end;
	}

	function flushText() {
		var parent = textParent;
		if (parent == null) return;
		textParent = null;
		var data = textBuf == null ? textFirst : textBuf.toString();
		textBuf = null;
		var ref = textRef;
		var prev = ref != null ? ref.previousSibling : parent.lastChild;
		if (prev != null && prev.nodeType == Node.TEXT_NODE) {
			var t:Text = cast prev;
			t.replaceData(t.value.length, 0, data);
			t.end = textEnd;
		} else {
			var t = new Text(parent.doc, data);
			t.start = textStart;
			t.end = textEnd;
			Node.insert(t, parent, ref);
		}
	}

	function insertComment(data:String, start:Int, end:Int, ?parent:Node) {
		if (parent != null) adjusted(parent, null) else place();
		var p = locParent, ref = locRef;
		if (ref != null && ref.parentNode != p) return;
		var c = new Comment(p.doc, data);
		c.start = start;
		c.end = end;
		Node.insert(c, p, ref);
	}

	function insertPi(target:String, data:String, start:Int, end:Int, ?parent:Node) {
		if (parent != null) adjusted(parent, null) else place();
		var p = locParent, ref = locRef;
		if (ref != null && ref.parentNode != p) return;
		var pi = new ProcessingInstruction(p.doc, target, data);
		pi.start = start;
		pi.end = end;
		Node.insert(pi, p, ref);
	}

	function addMissingAttrs(e:Element, t:Tag) {
		var a = t.attrs;
		if (a == null) return;
		var i = 0;
		while (i < a.length) {
			if (!e.hasAttribute(a[i])) e.appendAttr(new Attr(e.doc, a[i], a[i + 1]));
			i += 2;
		}
	}

	// the generic raw text and RCDATA element parsing algorithms
	function textElement(t:Tag, state:Int) {
		insertHtml(t);
		tokenizer.state = state;
		original = mode;
		mode = TEXT;
	}

	// --- the dispatcher

	static inline function isWs(c:Int):Bool
		return c == 0x20 || c == 0x0A || c == 0x09 || c == 0x0C || c == 0x0D;

	static function wsPrefix(s:String):Int {
		var i = 0;
		while (i < s.length && isWs(s.fastCodeAt(i)))
			i++;
		return i;
	}

	static inline function mathmlTextPoint(e:Element):Bool
		return e.ns == Element.MATHML && switch e.tag {
			case MI | MO | MN | MS | MTEXT: true;
			case _: false;
		}

	static function htmlPoint(e:Element):Bool {
		if (e.ns == Element.MATHML && e.tag == ANNOTATION_XML) {
			var enc = e.getAttributeNS(null, "encoding");
			if (enc == null) return false;
			enc = Names.lower(enc);
			return enc == "text/html" || enc == "application/xhtml+xml";
		}
		return e.ns == Element.SVG && (e.tag == FOREIGN_OBJECT || e.tag == DESC || e.tag == TITLE);
	}

	// the dispatcher's choice: HTML content's rules (else foreign content's)
	function htmlRules(t:Null<Tag>, chars:Bool):Bool {
		var a = adjustedCurrent();
		if (a == null || a.ns == Element.HTML) return true;
		var start = t != null && !t.end;
		if (mathmlTextPoint(a) && (chars || start && t.id != MGLYPH && t.id != MALIGNMARK)) return true;
		if (start && a.ns == Element.MATHML && a.tag == ANNOTATION_XML && t.name == "svg") return true;
		if (htmlPoint(a) && (start || chars)) return true;
		return false;
	}

	public function foreign():Bool {
		var a = adjustedCurrent();
		return a != null && a.ns != Element.HTML;
	}

	public function doctype(name:Null<String>, publicId:Null<String>, systemId:Null<String>, forceQuirks:Bool, start:Int, end:Int) {
		flushText();
		skipNewline = false;
		here = start;
		hereEnd = end;
		closing = null;
		if (mode == IN_TABLE_TEXT && htmlRules(null, false)) endTableText();
		if (!htmlRules(null, false) || mode != INITIAL) {
			error("unexpected-doctype");
			return;
		}
		if (name != "html" || publicId != null || systemId != null && systemId != "about:legacy-compat") error("non-conforming-doctype");
		var d = new DocumentType(doc, name ?? "", publicId ?? "", systemId ?? "");
		d.start = start;
		d.end = end;
		if (doc.doctype == null && doc.documentElement == null) Node.insert(d, doc, null);
		if (forceQuirks || name != "html" || quirksDoctype(publicId, systemId)) doc.mode = Quirks;
		else if (limitedQuirksDoctype(publicId, systemId)) doc.mode = LimitedQuirks;
		mode = BEFORE_HTML;
	}

	static function quirksDoctype(publicId:Null<String>, systemId:Null<String>):Bool {
		var pub = publicId == null ? null : Names.lower(publicId);
		var sys = systemId == null ? null : Names.lower(systemId);
		if (pub == "-//w3o//dtd w3 html strict 3.0//en//" || pub == "-/w3c/dtd html 4.0 transitional/en" || pub == "html") return true;
		if (sys == "http://www.ibm.com/data/dtd/v11/ibmxhtml1-transitional.dtd") return true;
		if (pub == null) return false;
		for (p in QUIRKS_PREFIXES)
			if (pub.startsWith(p)) return true;
		if ((systemId == null || systemId == "") && (pub.startsWith("-//w3c//dtd html 4.01 frameset//") || pub.startsWith("-//w3c//dtd html 4.01 transitional//")))
			return true;
		return false;
	}

	static function limitedQuirksDoctype(publicId:Null<String>, systemId:Null<String>):Bool {
		if (publicId == null) return false;
		var pub = Names.lower(publicId);
		if (pub.startsWith("-//w3c//dtd xhtml 1.0 frameset//") || pub.startsWith("-//w3c//dtd xhtml 1.0 transitional//")) return true;
		return systemId != null && systemId != "" && (pub.startsWith("-//w3c//dtd html 4.01 frameset//") || pub.startsWith("-//w3c//dtd html 4.01 transitional//"));
	}

	static final QUIRKS_PREFIXES = [
		"+//silmaril//dtd html pro v0r11 19970101//", "-//as//dtd html 3.0 aswedit + extensions//", "-//advasoft ltd//dtd html 3.0 aswedit + extensions//",
		"-//ietf//dtd html 2.0 level 1//", "-//ietf//dtd html 2.0 level 2//", "-//ietf//dtd html 2.0 strict level 1//", "-//ietf//dtd html 2.0 strict level 2//",
		"-//ietf//dtd html 2.0 strict//", "-//ietf//dtd html 2.0//", "-//ietf//dtd html 2.1e//", "-//ietf//dtd html 3.0//", "-//ietf//dtd html 3.2 final//",
		"-//ietf//dtd html 3.2//", "-//ietf//dtd html 3//", "-//ietf//dtd html level 0//", "-//ietf//dtd html level 1//", "-//ietf//dtd html level 2//",
		"-//ietf//dtd html level 3//", "-//ietf//dtd html strict level 0//", "-//ietf//dtd html strict level 1//", "-//ietf//dtd html strict level 2//",
		"-//ietf//dtd html strict level 3//", "-//ietf//dtd html strict//", "-//ietf//dtd html//", "-//metrius//dtd metrius presentational//",
		"-//microsoft//dtd internet explorer 2.0 html strict//", "-//microsoft//dtd internet explorer 2.0 html//", "-//microsoft//dtd internet explorer 2.0 tables//",
		"-//microsoft//dtd internet explorer 3.0 html strict//", "-//microsoft//dtd internet explorer 3.0 html//", "-//microsoft//dtd internet explorer 3.0 tables//",
		"-//netscape comm. corp.//dtd html//", "-//netscape comm. corp.//dtd strict html//", "-//o'reilly and associates//dtd html 2.0//",
		"-//o'reilly and associates//dtd html extended 1.0//", "-//o'reilly and associates//dtd html extended relaxed 1.0//",
		"-//sq//dtd html 2.0 hotmetal + extensions//", "-//softquad software//dtd hotmetal pro 6.0::19990601::extensions to html 4.0//",
		"-//softquad//dtd hotmetal pro 4.0::19971010::extensions to html 4.0//", "-//spyglass//dtd html 2.0 extended//", "-//sun microsystems corp.//dtd hotjava html//",
		"-//sun microsystems corp.//dtd hotjava strict html//", "-//w3c//dtd html 3 1995-03-24//", "-//w3c//dtd html 3.2 draft//", "-//w3c//dtd html 3.2 final//",
		"-//w3c//dtd html 3.2//", "-//w3c//dtd html 3.2s draft//", "-//w3c//dtd html 4.0 frameset//", "-//w3c//dtd html 4.0 transitional//",
		"-//w3c//dtd html experimental 19960712//", "-//w3c//dtd html experimental 970421//", "-//w3c//dtd w3 html//", "-//w3o//dtd w3 html 3.0//",
		"-//webtechs//dtd mozilla html 2.0//", "-//webtechs//dtd mozilla html//"
	];

	public function comment(data:String, start:Int, end:Int) {
		flushText();
		skipNewline = false;
		here = start;
		hereEnd = end;
		closing = null;
		if (!htmlRules(null, false)) {
			insertComment(data, start, end);
			return;
		}
		switch mode {
			case INITIAL | BEFORE_HTML | AFTER_AFTER_BODY | AFTER_AFTER_FRAMESET: insertComment(data, start, end, doc);
			case AFTER_BODY: insertComment(data, start, end, stack[0]);
			case IN_TABLE_TEXT:
				endTableText();
				comment(data, start, end);
			case _: insertComment(data, start, end);
		}
	}

	public function pi(target:String, data:String, start:Int, end:Int) {
		flushText();
		skipNewline = false;
		here = start;
		hereEnd = end;
		closing = null;
		if (!htmlRules(null, false)) {
			insertPi(target, data, start, end);
			return;
		}
		switch mode {
			case INITIAL | BEFORE_HTML | AFTER_AFTER_BODY | AFTER_AFTER_FRAMESET: insertPi(target, data, start, end, doc);
			case AFTER_BODY: insertPi(target, data, start, end, stack[0]);
			case IN_TABLE_TEXT:
				endTableText();
				pi(target, data, start, end);
			case _: insertPi(target, data, start, end);
		}
	}

	public function eof(at:Int) {
		flushText();
		here = hereEnd = at;
		closing = null;
		while (!stopped && eofIn(mode)) {}
		flushText();
		while (stack.length > 0)
			pop();
	}

	public function chars(text:String, start:Int, end:Int) {
		if (skipNewline) {
			skipNewline = false;
			if (text.fastCodeAt(0) == "\n".code) {
				if (text.length == 1) return;
				text = text.substr(1);
				start++;
			}
		}
		here = start;
		hereEnd = end;
		closing = null;
		var rest:Null<String> = text;
		while (rest != null && rest != "")
			rest = htmlRules(null, true) ? charsIn(mode, rest, start, end) : foreignChars(rest, start, end);
	}

	public function tag(t:Tag) {
		flushText();
		skipNewline = false;
		here = t.start;
		hereEnd = t.stop;
		closing = t.end ? t : null;
		if (t.end) {
			while (htmlRules(t, false) ? endIn(mode, t) : foreignEnd(t)) {}
		} else {
			while (htmlRules(t, false) ? startIn(mode, t) : foreignStart(t)) {}
			if (t.selfClosing && !t.acknowledged) error("non-void-html-element-start-tag-with-trailing-solidus");
		}
	}

	// --- character tokens: each mode's handling of a run, the rest to reprocess (null: none)

	function charsIn(m:Int, s:String, start:Int, end:Int):Null<String> {
		switch m {
			case INITIAL:
				var w = wsPrefix(s);
				if (w == s.length) return null;
				error("expected-doctype");
				doc.mode = Quirks;
				mode = BEFORE_HTML;
				return s.substr(w);
			case BEFORE_HTML:
				var w = wsPrefix(s);
				if (w == s.length) return null;
				beforeHtmlElse();
				return s.substr(w);
			case BEFORE_HEAD:
				var w = wsPrefix(s);
				if (w == s.length) return null;
				headElement = insertFake("head");
				mode = IN_HEAD;
				return s.substr(w);
			case IN_HEAD:
				var w = wsPrefix(s);
				insertChars(s.substr(0, w), start, end);
				if (w == s.length) return null;
				pop();
				mode = AFTER_HEAD;
				return s.substr(w);
			case IN_HEAD_NOSCRIPT:
				var w = wsPrefix(s);
				insertChars(s.substr(0, w), start, end);
				if (w == s.length) return null;
				error("unexpected-character");
				pop();
				mode = IN_HEAD;
				return s.substr(w);
			case AFTER_HEAD:
				var w = wsPrefix(s);
				insertChars(s.substr(0, w), start, end);
				if (w == s.length) return null;
				insertFake("body");
				framesetOk = true;
				mode = IN_BODY;
				return s.substr(w);
			case IN_BODY | IN_CAPTION | IN_CELL | IN_TEMPLATE:
				bodyChars(s, start, end);
				return null;
			case TEXT:
				insertChars(s, start, end);
				return null;
			case IN_TABLE | IN_TABLE_BODY | IN_ROW:
				if (current().ns == Element.HTML && switch current().tag {
					case TABLE | TBODY | TEMPLATE | TFOOT | THEAD | TR: true;
					case _: false;
				}) {
					tableText = new StringBuf();
					tableTextStart = start;
					tableTextSpaces = true;
					original = mode;
					mode = IN_TABLE_TEXT;
					return s;
				}
				error("unexpected-character-in-table");
				fosterParenting = true;
				bodyChars(s, start, end);
				fosterParenting = false;
				return null;
			case IN_TABLE_TEXT:
				if (s == "\x00") {
					error("unexpected-null-character");
					return null;
				}
				tableText.add(s);
				tableTextEnd = end;
				if (tableTextSpaces && wsPrefix(s) < s.length) tableTextSpaces = false;
				return null;
			case IN_COLUMN_GROUP:
				var w = wsPrefix(s);
				insertChars(s.substr(0, w), start, end);
				if (w == s.length) return null;
				if (!currentIs(COLGROUP)) {
					// (each character its own token: the white space among them inserted)
					error("unexpected-character");
					insertChars(spaces(s.substr(w)), start, end);
					return null;
				}
				pop();
				mode = IN_TABLE;
				return s.substr(w);
			case AFTER_BODY | AFTER_AFTER_BODY:
				var w = wsPrefix(s);
				if (w > 0) bodyChars(s.substr(0, w), start, end);
				if (w == s.length) return null;
				error("unexpected-character-after-body");
				mode = IN_BODY;
				return s.substr(w);
			case IN_FRAMESET | AFTER_FRAMESET:
				if (wsPrefix(s) < s.length) error("unexpected-character-in-frameset");
				insertChars(spaces(s), start, end);
				return null;
			case AFTER_AFTER_FRAMESET:
				if (wsPrefix(s) < s.length) error("unexpected-character-in-frameset");
				var w = spaces(s);
				if (w != "") bodyChars(w, start, end);
				return null;
			case _:
				return null;
		}
	}

	// the white space characters of s
	static function spaces(s:String):String {
		var buf = new StringBuf();
		for (i in 0...s.length)
			if (isWs(s.fastCodeAt(i))) buf.addChar(s.fastCodeAt(i));
		return buf.toString();
	}

	function bodyChars(s:String, start:Int, end:Int) {
		if (s == "\x00") {
			error("unexpected-null-character");
			return;
		}
		reconstruct();
		insertChars(s, start, end);
		if (framesetOk && wsPrefix(s) < s.length) framesetOk = false;
	}

	// the in table text mode's "anything else": its characters inserted, then the token reprocessed
	function endTableText() {
		var text = tableText.toString();
		tableText = null;
		if (!tableTextSpaces) {
			error("unexpected-character-in-table");
			fosterParenting = true;
			bodyChars(text, tableTextStart, tableTextEnd);
			fosterParenting = false;
		} else insertChars(text, tableTextStart, tableTextEnd);
		flushText();
		mode = original;
	}

	function foreignChars(s:String, start:Int, end:Int):Null<String> {
		if (s == "\x00") {
			error("unexpected-null-character");
			insertChars("\u{FFFD}", start, end);
			return null;
		}
		insertChars(s, start, end);
		if (framesetOk && wsPrefix(s) < s.length) framesetOk = false;
		return null;
	}

	// --- end of file: true to reprocess

	function eofIn(m:Int):Bool {
		switch m {
			case INITIAL:
				error("expected-doctype");
				doc.mode = Quirks;
				mode = BEFORE_HTML;
				return true;
			case BEFORE_HTML:
				beforeHtmlElse();
				return true;
			case BEFORE_HEAD:
				headElement = insertFake("head");
				mode = IN_HEAD;
				return true;
			case IN_HEAD:
				pop();
				mode = AFTER_HEAD;
				return true;
			case IN_HEAD_NOSCRIPT:
				error("eof-in-noscript");
				pop();
				mode = IN_HEAD;
				return true;
			case AFTER_HEAD:
				insertFake("body");
				framesetOk = true;
				mode = IN_BODY;
				return true;
			case IN_BODY | IN_TABLE | IN_CAPTION | IN_COLUMN_GROUP | IN_TABLE_BODY | IN_ROW | IN_CELL:
				if (templateModes.length > 0) return eofIn(IN_TEMPLATE);
				stopped = true;
				return false;
			case TEXT:
				error("eof-in-text");
				pop();
				mode = original;
				return true;
			case IN_TABLE_TEXT:
				endTableText();
				return true;
			case IN_TEMPLATE:
				if (!hasTemplate()) {
					stopped = true;
					return false;
				}
				error("eof-in-template");
				popUntil(TEMPLATE);
				clearToMarker();
				templateModes.pop();
				reset();
				return true;
			case _:
				stopped = true;
				return false;
		}
	}

	function beforeHtmlElse() {
		var e = Element.create(doc, "html", Namespaces.HTML);
		e.start = here;
		adjusted(doc, null);
		insertAt(e);
		stack.push(e);
		mode = BEFORE_HEAD;
	}

	// --- start tags: true to reprocess

	function startIn(m:Int, t:Tag):Bool {
		switch m {
			case INITIAL:
				error("expected-doctype");
				doc.mode = Quirks;
				mode = BEFORE_HTML;
				return true;
			case BEFORE_HTML:
				if (t.id == HTML) {
					var e = create(t, Namespaces.HTML, doc);
					adjusted(doc, null);
					insertAt(e);
					stack.push(e);
					mode = BEFORE_HEAD;
					return false;
				}
				beforeHtmlElse();
				return true;
			case BEFORE_HEAD:
				if (t.id == HTML) return startIn(IN_BODY, t);
				if (t.id == HEAD) {
					headElement = insertHtml(t);
					mode = IN_HEAD;
					return false;
				}
				headElement = insertFake("head");
				mode = IN_HEAD;
				return true;
			case IN_HEAD:
				return headStart(t);
			case IN_HEAD_NOSCRIPT:
				switch t.id {
					case HTML: return startIn(IN_BODY, t);
					case BASEFONT | BGSOUND | LINK | META | NOFRAMES | STYLE: return headStart(t);
					case HEAD | NOSCRIPT:
						error("unexpected-start-tag");
						return false;
					case _:
						error("unexpected-start-tag");
						pop();
						mode = IN_HEAD;
						return true;
				}
			case AFTER_HEAD:
				switch t.id {
					case HTML: return startIn(IN_BODY, t);
					case BODY:
						insertHtml(t);
						framesetOk = false;
						mode = IN_BODY;
						return false;
					case FRAMESET:
						insertHtml(t);
						mode = IN_FRAMESET;
						return false;
					case BASE | BASEFONT | BGSOUND | LINK | META | NOFRAMES | SCRIPT | STYLE | TEMPLATE | TITLE:
						error("unexpected-start-tag");
						var head = headElement;
						stack.push(head);
						var again = headStart(t);
						var i = stack.lastIndexOf(head);
						if (i >= 0) stack.splice(i, 1);
						return again;
					case HEAD:
						error("unexpected-start-tag");
						return false;
					case _:
						insertFake("body");
						framesetOk = true;
						mode = IN_BODY;
						return true;
				}
			case IN_BODY:
				return bodyStart(t);
			case TEXT:
				return false;
			case IN_TABLE:
				return tableStart(t);
			case IN_TABLE_TEXT:
				endTableText();
				return true;
			case IN_CAPTION:
				switch t.id {
					case CAPTION | COL | COLGROUP | TBODY | TD | TFOOT | TH | THEAD | TR:
						return closeCaption();
					case _:
						return bodyStart(t);
				}
			case IN_COLUMN_GROUP:
				switch t.id {
					case HTML: return bodyStart(t);
					case COL:
						insertHtml(t);
						pop();
						t.acknowledged = true;
						return false;
					case TEMPLATE: return headStart(t);
					case _:
						if (!currentIs(COLGROUP)) {
							error("unexpected-start-tag");
							return false;
						}
						pop();
						mode = IN_TABLE;
						return true;
				}
			case IN_TABLE_BODY:
				switch t.id {
					case TR:
						clearBackTo(TABLE_BODY_CONTEXT);
						insertHtml(t);
						mode = IN_ROW;
						return false;
					case TH | TD:
						error("unexpected-cell");
						clearBackTo(TABLE_BODY_CONTEXT);
						insertFake("tr");
						mode = IN_ROW;
						return true;
					case CAPTION | COL | COLGROUP | TBODY | TFOOT | THEAD:
						return closeTableBody();
					case _:
						return tableStart(t);
				}
			case IN_ROW:
				switch t.id {
					case TH | TD:
						clearBackTo(ROW_CONTEXT);
						insertHtml(t);
						mode = IN_CELL;
						insertMarker();
						return false;
					case CAPTION | COL | COLGROUP | TBODY | TFOOT | THEAD | TR:
						return closeRow();
					case _:
						return tableStart(t);
				}
			case IN_CELL:
				switch t.id {
					case CAPTION | COL | COLGROUP | TBODY | TD | TFOOT | TH | THEAD | TR:
						if (!inScope(TD, TABLE_SCOPE) && !inScope(TH, TABLE_SCOPE)) {
							error("unexpected-start-tag");
							return false;
						}
						closeCell();
						return true;
					case _:
						return bodyStart(t);
				}
			case IN_TEMPLATE:
				switch t.id {
					case BASE | BASEFONT | BGSOUND | LINK | META | NOFRAMES | SCRIPT | STYLE | TEMPLATE | TITLE:
						return headStart(t);
					case CAPTION | COLGROUP | TBODY | TFOOT | THEAD:
						switchTemplate(IN_TABLE);
					case COL:
						switchTemplate(IN_COLUMN_GROUP);
					case TR:
						switchTemplate(IN_TABLE_BODY);
					case TD | TH:
						switchTemplate(IN_ROW);
					case _:
						switchTemplate(IN_BODY);
				}
				return true;
			case AFTER_BODY:
				if (t.id == HTML) return bodyStart(t);
				error("unexpected-start-tag-after-body");
				mode = IN_BODY;
				return true;
			case IN_FRAMESET:
				switch t.id {
					case HTML: return bodyStart(t);
					case FRAMESET:
						insertHtml(t);
					case FRAME:
						insertHtml(t);
						pop();
						t.acknowledged = true;
					case NOFRAMES:
						return headStart(t);
					case _:
						error("unexpected-start-tag-in-frameset");
				}
				return false;
			case AFTER_FRAMESET:
				switch t.id {
					case HTML: return bodyStart(t);
					case NOFRAMES: return headStart(t);
					case _: error("unexpected-start-tag-after-frameset");
				}
				return false;
			case AFTER_AFTER_BODY:
				if (t.id == HTML) return bodyStart(t);
				error("unexpected-start-tag-after-body");
				mode = IN_BODY;
				return true;
			case AFTER_AFTER_FRAMESET:
				switch t.id {
					case HTML: return bodyStart(t);
					case NOFRAMES: return headStart(t);
					case _: error("unexpected-start-tag-after-frameset");
				}
				return false;
			case _:
				return false;
		}
	}

	function switchTemplate(m:Int) {
		templateModes.pop();
		templateModes.push(m);
		mode = m;
	}

	function headStart(t:Tag):Bool {
		switch t.id {
			case HTML:
				return bodyStart(t);
			case BASE | BASEFONT | BGSOUND | LINK | META:
				insertHtml(t);
				pop();
				t.acknowledged = true;
			case TITLE:
				textElement(t, Tokenizer.RCDATA);
			case NOFRAMES | STYLE:
				textElement(t, Tokenizer.RAWTEXT);
			case NOSCRIPT:
				insertHtml(t);
				mode = IN_HEAD_NOSCRIPT;
			case SCRIPT:
				flushText();
				place();
				var e = create(t, Namespaces.HTML, locParent);
				place();
				insertAt(e);
				stack.push(e);
				tokenizer.state = Tokenizer.SCRIPT_DATA;
				original = mode;
				mode = TEXT;
			case TEMPLATE:
				templateStart(t);
			case HEAD:
				error("unexpected-start-tag");
			case _:
				pop();
				mode = AFTER_HEAD;
				return true;
		}
		return false;
	}

	function templateStart(t:Tag) {
		insertMarker();
		framesetOk = false;
		mode = IN_TEMPLATE;
		templateModes.push(IN_TEMPLATE);
		place();
		var template:HTMLTemplateElement = cast create(t, Namespaces.HTML, locParent);
		place();
		var parent = locParent, ref = locRef;
		stack.push(template);
		var shadow = t.attr("shadowrootmode");
		if (shadow != null && (Names.lower(shadow) == "open" || Names.lower(shadow) == "closed") || t.attr("for") == null) {
			insertAt(template);
			return;
		}
		var scope = parent;
		if (ref != null && ref.parentNode != scope) return;
		if (scope.nodeType == Node.ELEMENT_NODE && scope == scope.doc.body && stack.contains(cast scope)) scope = scope.parentNode;
		if (scope != null && scope.nodeType != Node.DOCUMENT_NODE) patch(scope, template);
		locParent = parent;
		locRef = ref;
		insertAt(template);
	}

	// prepare content patching: the template's children go between its markers in scope
	function patch(scope:Node, template:HTMLTemplateElement):Bool {
		var name = template.getAttribute("for");
		if (name == null || name == "") return false;
		var start:Null<ProcessingInstruction> = null, end:Null<ProcessingInstruction> = null;
		// find markers
		var n = scope.firstChild;
		while (n != null && start == null) {
			if (n.nodeType == Node.PROCESSING_INSTRUCTION_NODE) {
				var pi:ProcessingInstruction = cast n;
				if (pi.getAttribute("name") == name) {
					if (pi.target == "marker") {
						start = end = pi;
						break;
					}
					if (pi.target == "start") {
						start = pi;
						var depth = 0, s = pi.nextSibling;
						while (s != null) {
							if (s.nodeType == Node.PROCESSING_INSTRUCTION_NODE) {
								var target = (cast s : ProcessingInstruction).target;
								if (target == "start") depth++;
								if (target == "end") {
									if (depth == 0) {
										end = cast s;
										break;
									}
									depth--;
								}
							}
							s = s.nextSibling;
						}
						break;
					}
				}
			}
			n = Node.following(n, scope);
		}
		if (start == null) return false;
		template.insertionTarget = start.parentNode;
		template.startMarker = start;
		template.endMarker = end;
		if (start == end) return true;
		var removed = [], c = start.nextSibling;
		while (c != null && c != end) {
			removed.push(c);
			c = c.nextSibling;
		}
		for (r in removed)
			if (r.parentNode != null) Node.remove(r);
		return true;
	}

	function templateEnd() {
		if (!hasTemplate()) {
			error("unexpected-end-tag");
			return;
		}
		generateAllImplied();
		if (!currentIs(TEMPLATE)) error("unexpected-end-tag");
		var i = stack.length - 1;
		while (!isHtml(stack[i], TEMPLATE))
			i--;
		var template:HTMLTemplateElement = cast stack[i];
		if (template.insertionTarget != null) {
			var s = template.startMarker, e = template.endMarker;
			if (s != null && s.parentNode != null) Node.remove(s);
			if (e != null && e.parentNode != null) Node.remove(e);
			template.insertionTarget = null;
			template.startMarker = template.endMarker = null;
		}
		popUntil(TEMPLATE);
		clearToMarker();
		templateModes.pop();
		reset();
	}

	function bodyStart(t:Tag):Bool {
		switch t.id {
			case HTML:
				error("unexpected-start-tag");
				if (!hasTemplate()) addMissingAttrs(stack[0], t);
			case BASE | BASEFONT | BGSOUND | LINK | META | NOFRAMES | SCRIPT | STYLE | TEMPLATE | TITLE:
				return headStart(t);
			case BODY:
				error("unexpected-start-tag");
				if (stack.length > 1 && isHtml(stack[1], BODY) && !hasTemplate()) {
					framesetOk = false;
					addMissingAttrs(stack[1], t);
				}
			case FRAMESET:
				error("unexpected-start-tag");
				if (stack.length == 1 || !isHtml(stack[1], BODY) || !framesetOk) return false;
				var body = stack[1];
				if (body.parentNode != null) Node.remove(body);
				while (stack.length > 1)
					pop();
				insertHtml(t);
				mode = IN_FRAMESET;
			case ADDRESS | ARTICLE | ASIDE | BLOCKQUOTE | CENTER | DETAILS | DIALOG | DIR | DIV | DL | FIELDSET | FIGCAPTION | FIGURE | FOOTER | HEADER | HGROUP
				| MAIN | MENU | NAV | OL | P | SEARCH | SECTION | SUMMARY | UL:
				closePInButtonScope();
				insertHtml(t);
			case H1 | H2 | H3 | H4 | H5 | H6:
				closePInButtonScope();
				if (current().ns == Element.HTML && current().tag >= H1 && current().tag <= H6) {
					error("unexpected-start-tag");
					pop();
				}
				insertHtml(t);
			case PRE | LISTING:
				closePInButtonScope();
				insertHtml(t);
				skipNewline = true;
				framesetOk = false;
			case FORM:
				var template = parsingTemplate();
				if (formElement != null && !template) {
					error("unexpected-start-tag");
					return false;
				}
				closePInButtonScope();
				var e = insertHtml(t);
				if (!template) formElement = e;
			case LI | DD | DT:
				framesetOk = false;
				var i = stack.length - 1;
				while (i >= 0) {
					var node = stack[i];
					var hit = t.id == LI ? isHtml(node, LI) : isHtml(node, DD) || isHtml(node, DT);
					if (hit) {
						generateImplied(node.tag);
						if (!currentIs(node.tag)) error("unexpected-start-tag");
						popUntil(node.tag);
						break;
					}
					if (isSpecial(node) && !isHtml(node, ADDRESS) && !isHtml(node, DIV) && !isHtml(node, P)) break;
					i--;
				}
				closePInButtonScope();
				insertHtml(t);
			case PLAINTEXT:
				closePInButtonScope();
				insertHtml(t);
				tokenizer.state = Tokenizer.PLAINTEXT;
			case BUTTON:
				if (inScope(BUTTON)) {
					error("unexpected-start-tag");
					generateImplied();
					popUntil(BUTTON);
				}
				reconstruct();
				insertHtml(t);
				framesetOk = false;
			case A:
				var i = active.length - 1;
				while (i >= 0 && active[i] != null) {
					var e = active[i];
					if (isHtml(e, A)) {
						error("unexpected-start-tag");
						if (adoptionAgency(new Tag("a", true, t.start))) anyOtherEnd(new Tag("a", true, t.start));
						var k = active.indexOf(e);
						if (k >= 0) {
							active.splice(k, 1);
							activeTags.splice(k, 1);
						}
						removeFromStack(e);
						break;
					}
					i--;
				}
				reconstruct();
				pushActive(insertHtml(t), t);
			case B | BIG | CODE | EM | FONT | I | S | SMALL | STRIKE | STRONG | TT | U:
				reconstruct();
				pushActive(insertHtml(t), t);
			case NOBR:
				reconstruct();
				if (inScope(NOBR)) {
					error("unexpected-start-tag");
					if (adoptionAgency(new Tag("nobr", true, t.start))) anyOtherEnd(new Tag("nobr", true, t.start));
					reconstruct();
				}
				pushActive(insertHtml(t), t);
			case APPLET | MARQUEE | OBJECT:
				reconstruct();
				insertHtml(t);
				insertMarker();
				framesetOk = false;
			case TABLE:
				if (doc.mode != Quirks) closePInButtonScope();
				insertHtml(t);
				framesetOk = false;
				mode = IN_TABLE;
			case AREA | BR | EMBED | IMG | KEYGEN | WBR:
				reconstruct();
				insertHtml(t);
				pop();
				t.acknowledged = true;
				framesetOk = false;
			case INPUT:
				if (context != null && context.isHTML(SELECT)) {
					error("unexpected-start-tag");
					return false;
				}
				if (inScope(SELECT)) {
					error("unexpected-start-tag");
					popUntil(SELECT);
				}
				reconstruct();
				insertHtml(t);
				pop();
				t.acknowledged = true;
				var type = t.attr("type");
				if (type == null || Names.lower(type) != "hidden") framesetOk = false;
			case PARAM | SOURCE | TRACK:
				insertHtml(t);
				pop();
				t.acknowledged = true;
			case HR:
				closePInButtonScope();
				if (inScope(SELECT)) {
					generateImplied();
					if (inScope(OPTION) || inScope(OPTGROUP)) error("unexpected-start-tag");
				}
				insertHtml(t);
				pop();
				t.acknowledged = true;
				framesetOk = false;
			case IMAGE:
				error("unexpected-start-tag");
				t.name = "img";
				t.id = IMG;
				return true;
			case TEXTAREA:
				insertHtml(t);
				skipNewline = true;
				tokenizer.state = Tokenizer.RCDATA;
				original = mode;
				framesetOk = false;
				mode = TEXT;
			case XMP:
				closePInButtonScope();
				reconstruct();
				framesetOk = false;
				textElement(t, Tokenizer.RAWTEXT);
			case IFRAME:
				framesetOk = false;
				textElement(t, Tokenizer.RAWTEXT);
			case NOEMBED:
				textElement(t, Tokenizer.RAWTEXT);
			case SELECT:
				if (context != null && context.isHTML(SELECT)) {
					error("unexpected-start-tag");
				} else if (inScope(SELECT)) {
					error("unexpected-start-tag");
					popUntil(SELECT);
				} else {
					reconstruct();
					insertHtml(t);
					framesetOk = false;
				}
			case OPTION:
				if (inScope(SELECT)) {
					generateImplied(OPTGROUP);
					if (inScope(OPTION)) error("unexpected-start-tag");
				} else if (currentIs(OPTION)) pop();
				reconstruct();
				insertHtml(t);
			case OPTGROUP:
				if (inScope(SELECT)) {
					generateImplied();
					if (inScope(OPTION) || inScope(OPTGROUP)) error("unexpected-start-tag");
				} else if (currentIs(OPTION)) pop();
				reconstruct();
				insertHtml(t);
			case RB | RTC:
				if (inScope(RUBY)) {
					generateImplied();
					if (!currentIs(RUBY)) error("unexpected-start-tag");
				}
				insertHtml(t);
			case RP | RT:
				if (inScope(RUBY)) {
					generateImplied(RTC);
					if (!currentIs(RTC) && !currentIs(RUBY)) error("unexpected-start-tag");
				}
				insertHtml(t);
			case MATH | SVG:
				reconstruct();
				insertForeign(t, t.id == MATH ? Namespaces.MATHML : Namespaces.SVG);
				if (t.selfClosing) {
					pop();
					t.acknowledged = true;
				}
			case CAPTION | COL | COLGROUP | FRAME | HEAD | TBODY | TD | TFOOT | TH | THEAD | TR:
				error("unexpected-start-tag");
			case _:
				reconstruct();
				insertHtml(t);
		}
		return false;
	}

	function tableStart(t:Tag):Bool {
		switch t.id {
			case CAPTION:
				clearBackTo(TABLE_CONTEXT);
				insertMarker();
				insertHtml(t);
				mode = IN_CAPTION;
			case COLGROUP:
				clearBackTo(TABLE_CONTEXT);
				insertHtml(t);
				mode = IN_COLUMN_GROUP;
			case COL:
				clearBackTo(TABLE_CONTEXT);
				insertFake("colgroup");
				mode = IN_COLUMN_GROUP;
				return true;
			case TBODY | TFOOT | THEAD:
				clearBackTo(TABLE_CONTEXT);
				insertHtml(t);
				mode = IN_TABLE_BODY;
			case TD | TH | TR:
				clearBackTo(TABLE_CONTEXT);
				insertFake("tbody");
				mode = IN_TABLE_BODY;
				return true;
			case TABLE:
				error("unexpected-start-tag");
				if (!inScope(TABLE, TABLE_SCOPE)) return false;
				popUntil(TABLE);
				reset();
				return true;
			case STYLE | SCRIPT | TEMPLATE:
				return headStart(t);
			case INPUT if (t.attr("type") != null && Names.lower(t.attr("type")) == "hidden"):
				error("unexpected-start-tag");
				insertHtml(t);
				pop();
				t.acknowledged = true;
			case FORM:
				error("unexpected-start-tag");
				var template = parsingTemplate();
				if (formElement != null && !template) return false;
				var e = insertHtml(t);
				if (!template) formElement = e;
				pop();
			case _:
				error("unexpected-start-tag-in-table");
				fosterParenting = true;
				var again = bodyStart(t);
				fosterParenting = false;
				return again;
		}
		return false;
	}

	function closeCaption():Bool {
		if (!inScope(CAPTION, TABLE_SCOPE)) {
			error("unexpected-tag");
			return false;
		}
		generateImplied();
		if (!currentIs(CAPTION)) error("unexpected-tag");
		popUntil(CAPTION);
		clearToMarker();
		mode = IN_TABLE;
		return true;
	}

	function closeTableBody():Bool {
		if (!inScope(TBODY, TABLE_SCOPE) && !inScope(THEAD, TABLE_SCOPE) && !inScope(TFOOT, TABLE_SCOPE)) {
			error("unexpected-tag");
			return false;
		}
		clearBackTo(TABLE_BODY_CONTEXT);
		pop();
		mode = IN_TABLE;
		return true;
	}

	function closeRow():Bool {
		if (!inScope(TR, TABLE_SCOPE)) {
			error("unexpected-tag");
			return false;
		}
		clearBackTo(ROW_CONTEXT);
		pop();
		mode = IN_TABLE_BODY;
		return true;
	}

	function closeCell() {
		generateImplied();
		if (!currentIs(TD) && !currentIs(TH)) error("unexpected-tag");
		while (stack.length > 0) {
			var e = pop();
			if (isHtml(e, TD) || isHtml(e, TH)) break;
		}
		clearToMarker();
		mode = IN_ROW;
	}

	// --- end tags: true to reprocess

	function endIn(m:Int, t:Tag):Bool {
		switch m {
			case INITIAL:
				error("expected-doctype");
				doc.mode = Quirks;
				mode = BEFORE_HTML;
				return true;
			case BEFORE_HTML:
				switch t.id {
					case HEAD | BODY | HTML | BR:
						beforeHtmlElse();
						return true;
					case _:
						error("unexpected-end-tag");
						return false;
				}
			case BEFORE_HEAD:
				switch t.id {
					case HEAD | BODY | HTML | BR:
						headElement = insertFake("head");
						mode = IN_HEAD;
						return true;
					case _:
						error("unexpected-end-tag");
						return false;
				}
			case IN_HEAD:
				return headEnd(t);
			case IN_HEAD_NOSCRIPT:
				switch t.id {
					case NOSCRIPT:
						pop();
						mode = IN_HEAD;
						return false;
					case BR:
						error("unexpected-end-tag");
						pop();
						mode = IN_HEAD;
						return true;
					case _:
						error("unexpected-end-tag");
						return false;
				}
			case AFTER_HEAD:
				switch t.id {
					case TEMPLATE:
						templateEnd();
						return false;
					case BODY | HTML | BR:
						insertFake("body");
						framesetOk = true;
						mode = IN_BODY;
						return true;
					case _:
						error("unexpected-end-tag");
						return false;
				}
			case IN_BODY:
				return bodyEnd(t);
			case TEXT:
				pop();
				mode = original;
				return false;
			case IN_TABLE:
				return tableEnd(t);
			case IN_TABLE_TEXT:
				endTableText();
				return true;
			case IN_CAPTION:
				switch t.id {
					case CAPTION:
						closeCaption();
						return false;
					case TABLE:
						return closeCaption();
					case BODY | COL | COLGROUP | HTML | TBODY | TD | TFOOT | TH | THEAD | TR:
						error("unexpected-end-tag");
						return false;
					case _:
						return bodyEnd(t);
				}
			case IN_COLUMN_GROUP:
				switch t.id {
					case COLGROUP:
						if (!currentIs(COLGROUP)) {
							error("unexpected-end-tag");
							return false;
						}
						pop();
						mode = IN_TABLE;
						return false;
					case COL:
						error("unexpected-end-tag");
						return false;
					case TEMPLATE:
						templateEnd();
						return false;
					case _:
						if (!currentIs(COLGROUP)) {
							error("unexpected-end-tag");
							return false;
						}
						pop();
						mode = IN_TABLE;
						return true;
				}
			case IN_TABLE_BODY:
				switch t.id {
					case TBODY | TFOOT | THEAD:
						if (!inScope(t.id, TABLE_SCOPE)) {
							error("unexpected-end-tag");
							return false;
						}
						clearBackTo(TABLE_BODY_CONTEXT);
						pop();
						mode = IN_TABLE;
						return false;
					case TABLE:
						return closeTableBody();
					case BODY | CAPTION | COL | COLGROUP | HTML | TD | TH | TR:
						error("unexpected-end-tag");
						return false;
					case _:
						return tableEnd(t);
				}
			case IN_ROW:
				switch t.id {
					case TR:
						closeRow();
						return false;
					case TABLE:
						return closeRow();
					case TBODY | TFOOT | THEAD:
						if (!inScope(t.id, TABLE_SCOPE)) {
							error("unexpected-end-tag");
							return false;
						}
						if (!inScope(TR, TABLE_SCOPE)) return false;
						return closeRow();
					case BODY | CAPTION | COL | COLGROUP | HTML | TD | TH:
						error("unexpected-end-tag");
						return false;
					case _:
						return tableEnd(t);
				}
			case IN_CELL:
				switch t.id {
					case TD | TH:
						if (!inScope(t.id, TABLE_SCOPE)) {
							error("unexpected-end-tag");
							return false;
						}
						generateImplied();
						if (!currentIs(t.id)) error("unexpected-end-tag");
						popUntil(t.id);
						clearToMarker();
						mode = IN_ROW;
						return false;
					case BODY | CAPTION | COL | COLGROUP | HTML:
						error("unexpected-end-tag");
						return false;
					case TABLE | TBODY | TFOOT | THEAD | TR:
						if (!inScope(t.id, TABLE_SCOPE)) {
							error("unexpected-end-tag");
							return false;
						}
						closeCell();
						return true;
					case _:
						return bodyEnd(t);
				}
			case IN_TEMPLATE:
				if (t.id == TEMPLATE) templateEnd() else error("unexpected-end-tag");
				return false;
			case AFTER_BODY:
				if (t.id == HTML) {
					if (context != null) error("unexpected-end-tag") else mode = AFTER_AFTER_BODY;
					return false;
				}
				error("unexpected-end-tag-after-body");
				mode = IN_BODY;
				return true;
			case IN_FRAMESET:
				if (t.id == FRAMESET) {
					if (current() == stack[0]) {
						error("unexpected-end-tag");
						return false;
					}
					pop();
					if (context == null && !currentIs(FRAMESET)) mode = AFTER_FRAMESET;
				} else error("unexpected-end-tag-in-frameset");
				return false;
			case AFTER_FRAMESET:
				if (t.id == HTML) mode = AFTER_AFTER_FRAMESET else error("unexpected-end-tag-after-frameset");
				return false;
			case AFTER_AFTER_BODY:
				error("unexpected-end-tag-after-body");
				mode = IN_BODY;
				return true;
			case AFTER_AFTER_FRAMESET:
				error("unexpected-end-tag-after-frameset");
				return false;
			case _:
				return false;
		}
	}

	function headEnd(t:Tag):Bool {
		switch t.id {
			case HEAD:
				pop();
				mode = AFTER_HEAD;
				return false;
			case BODY | HTML | BR:
				pop();
				mode = AFTER_HEAD;
				return true;
			case TEMPLATE:
				templateEnd();
				return false;
			case _:
				error("unexpected-end-tag");
				return false;
		}
	}

	// the stack has only elements allowed open at the body's end
	function checkOpenAtEnd() {
		if (errors == null) return;
		for (e in stack)
			if (!(implied(e, true) && !isHtml(e, CAPTION) && !isHtml(e, COLGROUP) || isHtml(e, BODY) || isHtml(e, HTML))) {
				error("end-tag-with-open-elements");
				return;
			}
	}

	function bodyEnd(t:Tag):Bool {
		switch t.id {
			case TEMPLATE:
				templateEnd();
			case BODY | HTML:
				if (!inScope(BODY)) {
					error("unexpected-end-tag");
					return false;
				}
				checkOpenAtEnd();
				mode = AFTER_BODY;
				return t.id == HTML;
			case ADDRESS | ARTICLE | ASIDE | BLOCKQUOTE | BUTTON | CENTER | DETAILS | DIALOG | DIR | DIV | DL | FIELDSET | FIGCAPTION | FIGURE | FOOTER | HEADER
				| HGROUP | LISTING | MAIN | MENU | NAV | OL | PRE | SEARCH | SECTION | SELECT | SUMMARY | UL:
				if (!inScope(t.id)) {
					error("unexpected-end-tag");
					return false;
				}
				generateImplied();
				if (!currentIs(t.id)) error("unexpected-end-tag");
				popUntil(t.id);
			case FORM:
				if (!parsingTemplate()) {
					var node = formElement;
					formElement = null;
					if (node == null || !elementInScope(node)) {
						error("unexpected-end-tag");
						return false;
					}
					generateImplied();
					if (current() != node) error("unexpected-end-tag");
					removeFromStack(node);
				} else {
					if (!inScope(FORM)) {
						error("unexpected-end-tag");
						return false;
					}
					generateImplied();
					if (!currentIs(FORM)) error("unexpected-end-tag");
					popUntil(FORM);
				}
			case P:
				if (!inScope(P, BUTTON_SCOPE)) {
					error("unexpected-end-tag");
					insertFake("p");
				}
				closeP();
			case LI:
				if (!inScope(LI, LIST_SCOPE)) {
					error("unexpected-end-tag");
					return false;
				}
				generateImplied(LI);
				if (!currentIs(LI)) error("unexpected-end-tag");
				popUntil(LI);
			case DD | DT:
				if (!inScope(t.id)) {
					error("unexpected-end-tag");
					return false;
				}
				generateImplied(t.id);
				if (!currentIs(t.id)) error("unexpected-end-tag");
				popUntil(t.id);
			case H1 | H2 | H3 | H4 | H5 | H6:
				if (!headingInScope()) {
					error("unexpected-end-tag");
					return false;
				}
				generateImplied();
				if (!currentIs(t.id)) error("unexpected-end-tag");
				while (stack.length > 0) {
					var e = pop();
					if (e.ns == Element.HTML && e.tag >= H1 && e.tag <= H6) break;
				}
			case A | B | BIG | CODE | EM | FONT | I | NOBR | S | SMALL | STRIKE | STRONG | TT | U:
				if (adoptionAgency(t)) anyOtherEnd(t);
			case APPLET | MARQUEE | OBJECT:
				if (!inScope(t.id)) {
					error("unexpected-end-tag");
					return false;
				}
				generateImplied();
				if (!currentIs(t.id)) error("unexpected-end-tag");
				popUntil(t.id);
				clearToMarker();
			case BR:
				error("unexpected-end-tag");
				reconstruct();
				insertFake("br");
				pop();
				framesetOk = false;
			case _:
				anyOtherEnd(t);
		}
		return false;
	}

	function anyOtherEnd(t:Tag) {
		var i = stack.length - 1;
		while (i >= 0) {
			var node = stack[i];
			if (node.ns == Element.HTML && node.localName == t.name) {
				generateImplied(t.id == OTHER ? -1 : t.id, t.name);
				if (node != current()) error("unexpected-end-tag");
				popUntilElement(node);
				return;
			}
			if (isSpecial(node)) {
				error("unexpected-end-tag");
				return;
			}
			i--;
		}
	}

	function tableEnd(t:Tag):Bool {
		switch t.id {
			case TABLE:
				if (!inScope(TABLE, TABLE_SCOPE)) {
					error("unexpected-end-tag");
					return false;
				}
				popUntil(TABLE);
				reset();
				return false;
			case BODY | CAPTION | COL | COLGROUP | HTML | TBODY | TD | TFOOT | TH | THEAD | TR:
				error("unexpected-end-tag");
				return false;
			case TEMPLATE:
				templateEnd();
				return false;
			case _:
				error("unexpected-end-tag-in-table");
				fosterParenting = true;
				var again = bodyEnd(t);
				fosterParenting = false;
				return again;
		}
	}

	// the adoption agency algorithm: true when its token is to be handled as any other end tag
	function adoptionAgency(t:Tag):Bool {
		var subject = t.name;
		var cur = current();
		if (cur.ns == Element.HTML && cur.localName == subject && !active.contains(cur)) {
			pop();
			return false;
		}
		for (_ in 0...8) {
			var fi = active.length - 1;
			while (fi >= 0 && active[fi] != null && active[fi].localName != subject)
				fi--;
			if (fi < 0 || active[fi] == null) return true;
			var formatting = active[fi];
			var si = stack.lastIndexOf(formatting);
			if (si < 0) {
				error("adoption-agency");
				active.splice(fi, 1);
				activeTags.splice(fi, 1);
				return false;
			}
			if (!elementInScope(formatting)) {
				error("adoption-agency");
				return false;
			}
			if (formatting != current()) error("adoption-agency");
			var fb = si + 1;
			while (fb < stack.length && !isSpecial(stack[fb]))
				fb++;
			if (fb == stack.length) {
				popUntilElement(formatting);
				active.splice(fi, 1);
				activeTags.splice(fi, 1);
				return false;
			}
			var furthest = stack[fb];
			var common = stack[si - 1];
			var bookmark = fi;
			var nodeIndex = fb;
			var lastNode:Element = furthest;
			var inner = 0;
			var moved = false;
			while (true) {
				inner++;
				nodeIndex--;
				var node = stack[nodeIndex];
				if (node == formatting) break;
				var ai = active.indexOf(node);
				if (inner > 3 && ai >= 0) {
					active.splice(ai, 1);
					activeTags.splice(ai, 1);
					if (ai < bookmark) bookmark--;
					ai = -1;
				}
				if (ai < 0) {
					stack.splice(nodeIndex, 1);
					popped(node);
					continue;
				}
				var e = create(activeTags[ai], Namespaces.HTML, common);
				e.start = node.start;
				active[ai] = e;
				stack[nodeIndex] = e;
				popped(node);
				node = e;
				if (!moved) {
					bookmark = ai + 1;
					moved = true;
				}
				Node.insert(lastNode, node, null);
				lastNode = node;
			}
			place(common);
			var parent = locParent, ref = locRef;
			if (lastNode.parentNode != null && (ref == null || ref.parentNode == parent)) Node.remove(lastNode);
			locParent = parent;
			locRef = ref;
			insertAt(lastNode);
			var e = create(activeTags[fi], Namespaces.HTML, furthest);
			e.start = formatting.start;
			while (furthest.firstChild != null)
				Node.insert(furthest.firstChild, e, null);
			Node.insert(e, furthest, null);
			active.insert(bookmark, e);
			activeTags.insert(bookmark, activeTags[fi]);
			var k = active.indexOf(formatting);
			active.splice(k, 1);
			activeTags.splice(k, 1);
			removeFromStack(formatting);
			stack.insert(stack.indexOf(furthest) + 1, e);
		}
		return false;
	}

	// --- foreign content: true to reprocess

	function foreignStart(t:Tag):Bool {
		var breakout = switch t.id {
			case B | BIG | BLOCKQUOTE | BODY | BR | CENTER | CODE | DD | DIV | DL | DT | EM | EMBED | H1 | H2 | H3 | H4 | H5 | H6 | HEAD | HR | I | IMG | LI
				| LISTING | MENU | META | NOBR | OL | P | PRE | RUBY | S | SMALL | SPAN | STRONG | STRIKE | SUB | SUP | TABLE | TT | U | UL | VAR: true;
			case FONT: t.attr("color") != null || t.attr("face") != null || t.attr("size") != null;
			case _: false;
		}
		if (breakout) {
			error("unexpected-html-element-in-foreign-content");
			while (!(mathmlTextPoint(current()) || htmlPoint(current()) || current().ns == Element.HTML))
				pop();
			while (startIn(mode, t)) {}
			return false;
		}
		var a = adjustedCurrent();
		var namespace = a.namespaceURI;
		if (a.ns == Element.SVG) {
			var adjusted = SVG_TAGS.get(t.name);
			if (adjusted != null) {
				t.name = adjusted;
				t.id = Tags.id(adjusted);
			}
		}
		insertForeign(t, namespace);
		if (t.selfClosing) {
			t.acknowledged = true;
			pop();
		}
		return false;
	}

	function foreignEnd(t:Tag):Bool {
		if (t.id == BR || t.id == P) {
			error("unexpected-html-element-in-foreign-content");
			while (!(mathmlTextPoint(current()) || htmlPoint(current()) || current().ns == Element.HTML))
				pop();
			while (endIn(mode, t)) {}
			return false;
		}
		if (t.name == "script" && current().ns == Element.SVG && current().localName == "script") {
			pop();
			return false;
		}
		var i = stack.length - 1;
		var node = stack[i];
		if (Names.lower(node.localName) != t.name) error("unexpected-end-tag");
		while (true) {
			if (i == 0) return false;
			if (Names.lower(node.localName) == t.name) {
				popUntilElement(node);
				return false;
			}
			i--;
			node = stack[i];
			if (node.ns == Element.HTML) {
				while (endIn(mode, t)) {}
				return false;
			}
		}
	}

	static final SVG_TAGS:Map<String, String> = [
		for (n in [
			"altGlyph", "altGlyphDef", "altGlyphItem", "animateColor", "animateMotion", "animateTransform", "clipPath", "feBlend", "feColorMatrix",
			"feComponentTransfer", "feComposite", "feConvolveMatrix", "feDiffuseLighting", "feDisplacementMap", "feDistantLight", "feDropShadow", "feFlood",
			"feFuncA", "feFuncB", "feFuncG", "feFuncR", "feGaussianBlur", "feImage", "feMerge", "feMergeNode", "feMorphology", "feOffset", "fePointLight",
			"feSpecularLighting", "feSpotLight", "feTile", "feTurbulence", "foreignObject", "glyphRef", "linearGradient", "radialGradient", "textPath"
		]) n.toLowerCase() => n
	];

	static final SVG_ATTRS:Map<String, String> = [
		for (n in [
			"attributeName", "attributeType", "baseFrequency", "baseProfile", "calcMode", "clipPathUnits", "diffuseConstant", "edgeMode", "filterUnits",
			"glyphRef", "gradientTransform", "gradientUnits", "kernelMatrix", "kernelUnitLength", "keyPoints", "keySplines", "keyTimes", "lengthAdjust",
			"limitingConeAngle", "markerHeight", "markerUnits", "markerWidth", "maskContentUnits", "maskUnits", "numOctaves", "pathLength",
			"patternContentUnits", "patternTransform", "patternUnits", "pointsAtX", "pointsAtY", "pointsAtZ", "preserveAlpha", "preserveAspectRatio",
			"primitiveUnits", "refX", "refY", "repeatCount", "repeatDur", "requiredExtensions", "requiredFeatures", "specularConstant", "specularExponent",
			"spreadMethod", "startOffset", "stdDeviation", "stitchTiles", "surfaceScale", "systemLanguage", "tableValues", "targetX", "targetY",
			"textLength", "viewBox", "viewTarget", "xChannelSelector", "yChannelSelector", "zoomAndPan"
		]) n.toLowerCase() => n
	];
}
