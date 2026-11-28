package helder.ui.controls;

import helder.ui.Clock;
import helder.ui.Node;

// A control's states as amounts that ease between 0 and 1 (hover, pressed,
// checked, focus: the keyboard's ring, open), each over its look's time
// for it, on its window's clock; under reduced motion they jump. What a
// recipe's states blend (colours, opacity, transforms) eases the same way,
// through the parts' transitions (Look); these are for what draws itself:
// a replaced rendering.
class Eased {
	public static inline var HOVER = 0;
	public static inline var PRESSED = 1;
	public static inline var CHECKED = 2;
	public static inline var FOCUS = 3;
	public static inline var OPEN = 4;

	public var hover(get, never):Float;
	public var pressed(get, never):Float;
	public var checked(get, never):Float;
	public var focus(get, never):Float;
	public var open(get, never):Float;
	// called while they move (a shader's node asks for its frame)
	public var onChange:Null<Void->Void> = null;
	// the node whose window's clock they move on
	public var node:Null<Node> = null;

	final values = [0.0, 0.0, 0.0, 0.0, 0.0];
	final from = [0.0, 0.0, 0.0, 0.0, 0.0];
	final to = [0.0, 0.0, 0.0, 0.0, 0.0];
	final since = [0.0, 0.0, 0.0, 0.0, 0.0];
	final times:Array<Float>;
	var ticking = false;
	final step:Float->Bool;

	// times: each state's seconds (HOVER... OPEN)
	public function new(times:Array<Float>) {
		this.times = times;
		step = tick;
	}

	inline function get_hover():Float
		return values[HOVER];

	inline function get_pressed():Float
		return values[PRESSED];

	inline function get_checked():Float
		return values[CHECKED];

	inline function get_focus():Float
		return values[FOCUS];

	inline function get_open():Float
		return values[OPEN];

	// a state's amount (HOVER... OPEN)
	public inline function get(state:Int):Float
		return values[state];

	// where a state is going: 1 while it holds; at once without moving
	// (a control's first state, reduced motion)
	public function set(state:Int, on:Bool, now = false) {
		var target = on ? 1.0 : 0.0;
		if (to[state] == target && !now) return;
		to[state] = target;
		if (now || Clock.reducedMotion || times[state] <= 0) {
			values[state] = target;
			from[state] = target;
			if (onChange != null) onChange();
			return;
		}
		from[state] = values[state];
		since[state] = Clock.now;
		if (!ticking) {
			ticking = true;
			if (node != null) Clock.addFor(node, step) else Clock.add(step);
		}
	}

	function tick(now:Float):Bool {
		var moving = false;
		for (k in 0...values.length) {
			if (values[k] == to[k]) continue;
			// (the share of a whole move: a partial one takes its part of the time)
			var span = Math.abs(to[k] - from[k]) * times[k], t = span <= 0 ? 1 : (now - since[k]) / span;
			if (t >= 1) values[k] = to[k] else {
				var e = 1 - Math.pow(1 - t, 3);
				values[k] = from[k] + (to[k] - from[k]) * e;
				moving = true;
			}
		}
		if (onChange != null) onChange();
		ticking = moving;
		return moving;
	}
}
