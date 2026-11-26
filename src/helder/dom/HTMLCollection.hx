package helder.dom;

// The DOM's HTMLCollection: the elements under a root (its children, or all
// its descendants) that a filter matches, live: read again in tree order
// after any change to the document's child lists or attributes.
@:allow(helder.dom)
class HTMLCollection {
	public var length(get, never):Int;

	final root:Node;
	final childrenOnly:Bool;
	final filter:Element->Bool;
	var items:Array<Element> = [];
	var version = -1;
	var owner:Null<Document> = null;

	function new(root:Node, childrenOnly:Bool, filter:Element->Bool) {
		this.root = root;
		this.childrenOnly = childrenOnly;
		this.filter = filter;
	}

	function elements():Array<Element> {
		if (root.doc == owner && root.doc.version == version) return items;
		owner = root.doc;
		version = root.doc.version;
		var a = [];
		if (childrenOnly) {
			var c = root.firstChild;
			while (c != null) {
				if (c.nodeType == Node.ELEMENT_NODE && filter(cast c)) a.push((cast c : Element));
				c = c.nextSibling;
			}
		} else {
			var n = root.firstChild;
			while (n != null) {
				if (n.nodeType == Node.ELEMENT_NODE && filter(cast n)) a.push((cast n : Element));
				n = Node.following(n, root);
			}
		}
		return items = a;
	}

	function get_length():Int
		return elements().length;

	public function item(index:Int):Null<Element> {
		var a = elements();
		return index >= 0 && index < a.length ? a[index] : null;
	}

	public function namedItem(key:String):Null<Element> {
		if (key == "") return null;
		for (e in elements())
			if (e.id == key || e.ns == Element.HTML && e.getAttributeNS(null, "name") == key) return e;
		return null;
	}

	public function iterator():Iterator<Element>
		return elements().copy().iterator();
}
