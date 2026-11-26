import haxe.DynamicAccess;
import helder.canvas.Canvas;
import helder.canvas.doc.Recorder;
import helder.css.CssCascade;
import helder.dom.Dom;
import helder.ui.box.BoxTree;
import helder.ui.box.BoxPainter;
import helder.ui.box.DocumentView;
import helder.ui.box.FontMatch;
import helder.ui.box.Fragments;
import helder.ui.box.PaintOrder;
import helder.ui.flow.Contexts;
import helder.ui.flow.Space;
import sys.io.File;

// helder.ui.box on a page, by phase, the least of runs (bench layout): the
// page parsed, cascaded (every element's style), its box tree, flow layout
// at 1024 pixels wide (lines through the inline stand-in), paint of its
// first 1024 by 768 on the CPU, and of the whole page recorded
// (helder.canvas.doc's Recorder: the calls, no pixels; its first million
// pixels). Then the boxes, fragments and
// what they take: the GC's bytes allocated building the tree and laying it
// out, per box and per fragment, and the fragment columns' own.
//
//   bin/bench/LayoutBench <page.html> <sheets.json: URL to file> <runs>
class LayoutBench {
	static function main() {
		var args = Sys.args();
		var html = File.getContent(args[0]);
		var files:DynamicAccess<String> = haxe.Json.parse(File.getContent(args[1]));
		var runs = Std.parseInt(args[2]) ?? 3;
		var best = {parse: 1e9, cascade: 1e9, boxes: 1e9, layout: 1e9, order: 1e9, record: 1e9, viewport: 1e9};
		var boxes = 0, fragments = 0, height = 0.0, treeBytes = 0.0, layoutBytes = 0.0;
		var fonts = new FontMatch();
		for (_ in 0...runs) {
			var t0 = haxe.Timer.stamp();
			var doc = Dom.parse(html);
			var t1 = haxe.Timer.stamp();
			var styles = CssCascade.styles(doc, {
				load: url -> files.exists(url) ? File.getContent(files[url]) : null,
				url: "https://html.spec.whatwg.org/",
				media: {type: "screen", width: 1024, height: 768},
				hints: true
			});
			var n = doc.documentElement;
			function walk(e:helder.dom.Element) {
				styles.computed(e);
				var c = e.firstElementChild;
				while (c != null) {
					walk(c);
					c = c.nextElementSibling;
				}
			}
			walk(n);
			var t2 = haxe.Timer.stamp();
			var b0 = GcStats.bytes();
			var tree = BoxTree.build(doc, styles);
			var t3 = haxe.Timer.stamp();
			var b1 = GcStats.bytes();
			var frags = new Fragments();
			var space = new Space(frags, fonts, 1024, 768);
			var root = Contexts.all().flow.layout(tree.root, space);
			var t4 = haxe.Timer.stamp();
			var b2 = GcStats.bytes();
			var order = new PaintOrder(frags, root);
			var t5 = haxe.Timer.stamp();
			var image = (url:String) -> null;
			var c = new Canvas(1024, 768);
			c.clear(0xFFFFFFFF);
			new BoxPainter(frags, order, image).paint(c);
			var t6 = haxe.Timer.stamp();
			// (recorded last: a million calls kept make the collector slow for what follows)
			var rec = new Recorder(1024, Std.int(Math.min(frags.height(root), 1e6)));
			new BoxPainter(frags, order, image).paint(rec);
			var t7 = haxe.Timer.stamp();
			rec = null;
			boxes = tree.count;
			fragments = frags.count;
			height = frags.height(root);
			treeBytes = b1 - b0;
			layoutBytes = b2 - b1;
			best.parse = Math.min(best.parse, t1 - t0);
			best.cascade = Math.min(best.cascade, t2 - t1);
			best.boxes = Math.min(best.boxes, t3 - t2);
			best.layout = Math.min(best.layout, t4 - t3);
			best.order = Math.min(best.order, t5 - t4);
			best.viewport = Math.min(best.viewport, t6 - t5);
			best.record = Math.min(best.record, t7 - t6);
		}
		inline function ms(s:Float)
			return Math.round(s * 1e4) / 10;
		Sys.println(haxe.Json.stringify({
			boxes: boxes,
			fragments: fragments,
			pageHeight: Math.round(height),
			parse: ms(best.parse),
			cascade: ms(best.cascade),
			boxTree: ms(best.boxes),
			layout: ms(best.layout),
			paintOrder: ms(best.order),
			paintRecorded: ms(best.record),
			paintViewport: ms(best.viewport),
			allocatedPerBox: Math.round(treeBytes / boxes),
			allocatedPerFragment: Math.round(layoutBytes / fragments),
			fragmentColumns: Fragments.BYTES
		}));
	}
}
