package helder.pdf;

// A glyph shown: its characters in its run's text (start == end: none, a
// code that maps to no Unicode), and its box on the page as shown (points
// from the top left, the page turned: Pdf.pageMatrix at 1) as a corner on
// the descent, the advance's side (ax, ay) and the side up to the ascent
// (ux, uy): turned, slanted or vertical text's too.
class PdfGlyph {
	public final start:Int;
	public final end:Int;
	public final x:Float;
	public final y:Float;
	public final ax:Float;
	public final ay:Float;
	public final ux:Float;
	public final uy:Float;

	public function new(start:Int, end:Int, x:Float, y:Float, ax:Float, ay:Float, ux:Float, uy:Float) {
		this.start = start;
		this.end = end;
		this.x = x;
		this.y = y;
		this.ax = ax;
		this.ay = ay;
		this.ux = ux;
		this.uy = uy;
	}
}
