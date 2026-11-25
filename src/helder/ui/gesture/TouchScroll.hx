package helder.ui.gesture;

// A touch's drag scrolling what is under where it started (Ui's own, the
// last in the first finger's arena: the gestures of the nodes inside win
// first): once past the slop it
// sends the drag's motion as Ui.wheel at where it started (the content
// follows the finger, a Wheel event first, the nearest scroller that can
// move that way), and the press is cancelled (PointerCancel: no click); let
// go moving (its last move within 100 ms) it glides on at its speed,
// slowing 5% a frame (60 a second), until under half a point a frame. A
// new touch stops a glide. Times in ms here; the glide's physics
// helder.os.Glide's.
@:allow(helder.ui.Ui)
class TouchScroll extends Gesture {
	final ui:ScrollHost;
	var startX = 0.0;
	var startY = 0.0;
	// (the scroll's speed and its glide, points: helder's, or the platform's physics, UiWindow's)
	var g = new helder.os.Glide();

	// (the program's, its pointer's scroll the compositor's: helder.ui.ScrollMirror's own
	// TouchScroll moves it; asking: the compositor waits for this one's answer, the gesture's id)
	var mirrored = false;
	var asking = 0;

	function new(ui:ScrollHost) {
		super();
		this.ui = ui;
	}

	override function owner():Null<Ui>
		return Std.isOfType(ui, Ui) ? cast ui : null;

	public var gliding(get, never):Bool;

	inline function get_gliding():Bool
		return g.gliding;

	override function added() {
		g.start(time * 1000);
		startX = fx;
		startY = fy;
	}

	override function moved() {
		if (!active) {
			if (pointers > 1 || travel() <= slop || !accept()) return;
			state = Began;
		} else state = Changed;
		// (the content follows: the scroll the other way)
		var ddx = -pendX, ddy = -pendY;
		pendX = pendY = 0;
		g.move(ddx, ddy, time * 1000);
		// (the compositor's to scroll: let through, it scrolls from the start)
		if (asking != 0) {
			@:privateAccess (cast ui : Ui).answer(asking, true);
			asking = 0;
			mirrored = true;
		}
		if (mirrored) return;
		// (Android's: past an end it stretches)
		if (ui.stretch) {
			@:privateAccess ui.stretcher.drag(startX, startY, ddx, ddy);
			flush();
		} else {
			@:privateAccess ui.wheelNow(startX, startY, ddx, ddy, false, -1, 0, 0, @:privateAccess ui.clock());
			flush();
		}
	}

	override function lifted(cancelled:Bool) {
		// (never let through: the program's, the compositor drops it)
		if (asking != 0) {
			@:privateAccess (cast ui : Ui).answer(asking, false);
			asking = 0;
		}
		if (mirrored) {
			mirrored = false;
			if (active) state = cancelled ? Cancelled : Ended;
			return;
		}
		if (!active) return;
		state = cancelled ? Cancelled : Ended;
		// (a stretch held: it springs back at the drag's speed, no fling)
		if (ui.stretch && @:privateAccess ui.stretcher.held()) {
			// (Android's fling only Android's: UiWindow.native)
			var s = @:privateAccess ui.stretcher,
				v = #if (!helder.os || helder.os == "android") Std.isOfType(g, helder.os.android.Fling) ? (cast g : helder.os.android.Fling).velocity(time * 1000) : #end {x: 0.0, y: 0.0};
			@:privateAccess s.release(cancelled ? 0 : @:privateAccess s.alongX ? v.x : v.y);
			return;
		}
		// (its frames: Ui.update steps it)
		if (!cancelled && g.release(time * 1000)) ui.requestFrame();
	}

	override function lost() {
		// (another recogniser won the touch: the program's)
		if (asking != 0) {
			@:privateAccess (cast ui : Ui).answer(asking, false);
			asking = 0;
		}
		if (active && pointers == 0) state = Cancelled;
	}

	// the glide's scroll up to now (ms): whether it still glides
	function glide(now:Float):Bool {
		if (!g.step(now)) return gliding;
		// (Android's: a fling into an end stops there, its speed a stretch's)
		#if (!helder.os || helder.os == "android")
		if (ui.stretch && Std.isOfType(g, helder.os.android.Fling)) {
			var f:helder.os.android.Fling = cast g;
			if (!@:privateAccess ui.stretcher.glide(startX, startY, g.dx, g.dy, f.speedX, f.speedY)) g.stop();
			flush();
		} else
		#end
		{
			@:privateAccess ui.wheelNow(startX, startY, g.dx, g.dy, false, -1, 0, 0, @:privateAccess ui.clock());
			flush();
		}
		return gliding;
	}

	// (what the program's graph was written lands: a Ui's, not the compositor's)
	inline function flush()
		if (Std.isOfType(ui, Ui)) helder.view.graph.Graph.flush();

	function stop()
		g.stop();
}
