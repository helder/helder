package helder.ui.flow;

import helder.canvas.ShapedRun;
import helder.text.FontSet;
import helder.ui.box.Box;

// A line's plain text (InlineLayout.plain): its item's words in the shaped
// word cache placed one after the other from its start, its glyph run made
// from them when it is first asked for (paint, a hit test, a PDF), not as
// the lines are laid out: what a long document's lines keep is a few
// numbers each, and a relayout copies no glyph (LayoutNG's ShapeResultView
// over its items' shape results).
class LazyText {
	// the run of an item's text from start to end: each glyph's pen from its start, as the line builder places them
	public static function make(content:InlineContent, item:Int, start:Int, end:Int, fonts:FontSet, box:Box, palettes:helder.ui.box.FontMatch):ShapedRun {
		var c = content, sh = c.shaper, face = fonts.first;
		c.ensureShaped();
		// (the piece holding start: the last that starts at or before it)
		var lo = 0, hi = c.pieces - 1;
		while (lo < hi) {
			var m = (lo + hi + 1) >> 1;
			if (c.pieceStart(m) <= start) lo = m else hi = m - 1;
		}
		var p = lo;
		while (p > 0 && c.pieceStart(p - 1) == c.pieceStart(p))
			p--;
		var x = 0.0, ids:Array<Int> = [], xs:Array<Float> = [], ys:Array<Float> = [], clusters:Array<Int> = [];
		while (p < c.pieces && c.pieceStart(p) < end) {
			var s = c.pieceStart(p), e = c.pieceEnd(p);
			if (c.pieceItem(p) != item || c.pieceKind(p) == InlineContent.ITEM || e <= start) {
				p++;
				continue;
			}
			var from = s > start ? s : start, to = e < end ? e : end, entry = c.pieceEntry(p);
			if (entry >= 0) {
				var whole = from == s && to == e, gx = x;
				for (g in sh.glyphStart(entry)...sh.glyphStart(entry) + sh.glyphCount(entry)) {
					var cl = s + sh.cluster(g);
					if (!whole && (cl < from || cl >= to)) continue;
					if (sh.id(g) >= 0) {
						ids.push(sh.id(g));
						xs.push(gx + sh.dx(g));
						ys.push(sh.dy(g));
						clusters.push(cl);
					}
					gx += sh.advance(g);
				}
			}
			// (the next piece where the line builder puts it: a word's width, or its units' advance)
			x += from == s && to == e ? c.pieceWidth(p) : entry >= 0 ? sh.advanceOf(entry, from - s, to - s) : 0;
			p++;
		}
		// (each glyph's characters: its cluster up to the next one above it, the text's end after the last)
		var n = ids.length, ends = [], next = end, k = n;
		ends.resize(n);
		while (--k >= 0) {
			ends[k] = next;
			if (k == 0 || clusters[k - 1] != clusters[k]) next = clusters[k];
		}
		var run = new ShapedRun(face, fonts.size);
		run.skew = fonts.oblique && (face == fonts.primary || !face.italic) ? 0.25 : 0;
		run.bold = fonts.bold && (face == fonts.primary || face.weight < 600) ? BlockLines.embolden(fonts.size) : 0;
		if (face.hasColor) run.palette = palettes.palette(face, box.style);
		run.text = c.text;
		run.reserve(n);
		for (i in 0...n) {
			var u = clusters[i] < start ? start : clusters[i];
			run.push(ids[i], xs[i], ys[i], u, ends[i] > u ? ends[i] : u + 1);
		}
		return run;
	}
}
