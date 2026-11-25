package helder.os;

// One event, preallocated and refilled for each dispatch (App.run): copy
// what must outlive the callback.
class Event {
	@:typescript public var kind:EventKind = None;
	@:typescript public var window:Window;
	// KeyDown, KeyUp: the key (an X11 KeySym for now, also on macOS and
	// Windows: Latin-1 keys are their unshifted character code, Escape 0xFF1B)
	@:typescript public var key = 0;
	// the pointer (Mouse*, Pointer*: rounded, from the top left) or the new size (Resize), in pixels
	@:typescript public var x = 0;
	@:typescript public var y = 0;
	// MouseDown, MouseUp: 1 left, 2 middle, 3 right
	@:typescript public var button = 0;
	// Scroll: pixels toward the right and the bottom
	@:typescript public var deltaX = 0.0;
	@:typescript public var deltaY = 0.0;
	// a Scroll's deltas to glide to rather than jump to (helder.ui.ScrollGlide):
	// a mouse wheel's notches where the platform's own views glide them, on
	// macOS and in a browser; not on Windows and Linux, whose own apps jump
	public var eased = false;
	// a trackpad's Scroll: its gesture's phase and its momentum's (ScrollPhase:
	// 0 none, a wheel's; Began, Changed, Ended, Cancelled), and its time (ms,
	// the system's clock: what the momentum is replayed by)
	public var phase = 0;
	public var momentum = 0;
	public var time = 0.0;
	// keys, mouse buttons and scrolls: the modifiers held (Mods: Shift, Control, Alt, Meta: the Windows or Command key)
	@:typescript public var mods:Mods = Mods.NONE;
	// TextInput: the characters; TextEditing: the composition
	public var text = "";
	// Pointer*: the pointer, already updated (its slot: copy what must
	// outlive the callback); button: the mouse's button that changed
	public var pointer:Null<Pointer> = null;
	// Drop: the files' paths (absolute, the system's separators)
	public var files:Array<String> = [];
	// what the compositor made of it (helder.ui.ScrollMirror: 0 the
	// program's, 1 scrolled by it, 2 a question, 3 waiting on one) and its gesture
	@:noCompletion public var routed = 0;
	@:noCompletion public var gesture = 0;

	public function new() {}
}
