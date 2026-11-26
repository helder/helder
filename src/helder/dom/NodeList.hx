package helder.dom;

// The DOM's NodeList: a node's children, live (a view over its links), or
// a list of its own (static).
@:allow(helder.dom)
class NodeList {
	public var length(get, never):Int;

	final root:Null<Node>;
	var items:Array<Node>;
	var version = -1;
	var owner:Null<Document> = null;

	function new(root:Null<Node>, ?items:Array<Node>) {
		this.root = root;
		this.items = items ?? [];
	}

	function nodes():Array<Node> {
		var r = root;
		if (r == null || r.doc == owner && r.doc.version == version) return items;
		owner = r.doc;
		version = r.doc.version;
		var a = [], c = r.firstChild;
		while (c != null) {
			a.push(c);
			c = c.nextSibling;
		}
		return items = a;
	}

	function get_length():Int
		return nodes().length;

	public function item(index:Int):Null<Node> {
		var a = nodes();
		return index >= 0 && index < a.length ? a[index] : null;
	}

	public function iterator():Iterator<Node>
		return nodes().copy().iterator();
}
