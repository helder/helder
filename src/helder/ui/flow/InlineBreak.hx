package helder.ui.flow;

// Where a laid out InlineContent goes on (fragmentation's break token): a
// line's start, without geometry, so that the rest can be laid out at another
// width and beside other floats (InlineLayout.layout's from). Its piece and
// the unit of it the line starts at (InlineContent's), the line's index in
// the whole content (orphans and widows; text-indent's first line is 0),
// whether a forced break ends the line before it (text-indent: each-line),
// and the inline boxes still open there, outermost first (their Open items:
// their start edges not drawn again, as box-decoration-break: slice).
class InlineBreak {
	public final piece:Int;
	public final unit:Int;
	public final line:Int;
	public final afterForced:Bool;
	public final openBoxes:Array<Int>;

	public function new(piece:Int, unit:Int, line:Int, afterForced:Bool, openBoxes:Array<Int>) {
		this.piece = piece;
		this.unit = unit;
		this.line = line;
		this.afterForced = afterForced;
		this.openBoxes = openBoxes;
	}

	// the start of a content (line 0)
	public static function start(c:InlineContent):InlineBreak
		return new InlineBreak(0, c.pieces > 0 ? c.pieceStart(0) : 0, 0, false, []);

	// the token of a line starting at piece p (its unit u): the boxes open there from the content
	public static function at(c:InlineContent, p:Int, u:Int, line:Int, afterForced:Bool):InlineBreak {
		var open:Array<Int> = [];
		if (p < c.pieces) {
			var i = c.pieceItem(p);
			var b = c.kind(i) == Open ? c.parent(i) : c.box(i);
			while (b >= 0) {
				open.unshift(b);
				b = c.parent(b);
			}
		}
		return new InlineBreak(p, u, line, afterForced, open);
	}
}
