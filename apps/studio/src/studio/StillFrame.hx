package studio;

#if !(hxmc.target == "wasm32-wasi")
import helder.scene.view.SceneData;
#end
import helder.ui.Canvas;
import helder.ui.Clock;
import helder.ui.Node;
import helder.ui.draw.DisplayList;
import helder.ui.draw.PassCanvas;
import helder.ui.draw.PassData;

// A screen's still from the frames file (Stills): its list replayed in
// the node's box, scaled from the story's points to it, vector at any zoom;
// what a markup <Scene> in it draws built again from its data and drawn in
// its place at sharp pixels a point (SceneData; the canvas' zoom at rest,
// Sharp's). Its loop (a hovered loop
// story's, from the file) played over it at the fps it was recorded at,
// from its first frame, round and round, its scenes' changed props set at
// each; stopped, the still again.
class StillFrame extends Node {
	final still:DisplayList;
	final stillPasses:Array<PassData>;
	final w:Float;
	final h:Float;
	var list:DisplayList;
	var passes:Array<PassData>;
	#if !(hxmc.target == "wasm32-wasi")
	// (the scenes of its passes, built when first drawn; the browser's studio
	// has no frames file: helder.scene not linked for it)
	final scenes:Array<SceneReplay> = [];
	#end
	var playing = 0;
	// (a loop's frames painted, their replays' time: its cost a frame)
	var painted = 0;
	var paintMs = 0.0;

	// pixels a point of its scenes (the studio's sharpness: its zoom at rest)
	public var sharp(default, set) = 1.0;

	function set_sharp(v:Float):Float {
		if (v != sharp) paintChanged();
		return sharp = v;
	}

	public function new(list:DisplayList, passes:Array<PassData>, width:Float, height:Float) {
		super();
		still = this.list = list;
		stillPasses = this.passes = passes;
		w = width;
		h = height;
	}

	// a loop's frames, played; first: told at its first frame, done: when stopped (frames painted, ms each)
	public function play(fps:Int, lists:Array<DisplayList>, framePasses:Array<Array<PassData>>, ?first:Void->Void, ?done:(frames:Int, ms:Float) -> Void) {
		if (lists.length == 0 || fps <= 0) return;
		var id = ++playing, t0 = -1.0;
		painted = 0;
		paintMs = 0;
		stopped = done;
		Clock.addFor(this, t -> {
			if (playing != id) return false;
			if (t0 < 0) t0 = t;
			var i = Std.int((t - t0) * fps) % lists.length;
			if (lists[i] != list) {
				list = lists[i];
				passes = framePasses[i] ?? [];
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

	// one of its loop's frames shown (the selection bar's scrubber), its loop stopped
	public function at(l:DisplayList, p:Array<PassData>) {
		playing++;
		if (l == list) return;
		list = l;
		passes = p;
		paintChanged();
	}

	// let go (its owner's cleanup): its loop stopped, its scenes' boxes and
	// worlds (one of 16 a process each: a board of scenes' stills)
	public function dispose() {
		playing++;
		stopped = null;
		#if !(hxmc.target == "wasm32-wasi")
		for (s in scenes)
			s.dispose();
		scenes.resize(0);
		#end
	}

	public function stop() {
		if (list == still && stopped == null) return;
		playing++;
		list = still;
		passes = stillPasses;
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
		#if !(hxmc.target == "wasm32-wasi")
		if (passes.length > 0) {
			// (each scene of this frame's data: built once, its props set as they change)
			for (k => d in passes)
				if (k >= scenes.length) scenes.push(SceneData.build(d)) else scenes[k].apply(d);
			var g = helder.ui.draw.GpuHost.of(c), m = g == null ? 1.0 : sharp / g.scale;
			list.replay(new PassCanvas(c, (k, px, py, pw, ph) -> if (k < scenes.length) scene(c, scenes[k], m, px, py, pw, ph)));
		} else
		#end
		list.replay(c);
		c.popTransform();
		c.popClip();
		if (list != still) {
			painted++;
			paintMs += (haxe.Timer.stamp() - t0) * 1000;
		}
	}

	#if !(hxmc.target == "wasm32-wasi")
	// (a scene drawn at m times its box's pixels, then scaled into its box: its target the size the canvas shows it at)
	static function scene(c:Canvas, s:SceneReplay, m:Float, x:Float, y:Float, w:Float, h:Float) {
		if (m == 1) return s.draw(c, x, y, w, h);
		c.pushTransform(1 / m, 0, 0, 1 / m, x, y);
		s.draw(c, 0, 0, w * m, h * m);
		c.popTransform();
	}
	#end
}
