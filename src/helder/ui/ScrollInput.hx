package helder.ui;

// An input as the compositor takes it (ScrollMirror.input), in the
// window's points: a wheel's or a trackpad's scroll (its phases, its time:
// ms on the system's clock), a finger's down, move, up or cancel (id, its
// time), the mouse's button (key: 1 the left) and moves, a key (key, mods:
// Mods). UiEvents.route fills one from a window's event.
@:allow(helder.ui)
class ScrollInput {
	public var kind:ScrollInputKind = Wheel;
	public var x = 0.0;
	public var y = 0.0;
	public var dx = 0.0;
	public var dy = 0.0;
	public var eased = false;
	public var mods = 0;
	public var phase = 0;
	public var momentum = 0;
	public var time = 0.0;
	public var id = -1;
	public var key = 0;
	// the gesture it is of (route's)
	public var gesture(default, null) = 0;
	// (the scroll keys' start: the focus's scroller or the pointer's)
	var node:Null<Node> = null;
	// (a touch the program has: it stops the compositor's glide, as any new touch)
	var stopOnly = false;

	public function new() {}
}

enum abstract ScrollInputKind(Int) {
	var Wheel;
	var Down;
	var Move;
	var Up;
	var Cancel;
	var MouseDown;
	var MouseMove;
	var MouseUp;
	var Key;
	// (the mouse's, on a scrollbar: its thumb pressed, dragged, let go)
	var Press;
	var Drag;
	var Release;
}
