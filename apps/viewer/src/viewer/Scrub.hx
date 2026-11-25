package viewer;

import helder.ui.Event;
import helder.ui.Node;

// MediaView's scrub bar: a press seeks to the keyframe under the pointer,
// a drag on to those it passes, the release exactly there. Its fill is
// the time shown (show), the pointer's while held: a keyframe seek's
// time is its keyframe's, seconds behind the pointer where they are far
// apart. hover: the pointer over it, as a fraction of the duration.
class Scrub {
	public final node:Node;
	// the media's length in seconds (0: nothing to seek)
	public var duration = 0.0;
	public var hover:Null<Float->Void>;
	// the time shown: the player's, the pointer's while held
	public var time(default, null) = 0.0;

	final done:Node;
	final seek:(t:Float, exact:Bool) -> Void;
	var held = false;

	public function new(seek:(t:Float, exact:Bool) -> Void) {
		this.seek = seek;
		var t = helder.ui.controls.Look.ref;
		node = new Node();
		node.style.set({height: 14, justify: Center});
		var track = new Node();
		track.style.set({height: 4, radius: 2, background: t.fill});
		done = new Node();
		done.style.set({height: 4, radius: 2, background: t.fg, width: 0});
		track.append(done);
		node.append(track);
		node.onPointerDown = e -> {
			node.capture();
			held = true;
			at(e, false);
		};
		node.onPointerMove = e -> {
			if (held) at(e, false);
			if (hover != null) hover(ratio(e));
		};
		node.onPointerUp = e -> {
			if (!held) return;
			held = false;
			at(e, true);
		};
		// (the press taken from it, no release: exact where it was)
		node.onLostPointerCapture = _ -> {
			if (!held) return;
			held = false;
			seek(time, true);
		};
	}

	// the time the player is at (seconds)
	public function show(t:Float) {
		if (!held) time = t;
		fill();
	}

	function at(e:Event, exact:Bool) {
		if (duration <= 0) return;
		seek(time = ratio(e) * duration, exact);
		fill();
	}

	function ratio(e:Event):Float
		return node.width <= 0 ? 0 : Math.max(0, Math.min(1, e.localX / node.width));

	function fill()
		done.style.width = duration > 0 ? node.width * Math.min(1, time / duration) : 0;
}
