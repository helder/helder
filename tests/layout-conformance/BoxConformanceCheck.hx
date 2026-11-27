import haxe.DynamicAccess;
import haxe.Json;
import helder.dom.Dom;
import helder.dom.Element;
import helder.ui.box.DocumentView;
import helder.ui.box.FontMatch;
import helder.ui.box.Fragments;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// Taffy's fixtures (Chrome's boxes) through helder's CSS engine, natively:
// each fixture's tree made the page Taffy's gentest gave Chrome (each node
// a div, Taffy's defaults: display flex, position relative; text in Ahem
// 10px/1, broken at its zero-width spaces; the root at the start of a
// max-content flex row unless the viewport is given), laid out by
// DocumentView, each node's border box compared, x and y from its
// parent's, within TOLERANCE pixels. All four variants: box-sizing and
// direction are CSS's here. box-manifest.json gates them as
// manifest.json does helder.ui's: a case is required unless pending says
// why; a pending one that passes fails the run too, until BLESS=1.
// SHOW=1 prints each case that fails.
//
//   BoxConformanceCheck [filter...]   (a fixture id's part: those alone)
class BoxConformanceCheck {
	static final here = "tests/layout-conformance";
	static inline var TOLERANCE = 0.5;
	static final VARIANTS = ["border-box-ltr", "border-box-rtl", "content-box-ltr", "content-box-rtl"];

	static function main() {
		helder.text.Shaping.engine = helder.text.Shaping.HELDER;
		var filters = Sys.args();
		var bless = Sys.getEnv("BLESS") == "1";
		// (SHOW=1: each case that fails, and how)
		var show = Sys.getEnv("SHOW") == "1";
		var path = '$here/box-manifest.json';
		var manifest:DynamicAccess<Dynamic> = FileSystem.exists(path) ? Json.parse(File.getContent(path)).cases : {};
		var next:DynamicAccess<Dynamic> = {};
		var fonts = new FontMatch();
		fonts.register(File.getBytes("tests/flow/fixtures/Ahem.ttf"), "Ahem");
		var ids = [];
		for (cat in FileSystem.readDirectory('$here/fixtures')) if (FileSystem.isDirectory('$here/fixtures/$cat'))
			for (f in FileSystem.readDirectory('$here/fixtures/$cat')) if (f.endsWith(".json")) ids.push('$cat/${f.substr(0, f.length - 5)}');
		ids.sort(Reflect.compare);
		var failures = [], fixed = [], stats = new Map<String, {pass:Int, total:Int}>();
		for (id in ids) {
			var cat = id.split("/")[0];
			var st = stats.get(cat);
			if (st == null) stats.set(cat, st = {pass: 0, total: 0});
			for (v in VARIANTS) {
				var key = '$id $v';
				var entry:Dynamic = manifest[key];
				if (filters.length > 0 && !Lambda.exists(filters, f -> key.indexOf(f) >= 0)) {
					if (entry != null) next[key] = entry;
					continue;
				}
				st.total++;
				var fixture:Dynamic = Json.parse(File.getContent('$here/fixtures/$id.json'));
				var r = try layout(fixture, v, fonts) catch (e:Dynamic) {ok: false, reason: 'error: ${Std.string(e).split("\n")[0]}'};
				var pending:Null<String> = entry == null ? "new" : entry.pending;
				if (r.ok) {
					st.pass++;
					if (pending != null && entry != null) fixed.push(key);
					next[key] = {};
				} else {
					if (show) Sys.println('$key: ${r.reason}');
					if (pending == null) failures.push('$key: ${r.reason}');
					next[key] = {pending: bless || pending == null || pending == "new" ? r.reason : pending};
				}
			}
		}
		var pass = 0, total = 0;
		for (cat => s in stats) {
			Sys.println('$cat: ${s.pass} of ${s.total}');
			pass += s.pass;
			total += s.total;
		}
		Sys.println('all: $pass of $total cases pass');
		if (bless) {
			var keys = [for (k in next.keys()) k];
			keys.sort(Reflect.compare);
			var lines = [for (k in keys) '\t\t${Json.stringify(k)}: ${Json.stringify(next[k])}'];
			File.saveContent(path, '{\n\t"schema": 1,\n\t"cases": {\n${lines.join(",\n")}\n\t}\n}\n');
			Sys.println('BLESS: $path');
			return;
		}
		for (f in failures) Sys.println("FAIL " + f);
		for (f in fixed) Sys.println("FIXED " + f + " (BLESS=1 to require it)");
		if (failures.length + fixed.length > 0) {
			Sys.println('BoxConformanceCheck: ${failures.length} required failing, ${fixed.length} pending passing');
			Sys.exit(1);
		}
	}

	// (the fixture's page in a variant: its nodes' boxes against Chrome's)
	static function layout(f:Dynamic, variant:String, fonts:FontMatch):{ok:Bool, reason:String} {
		var sizing = variant.startsWith("border-box") ? "border-box" : "content-box", dir = variant.endsWith("rtl") ? "rtl" : "ltr";
		var count = 0;
		var body = new StringBuf();
		function node(t:Dynamic, root:Bool) {
			var style:DynamicAccess<String> = t.style;
			// (Taffy's border-<side>: a width, solid)
			var css = [for (k => v in style) k.startsWith("border-") && k.split("-").length == 2 ? '$k: $v solid' : '$k: $v'];
			if (root && f.viewport.width == "max-content" && style.get("position") == "absolute") css.push("position: relative");
			body.add('<div id=n${count++} style="${css.join("; ")}">');
			if (t.text != null) body.add(StringTools.htmlEscape(t.text));
			var ch:Array<Dynamic> = t.children ?? [];
			for (c in ch) node(c, false);
			body.add("</div>");
		}
		node(f.tree, true);
		var html = '<!doctype html><style>body { margin: 0; font: 10px/1 Ahem } div { display: flex; position: relative; box-sizing: $sizing; direction: $dir }'
			+ ' #v { position: absolute; left: 0; top: 0; flex-direction: row; align-items: start; width: ${f.viewport.width}; height: ${f.viewport.height} }</style>'
			+ '<div id=v>${body.toString()}</div>';
		var doc = Dom.parse(html);
		var view = DocumentView.html(doc, {fonts: fonts});
		view.layout(100000, 100000);
		var frags = view.fragments;
		function boxOf(el:Element):Int {
			for (k in 0...frags.count) if (frags.kind(k) == Fragments.BOX && helder.ui.box.BoxTree.nodeOf(frags.box(k)) == el && boxIn(frags, k, view.root)) return k;
			return -1;
		}
		var want:Array<Array<Float>> = Reflect.field(f.variants, variant);
		var bad = [];
		for (i in 0...count) {
			var el = doc.getElementById('n$i');
			var k = boxOf(el);
			var got = if (k < 0) [0.0, 0, 0, 0] else {
				var p = boxOf(cast el.parentNode);
				var a = frags.absolute(k), o = p < 0 ? a : frags.absolute(p);
				// (rounded as Taffy's fixtures are: each edge to a whole pixel, in the page's coordinates)
				if (f.rounding) {
					var x0 = Math.round(a.x), y0 = Math.round(a.y), px = Math.round(o.x), py = Math.round(o.y);
					[(x0 - px : Float), y0 - py, Math.round(a.x + frags.width(k)) - x0, Math.round(a.y + frags.height(k)) - y0];
				} else [a.x - o.x, a.y - o.y, frags.width(k), frags.height(k)];
			}
			var w = want[i];
			for (j in 0...4)
				if (Math.abs(got[j] - w[j]) > TOLERANCE) {
					bad.push('node $i [${got.join(" ")}], Chrome [${w.join(" ")}]');
					break;
				}
		}
		return bad.length == 0 ? {ok: true, reason: ""} : {ok: false, reason: "differs: " + bad[0] + (bad.length > 1 ? ' (+${bad.length - 1})' : "")};
	}

	// (a fragment in the laid out tree, not one a cache left behind)
	static function boxIn(f:Fragments, k:Int, root:Int):Bool {
		var p = k;
		while (p >= 0) {
			if (p == root) return true;
			p = f.parent(p);
		}
		return false;
	}
}
