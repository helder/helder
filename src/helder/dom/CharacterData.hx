package helder.dom;

using StringTools;

// The DOM's CharacterData: Text, Comment and ProcessingInstruction's data.
// Offsets and lengths count the string's code units (code points on Eval).
@:allow(helder.dom)
class CharacterData extends Node {
	public var data(get, set):String;
	public var length(get, never):Int;
	public var previousElementSibling(get, never):Null<Element>;
	public var nextElementSibling(get, never):Null<Element>;

	var value:String;

	function new(type:Int, doc:Document, data:String) {
		super(type, doc);
		value = data;
	}

	inline function get_data():String
		return value;

	function set_data(v:String):String {
		replaceData(0, value.length, v ?? "");
		return v;
	}

	inline function get_length():Int
		return value.length;

	override function get_nodeValue():Null<String>
		return value;

	override function set_nodeValue(v:Null<String>):Null<String> {
		replaceData(0, value.length, v ?? "");
		return v;
	}

	override function get_textContent():Null<String>
		return value;

	override function set_textContent(v:Null<String>):Null<String> {
		replaceData(0, value.length, v ?? "");
		return v;
	}

	function get_previousElementSibling():Null<Element>
		return Node.firstElement(previousSibling, false);

	function get_nextElementSibling():Null<Element>
		return Node.firstElement(nextSibling, true);

	public function substringData(offset:Int, count:Int):String {
		if (offset < 0 || offset > value.length) throw new DOMException("offset out of range", "IndexSizeError");
		return value.substr(offset, count);
	}

	public function appendData(data:String)
		replaceData(value.length, 0, data);

	public function insertData(offset:Int, data:String)
		replaceData(offset, 0, data);

	public function deleteData(offset:Int, count:Int)
		replaceData(offset, count, "");

	// the spec's "replace data" (live ranges and mutation records will hook in here)
	public function replaceData(offset:Int, count:Int, data:String) {
		var length = value.length;
		if (offset < 0 || offset > length) throw new DOMException("offset out of range", "IndexSizeError");
		if (count < 0 || offset + count > length) count = length - offset;
		value = value.substr(0, offset) + data + value.substr(offset + count);
		changed();
	}

	function changed() {}

	public function before(...nodes:NodeOrString)
		Node.before(this, nodes.toArray());

	public function after(...nodes:NodeOrString)
		Node.after(this, nodes.toArray());

	public function replaceWith(...nodes:NodeOrString)
		Node.replaceWith(this, nodes.toArray());

	public function remove()
		Node.removeSelf(this);

	override function equalsOne(other:Node):Bool
		return other.nodeType == nodeType && (cast other : CharacterData).value == value;
}
