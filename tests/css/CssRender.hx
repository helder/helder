import helder.canvas.Canvas;
import helder.css.CssSheet;
import helder.ui.box.DocumentView;
import helder.ui.box.PagedView;
import helder.ui.box.Fragments;
import sys.io.File;

using StringTools;

// A page drawn by helder.ui.box, natively, as a reftest's run draws it
// (800 by 600 unless said); --tree prints its boxes and fragments.
//
//   bun run test css-render <page.html|.xht> <out.png> [width height] [--tree] [--ref <reference>]
// (--ref: the reference drawn too, out-ref.png, and out-diff.png: the pixels that differ in red, their box printed)
//   bun run test css-render <page> <out.png> --pages [--tree]
// (--pages: on pages, as print reftests are, WPT's 5in by 3in default: out-1.png, out-2.png...)
class CssRender {
	static function main() {
		var args = Sys.args();
		var tree = args.remove("--tree");
		if (args.remove("--pages")) return pages(args[0], args[1], tree);
		var at = args.indexOf("--ref");
		var ref = at >= 0 ? args.splice(at, 2)[1] : null;
		if (args.length < 2) {
			Sys.println("CssRender <page.html|.xht> <out.png> [width height] [--tree]");
			Sys.exit(2);
		}
		var w = args.length > 2 ? Std.parseInt(args[2]) : 800, h = args.length > 3 ? Std.parseInt(args[3]) : 600;
		var doc = WptPage.parse(args[0]);
		var c = new Canvas(w, h);
		var t0 = haxe.Timer.stamp();
		var view = DocumentView.render(doc, w, c, WptPage.options(args[0]));
		var ms = Math.round((haxe.Timer.stamp() - t0) * 10000) / 10;
		File.saveBytes(args[1], c.toPng());
		Sys.println('${args[1]}: ${view.tree.count} boxes, ${view.fragments.count} fragments, $ms ms');
		for (p in view.tree.pending) Sys.println('pending: $p');
		if (ref != null) {
			var r = new Canvas(w, h);
			DocumentView.render(WptPage.parse(ref), w, r, WptPage.options(ref));
			var base = args[1].substr(0, args[1].length - 4);
			File.saveBytes(base + "-ref.png", r.toPng());
			var a = haxe.io.Bytes.alloc(w * h * 4), b = haxe.io.Bytes.alloc(w * h * 4);
			c.readPixels(a, 0, 0, w, h);
			r.readPixels(b, 0, 0, w, h);
			var d = new Canvas(w, h);
			var out = haxe.io.Bytes.alloc(w * h * 4);
			var n = 0, x0 = w, y0 = h, x1 = -1, y1 = -1;
			for (i in 0...w * h) {
				var same = a.getInt32(i * 4) == b.getInt32(i * 4);
				out.setInt32(i * 4, same ? (a.getInt32(i * 4) & 0x00FFFFFF) | 0x40000000 : 0xFF0000FF);
				if (!same) {
					n++;
					var x = i % w, y = Std.int(i / w);
					if (x < x0) x0 = x;
					if (y < y0) y0 = y;
					if (x > x1) x1 = x;
					if (y > y1) y1 = y;
				}
			}
			d.writePixels(out, 0, 0, w, h);
			File.saveBytes(base + "-diff.png", d.toPng());
			Sys.println(n == 0 ? "the same as the reference" : '$n pixels differ, in $x0,$y0 to $x1,$y1');
		}
		if (tree) {
			Sys.print(view.tree.dump());
			if (view.root >= 0) dump(view.fragments, view.root, 0);
		}
	}

	static function pages(page:String, out:String, tree:Bool) {
		var o = WptPage.options(page);
		var user = CssSheet.parse("@page { size: 5in 3in; margin: 0.5in }", User);
		var v = new PagedView(WptPage.parse(page), {url: o.url, fonts: o.fonts, load: o.load, font: o.font, image: o.image, user: [user]});
		var n = v.layout();
		var base = out.substr(0, out.length - 4);
		for (i in 0...n) {
			var p = v.pages[i];
			var c = new Canvas(Math.round(p.width + 2 * p.bleed), Math.round(p.height + 2 * p.bleed));
			c.clear(0xFFFFFFFF);
			v.paint(i, c);
			File.saveBytes('$base-${i + 1}.png', c.toPng());
			Sys.println('$base-${i + 1}.png: ${p.width}x${p.height}, area ${p.area}${p.left ? ", left" : ""}${p.blank ? ", blank" : ""}');
			if (tree && p.root >= 0) dump(v.fragments, p.root, 1);
		}
	}

	static function dump(f:Fragments, id:Int, depth:Int) {
		var kind = ["box", "line", "span", "text"][f.kind(id)];
		Sys.println("".lpad(" ", depth * 2) + '$kind ${f.box(id)} at ${f.x(id)},${f.y(id)} ${f.width(id)}x${f.height(id)}');
		var c = f.first(id);
		while (c >= 0) {
			dump(f, c, depth + 1);
			c = f.next(c);
		}
	}
}
