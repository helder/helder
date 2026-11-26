package helder.css;

import helder.dom.CharacterData;
import helder.dom.Document;
import helder.dom.DomObserver;
import helder.dom.Element;
import helder.dom.Node;

using StringTools;

// A document's restyle tracker: attached as its DomObserver, it marks the
// elements that may match differently after each change, by the sheets'
// invalidation sets (CssInvalidation): a class or id changed, an
// attribute, a state bit, a child inserted or removed, a text changed. An
// inserted subtree is marked whole (new elements have no style yet).
// Marks are an element alone or an element's subtree; `marked` reads them
// out, `clear` forgets them once restyled. Detached, the document's steps
// pay a null check.
class CssRestyle implements DomObserver {
	public final document:Document;
	final sets:CssInvalidation;
	final self = new Map<Element, Bool>();
	final subtrees = new Map<Element, Bool>();
	var all = false;

	public function new(document:Document, sets:CssInvalidation) {
		this.document = document;
		this.sets = sets;
	}

	public static function attach(document:Document, sets:CssInvalidation):CssRestyle {
		var r = new CssRestyle(document, sets);
		document.observer = r;
		return r;
	}

	public function detach()
		if (document.observer == this) document.observer = null;

	// whether el may need its style made again
	public function isMarked(el:Element):Bool {
		if (all || self.exists(el)) return true;
		var e:Null<Element> = el;
		while (e != null) {
			if (subtrees.exists(e)) return true;
			e = e.parentElement;
		}
		return false;
	}

	// the marked elements in the document, in tree order
	public function marked():Array<Element> {
		var out = [], n:Null<Node> = document.documentElement;
		while (n != null) {
			if (n.nodeType == Node.ELEMENT_NODE && isMarked(cast n)) out.push(cast n);
			n = next(n);
		}
		return out;
	}

	// whether anything is marked
	public function dirty():Bool
		return all || self.keys().hasNext() || subtrees.keys().hasNext();

	public function clear() {
		self.clear();
		subtrees.clear();
		all = false;
	}

	// ---- the document's changes

	public function inserted(parent:Node, node:Node) {
		if (node.nodeType == Node.ELEMENT_NODE) subtrees.set(cast node, true);
		structure(parent);
	}

	public function removed(parent:Node, node:Node, previous:Null<Node>, next:Null<Node>)
		structure(parent);

	public function attributeChanged(el:Element, namespace:Null<String>, localName:String, old:Null<String>, value:Null<String>) {
		// (any attribute: its own style at least, for presentational hints and the style attribute)
		var f = CssInvalidation.SELF;
		if (namespace == null && localName == "class") f |= classes(el, old, value) else if (namespace == null && localName == "id") {
			if (old != null) f |= sets.forId(old, el, old);
			if (value != null) f |= sets.forId(value, el, old);
		}
		f |= sets.forAttribute(localName, el);
		apply(el, f);
	}

	public function dataChanged(node:CharacterData) {
		var p = node.parentNode;
		if (p != null && p.nodeType == Node.ELEMENT_NODE) apply(cast p, sets.text);
	}

	public function stateChanged(el:Element, old:Int, value:Int)
		apply(el, sets.forState(old ^ value, el));

	// (a child list changed: the parent's :empty, its children's sibling counts)
	function structure(parent:Node) {
		var f = sets.structure;
		if (f == 0) return;
		if (parent.nodeType == Node.ELEMENT_NODE) apply(cast parent, f) else if (f & (CssInvalidation.SUBTREE | CssInvalidation.DOCUMENT) != 0) all = true;
	}

	// (the classes in one of old and new, not both: their flags)
	function classes(el:Element, old:Null<String>, value:Null<String>):Int {
		var a = split(old), b = split(value), f = 0;
		for (c in a)
			if (!b.contains(c)) f |= sets.forClass(c, el, old);
		for (c in b)
			if (!a.contains(c)) f |= sets.forClass(c, el, old);
		return f;
	}

	static function split(s:Null<String>):Array<String>
		return s == null ? [] : [for (c in ~/[ \t\n\x0C\r]+/g.split(s)) if (c != "") c];

	function apply(el:Element, f:Int) {
		if (f == 0 || all) return;
		if (f & CssInvalidation.DOCUMENT != 0) {
			all = true;
			return;
		}
		if (f & CssInvalidation.SELF != 0) self.set(el, true);
		if (f & CssInvalidation.SUBTREE != 0) subtrees.set(el, true);
		if (f & CssInvalidation.SIBLINGS != 0) {
			var p = el.parentElement;
			if (p != null) subtrees.set(p, true) else all = true;
			return;
		}
		if (f & CssInvalidation.LATER != 0) {
			var s = el.nextElementSibling;
			while (s != null) {
				subtrees.set(s, true);
				s = s.nextElementSibling;
			}
		} else if (f & CssInvalidation.NEXT != 0) {
			var s = el.nextElementSibling;
			if (s != null) subtrees.set(s, true);
		}
	}

	function next(n:Node):Null<Node> {
		if (n.firstChild != null) return n.firstChild;
		while (n != null) {
			if (n.nextSibling != null) return n.nextSibling;
			n = n.parentNode;
		}
		return null;
	}
}
