package helder.dom;

using StringTools;

// The DOM's Node (dom.spec.whatwg.org, 4.4): a tree of linked siblings.
// Every change to a child list goes through insert and remove below (the
// spec's algorithms), where mutation records and live ranges will hook in.
@:allow(helder.dom)
class Node {
	public static inline var ELEMENT_NODE = 1;
	public static inline var ATTRIBUTE_NODE = 2;
	public static inline var TEXT_NODE = 3;
	public static inline var CDATA_SECTION_NODE = 4;
	public static inline var ENTITY_REFERENCE_NODE = 5;
	public static inline var ENTITY_NODE = 6;
	public static inline var PROCESSING_INSTRUCTION_NODE = 7;
	public static inline var COMMENT_NODE = 8;
	public static inline var DOCUMENT_NODE = 9;
	public static inline var DOCUMENT_TYPE_NODE = 10;
	public static inline var DOCUMENT_FRAGMENT_NODE = 11;
	public static inline var NOTATION_NODE = 12;

	public static inline var DOCUMENT_POSITION_DISCONNECTED = 0x01;
	public static inline var DOCUMENT_POSITION_PRECEDING = 0x02;
	public static inline var DOCUMENT_POSITION_FOLLOWING = 0x04;
	public static inline var DOCUMENT_POSITION_CONTAINS = 0x08;
	public static inline var DOCUMENT_POSITION_CONTAINED_BY = 0x10;
	public static inline var DOCUMENT_POSITION_IMPLEMENTATION_SPECIFIC = 0x20;

	public var nodeType(default, null):Int;
	public var nodeName(get, never):String;
	public var ownerDocument(get, never):Null<Document>;
	public var parentNode(default, null):Null<Node> = null;
	public var parentElement(get, never):Null<Element>;
	public var firstChild(default, null):Null<Node> = null;
	public var lastChild(default, null):Null<Node> = null;
	public var previousSibling(default, null):Null<Node> = null;
	public var nextSibling(default, null):Null<Node> = null;
	public var childNodes(get, never):NodeList;
	public var nodeValue(get, set):Null<String>;
	public var textContent(get, set):Null<String>;
	public var isConnected(get, never):Bool;

	// where the parser read this node: offsets into its source string (code
	// units; code points on Eval), end after its end tag or last character;
	// -1 for a node made by code
	public var start = -1;
	public var end = -1;

	// the node document
	var doc:Document;
	var made:Null<Views> = null;

	function new(type:Int, doc:Document) {
		nodeType = type;
		this.doc = doc;
	}

	function get_nodeName():String
		return "";

	function get_ownerDocument():Null<Document>
		return doc;

	function get_parentElement():Null<Element>
		return parentNode != null && parentNode.nodeType == ELEMENT_NODE ? cast parentNode : null;

	function get_childNodes():NodeList
		return views().childNodes ?? (views().childNodes = new NodeList(this));

	function get_nodeValue():Null<String>
		return null;

	function set_nodeValue(v:Null<String>):Null<String>
		return v;

	function get_textContent():Null<String>
		return null;

	function set_textContent(v:Null<String>):Null<String>
		return v;

	function get_isConnected():Bool
		return root().nodeType == DOCUMENT_NODE;

	public function getRootNode():Node
		return root();

	public function hasChildNodes():Bool
		return firstChild != null;

	public function normalize() {
		var node = firstChild;
		while (node != null) {
			if (node.nodeType != TEXT_NODE) {
				node = following(node, this);
				continue;
			}
			var text:Text = cast node;
			if (text.data.length == 0) {
				var next = skip(node, this);
				remove(node);
				node = next;
				continue;
			}
			var buf:Null<StringBuf> = null, sibling = node.nextSibling;
			while (sibling != null && sibling.nodeType == TEXT_NODE) {
				if (buf == null) buf = new StringBuf();
				buf.add((cast sibling : Text).data);
				sibling = sibling.nextSibling;
			}
			if (buf != null) {
				text.replaceData(text.data.length, 0, buf.toString());
				while (node.nextSibling != sibling)
					remove(node.nextSibling);
			}
			node = following(node, this);
		}
	}

	public function cloneNode(subtree = false):Node
		return clone(this, doc, subtree, null);

	public function isEqualNode(otherNode:Null<Node>):Bool {
		if (otherNode == null) return false;
		var a:Null<Node> = this, b:Null<Node> = otherNode;
		while (a != null) {
			if (b == null || !a.equalsOne(b) || childCount(a) != childCount(b)) return false;
			var na = following(a, this), nb = following(b, otherNode);
			// (in step: the same shapes give the same walks)
			a = na;
			b = nb;
		}
		return b == null;
	}

	public function isSameNode(otherNode:Null<Node>):Bool
		return otherNode == this;

	public function compareDocumentPosition(other:Node):Int {
		if (this == other) return 0;
		var node1:Null<Node> = other, node2:Null<Node> = this;
		var attr1:Null<Attr> = null, attr2:Null<Attr> = null;
		if (node1.nodeType == ATTRIBUTE_NODE) {
			attr1 = cast node1;
			node1 = attr1.ownerElement;
		}
		if (node2.nodeType == ATTRIBUTE_NODE) {
			attr2 = cast node2;
			node2 = attr2.ownerElement;
			if (attr1 != null && node1 != null && node2 == node1) {
				for (attr in (cast node2 : Element).attrList())
					if (attr.equalsOne(attr1)) return DOCUMENT_POSITION_IMPLEMENTATION_SPECIFIC + DOCUMENT_POSITION_PRECEDING;
					else if (attr.equalsOne(attr2)) return DOCUMENT_POSITION_IMPLEMENTATION_SPECIFIC + DOCUMENT_POSITION_FOLLOWING;
			}
		}
		if (node1 == null || node2 == null || node1.root() != node2.root())
			return DOCUMENT_POSITION_DISCONNECTED + DOCUMENT_POSITION_IMPLEMENTATION_SPECIFIC
				+ (order(node1 ?? other, node2 ?? this) ? DOCUMENT_POSITION_PRECEDING : DOCUMENT_POSITION_FOLLOWING);
		if (node1 != node2 && node1.contains(node2) && attr1 == null || node1 == node2 && attr2 != null)
			return DOCUMENT_POSITION_CONTAINS + DOCUMENT_POSITION_PRECEDING;
		if (node1 != node2 && node2.contains(node1) && attr2 == null || node1 == node2 && attr1 != null)
			return DOCUMENT_POSITION_CONTAINED_BY + DOCUMENT_POSITION_FOLLOWING;
		return precedes(node1, node2) ? DOCUMENT_POSITION_PRECEDING : DOCUMENT_POSITION_FOLLOWING;
	}

	// (disconnected nodes: an order that stays the same, by their roots' creation)
	static function order(a:Node, b:Node):Bool
		return a.root().serial() < b.root().serial();

	static var serials = 0;

	function serial():Int {
		var v = views();
		return v.serial >= 0 ? v.serial : (v.serial = serials++);
	}

	inline function views():Views
		return made ?? (made = new Views());

	// (children, the ParentNode member: Document's, DocumentFragment's, Element's)
	function childElements():HTMLCollection
		return views().children ?? (views().children = new HTMLCollection(this, true, e -> true));

	public function contains(other:Null<Node>):Bool {
		var n = other;
		while (n != null) {
			if (n == this) return true;
			n = n.parentNode;
		}
		return false;
	}

	public function lookupPrefix(namespace:Null<String>):Null<String> {
		if (namespace == null || namespace == "") return null;
		return switch nodeType {
			case ELEMENT_NODE: (cast this : Element).locatePrefix(namespace);
			case DOCUMENT_NODE:
				var e = (cast this : Document).documentElement;
				e == null ? null : e.locatePrefix(namespace);
			case DOCUMENT_TYPE_NODE | DOCUMENT_FRAGMENT_NODE: null;
			case ATTRIBUTE_NODE:
				var e = (cast this : Attr).ownerElement;
				e == null ? null : e.locatePrefix(namespace);
			case _:
				var e = parentElement;
				e == null ? null : e.locatePrefix(namespace);
		}
	}

	public function lookupNamespaceURI(prefix:Null<String>):Null<String>
		return locateNamespace(this, prefix == "" ? null : prefix);

	public function isDefaultNamespace(namespace:Null<String>):Bool
		return locateNamespace(this, null) == (namespace == "" ? null : namespace);

	public function insertBefore(node:Node, child:Null<Node>):Node
		return preInsert(node, this, child);

	public function appendChild(node:Node):Node
		return preInsert(node, this, null);

	public function replaceChild(node:Node, child:Node):Node
		return replace(child, node, this);

	public function removeChild(child:Node):Node {
		if (child.parentNode != this) throw new DOMException("not a child", "NotFoundError");
		remove(child);
		return child;
	}

	// (each node type's: the spec's "clone a single node" and "equals")
	function cloneOne(document:Document):Node
		throw new DOMException("not cloneable", "NotSupportedError");

	function equalsOne(other:Node):Bool
		return nodeType == other.nodeType;

	function root():Node {
		var n = this;
		while (n.parentNode != null)
			n = n.parentNode;
		return n;
	}

	// the node after n in tree order within root (null: none)
	static inline function following(n:Node, root:Node):Null<Node> {
		if (n.firstChild != null) return n.firstChild;
		return skip(n, root);
	}

	// the node after n and its descendants within root
	static function skip(n:Node, root:Node):Null<Node> {
		var m = n;
		while (m != root) {
			if (m.nextSibling != null) return m.nextSibling;
			m = m.parentNode;
			if (m == null) return null;
		}
		return null;
	}

	static function childCount(n:Node):Int {
		var k = 0, c = n.firstChild;
		while (c != null) {
			k++;
			c = c.nextSibling;
		}
		return k;
	}

	static function index(n:Node):Int {
		var k = 0, c = n.previousSibling;
		while (c != null) {
			k++;
			c = c.previousSibling;
		}
		return k;
	}

	// a is before b in tree order (same root)
	static function precedes(a:Node, b:Node):Bool {
		var pa = [], pb = [];
		var n:Null<Node> = a;
		while (n != null) {
			pa.push(n);
			n = n.parentNode;
		}
		n = b;
		while (n != null) {
			pb.push(n);
			n = n.parentNode;
		}
		var i = pa.length - 1, j = pb.length - 1;
		while (i >= 0 && j >= 0 && pa[i] == pb[j]) {
			i--;
			j--;
		}
		if (i < 0) return true; // a is an ancestor of b
		if (j < 0) return false;
		var x = pa[i], y = pb[j];
		var c = x.nextSibling;
		while (c != null) {
			if (c == y) return true;
			c = c.nextSibling;
		}
		return false;
	}

	// descendant text content
	static function descendantText(root:Node):String {
		var buf:Null<StringBuf> = null, only:Null<String> = null;
		var n = root.firstChild;
		while (n != null) {
			if (n.nodeType == TEXT_NODE || n.nodeType == CDATA_SECTION_NODE) {
				var d = (cast n : Text).data;
				if (only == null && buf == null) only = d else {
					if (buf == null) {
						buf = new StringBuf();
						buf.add(only);
					}
					buf.add(d);
				}
			}
			n = following(n, root);
		}
		return buf != null ? buf.toString() : only ?? "";
	}

	static function locateNamespace(node:Node, prefix:Null<String>):Null<String> {
		return switch node.nodeType {
			case ELEMENT_NODE: (cast node : Element).locateNamespace(prefix);
			case DOCUMENT_NODE:
				var e = (cast node : Document).documentElement;
				e == null ? null : e.locateNamespace(prefix);
			case DOCUMENT_TYPE_NODE | DOCUMENT_FRAGMENT_NODE: null;
			case ATTRIBUTE_NODE:
				var e = (cast node : Attr).ownerElement;
				e == null ? null : e.locateNamespace(prefix);
			case _:
				var e = node.parentElement;
				e == null ? null : e.locateNamespace(prefix);
		}
	}

	// the spec's "clone a node": node's copy in document, and its descendants' with subtree
	static function clone(node:Node, document:Document, subtree:Bool, parent:Null<Node>):Node {
		var copy = node.cloneOne(document);
		if (node.nodeType == DOCUMENT_NODE) document = cast copy;
		if (node.nodeType == ELEMENT_NODE) (cast node : Element).cloningSteps(cast copy, subtree);
		if (parent != null) insert(copy, parent, null);
		if (!subtree) return copy;
		// (the descendants without recursion: a parser's deep tree)
		var from = node.firstChild, to = copy;
		while (from != null) {
			var c = from.cloneOne(document);
			if (from.nodeType == ELEMENT_NODE) (cast from : Element).cloningSteps(cast c, true);
			insert(c, to, null);
			if (from.firstChild != null) {
				from = from.firstChild;
				to = c;
				continue;
			}
			while (from != node && from.nextSibling == null) {
				from = from.parentNode;
				to = to.parentNode;
			}
			if (from == node) break;
			from = from.nextSibling;
		}
		return copy;
	}

	// a is a host-including inclusive ancestor of b (a template's contents' host is the template)
	static function hostIncludingAncestor(a:Node, b:Node):Bool {
		var n:Null<Node> = b;
		while (n != null) {
			var top = n;
			while (top != null) {
				if (top == a) return true;
				if (top.parentNode == null) break;
				top = top.parentNode;
			}
			n = top.nodeType == DOCUMENT_FRAGMENT_NODE ? (cast top : DocumentFragment).host : null;
		}
		return false;
	}

	static inline function isParentType(n:Node):Bool
		return n.nodeType == DOCUMENT_NODE || n.nodeType == DOCUMENT_FRAGMENT_NODE || n.nodeType == ELEMENT_NODE;

	static inline function isCharacterData(n:Node):Bool
		return n.nodeType == TEXT_NODE || n.nodeType == CDATA_SECTION_NODE || n.nodeType == COMMENT_NODE || n.nodeType == PROCESSING_INSTRUCTION_NODE;

	static function hierarchy(why:String)
		throw new DOMException(why, "HierarchyRequestError");

	// ensure pre-insert validity (excludeOne: replace's child; excludeAll: replaceChildren's)
	static function ensurePreInsertValidity(node:Node, parent:Node, child:Null<Node>, excludeOne:Null<Node>, excludeAll:Bool) {
		if (!isParentType(parent)) hierarchy("the parent cannot have children");
		if (hostIncludingAncestor(node, parent)) hierarchy("the node contains the parent");
		if (child != null && child.parentNode != parent) throw new DOMException("not a child of the parent", "NotFoundError");
		var t = node.nodeType;
		if (t != DOCUMENT_FRAGMENT_NODE && t != DOCUMENT_TYPE_NODE && t != ELEMENT_NODE && !isCharacterData(node)) hierarchy("the node cannot be a child");
		if (parent.nodeType != DOCUMENT_NODE) {
			if (t == DOCUMENT_TYPE_NODE) hierarchy("a doctype in an element");
			return;
		}
		if (t == TEXT_NODE || t == CDATA_SECTION_NODE) hierarchy("text in a document");
		if (isCharacterData(node)) return;
		inline function excluded(c:Node)
			return excludeAll || c == excludeOne;
		function hasElement(n:Node):Bool {
			var c = n.firstChild;
			while (c != null) {
				if (c.nodeType == ELEMENT_NODE && !(n == parent && excluded(c))) return true;
				c = c.nextSibling;
			}
			return false;
		}
		function doctypeAfter(c:Null<Node>):Bool {
			var n = c == null ? null : c.nextSibling;
			while (n != null) {
				if (n.nodeType == DOCUMENT_TYPE_NODE) return true;
				n = n.nextSibling;
			}
			return false;
		}
		if (t == DOCUMENT_FRAGMENT_NODE || t == ELEMENT_NODE) {
			if (t == DOCUMENT_FRAGMENT_NODE) {
				var elements = 0, c = node.firstChild;
				while (c != null) {
					if (c.nodeType == ELEMENT_NODE) elements++;
					if (c.nodeType == TEXT_NODE || c.nodeType == CDATA_SECTION_NODE) hierarchy("text in a document");
					c = c.nextSibling;
				}
				if (elements > 1) hierarchy("two document elements");
				if (elements == 0) return;
			}
			if (hasElement(parent) || child != null && (child.nodeType == DOCUMENT_TYPE_NODE && !excluded(child) || doctypeAfter(child)))
				hierarchy("a second document element, or one before the doctype");
			return;
		}
		// a doctype
		var c = parent.firstChild, elementBefore = false;
		while (c != null) {
			if (c.nodeType == DOCUMENT_TYPE_NODE && !excluded(c)) hierarchy("a second doctype");
			c = c.nextSibling;
		}
		if (child != null) {
			var p = child.previousSibling;
			while (p != null) {
				if (p.nodeType == ELEMENT_NODE) elementBefore = true;
				p = p.previousSibling;
			}
			if (elementBefore) hierarchy("a doctype after the document element");
		} else if (hasElement(parent)) hierarchy("a doctype after the document element");
	}

	static function preInsert(node:Node, parent:Node, child:Null<Node>):Node {
		ensurePreInsertValidity(node, parent, child, null, false);
		var ref = child;
		if (ref == node) ref = node.nextSibling;
		insert(node, parent, ref);
		return node;
	}

	// the spec's insert: node (a fragment: its children) into parent before child
	static function insert(node:Node, parent:Node, child:Null<Node>, suppressObservers = false) {
		var document = parent.doc;
		var first = node, last = node;
		if (node.nodeType == DOCUMENT_FRAGMENT_NODE) {
			first = node.firstChild;
			last = node.lastChild;
			if (first == null) return;
			node.firstChild = node.lastChild = null;
			var n = first;
			while (n != null) {
				var next = n.nextSibling;
				n.parentNode = n.previousSibling = n.nextSibling = null;
				adoptInto(n, document);
				link(n, parent, child);
				if (document.observer != null) document.observer.inserted(parent, n);
				n = next;
			}
			node.doc.version++;
		} else {
			// (a node new to the tree, of its document: no removal, no adoption to run)
			if (node.parentNode != null || node.doc != document) adopt(node, document);
			link(node, parent, child);
			if (document.observer != null) document.observer.inserted(parent, node);
		}
		document.version++;
		if (document.selects > 0) steps(first, last, document);
	}

	// the insertion steps, then the post-connection steps, of the inserted nodes and their descendants
	static function steps(first:Node, last:Node, document:Document) {
		document.depth++;
		for (post in [false, true]) {
			var n = first;
			while (true) {
				var d:Null<Node> = n;
				while (d != null) {
					if (d.nodeType == ELEMENT_NODE) {
						var e:Element = cast d;
						if (!post) e.insertionSteps() else if (e.get_isConnected()) e.postConnection();
					}
					d = following(d, n);
				}
				if (n == last || n.nextSibling == null) break;
				n = n.nextSibling;
			}
		}
		document.depth--;
		document.checkpoint();
	}

	// each node's own steps for it and its descendants (removing, moving)
	static function eachElement(node:Node, f:Element->Void) {
		var d:Null<Node> = node;
		while (d != null) {
			if (d.nodeType == ELEMENT_NODE) f(cast d);
			d = following(d, node);
		}
	}

	static inline function link(node:Node, parent:Node, child:Null<Node>) {
		node.parentNode = parent;
		if (child == null) {
			var last = parent.lastChild;
			node.previousSibling = last;
			if (last == null) parent.firstChild = node else last.nextSibling = node;
			parent.lastChild = node;
		} else {
			var prev = child.previousSibling;
			node.previousSibling = prev;
			node.nextSibling = child;
			child.previousSibling = node;
			if (prev == null) parent.firstChild = node else prev.nextSibling = node;
		}
	}

	static function replace(child:Node, node:Node, parent:Node):Node {
		ensurePreInsertValidity(node, parent, child, child, false);
		var ref = child.nextSibling;
		if (ref == node) ref = node.nextSibling;
		adopt(node, parent.doc);
		if (child.parentNode != null) remove(child, true);
		insert(node, parent, ref, true);
		return child;
	}

	static function replaceAll(node:Null<Node>, parent:Node) {
		while (parent.firstChild != null)
			remove(parent.firstChild, true);
		if (node != null) insert(node, parent, null, true);
	}

	// the spec's remove
	static function remove(node:Node, suppressObservers = false) {
		var parent = node.parentNode;
		var prev = node.previousSibling, next = node.nextSibling;
		if (prev == null) parent.firstChild = next else prev.nextSibling = next;
		if (next == null) parent.lastChild = prev else next.previousSibling = prev;
		node.parentNode = node.previousSibling = node.nextSibling = null;
		var d = parent.doc;
		d.version++;
		if (d.observer != null) d.observer.removed(parent, node, prev, next);
		if (node.doc.selects > 0) {
			d.depth++;
			eachElement(node, e -> e.removingSteps());
			d.depth--;
			d.checkpoint();
		}
	}

	// the spec's adopt: node out of its parent, it and its descendants into document
	static function adopt(node:Node, document:Document) {
		if (node.parentNode != null) remove(node);
		adoptInto(node, document);
	}

	static function adoptInto(node:Node, document:Document) {
		var old = node.doc;
		if (document == old) return;
		var n:Null<Node> = node;
		if (old.selects > 0) document.selects++;
		while (n != null) {
			n.doc = document;
			if (n.nodeType == ELEMENT_NODE) (cast n : Element).adopted(old);
			n = following(n, node);
		}
	}

	// ParentNode's and ChildNode's arguments as one node
	static function convertNodes(nodes:Array<NodeOrString>, document:Document):Node {
		if (nodes.length == 1) return nodes[0].toNode(document);
		var fragment = document.createDocumentFragment();
		for (n in nodes)
			preInsert(n.toNode(document), fragment, null);
		return fragment;
	}

	static function firstElement(n:Null<Node>, forward:Bool):Null<Element> {
		while (n != null) {
			if (n.nodeType == ELEMENT_NODE) return cast n;
			n = forward ? n.nextSibling : n.previousSibling;
		}
		return null;
	}

	static function elementCount(parent:Node):Int {
		var k = 0, c = parent.firstChild;
		while (c != null) {
			if (c.nodeType == ELEMENT_NODE) k++;
			c = c.nextSibling;
		}
		return k;
	}

	static function prependTo(parent:Node, nodes:Array<NodeOrString>)
		preInsert(convertNodes(nodes, parent.doc), parent, parent.firstChild);

	static function appendTo(parent:Node, nodes:Array<NodeOrString>)
		preInsert(convertNodes(nodes, parent.doc), parent, null);

	static function replaceChildrenOf(parent:Node, nodes:Array<NodeOrString>) {
		var node = convertNodes(nodes, parent.doc);
		ensurePreInsertValidity(node, parent, null, null, true);
		replaceAll(node, parent);
	}

	// the spec's move (moveBefore): state kept, no removal and insertion
	static function move(node:Node, parent:Node, child:Null<Node>) {
		if (parent.root() != node.root()) hierarchy("another tree");
		if (hostIncludingAncestor(node, parent)) hierarchy("the node contains the parent");
		if (child != null && child.parentNode != parent) throw new DOMException("not a child of the parent", "NotFoundError");
		if (node.nodeType != ELEMENT_NODE && !isCharacterData(node)) hierarchy("only elements and character data move");
		if (node.nodeType == TEXT_NODE && parent.nodeType == DOCUMENT_NODE) hierarchy("text in a document");
		if (parent.nodeType == DOCUMENT_NODE && node.nodeType == ELEMENT_NODE) {
			var after = false, n = child == null ? null : child.nextSibling;
			while (n != null) {
				if (n.nodeType == DOCUMENT_TYPE_NODE) after = true;
				n = n.nextSibling;
			}
			if (firstElement(parent.firstChild, true) != null || child != null && child.nodeType == DOCUMENT_TYPE_NODE || after)
				hierarchy("a second document element, or one before the doctype");
		}
		var old = node.parentNode;
		var prev = node.previousSibling, next = node.nextSibling;
		if (prev == null) old.firstChild = next else prev.nextSibling = next;
		if (next == null) old.lastChild = prev else next.previousSibling = prev;
		node.parentNode = node.previousSibling = node.nextSibling = null;
		link(node, parent, child);
		var d = parent.doc;
		d.version++;
		if (d.selects > 0) {
			d.depth++;
			eachElement(node, e -> e.movingSteps());
			d.depth--;
			d.checkpoint();
		}
	}

	static function moveBeforeIn(parent:Node, node:Node, child:Null<Node>) {
		var ref = child;
		if (ref == node) ref = node.nextSibling;
		move(node, parent, ref);
	}

	static function inNodes(n:Node, nodes:Array<NodeOrString>):Bool {
		for (x in nodes)
			if (x.node() == n) return true;
		return false;
	}

	static function before(self:Node, nodes:Array<NodeOrString>) {
		var parent = self.parentNode;
		if (parent == null) return;
		var prev = self.previousSibling;
		while (prev != null && inNodes(prev, nodes))
			prev = prev.previousSibling;
		var node = convertNodes(nodes, self.doc);
		preInsert(node, parent, prev == null ? parent.firstChild : prev.nextSibling);
	}

	static function after(self:Node, nodes:Array<NodeOrString>) {
		var parent = self.parentNode;
		if (parent == null) return;
		var next = self.nextSibling;
		while (next != null && inNodes(next, nodes))
			next = next.nextSibling;
		preInsert(convertNodes(nodes, self.doc), parent, next);
	}

	static function replaceWith(self:Node, nodes:Array<NodeOrString>) {
		var parent = self.parentNode;
		if (parent == null) return;
		var next = self.nextSibling;
		while (next != null && inNodes(next, nodes))
			next = next.nextSibling;
		var node = convertNodes(nodes, self.doc);
		if (self.parentNode == parent) replace(self, node, parent) else preInsert(node, parent, next);
	}

	static function removeSelf(self:Node)
		if (self.parentNode != null) remove(self);

	static function elementById(root:Node, id:String):Null<Element> {
		var n = root.firstChild;
		while (n != null) {
			if (n.nodeType == ELEMENT_NODE && (cast n : Element).id == id && id != "") return cast n;
			n = following(n, root);
		}
		return null;
	}

	static function byQualifiedName(root:Node, qualifiedName:String):HTMLCollection {
		if (qualifiedName == "*") return new HTMLCollection(root, false, e -> true);
		if (root.doc.isHTML) {
			var lower = qualifiedName.toLowerCase();
			return new HTMLCollection(root, false, e -> e.namespaceURI == Namespaces.HTML ? e.qualifiedName() == lower : e.qualifiedName() == qualifiedName);
		}
		return new HTMLCollection(root, false, e -> e.qualifiedName() == qualifiedName);
	}

	static function byNamespace(root:Node, namespace:Null<String>, localName:String):HTMLCollection {
		if (namespace == "") namespace = null;
		if (namespace == "*" && localName == "*") return new HTMLCollection(root, false, e -> true);
		if (namespace == "*") return new HTMLCollection(root, false, e -> e.localName == localName);
		if (localName == "*") return new HTMLCollection(root, false, e -> e.namespaceURI == namespace);
		return new HTMLCollection(root, false, e -> e.namespaceURI == namespace && e.localName == localName);
	}

	static function byClassName(root:Node, classNames:String):HTMLCollection {
		var classes = DOMTokenList.parse(classNames);
		if (classes.length == 0) return new HTMLCollection(root, false, e -> false);
		return new HTMLCollection(root, false, e -> {
			var quirks = root.doc.mode == Quirks;
			var have = DOMTokenList.parse(e.getAttribute("class") ?? "");
			if (quirks) have = [for (c in have) c.toLowerCase()];
			for (c in classes)
				if (!have.contains(quirks ? c.toLowerCase() : c)) return false;
			return true;
		});
	}
}
