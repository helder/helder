package studio;

import helder.ui.Canvas;
import helder.ui.Node;
import helder.ui.draw.DisplayList;

// A screen's still from the frames file (Stills): its list replayed in
// the node's box, scaled from the story's points to it, vector at any zoom
class StillFrame extends Node {
	final list:DisplayList;
	final w:Float;
	final h:Float;

	public function new(list:DisplayList, width:Float, height:Float) {
		super();
		this.list = list;
		w = width;
		h = height;
	}

	override public function hasContent():Bool
		return true;

	// (its calls the same each frame: recorded once, as an image's)
	@:allow(helder.ui) override function paintsLive():Bool
		return false;

	override public function paintContent(c:Canvas, x:Float, y:Float, width:Float, height:Float) {
		if (w <= 0 || h <= 0) return;
		c.pushClip(x, y, width, height, 0);
		c.pushTransform(width / w, 0, 0, height / h, x, y);
		list.replay(c);
		c.popTransform();
		c.popClip();
	}
}
