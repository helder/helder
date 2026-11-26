package helder.dom;

// The DOM's Attr: an element's attribute, as a node of its own (not a child).
@:allow(helder.dom)
class Attr extends Node {
	public var namespaceURI(default, null):Null<String>;
	public var prefix(default, null):Null<String>;
	public var localName(default, null):String;
	public var name(get, never):String;
	public var value(get, set):String;
	public var ownerElement(default, null):Null<Element> = null;
	public var specified(get, never):Bool;

	var data:String;

	function new(doc:Document, localName:String, value:String, ?namespace:String, ?prefix:String) {
		super(Node.ATTRIBUTE_NODE, doc);
		this.localName = localName;
		this.data = value;
		this.namespaceURI = namespace;
		this.prefix = prefix;
	}

	inline function qualifiedName():String
		return prefix == null ? localName : prefix + ":" + localName;

	function get_name():String
		return qualifiedName();

	override function get_nodeName():String
		return qualifiedName();

	inline function get_value():String
		return data;

	function set_value(v:String):String {
		setExisting(v);
		return v;
	}

	function get_specified():Bool
		return true;

	override function get_nodeValue():Null<String>
		return data;

	override function set_nodeValue(v:Null<String>):Null<String> {
		setExisting(v ?? "");
		return v;
	}

	override function get_textContent():Null<String>
		return data;

	override function set_textContent(v:Null<String>):Null<String> {
		setExisting(v ?? "");
		return v;
	}

	// set an existing attribute value
	function setExisting(v:String) {
		if (ownerElement == null) data = v else ownerElement.changeAttr(this, v);
	}

	override function cloneOne(document:Document):Node
		return new Attr(document, localName, data, namespaceURI, prefix);

	override function equalsOne(other:Node):Bool {
		if (other.nodeType != nodeType) return false;
		var o:Attr = cast other;
		return o.namespaceURI == namespaceURI && o.localName == localName && o.data == data;
	}
}
