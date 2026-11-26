import helder.css.CssCascade;
import helder.css.CssInvalidation;
import helder.css.CssMatcher;
import helder.css.CssRestyle;
import helder.css.CssSelector;
import helder.css.CssSheet;
import helder.css.CssStyles;
import helder.dom.Document;
import helder.dom.Dom;
import helder.dom.Element;
import helder.dom.ElementState;

// A viewer's rows restyled (the bench row lane, natively): 12 rows of 18
// elements each (an icon, a name and its line under, four facts, three
// buttons) in a list, under the user agent's sheet and one of the viewer's
// kind (rows, their hover and focus-within, a selected row, siblings'
// borders). Each operation (12 more rows made in the styled list, a row
// hovered, unhovered, a button focused, a row selected) is timed with
// its restyle: the elements
// CssRestyle marks forgotten and styled again (CssStyles: the
// style-sharing cache, the rule index and Bloom filter, the cascade); and,
// beside, every element styled again without the sharing cache. The least
// of RUNS (200), in microseconds, with the elements marked and shared.
class RowBench {
	static final SHEET = "
		.list { display: flex; flex-direction: column } .list > .row { margin: 0 } .row { display: flex; padding: 4px; color: #222 }
		.row + .row { border-top: 1px solid #eee } .row:hover { background: #f4f4f4 } .row:hover .name .title { color: #000 }
		.row:hover .actions { opacity: 1 } .row:focus-within { outline: 1px solid blue } .row:focus-within .actions button { opacity: 1 }
		.row.selected { background: #dde } .row.selected .icon img { filter: none } .row.selected .title { font-weight: bold }
		.row .icon { width: 24px } .row .icon img { width: 24px; height: 24px } .row .name { flex: 1 } .row .name .title { font-size: 14px }
		.row .name .sub { font-size: 12px; color: #666 } .row .meta { display: flex; gap: 8px } .row .meta span { color: #888 }
		.row .meta span:first-child { color: #444 } .row .meta span + span { margin-left: 4px } .row .actions { opacity: 0 }
		.row .actions button { border: 0; background: none } .row .actions button:hover { color: blue } .row .actions button:active { color: navy }
		.row .actions button:focus-visible { outline: 2px solid blue } .row .actions button span { font-size: 12px }
		.list:has(.selected) .row { opacity: 0.9 } .row:nth-child(odd) { background: #fafafa } [disabled] { opacity: 0.5 }
	";

	static function main() {
		var runs = Std.parseInt(Sys.getEnv("RUNS") ?? "") ?? 200;
		var author = [CssSheet.parse(SHEET, Author)];
		var selectors = [];
		for (r in author[0].rules)
			switch r {
				case Style(list, _): for (s in list) selectors.push(s);
				default:
			}
		var sets = CssInvalidation.of(selectors);
		var star = CssSelector.parse("*");

		var doc:Document = null, r:CssRestyle = null, list:Element = null, rows:Array<Element> = [];
		var shared:CssStyles = null, plain:CssStyles = null;
		function styleAll(s:CssStyles)
			for (el in CssMatcher.query(star, doc))
				s.computed(el);
		function fresh() {
			doc = Dom.parse("<!doctype html><body><div class=list></div>");
			list = doc.body.firstElementChild;
			shared = CssCascade.styles(doc, {author: author});
			plain = CssCascade.styles(doc, {author: author, share: false});
			styleAll(shared);
			styleAll(plain);
			r = CssRestyle.attach(doc, sets);
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
		// (the marked forgotten and styled again; then the marks cleared)
		function restyle():{marked:Int, shares:Int} {
			var marked = r.marked(), before = shared.shares;
			shared.forget(marked);
			for (el in marked)
				shared.computed(el);
			r.clear();
			return {marked: marked.length, shares: shared.shares - before};
		}
		function everything():Int {
			var all = CssMatcher.query(star, doc);
			plain.forget(all);
			for (el in all)
				plain.computed(el);
			return all.length;
		}
		function ready() {
			fresh();
			make();
			restyle();
			everything();
		}

		var results = [];
		function op(name:String, setup:() -> Void, f:() -> Void) {
			var best = Math.POSITIVE_INFINITY, bestAll = Math.POSITIVE_INFINITY, last = {marked: 0, shares: 0}, all = 0;
			for (_ in 0...runs) {
				setup();
				var t = haxe.Timer.stamp();
				f();
				last = restyle();
				best = Math.min(best, haxe.Timer.stamp() - t);
				setup();
				r.detach();
				t = haxe.Timer.stamp();
				f();
				all = everything();
				bestAll = Math.min(bestAll, haxe.Timer.stamp() - t);
			}
			results.push('{"op":"$name","us":${Math.round(best * 1e7) / 10},"marked":${last.marked},"shared":${last.shares},"everything_us":${Math.round(bestAll * 1e7) / 10},"elements":$all}');
		}

		// (12 more rows added to a list already styled, as an app adds them)
		op("rows made", ready, make);
		op("a row hovered", ready, () -> rows[5].setState(ElementState.HOVER, true));
		op("a row unhovered", () -> {
			ready();
			rows[5].setState(ElementState.HOVER, true);
			restyle();
			everything();
		}, () -> rows[5].setState(ElementState.HOVER, false));
		op("a button focused", ready, () -> {
			var b = rows[5].lastElementChild.firstElementChild;
			b.setState(ElementState.FOCUS | ElementState.FOCUS_VISIBLE | ElementState.FOCUS_WITHIN, true);
			var p = b.parentElement;
			while (p != null) {
				p.setState(ElementState.FOCUS_WITHIN, true);
				p = p.parentElement;
			}
		});
		op("a row selected", ready, () -> rows[5].className = "row selected");
		for (l in results)
			Sys.println(l);
	}

	static function el(doc:Document, tag:String, cls:Null<String>):Element {
		var e = doc.createElement(tag);
		if (cls != null) e.className = cls;
		return e;
	}
}
