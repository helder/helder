import helder.css.Css;
import helder.css.CssBloom;
import helder.css.CssInvalidation;
import helder.css.CssMatcher;
import helder.css.CssRestyle;
import helder.css.CssRuleIndex;
import helder.css.CssSelector;
import helder.dom.Document;
import helder.dom.Dom;
import helder.dom.Element;
import helder.dom.ElementState;

// A viewer's rows restyled (the bench row lane, natively): 12 rows of 19
// elements each (an icon, a name and its line under, four facts, three
// buttons) in a list, under a sheet of the viewer's kind (rows, their
// hover and focus-within, a selected row, siblings' borders). Each
// operation (the rows made, a row hovered, unhovered, selected) timed with
// its restyle: the elements CssRestyle marks matched again through the
// rule index and Bloom filter; and, beside, every element matched again
// (no invalidation). The least of RUNS (200), in microseconds, with the
// elements marked.
class RowBench {
	static final SHEET = "
		.list { } .list > .row { } .row { } .row + .row { } .row:hover { } .row:hover .name .title { } .row:hover .actions { }
		.row:focus-within { } .row:focus-within .actions button { } .row.selected { } .row.selected .icon img { } .row.selected .title { }
		.row .icon { } .row .icon img { } .row .name { } .row .name .title { } .row .name .sub { } .row .meta { } .row .meta span { }
		.row .meta span:first-child { } .row .meta span + span { } .row .actions { } .row .actions button { } .row .actions button:hover { }
		.row .actions button:active { } .row .actions button:focus-visible { } .row .actions button span { } .list:has(.selected) .row { }
		button { } img { } span { } div { } .title { } .sub { } .hidden { } [disabled] { } :focus-visible { } .row:nth-child(odd) { }
	";

	static function main() {
		var runs = Std.parseInt(Sys.getEnv("RUNS") ?? "") ?? 200;
		var selectors = [];
		for (rule in Css.sheet(SHEET))
			switch rule {
				case Qualified(prelude, _, _): for (s in CssSelector.list(prelude) ?? []) selectors.push(s);
				default:
			}
		var index = new CssRuleIndex<Int>();
		for (k in 0...selectors.length)
			index.add(selectors[k], k);
		var sets = CssInvalidation.of(selectors);
		var bloom = new CssBloom(), out = [];

		function restyle(r:CssRestyle):Int {
			var marked = r.marked();
			for (el in marked) {
				bloom.moveTo(el);
				out.resize(0);
				index.matching(el, out, bloom);
			}
			r.clear();
			return marked.length;
		}
		function everything(doc:Document):Int {
			var all = CssMatcher.query(CssSelector.parse("*"), doc);
			for (el in all) {
				bloom.moveTo(el);
				out.resize(0);
				index.matching(el, out, bloom);
			}
			return all.length;
		}

		var doc:Document = null, r:CssRestyle = null, list:Element = null, rows:Array<Element> = [];
		function fresh() {
			doc = Dom.parse("<!doctype html><body><div class=list></div>");
			list = doc.body.firstElementChild;
			r = CssRestyle.attach(doc, sets);
			restyle(r);
		}
		function make() {
			rows = [];
			for (k in 0...12) {
				var row = el(doc, "div", "row");
				var icon = row.appendChild(el(doc, "div", "icon"));
				icon.appendChild(el(doc, "img", null));
				var name = row.appendChild(el(doc, "div", "name"));
				name.appendChild(el(doc, "span", "title"));
				name.appendChild(el(doc, "span", "sub"));
				var meta = row.appendChild(el(doc, "div", "meta"));
				for (_ in 0...4)
					meta.appendChild(el(doc, "span", null));
				var actions = row.appendChild(el(doc, "div", "actions"));
				for (_ in 0...3)
					actions.appendChild(el(doc, "button", null)).appendChild(el(doc, "span", null));
				list.appendChild(row);
				rows.push(row);
			}
		}

		var results = [];
		function op(name:String, setup:() -> Void, f:() -> Void) {
			var best = Math.POSITIVE_INFINITY, bestAll = Math.POSITIVE_INFINITY, marked = 0, all = 0;
			for (_ in 0...runs) {
				setup();
				var t = haxe.Timer.stamp();
				f();
				marked = restyle(r);
				best = Math.min(best, haxe.Timer.stamp() - t);
				setup();
				t = haxe.Timer.stamp();
				r.detach();
				f();
				all = everything(doc);
				bestAll = Math.min(bestAll, haxe.Timer.stamp() - t);
				r = CssRestyle.attach(doc, sets);
			}
			results.push('{"op":"$name","us":${Math.round(best * 1e7) / 10},"marked":$marked,"everything_us":${Math.round(bestAll * 1e7) / 10},"elements":$all}');
		}

		op("rows made", fresh, make);
		op("a row hovered", () -> {
			fresh();
			make();
			restyle(r);
		}, () -> rows[5].setState(ElementState.HOVER, true));
		op("a row unhovered", () -> {
			fresh();
			make();
			rows[5].setState(ElementState.HOVER, true);
			restyle(r);
		}, () -> rows[5].setState(ElementState.HOVER, false));
		op("a button focused", () -> {
			fresh();
			make();
			restyle(r);
		}, () -> {
			var b = rows[5].lastElementChild.firstElementChild;
			b.setState(ElementState.FOCUS | ElementState.FOCUS_VISIBLE | ElementState.FOCUS_WITHIN, true);
			var p = b.parentElement;
			while (p != null) {
				p.setState(ElementState.FOCUS_WITHIN, true);
				p = p.parentElement;
			}
		});
		op("a row selected", () -> {
			fresh();
			make();
			restyle(r);
		}, () -> rows[5].className = "row selected");
		for (l in results)
			Sys.println(l);
	}

	static function el(doc:Document, tag:String, cls:Null<String>):Element {
		var e = doc.createElement(tag);
		if (cls != null) e.className = cls;
		return e;
	}
}
