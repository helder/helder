package helder.ui.flow;

import haxe.ds.Vector;

// An InlineContent laid out in line boxes (LineBuilder's), as flat arrays:
// per line its top, height, baseline (from its top), the inline size it
// uses (its indent in, hanging spaces out), its left (where its content
// starts: the constraints' offset and text-align's), its text range and its
// fragments; per fragment its kind (InlineFragment), rectangle, ascent and
// descent, bidi level, item, text range and glyph run (InlineGlyphs: -1
// none). Coordinates are pixels from the IFC's content box's top left.
// Kept and filled again by each layout, allocating only to grow; laid out
// again with the same content and constraints it does nothing (the cache).
@:allow(helder.ui.flow.LineBuilder)
class InlineLayout {
	public var content(default, null):Null<InlineContent> = null;
	public var lines(default, null) = 0;
	public var fragments(default, null) = 0;
	// the lines' total height, the widest line's left + width
	public var height(default, null) = 0.0;
	public var width(default, null) = 0.0;
	// where this layout began (its first line's index in the content: from's), and where it ended
	public var from(default, null):Null<InlineBreak> = null;
	public var firstLine(default, null) = 0;
	var nextPiece = 0;
	var nextUnit = 0;
	var nextForced = false;
	public final glyphs = new InlineGlyphs();

	var lTop = new Vector<Float>(8);
	var lHeight = new Vector<Float>(8);
	var lBaseline = new Vector<Float>(8);
	var lWidth = new Vector<Float>(8);
	var lLeft = new Vector<Float>(8);
	var lAvail = new Vector<Float>(8);
	var lStart = new Vector<Int>(8);
	var lEnd = new Vector<Int>(8);
	var lFirst = new Vector<Int>(8);
	var lLast = new Vector<Int>(8);
	var lFlags = new Vector<Int>(8);
	var lPiece = new Vector<Int>(8);

	var fKind = new Vector<Int>(32);
	var fX = new Vector<Float>(32);
	var fY = new Vector<Float>(32);
	var fWidth = new Vector<Float>(32);
	var fHeight = new Vector<Float>(32);
	var fAscent = new Vector<Float>(32);
	var fDescent = new Vector<Float>(32);
	var fLevel = new Vector<Int>(32);
	var fItem = new Vector<Int>(32);
	var fStart = new Vector<Int>(32);
	var fEnd = new Vector<Int>(32);
	var fRun = new Vector<Int>(32);

	// (what the last layout was: the cache's key)
	var laidWidth = Math.NaN;
	var laidCallback:Null<(y:Float, height:Float) -> {offset:Float, width:Float}> = null;
	var laidGeneration = -1;
	var laidDirection = -2;
	var laidFrom:Null<InlineBreak> = null;

	static final builder = new LineBuilder();

	public function new() {}

	// content laid out under constraints (the content finished); from a
	// break token (a continuation: its first line the token's, its lines'
	// tops from 0, the constraints' lineWidth asked from its own top), else
	// from the start
	public function layout(content:InlineContent, constraints:InlineConstraints, ?from:InlineBreak):InlineLayout {
		if (!content.finished) content.finish();
		content.ensureShaped();
		if (this.content == content && laidWidth == constraints.width && laidCallback == constraints.lineWidth && constraints.lineWidth == null
			&& laidGeneration == content.shaper.generation && laidDirection == constraints.direction && laidFrom == from)
			return this;
		this.content = content;
		laidWidth = constraints.width;
		laidCallback = constraints.lineWidth;
		laidGeneration = content.shaper.generation;
		laidDirection = constraints.direction;
		laidFrom = from;
		this.from = from;
		firstLine = from == null ? 0 : from.line;
		builder.layout(this, content, constraints, from);
		return this;
	}

	// the token of line k's start (to lay the rest out from it: a page's
	// break before line k)
	public function breakAt(k:Int):InlineBreak
		return InlineBreak.at(content, lPiece[k], lStart[k], firstLine + k, k == 0 ? from != null && from.afterForced : lFlags[k - 1] & LineBuilder.FORCED != 0);

	// the token after the last line (null: all of the content laid out, or line-clamp's lines)
	public function endBreak():Null<InlineBreak>
		return nextPiece >= content.pieces ? null : InlineBreak.at(content, nextPiece, nextUnit, firstLine + lines, nextForced);

	// the content's min-content and max-content inline sizes (CSS Sizing 3):
	// its widest piece that cannot break (overflow-wrap: anywhere's
	// clusters), its widest line between forced breaks
	public static function minContent(content:InlineContent):Float {
		if (!content.finished) content.finish();
		content.ensureShaped();
		return builder.intrinsic(content, 0);
	}

	public static function maxContent(content:InlineContent):Float {
		if (!content.finished) content.finish();
		content.ensureShaped();
		return builder.intrinsic(content, Math.POSITIVE_INFINITY);
	}

	// --- hit testing, carets, selection ---

	// the text position nearest (x, y): its unit in the content's text (a
	// caret's place: before that unit) and the item it is in. Over a glyph,
	// the boundary nearer by its half and direction (a ligature's by its
	// characters' equal parts); beside the line's content, its nearer end
	public function hitTest(x:Float, y:Float):{item:Int, offset:Int} {
		var c = content;
		if (c == null || lines == 0) return {item: -1, offset: 0};
		var k = 0;
		while (k < lines - 1 && y >= lTop[k] + lHeight[k])
			k++;
		// (the fragment under x, else the nearest)
		var best = -1, distance = Math.POSITIVE_INFINITY;
		for (f in lFirst[k]...lLast[k]) {
			var kind = fKind[f];
			if (kind != TextRun && kind != Atomic) continue;
			var d = x < fX[f] ? fX[f] - x : x > fX[f] + fWidth[f] ? x - fX[f] - fWidth[f] : 0;
			if (d < distance) {
				best = f;
				distance = d;
			}
		}
		if (best < 0) {
			var u = lStart[k];
			return {item: u < c.text.length ? c.itemAt(u) : c.items - 1, offset: u};
		}
		var rtl = fLevel[best] & 1 == 1, item = fItem[best];
		if (fKind[best] == Atomic) {
			var left = x < fX[best] + fWidth[best] / 2;
			return {item: item, offset: left != rtl ? c.start(item) : c.end(item)};
		}
		var r = fRun[best];
		if (r < 0 || glyphs.runCount(r) == 0) return {item: item, offset: fStart[best]};
		var g0 = glyphs.runStart(r), n = glyphs.runCount(r), rx = x - fX[best];
		for (i in g0...g0 + n) {
			var gx = glyphs.x(i), a = glyphs.advance(i);
			if (rx < gx + a || i == g0 + n - 1) {
				var s = glyphs.cluster(i), e = clusterEnd(best, i);
				var frac = a > 0 ? Math.max(0, Math.min(1, (rx - gx) / a)) : 0;
				if (rtl) frac = 1 - frac;
				// (a ligature: the nearest of its characters' boundaries)
				var parts = e - s;
				var at = parts > 1 && ligature(best, i) ? s + Math.round(frac * parts) : frac < 0.5 ? s : e;
				return {item: c.itemAt(at < c.text.length ? at : c.text.length - 1), offset: at};
			}
		}
		return {item: item, offset: fEnd[best]};
	}

	// the caret before a unit of the content's text: its x, its line's top and
	// height (a right-to-left glyph's leading edge its right)
	public function caret(offset:Int):{x:Float, y:Float, height:Float, line:Int} {
		if (lines == 0) return {x: 0, y: 0, height: 0, line: -1};
		var k = 0;
		while (k < lines - 1 && offset >= lEnd[k] && !(offset == lEnd[k] && lStart[k + 1] > offset))
			k++;
		var x = lLeft[k];
		var rtlLine = false, found = false;
		for (f in lFirst[k]...lLast[k]) {
			var kind = fKind[f], rtl = fLevel[f] & 1 == 1;
			if (kind == TextRun && offset >= fStart[f] && offset < fEnd[f] && fRun[f] >= 0) {
				var r = fRun[f], g0 = glyphs.runStart(r);
				for (i in g0...g0 + glyphs.runCount(r)) {
					var s = glyphs.cluster(i), e = clusterEnd(f, i);
					if (offset >= s && offset < e) {
						var frac = e - s > 1 && ligature(f, i) ? (offset - s) / (e - s) : 0.0;
						var a = glyphs.advance(i), gx = fX[f] + glyphs.x(i);
						return {x: rtl ? gx + a * (1 - frac) : gx + a * frac, y: lTop[k], height: lHeight[k], line: k};
					}
				}
			}
			if (kind == Atomic && offset == fStart[f]) return {x: rtl ? fX[f] + fWidth[f] : fX[f], y: lTop[k], height: lHeight[k], line: k};
			if ((kind == TextRun || kind == Atomic) && offset == fEnd[f] && fEnd[f] > fStart[f]) {
				x = rtl ? fX[f] : fX[f] + fWidth[f];
				found = true;
			}
			if (kind == TextRun && rtl) rtlLine = true;
		}
		if (!found && rtlLine && offset <= lStart[k]) x = lLeft[k] + lWidth[k];
		return {x: x, y: lTop[k], height: lHeight[k], line: k};
	}

	// the rectangles a selection of the content's text from start to end
	// covers: on each line, each run of selected glyphs and atomics in visual
	// order as one (a ligature partly selected by its characters' parts),
	// the line's height
	public function selection(start:Int, end:Int):Array<{x:Float, y:Float, width:Float, height:Float}> {
		var out = [];
		if (end <= start) return out;
		for (k in 0...lines) {
			if (lEnd[k] <= start || lStart[k] >= end) continue;
			// (each selected piece's interval, then those that touch as one)
			var spans:Array<Float> = [];
			for (f in lFirst[k]...lLast[k]) {
				var kind = fKind[f], rtl = fLevel[f] & 1 == 1;
				if (kind == Atomic) {
					if (fStart[f] >= start && fEnd[f] <= end) {
						spans.push(fX[f]);
						spans.push(fX[f] + fWidth[f]);
					}
					continue;
				}
				if (kind != TextRun || fRun[f] < 0 || fEnd[f] <= start || fStart[f] >= end) continue;
				var r = fRun[f], g0 = glyphs.runStart(r);
				for (i in g0...g0 + glyphs.runCount(r)) {
					var s = glyphs.cluster(i), e = clusterEnd(f, i);
					if (e <= start || s >= end) continue;
					var gx = fX[f] + glyphs.x(i), a = glyphs.advance(i);
					var f0 = 0.0, f1 = 1.0;
					if ((s < start || e > end) && e - s > 1) {
						f0 = (Math.max(start, s) - s) / (e - s);
						f1 = (Math.min(end, e) - s) / (e - s);
					}
					spans.push(rtl ? gx + a * (1 - f1) : gx + a * f0);
					spans.push(rtl ? gx + a * (1 - f0) : gx + a * f1);
				}
			}
			var order = [for (i in 0...spans.length >> 1) i];
			order.sort((a, b) -> spans[2 * a] < spans[2 * b] ? -1 : spans[2 * a] > spans[2 * b] ? 1 : 0);
			var open = false, x0 = 0.0, x1 = 0.0;
			for (i in order) {
				var a = spans[2 * i], b = spans[2 * i + 1];
				if (open && a <= x1 + 1e-6) {
					if (b > x1) x1 = b;
				} else {
					if (open) out.push({x: x0, y: lTop[k], width: x1 - x0, height: lHeight[k]});
					x0 = a;
					x1 = b;
					open = true;
				}
			}
			if (open) out.push({x: x0, y: lTop[k], width: x1 - x0, height: lHeight[k]});
		}
		return out;
	}

	// (where glyph i's cluster ends: the next cluster above it in its fragment's run, or the fragment's end)
	function clusterEnd(f:Int, i:Int):Int {
		var r = fRun[f], c = glyphs.cluster(i), e = fEnd[f];
		for (j in glyphs.runStart(r)...glyphs.runStart(r) + glyphs.runCount(r)) {
			var d = glyphs.cluster(j);
			if (d > c && d < e) e = d;
		}
		return e;
	}

	// (whether glyph i is one glyph for several characters: no other glyph in its cluster)
	function ligature(f:Int, i:Int):Bool {
		var r = fRun[f], c = glyphs.cluster(i);
		for (j in glyphs.runStart(r)...glyphs.runStart(r) + glyphs.runCount(r))
			if (j != i && glyphs.cluster(j) == c) return false;
		var e = clusterEnd(f, i);
		// (one grapheme: a base and its marks; several: a ligature)
		for (u in c + 1...e)
			if (content.breakAt(u) & LineBreaks.CLUSTER != 0) return true;
		return false;
	}

	// --- lines ---

	public inline function lineTop(k:Int):Float
		return lTop[k];

	public inline function lineHeight(k:Int):Float
		return lHeight[k];

	// its baseline below its top
	public inline function lineBaseline(k:Int):Float
		return lBaseline[k];

	// the inline size its content uses (its indent in, hanging spaces out)
	public inline function lineWidth(k:Int):Float
		return lWidth[k];

	// where its content starts (the line's own offset and its alignment)
	public inline function lineLeft(k:Int):Float
		return lLeft[k];

	// the inline size it had (the constraints' width, or the callback's)
	public inline function lineAvailable(k:Int):Float
		return lAvail[k];

	// its text: start to end (units of the content's text)
	public inline function lineStart(k:Int):Int
		return lStart[k];

	public inline function lineEnd(k:Int):Int
		return lEnd[k];

	// its fragments: lineFragmentStart to lineFragmentEnd
	public inline function lineFragmentStart(k:Int):Int
		return lFirst[k];

	public inline function lineFragmentEnd(k:Int):Int
		return lLast[k];

	// whether a forced break ends it
	public inline function lineForced(k:Int):Bool
		return lFlags[k] & LineBuilder.FORCED != 0;

	// --- fragments ---

	public inline function kind(f:Int):InlineFragment
		return cast fKind[f];

	public inline function x(f:Int):Float
		return fX[f];

	public inline function y(f:Int):Float
		return fY[f];

	public inline function fragmentWidth(f:Int):Float
		return fWidth[f];

	public inline function fragmentHeight(f:Int):Float
		return fHeight[f];

	// above and below its baseline (a text run's and a box's: their font's; an atomic's: its margin box's)
	public inline function ascent(f:Int):Float
		return fAscent[f];

	public inline function descent(f:Int):Float
		return fDescent[f];

	public inline function level(f:Int):Int
		return fLevel[f];

	// its item in the content (a box's: its Open)
	public inline function item(f:Int):Int
		return fItem[f];

	// its text, units of the content's text (none: start == end)
	public inline function textStart(f:Int):Int
		return fStart[f];

	public inline function textEnd(f:Int):Int
		return fEnd[f];

	// its glyph run (glyphs; -1: none)
	public inline function glyphRun(f:Int):Int
		return fRun[f];
}

// What a fragment of an InlineLayout is
enum abstract InlineFragment(Int) to Int {
	// text of one item on one line, its glyphs a run
	var TextRun;
	// an inline box's start and end edges (margin, border, padding) where it starts and ends
	var BoxStart;
	var BoxEnd;
	// an inline box's part on a line: its border box there (background, borders)
	var BoxSpan;
	// an atomic inline's border box
	var Atomic;
	// a hyphen shown where a line breaks in a word, a text-overflow's or line-clamp's ellipsis
	var Hyphen;
	var Ellipsis;
	// a float's and an absolutely positioned box's static position (no size)
	var Float;
	var Abspos;
}
