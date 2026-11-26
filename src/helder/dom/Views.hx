package helder.dom;

// A node's views, made when first asked for (most nodes never are): its
// childNodes and children, an element's attributes and classList, and the
// order compareDocumentPosition gives a disconnected node.
@:noCompletion class Views {
	public var childNodes:Null<NodeList> = null;
	public var children:Null<HTMLCollection> = null;
	public var attributes:Null<NamedNodeMap> = null;
	public var classList:Null<DOMTokenList> = null;
	public var serial = -1;

	public function new() {}
}
