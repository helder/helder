package helder.pdf;

import helder.canvas.Matrix;

// (the interpreter's text, glyph by glyph: a newline when the line moved
// off its baseline or turned, a space at a gap of a quarter em along it;
// an ActualText span's characters for its glyphs, in its order: over each
// glyph whose own characters, read in content order or backwards (a
// right-to-left run in visual order), make the span's, else over one box
// from its first glyph to its last)
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
	// (an ActualText span's characters, its glyphs until its end)
	var span:Null<String> = null;
	var spanned:Array<{f:PdfFont, m:Matrix, w:Float, u:String}> = [];

	function new(shown:Matrix)
		this.shown = shown;

	// a glyph at m (glyph space to user space: the text rendering matrix and
	// the CTM), w its advance in ems, u its characters
	function add(f:PdfFont, m:Matrix, w:Float, u:String) {
		if (span != null) {
			spanned.push({f: f, m: m.clone(), w: w, u: u});
			return;
		}
		if (u != "") {
			gap(f, m, u);
			moved(f, m, w);
		}
		glyphs.push(box(f, m, w, length, length + u.length));
		text.add(u);
		length += u.length;
	}

	// a span's start: its glyphs' characters are these
	function begin(actual:String) {
		if (span != null) return;
		span = actual;
		spanned = [];
	}

	function end() {
		var actual = span, gs = spanned;
		if (actual == null) return;
		span = null;
		spanned = [];
		if (gs.length == 0) {
			text.add(actual);
			length += actual.length;
			return;
		}
		if (actual != "") gap(gs[0].f, gs[0].m, actual);
		var forward = [for (g in gs) g.u].join(""), backward = [for (k in 0...gs.length) gs[gs.length - 1 - k].u].join("");
		if (actual != "" && (forward == actual || backward == actual)) {
			// (both: a run that reads the same either way, "אא": backwards if it is written right to left)
			var at = length, back = forward != actual || backward == actual && rtl(actual);
			for (k in 0...gs.length) {
				var g = gs[back ? gs.length - 1 - k : k];
				glyphs.push(box(g.f, g.m, g.w, at, at + g.u.length));
				at += g.u.length;
			}
		} else {
			// (one box from the first's start to the last's end, along the first's line)
			var a = gs[0], z = gs[gs.length - 1];
			var b = box(a.f, a.m, a.w, length, length + actual.length);
			var ex = z.m.e + z.m.a * z.w - a.m.e, ey = z.m.f + z.m.b * z.w - a.m.f, s = shown;
			var sx = s.a * ex + s.c * ey, sy = s.b * ex + s.d * ey, al = Math.sqrt(b.ax * b.ax + b.ay * b.ay);
			var along = al > 1e-9 ? (sx * b.ax + sy * b.ay) / al : 0.0;
			if (along > al) b = new PdfGlyph(b.start, b.end, b.x, b.y, b.ax / al * along, b.ay / al * along, b.ux, b.uy);
			glyphs.push(b);
			for (k in 1...gs.length)
				glyphs.push(box(gs[k].f, gs[k].m, gs[k].w, length + actual.length, length + actual.length));
		}
		text.add(actual);
		length += actual.length;
		var z = gs[gs.length - 1];
		moved(z.f, z.m, z.w);
	}

	// (whether the text's first strong character is right to left)
	static function rtl(s:String):Bool {
		var i = 0;
		while (i < s.length) {
			var c = StringTools.fastCodeAt(s, i++);
			if (c >= 0xD800 && c < 0xDC00 && i < s.length) c = 0x10000 + ((c - 0xD800) << 10) + (StringTools.fastCodeAt(s, i++) - 0xDC00);
			switch helder.text.Bidi.classOf(c) {
				case helder.text.Bidi.L: return false;
				case helder.text.Bidi.R | helder.text.Bidi.AL: return true;
				case _:
			}
		}
		return false;
	}

	// (a new run where the line moved off its baseline or turned, a space at a gap along it)
	function gap(f:PdfFont, m:Matrix, u:String) {
		if (next == null) return;
		var size = Math.sqrt(m.c * m.c + m.d * m.d);
		var lx = f.vertical ? -m.c : m.a, ly = f.vertical ? -m.d : m.b, ll = Math.sqrt(lx * lx + ly * ly);
		if (ll > 0) {
			lx /= ll;
			ly /= ll;
		}
		var ex = m.e - next.x, ey = m.f - next.y, k = Math.max(size, lastSize);
		var along = ex * dx + ey * dy, across = Math.abs(ey * dx - ex * dy);
		if (across > k * 0.5 || lx * dx + ly * dy < 0.9) {
			runs.push(new PdfRun(text.toString(), glyphs));
			text = new StringBuf();
			length = 0;
			glyphs = [];
			next = null;
		} else if (along > k * 0.25 && u != " ") {
			text.add(" ");
			length++;
		}
	}

	// (where the glyph after this one would start)
	function moved(f:PdfFont, m:Matrix, w:Float) {
		var lx = f.vertical ? -m.c : m.a, ly = f.vertical ? -m.d : m.b, ll = Math.sqrt(lx * lx + ly * ly);
		if (ll > 0) {
			lx /= ll;
			ly /= ll;
		}
		var to = f.vertical ? {x: m.e - m.c * w, y: m.f - m.d * w} : {x: m.e + m.a * w, y: m.f + m.b * w};
		// (never back along the line: a mark drawn over its base leaves the base's end the next start)
		if (next == null || lx * dx + ly * dy < 0.9 || (to.x - next.x) * lx + (to.y - next.y) * ly > 0) next = to;
		dx = lx;
		dy = ly;
		lastSize = Math.sqrt(m.c * m.c + m.d * m.d);
	}

	function box(f:PdfFont, m:Matrix, w:Float, start:Int, end:Int):PdfGlyph {
		var s = shown, a = f.ascent, d = f.descent;
		var ox = m.e + m.c * d, oy = m.f + m.d * d, px = s.mapX(ox, oy), py = s.mapY(ox, oy);
		var ax = m.a * w, ay = m.b * w, ux = m.c * (a - d), uy = m.d * (a - d);
		return new PdfGlyph(start, end, px, py, s.a * ax + s.c * ay, s.b * ax + s.d * ay, s.a * ux + s.c * uy, s.b * ux + s.d * uy);
	}

	function done():Array<PdfRun> {
		end();
		if (glyphs.length > 0 || length > 0) runs.push(new PdfRun(text.toString(), glyphs));
		glyphs = [];
		return runs;
	}
}
