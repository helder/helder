package helder.ui.draw;

import helder.image.Image;
import helder.ui.*;
import helder.ui.Paint;
import helder.ui.Stroke;

// A path's image as a renderer drew it (Renderer.path, SoftCanvas.path),
// and what it was drawn with: kept while it is drawn the same way.
class PathImage {
	public final img:Image;
	public final x:Float;
	public final y:Float;
	public var frame = 0;

	final scale:Float;
	final commands:Int;
	final evenOdd:Bool;
	final fill:Null<Paint>;
	final stroke:Null<Stroke>;
	// (the stroke's fields when drawn: a stroke object may be changed and drawn again)
	final width:Float;
	final paint:Null<Paint>;
	final cap:Null<LineCap>;
	final join:Null<LineJoin>;
	final miterLimit:Null<Float>;
	final dashes:Null<Array<Float>>;
	final dashOffset:Null<Float>;

	public function new(scale:Float, p:Path, fill:Null<Paint>, stroke:Null<Stroke>, img:Image, x:Float, y:Float) {
		this.scale = scale;
		commands = p.commands.length;
		evenOdd = p.evenOdd;
		this.fill = fill;
		this.stroke = stroke;
		width = stroke == null ? 0 : stroke.width;
		paint = stroke?.paint;
		cap = stroke?.cap;
		join = stroke?.join;
		miterLimit = stroke?.miterLimit;
		dashes = stroke?.dashes == null ? null : stroke.dashes.copy();
		dashOffset = stroke?.dashOffset;
		this.img = img;
		this.x = x;
		this.y = y;
	}

	public function same(s:Float, p:Path, f:Null<Paint>, st:Null<Stroke>):Bool {
		if (s != scale || p.commands.length != commands || p.evenOdd != evenOdd || !samePaint(f, fill)) return false;
		if (st == null || stroke == null) return st == stroke;
		if (st.width != width || !samePaint(st.paint, paint) || st.cap != cap || st.join != join || st.miterLimit != miterLimit
			|| st.dashOffset != dashOffset) return false;
		var d = st.dashes;
		if (d == null || dashes == null) return d == dashes;
		if (d.length != dashes.length) return false;
		for (k in 0...d.length)
			if (d[k] != dashes[k]) return false;
		return true;
	}

	static function samePaint(a:Null<Paint>, b:Null<Paint>):Bool {
		if (a == null || b == null) return a == b;
		return switch [(a : PaintValue), (b : PaintValue)] {
			case [Solid(x), Solid(y)]: x == y;
			// (another gradient object: the same if it reads the same)
			case [Gradient(x), Gradient(y)]: x == y || Std.string(x) == Std.string(y);
			case _: false;
		}
	}
}
