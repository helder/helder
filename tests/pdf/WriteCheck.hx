import haxe.Json;
import helder.canvas.Glyphs;
import helder.canvas.Paint;
import helder.canvas.doc.Document;
import helder.canvas.doc.PdfWriter;
import helder.pdf.Pdf;
import helder.text.FontFile;
import helder.text.FontSet;
import helder.text.TextLayout;
import sys.FileSystem;
import sys.io.File;

// The pdf lane's written files: pages of text drawn into a helder.canvas
// Document and written by PdfWriter (bin/pdf/written), each read back by
// helder.pdf (its text, line by line, the drawn one), with what pdf.js
// should read of them (expected.json: tests/pdf/written.mjs); a links,
// anchors and outline page; and the size of a text-heavy document written
// with fonts against the same as outlines (size.md)
class WriteCheck {
	static final out = "bin/pdf/written";
	static final expected:Dynamic = {};
	static var failed = 0;

	static function face(path:String):FontFile
		return FontFile.parse(File.getBytes(path));

	static function main() {
		FileSystem.createDirectory(out);
		var dejavu = face("tests/canvas/fonts/DejaVuSans-pdf.ttf"), otf = face("tests/canvas/fonts/DejaVuSans-pdf.otf");
		var cid = face("tests/canvas/fonts/DejaVuSans-pdf-cid.otf"), ipa = face("tests/canvas/fonts/IPAGothic-canvas.ttf");
		var inter = face("src/helder/text/fonts/Inter.ttf");
		page("latin", dejavu, ["The office's waffles fit", "a fjord affluent flat"]);
		page("marks", dejavu, ["Crème brûlée, ño", "šé ą ż"]);
		page("hebrew", dejavu, ["שלום עולם"]);
		page("arabic", dejavu, ["مرحبا بالعالم"]);
		page("japanese", ipa, ["日本語の漢字。"]);
		page("cff", otf, ["Office fit, café"]);
		page("cff-cid", cid, ["Office fit, café"]);
		page("variable", inter.instance(["wght" => 700]), ["Bold office text"]);
		document();
		sizes(dejavu);
		File.saveContent('$out/expected.json', Json.stringify(expected, null, "  "));
		if (failed > 0) {
			Sys.println('WriteCheck: $failed failed');
			Sys.exit(1);
		}
		Sys.println('WriteCheck: ${Reflect.fields(expected).length} files written and read back (bin/pdf/written)');
	}

	// lines of text, each its own layout, on a page; read back by helder.pdf as the same lines
	static function page(name:String, f:FontFile, lines:Array<String>) {
		var doc = new Document();
		doc.title = name;
		var p = doc.newPage(420, 40 + 40 * lines.length);
		for (i => l in lines)
			Glyphs.fill(p, new TextLayout(l, new FontSet(f, 24), 1.2, Math.POSITIVE_INFINITY), 20, 50 + 40 * i, Paint.solid(0xFF000000));
		var bytes = PdfWriter.write(doc);
		File.saveBytes('$out/$name.pdf', bytes);
		var text = Pdf.text(Pdf.open(bytes).pages[0]), want = lines.join("\n");
		if (text != want) {
			failed++;
			Sys.println('WriteCheck: $name.pdf read back as "$text", drawn "$want"');
		}
		Reflect.setField(expected, name, {text: want});
	}

	// links, anchors, bookmarks and the information
	static function document() {
		var doc = new Document(), f = face("tests/canvas/fonts/DejaVuSans-pdf.ttf");
		for (i in 0...2) {
			var p = doc.newPage(300, 200);
			Glyphs.fill(p, new TextLayout('Page ${i + 1}', new FontSet(f, 20), 1.2, Math.POSITIVE_INFINITY), 20, 40, Paint.solid(0xFF000000));
		}
		doc.link(0, 20, 60, 120, 20, "https://helder.build/");
		doc.linkTo(0, 20, 100, 120, 20, "second");
		doc.anchor("second", 1, 0, 20);
		doc.bookmark("First", 1, 0, 0);
		doc.bookmark("Inside", 2, 0, 50);
		doc.bookmark("Second", 1, 1, 0);
		doc.title = "Written by helder";
		doc.author = "helder.canvas";
		doc.subject = "PdfWriter's document features";
		doc.keywords = "pdf, links";
		doc.lang = "en";
		doc.created = Date.fromTime(1764158400000.0);
		File.saveBytes('$out/document.pdf', PdfWriter.write(doc));
		Reflect.setField(expected, "document", {
			text: "Page 1",
			links: ([{url: "https://helder.build/"}, {dest: "second"}] : Array<Dynamic>),
			destinations: ["second"],
			outline: ([{title: "First", items: ["Inside"]}, {title: "Second", items: []}] : Array<Dynamic>),
			title: "Written by helder",
			author: "helder.canvas",
			language: "en"
		});
	}

	// a text-heavy document (20 pages of paragraphs) as text and as outlines
	static function sizes(f:FontFile) {
		var words = "the of and to in is was for on that with as by at from his her an were are which this be or has had not but also its after first new two other their".split(" ");
		var seed = 7;
		function word() {
			seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
			return words[seed % words.length];
		}
		var text = new Document(), outlines = new Document();
		for (_ in 0...20) {
			var a = text.newPage(595, 842), b = outlines.newPage(595, 842);
			var para = [for (_ in 0...420) word()].join(" ");
			var l = new TextLayout(para, new FontSet(f, 11), 1.4, 515);
			Glyphs.fill(a, l, 40, 60, Paint.solid(0xFF000000));
			var g = new Glyphs();
			g.add(l, 40, 60);
			b.fill(g.path, Paint.solid(0xFF000000));
		}
		var t = PdfWriter.write(text).length, o = PdfWriter.write(outlines).length;
		var report = '20 pages of 11 px text (DejaVu Sans, 8,400 words): with fonts ${Math.round(t / 1024)} KB, as outlines ${Math.round(o / 1024)} KB (${Math.round(o / t * 10) / 10} times)';
		File.saveContent('$out/size.md', report + "\n");
		Sys.println("WriteCheck: " + report);
		if (t >= o) {
			failed++;
			Sys.println("WriteCheck: the text not smaller than its outlines");
		}
	}
}
