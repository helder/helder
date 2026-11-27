package helder.ui.box;

import haxe.Json;
import helder.ui.box.Geometry.GeometryNode;

using StringTools;

// Two layouts' geometry (Geometry) compared node by node, matched by
// their DOM paths: each rectangle within tolerance, a text node's
// fragments as lines (those touching on a line taken as one: where a
// fragment ends is each engine's own) and their ranges of its data. The
// likely cause is `first`: from the root down, the first child that
// differs from its parent's place on (earlier siblings matching), until a
// node is itself off from its parent or none of its children are.
class GeometryDiff {
	// every node within tolerance, none on one side only
	public final match:Bool;
	// nodes compared (on both sides), and all (on either)
	public final compared:Int;
	public final nodes:Int;
	// the differences in tree order, those on one side included
	public final differences:Array<GeometryDifference>;
	public final first:Null<GeometryDifference>;
	// (whether first's parent is within tolerance)
	public final parentMatches:Bool;
	public final chromiumOnly:Array<String>;
	public final helderOnly:Array<String>;
	public final tolerance:Float;

	function new(compared, differences, first, parentMatches, chromiumOnly, helderOnly, tolerance) {
		this.tolerance = tolerance;
		this.compared = compared;
		this.differences = differences;
		this.first = first;
		this.parentMatches = parentMatches;
		this.chromiumOnly = chromiumOnly;
		this.helderOnly = helderOnly;
		nodes = compared + chromiumOnly.length + helderOnly.length;
		match = differences.length == 0;
	}

	public static function of(chromium:Geometry, helder:Geometry, tolerance = 0.5):GeometryDiff {
		var skipped = chromium.skipped.concat(helder.skipped);
		function kept(n:GeometryNode):Bool {
			for (s in skipped) if (n.path == s || n.path.startsWith('$s>')) return false;
			return true;
		}
		var a = new Map<String, GeometryNode>(), b = new Map<String, GeometryNode>();
		// (a node with nothing left once shaped, a text node's empty fragments alone, as none)
		for (n in chromium.nodes) if (kept(n)) {
			var s = shape(n);
			if (s.rects.length > 0 || s.text.length > 0) a.set(n.path, s);
		}
		for (n in helder.nodes) if (kept(n)) {
			var s = shape(n);
			if (s.rects.length > 0 || s.text.length > 0) b.set(n.path, s);
		}
		// (tree order: Chromium's, a node only helder has after the one it follows there)
		var order = [], after = new Map<String, Array<String>>(), lead = [], last:Null<String> = null;
		for (n in helder.nodes) {
			if (!b.exists(n.path)) continue;
			if (a.exists(n.path)) {
				last = n.path;
				continue;
			}
			if (last == null) lead.push(n.path) else {
				if (!after.exists(last)) after.set(last, []);
				after.get(last).push(n.path);
			}
		}
		order = order.concat(lead);
		for (n in chromium.nodes) {
			if (!a.exists(n.path)) continue;
			order.push(n.path);
			if (after.exists(n.path)) order = order.concat(after.get(n.path));
		}
		function parent(p:String):Null<String> {
			while (true) {
				var at = p.lastIndexOf(">");
				if (at < 0) return null;
				p = p.substr(0, at);
				if (a.exists(p) || b.exists(p)) return p;
			}
		}
		var kids = new Map<String, Array<String>>(), tops = [];
		for (p in order) {
			var up = parent(p);
			if (up == null) tops.push(p) else {
				if (!kids.exists(up)) kids.set(up, []);
				kids.get(up).push(p);
			}
		}
		// (each node against its own, in page coordinates and from its parent's top left)
		var own = new Map<String, Null<GeometryDifference>>(), near = new Map<String, Null<GeometryDifference>>();
		for (p in order) {
			var up = parent(p);
			var d = differ(p, a.get(p), b.get(p), [0, 0], [0, 0], tolerance);
			own.set(p, d);
			// (off from its parent too: where it is right in the page, it is right)
			near.set(p, d == null ? null : differ(p, a.get(p), b.get(p), origin(up == null ? null : a.get(up)), origin(up == null ? null : b.get(up)), tolerance));
		}
		var deep = new Map<String, Bool>();
		function differs(p:String):Bool {
			if (deep.exists(p)) return deep.get(p);
			var d = near.get(p) != null;
			if (!d) for (k in kids.get(p) ?? []) if (differs(k)) d = true;
			deep.set(p, d);
			return d;
		}
		function find(list:Array<String>):Null<String> {
			for (p in list) {
				if (!differs(p)) continue;
				var d = near.get(p);
				if (d != null && (d.what == "missing" || d.what == "extra" || d.moved)) return p;
				return find(kids.get(p) ?? []) ?? p;
			}
			return null;
		}
		var differences = [for (p in order) if (own.get(p) != null) own.get(p)];
		var culprit = find(tops);
		var first = culprit == null ? differences[0] : own.get(culprit);
		var up = first == null ? null : parent(first.path);
		var compared = 0;
		for (p in order) if (a.exists(p) && b.exists(p)) compared++;
		return new GeometryDiff(compared, differences, first, up == null || own.get(up) == null,
			[for (p in order) if (!b.exists(p)) p], [for (p in order) if (!a.exists(p)) p], tolerance);
	}

	// (a node's text fragments as lines: those touching on a line one, empty ones left out)
	static function shape(n:GeometryNode):GeometryNode {
		return {path: n.path, rects: lines(n.rects, false), text: lines(n.text, true)};
	}

	static function lines(list:Array<Array<Float>>, text:Bool):Array<Array<Float>> {
		var sorted = [for (r in list) if (!text || r[2] > 0.01) r.copy()];
		if (text) sorted.sort((p, q) -> p[1] != q[1] ? (p[1] < q[1] ? -1 : 1) : p[0] < q[0] ? -1 : p[0] > q[0] ? 1 : 0);
		var out:Array<Array<Float>> = [];
		for (r in sorted) {
			var l = out[out.length - 1];
			if (l != null && Math.abs(l[1] - r[1]) < 0.05 && Math.abs(l[3] - r[3]) < 0.05 && Math.abs(l[0] + l[2] - r[0]) < 0.05) {
				l[2] = r[0] + r[2] - l[0];
				if (text && r[5] > r[4]) {
					if (l[5] <= l[4]) {
						l[4] = r[4];
						l[5] = r[5];
					} else {
						l[4] = Math.min(l[4], r[4]);
						l[5] = Math.max(l[5], r[5]);
					}
				}
			} else
				out.push(r);
		}
		return out;
	}

	static function origin(n:Null<GeometryNode>):Array<Float>
		return n == null || n.rects.length == 0 ? [0, 0] : [n.rects[0][0], n.rects[0][1]];

	// (how a node differs, its rectangles taken from oa and ob; null: within tolerance)
	static function differ(path:String, a:Null<GeometryNode>, b:Null<GeometryNode>, oa:Array<Float>, ob:Array<Float>, tolerance:Float):Null<GeometryDifference> {
		if (a == null) return {path: path, what: "extra", chromium: [], helder: b.rects.concat(b.text), index: -1, delta: null, moved: false};
		if (b == null) return {path: path, what: "missing", chromium: a.rects.concat(a.text), helder: [], index: -1, delta: null, moved: false};
		// (generated text's ranges are of no node's data)
		var generated = path.indexOf("::") >= 0;
		for (what in ["box", "text"]) {
			var x = what == "box" ? a.rects : a.text, y = what == "box" ? b.rects : b.text;
			if (x.length != y.length) return {path: path, what: what, chromium: x, helder: y, index: -1, delta: null, moved: false};
			for (i in 0...x.length) {
				var d = [y[i][0] - ob[0] - (x[i][0] - oa[0]), y[i][1] - ob[1] - (x[i][1] - oa[1]), y[i][2] - x[i][2], y[i][3] - x[i][3]];
				var off = Lambda.exists(d, v -> Math.abs(v) > tolerance) || what == "text" && !generated && (x[i][4] != y[i][4] || x[i][5] != y[i][5]);
				if (off) return {path: path, what: what, chromium: x, helder: y, index: i, delta: d, moved: i == 0 && (Math.abs(d[0]) > tolerance || Math.abs(d[1]) > tolerance)};
			}
		}
		return null;
	}

	// The differences as a few lines for a terminal: the likely cause first, then up to `more`.
	public function describe(more = 5):String {
		if (match) return 'geometry matches ($compared nodes)';
		var out = ['geometry differs: ${differences.length} of $nodes nodes'];
		if (first != null) out.push('first: ${line(first, tolerance)}; its parent ${parentMatches ? "matches" : "differs too"}');
		var shown = 0;
		for (d in differences) {
			if (d == first || d.what == "missing" || d.what == "extra") continue;
			if (shown++ == more) break;
			out.push('  ${line(d, tolerance)}');
		}
		function some(list:Array<String>):String
			return list.slice(0, more).join(", ") + (list.length > more ? ' and ${list.length - more} more' : "");
		if (chromiumOnly.length > 0) out.push('only in Chromium: ${some(chromiumOnly)}');
		if (helderOnly.length > 0) out.push('only in helder: ${some(helderOnly)}');
		return out.join("\n");
	}

	// (a difference in words: helder's against Chromium's, by edge)
	public static function line(d:GeometryDifference, tolerance = 0.5):String {
		var at = d.path.substr(d.path.lastIndexOf(">") + 1);
		var head = '`$at` (${d.path})';
		return switch d.what {
			case "missing": '$head: not in helder\'s layout (Chromium: ${rects(d.chromium)})';
			case "extra": '$head: only in helder\'s layout (${rects(d.helder)})';
			case what if (d.index < 0):
				var unit = what == "box" ? "box" : "line", n = d.helder.length;
				'$head: $n ${n == 1 ? unit : unit == "box" ? "boxes" : "lines"}, Chromium ${d.chromium.length}: helder ${rects(d.helder)}, Chromium ${rects(d.chromium)}';
			case what:
				var x = d.chromium[d.index], y = d.helder[d.index];
				var part = what == "box" ? (d.chromium.length > 1 ? 'border box ${d.index + 1}' : "border box") : 'line ${d.index + 1}';
				var words = [];
				var e = d.delta;
				if (Math.abs(e[2]) > tolerance) words.push('${px(e[2])} too ${e[2] > 0 ? "wide" : "narrow"}');
				if (Math.abs(e[3]) > tolerance) words.push('${px(e[3])} too ${e[3] > 0 ? "tall" : "short"}');
				if (Math.abs(e[0]) > tolerance) words.push('${px(e[0])} too far ${e[0] > 0 ? "right" : "left"}');
				if (Math.abs(e[1]) > tolerance) words.push('${px(e[1])} too ${e[1] > 0 ? "low" : "high"}');
				var range = what == "text" && d.path.indexOf("::") < 0 && (x[4] != y[4] || x[5] != y[5]) ? ', characters ${y[4]}–${y[5]}, Chromium ${x[4]}–${x[5]}' : "";
				'$head: $part ${words.length > 0 ? words.join(", ") : "within tolerance"} (x ${sign(e[0])}, y ${sign(e[1])}, w ${sign(e[2])}, h ${sign(e[3])})$range; helder ${rect(y)}, Chromium ${rect(x)}';
		}
	}

	static function round(v:Float):Float
		return Math.round(v * 100) / 100;

	static function px(v:Float):String
		return '${round(Math.abs(v))} px';

	static function sign(v:Float):String
		return round(v) > 0 ? '+${round(v)}' : '${round(v)}';

	static function rect(r:Array<Float>):String
		return '[${[for (k in 0...4) round(r[k])].join(", ")}]';

	static function rects(list:Array<Array<Float>>):String
		return list.length == 0 ? "none" : [for (r in list.slice(0, 4)) rect(r)].join(" ") + (list.length > 4 ? " ..." : "");

	public function toJson():String
		return Json.stringify({
			match: match,
			compared: compared,
			first: first,
			parentMatches: parentMatches,
			differences: differences,
			chromiumOnly: chromiumOnly,
			helderOnly: helderOnly
		});
}

typedef GeometryDifference = {
	path:String,
	// "box", "text" (a node's rectangles or lines), "missing" (Chromium's alone), "extra" (helder's alone)
	what:String,
	chromium:Array<Array<Float>>,
	helder:Array<Array<Float>>,
	// the first rectangle or line off; -1: not as many on each side
	index:Int,
	// helder's minus Chromium's: x, y, width, height
	delta:Null<Array<Float>>,
	// (its first rectangle off from where its parent puts it)
	moved:Bool
}
