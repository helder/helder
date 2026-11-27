package helder.ui.box;

import haxe.Json;
import haxe.ds.ObjectMap;
import helder.dom.Node;

// A layout's geometry node by node, in the shape Chromium's DOMSnapshot
// gives it (tests/css/geometry.mjs): each element's border box in page
// coordinates (an inline box's one a line, any other's one), each text
// node's fragments with their range of its data (white space at their
// ends left out), generated content as its element's ::before, ::after,
// ::marker; each node named by its DOM path (html>body>div[2]>#text), in
// tree order. GeometryDiff compares two.
class Geometry {
	public final nodes:Array<GeometryNode>;
	// (subtrees not compared: transformed ones, their boxes not where layout put them)
	public final skipped:Array<String>;

	public function new(nodes:Array<GeometryNode>, ?skipped:Array<String>) {
		this.nodes = nodes;
		this.skipped = skipped ?? [];
	}

	// The geometry of a view's last layout.
	public static function of(view:DocumentView):Geometry {
		var paths = new ObjectMap<Node, String>();
		var order:Array<String> = [];
		function walk(n:Node, at:String) {
			var kids = [], k = n.firstChild;
			while (k != null) {
				kids.push(k);
				k = k.nextSibling;
			}
			var named = names([for (k in kids) name(k)]);
			for (i in 0...kids.length) {
				var k = kids[i];
				var p = at == "" ? named[i] : '$at>${named[i]}';
				paths.set(k, p);
				if (k.nodeType != Node.ELEMENT_NODE) {
					order.push(p);
					continue;
				}
				order.push(p);
				order.push('$p>::marker');
				order.push('$p>::before');
				order.push('$p>::first-letter');
				if ((cast k : helder.dom.Element).localName != "svg") walk(k, p);
				order.push('$p>::after');
			}
		}
		walk(view.document, "");
		var found = new Map<String, GeometryNode>(), unions = new Map<String, Bool>();
		var f = view.fragments;
		function entry(p:String):GeometryNode {
			var e = found.get(p);
			if (e == null) found.set(p, e = {path: p, rects: [], text: []});
			return e;
		}
		function visit(id:Int, x:Float, y:Float) {
			x += f.x(id);
			y += f.y(id);
			var b = f.box(id), kind = f.kind(id);
			var p = kind == Fragments.LINE ? null : path(b, paths);
			if (p != null && kind == Fragments.TEXT) {
				// (a fragment's range is of the node's data; the box's text from its offset in it)
				var s = trim(b.text, f.start(id) - b.offset, f.end(id) - b.offset);
				entry(p).text.push([x, y, f.width(id), f.height(id), b.offset + s[0], b.offset + s[1]]);
			} else if (p != null && b.kind != Text && b.kind != Break) {
				var r = [x, y, f.width(id), f.height(id)], e = entry(p);
				// (an inline box's parts each a line's; any other's fragments, a table's wrapper and grid, as one)
				if (b.kind == Inline && b.pseudo == null || e.rects.length == 0) e.rects.push(r) else union(e.rects[0], r);
			}
			var c = f.first(id);
			while (c >= 0) {
				visit(c, x, y);
				c = f.next(c);
			}
		}
		if (view.root >= 0) visit(view.root, 0, 0);
		return new Geometry([for (p in order) if (found.exists(p)) found.get(p)]);
	}

	// (a box's node's path: generated content its element's ::before; none for an anonymous box)
	static function path(b:Box, paths:ObjectMap<Node, String>):Null<String> {
		// (the first letter's text is its ::first-letter's, as Blink has it)
		var which = b.pseudo ?? (b.kind == Text && b.parent != null && b.parent.pseudo == "first-letter" ? "first-letter" : null);
		if (which == null) return b.node == null ? null : paths.get(b.node);
		var a = b;
		while (a != null && (a.node == null || a.node.nodeType != Node.ELEMENT_NODE)) a = a.parent;
		return a == null || paths.get(a.node) == null ? null : '${paths.get(a.node)}>::$which';
	}

	static function union(a:Array<Float>, b:Array<Float>) {
		var x0 = Math.min(a[0], b[0]), y0 = Math.min(a[1], b[1]);
		var x1 = Math.max(a[0] + a[2], b[0] + b[2]), y1 = Math.max(a[1] + a[3], b[1] + b[3]);
		a[0] = x0;
		a[1] = y0;
		a[2] = x1 - x0;
		a[3] = y1 - y0;
	}

	// (a node's name: an element's in lower case, #text; numbered from 1
	// among its siblings of that name where there are several, as geometry.mjs names them)
	static function name(n:Node):String
		return switch n.nodeType {
			case Node.ELEMENT_NODE: n.nodeName.toLowerCase();
			case Node.TEXT_NODE: "#text";
			case Node.CDATA_SECTION_NODE: "#cdata-section";
			case t: '#$t';
		}

	static function names(list:Array<String>):Array<String> {
		var count = new Map<String, Int>(), seen = new Map<String, Int>();
		for (n in list) count.set(n, (count.get(n) ?? 0) + 1);
		return [for (n in list) {
			var k = (seen.get(n) ?? 0) + 1;
			seen.set(n, k);
			count.get(n) > 1 ? '$n[$k]' : n;
		}];
	}

	// (a range without white space at its ends: where an engine ends a fragment around collapsed spaces is its own)
	static function trim(s:String, a:Int, b:Int):Array<Int> {
		if (a < 0) a = 0;
		if (b > s.length) b = s.length;
		while (a < b && space(StringTools.fastCodeAt(s, a))) a++;
		while (b > a && space(StringTools.fastCodeAt(s, b - 1))) b--;
		return [a, b];
	}

	static inline function space(c:Int):Bool
		return c == " ".code || c == "\t".code || c == "\n".code || c == "\r".code || c == 12;

	// geometry.mjs's JSON
	public static function parse(json:String):Geometry {
		var o:Dynamic = Json.parse(json);
		function floats(list:Null<Array<Dynamic>>):Array<Array<Float>> {
			var out:Array<Array<Float>> = [];
			if (list != null) for (r in list) {
				var values:Array<Dynamic> = r;
				out.push([for (v in values) (v : Float)]);
			}
			return out;
		}
		var list:Array<Dynamic> = o.nodes ?? [];
		var skipped:Array<Dynamic> = o.skipped ?? [];
		var nodes:Array<GeometryNode> = [for (n in list) {path: (n.path : String), rects: floats(n.rects), text: floats(n.text)}];
		return new Geometry(nodes, [for (s in skipped) (s : String)]);
	}

	public function toJson():String {
		var list = [for (n in nodes) n.text.length > 0 ? {path: n.path, rects: n.rects, text: n.text} : cast {path: n.path, rects: n.rects}];
		return Json.stringify(skipped.length > 0 ? {nodes: list, skipped: skipped} : cast {nodes: list});
	}
}

typedef GeometryNode = {
	path:String,
	// [x, y, width, height]
	rects:Array<Array<Float>>,
	// [x, y, width, height, start, end]: start and end in the node's data
	text:Array<Array<Float>>
}
