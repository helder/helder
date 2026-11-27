import haxe.io.Bytes;
import helder.canvas.Canvas;
import helder.image.Image;
import helder.ui.box.PagedView;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// Real documents on pages (an invoice, a report), drawn by PagedView with
// the reftests' fonts (WptPage: DejaVu), each page against its golden of
// our own output (goldens/<name>-<n>.png): regression fixtures, not
// truth. BLESS=1 writes the goldens; each document's PDF is written to
// bin/paged too, a PDF's header checked.
class PagedCheck {
	static final dir = "tests/paged";

	static function main() {
		var bless = Sys.getEnv("BLESS") == "1";
		var names = [for (f in FileSystem.readDirectory(dir)) if (f.endsWith(".html")) f];
		names.sort(Reflect.compare);
		FileSystem.createDirectory("bin/paged");
		var failures = [];
		for (name in names) {
			var path = '$dir/$name', base = name.substr(0, name.length - 5);
			var o = WptPage.options(path);
			var v = new PagedView(WptPage.parse(path), {url: o.url, fonts: o.fonts, load: o.load, font: o.font, image: o.image});
			var n = v.layout();
			var why = [];
			for (i in 0...n) {
				var page = v.pages[i];
				var w = Math.round(page.width + 2 * page.bleed), h = Math.round(page.height + 2 * page.bleed);
				var c = new Canvas(w, h);
				c.clear(0xFFFFFFFF);
				v.paint(i, c);
				var golden = '$dir/goldens/$base-${i + 1}.png';
				if (bless) {
					File.saveBytes(golden, c.toPng());
					continue;
				}
				if (!FileSystem.exists(golden)) {
					why.push('page ${i + 1}: no golden');
					continue;
				}
				var g = Image.decode(File.getBytes(golden));
				if (g.width != w || g.height != h) {
					why.push('page ${i + 1}: ${w}x$h, the golden ${g.width}x${g.height}');
					continue;
				}
				var px = Bytes.alloc(w * h * 4);
				c.readPixels(px, 0, 0, w, h);
				var differ = 0;
				for (k in 0...w * h) if (px.getInt32(k * 4) != g.pixels.getInt32(k * 4)) differ++;
				if (differ > 0) why.push('page ${i + 1}: $differ pixels differ');
			}
			// (goldens of pages no longer there)
			var k = n + 1;
			while (FileSystem.exists('$dir/goldens/$base-$k.png')) {
				if (bless) FileSystem.deleteFile('$dir/goldens/$base-$k.png') else why.push('$k pages in the goldens, $n now');
				k++;
			}
			var pdf = v.pdf();
			File.saveBytes('bin/paged/$base.pdf', pdf);
			if (pdf.length < 5 || pdf.getString(0, 5) != "%PDF-") why.push("no PDF");
			Sys.println('$name: $n pages, ${Math.round(pdf.length / 1024)} KB of PDF${why.length == 0 ? "" : ": " + why.join("; ")}');
			if (why.length > 0) failures.push(name);
		}
		if (bless) Sys.println('BLESS: $dir/goldens');
		if (failures.length > 0) {
			Sys.println('PagedCheck: ${failures.join(", ")} differ (BLESS=1 to take them)');
			Sys.exit(1);
		}
	}
}
