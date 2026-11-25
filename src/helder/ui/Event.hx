package helder.ui;

// An event as Ui dispatches it: to the target, then (unless stopped) to
// each ancestor (current), except PointerEnter, PointerLeave, Focus and
// Blur, which each node gets for itself.
class Event {
	public final type:EventType;
	public final target:Node;
	// the node whose handler runs
	public var current(default, null):Node;
	// the pointer in window pixels (pointer events; else where it was last)
	public final x:Float;
	public final y:Float;
	// pointer buttons: 1 left, 2 middle, 3 right (a finger, a pen: 1)
	public var button = 0;
	// pointer events: which pointer (0 the mouse, else helder.os's slot of a
	// finger or a pen: Pointer.id), its type, its pressure (0 to 1), and
	// whether it is the primary one (the mouse, the first finger down)
	public var pointerId = 0;
	public var pointerType:helder.os.PointerType = Mouse;
	public var pressure = 0.0;
	public var isPrimary = true;
	// KeyDown, KeyUp: the key (Key) and the modifiers (helder.os.Mods)
	public var key = 0;
	public var mods:helder.os.Mods = helder.os.Mods.NONE;
	// TextInput: the characters typed (an IME's composed text, too); Input: the field's text;
	// Composition: an input method's text not committed yet (empty: none)
	public var text = "";
	// Composition: the caret in text (UTF-16)
	public var caret = 0;
	// Wheel: the scroll in pixels (down and right positive)
	// drag and drop: what is dragged (the source's dragData); DragEnd: whether it was dropped
	public var data:Dynamic = null;
	public var dropped = false;
	public var deltaX = 0.0;
	public var deltaY = 0.0;
	// a wheel's deltas to ease rather than jump to (a mouse's notches on macOS)
	public var eased = false;
	public var stopped(default, null) = false;
	// the default action (Tab moving the focus, the wheel scrolling) is not taken
	public var defaultPrevented(default, null) = false;

	// (made by of: a page's code using an event's fields keeps its class,
	// its constructor with it, and so none of a Node's methods)
	function new(type:EventType, target:Node, x:Float, y:Float) {
		this.type = type;
		this.target = target;
		this.x = x;
		this.y = y;
	}

	// an event of type at target, the pointer at x, y in the window's coordinates
	public static function of(type:EventType, target:Node, x:Float, y:Float):Event
		return new Event(type, target, x, y).at(target);

	// the pointer relative to current's border box (Node.localX: through
	// scrolling and transforms; fields, so that a handler's untyped event
	// reads them too)
	public var localX(default, null) = 0.0;
	public var localY(default, null) = 0.0;

	public inline function stop()
		stopped = true;

	public inline function preventDefault()
		defaultPrevented = true;

	@:allow(helder.ui.Ui) function at(n:Node):Event {
		current = n;
		localX = n.localX(x, y);
		localY = n.localY(x, y);
		return this;
	}
}
