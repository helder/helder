package helder.dom;

// HTML's template element: its children parsed into content, a fragment in
// the document's inert template document (nothing in it is live).
@:allow(helder.dom)
class HTMLTemplateElement extends Element {
	public var content(default, null):DocumentFragment;

	// a <template for>'s content patching (the parser's): where its children go
	var insertionTarget:Null<Node> = null;
	var startMarker:Null<ProcessingInstruction> = null;
	var endMarker:Null<ProcessingInstruction> = null;

	function new(doc:Document, prefix:Null<String>) {
		super(doc, "template", Namespaces.HTML, prefix);
		content = new DocumentFragment(doc.templateOwner());
		content.host = this;
	}

	override function cloningSteps(copy:Element, subtree:Bool) {
		if (!subtree) return;
		var to = (cast copy : HTMLTemplateElement).content;
		var c = content.firstChild;
		while (c != null) {
			Node.clone(c, to.doc, true, to);
			c = c.nextSibling;
		}
	}

	override function adopted(old:Document) {
		super.adopted(old);
		Node.adopt(content, doc.templateOwner());
	}
}
