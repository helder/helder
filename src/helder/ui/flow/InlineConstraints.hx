package helder.ui.flow;

// What an InlineContent is laid out in: the available inline size, and
// where floats are, the line's offset and width at a height y for a line
// of a height (null: the whole width at every line); the containing
// block's direction (-1: the content's root's).
class InlineConstraints {
	public var width:Float;
	public var lineWidth:Null<(y:Float, height:Float) -> {offset:Float, width:Float}>;
	public var direction:Int;

	public function new(width:Float, ?lineWidth:(y:Float, height:Float) -> {offset:Float, width:Float}, direction = -1) {
		this.width = width;
		this.lineWidth = lineWidth;
		this.direction = direction;
	}
}
