package helder.dom;

// The DOM's Comment.
@:allow(helder.dom)
class Comment extends CharacterData {
	function new(doc:Document, data:String)
		super(Node.COMMENT_NODE, doc, data);

	override function get_nodeName():String
		return "#comment";

	override function cloneOne(document:Document):Node
		return new Comment(document, value);
}
