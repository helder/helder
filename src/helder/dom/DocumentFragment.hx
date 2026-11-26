package helder.dom;

// The DOM's DocumentFragment: a parentless list of nodes, moved as its
// children when inserted. A template's contents are one, the template its host.
@:allow(helder.dom)
class DocumentFragment extends Node {
	public var children(get, never):HTMLCollection;
	public var firstElementChild(get, never):Null<Element>;
	public var lastElementChild(get, never):Null<Element>;
	public var childElementCount(get, never):Int;

	var host:Null<Element> = null;
	var collection:Null<HTMLCollection> = null;

	function new(doc:Document)
		super(Node.DOCUMENT_FRAGMENT_NODE, doc);

	override function get_nodeName():String
		return "#document-fragment";

	override function get_textContent():Null<String>
		return Node.descendantText(this);

	override function set_textContent(v:Null<String>):Null<String> {
		Node.replaceAll(v == null || v == "" ? null : doc.createTextNode(v), this);
		return v;
	}

	function get_children():HTMLCollection
		return collection ?? (collection = new HTMLCollection(this, true, e -> true));

	function get_firstElementChild():Null<Element>
		return Node.firstElement(firstChild, true);

	function get_lastElementChild():Null<Element>
		return Node.firstElement(lastChild, false);

	function get_childElementCount():Int
		return Node.elementCount(this);

	public function getElementById(elementId:String):Null<Element>
		return Node.elementById(this, elementId);

	public function prepend(...nodes:NodeOrString)
		Node.prependTo(this, nodes.toArray());

	public function append(...nodes:NodeOrString)
		Node.appendTo(this, nodes.toArray());

	public function replaceChildren(...nodes:NodeOrString)
		Node.replaceChildrenOf(this, nodes.toArray());

	public function moveBefore(node:Node, child:Null<Node>)
		Node.moveBeforeIn(this, node, child);

	override function cloneOne(document:Document):Node
		return new DocumentFragment(document);
}
