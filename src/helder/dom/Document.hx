package helder.dom;

// The DOM's Document (4.5) with ParentNode's members and HTML's head, body
// and title. new Document() is an XML document, as the spec's constructor
// makes; Dom.parse's are HTML documents. mode is the parser's, from the
// doctype.
@:allow(helder.dom)
class Document extends Node {
	public var mode(default, null):DocumentMode = NoQuirks;
	public var compatMode(get, never):String;
	public var contentType(default, null):String;
	public var characterSet(get, never):String;
	public var doctype(get, never):Null<DocumentType>;
	public var documentElement(get, never):Null<Element>;
	public var head(get, never):Null<Element>;
	public var body(get, never):Null<Element>;
	public var title(get, never):String;
	public var children(get, never):HTMLCollection;
	public var firstElementChild(get, never):Null<Element>;
	public var lastElementChild(get, never):Null<Element>;
	public var childElementCount(get, never):Int;

	// an HTML document (else an XML one)
	var isHTML = false;
	// bumped by every change to a child list or an attribute in the document: live collections' key
	var version = 0;
	// an engine's hooks on this document's changes (null: none)
	public var observer:Null<DomObserver> = null;
	// the inert document its templates' contents live in (one made for that: itself)
	var inert:Null<Document> = null;
	var isInert = false;
	// select, option and selectedcontent elements made in it (none: no steps to run)
	var selects = 0;
	// the selects whose selectedcontent is to update (HTML's microtask), run when
	// the outermost DOM operation (depth) or the parse ends
	var microtasks:Array<HTMLSelectElement> = [];
	var depth = 0;
	var parsing = 0;

	public function new() {
		super(Node.DOCUMENT_NODE, null);
		doc = this;
		contentType = "application/xml";
	}

	static function html():Document {
		var d = new Document();
		d.isHTML = true;
		d.contentType = "text/html";
		return d;
	}

	override function get_nodeName():String
		return "#document";

	override function get_ownerDocument():Null<Document>
		return null;

	function get_compatMode():String
		return mode == Quirks ? "BackCompat" : "CSS1Compat";

	function get_characterSet():String
		return "UTF-8";

	function get_doctype():Null<DocumentType> {
		var c = firstChild;
		while (c != null) {
			if (c.nodeType == Node.DOCUMENT_TYPE_NODE) return cast c;
			c = c.nextSibling;
		}
		return null;
	}

	function get_documentElement():Null<Element>
		return Node.firstElement(firstChild, true);

	function htmlChild(test:Element->Bool):Null<Element> {
		var root = documentElement;
		if (root == null || !root.isHTML(Tags.HTML)) return null;
		var c = root.firstChild;
		while (c != null) {
			if (c.nodeType == Node.ELEMENT_NODE && test(cast c)) return cast c;
			c = c.nextSibling;
		}
		return null;
	}

	function get_head():Null<Element>
		return htmlChild(e -> e.isHTML(Tags.HEAD));

	function get_body():Null<Element>
		return htmlChild(e -> e.isHTML(Tags.BODY) || e.isHTML(Tags.FRAMESET));

	// the first title element's text, its white space stripped and collapsed
	function get_title():String {
		var root = documentElement;
		var title:Null<Element> = null;
		if (root != null && root.ns == Element.SVG && root.localName == "svg") {
			var c = root.firstChild;
			while (c != null && title == null) {
				if (c.nodeType == Node.ELEMENT_NODE && (cast c : Element).ns == Element.SVG && (cast c : Element).localName == "title") title = cast c;
				c = c.nextSibling;
			}
		} else {
			var n = firstChild;
			while (n != null && title == null) {
				if (n.nodeType == Node.ELEMENT_NODE && (cast n : Element).isHTML(Tags.TITLE)) title = cast n;
				n = Node.following(n, this);
			}
		}
		if (title == null) return "";
		var text = new StringBuf(), c = title.firstChild;
		while (c != null) {
			if (c.nodeType == Node.TEXT_NODE) text.add((cast c : Text).data);
			c = c.nextSibling;
		}
		return ~/[\t\n\x0C\r ]+/g.replace(text.toString(), " ").split(" ").filter(w -> w != "").join(" ");
	}

	function get_children():HTMLCollection
		return childElements();

	function get_firstElementChild():Null<Element>
		return Node.firstElement(firstChild, true);

	function get_lastElementChild():Null<Element>
		return Node.firstElement(lastChild, false);

	function get_childElementCount():Int
		return Node.elementCount(this);

	public function getElementById(elementId:String):Null<Element>
		return Node.elementById(this, elementId);

	public function getElementsByTagName(qualifiedName:String):HTMLCollection
		return Node.byQualifiedName(this, qualifiedName);

	public function getElementsByTagNameNS(namespace:Null<String>, localName:String):HTMLCollection
		return Node.byNamespace(this, namespace, localName);

	public function getElementsByClassName(classNames:String):HTMLCollection
		return Node.byClassName(this, classNames);

	public function createElement(localName:String):Element {
		if (!Names.validElementLocalName(localName)) throw new DOMException("invalid name", "InvalidCharacterError");
		if (isHTML) localName = Names.lower(localName);
		return Element.create(this, localName, isHTML || contentType == "application/xhtml+xml" ? Namespaces.HTML : null);
	}

	public function createElementNS(namespace:Null<String>, qualifiedName:String):Element {
		var parts = Names.extract(namespace, qualifiedName, true);
		return Element.create(this, parts[2], parts[0], parts[1]);
	}

	public function createDocumentFragment():DocumentFragment
		return new DocumentFragment(this);

	public function createTextNode(data:String):Text
		return new Text(this, data);

	public function createCDATASection(data:String):CDATASection {
		if (isHTML) throw new DOMException("an HTML document", "NotSupportedError");
		if (data.indexOf("]]>") >= 0) throw new DOMException("]]> in a CDATA section", "InvalidCharacterError");
		return new CDATASection(this, data);
	}

	public function createComment(data:String):Comment
		return new Comment(this, data);

	public function createProcessingInstruction(target:String, data:String):ProcessingInstruction {
		if (!Names.isXmlName(target)) throw new DOMException("invalid target", "InvalidCharacterError");
		if (data.indexOf("?>") >= 0) throw new DOMException("?> in a processing instruction", "InvalidCharacterError");
		return new ProcessingInstruction(this, target, data);
	}

	public function importNode(node:Node, subtree = false):Node {
		if (node.nodeType == Node.DOCUMENT_NODE) throw new DOMException("a document", "NotSupportedError");
		return Node.clone(node, this, subtree, null);
	}

	public function adoptNode(node:Node):Node {
		if (node.nodeType == Node.DOCUMENT_NODE) throw new DOMException("a document", "NotSupportedError");
		Node.adopt(node, this);
		return node;
	}

	public function createAttribute(localName:String):Attr {
		if (!Names.validAttributeLocalName(localName)) throw new DOMException("invalid name", "InvalidCharacterError");
		return new Attr(this, isHTML ? Names.lower(localName) : localName, "");
	}

	public function createAttributeNS(namespace:Null<String>, qualifiedName:String):Attr {
		var parts = Names.extract(namespace, qualifiedName, false);
		return new Attr(this, parts[2], "", parts[0], parts[1]);
	}

	public function prepend(...nodes:NodeOrString)
		Node.prependTo(this, nodes.toArray());

	public function append(...nodes:NodeOrString)
		Node.appendTo(this, nodes.toArray());

	public function replaceChildren(...nodes:NodeOrString)
		Node.replaceChildrenOf(this, nodes.toArray());

	public function moveBefore(node:Node, child:Null<Node>)
		Node.moveBeforeIn(this, node, child);

	// a microtask checkpoint (once no operation or parse is running)
	function checkpoint() {
		if (depth > 0 || parsing > 0) return;
		while (microtasks.length > 0) {
			var s = microtasks.shift();
			if (s.pending) s.updateSelectedContent();
		}
	}

	// the appropriate template contents owner document
	function templateOwner():Document {
		if (isInert) return this;
		if (inert == null) {
			var d = new Document();
			d.isHTML = isHTML;
			d.contentType = contentType;
			d.isInert = true;
			inert = d;
		}
		return inert;
	}

	override function cloneOne(document:Document):Node {
		var d = new Document();
		d.isHTML = isHTML;
		d.contentType = contentType;
		d.mode = mode;
		return d;
	}
}
