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
// percentages, heights, margin collapsing (siblings, negative, parent and
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
		tree = BoxTree.build(doc, CssCascade.styles(doc, {media: {type: "screen", width: 800, height: 600}, hints: true}));
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
