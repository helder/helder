package helder.ui.flow;

import helder.dom.Dom;
import helder.dom.Element;
import helder.test.Gen;
import helder.test.Test;
import helder.css.CssCascade;
import helder.ui.box.BoxTree;
import helder.ui.box.FontMatch;
import helder.ui.box.Fragments;

// Block layout: widths and auto margins, min and max, box-sizing,
// percentages, heights, aspect-ratio, containment, the sizing keywords, margin collapsing (siblings, negative, parent and
// child, through empty boxes, not across a formatting context's root),
// relative offsets, the layout cache. Then a property: siblings' places
// as a plain model of §8.3.1 has them.
function tests() {
	describe("BlockFlow", () -> {
		test("widths", () -> {
			var v = view('<div id=a style="width:200px;margin:0 auto"></div><div id=b style="width:100px;margin:0 10px"></div>'
				+ '<div id=c style="width:50%;padding:0 10px;border:0 solid;border-left-width:4px;box-sizing:border-box"></div>'
				+ '<div id=d style="max-width:100px;min-width:300px"></div><div id=e style="margin-left:-20px"></div>');
			equals(rect(v, "a"), [300.0, 1, 200, 0]);
			equals(rect(v, "b"), [10.0, 1, 100, 0]);
			equals(rect(v, "c"), [0.0, 1, 400, 0]);
			equals(rect(v, "d"), [0.0, 1, 300, 0]);
			equals(rect(v, "e"), [-20.0, 1, 820, 0]);
		});
		test("heights", () -> {
			var v = view('<div id=p style="height:200px"><div id=a style="height:50%"></div></div><div id=q><div id=b style="height:50%;min-height:5px"></div></div>'
				+ '<div id=r style="height:30px;max-height:10px;padding:2px"></div>');
			equals(rect(v, "a")[3], 100.0);
			equals(rect(v, "b")[3], 5.0);
			equals(rect(v, "r")[3], 14.0);
		});
		test("aspect-ratio: a height from the width, no less than the content unless it clips; a width from a height", () -> {
			var v = view('<div id=a style="width:100px;aspect-ratio:2"></div><div id=b style="width:20px;aspect-ratio:2">x x x</div>'
				+ '<div id=c style="width:20px;aspect-ratio:2;overflow:hidden">x x x</div><div id=d style="width:100px;aspect-ratio:2;padding:5px;box-sizing:border-box"></div>'
				+ '<div id=e style="height:30px;aspect-ratio:2;float:left"></div>');
			equals([rect(v, "a")[3], rect(v, "b")[3], rect(v, "c")[3], rect(v, "d")[3]], [50.0, 48, 10, 50]);
			equals(rect(v, "e")[2], 60.0);
		});
		test("containment: size's height and width its contain-intrinsic-size's, layout's a containing block, hidden content-visibility's contents not laid out", () -> {
			var v = view('<div id=a style="contain:size;contain-intrinsic-height:30px;width:100px"><div style="height:80px"></div></div>'
				+ '<div id=b style="contain:size;contain-intrinsic-width:40px;float:left"><div style="width:90px;height:5px"></div></div>'
				+ '<div id=c style="contain:layout;margin-top:20px"><div id=d style="position:fixed;top:0;left:0;width:5px;height:5px"></div></div>'
				+ '<div id=e style="content-visibility:hidden;contain-intrinsic-size:10px 12px;width:fit-content"><div id=f style="height:50px">x</div></div>');
			equals([rect(v, "a")[3], rect(v, "b")[2]], [30.0, 40]);
			// (c the fixed box's containing block, not the viewport)
			equals(rect(v, "d")[1], rect(v, "c")[1]);
			equals([rect(v, "e")[2], rect(v, "e")[3], rect(v, "f").length], [10.0, 12, 0]);
		});
		test("width: min-content, max-content and fit-content", () -> {
			var v = view('<div style="width:100px"><div id=a style="width:min-content">xx xx</div><div id=b style="width:max-content">xx xx</div><div id=c style="width:fit-content">xx xx xx xx xx xx xx</div></div>');
			equals([rect(v, "a")[2], rect(v, "b")[2], rect(v, "c")[2]], [32.0, 80, 100]);
		});
		test("margins: siblings, negative, parent and child", () -> {
			var v = view('<div style="height:10px;margin-bottom:20px"></div><div id=a style="height:10px;margin-top:30px;margin-bottom:-5px"></div>'
				+ '<div id=b style="height:10px;margin-top:20px"></div><div id=p style="margin-top:10px"><div id=c style="margin-top:25px;height:10px;margin-bottom:40px"></div></div><div id=n style="height:1px"></div>');
			equals(rect(v, "a")[1], 41.0);
			equals(rect(v, "b")[1], 66.0);
			equals(rect(v, "p")[1], 101.0);
			equals(rect(v, "c")[1], 101.0);
			equals(rect(v, "p")[3], 10.0);
			equals(rect(v, "n")[1], 151.0);
		});
		test("margins: through empty boxes, not across a formatting context's root", () -> {
			var v = view('<div style="height:10px;margin-bottom:10px"></div><div style="margin:20px 0"></div><div style="height:0;margin:5px 0"></div><div id=a style="margin-top:15px;height:1px"></div>'
				+ '<div id=p style="overflow:hidden"><div id=c style="margin-top:20px;height:5px"></div></div>'
				+ '<div id=q style="display:flow-root;margin-top:3px"><div id=d style="margin-top:7px;height:5px;margin-bottom:9px"></div></div>');
			equals(rect(v, "a")[1], 31.0);
			equals(rect(v, "p")[1], 32.0);
			equals(rect(v, "c")[1], 52.0);
			equals(rect(v, "p")[3], 25.0);
			equals(rect(v, "d")[1], 67.0);
			equals(rect(v, "q")[3], 21.0);
		});
		test("margins: a flex or grid item, a table cell or caption holds its children's", () -> {
			var v = view('<div id=f style="display:flex"><div id=fi><div style="margin:4px 0 9px;height:5px"></div></div></div>'
				+ '<div id=g style="display:grid"><div id=gi><div style="margin:4px 0 9px;height:5px"></div></div></div>'
				+ '<table style="border-spacing:0"><caption id=k><div style="margin:4px 0 9px;height:5px"></div></caption>'
				+ '<tr><td id=c style="padding:0"><div style="margin:4px 0 9px;height:5px"></div></td></tr></table>');
			equals([rect(v, "fi")[3], rect(v, "f")[3]], [18.0, 18]);
			equals([rect(v, "gi")[3], rect(v, "g")[3]], [18.0, 18]);
			equals([rect(v, "k")[3], rect(v, "c")[3]], [18.0, 18]);
		});
		test("margins: through overflow: clip, not a formatting context's root", () -> {
			var v = view('<div id=a style="overflow:clip"><div style="margin:4px 0 9px;height:5px"></div></div>'
				+ '<div id=b style="overflow-x:clip;overflow-y:visible"><div style="margin:4px 0 9px;height:5px"></div></div>');
			equals([rect(v, "a")[1], rect(v, "a")[3]], [5.0, 5]);
			equals([rect(v, "b")[1], rect(v, "b")[3]], [19.0, 5]);
		});
		test("relative offsets", () -> {
			var v = view('<div id=r style="position:relative;left:5px;top:6px;right:100px;height:10px"></div><div id=s style="position:relative;right:5px;bottom:10%"></div>');
			equals(rect(v, "r"), [5.0, 7, 800, 10]);
			equals(rect(v, "s"), [-5.0, 11, 800, 0]);
		});
		test("the cache: the same space, the same fragment", () -> {
			var v = view('<div><p>a</p></div>');
			var first = v.layout(800), count = v.fragments.count;
			equals(v.layout(800), first);
			equals(v.fragments.count, count);
			equals(v.fragments.width(v.layout(400)), 400.0);
		});
		test("floats: placement, lines beside them, clearance, a root's height", () -> {
			var v = view('<div id=box style="width:200px"><div id=l style="float:left;width:50px;height:30px"></div><div id=r style="float:right;width:40px;height:60px"></div>'
				+ '<div id=l2 style="float:left;width:50px;height:10px"></div><p id=p style="margin:0">x</p><div id=c style="clear:left;height:5px"></div></div>'
				+ '<div id=root style="overflow:hidden"><div style="float:left;width:10px;height:40px"></div></div>');
			equals(rect(v, "l"), [0.0, 1, 50, 30]);
			equals(rect(v, "r"), [160.0, 1, 40, 60]);
			equals(rect(v, "l2"), [50.0, 1, 50, 10]);
			equals(rect(v, "c")[1], 31.0);
			equals(rect(v, "root")[3], 40.0);
			// (the paragraph's line starts after the left floats)
			var line = lineOf(v, "p");
			equals(line[0], 100.0);
		});
		test("a formatting context's root beside floats, or below them", () -> {
			var v = view('<div style="width:200px"><div style="float:left;width:50px;height:30px"></div><div id=a style="overflow:hidden;height:10px"></div>'
				+ '<div id=b style="display:flow-root;height:10px;margin-left:160px"></div></div>');
			equals(rect(v, "a"), [50.0, 1, 150, 10]);
			equals(rect(v, "b")[1], 31.0);
		});
		test("absolute and fixed positioning", () -> {
			var v = view('<div id=cb style="position:relative;width:200px;height:100px;margin-left:10px;padding:5px">x<div id=a style="position:absolute;left:10px;top:20px;width:30px;height:40px"></div>'
				+ '<div id=b style="position:absolute;right:0;bottom:0;width:20px;height:10px"></div><div id=c style="position:absolute;left:0;right:0;width:100px;margin:0 auto;height:5px"></div>'
				+ '<div id=s style="position:absolute;height:5px;width:5px"></div><span id=i style="position:absolute;height:5px;width:5px"></span><div id=f style="position:fixed;left:3px;top:4px;width:5px;height:5px"></div></div>');
			equals(rect(v, "a"), [20.0, 21, 30, 40]);
			equals(rect(v, "b"), [200.0, 101, 20, 10]);
			equals(rect(v, "c")[0], 65.0);
			// (static positions: an inline-level box's where it is met in the line, after the text's 16px;
			// a block-level one's as a block's: the content edge, below the line the text is on)
			equals(rect(v, "i")[0], 31.0);
			equals(rect(v, "s").slice(0, 2), [15.0, 22]);
			equals(rect(v, "f"), [3.0, 4, 5, 5]);
		});
		test("floats placed never overlap, and stay in their containing block when they fit", () -> property(FLOATS, list -> {
			var ex = new Exclusions();
			var placed = [];
			for (f in list) {
				var at = ex.place(f.left, f.w, f.h, f.y, 0, 300);
				for (p in placed) {
					var apart = at.x + f.w <= p.x + 1e-9 || p.x + p.w <= at.x + 1e-9 || at.y + f.h <= p.y + 1e-9 || p.y + p.h <= at.y + 1e-9;
					assert(apart, 'overlap: ${at.x},${at.y} ${f.w}x${f.h} and ${p.x},${p.y} ${p.w}x${p.h}');
				}
				if (f.w <= 300) assert(at.x >= -1e-9 && at.x + f.w <= 300 + 1e-9, 'out: ${at.x} + ${f.w}');
				placed.push({x: at.x, y: at.y, w: f.w, h: f.h});
			}
		}, {cases: 300}));
		test("siblings' margins collapse as §8.3.1 says", () -> property(SIBLINGS, list -> {
			var html = [for (k in 0...list.length) {
				var s = list[k];
				'<div id=k$k style="height:${s.h}px;margin-top:${s.mt}px;margin-bottom:${s.mb}px"></div>';
			}].join("");
			var v = view('<div id=box style="border:1px solid">$html</div>');
			// (the model: a set of adjoining margins, its largest positive plus its most negative)
			var y = 1.0, set:Array<Float> = [];
			inline function collapse():Float {
				var pos = 0.0, neg = 0.0;
				for (m in set) if (m > 0) pos = Math.max(pos, m) else neg = Math.min(neg, m);
				return pos + neg;
			}
			for (k in 0...list.length) {
				var s = list[k];
				set.push(s.mt);
				if (s.h == 0) {
					set.push(s.mb);
					continue;
				}
				var top = y + collapse();
				equals(rect(v, 'k$k')[1], top + 1, 'k$k');
				y = top + s.h;
				set = [s.mb];
			}
			equals(rect(v, "box")[3], Math.max(0, y + collapse() - 1) + 2);
		}, {cases: 300}));
	});
}

private typedef Sibling = {h:Int, mt:Int, mb:Int};

private final FLOATS:Gen<Array<{left:Bool, w:Float, h:Float, y:Float}>> = array(c -> {
	left: c.draw(pick([true, false])),
	w: c.draw(int(1, 320)) * 1.0,
	h: c.draw(int(1, 80)) * 1.0,
	y: c.draw(int(0, 100)) * 1.0
}, 1, 8);

// (the first line box of an element's box: where its content starts)
private function lineOf(v:Laid, id:String):Array<Float> {
	var el:Element = v.document.getElementById(id);
	var f = v.fragments;
	var k = f.count;
	while (k-- > 0)
		if (f.kind(k) == Fragments.BOX && f.box(k).node == el && f.parent(k) >= 0) {
			var c = f.first(k);
			while (c >= 0 && f.kind(c) != Fragments.LINE) c = f.next(c);
			if (c < 0 || f.first(c) < 0) return [];
			// (where its content starts: its first fragment's place)
			var at = f.absolute(f.first(c));
			return [at.x, at.y];
		}
	return [];
}

private final SIBLINGS:Gen<Array<Sibling>> = array(c -> ({h: c.draw(pick([0, 0, 10, 25])), mt: c.draw(int(-15, 30)), mb: c.draw(int(-15, 30))} : Sibling), 1, 7);

// (a document on a body of no margin under a 1px border: nothing collapses with the root's; its text in
// Ahem, a font wherever it runs: wasm32-wasi has no system's)
private function view(body:String):Laid {
	var doc = Dom.parse('<!doctype html><style>body { margin: 0; border-top: 1px solid; font-family: Ahem }</style><body>$body');
	var v = new Laid(doc);
	v.layout(800);
	return v;
}

private class Laid {
	public final document:helder.dom.Document;
	public final fragments = new Fragments();
	final tree:BoxTree;
	final fonts = new FontMatch();

	public function new(doc:helder.dom.Document) {
		document = doc;
		fonts.register(sys.io.File.getBytes("tests/flow/fixtures/Ahem.ttf"), "Ahem");
		tree = BoxTree.build(doc, CssCascade.styles(doc, {media: {type: "screen", width: 800, height: 600}, hints: true}), {contexts: helder.ui.flow.Contexts.all()});
	}

	public function layout(width:Float):Int
		return tree.root.context.layout(tree.root, new Space(fragments, fonts, width, 600));
}

// an element's border box: x, y, width, height
private function rect(v:Laid, id:String):Array<Float> {
	var el:Element = v.document.getElementById(id);
	var f = v.fragments;
	var k = f.count;
	// (the last laid out)
	while (k-- > 0)
		if (f.kind(k) == Fragments.BOX && f.box(k).node == el && f.parent(k) >= 0) {
			var at = f.absolute(k);
			return [at.x, at.y, f.width(k), f.height(k)];
		}
	return [];
}
