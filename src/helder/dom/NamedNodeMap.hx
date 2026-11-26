package helder.dom;

// The DOM's NamedNodeMap: an element's attributes, live.
@:allow(helder.dom)
class NamedNodeMap {
	public var length(get, never):Int;

	final element:Element;

	function new(element:Element)
		this.element = element;

	function get_length():Int
		return element.attrList().length;

	public function item(index:Int):Null<Attr> {
		var a = element.attrList();
		return index >= 0 && index < a.length ? a[index] : null;
	}

	public function getNamedItem(qualifiedName:String):Null<Attr>
		return element.byName(qualifiedName);

	public function getNamedItemNS(namespace:Null<String>, localName:String):Null<Attr>
		return element.byNamespace(namespace, localName);

	public function setNamedItem(attr:Attr):Null<Attr>
		return element.setAttr(attr);

	public function setNamedItemNS(attr:Attr):Null<Attr>
		return element.setAttr(attr);

	public function removeNamedItem(qualifiedName:String):Attr {
		var a = element.byName(qualifiedName);
		if (a == null) throw new DOMException("no such attribute", "NotFoundError");
		element.removeAttr(a);
		return a;
	}

	public function removeNamedItemNS(namespace:Null<String>, localName:String):Attr {
		var a = element.byNamespace(namespace, localName);
		if (a == null) throw new DOMException("no such attribute", "NotFoundError");
		element.removeAttr(a);
		return a;
	}

	public function iterator():Iterator<Attr>
		return element.attrList().copy().iterator();
}
