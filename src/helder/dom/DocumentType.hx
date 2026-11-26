package helder.dom;

// The DOM's DocumentType: <!DOCTYPE name "publicId" "systemId">.
@:allow(helder.dom)
class DocumentType extends Node {
	public var name(default, null):String;
	public var publicId(default, null):String;
	public var systemId(default, null):String;

	function new(doc:Document, name:String, publicId:String, systemId:String) {
		super(Node.DOCUMENT_TYPE_NODE, doc);
		this.name = name;
		this.publicId = publicId;
		this.systemId = systemId;
	}

	override function get_nodeName():String
		return name;

	public function before(...nodes:NodeOrString)
		Node.before(this, nodes.toArray());

	public function after(...nodes:NodeOrString)
		Node.after(this, nodes.toArray());

	public function replaceWith(...nodes:NodeOrString)
		Node.replaceWith(this, nodes.toArray());

	public function remove()
		Node.removeSelf(this);

	override function cloneOne(document:Document):Node
		return new DocumentType(document, name, publicId, systemId);

	override function equalsOne(other:Node):Bool {
		if (other.nodeType != nodeType) return false;
		var o:DocumentType = cast other;
		return o.name == name && o.publicId == publicId && o.systemId == systemId;
	}
}
