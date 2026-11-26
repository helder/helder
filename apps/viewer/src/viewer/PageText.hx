package viewer;

import helder.pdf.PdfRun;

// A PDF page's text for selecting it (helder.pdf's Pdf.runs, sendable from
// a decode's job): its text (Pdf.text) and each UTF-16 character's box on
// the page as shown, in points, six numbers each (PdfGlyph's corner, advance
// and ascent sides; NaN: none, a gap's space, a line's end). A ligature's
// characters share its glyph's box in equal parts; a glyph with no text has
// none.
typedef PageText = {text:String, boxes:Array<Float>};

class PageTexts {
	public static function of(runs:Array<PdfRun>):PageText {
		var b = new StringBuf(), boxes:Array<Float> = [], at = 0;
		for (k in 0...runs.length) {
			var r = runs[k];
			if (k > 0) {
				b.add("\n");
				none(boxes, 1);
				at++;
			}
			b.add(r.text);
			none(boxes, r.text.length);
			for (g in r.glyphs) {
				var n = g.end - g.start;
				for (j in 0...n) {
					var i = (at + g.start + j) * 6;
					boxes[i] = g.x + g.ax * j / n;
					boxes[i + 1] = g.y + g.ay * j / n;
					boxes[i + 2] = g.ax / n;
					boxes[i + 3] = g.ay / n;
					boxes[i + 4] = g.ux;
					boxes[i + 5] = g.uy;
				}
			}
			at += r.text.length;
		}
		return {text: b.toString(), boxes: boxes};
	}

	static function none(boxes:Array<Float>, n:Int)
		for (_ in 0...n * 6)
			boxes.push(Math.NaN);

	static inline function has(t:PageText, i:Int):Bool
		return i >= 0 && i < t.text.length && i * 6 < t.boxes.length && !Math.isNaN(t.boxes[i * 6]);

	// (where a point is in character i's box: along it (0 to 1) and up it)
	static function local(t:PageText, i:Int, x:Float, y:Float):{s:Float, t:Float} {
		var b = t.boxes, k = i * 6, ax = b[k + 2], ay = b[k + 3], ux = b[k + 4], uy = b[k + 5];
		var det = ax * uy - ay * ux, dx = x - b[k], dy = y - b[k + 1];
		if (Math.abs(det) < 1e-9) return {s: Math.POSITIVE_INFINITY, t: Math.POSITIVE_INFINITY};
		return {s: (dx * uy - dy * ux) / det, t: (ax * dy - ay * dx) / det};
	}

	// the character whose box is under a point (-1: none)
	public static function over(t:PageText, x:Float, y:Float):Int {
		for (i in 0...t.text.length)
			if (has(t, i)) {
				var l = local(t, i, x, y);
				if (l.s >= 0 && l.s <= 1 && l.t >= 0 && l.t <= 1) return i;
			}
		return -1;
	}

	// the index nearest to a point: in a box, before or after its character
	// by its half; else the nearest box's, its line's first (under: the
	// character itself)
	public static function index(t:PageText, x:Float, y:Float, under = false):Int {
		var best = -1, bestS = 0.0, score = Math.POSITIVE_INFINITY, b = t.boxes;
		for (i in 0...t.text.length) {
			if (!has(t, i)) continue;
			var l = local(t, i, x, y), k = i * 6;
			var along = l.s < 0 ? -l.s : l.s > 1 ? l.s - 1 : 0.0, across = l.t < 0 ? -l.t : l.t > 1 ? l.t - 1 : 0.0;
			// (in points: off its line counts more than along it)
			var d = across * Math.sqrt(b[k + 4] * b[k + 4] + b[k + 5] * b[k + 5]) * 8 + along * Math.sqrt(b[k + 2] * b[k + 2] + b[k + 3] * b[k + 3]);
			if (d < score) {
				score = d;
				best = i;
				bestS = l.s;
				if (d == 0) break;
			}
		}
		if (best < 0) return 0;
		return under || bestS < 0.5 ? best : best + 1;
	}

	// index i's caret on the page: x, its line's top and height (null: no box near it)
	public static function caret(t:PageText, i:Int):Null<{x:Float, y:Float, height:Float}> {
		var b = t.boxes, k = i * 6;
		var x = 0.0, y = 0.0;
		if (has(t, i)) {
			x = b[k];
			y = b[k + 1];
		} else if (has(t, i - 1)) {
			k = (i - 1) * 6;
			x = b[k] + b[k + 2];
			y = b[k + 1] + b[k + 3];
		} else return null;
		var ux = b[k + 4], uy = b[k + 5];
		return {x: x + Math.min(0, ux), y: Math.min(y, y + uy), height: Math.max(Math.abs(uy), 1)};
	}

	// the boxes a range is highlighted with: a box from each line's first
	// character in it to its last, the first's sides (corner, along, up)
	public static function spans(t:PageText, start:Int, end:Int):Array<Array<Float>> {
		var out = [], b = t.boxes, first = -1, last = -1;
		function close() {
			if (first < 0) return;
			var k = first * 6, ax = b[k + 2], ay = b[k + 3], len = Math.sqrt(ax * ax + ay * ay);
			var q = last * 6, ex = b[q] + b[q + 2] - b[k], ey = b[q + 1] + b[q + 3] - b[k + 1];
			var w = len > 1e-9 ? (ex * ax + ey * ay) / len : 0.0;
			if (len > 1e-9 && w > 0) out.push([b[k], b[k + 1], ax / len * w, ay / len * w, b[k + 4], b[k + 5]]);
			first = -1;
		}
		for (i in (start < 0 ? 0 : start)...(end > t.text.length ? t.text.length : end)) {
			if (StringTools.fastCodeAt(t.text, i) == "\n".code) close();
			if (!has(t, i)) continue;
			if (first < 0) first = i;
			last = i;
		}
		close();
		return out;
	}
}
