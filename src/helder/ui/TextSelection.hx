package helder.ui;

import helder.ui.access.Role;

// A selection of text (Ui.textSelection): in a scope (Node.selectable: a
// selectable TextNode alone, or a node whose texts share one), from the
// anchor to the focus. The scope's texts are its TextNodes (their spans
// in them) and what else has a text of its own (a CodeView's), in the
// tree's order, but those of user-select none. A point is a text by its
// path down from the scope (a VirtualScroll's rows by their index: a row
// let go and made again is the same) and a UTF-16 index in its text. A
// value: a selection changed is a new one.
class TextSelection {
	public final scope:Node;
	public final anchor:TextPoint;
	public final focus:TextPoint;

	public function new(scope:Node, anchor:TextPoint, focus:TextPoint) {
		this.scope = scope;
		this.anchor = anchor;
		this.focus = focus;
	}

	// from index a of text from to index b of text to, both in scope (null:
	// either not one of its texts)
	public static function between(scope:Node, from:Node, a:Int, to:Node, b:Int):Null<TextSelection> {
		var p = TextPoint.of(scope, from, a), q = TextPoint.of(scope, to, b);
		return p == null || q == null ? null : new TextSelection(scope, p, q);
	}

	// all of a scope's text (from before its first to after its last: rows
	// not made too)
	public static function all(scope:Node):TextSelection
		return new TextSelection(scope, new TextPoint([], 0), new TextPoint([TextPoint.LAST], TextPoint.LAST));

	public function collapsed():Bool
		return TextPoint.compare(anchor, focus) == 0;

	// its first point and its last, in the scope's order
	public function start():TextPoint
		return TextPoint.compare(anchor, focus) <= 0 ? anchor : focus;

	public function end():TextPoint
		return TextPoint.compare(anchor, focus) <= 0 ? focus : anchor;

	// what it covers of a text of its scope, length long (null: none of it)
	public function rangeIn(n:Node, length:Int):Null<{start:Int, end:Int}> {
		if (collapsed() || n.userSelect() == None) return null;
		var path = TextPoint.pathOf(scope, n);
		if (path == null) return null;
		var s = start(), e = end();
		if (TextPoint.order(path, s.path) < 0 || TextPoint.order(path, e.path) > 0) return null;
		var a = TextPoint.order(path, s.path) == 0 ? s.index : 0, b = TextPoint.order(path, e.path) == 0 ? e.index : length;
		if (b > length) b = length;
		return a < b ? {start: a, end: b} : null;
	}

	// its text: each text's part, a blank line between blocks, a line
	// between list items and a table's rows, a tab between a row's cells
	// (rows of a VirtualScroll not made: made for their text alone)
	public function text():String {
		var s = start(), e = end(), parts:Array<{node:Node, text:String}> = [];
		texts(scope, s, e, ALL, (n, path) -> {
			var t = n.selectableText(), a = TextPoint.order(path, s.path) == 0 ? s.index : 0;
			var b = TextPoint.order(path, e.path) == 0 ? e.index : t.length;
			if (b > t.length) b = t.length;
			parts.push({node: n, text: a < b ? t.substring(a, b) : ""});
		});
		// (a text at either end of which nothing is selected: not a block's break)
		while (parts.length > 0 && parts[parts.length - 1].text == "")
			parts.pop();
		while (parts.length > 0 && parts[0].text == "")
			parts.shift();
		var b = new StringBuf();
		for (k in 0...parts.length) {
			if (k > 0) b.add(separator(parts[k - 1].node, parts[k].node, parts[k - 1].text, parts[k].text));
			b.add(parts[k].text);
		}
		return b.toString();
	}

	// (what is between two texts copied one after the other)
	static function separator(a:Node, b:Node, ta:String, tb:String):String {
		var ca = within(a, isCell), cb = within(b, isCell);
		if (ca != null && cb != null && ca.parent == cb.parent) return gridRow(ca) == gridRow(cb) ? "\t" : "\n";
		var ia = within(a, n -> roleOf(n) == ListItem), ib = within(b, n -> roleOf(n) == ListItem);
		if (ia != null && ib != null && ia != ib) return "\n";
		// (side by side in a row: inline, as a paragraph's runs around a picture)
		var p = a.parent;
		if (p != null && p == b.parent && (p.style.direction == Row || p.style.direction == RowReverse))
			return ta == "" || tb == "" || StringTools.isSpace(ta, ta.length - 1) || StringTools.isSpace(tb, 0) ? "" : " ";
		return "\n\n";
	}

	static function roleOf(n:Node):Null<Role>
		return n.semantics == null ? null : n.semantics.role;

	static function isCell(n:Node):Bool {
		var r = roleOf(n);
		return r == Cell || r == ColumnHeader;
	}

	static function within(n:Null<Node>, f:Node->Bool):Null<Node> {
		while (n != null && !f(n))
			n = n.parent;
		return n;
	}

	// (a grid's cell's row: by its columns, else its place)
	static function gridRow(c:Node):Float {
		var p = c.parent, cols = p.style.gridTemplateColumns.length;
		return cols > 0 ? Std.int(p.indexOf(c) / cols) : c.y;
	}

	// (which texts: those drawn, those made too (a VirtualScroll's rows out
	// of its window), those not made as well (made for their text alone,
	// let go after))
	@:allow(helder.ui) static inline var SHOWN = 0;
	@:allow(helder.ui) static inline var MADE = 1;
	@:allow(helder.ui) static inline var ALL = 2;

	// the texts of scope (in order, with their paths) from point from's to
	// to's (null: from the first, to the last), which of them
	@:allow(helder.ui) static function texts(scope:Node, from:Null<TextPoint>, to:Null<TextPoint>, which:Int, f:(Node, Array<Int>) -> Void) {
		var path:Array<Int> = [];
		// (whether the subtree at path can hold a text in the range)
		function inRange():Bool
			return (from == null || prefix(path, from.path) >= 0) && (to == null || prefix(path, to.path) <= 0);
		function visit(n:Node) {
			if (n.selectableText() != null) {
				if (n.userSelect() != None) f(n, path.copy());
				return;
			}
			if (Std.isOfType(n, VirtualScroll)) {
				var v:VirtualScroll = cast n;
				var lo = from != null && from.path.length > path.length && prefix(path, from.path) == 0 ? from.path[path.length] : 0;
				var hi = to != null && to.path.length > path.length && prefix(path, to.path) == 0 ? to.path[path.length] : v.count - 1;
				for (i in (lo < 0 ? 0 : lo)...(hi >= v.count ? v.count : hi + 1)) {
					var r = v.rowAt(i);
					if (r != null && (which != SHOWN || r.node.style.display != None)) {
						path.push(i);
						visit(r.node);
						path.pop();
					} else if (r == null && which == ALL && v.onMakeRow != null) {
						var row = v.textRow(i);
						path.push(i);
						try visit(row.node) catch (e:Dynamic) {
							v.dropTextRow(row);
							throw e;
						}
						path.pop();
						v.dropTextRow(row);
					}
				}
				return;
			}
			for (k in 0...n.children.length) {
				var c = n.children[k];
				if (c.style.display == None) continue;
				path.push(k);
				if (inRange()) visit(c);
				path.pop();
			}
		}
		if (scope.style.display != None) visit(scope);
	}

	// (a subtree's path against a point's: before it, around it (0), after it)
	static function prefix(sub:Array<Int>, point:Array<Int>):Int {
		for (k in 0...sub.length) {
			if (k >= point.length) return 0;
			if (sub[k] != point[k]) return sub[k] < point[k] ? -1 : 1;
		}
		return 0;
	}
}
