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

	static final builder = new LineBuilder();

	public function new() {}

	// content laid out under constraints (the content finished)
	public function layout(content:InlineContent, constraints:InlineConstraints):InlineLayout {
		if (!content.finished) content.finish();
		content.ensureShaped();
		if (this.content == content && laidWidth == constraints.width && laidCallback == constraints.lineWidth && constraints.lineWidth == null
			&& laidGeneration == content.shaper.generation && laidDirection == constraints.direction)
			return this;
		this.content = content;
		laidWidth = constraints.width;
		laidCallback = constraints.lineWidth;
		laidGeneration = content.shaper.generation;
		laidDirection = constraints.direction;
		builder.layout(this, content, constraints);
		return this;
	}

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
