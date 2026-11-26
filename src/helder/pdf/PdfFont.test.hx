package helder.pdf;

import haxe.io.Bytes;
import helder.test.Gen;
import helder.test.Test;
import helder.text.FontEncoder;
import helder.text.FontEncoder.FontPoint;

// A composite font's TrueType subset without a cmap table (as PDF writers
// make them: CIDToGIDMap Identity, the glyphs by CID) drawn from its own
// glyphs, a ligature's code whose ToUnicode is "ti" its glyph whole. It
// was read as no font at all, a system face drawn in its place with the
// code's first character alone ("situatie" as "situat e", Lato's
// subsets in Office's PDFs). As a property: any ligature glyph (a few boxes
// anywhere in the em) is inked inside each of its boxes, and its text is
// "ti".
function tests() {
	describe("PdfFont, an embedded TrueType without a cmap", () -> {
		var box:Gen<Array<Int>> = c -> [c.draw(int(0, 850)), c.draw(int(0, 450)), c.draw(int(70, 150)), c.draw(int(70, 250))];
		test("a ligature's glyph drawn whole, its text its characters", () -> property(array(box, 1, 3), boxes -> {
			var doc = Pdf.open(ligaturePdf(boxes));
			equals(Pdf.text(doc.pages[0]), "ti");
			var page = Pdf.render(doc, 0, 1), px = page.straight();
			for (b in boxes) {
				// (the box's centre: font units at 100 points, from the origin at 20, 50; y down on the page)
				var x = Std.int(20 + (b[0] + b[2] / 2) * 0.1), y = Std.int(PAGE - (50 + (b[1] + b[3] / 2) * 0.1));
				var r = px.get((y * page.width + x) * 4);
				assert(r < 128, 'the box ${b} not inked at $x, $y ($r)');
			}
		}));
		// (a font not embedded, a system face in its place: the code's characters each drawn, "ti" wider than "t")
		test("not embedded: a ligature's characters each drawn by the substitute", () -> {
			if (helder.text.SystemFonts.get().match("sans-serif") == null) return;
			function inkWidth(text:String):Int {
				var page = Pdf.render(Pdf.open(substitutePdf(text)), 0, 1), px = page.straight(), lo = page.width, hi = -1;
				for (y in 0...page.height)
					for (x in 0...page.width)
						if (px.get((y * page.width + x) * 4) < 128) {
							if (x < lo) lo = x;
							if (x > hi) hi = x;
						}
				return hi < 0 ? 0 : hi - lo + 1;
			}
			var t = inkWidth("0074"), ti = inkWidth("00740069");
			assert(t > 0, "no t drawn");
			assert(ti > t + 5, 'ti ${ti} pixels wide, t alone ${t}: its i not drawn');
		});
	});
}

// (a page of one code, 3, in a Type0 font with no program: a system face drawn, ToUnicode 3 -> the UTF-16BE given)
private function substitutePdf(utf16:String):Bytes {
	var toUnicode = "/CIDInit /ProcSet findresource begin 12 dict begin begincmap /CMapName /Lig def 1 begincodespacerange <0000> <FFFF> endcodespacerange\n"
		+ '1 beginbfchar <0003> <$utf16> endbfchar endcmap CMapName currentdict /CMap defineresource pop end end';
	return document([
		Bytes.ofString("<< /Type /Font /Subtype /Type0 /BaseFont /Helvetica /Encoding /Identity-H /DescendantFonts [6 0 R] /ToUnicode 8 0 R >>"),
		Bytes.ofString("<< /Type /Font /Subtype /CIDFontType2 /BaseFont /Helvetica /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >>"
			+ " /FontDescriptor 7 0 R /DW 600 >>"),
		Bytes.ofString("<< /Type /FontDescriptor /FontName /Helvetica /Flags 32 /FontBBox [0 -200 1000 800] /ItalicAngle 0 /Ascent 800 /Descent -200"
			+ " /CapHeight 700 /StemV 80 >>"),
		stream(Bytes.ofString(toUnicode), "")
	]);
}

private inline var PAGE = 200;

// (a page of one code, 3, in a Type0 font: Identity-H, its CIDFontType2's
// program a FontEncoder font of .notdef, "t", "i" and the ligature, its cmap
// table out; ToUnicode 3 -> "ti")
private function ligaturePdf(boxes:Array<Array<Int>>):Bytes {
	inline function rect(b:Array<Int>):Array<FontPoint>
		return [{x: b[0], y: b[1], on: true}, {x: b[0], y: b[1] + b[3], on: true}, {x: b[0] + b[2], y: b[1] + b[3], on: true},
			{x: b[0] + b[2], y: b[1], on: true}];
	var font = withoutCmap(FontEncoder.encode({
		family: "Subset",
		unitsPerEm: 1000,
		ascender: 800,
		descender: -200,
		glyphs: [
			{codes: [], advance: 500, contours: []},
			{codes: [0x74], advance: 400, contours: [rect([50, 0, 100, 700])]},
			{codes: [0x69], advance: 300, contours: [rect([50, 0, 80, 500])]},
			{codes: [0xFB01], advance: 1000, contours: [for (b in boxes) rect(b)]}
		]
	}));
	var toUnicode = "/CIDInit /ProcSet findresource begin 12 dict begin begincmap /CMapName /Lig def 1 begincodespacerange <0000> <FFFF> endcodespacerange\n"
		+ "1 beginbfchar <0003> <00740069> endbfchar endcmap CMapName currentdict /CMap defineresource pop end end";
	return document([
		Bytes.ofString("<< /Type /Font /Subtype /Type0 /BaseFont /AAAAAA+Subset /Encoding /Identity-H /DescendantFonts [6 0 R] /ToUnicode 8 0 R >>"),
		Bytes.ofString("<< /Type /Font /Subtype /CIDFontType2 /BaseFont /AAAAAA+Subset /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >>"
			+ " /FontDescriptor 7 0 R /CIDToGIDMap /Identity /DW 1000 >>"),
		Bytes.ofString("<< /Type /FontDescriptor /FontName /AAAAAA+Subset /Flags 4 /FontBBox [0 -200 1000 800] /ItalicAngle 0 /Ascent 800 /Descent -200"
			+ " /CapHeight 700 /StemV 80 /FontFile2 9 0 R >>"),
		stream(Bytes.ofString(toUnicode), ""),
		stream(font, '/Length1 ${font.length} ')
	]);
}

// (a one-page document: its catalog, pages, page and content, code 3 at 100 points from 20, 50, then the font's objects from 5)
private function document(font:Array<Bytes>):Bytes {
	var content = "BT /F1 100 Tf 20 50 Td <0003> Tj ET";
	var objs:Array<Bytes> = [
		Bytes.ofString("<< /Type /Catalog /Pages 2 0 R >>"),
		Bytes.ofString("<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
		Bytes.ofString('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $PAGE $PAGE] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>'),
		stream(Bytes.ofString(content), "")
	].concat(font);
	var out = new haxe.io.BytesOutput(), offsets = [];
	out.writeString("%PDF-1.7\n");
	for (i in 0...objs.length) {
		offsets.push(out.length);
		out.writeString('${i + 1} 0 obj\n');
		out.write(objs[i]);
		out.writeString("\nendobj\n");
	}
	var xref = out.length;
	out.writeString('xref\n0 ${objs.length + 1}\n0000000000 65535 f \n');
	for (o in offsets)
		out.writeString(StringTools.lpad(Std.string(o), "0", 10) + " 00000 n \n");
	out.writeString('trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
	return out.getBytes();
}

private function stream(data:Bytes, extra:String):Bytes {
	var o = new haxe.io.BytesOutput();
	o.writeString('<< $extra/Length ${data.length} >>\nstream\n');
	o.write(data);
	o.writeString("\nendstream");
	return o.getBytes();
}

// (its cmap table's record out of the directory, the other tables where they were)
private function withoutCmap(b:Bytes):Bytes {
	var out = Bytes.alloc(b.length);
	out.blit(0, b, 0, b.length);
	var n = (b.get(4) << 8) | b.get(5), at = 12;
	for (i in 0...n) {
		var r = 12 + 16 * i;
		if (b.getString(r, 4) == "cmap") continue;
		out.blit(at, b, r, 16);
		at += 16;
	}
	out.fill(at, 12 + 16 * n - at, 0);
	out.set(4, ((at - 12) >> 4) >> 8);
	out.set(5, ((at - 12) >> 4) & 0xFF);
	return out;
}
