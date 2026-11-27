package helder.ui.box;

import helder.css.CssInvalidation;
import helder.css.CssRestyle;
import helder.css.CssStyles;
import helder.dom.CharacterData;
import helder.dom.Document;
import helder.dom.DomObserver;
import helder.dom.Element;
import helder.dom.Node;

// A live document's changes since its view's last update (DocumentView.watch):
// its observer, handing each change to helder.css's CssRestyle (the
// elements to style again, by the styles' invalidation sets) and keeping
// what else it changes of the box tree: children inserted or removed, an
// attribute boxes read (an image's src, a cell's span), a text changed.
class DocumentChanges implements DomObserver {
	public final restyle:CssRestyle;
	// the box tree is to be made again
	public var structure(default, null) = false;
	// the texts changed, once each
	public final texts:Array<CharacterData> = [];

	final document:Document;

	public function new(document:Document, styles:CssStyles) {
		this.document = document;
		restyle = new CssRestyle(document, CssInvalidation.of(styles.selectors()));
		document.observer = this;
	}

	public function detach()
		if (document.observer == this) document.observer = null;

	public function dirty():Bool
		return structure || texts.length > 0 || restyle.dirty();

	public function clear() {
		restyle.clear();
		structure = false;
		texts.resize(0);
	}

	public function inserted(parent:Node, node:Node) {
		restyle.inserted(parent, node);
		if (node.nodeType != Node.COMMENT_NODE) structure = true;
	}

	public function removed(parent:Node, node:Node, previous:Null<Node>, next:Null<Node>) {
		restyle.removed(parent, node, previous, next);
		if (node.nodeType != Node.COMMENT_NODE) structure = true;
	}

	public function attributeChanged(el:Element, namespace:Null<String>, localName:String, old:Null<String>, value:Null<String>) {
		restyle.attributeChanged(el, namespace, localName, old, value);
		// (what the cascade alone reads: styled again; the rest (src, colspan, start...) the boxes' too)
		if (namespace != null || !STYLED.exists(localName) && !StringTools.startsWith(localName, "data-")
			&& !StringTools.startsWith(localName, "aria-")) structure = true;
	}

	static final STYLED = ["class" => true, "id" => true, "style" => true, "title" => true, "href" => true, "role" => true, "tabindex" => true,
		"lang" => true, "dir" => true, "hidden" => true];

	public function dataChanged(node:CharacterData) {
		restyle.dataChanged(node);
		if (node.nodeType == Node.TEXT_NODE || node.nodeType == Node.CDATA_SECTION_NODE) {
			if (texts.indexOf(node) < 0) texts.push(node);
		}
	}

	public function stateChanged(el:Element, old:Int, value:Int)
		restyle.stateChanged(el, old, value);
}
