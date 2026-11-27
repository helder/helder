import haxe.io.Bytes;
import helder.image.Image;
import helder.image.PngEncoder;
import helder.pdf.Pdf;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// Real-world documents as PDFs (tests/pdf-docs: an invoice, a report with
// its contents and running heads, a long table, a book chapter with
// endnotes, floats and images, a CV in flex and grid). The lane writes
// helder pdf's (bin/pdf-docs/<name>.pdf); each page rasterised by
// helder.pdf is checked against its golden of our own output
// (goldens/<name>-<n>.png: regression fixtures, not truth; BLESS=1 takes
// them). Where WeasyPrint's PDF of a document is there too
// (bin/pdf-docs/<name>.weasyprint.pdf, the CI job writes it: WeasyPrint is
// the parity target), the two are rasterised the same way and compared
// page by page, a pixel differing when a channel is off by more than
// TOLERANCE: each page's similarity, a diff image (diff/<name>-<n>.png:
// helder's page in grey, what differs red) and a summary
// (similarity.md). The comparison never fails the run.
class DocsCheck {
	static final dir = "tests/pdf-docs";
	static final out = "bin/pdf-docs";
	// (96 dpi: a pixel a CSS pixel)
	static final SCALE = 96 / 72;
	static inline var TOLERANCE = 48;

	static function main() {
		var bless = Sys.getEnv("BLESS") == "1";
		var names = [for (f in FileSystem.readDirectory(dir)) if (f.endsWith(".html")) f.substr(0, f.length - 5)];
		names.sort(Reflect.compare);
		FileSystem.createDirectory('$out/diff');
		FileSystem.createDirectory('$dir/goldens');
		var failures = [], summary = ["| Document | Pages (helder, WeasyPrint) | Similarity | Per page |", "| --- | --- | --- | --- |"];
		for (name in names) {
			var ours = rasters('$out/$name.pdf');
			if (ours == null) {
				Sys.println('$name: no PDF ($out/$name.pdf)');
				failures.push(name);
				continue;
			}
			var why = [];
			for (i in 0...ours.length) {
				var golden = '$dir/goldens/$name-${i + 1}.png';
				var page = ours[i];
				if (bless) {
					File.saveBytes(golden, PngEncoder.encode(page.pixels, page.width, page.height));
					continue;
				}
				if (!FileSystem.exists(golden)) {
					why.push('page ${i + 1}: no golden');
					continue;
				}
				var g = Image.decode(File.getBytes(golden));
				if (g.width != page.width || g.height != page.height) why.push('page ${i + 1}: ${page.width}x${page.height}, the golden ${g.width}x${g.height}') else {
					var differ = 0;
					for (k in 0...page.width * page.height) if (page.pixels.getInt32(k * 4) != g.pixels.getInt32(k * 4)) differ++;
					if (differ > 0) why.push('page ${i + 1}: $differ pixels differ');
				}
			}
			var k = ours.length + 1;
			while (FileSystem.exists('$dir/goldens/$name-$k.png')) {
				if (bless) FileSystem.deleteFile('$dir/goldens/$name-$k.png') else why.push('${k} pages in the goldens, ${ours.length} now');
				k++;
			}
			var theirs = rasters('$out/$name.weasyprint.pdf');
			var line = '$name: ${ours.length} pages';
			if (theirs != null) {
				var pages = [], total = 0.0, n = Std.int(Math.max(ours.length, theirs.length));
				for (i in 0...n) {
					var s = i < ours.length && i < theirs.length ? compare(ours[i], theirs[i], '$out/diff/$name-${i + 1}.png') : 0.0;
					pages.push(s);
					total += s;
				}
				var mean = n == 0 ? 1 : total / n;
				line += ', WeasyPrint ${theirs.length}: ${percent(mean)} similar (${[for (s in pages) percent(s)].join(", ")})';
				summary.push('| $name | ${ours.length}, ${theirs.length} | ${percent(mean)} | ${[for (s in pages) percent(s)].join(", ")} |');
			}
			Sys.println(line + (why.length == 0 ? "" : ": " + why.join("; ")));
			if (why.length > 0) failures.push(name);
		}
		if (summary.length > 2) {
			File.saveContent('$out/similarity.md', "# helder pdf against WeasyPrint\n\n" + summary.join("\n") + '\n\nA pixel differs when a channel is off by more than $TOLERANCE (of 255), at 96 dpi; a page one has and the other not: 0%.\n');
			Sys.println('similarity: $out/similarity.md, diffs: $out/diff');
		}
		if (bless) Sys.println('BLESS: $dir/goldens');
		if (failures.length > 0) {
			Sys.println('DocsCheck: ${failures.join(", ")} differ (BLESS=1 to take them)');
			Sys.exit(1);
		}
	}

	// (a PDF's pages rasterised by helder.pdf, straight RGBA; null: none there)
	static function rasters(path:String):Null<Array<{width:Int, height:Int, pixels:Bytes}>> {
		if (!FileSystem.exists(path)) return null;
		var doc = Pdf.open(File.getBytes(path));
		return [
			for (i in 0...doc.pages.length) {
				var b = Pdf.render(doc, i, SCALE);
				{width: b.width, height: b.height, pixels: b.straight()};
			}
		];
	}

	// (the share of pixels alike within TOLERANCE, over the larger page; the diff image written)
	static function compare(a:{width:Int, height:Int, pixels:Bytes}, b:{width:Int, height:Int, pixels:Bytes}, diff:String):Float {
		var w = Std.int(Math.max(a.width, b.width)), h = Std.int(Math.max(a.height, b.height));
		var img = Bytes.alloc(w * h * 4), alike = 0;
		inline function px(p:{width:Int, height:Int, pixels:Bytes}, x:Int, y:Int, c:Int):Int
			return x < p.width && y < p.height ? p.pixels.get((y * p.width + x) * 4 + c) : 255;
		for (y in 0...h) for (x in 0...w) {
			var same = true;
			for (c in 0...3) if (Math.abs(px(a, x, y, c) - px(b, x, y, c)) > TOLERANCE) same = false;
			var o = (y * w + x) * 4;
			if (same) {
				alike++;
				var grey = Std.int((px(a, x, y, 0) + px(a, x, y, 1) + px(a, x, y, 2)) / 3 * 0.4 + 153);
				img.set(o, grey);
				img.set(o + 1, grey);
				img.set(o + 2, grey);
			} else {
				img.set(o, 230);
				img.set(o + 1, 30);
				img.set(o + 2, 30);
			}
			img.set(o + 3, 255);
		}
		File.saveBytes(diff, PngEncoder.encode(img, w, h));
		return alike / (w * h);
	}

	static function percent(v:Float):String
		return '${Math.round(v * 1000) / 10}%';
}
