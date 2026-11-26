import helder.css.Css;
import helder.css.CssMatcher;
import helder.css.CssRule;
import helder.css.CssRuleIndex;
import helder.css.CssSelector;
import helder.dom.Dom;
import helder.dom.Element;
import sys.io.File;

// helder.css's selector matching on a page (the bench match lane,
// natively): every element against every selector of the sheets given
// (their style rules, those in @media and @supports too), three ways:
// each selector tried on each element (before: no index), the rule index
// alone, and the index with the ancestor Bloom filter during a walk. The
// least of RUNS (5, the naive way once); a JSON line each, with what the
// index visited and the filter rejected, and the matches (the same every
// way, or the bench fails).
//
//   MatchBench <page.html> <sheet.css>...
class MatchBench {
	static function main() {
		var args = Sys.args(), page = args.shift(), runs = Std.parseInt(Sys.getEnv("RUNS") ?? "") ?? 5;
		var doc = Dom.parse(File.getContent(page)), selectors = [];
		for (path in args)
			collect(Css.sheet(Css.decode(File.getBytes(path)).text), selectors);
		var elements = CssMatcher.query(CssSelector.parse("*"), doc);
		var name = haxe.io.Path.withoutDirectory(page);

		var t = haxe.Timer.stamp(), naive = 0;
		for (el in elements)
			for (s in selectors)
				if (CssMatcher.matches(s, el)) naive++;
		line(name, elements.length, selectors.length, "each selector", (haxe.Timer.stamp() - t) * 1000, elements.length * selectors.length, 0, naive);

		var index = new CssRuleIndex<Int>();
		for (k in 0...selectors.length)
			index.add(selectors[k], k);
		var out = [];
		var best = least(runs, () -> {
			index.resetStats();
			for (el in elements) {
				out.resize(0);
				index.matching(el, out);
			}
		});
		check(index.matched, naive, "index");
		line(name, elements.length, selectors.length, "index", best, index.visited, index.rejected, index.matched);

		best = least(runs, () -> {
			index.resetStats();
			index.walk(doc, (_, _) -> {});
		});
		check(index.matched, naive, "index and Bloom filter");
		line(name, elements.length, selectors.length, "index and Bloom filter", best, index.visited, index.rejected, index.matched);
	}

	// (the selectors of a sheet's style rules, through @media, @supports and @layer blocks)
	static function collect(rules:Array<CssRule>, out:Array<CssSelector>)
		for (r in rules)
			switch r {
				case Qualified(prelude, _, _):
					var l = CssSelector.list(prelude);
					if (l != null) for (s in l) out.push(s);
				case At(name, _, block) if (block != null && ["media", "supports", "layer"].contains(Css.lower(name))):
					collect(block, out);
				default:
			}

	static function least(runs:Int, f:() -> Void):Float {
		f();
		var best = Math.POSITIVE_INFINITY;
		for (_ in 0...runs) {
			var t = haxe.Timer.stamp();
			f();
			best = Math.min(best, (haxe.Timer.stamp() - t) * 1000);
		}
		return best;
	}

	static function check(got:Int, want:Int, what:String)
		if (got != want) {
			Sys.println('MatchBench: the $what matched $got, each selector $want');
			Sys.exit(1);
		}

	static function line(page:String, elements:Int, selectors:Int, way:String, ms:Float, visited:Int, rejected:Int, matched:Int)
		Sys.println('{"page":"$page","elements":$elements,"selectors":$selectors,"way":"$way","ms":${Math.round(ms * 10) / 10},"visited":$visited,"rejected":$rejected,"matched":$matched}');
}
