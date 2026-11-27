package helder.ui.box;

// A Painter that draws box shadows itself (UiPainter: helder.ui's Canvas,
// whose shadows the GPU blurs), as a GlyphText painter keeps text: Borders
// offers it each shadow, blurred as CSS blurs it (its standard deviation
// half the blur), and draws on the CPU the ones it doesn't take (false).
// Radii: each corner's (top left, top right, bottom right, bottom left; x
// and y each), null for square corners.
interface ShadowPainter {
	// an outer shadow: the shape (x, y, w, h: the box moved by dx, dy and
	// grown by spread), not drawn under the box that casts it
	function outerShadow(x:Float, y:Float, w:Float, h:Float, radii:Null<Array<Float>>, color:Int, blur:Float, dx:Float, dy:Float, spread:Float):Bool;

	// an inset shadow inside a padding box (x, y, w, h): darkened from
	// outside it moved by dx, dy and shrunk by spread
	function innerShadow(x:Float, y:Float, w:Float, h:Float, radii:Null<Array<Float>>, color:Int, blur:Float, dx:Float, dy:Float, spread:Float):Bool;
}
