package helder.pdf;

import helder.canvas.Matrix;

// (the interpreter's text, glyph by glyph: a newline when the line moved
// off its baseline or turned, a space at a gap of a quarter em along it)
@:allow(helder.pdf)
class TextRuns {
	public final runs:Array<PdfRun> = [];

	final shown:Matrix;
	var text = new StringBuf();
	var length = 0;
	var glyphs:Array<PdfGlyph> = [];
	// (where the next glyph would start, the line's direction, the last one's size)
	var next:Null<{x:Float, y:Float}> = null;
	var dx = 1.0;
	var dy = 0.0;
	var lastSize = 0.0;

	function new(shown:Matrix)
		this.shown = shown;

	// a glyph at m (glyph space to user space: the text rendering matrix and
	// the CTM), w its advance in ems, u its characters
	function add(f:PdfFont, m:Matrix, w:Float, u:String) {
		var size = Math.sqrt(m.c * m.c + m.d * m.d);
		// (the line's direction: along the baseline, down a vertical font's column)
		var lx = f.vertical ? -m.c : m.a, ly = f.vertical ? -m.d : m.b, ll = Math.sqrt(lx * lx + ly * ly);
		if (ll > 0) {
			lx /= ll;
			ly /= ll;
		}
		if (u != "") {
			if (next != null) {
				var ex = m.e - next.x, ey = m.f - next.y, k = Math.max(size, lastSize);
				var along = ex * dx + ey * dy, across = Math.abs(ey * dx - ex * dy);
				if (across > k * 0.5 || lx * dx + ly * dy < 0.9) {
					runs.push(new PdfRun(text.toString(), glyphs));
					text = new StringBuf();
					length = 0;
					glyphs = [];
				} else if (along > k * 0.25 && u != " ") {
					text.add(" ");
					length++;
				}
			}
			next = f.vertical ? {x: m.e - m.c * w, y: m.f - m.d * w} : {x: m.e + m.a * w, y: m.f + m.b * w};
			dx = lx;
			dy = ly;
			lastSize = size;
		}
		var s = shown, a = f.ascent, d = f.descent;
		var ox = m.e + m.c * d, oy = m.f + m.d * d, px = s.mapX(ox, oy), py = s.mapY(ox, oy);
		var ax = m.a * w, ay = m.b * w, ux = m.c * (a - d), uy = m.d * (a - d);
		glyphs.push(new PdfGlyph(length, length + u.length, px, py, s.a * ax + s.c * ay, s.b * ax + s.d * ay, s.a * ux + s.c * uy, s.b * ux + s.d * uy));
		text.add(u);
		length += u.length;
	}

	function done():Array<PdfRun> {
		if (glyphs.length > 0 || length > 0) runs.push(new PdfRun(text.toString(), glyphs));
		glyphs = [];
		return runs;
	}
}
