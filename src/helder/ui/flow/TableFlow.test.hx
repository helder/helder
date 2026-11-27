package helder.ui.flow;

import helder.css.CssCascade;
import helder.dom.Dom;
import helder.dom.Element;
import helder.test.Gen;
import helder.test.Test;
import helder.ui.box.BoxTree;
import helder.ui.box.FontMatch;
import helder.ui.box.Fragments;
import helder.ui.box.TableGrid;
import helder.ui.flow.TableFlow;

// Tables: anonymous table objects, the grid (colspan, rowspan), the auto
// and fixed width algorithms, border-spacing, row heights and
// vertical-align in cells, captions, the collapsing border model's
// winners and its lines' halves. Then a property: the columns' widths
// are at least their min-content and add up to the width given.
function tests() {
	describe("TableFlow", () -> {
		test("anonymous table objects", () -> {
			// (consecutive parts share one anonymous table; text between them parts them)
			var one = build('<div style="display:table-cell">a</div><span style="display:table-row"><b>b</b></span>').dump();
			equals(one.split("\n").filter(l -> StringTools.trim(l) == "TableWrapper").length, 1);
			var two = build('<div style="display:table-cell">a</div>x<span style="display:table-row"><b>b</b></span>').dump();
			equals(two.split("\n").filter(l -> StringTools.trim(l) == "TableWrapper").length, 2);
			// (white space between a table's parts dropped)
			var t = build('<table>\n <tr>\n  <td>x</td>\n </tr>\n</table>');
			equals(StringTools.trim(t.dump()).split("\n").filter(l -> l.indexOf("Text") >= 0).length, 1);
		});
		test("the grid: spans, spacing, widths", () -> {
			var v = view('<table id=t style="border-spacing:2px;border:1px solid"><tr><td id=a colspan=2 style="width:100px;padding:0">a</td><td id=b rowspan=2 style="padding:0">b</td>'
				+ '<tr><td id=c style="width:30px;padding:0">c</td><td id=d style="width:40px;padding:0">d</td></table>');
			var a = rect(v, "a"), b = rect(v, "b"), c = rect(v, "c"), d = rect(v, "d");
			equals(c[0], 3.0);
			equals(d[0], c[0] + c[2] + 2);
			equals(a[2], d[0] + d[2] - c[0]);
			equals(b[3], c[1] + c[3] - a[1]);
		});
		test("fixed layout: the first row's widths, the rest shared", () -> {
			var v = view('<table style="table-layout:fixed;width:300px;border-spacing:0"><tr><td id=a style="width:100px;padding:0">a</td><td id=b style="padding:0">b</td><td id=c style="padding:0">c</td>'
				+ '<tr><td id=d style="width:250px;padding:0">wide</td></table>');
			equals(rect(v, "a")[2], 100.0);
			equals(rect(v, "b")[2], 100.0);
			equals(rect(v, "c")[2], 100.0);
		});
		test("rows: heights, vertical-align, captions", () -> {
			var v = view('<table style="border-spacing:0"><caption id=cap style="height:10px">c</caption><tr style="height:50px"><td id=a style="padding:0;vertical-align:top">a</td>'
				+ '<td id=b style="padding:0;vertical-align:bottom">b</td><td id=m style="padding:0;vertical-align:middle;height:20px"></td></table>');
			var cap = rect(v, "cap"), a = rect(v, "a"), b = rect(v, "b");
			equals(cap[3], 10.0);
			equals(a[1], cap[1] + 10);
			equals(a[3], 50.0);
			equals(b[3], 50.0);
			var text = firstText(v, "b");
			equals(text[1] + text[3], b[1] + 50);
		});
		test("the collapsing model: what wins", () -> {
			assert(TableGrid.wins(3, "solid", 1, "solid"));
			assert(!TableGrid.wins(1, "solid", 3, "dotted"));
			assert(TableGrid.wins(2, "double", 2, "solid"));
			assert(!TableGrid.wins(5, "solid", 1, "hidden"));
			assert(TableGrid.wins(0, "hidden", 9, "solid"));
			var v = view('<table id=t style="border-collapse:collapse;border:4px solid"><tr><td id=a style="border:2px solid;padding:0">a</td><td id=b style="border:6px solid;padding:0">b</td></table>');
			var a = rect(v, "a"), b = rect(v, "b");
			// (the line between a and b is b's 6px: 3 in a, 3 in b; the table's 4px: 2 outside, 2 in a)
			equals(b[0] - a[0], a[2]);
			equals(rect(v, "t")[0] + 2, a[0]);
		});
		test("the collapsing model's lines split in whole pixels, or exactly without a pixel grid", () -> {
			var html = '<table style="border-collapse:collapse"><tr><td id=a style="padding:3px;border-bottom:1px solid">a</td></tr>'
				+ '<tr><td id=b style="padding:3px;border-bottom:1px solid">b</td></tr><tr><td id=f style="padding:4px;border-top:2px solid">f</td></tr></table>';
			var v = view(html);
			equals([rect(v, "a")[3], rect(v, "b")[1], rect(v, "b")[3], rect(v, "f")[1]], [16.0, 16, 18, 34]);
			var x = view(html, true);
			equals([rect(x, "a")[3], rect(x, "b")[1], rect(x, "b")[3], rect(x, "f")[1]], [16.5, 16.5, 17.5, 34]);
			equals([firstText(v, "b")[1], firstText(x, "b")[1], firstText(v, "f")[1], firstText(x, "f")[1]], [20.0, 20, 39, 39]);
		});
		test("the columns take the width given, each its min-content at least", () -> property(COLUMNS, cols -> {
			var min = 0.0;
			for (c in cols.list) min += c.min;
			var out = TableFlow.distribute(cols.list, cols.width);
			var sum = 0.0;
			for (k in 0...out.length) {
				assert(out[k] >= cols.list[k].min - 1e-6, 'column $k: ${out[k]} under ${cols.list[k].min}');
				sum += out[k];
			}
			approx(sum, Math.max(cols.width, min), 1e-6);
		}, {cases: 400}));
	});
}

private final COLUMNS:Gen<{list:Array<TableColumn>, width:Float}> = c -> {
	var n = c.draw(int(1, 6));
	var list:Array<TableColumn> = [for (_ in 0...n) {
		var min = c.draw(int(0, 80)) * 1.0;
		{min: min, max: min + c.draw(int(0, 120)), pct: c.draw(pick([0, 0, 0, 10, 25, 50])), fixed: c.draw(pick([false, false, true]))};
	}];
	{list: list, width: c.draw(int(0, 800)) * 1.0};
};

private function build(body:String):BoxTree {
	var doc = Dom.parse('<!doctype html><body>$body');
	return BoxTree.build(doc, CssCascade.styles(doc), {contexts: helder.ui.flow.Contexts.all(), counters: s -> new helder.css.CssCounters(s)});
}

private class Laid {
	public final document:helder.dom.Document;
	public final fragments = new Fragments();

	public function new(doc:helder.dom.Document, exact = false) {
		document = doc;
		var fonts = new FontMatch();
		fonts.register(sys.io.File.getBytes("tests/flow/fixtures/Ahem.ttf"), "Ahem");
		var tree = BoxTree.build(doc, CssCascade.styles(doc, {media: {type: "screen", width: 800, height: 600}, hints: true}), {contexts: helder.ui.flow.Contexts.all(), counters: s -> new helder.css.CssCounters(s)});
		var space = new Space(fragments, fonts, 800, 600);
		space.exact = exact;
		tree.root.context.layout(tree.root, space);
	}
}

private function view(body:String, exact = false):Laid
	return new Laid(Dom.parse('<!doctype html><style>body { margin: 0; font: 10px/1 Ahem }</style><body>$body'), exact);

private function rect(v:Laid, id:String):Array<Float> {
	var el:Element = v.document.getElementById(id);
	var f = v.fragments;
	var k = f.count;
	while (k-- > 0)
		if (f.kind(k) == Fragments.BOX && helder.ui.box.BoxTree.nodeOf(f.box(k)) == el && f.box(k).kind != TableWrapper && f.parent(k) >= 0) {
			var at = f.absolute(k);
			return [at.x, at.y, f.width(k), f.height(k)];
		}
	return [];
}

// (the first text fragment in an element's box)
private function firstText(v:Laid, id:String):Array<Float> {
	var el:Element = v.document.getElementById(id);
	var f = v.fragments;
	for (k in 0...f.count)
		if (f.kind(k) == Fragments.TEXT) {
			var p = f.parent(k);
			while (p >= 0 && helder.ui.box.BoxTree.nodeOf(f.box(p)) != el) p = f.parent(p);
			if (p >= 0) {
				var at = f.absolute(k);
				return [at.x, at.y, f.width(k), f.height(k)];
			}
		}
	return [];
}
