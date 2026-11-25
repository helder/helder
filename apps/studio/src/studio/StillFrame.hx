package studio;

import helder.ui.Canvas;
import helder.ui.Clock;
import helder.ui.Node;
import helder.ui.draw.DisplayList;

// A screen's still from the frames file (Stills): its list replayed in
// the node's box, scaled from the story's points to it, vector at any zoom.
// Its loop (a hovered loop story's, from the file) played over it at the
// fps it was recorded at, from its first frame, round and round; stopped,
// the still again.
class StillFrame extends Node {
	final still:DisplayList;
	final w:Float;
	final h:Float;
	var list:DisplayList;
	var playing = 0;
	// (a loop's frames painted, their replays' time: its cost a frame)
	var painted = 0;
	var paintMs = 0.0;

	public function new(list:DisplayList, width:Float, height:Float) {
		super();
		still = this.list = list;
		w = width;
		h = height;
	}

	// a loop's frames, played; first: told at its first frame, done: when stopped (frames painted, ms each)
	public function play(fps:Int, lists:Array<DisplayList>, ?first:Void->Void, ?done:(frames:Int, ms:Float) -> Void) {
		if (lists.length == 0 || fps <= 0) return;
		var id = ++playing, t0 = -1.0;
		painted = 0;
		paintMs = 0;
		stopped = done;
		Clock.addFor(this, t -> {
			if (playing != id) return false;
			if (t0 < 0) t0 = t;
			var next = lists[Std.int((t - t0) * fps) % lists.length];
			if (next != list) {
				list = next;
				paintChanged();
			}
			if (first != null) {
				first();
				first = null;
			}
			return true;
		});
	}

	var stopped:Null<(frames:Int, ms:Float) -> Void> = null;

	public function stop() {
		if (list == still && stopped == null) return;
		playing++;
		list = still;
		paintChanged();
		var done = stopped;
		stopped = null;
		if (done != null && painted > 0) done(painted, paintMs / painted);
	}

	override public function hasContent():Bool
		return true;

	// (its calls the same until its loop's frame changes: recorded then, as an image's)
	@:allow(helder.ui) override function paintsLive():Bool
		return false;

	override public function paintContent(c:Canvas, x:Float, y:Float, width:Float, height:Float) {
		if (w <= 0 || h <= 0) return;
		var t0 = haxe.Timer.stamp();
		c.pushClip(x, y, width, height, 0);
		c.pushTransform(width / w, 0, 0, height / h, x, y);
		list.replay(c);
		c.popTransform();
		c.popClip();
		if (list != still) {
			painted++;
			paintMs += (haxe.Timer.stamp() - t0) * 1000;
		}
	}
}
