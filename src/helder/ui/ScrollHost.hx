package helder.ui;

import helder.os.Mods;

// What the scroll physics move the scrollers for (Scrolling, Trackpad,
// Stretch, ScrollGlide): a Ui on its tree, and the compositor on its copy
// of the scrollers (helder.ui.draw.ScrollMirror), so that both scroll by
// the same code and an offset the compositor gives the program is the one
// the program would have reached itself.
@:allow(helder.ui)
@:access(helder.ui.Scrolling)
class ScrollHost {
	// a trackpad's scrolls as macOS's own views take them (Trackpad: one
	// scroller a gesture, stretching past its ends and springing back, the
	// system's momentum replayed at the frames' times): UiWindow's on macOS
	// (false: each scroll as a wheel's)
	public var elastic = false;
	// a touchpad's scrolls as GTK's kinetic scrolling takes them (Trackpad: one
	// scroller a gesture, our glide once the fingers lift, a bounce at an
	// end): UiWindow's on Linux's Wayland, whose touchpads say when they lift
	public var kinetic = false;
	// a touch's drag past a scroller's end stretches it, as Android 12's
	// (Stretch: UiWindow's on Android)
	public var stretch = false;
	// how long a scroll by the keys eases (seconds; 0: at once)
	public var scrollDuration = 0.15;

	final trackpad:Trackpad;
	final stretcher:Stretch;
	// (the scrollers' glides: a wheel's notches, the keys' scrolls)
	final glides = new Map<Node, ScrollGlide>();
	// (the last wheel's scroller and what it could not scroll, past its end: Stretch's)
	var overNode:Null<Node> = null;
	var overX = 0.0;
	var overY = 0.0;
	// (the scroller a wheel latched to and its last scroll's time: Chromium's half a second)
	var wheelLatch:Null<Node> = null;
	var wheelAt = -1e9;
	// (the scroller the last wheel moved)
	var wheelNode:Null<Node> = null;

	static inline var WHEEL_LATCH = 0.5;

	function new() {
		trackpad = @:privateAccess new Trackpad(this);
		stretcher = @:privateAccess new Stretch(this);
	}

	public function requestFrame() {}

	// scrolls n to x, y at once (a glide stopped)
	public function scrollTo(n:Node, x:Float, y:Float) {
		Scrolling.stopGlide(this, n);
		Scrolling.setScroll(this, n, true, x);
		Scrolling.setScroll(this, n, false, y);
	}

	// (the topmost node under a point)
	function hit(x:Float, y:Float):Null<Node>
		return null;

	// (a step on its clock, called with the time each tick until it returns false)
	function animate(step:Float->Bool) {}

	// (its clock's time now: Ui.now's)
	function clock():Float
		return Ui.now();

	// (whether n is still among its scrollers)
	function has(n:Node):Bool
		return true;

	// (the modifier keys held)
	function held():Int
		return 0;

	// (the tree told of a wheel's move: whether it kept it, no scroll then)
	function heard(target:Node, x:Float, y:Float, dx:Float, dy:Float, eased:Bool, mods:Int):Bool
		return false;

	// a wheel's or a trackpad's scroll at x, y (mods: -1 the keys held; phase,
	// momentum: helder.os.ScrollPhase, time on clock's clock)
	function wheelNow(x:Float, y:Float, deltaX:Float, deltaY:Float, eased:Bool, mods = -1, phase = 0, momentum = 0, time = 0.0) {
		if (mods < 0) mods = held();
		overNode = null;
		overX = overY = 0;
		var phased = (elastic || kinetic) && (phase != 0 || momentum != 0) && mods & Mods.CONTROL == 0;
		var target = hit(x, y);
		if (phased) {
			// (the tree hears the moves, the momentum's too, and may keep them: no scroll then)
			if (target != null && (deltaX != 0 || deltaY != 0) && heard(target, x, y, deltaX, deltaY, false, mods)) return;
			@:privateAccess trackpad.scroll(x, y, deltaX, deltaY, phase, momentum, time);
			return;
		}
		if (target == null) return;
		if (heard(target, x, y, deltaX, deltaY, eased, mods)) return;
		// (a wheel's scrolls latched to the scroller it moved until it rests half a second, as Chromium's: not
		// into one it passes over, nor out of it at its end)
		var latched = wheelLatch != null && clock() - wheelAt < WHEEL_LATCH && has(wheelLatch) ? wheelLatch : null;
		wheelAt = clock();
		if (latched != null) {
			if (Scrolling.canScroll(latched, deltaX, true) || Scrolling.canScroll(latched, deltaY, false))
				Scrolling.wheel(this, latched, deltaX, deltaY, eased);
			else {
				// (at its end: all of it past that end, Stretch's)
				overNode = latched;
				overX = deltaX;
				overY = deltaY;
			}
			return;
		}
		Scrolling.wheel(this, target, deltaX, deltaY, eased);
		wheelLatch = wheelNode;
	}
}
