package helder.dom;

// The DOM's Element (4.9) with ParentNode, ChildNode and
// NonDocumentTypeChildNode's members, and HTML's innerHTML and outerHTML.
// Every element is made by create (the spec's "create an element"): the one
// place that picks an element's class (a template's HTMLTemplateElement).
@:allow(helder.dom)
class Element extends Node {
	public var namespaceURI(default, null):Null<String>;
	public var prefix(default, null):Null<String>;
	public var localName(default, null):String;
	public var tagName(get, never):String;
	public var id(get, set):String;
	public var className(get, set):String;
	public var classList(get, never):DOMTokenList;
	public var slot(get, set):String;
	public var attributes(get, never):NamedNodeMap;
	public var children(get, never):HTMLCollection;
	public var firstElementChild(get, never):Null<Element>;
	public var lastElementChild(get, never):Null<Element>;
	public var childElementCount(get, never):Int;
	public var previousElementSibling(get, never):Null<Element>;
	public var nextElementSibling(get, never):Null<Element>;
	public var innerHTML(get, set):String;
	public var outerHTML(get, set):String;
	// its dynamic state (ElementState's bits): an engine's extra, as source
	// offsets are, set by setState; 0 (all off) on a printed page
	public var state(default, null):Int = 0;

	// the namespace as a number (HTML, SVG, MATHML, OTHER) and the local name's Tags id
	var ns:Int;
	var tag:Int;
	var attrs:Null<Array<Attr>> = null;
	// the parser's attributes, not yet Attr nodes (Attrs' spans of src; null: none, or made)
	var raw:Null<Array<Int>> = null;
	var src:Null<String> = null;

	static inline var HTML = 0;
	static inline var SVG = 1;
	static inline var MATHML = 2;
	static inline var OTHER = 3;

	function new(doc:Document, localName:String, namespace:Null<String>, prefix:Null<String>, id = -1) {
		super(Node.ELEMENT_NODE, doc);
		this.localName = localName;
		this.namespaceURI = namespace;
		this.prefix = prefix;
		ns = switch namespace {
			case Namespaces.HTML: HTML;
			case Namespaces.SVG: SVG;
			case Namespaces.MATHML: MATHML;
			case _: OTHER;
		}
		tag = ns == OTHER ? Tags.OTHER : id >= 0 ? id : Tags.id(localName);
	}

	// create an element (no custom elements: the element interface for the name and namespace)
	static function create(document:Document, localName:String, namespace:Null<String>, ?prefix:String, id = -1):Element {
		if (namespace == Namespaces.HTML) switch localName {
			case "template": return new HTMLTemplateElement(document, prefix);
			case "option": return new HTMLOptionElement(document, prefix);
			case "select": return new HTMLSelectElement(document, prefix);
			case "selectedcontent": return new HTMLSelectedContentElement(document, prefix);
			case _:
		}
		return new Element(document, localName, namespace, prefix, id);
	}

	// (the HTML standard's steps for its elements, run by the DOM's algorithms:
	// insertion, post-connection, removing, moving and attribute change steps,
	// and the parser's children parsed steps; select, option and
	// selectedcontent have some)
	function insertionSteps() {}

	function postConnection() {}

	function removingSteps() {}

	function movingSteps() {}

	function attributeChangeSteps(localName:String, old:Null<String>, value:Null<String>, namespace:Null<String>) {}

	function childrenParsed() {}

	// (the parser's: its attributes set at once, as created)
	function attributesSet() {}

	inline function isHTML(id:Int):Bool
		return ns == HTML && tag == id;

	function qualifiedName():String
		return prefix == null ? localName : prefix + ":" + localName;

	override function get_nodeName():String
		return get_tagName();

	function get_tagName():String {
		var q = qualifiedName();
		return ns == HTML && doc.isHTML ? Names.upper(q) : q;
	}

	override function get_textContent():Null<String>
		return Node.descendantText(this);

	override function set_textContent(v:Null<String>):Null<String> {
		Node.replaceAll(v == null || v == "" ? null : doc.createTextNode(v), this);
		return v;
	}

	function get_id():String
		return attrValue("id");

	function set_id(v:String):String {
		setAttrValue("id", v);
		return v;
	}

	function get_className():String
		return attrValue("class");

	function set_className(v:String):String {
		setAttrValue("class", v);
		return v;
	}

	function get_slot():String
		return attrValue("slot");

	function set_slot(v:String):String {
		setAttrValue("slot", v);
		return v;
	}

	function get_classList():DOMTokenList
		return views().classList ?? (views().classList = new DOMTokenList(this, "class"));

	function get_attributes():NamedNodeMap
		return views().attributes ?? (views().attributes = new NamedNodeMap(this));

	function get_children():HTMLCollection
		return childElements();

	function get_firstElementChild():Null<Element>
		return Node.firstElement(firstChild, true);

	function get_lastElementChild():Null<Element>
		return Node.firstElement(lastChild, false);

	function get_childElementCount():Int
		return Node.elementCount(this);

	function get_previousElementSibling():Null<Element>
		return Node.firstElement(previousSibling, false);

	function get_nextElementSibling():Null<Element>
		return Node.firstElement(nextSibling, true);

	function get_innerHTML():String
		return Serializer.children(this);

	function set_innerHTML(v:String):String {
		var fragment = TreeBuilder.fragment(v, this, null);
		var target:Node = isHTML(Tags.TEMPLATE) ? (cast this : HTMLTemplateElement).content : this;
		Node.replaceAll(fragment, target);
		return v;
	}

	function get_outerHTML():String
		return Serializer.node(this);

	function set_outerHTML(v:String):String {
		var parent = parentNode;
		if (parent == null) return v;
		if (parent.nodeType == Node.DOCUMENT_NODE) throw new DOMException("the document element", "NoModificationAllowedError");
		var context:Element = parent.nodeType == Node.DOCUMENT_FRAGMENT_NODE ? create(doc, "body", Namespaces.HTML) : cast parent;
		Node.replace(this, TreeBuilder.fragment(v, context, null), parent);
		return v;
	}

	// the attribute list as Attr nodes (the parser's made now, in their order)
	function attrList():Array<Attr> {
		var r = raw;
		if (r != null) {
			raw = null;
			var n = Std.int(r.length / Attrs.SIZE), list = [];
			for (i in 0...n) {
				var a = new Attr(doc, Attrs.name(src, r, i), Attrs.value(src, r, i));
				a.ownerElement = this;
				list.push(a);
			}
			src = null;
			attrs = attrs == null ? list : list.concat(attrs);
		}
		return attrs ?? NONE;
	}

	static final NONE:Array<Attr> = [];

	inline function rawCount():Int
		return raw == null ? 0 : Std.int(raw.length / Attrs.SIZE);

	public function hasAttributes():Bool
		return raw != null || attrs != null && attrs.length > 0;

	public function getAttributeNames():Array<String> {
		if (raw != null && attrs == null) return [for (i in 0...rawCount()) Attrs.name(src, raw, i)];
		return [for (a in attrList()) a.qualifiedName()];
	}

	public function getAttribute(qualifiedName:String):Null<String>
		return valueByName(qualifiedName);

	public function getAttributeNS(namespace:Null<String>, localName:String):Null<String>
		return valueByNamespace(namespace, localName);

	// (the value of get an attribute by name, read from the parser's spans when they are still all there is)
	function valueByName(qualifiedName:String):Null<String> {
		if (raw != null && attrs == null) {
			if (ns == HTML && doc.isHTML) qualifiedName = Names.lower(qualifiedName);
			for (i in 0...rawCount())
				if (Attrs.nameIs(src, raw, i, qualifiedName)) return Attrs.value(src, raw, i);
			return null;
		}
		var a = byName(qualifiedName);
		return a == null ? null : a.data;
	}

	// (by namespace and local name: the parser's attributes have none)
	function valueByNamespace(namespace:Null<String>, localName:String):Null<String> {
		if (raw != null && attrs == null) {
			if (namespace != null && namespace != "") return null;
			for (i in 0...rawCount())
				if (Attrs.nameIs(src, raw, i, localName)) return Attrs.value(src, raw, i);
			return null;
		}
		var a = byNamespace(namespace, localName);
		return a == null ? null : a.data;
	}

	public function setAttribute(qualifiedName:String, value:String) {
		if (!Names.validAttributeLocalName(qualifiedName)) throw new DOMException("invalid name", "InvalidCharacterError");
		if (ns == HTML && doc.isHTML) qualifiedName = Names.lower(qualifiedName);
		for (a in attrList())
			if (a.qualifiedName() == qualifiedName) {
				changeAttr(a, value);
				return;
			}
		appendAttr(new Attr(doc, qualifiedName, value));
	}

	public function setAttributeNS(namespace:Null<String>, qualifiedName:String, value:String) {
		var parts = Names.extract(namespace, qualifiedName, false);
		setAttrValue(parts[2], value, parts[1], parts[0]);
	}

	public function removeAttribute(qualifiedName:String) {
		var a = byName(qualifiedName);
		if (a != null) removeAttr(a);
	}

	public function removeAttributeNS(namespace:Null<String>, localName:String) {
		var a = byNamespace(namespace, localName);
		if (a != null) removeAttr(a);
	}

	public function toggleAttribute(qualifiedName:String, ?force:Bool):Bool {
		if (!Names.validAttributeLocalName(qualifiedName)) throw new DOMException("invalid name", "InvalidCharacterError");
		if (ns == HTML && doc.isHTML) qualifiedName = Names.lower(qualifiedName);
		var found:Null<Attr> = null;
		for (a in attrList())
			if (a.qualifiedName() == qualifiedName) {
				found = a;
				break;
			}
		if (found == null) {
			if (force == null || force) {
				appendAttr(new Attr(doc, qualifiedName, ""));
				return true;
			}
			return false;
		}
		if (force == null || !force) {
			removeAttr(found);
			return false;
		}
		return true;
	}

	public function hasAttribute(qualifiedName:String):Bool
		return valueByName(qualifiedName) != null;

	public function hasAttributeNS(namespace:Null<String>, localName:String):Bool
		return valueByNamespace(namespace, localName) != null;

	public function getAttributeNode(qualifiedName:String):Null<Attr>
		return byName(qualifiedName);

	public function getAttributeNodeNS(namespace:Null<String>, localName:String):Null<Attr>
		return byNamespace(namespace, localName);

	public function setAttributeNode(attr:Attr):Null<Attr>
		return setAttr(attr);

	public function setAttributeNodeNS(attr:Attr):Null<Attr>
		return setAttr(attr);

	public function removeAttributeNode(attr:Attr):Attr {
		if (!attrList().contains(attr)) throw new DOMException("not an attribute of this element", "NotFoundError");
		removeAttr(attr);
		return attr;
	}

	public function getElementsByTagName(qualifiedName:String):HTMLCollection
		return Node.byQualifiedName(this, qualifiedName);

	public function getElementsByTagNameNS(namespace:Null<String>, localName:String):HTMLCollection
		return Node.byNamespace(this, namespace, localName);

	public function getElementsByClassName(classNames:String):HTMLCollection
		return Node.byClassName(this, classNames);

	public function insertAdjacentElement(where:String, element:Element):Null<Element>
		return cast insertAdjacent(where, element);

	public function insertAdjacentText(where:String, data:String)
		insertAdjacent(where, doc.createTextNode(data));

	function insertAdjacent(where:String, node:Node):Null<Node> {
		return switch Names.lower(where) {
			case "beforebegin": parentNode == null ? null : Node.preInsert(node, parentNode, this);
			case "afterbegin": Node.preInsert(node, this, firstChild);
			case "beforeend": Node.preInsert(node, this, null);
			case "afterend": parentNode == null ? null : Node.preInsert(node, parentNode, nextSibling);
			case _: throw new DOMException("not a position: " + where, "SyntaxError");
		}
	}

	public function prepend(...nodes:NodeOrString)
		Node.prependTo(this, nodes.toArray());

	public function append(...nodes:NodeOrString)
		Node.appendTo(this, nodes.toArray());

	public function replaceChildren(...nodes:NodeOrString)
		Node.replaceChildrenOf(this, nodes.toArray());

	public function moveBefore(node:Node, child:Null<Node>)
		Node.moveBeforeIn(this, node, child);

	public function before(...nodes:NodeOrString)
		Node.before(this, nodes.toArray());

	public function after(...nodes:NodeOrString)
		Node.after(this, nodes.toArray());

	public function replaceWith(...nodes:NodeOrString)
		Node.replaceWith(this, nodes.toArray());

	public function remove()
		Node.removeSelf(this);

	// get an attribute by name
	function byName(qualifiedName:String):Null<Attr> {
		var attrs = attrList();
		if (attrs.length == 0) return null;
		if (ns == HTML && doc.isHTML) qualifiedName = Names.lower(qualifiedName);
		for (a in attrs)
			if (a.prefix == null ? a.localName == qualifiedName : a.qualifiedName() == qualifiedName) return a;
		return null;
	}

	// get an attribute by namespace and local name
	function byNamespace(namespace:Null<String>, localName:String):Null<Attr> {
		var attrs = attrList();
		if (attrs.length == 0) return null;
		if (namespace == "") namespace = null;
		for (a in attrs)
			if (a.localName == localName && a.namespaceURI == namespace) return a;
		return null;
	}

	// get an attribute value (no namespace)
	inline function attrValue(localName:String):String
		return valueByNamespace(null, localName) ?? "";

	// set an attribute value
	function setAttrValue(localName:String, value:String, ?prefix:String, ?namespace:String) {
		var a = byNamespace(namespace, localName);
		if (a == null) appendAttr(new Attr(doc, localName, value, namespace, prefix)) else changeAttr(a, value);
	}

	// set an attribute
	function setAttr(attr:Attr):Null<Attr> {
		if (attr.ownerElement != null && attr.ownerElement != this) throw new DOMException("an attribute of another element", "InUseAttributeError");
		var old = byNamespace(attr.namespaceURI, attr.localName);
		if (old == attr) return attr;
		if (old != null) replaceAttr(old, attr) else appendAttr(attr);
		return old;
	}

	// the state's bits turned on or off (the document's observer told)
	public function setState(bits:Int, on:Bool) {
		var old = state, value = on ? old | bits : old & ~bits;
		if (value == old) return;
		state = value;
		if (doc.observer != null) doc.observer.stateChanged(this, old, value);
	}

	// handle attribute changes (mutation records will hook in here)
	function attributeChanged(attr:Attr, old:Null<String>, value:Null<String>) {
		var d = doc;
		d.version++;
		if (d.observer != null) d.observer.attributeChanged(this, attr.namespaceURI, attr.localName, old, value);
		d.depth++;
		attributeChangeSteps(attr.localName, old, value, attr.namespaceURI);
		d.depth--;
		d.checkpoint();
	}

	function changeAttr(attr:Attr, value:String) {
		var old = attr.data;
		attr.data = value;
		attributeChanged(attr, old, value);
	}

	function appendAttr(attr:Attr) {
		attrList();
		if (attrs == null) attrs = [];
		attrs.push(attr);
		attr.ownerElement = this;
		attr.doc = doc;
		attributeChanged(attr, null, attr.data);
	}

	function removeAttr(attr:Attr) {
		attrs.remove(attr);
		attr.ownerElement = null;
		attributeChanged(attr, attr.data, null);
	}

	function replaceAttr(old:Attr, attr:Attr) {
		attrs[attrs.indexOf(old)] = attr;
		attr.ownerElement = this;
		attr.doc = doc;
		old.ownerElement = null;
		attributeChanged(attr, old.data, attr.data);
	}

	// locate a namespace prefix
	function locatePrefix(namespace:String):Null<String> {
		var e:Null<Element> = this;
		while (e != null) {
			if (e.namespaceURI == namespace && e.prefix != null) return e.prefix;
			// (the parser's attributes, not made yet, are in no namespace)
			for (a in e.attrs ?? NONE)
				if (a.prefix == "xmlns" && a.data == namespace) return a.localName;
			e = e.parentElement;
		}
		return null;
	}

	// locate a namespace
	function locateNamespace(prefix:Null<String>):Null<String> {
		if (prefix == "xml") return Namespaces.XML;
		if (prefix == "xmlns") return Namespaces.XMLNS;
		var e:Null<Element> = this;
		while (e != null) {
			if (e.namespaceURI != null && e.prefix == prefix) return e.namespaceURI;
			for (a in e.attrs ?? NONE)
				if (a.namespaceURI == Namespaces.XMLNS && (prefix != null ? a.prefix == "xmlns" && a.localName == prefix : a.prefix == null && a.localName == "xmlns"))
					return a.data == "" ? null : a.data;
			e = e.parentElement;
		}
		return null;
	}

	// (the HTML standard's cloning steps: a template's)
	function cloningSteps(copy:Element, subtree:Bool) {}

	// (adopting steps: the attributes', a template's contents')
	function adopted(old:Document)
		for (a in attrs ?? NONE)
			a.doc = doc;

	override function cloneOne(document:Document):Node {
		var copy = create(document, localName, namespaceURI, prefix);
		if (raw != null && attrs == null) {
			copy.raw = raw;
			copy.src = src;
			copy.attributesSet();
			return copy;
		}
		for (a in attrList())
			copy.appendAttr(cast a.cloneOne(document));
		return copy;
	}

	override function equalsOne(other:Node):Bool {
		if (other.nodeType != nodeType) return false;
		var o:Element = cast other;
		if (o.namespaceURI != namespaceURI || o.prefix != prefix || o.localName != localName) return false;
		var mine = attrList(), theirs = o.attrList();
		if (mine.length != theirs.length) return false;
		for (a in mine) {
			var found = false;
			for (b in theirs)
				if (a.equalsOne(b)) {
					found = true;
					break;
				}
			if (!found) return false;
		}
		return true;
	}
}
