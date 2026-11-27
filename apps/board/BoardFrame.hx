import helder.scene.view.SceneData;
import helder.ui.Canvas;
import helder.ui.Clock;
import helder.ui.Node;
import helder.ui.draw.DisplayList;
import helder.ui.draw.PassCanvas;
import helder.ui.draw.PassData;

// A scene's still from a frames file, its list replayed in the node's box
// (scaled from the scene's points: vectors at any size); what a markup
// <Scene> in it draws built again from its data and drawn in its place
// (SceneData, as the studio's StillFrame draws it: a 3D story's still is
// its scene's data, a few kilobytes, not a picture). Its loop, when
// played, at the fps it was recorded at, from its first frame, round and
// round, its scenes' changed props set at each; stopped, the still again.
// dispose: its scenes' worlds let go (16 a process).
class BoardFrame extends Node {
	final still:DisplayList;
	final stillPasses:Array<PassData>;
	final w:Float;
	final h:Float;
	var list:DisplayList;
	var passes:Array<PassData>;
	final scenes:Array<SceneReplay> = [];
	var playing = 0;

	public function new(still:DisplayList, passes:Array<PassData>, width:Float, height:Float) {
		super();
		this.still = list = still;
		stillPasses = this.passes = passes;
		w = width;
		h = height;
	}

	public function play(fps:Int, lists:Array<DisplayList>, framePasses:Array<Array<PassData>>) {
		if (lists.length == 0 || fps <= 0) return;
		var id = ++playing, t0 = -1.0;
		Clock.addFor(this, t -> {
			if (playing != id) return false;
			if (t0 < 0) t0 = t;
			var i = Std.int((t - t0) * fps) % lists.length;
			if (lists[i] != list) {
				list = lists[i];
				passes = framePasses[i] ?? [];
				paintChanged();
			}
			return true;
		});
	}

	public function stop() {
		playing++;
		if (list == still) return;
		list = still;
		passes = stillPasses;
		paintChanged();
	}

	public function dispose() {
		playing++;
		for (s in scenes)
			s.dispose();
		scenes.resize(0);
	}

	override public function hasContent():Bool
		return true;

	@:allow(helder.ui) override function paintsLive():Bool
		return false;

	override public function paintContent(c:Canvas, x:Float, y:Float, width:Float, height:Float) {
		if (w <= 0 || h <= 0) return;
		c.pushClip(x, y, width, height, 0);
		c.pushTransform(width / w, 0, 0, height / h, x, y);
		if (passes.length > 0) {
			// (each scene of this frame's data: built once, its props set as they change)
			for (k => d in passes)
				if (k >= scenes.length) scenes.push(SceneData.build(d)) else scenes[k].apply(d);
			list.replay(new PassCanvas(c, (k, px, py, pw, ph) -> if (k < scenes.length) scenes[k].draw(c, px, py, pw, ph)));
		} else
			list.replay(c);
		c.popTransform();
		c.popClip();
	}
}
