package helder.canvas.doc;

import haxe.io.Bytes;
import helder.canvas.Gradient;
import helder.pdf.Pdf;
import helder.pdf.PdfValue;
import helder.test.Gen;
import helder.test.Test;
import helder.text.FontFile;
import helder.text.FontSet;
import helder.text.TextLayout;

using StringTools;

// PdfWriter's text read back by helder.pdf: a line drawn into a page comes
// back from Pdf.runs as its characters, each glyph's box where it was drawn
// (selection over it lines up); its pixels those of the same line as
// outlines. As a property over Latin, ligatures, combining marks, Hebrew,
// Arabic, both in one line, Japanese and emoji (no emoji face here: the
// .notdef glyph, an ActualText span). Then CFF faces (name-keyed and
// CID-keyed, their subroutines subset), a variable face's instance, strokes
// and gradients, a font for each face across pages, and the document's
// links, anchors, bookmarks, labels and information.
function tests() {
	var dejavu = face("tests/canvas/fonts/DejaVuSans-pdf.ttf"), ipa = face("tests/canvas/fonts/IPAGothic-canvas.ttf");
	var inter = face("src/helder/text/fonts/Inter.ttf");
	function has(cps:Array<Int>)
		return [for (c in cps) if (dejavu.glyph(c) > 0) String.fromCharCode(c)];
	var letters = [for (c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,;:!?'()-".split("")) c];
	var marks = has([for (c in 0x300...0x370) c]);
	var hebrew = has([for (c in 0x5D0...0x5EB) c]), points = has([for (c in 0x5B0...0x5BD) c]);
	var arabic = has([for (c in 0x627...0x64B) if (c < 0x63B || c > 0x640) c]), harakat = has([for (c in 0x64B...0x653) c]);
	var japanese = [for (c in [0x3001, 0x3002, 0x304B, 0x306A, 0x306E, 0x30AD, 0x30B9, 0x30C6, 0x30C8, 0x5B57, 0x65E5, 0x672C, 0x6F22, 0x8A9E]) String.fromCharCode(c)];
	function words(word:Gen<String>):Gen<String>
		return array(word, 1, 6).map(ws -> ws.join(" "));
	function letterWord(set:Array<String>, ?marked:Array<String>):Gen<String>
		return c -> {
			var n = c.draw(int(1, 7)), b = new StringBuf();
			for (_ in 0...n) {
				b.add(c.draw(pick(set)));
				if (marked != null && marked.length > 0 && c.draw(int(0, 3)) == 0) b.add(c.draw(pick(marked)));
			}
			b.toString();
		};
	var latin = words(letterWord(letters));
	var ligatures = words(pick(["fi", "fl", "ffi", "ffl", "ff", "office", "waffle", "flu", "fit", "affix", "Æsir"]));
	var combining = words(letterWord("aeiouncsAEIOUNCS".split(""), marks));
	var hebrewText = words(letterWord(hebrew, points));
	var arabicText = words(letterWord(arabic, harakat));
	var mixed:Gen<String> = c -> [c.draw(letterWord(letters)), c.draw(letterWord(hebrew)), c.draw(pick(["2026", "12", "3.5"])), c.draw(letterWord(arabic)), c.draw(letterWord(letters))].join(" ");
	var cjk = array(pick(japanese), 1, 12).map(a -> a.join(""));
	var emoji = words(c -> c.draw(pick(["\u{1F600}", "\u{1F44D}\u{1F3FD}", "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}", "\u{1F1E7}\u{1F1EA}", "\u{2764}\u{FE0F}", "ok"])));
	var texts = oneOf([latin, ligatures, combining, hebrewText, arabicText, mixed, cjk, emoji]);

	describe("PdfWriter's text", () -> {
		test("a line comes back from Pdf.runs as its characters, each glyph's box where it was drawn", () -> property(c -> {
			text: c.draw(texts),
			size: c.draw(pick([9.0, 12.0, 17.5, 32.0]))
		}, v -> {
			var fs = new FontSet(dejavu, [ipa], v.size);
			var l = new TextLayout(v.text, fs, 1.2, Math.POSITIVE_INFINITY);
			var doc = new Document();
			Glyphs.fill(doc.newPage(Std.int(l.lines[0].advance + 40), 100), l, 10, 50, Paint.solid(0xFF000000));
			var runs = Pdf.runs(Pdf.open(PdfWriter.write(doc)).pages[0]);
			equals(runs.length, 1);
			if (runs.length != 1) return;
			equals(runs[0].text, v.text);
			boxesAt(runs[0], l, 10, 50, v.size);
		}, {cases: 150}));

		test("its pixels are the outlines' (TrueType, CFF, CID-keyed CFF, a variable instance)", () -> {
			var otf = face("tests/canvas/fonts/DejaVuSans-pdf.otf"), cid = face("tests/canvas/fonts/DejaVuSans-pdf-cid.otf");
			var bold = inter.instance(["wght" => 700]);
			for (f in [dejavu, otf, cid, inter, bold]) {
				var text = f == dejavu ? "Office fix: שלום, café" : "Office waffles, fjord café (fit)";
				var asText = page(f, text, false), asPaths = page(f, text, true);
				var off = differ(Pdf.render(Pdf.open(asText), 0, 2), Pdf.render(Pdf.open(asPaths), 0, 2));
				assert(off < 0.002, '${f.postScriptName}: ${Math.round(off * 10000) / 100}% of the pixels off');
				equals(Pdf.text(Pdf.open(asText).pages[0]), text);
				// (its program embedded: a font file, not the outlines)
				var s = asText.toString();
				assert(s.indexOf(f.trueType ? "/FontFile2" : "/FontFile3") >= 0, '${f.postScriptName}: no embedded program');
			}
		});

		test("a CFF subset keeps the glyphs shown and the subroutines they call, the others empty", () -> {
			var otf = face("tests/canvas/fonts/DejaVuSans-pdf.otf");
			var whole = otf.cffSubset([for (g in 0...otf.numGlyphs) g]), some = otf.cffSubset([otf.glyph("O".code), otf.glyph("k".code)]);
			assert(some.length < whole.length / 2, 'the subset ${some.length} bytes, the whole ${whole.length}');
			var cff = new helder.text.Cff(some, 0, otf.unitsPerEm), all = new helder.text.Cff(whole, 0, otf.unitsPerEm);
			equals(cff.glyphCount, otf.numGlyphs);
			for (g in [otf.glyph("O".code), otf.glyph("k".code)])
				equals(path(cff, g), path(all, g));
			equals(path(cff, otf.glyph("x".code)), "");
		});

		test("stroked and gradient text as text, its pixels the outlines'", () -> {
			var grad = new LinearGradient(0, 0, 300, 0).addStop(0, 0xFFE11D48).addStop(1, 0x802563EB);
			for (kind in ["stroke", "gradient"]) {
				function draw(paths:Bool):Bytes {
					var doc = new Document(), p = doc.newPage(320, 80);
					var l = new TextLayout("Strokes fit", new FontSet(dejavu, 36), 1.2, Math.POSITIVE_INFINITY);
					var paint = kind == "gradient" ? Paint.shaded(grad) : Paint.solid(0xFF1D4ED8), st = kind == "stroke" ? new Stroke(1.5) : null;
					if (paths) {
						var g = new Glyphs();
						g.add(l, 10, 50);
						if (st == null) p.fill(g.path, paint) else p.stroke(g.path, st, paint);
					} else if (st == null) Glyphs.fill(p, l, 10, 50, paint) else Glyphs.stroke(p, l, 10, 50, st, paint);
					return PdfWriter.write(doc);
				}
				var t = draw(false);
				equals(Pdf.text(Pdf.open(t).pages[0]), "Strokes fit");
				var off = differ(Pdf.render(Pdf.open(t), 0, 2), Pdf.render(Pdf.open(draw(true)), 0, 2));
				assert(off < 0.003, '$kind: ${Math.round(off * 10000) / 100}% of the pixels off');
			}
		});

		test("a paint text cannot have: drawn apart, its text still there once", () -> {
			var doc = new Document(), p = doc.newPage(300, 80);
			var l = new TextLayout("Conic", new FontSet(dejavu, 30), 1.2, Math.POSITIVE_INFINITY);
			Glyphs.fill(p, l, 10, 50, Paint.shaded(new ConicGradient(0, 150, 40).addStop(0, 0xFF000000).addStop(1, 0xFFFF0000)));
			var pdf = Pdf.open(PdfWriter.write(doc));
			equals(Pdf.text(pdf.pages[0]), "Conic");
			var px = Pdf.render(pdf, 0, 1);
			assert(differ(px, new Bitmap(px.width, px.height)) > 0.01, "nothing drawn");
		});

		test("colour glyphs drawn in their colours, their text invisible", () -> {
			var f = FontFile.parse(colourFont());
			var doc = new Document(), p = doc.newPage(200, 80);
			Glyphs.fill(p, new TextLayout("★★", new FontSet(f, 40), 1.2, Math.POSITIVE_INFINITY), 10, 60, Paint.solid(0xFF0000FF));
			var bytes = PdfWriter.write(doc), pdf = Pdf.open(bytes);
			equals(Pdf.text(pdf.pages[0]), "★★");
			var px = Pdf.render(pdf, 0, 1).straight();
			// (the first layer the palette's red, the second the text's blue)
			function at(x:Int, y:Int):Int
				return (px.get((y * 200 + x) * 4) << 16) | (px.get((y * 200 + x) * 4 + 1) << 8) | px.get((y * 200 + x) * 4 + 2);
			equals(at(15, 45), 0xFF0000);
			equals(at(35, 45), 0x0000FF);
		});

		test("one font for a face across pages, its variations apart", () -> {
			var doc = new Document();
			for (i in 0...3) {
				var p = doc.newPage(200, 60);
				Glyphs.fill(p, new TextLayout('Page $i', new FontSet(dejavu, 20), 1.2, Math.POSITIVE_INFINITY), 10, 40, Paint.solid(0xFF000000));
				Glyphs.fill(p, new TextLayout('bold $i', new FontSet(inter.instance(["wght" => 700]), 20), 1.2, Math.POSITIVE_INFINITY), 100, 40,
					Paint.solid(0xFF000000));
			}
			var pdf = PdfWriter.write(doc), s = pdf.toString();
			equals(s.split("/Subtype /Type0").length - 1, 2);
			var read = Pdf.open(pdf);
			for (i in 0...3)
				equals(Pdf.text(read.pages[i]), 'Page $i bold $i');
		});

		test("a shadow's copy is not text: each character once", () -> {
			var c = new helder.canvas.dom.Canvas(200, 60), ctx = c.getContext("2d");
			helder.canvas.dom.FontLibrary.use("DejaVu Test", ["tests/canvas/fonts/DejaVuSans-pdf.ttf"]);
			ctx.font = "20px 'DejaVu Test'";
			ctx.shadowColor = "rgba(0,0,0,0.5)";
			ctx.shadowBlur = 4;
			ctx.fillText("Shadowed", 10, 40);
			equals(Pdf.text(Pdf.open(c.toBuffer("pdf")).pages[0]), "Shadowed");
		});
	});

	describe("Document's links, anchors, bookmarks, labels and information", () -> {
		test("read back from the file", () -> {
			var doc = new Document();
			for (_ in 0...3)
				doc.newPage(200, 300);
			doc.link(0, 10, 20, 100, 12, "https://helder.build/docs/?a=(1)");
			doc.linkTo(0, 10, 40, 100, 12, "chapter-2");
			doc.anchor("chapter-2", 1, 0, 50);
			doc.anchor("café", 2, 5, 60);
			doc.bookmark("One", 1, 0, 0);
			doc.bookmark("One a", 2, 0, 100);
			doc.bookmark("One b", 2, 1, 0);
			doc.bookmark("Two ש", 1, 2, 10);
			doc.label(0, "lower-roman");
			doc.label(2, "decimal", "A-", 5);
			doc.title = "A title (with parentheses)";
			doc.author = "Someone É";
			doc.subject = "Tests";
			doc.keywords = "pdf, text";
			doc.creator = "PdfWriter.test";
			doc.lang = "en";
			doc.created = Date.fromTime(1764158400000.0);
			doc.modified = Date.fromTime(1764162000000.0);
			var pdf = Pdf.open(PdfWriter.write(doc));
			function d(v:PdfValue):PdfDict
				return require(Values.dict(pdf.resolve(v)));
			function s(v:PdfValue):String
				return pdfString(require(Values.str(pdf.resolve(v))));
			var root = d(pdf.trailer.get("Root")), info = d(pdf.trailer.get("Info"));
			// (links: a URI's action, a named destination)
			var annots = require(Values.arr(pdf.resolve(pdf.pages[0].dict.get("Annots"))));
			equals(annots.length, 2);
			var uri = d(d(annots[0]).get("A"));
			equals(s(uri.get("URI")), "https://helder.build/docs/?a=(1)");
			equals([for (v in require(Values.arr(d(annots[0]).get("Rect")))) Values.num(v)], [10.0, 268.0, 110.0, 280.0]);
			equals(s(d(annots[1]).get("Dest")), "chapter-2");
			var names = require(Values.arr(d(d(root.get("Names")).get("Dests")).get("Names")));
			equals([for (i in 0...names.length >> 1) s(names[i * 2])], ["chapter-2", "café"]);
			// (the outline: two at the top, the first with two children)
			var outlines = d(root.get("Outlines")), first = d(outlines.get("First"));
			equals(s(first.get("Title")), "One");
			equals(Values.int(first.get("Count")), 2);
			equals(s(d(first.get("First")).get("Title")), "One a");
			equals(s(d(d(first.get("First")).get("Next")).get("Title")), "One b");
			equals(s(d(first.get("Next")).get("Title")), "Two ש");
			var dest = require(Values.arr(pdf.resolve(d(first.get("Next")).get("Dest"))));
			equals(Values.num(dest[3]), 290.0);
			// (labels from 0 and 2)
			var nums = require(Values.arr(d(root.get("PageLabels")).get("Nums")));
			equals(Values.int(nums[0]), 0);
			equals(Values.name(d(nums[1]).get("S")), "r");
			equals(Values.int(nums[2]), 2);
			equals(s(d(nums[3]).get("P")), "A-");
			equals(Values.int(d(nums[3]).get("St")), 5);
			// (the information, again as XMP)
			equals(s(info.get("Title")), "A title (with parentheses)");
			equals(s(info.get("Author")), "Someone É");
			equals(s(info.get("CreationDate")), "D:20251126120000Z");
			equals(s(root.get("Lang")), "en");
			var xmp = pdf.stream(root.get("Metadata")).getString(0, pdf.stream(root.get("Metadata")).length, UTF8);
			assert(xmp.indexOf("<rdf:li xml:lang=\"x-default\">A title (with parentheses)</rdf:li>") >= 0, xmp);
			assert(xmp.indexOf("<xmp:ModifyDate>2025-11-26T13:00:00Z</xmp:ModifyDate>") >= 0, xmp);
			assert(xmp.indexOf("<rdf:li>text</rdf:li>") >= 0, xmp);
		});
	});
}

private function face(path:String):FontFile
	return FontFile.parse(sys.io.File.getBytes(path));

// (a PDF text string's characters)
private function pdfString(b:Bytes):String {
	if (b.length >= 2 && b.get(0) == 0xFE && b.get(1) == 0xFF) {
		var s = new StringBuf(), i = 2;
		while (i + 1 < b.length) {
			var c = (b.get(i) << 8) | b.get(i + 1);
			i += 2;
			if (c >= 0xD800 && c < 0xDC00 && i + 1 < b.length) {
				c = 0x10000 + ((c - 0xD800) << 10) + ((((b.get(i) << 8) | b.get(i + 1))) - 0xDC00);
				i += 2;
			}
			s.addChar(c);
		}
		return s.toString();
	}
	return b.toString();
}

// (a font of one colour glyph, U+2605: COLR's two layers over a square's halves, the left in its palette's
// red, the right the text's colour)
private function colourFont():Bytes {
	function square(x0:Float, x1:Float):Array<helder.text.FontEncoder.FontPoint>
		return [{x: x0, y: 0, on: true}, {x: x0, y: 1000, on: true}, {x: x1, y: 1000, on: true}, {x: x1, y: 0, on: true}];
	var colr = Bytes.alloc(28), cpal = Bytes.alloc(18);
	function u16(b:Bytes, at:Int, v:Int) {
		b.set(at, v >> 8);
		b.set(at + 1, v & 255);
	}
	u16(colr, 2, 1);
	u16(colr, 6, 14);
	u16(colr, 10, 20);
	u16(colr, 12, 2);
	u16(colr, 14, 1);
	u16(colr, 16, 0);
	u16(colr, 18, 2);
	u16(colr, 20, 2);
	u16(colr, 22, 0);
	u16(colr, 24, 3);
	u16(colr, 26, 0xFFFF);
	u16(cpal, 2, 1);
	u16(cpal, 4, 1);
	u16(cpal, 6, 1);
	u16(cpal, 10, 14);
	// (BGRA: red)
	cpal.set(16, 255);
	cpal.set(17, 255);
	return helder.text.FontEncoder.encode({
		family: "Colour Test",
		unitsPerEm: 1000,
		ascender: 1000,
		descender: -200,
		glyphs: [
			{codes: [], advance: 500, contours: []},
			{codes: [0x2605], advance: 1000, contours: [square(0, 1000)]},
			{codes: [], advance: 1000, contours: [square(0, 500)]},
			{codes: [], advance: 1000, contours: [square(500, 1000)]}
		],
		tables: ["COLR" => colr, "CPAL" => cpal]
	});
}

// a line of text in a page, as text or as its outlines
private function page(f:FontFile, text:String, paths:Bool):Bytes {
	var doc = new Document(), p = doc.newPage(420, 70);
	var l = new TextLayout(text, new FontSet(f, 24), 1.2, Math.POSITIVE_INFINITY);
	if (paths) {
		var g = new Glyphs();
		g.add(l, 10, 45);
		p.fill(g.path, Paint.solid(0xFF000000));
	} else Glyphs.fill(p, l, 10, 45, Paint.solid(0xFF000000));
	return PdfWriter.write(doc);
}

// the share of pixels off by more than 24 in a channel
private function differ(a:Bitmap, b:Bitmap):Float {
	var pa = a.pixels, pb = b.pixels, n = a.width * a.height, off = 0;
	if (a.width != b.width || a.height != b.height) return 1;
	for (i in 0...n)
		for (k in 0...4)
			if (Math.abs(pa.get(i * 4 + k) - pb.get(i * 4 + k)) > 24) {
				off++;
				break;
			}
	return off / n;
}

// (a CFF glyph's outline as text: two subsets compared)
private function path(cff:helder.text.Cff, g:Int):String {
	var p = new Path();
	cff.outline(g, new Sink(p));
	return [for (i in 0...p.pointCount) Std.string(p.points[i])].join(",");
}

private class Sink implements helder.text.Outline {
	final p:Path;

	public function new(p:Path)
		this.p = p;

	public function moveTo(x:Float, y:Float)
		p.moveTo(x, y);

	public function lineTo(x:Float, y:Float)
		p.lineTo(x, y);

	public function quadTo(cx:Float, cy:Float, x:Float, y:Float)
		p.quadTo(cx, cy, x, y);

	public function cubicTo(a:Float, b:Float, c:Float, d:Float, x:Float, y:Float)
		p.cubicTo(a, b, c, d, x, y);

	public function close()
		p.close();
}

// each drawn glyph's characters in a box where it was drawn: its own box at its pen with its advance, or
// a span's box that holds its pen; the baseline inside it
private function boxesAt(run:helder.pdf.PdfRun, l:TextLayout, x:Float, y:Float, size:Float) {
	var line = l.lines[0], tol = 0.02 + size * 0.001;
	for (i in line.glyphStart...line.glyphEnd) {
		if (l.glyphHidden(i)) continue;
		var c = l.glyphCluster(i), n = l.glyphLength(i);
		if (n == 0) continue;
		var gx = x + l.glyphX(i) + l.glyphOffsetX(i);
		var box:Null<helder.pdf.PdfGlyph> = null;
		for (g in run.glyphs)
			if (g.start <= c && c < g.end) {
				box = g;
				break;
			}
		if (box == null) {
			fail('no box for ${run.text.substr(c, n)} at $c');
			return;
		}
		var face = l.glyphFont(i);
		if (box.start == c && box.end == c + n) {
			assert(Math.abs(box.x - gx) < tol, '${run.text.substr(c, n)} at ${box.x}, drawn at $gx');
			var adv = face.advance(l.glyphId(i)) * size / face.unitsPerEm;
			assert(Math.abs(box.ax - adv) < tol, '${run.text.substr(c, n)}: an advance of ${box.ax}, drawn ${adv}');
		} else assert(gx > box.x - tol && gx < box.x + box.ax + tol, '${run.text.substr(c, n)} drawn at $gx, outside ${box.x} to ${box.x + box.ax}');
		var top = Math.min(box.y, box.y + box.uy), bottom = Math.max(box.y, box.y + box.uy);
		assert(top < y && y < bottom, 'the baseline $y outside $top to $bottom');
	}
}
