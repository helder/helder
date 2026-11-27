package helder.ui.flow;

// What an InlineContent is laid out in: the available inline size, and
// where floats are, the line's offset and width at a height y for a line
// of a height (null: the whole width at every line); the containing
// block's direction (-1: the content's root's). Where floats shorten a
// line so that its first piece does not fit, the line moves down (CSS 2.1
// §9.5): to floatEdge(y), the next y below y where the floats beside the
// lines change (infinity: they do not), or without it a pixel at a time,
// until it fits or the floats end.
class InlineConstraints {
	public var width:Float;
	public var lineWidth:Null<(y:Float, height:Float) -> {offset:Float, width:Float}>;
	public var floatEdge:Null<(y:Float) -> Float>;
	public var direction:Int;

	public function new(width:Float, ?lineWidth:(y:Float, height:Float) -> {offset:Float, width:Float}, direction = -1, ?floatEdge:(y:Float) -> Float) {
		this.width = width;
		this.lineWidth = lineWidth;
		this.direction = direction;
		this.floatEdge = floatEdge;
	}
}
