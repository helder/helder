package helder.dom;

// An engine's hooks on a document's changes, for its restyle tracker
// (helder.css's CssRestyle): set on Document.observer. Not the DOM's
// MutationObserver: called at once, synchronously, from the steps every
// change goes through (insert, remove, an attribute's change, a node's
// data, an element's state). With none set, each step costs a null check.
interface DomObserver {
	// node (not a fragment: each of its children) now parent's child
	function inserted(parent:Node, node:Node):Void;

	// node no longer parent's child; it was between previous and next
	function removed(parent:Node, node:Node, previous:Null<Node>, next:Null<Node>):Void;

	function attributeChanged(el:Element, namespace:Null<String>, localName:String, old:Null<String>, value:Null<String>):Void;

	function dataChanged(node:CharacterData):Void;

	function stateChanged(el:Element, old:Int, value:Int):Void;
}
