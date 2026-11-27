package helder.text;

// A colour glyph as COLR describes it (Colr: version 0's layers and
// version 1's paint graph), in font units, y up: what a renderer draws
// (helder.canvas.ColorGlyphs). Colours are palette entries (CPAL's: the
// palette a renderer is given) with an alpha; FOREGROUND is the text's.
// Every transform COLR has (translate, scale, rotate, skew, around a centre
// or not) is a matrix here, and a reference to another glyph's paint
// (PaintColrGlyph) is that paint.
enum ColorPaint {
	// each drawn over the ones before
	Layers(paints:Array<ColorPaint>);
	Solid(entry:Int, alpha:Float);
	// along p0 to p1, its stripes parallel to p0 to p2 (COLR's three points)
	Linear(line:ColorLine, x0:Float, y0:Float, x1:Float, y1:Float, x2:Float, y2:Float);
	// between two circles
	Radial(line:ColorLine, x0:Float, y0:Float, r0:Float, x1:Float, y1:Float, r1:Float);
	// around a centre, from start to end (degrees, counter-clockwise)
	Sweep(line:ColorLine, x:Float, y:Float, start:Float, end:Float);
	// the paint inside the glyph's outline
	Glyph(glyph:Int, paint:ColorPaint);
	// x' = xx x + xy y + dx, y' = yx x + yy y + dy
	Transform(xx:Float, yx:Float, xy:Float, yy:Float, dx:Float, dy:Float, paint:ColorPaint);
	// the paint inside a box (xMin, yMin, xMax, yMax): a glyph's ClipBox, PaintColrGlyph's
	Clip(x0:Float, y0:Float, x1:Float, y1:Float, paint:ColorPaint);
	// source over backdrop by a COLR composite mode (0 clear, 1 src, 2 dest,
	// 3 src-over... 12 plus, 13 screen... 23 multiply, 24-27 the HSL ones)
	Composite(mode:Int, source:ColorPaint, backdrop:ColorPaint);
}

// a gradient's stops (offsets 0 to 1, a palette entry and an alpha each) and
// what lies past them: ColorPaint.PAD, REPEAT or REFLECT
typedef ColorLine = {extend:Int, stops:Array<{offset:Float, entry:Int, alpha:Float}>}

class ColorPaints {
	// (the palette entry that is the text's colour)
	public static inline var FOREGROUND = 0xFFFF;
	public static inline var PAD = 0;
	public static inline var REPEAT = 1;
	public static inline var REFLECT = 2;
}
