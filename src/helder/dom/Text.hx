package helder.dom;

// The DOM's Text.
@:allow(helder.dom)
class Text extends CharacterData {
	public var wholeText(get, never):String;

	function new(doc:Document, data:String, type = Node.TEXT_NODE)
		super(type, doc, data);

	override function get_nodeName():String
		return "#text";

	function get_wholeText():String {
		var first:Node = this;
		while (first.previousSibling != null && isText(first.previousSibling))
			first = first.previousSibling;
		var buf = new StringBuf(), n:Null<Node> = first;
		while (n != null && isText(n)) {
			buf.add((cast n : Text).value);
			n = n.nextSibling;
		}
		return buf.toString();
	}

	static inline function isText(n:Node):Bool
		return n.nodeType == Node.TEXT_NODE || n.nodeType == Node.CDATA_SECTION_NODE;

	public function splitText(offset:Int):Text {
		var length = value.length;
		if (offset < 0 || offset > length) throw new DOMException("offset out of range", "IndexSizeError");
		var count = length - offset;
		var copy = new Text(doc, value.substr(offset, count));
		if (parentNode != null) Node.insert(copy, parentNode, nextSibling);
		replaceData(offset, count, "");
		return copy;
	}

	override function cloneOne(document:Document):Node
		return new Text(document, value);
}
