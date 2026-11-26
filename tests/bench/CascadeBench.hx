import haxe.DynamicAccess;
import helder.css.CssCascade;
import helder.css.CssData;
import helder.dom.Dom;
import helder.dom.Element;
import sys.io.File;

// helder.css's cascade on a page, timed by phase, the least of runs (bench
// cascade): the page parsed (helder.dom, apart), its sheets read and indexed,
// every element's cascade (its rules matched and sorted), then every
// element's computed value of each longhand.
//
//   bin/bench/CascadeBench <page.html> <sheets.json: URL to file> <runs>
class CascadeBench {
	static function main() {
		var args = Sys.args();
		var html = File.getContent(args[0]);
		var files:DynamicAccess<String> = haxe.Json.parse(File.getContent(args[1]));
		var runs = Std.parseInt(args[2]) ?? 3;
		var longhands = [for (p in CssData.properties) if (p.longhands.length == 0 && p.alias == null) p.name];
		var best = {parse: 1e9, sheets: 1e9, cascade: 1e9, computed: 1e9};
		var elements = 0, rules = 0;
		for (_ in 0...runs) {
			var t0 = haxe.Timer.stamp();
			var doc = Dom.parse(html);
			var t1 = haxe.Timer.stamp();
			var styles = CssCascade.styles(doc, {load: url -> files.exists(url) ? File.getContent(files[url]) : null, url: "https://html.spec.whatwg.org/"});
			var t2 = haxe.Timer.stamp();
			var all = elementsOf(doc.documentElement);
			elements = all.length;
			for (el in all) styles.computed(el);
			var t3 = haxe.Timer.stamp();
			for (el in all) {
				var s = styles.computed(el);
				for (p in longhands) s.get(p);
			}
			var t4 = haxe.Timer.stamp();
			best.parse = Math.min(best.parse, t1 - t0);
			best.sheets = Math.min(best.sheets, t2 - t1);
			best.cascade = Math.min(best.cascade, t3 - t2);
			best.computed = Math.min(best.computed, t4 - t3);
		}
		inline function ms(s:Float)
			return Math.round(s * 1e4) / 10;
		Sys.println(haxe.Json.stringify({
			elements: elements,
			longhands: longhands.length,
			parse: ms(best.parse),
			sheets: ms(best.sheets),
			cascade: ms(best.cascade),
			computed: ms(best.computed),
			perElement: Math.round((best.cascade + best.computed) / elements * 1e7) / 1e4
		}));
	}

	static function elementsOf(root:Element):Array<Element> {
		var out = [], stack = [root];
		while (stack.length > 0) {
			var e = stack.pop();
			out.push(e);
			var c = e.lastElementChild;
			while (c != null) {
				stack.push(c);
				c = c.previousElementSibling;
			}
		}
		return out;
	}
}
