import haxe.DynamicAccess;
import helder.css.CssCascade;
import helder.css.CssData;
import helder.css.CssProperties;
import helder.css.CssProperty;
import helder.css.CssStyles;
import helder.dom.Dom;
import helder.dom.Element;
import sys.io.File;

// helder.css's cascade on a page, timed by phase, the least of runs (bench
// cascade), natively: the page parsed (helder.dom, apart), its sheets read
// and indexed, every element's style (its rules matched, its groups made
// or shared), then every stored longhand read typed. The collector's
// share of the styles' phase, what they allocate and keep, the groups and
// styles made; then the styles against #321's cascade (frozen): every
// element's display, margin-top, color and font-size, every 37th's every
// longhand; and against the same cascade without the sharing cache.
//
//   bin/bench/CascadeBench <page.html> <sheets.json: URL to file> <runs>
class CascadeBench {
	static function main() {
		var args = Sys.args();
		var html = File.getContent(args[0]);
		var files:DynamicAccess<String> = haxe.Json.parse(File.getContent(args[1]));
		var runs = Std.parseInt(args[2]) ?? 3;
		var load = (url:String) -> files.exists(url) ? File.getContent(files[url]) : null;
		var options = {load: load, url: "https://html.spec.whatwg.org/"};
		var best = {parse: 1e9, sheets: 1e9, styles: 1e9, read: 1e9, gc: 0.0, allocated: 0.0};
		var elements = 0;
		for (_ in 0...runs) {
			var t0 = haxe.Timer.stamp();
			var doc = Dom.parse(html);
			var t1 = haxe.Timer.stamp();
			var styles = CssCascade.styles(doc, options);
			var t2 = haxe.Timer.stamp();
			var all = elementsOf(doc.documentElement);
			elements = all.length;
			var gc0 = GcStats.seconds(), bytes0 = GcStats.bytes();
			var t3 = haxe.Timer.stamp();
			for (el in all) styles.computed(el);
			var t4 = haxe.Timer.stamp();
			var gc = GcStats.seconds() - gc0, allocated = GcStats.bytes() - bytes0;
			var n = 0;
			for (el in all) {
				var s = styles.computed(el);
				for (k in 0...CssProperties.COUNT) if (!CssProperties.logical(cast k)) n += s.terms(cast k).length;
			}
			var t5 = haxe.Timer.stamp();
			best.parse = Math.min(best.parse, t1 - t0);
			best.sheets = Math.min(best.sheets, t2 - t1);
			if (t4 - t3 < best.styles) {
				best.styles = t4 - t3;
				best.gc = gc;
				best.allocated = allocated;
			}
			best.read = Math.min(best.read, t5 - t4);
		}
		// (what the styles keep: the heap with them and without, after a full collection)
		var doc = Dom.parse(html);
		var all = elementsOf(doc.documentElement);
		hxmc.NativeGc.collect(true);
		var before = hxmc.GcStats.liveBytes();
		var kept = CssCascade.styles(doc, options);
		for (el in all) kept.computed(el);
		hxmc.NativeGc.collect(true);
		var after = hxmc.GcStats.liveBytes();
		var counts = kept.counts();
		// (against #321's cascade)
		var old = reference.RefCascade.styles(doc, {load: load, url: options.url});
		// (page-break-* left out: they now map break-*'s values, as Break 3 §3.4 says; #321 gave auto)
		var longhands = [for (p in CssData.properties) if (p.longhands.length == 0 && p.alias == null && p.name != "all" && !LOGICAL.match(p.name)
			&& !StringTools.startsWith(p.name, "page-break-") && !~/^(border-(top|right|bottom|left)-width|outline-width)$/.match(p.name)) p.name];
		var checked = 0, differ = [], differs = 0;
		for (k in 0...all.length) {
			var props = k % 37 == 0 ? longhands : ["display", "margin-top", "color", "font-size"];
			var a = kept.computed(all[k]), b = old.computed(all[k]);
			for (p in props) {
				checked++;
				if (a.text(p) == b.text(p)) continue;
				differs++;
				if (differ.length < 20) differ.push('${all[k].localName} $p: ${a.text(p)} (#321: ${b.text(p)})');
			}
		}
		// (the sharing cache against none: the same values)
		var plain = CssCascade.styles(doc, {load: load, url: options.url, share: false});
		var sharingChecked = 0, sharingDiffer = [], sharingDiffers = 0;
		for (k in 0...all.length) {
			var props = k % 37 == 0 ? longhands : ["display", "margin-top", "color", "font-size"];
			var a = kept.computed(all[k]), b = plain.computed(all[k]);
			for (p in props) {
				sharingChecked++;
				if (a.text(p) == b.text(p)) continue;
				sharingDiffers++;
				if (sharingDiffer.length < 20) sharingDiffer.push('${all[k].localName} $p: ${a.text(p)} (no sharing: ${b.text(p)})');
			}
		}
		inline function ms(s:Float)
			return Math.round(s * 1e4) / 10;
		var groups = {};
		for (g => n in counts.groups) Reflect.setField(groups, g, n);
		Sys.println(haxe.Json.stringify({
			elements: elements,
			parse: ms(best.parse),
			sheets: ms(best.sheets),
			styles: ms(best.styles),
			read: ms(best.read),
			gcShare: Math.round(best.gc / best.styles * 1000) / 10,
			allocatedPerElement: Math.round(best.allocated / elements),
			keptPerElement: Math.round((after - before) / elements),
			shares: kept.shares,
			hits: kept.hits,
			misses: kept.misses,
			styles_: counts.styles,
			groups: groups,
			parity: {checked: checked, differs: differs, first: differ},
			sharing: {checked: sharingChecked, differs: sharingDiffers, first: sharingDiffer}
		}));
	}

	static final LOGICAL = ~/(margin|padding|inset|border)-(block|inline)|(min-|max-|\b)(inline|block)-size|border-(start|end)-(start|end)-radius/;

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
