package helder.ui;

// a text of a selection's scope, by its path from the scope, and an index in it
class TextPoint {
	// (past every text and index: TextSelection.all's end)
	@:allow(helder.ui) static inline var LAST = 0x7FFFFFFF;

	public final path:Array<Int>;
	public final index:Int;

	public function new(path:Array<Int>, index:Int) {
		this.path = path;
		this.index = index;
	}

	// (null: not one of scope's texts)
	public static function of(scope:Node, text:Node, index:Int):Null<TextPoint> {
		var p = pathOf(scope, text);
		return p == null || text.selectableText() == null ? null : new TextPoint(p, index);
	}

	// its text's node, if made
	public function node(scope:Node):Null<Node> {
		var n:Null<Node> = scope;
		for (k in path) {
			if (n == null) return null;
			if (Std.isOfType(n, VirtualScroll)) {
				var r = (cast n : VirtualScroll).rowAt(k);
				n = r == null ? null : r.node;
			} else n = k >= 0 && k < n.children.length ? n.children[k] : null;
		}
		return n;
	}

	public function equals(p:TextPoint):Bool
		return compare(this, p) == 0;

	// the order of two points of a scope (negative: a first)
	public static function compare(a:TextPoint, b:TextPoint):Int {
		var o = order(a.path, b.path);
		return o != 0 ? o : a.index < b.index ? -1 : a.index > b.index ? 1 : 0;
	}

	@:allow(helder.ui) static function order(a:Array<Int>, b:Array<Int>):Int {
		for (k in 0...(a.length < b.length ? a.length : b.length))
			if (a[k] != b[k]) return a[k] < b[k] ? -1 : 1;
		return a.length - b.length;
	}

	// (n's path down from scope: a VirtualScroll's rows by index; null: not in it)
	@:allow(helder.ui) static function pathOf(scope:Node, n:Node):Null<Array<Int>> {
		var path = [], c = n;
		while (c != scope) {
			var p = c.parent;
			if (p == null) return null;
			if (Std.isOfType(p, VirtualScroll)) {
				var r = (cast p : VirtualScroll).rowOf(c);
				if (r == null) return null;
				path.push(r.index);
			} else path.push(p.indexOf(c));
			c = p;
		}
		path.reverse();
		return path;
	}
}
