package helder.canvas.doc;

import haxe.io.Bytes;
import helder.text.FontEncoder;
import helder.text.FontFile;
import helder.text.Outline;

// A document's fonts as PdfWriter writes them: a face (and its variation)
// one Type0 font of Identity-H codes for the whole file, embedded as the
// subset its pages show. TrueType faces as CIDFontType2 (FontFile2): the
// glyphs shown renumbered from 1 (a code is its glyph in the subset,
// CIDToGIDMap Identity), each one's outline as the face gives it (a
// variable font's at its instance; composites made simple) written again
// by FontEncoder, the points as they are. CFF faces as CIDFontType0
// (FontFile3, CIDFontType0C): the CFF table subset in place (Cff.subset:
// the charstrings and subroutines shown byte for byte, a code the glyph's
// index or a CID-keyed font's CID). Widths (W) are the face's advances, so
// a reader's spacing is the PDF's own, the layout's placed by TJ; ToUnicode
// maps a code to the characters it was first shown for. A face of colour
// bitmaps only is embedded with empty glyphs: its text is invisible (render
// mode 3), drawn apart (PdfWriter).
class PdfFonts {
	final writer:PdfWriter;
	final fonts:Array<EmbeddedFont> = [];

	public function new(writer:PdfWriter)
		this.writer = writer;

	// the face's font (the same face and variation: the same font)
	public function get(face:FontFile):EmbeddedFont {
		for (f in fonts)
			if (f.face == face || same(f.face, face)) return f;
		var f = new EmbeddedFont(face, writer.reserve(), fonts.length);
		fonts.push(f);
		return f;
	}

	static function same(a:FontFile, b:FontFile):Bool {
		if (a.data != b.data || a.faceIndex != b.faceIndex) return false;
		var va = a.variation, vb = b.variation;
		if (va == null || vb == null) return va == vb;
		if (va.length != vb.length) return false;
		for (i in 0...va.length)
			if (va[i] != vb[i]) return false;
		return true;
	}

	public function write()
		for (f in fonts)
			f.write(writer);
}

class EmbeddedFont {
	public final face:FontFile;
	// its Type0 font's object, its name in a page's resources
	public final id:Int;
	public final name:String;
	final index:Int;
	final cff:Bool;
	// glyph -> code, and back
	final codes = new Map<Int, Int>();
	final glyphs:Array<Int> = [];
	final unicode = new Map<Int, String>();

	public function new(face:FontFile, id:Int, index:Int) {
		this.face = face;
		this.id = id;
		this.index = index;
		name = "F" + id;
		cff = !face.trueType && !face.bitmapsOnly;
	}

	// the code that shows a glyph (two bytes)
	public function code(g:Int):Int {
		var c = codes.get(g);
		if (c != null) return c;
		// (TrueType: its place in the subset, .notdef first; CFF: the glyph itself, a CID-keyed one's CID)
		if (!cff && glyphs.length == 0 && g != 0) code(0);
		c = cff ? face.glyphCid(g) : glyphs.length;
		codes.set(g, c);
		glyphs.push(g);
		return c;
	}

	// the glyph's characters for ToUnicode: true when they are its own (the first given), false when it
	// shows others (an ActualText then says them)
	public function map(g:Int, text:String):Bool {
		var c = code(g), u = unicode.get(c);
		if (u == null) {
			if (text == "") return false;
			unicode.set(c, text);
			return true;
		}
		return u == text;
	}

	public function mapped(g:Int):Bool
		return unicode.exists(code(g));

	// an advance in thousandths of an em
	public function width(g:Int):Float
		return face.advance(g) * 1000 / face.unitsPerEm;

	public function write(w:PdfWriter) {
		if (glyphs.length == 0) code(0);
		var order = glyphs.copy();
		var program = cff ? face.cffSubset(order) : trueType(order), programKey = cff ? "FontFile3" : "FontFile2";
		var tag = subsetTag(order);
		var psName = tag + "+" + postScript(face.postScriptName == "" ? face.family : face.postScriptName);
		var k = 1000 / face.unitsPerEm;
		var fileId = w.reserve();
		if (cff) w.stream(fileId, "/Subtype /CIDFontType0C", program) else w.stream(fileId, '/Length1 ${program.length}', program);
		var bbox = bounds(order);
		var flags = 4 | (face.italic ? 64 : 0);
		var descriptor = w.add('<< /Type /FontDescriptor /FontName /$psName /Flags $flags /FontBBox [${bbox.map(v -> Std.string(Math.round(v * k))).join(" ")}]'
			+ ' /ItalicAngle 0 /Ascent ${Math.round(face.ascender * k)} /Descent ${Math.round(face.descender * k)} /CapHeight ${Math.round(face.ascender * k)}'
			+ ' /StemV 80 /$programKey $fileId 0 R >>');
		// (widths by code, runs of consecutive codes in one array)
		var byCode = [for (g in order) {code: codes.get(g), width: Math.round(width(g))}];
		byCode.sort((a, b) -> a.code - b.code);
		var wb = new StringBuf(), i = 0;
		while (i < byCode.length) {
			var j = i + 1;
			while (j < byCode.length && byCode[j].code == byCode[j - 1].code + 1)
				j++;
			wb.add('${byCode[i].code} [${[for (x in i...j) byCode[x].width].join(" ")}] ');
			i = j;
		}
		var cidFont = w.add('<< /Type /Font /Subtype /${cff ? "CIDFontType0" : "CIDFontType2"} /BaseFont /$psName'
			+ ' /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /FontDescriptor $descriptor 0 R /DW 0 /W [${wb.toString()}]'
			+ '${cff ? "" : " /CIDToGIDMap /Identity"} >>');
		var toUnicode = w.reserve();
		w.stream(toUnicode, "", Bytes.ofString(cmap()));
		w.set(id, '<< /Type /Font /Subtype /Type0 /BaseFont /$psName /Encoding /Identity-H /DescendantFonts [$cidFont 0 R] /ToUnicode $toUnicode 0 R >>');
	}

	// (the six letters before a subset's name: its glyphs and place, the same for the same document)
	function subsetTag(order:Array<Int>):String {
		var h = 0x811C9DC5 ^ index;
		for (g in order)
			h = (h ^ g) * 0x01000193;
		var s = new StringBuf();
		for (_ in 0...6) {
			s.addChar(65 + ((h >>> 0) % 26 + 26) % 26);
			h = Std.int(h / 26);
		}
		return s.toString();
	}

	static function postScript(n:String):String {
		var s = new StringBuf();
		for (i in 0...n.length) {
			var c = StringTools.fastCodeAt(n, i);
			if (c > 32 && c < 127 && "()<>[]{}/%#".indexOf(String.fromCharCode(c)) < 0) s.addChar(c);
		}
		return s.length == 0 ? "Font" : s.toString();
	}

	function bounds(order:Array<Int>):Array<Int> {
		var x0 = 0, y0 = face.descender, x1 = 0, y1 = face.ascender;
		for (g in order) {
			var b = face.bounds(g);
			if (b == null || b.length < 4 || b[2] <= b[0]) continue;
			if (b[0] < x0) x0 = b[0];
			if (b[1] < y0) y0 = b[1];
			if (b[2] > x1) x1 = b[2];
			if (b[3] > y1) y1 = b[3];
		}
		return [x0, y0, x1, y1];
	}

	// the subset as a TrueType font, glyph i of it order[i] (FontEncoder: its points as the face gives them)
	function trueType(order:Array<Int>):Bytes {
		var sink = new Contours();
		var list:Array<FontGlyph> = [];
		for (g in order) {
			sink.contours = [];
			if (!face.bitmapsOnly) face.outline(g, sink);
			sink.close();
			list.push({codes: [], advance: face.advance(g), contours: sink.contours});
		}
		return FontEncoder.encode({
			family: face.family == "" ? "Font" : face.family,
			style: face.subfamily == "" ? null : face.subfamily,
			unitsPerEm: face.unitsPerEm,
			ascender: face.ascender,
			descender: face.descender,
			lineGap: face.lineGap,
			weight: face.weight,
			glyphs: list,
			postScriptName: postScript(face.postScriptName),
			modified: 0
		});
	}

	// the ToUnicode CMap: each code's characters, UTF-16BE
	function cmap():String {
		var b = new StringBuf();
		b.add("/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def\n");
		b.add("/CMapName /Adobe-Identity-UCS def\n/CMapType 2 def\n1 begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n");
		var list = [for (c in unicode.keys()) c];
		list.sort((a, b) -> a - b);
		var i = 0;
		while (i < list.length) {
			var n = list.length - i > 100 ? 100 : list.length - i;
			b.add('$n beginbfchar\n');
			for (k in i...i + n) {
				var u = unicode.get(list[k]);
				b.add("<" + StringTools.hex(list[k], 4) + "> <");
				for (j in 0...u.length)
					b.add(StringTools.hex(StringTools.fastCodeAt(u, j), 4));
				b.add(">\n");
			}
			b.add("endbfchar\n");
			i += n;
		}
		b.add("endcmap\nCMapName currentdict /CMap defineresource pop\nend\nend\n");
		return b.toString();
	}
}

// (a glyph's outline as TrueType contours: the on-curve points halfway between
// two off-curve ones left out again, as glyf has them)
private class Contours implements Outline {
	public var contours:Array<Array<FontPoint>> = [];
	var current:Null<Array<FontPoint>> = null;
	var lx = 0.0;
	var ly = 0.0;

	public function new() {}

	public function moveTo(x:Float, y:Float) {
		close();
		current = [{x: x, y: y, on: true}];
		lx = x;
		ly = y;
	}

	public function lineTo(x:Float, y:Float) {
		if (current == null) moveTo(lx, ly);
		current.push({x: x, y: y, on: true});
		lx = x;
		ly = y;
	}

	public function quadTo(cx:Float, cy:Float, x:Float, y:Float) {
		if (current == null) moveTo(lx, ly);
		current.push({x: cx, y: cy, on: false});
		current.push({x: x, y: y, on: true});
		lx = x;
		ly = y;
	}

	// (not TrueType's: a cubic as two quadratics, each through its half's midpoint control)
	public function cubicTo(c1x:Float, c1y:Float, c2x:Float, c2y:Float, x:Float, y:Float) {
		var q0x = (lx + c1x) / 2, q0y = (ly + c1y) / 2, q1x = (c1x + c2x) / 2, q1y = (c1y + c2y) / 2, q2x = (c2x + x) / 2, q2y = (c2y + y) / 2;
		var r0x = (q0x + q1x) / 2, r0y = (q0y + q1y) / 2, r1x = (q1x + q2x) / 2, r1y = (q1y + q2y) / 2, sx = (r0x + r1x) / 2, sy = (r0y + r1y) / 2;
		var px = lx, py = ly;
		quadTo((3 * (q0x + r0x) - px - sx) / 4, (3 * (q0y + r0y) - py - sy) / 4, sx, sy);
		quadTo((3 * (r1x + q2x) - sx - x) / 4, (3 * (r1y + q2y) - sy - y) / 4, x, y);
	}

	public function close() {
		var c = current;
		current = null;
		if (c == null || c.length < 2) return;
		var last = c[c.length - 1];
		if (last.on && last.x == c[0].x && last.y == c[0].y) c.pop();
		var i = 0;
		while (i < c.length && c.length > 2) {
			var p = c[i], a = c[(i + c.length - 1) % c.length], b = c[(i + 1) % c.length];
			if (p.on && !a.on && !b.on && p.x * 2 == a.x + b.x && p.y * 2 == a.y + b.y) c.splice(i, 1) else i++;
		}
		contours.push(c);
	}
}
