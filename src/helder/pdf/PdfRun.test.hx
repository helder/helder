package helder.pdf;

import haxe.io.Bytes;
import helder.test.Gen;
import helder.test.Test;

using StringTools;

// Pdf.runs: lines and gaps as Pdf.text has them, each glyph's box on the
// page as shown (turned text, a turned page, a vertical font), a font with
// no ToUnicode whose codes map to nothing kept as boxes without text
function tests() {
	describe("pdf runs", () -> {
		test("lines and words, each glyph's box", () -> {
			var page = one(pdf(["BT /F1 10 Tf 72 700 Td (Hello) Tj 40 0 Td (world) Tj 0 -14 Td (two) Tj ET"]));
			var runs = Pdf.runs(page);
			equals([for (r in runs) r.text], ["Hello world", "two"]);
			equals(Pdf.text(page), "Hello world\ntwo");
			// (H: 72 from the left, its baseline 700 up a 792-point page, 0.5 em wide; the ascent 0.8 em over it)
			var h = runs[0].glyphs[0];
			equals([h.start, h.end], [0, 1]);
			approx(h.x, 72);
			approx(h.y, 792 - 700 + 2);
			approx(h.ax, 5);
			approx(h.uy, -10);
			// (the gap's space has no glyph: w is the sixth)
			equals(runs[0].glyphs[5].start, 6);
		});
		test("turned text, a turned page", () -> {
			var up = one(pdf(["BT /F1 10 Tf 0 1 -1 0 300 100 Tm (Up the) Tj 40 0 Td (side) Tj ET"]));
			equals(Pdf.text(up), "Up the side");
			var g = Pdf.runs(up)[0].glyphs[0];
			approx(g.ax, 0);
			approx(g.ay, -5);
			var turned = one(pdf(["BT /F1 10 Tf 72 700 Td (Across) Tj ET"], 90));
			equals(Pdf.text(turned), "Across");
			var t = Pdf.runs(turned)[0].glyphs[0];
			// (the page shown 792 wide: its baseline 700 from the left, down from 72 below the top)
			approx(t.ax, 0);
			approx(t.ay, 5);
			approx(t.x, 700 - 2);
			approx(t.y, 72);
		});
		test("a vertical font: down a column, one line", () -> {
			var v = one(pdf(["BT /F2 10 Tf 200 700 Td <000100020003> Tj ET"]));
			equals(Pdf.text(v), "abc");
			var gs = Pdf.runs(v)[0].glyphs;
			approx(gs[1].y - gs[0].y, 10);
		});
		test("codes that map to nothing: boxes without text", () -> {
			var page = one(pdf(["BT /F3 10 Tf 72 700 Td <010203> Tj ( and) Tj ET"]));
			var r = Pdf.runs(page)[0];
			equals(r.text, " and");
			equals([for (g in r.glyphs) g.end - g.start], [0, 0, 0, 1, 1, 1, 1]);
		});
		test("the runs joined are Pdf.text; every glyph inside its page", () -> property(lines(), ls -> {
			var page = one(pdf([for (l in ls) show(l)], ls.length > 0 ? ls[0].rotate : 0));
			var runs = Pdf.runs(page);
			equals([for (r in runs) r.text].join("\n"), Pdf.text(page));
			var w = page.width, h = page.height;
			for (r in runs)
				for (g in r.glyphs)
					for (p in [[g.x, g.y], [g.x + g.ax, g.y + g.ay], [g.x + g.ux, g.y + g.uy], [g.x + g.ax + g.ux, g.y + g.ay + g.uy]])
						assert(p[0] >= -1e-6 && p[0] <= w + 1e-6 && p[1] >= -1e-6 && p[1] <= h + 1e-6, 'a glyph at $p, outside $w x $h');
			// (every character shown, in order: only the gaps' spaces added)
			var shown = [for (l in ls) l.text].join("").replace(" ", "");
			equals(Pdf.text(page).replace(" ", "").replace("\n", ""), shown);
		}));
	});
}

typedef Line = {text:String, x:Float, y:Float, angle:Int, size:Float, rotate:Int};

// (lines of words somewhere on the page, turned by a quarter or not, their
// ends within it at 0.5 em a character)
function lines():Gen<Array<Line>>
	return array(c -> {
		var text = c.draw(string(pick(["a", "b", "x", " "]), 1, 20)), size = c.draw(float(4, 12));
		{
			text: text,
			x: c.draw(float(150, 450)),
			y: c.draw(float(150, 650)),
			angle: c.draw(pick([0, 90, 180, 270])),
			size: size,
			rotate: c.draw(pick([0, 90, 180, 270]))
		}
	}, 0, 8);

function show(l:Line):String {
	var r = l.angle * Math.PI / 180, cs = Math.round(Math.cos(r)), sn = Math.round(Math.sin(r));
	return 'BT /F1 ${l.size} Tf $cs $sn ${-sn} $cs ${l.x} ${l.y} Tm (${l.text}) Tj ET';
}

function one(b:Bytes):Document.Page
	return Pdf.open(b).pages[0];

// a one-page Letter PDF of these content streams: F1 a Helvetica every
// character 0.5 em wide, F2 a vertical Identity-V font (codes 1 to 3 to a,
// b, c by its ToUnicode), F3 a Type 3 font of three glyphs with no names
// a table knows and no ToUnicode (and its space and letters by their names)
function pdf(contents:Array<String>, rotate = 0):Bytes {
	var content = contents.join("\n");
	var widths = [for (_ in 32...127) "500"].join(" ");
	var cmap = "/CIDInit /ProcSet findresource begin 12 dict begin begincmap 1 begincodespacerange <0000> <FFFF> endcodespacerange "
		+ "3 beginbfchar <0001> <0061> <0002> <0062> <0003> <0063> endbfchar endcmap CMapName currentdict /CMap defineresource pop end end";
	var objs = [
		"<< /Type /Catalog /Pages 2 0 R >>",
		"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
		'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Rotate $rotate /Contents 4 0 R /Resources << /Font << /F1 5 0 R /F2 6 0 R /F3 9 0 R >> >> >>',
		'<< /Length ${content.length} >>\nstream\n$content\nendstream',
		'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /FirstChar 32 /LastChar 126 /Widths [$widths] >>',
		"<< /Type /Font /Subtype /Type0 /BaseFont /V /Encoding /Identity-V /DescendantFonts [7 0 R] /ToUnicode 8 0 R >>",
		"<< /Type /Font /Subtype /CIDFontType2 /BaseFont /V /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /DW 1000 >>",
		'<< /Length ${cmap.length} >>\nstream\n$cmap\nendstream',
		"<< /Type /Font /Subtype /Type3 /FontBBox [0 0 1000 1000] /FontMatrix [0.001 0 0 0.001 0 0] /CharProcs 10 0 R /Encoding << /Differences [1 /g1 /g2 /g3 32 /space 97 /a 100 /d 110 /n] >> /FirstChar 1 /LastChar 110 /Widths ["
		+ [for (i in 1...111) "600"].join(" ") + "] >>",
		"<< /g1 11 0 R /g2 11 0 R /g3 11 0 R /space 11 0 R /a 11 0 R /d 11 0 R /n 11 0 R >>",
		"<< /Length 34 >>\nstream\n600 0 d0 0 0 500 500 re f\nendstream"
	];
	var b = new StringBuf(), offsets = [];
	b.add("%PDF-1.4\n");
	var at = 9;
	for (i in 0...objs.length) {
		offsets.push(at);
		var o = '${i + 1} 0 obj\n${objs[i]}\nendobj\n';
		b.add(o);
		at += o.length;
	}
	b.add('xref\n0 ${objs.length + 1}\n0000000000 65535 f \n');
	for (o in offsets)
		b.add(StringTools.lpad(Std.string(o), "0", 10) + " 00000 n \n");
	b.add('trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\nstartxref\n$at\n%%EOF\n');
	return Bytes.ofString(b.toString());
}
