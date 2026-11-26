import helder.ui.Canvas;
import helder.ui.Clock;
import helder.ui.Node;
import helder.ui.draw.DisplayList;

// A scene's still from a frames file, its list replayed in the node's box
// (scaled from the scene's points: vectors at any size); its loop, when
// played, at the fps it was recorded at, from its first frame, round and
// round; stopped, the still again. (The studio's StillFrame, without the
// scenes it builds again from their data: a 3D scene's still or loop is
// its pictures here.)
class BoardFrame extends Node {
	final still:DisplayList;
	final w:Float;
	final h:Float;
	var list:DisplayList;
	var playing = 0;

	public function new(still:DisplayList, width:Float, height:Float) {
		super();
		this.still = list = still;
		w = width;
		h = height;
	}

	public function play(fps:Int, lists:Array<DisplayList>) {
		if (lists.length == 0 || fps <= 0) return;
		var id = ++playing, t0 = -1.0;
		Clock.addFor(this, t -> {
			if (playing != id) return false;
			if (t0 < 0) t0 = t;
			var next = lists[Std.int((t - t0) * fps) % lists.length];
			if (next != list) {
				list = next;
				paintChanged();
			}
			return true;
		});
	}

	public function stop() {
		playing++;
		if (list == still) return;
		list = still;
		paintChanged();
	}

	override public function hasContent():Bool
		return true;

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
