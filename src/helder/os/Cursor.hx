package helder.os;

// The pointer's shape over a window (Window.cursor): the system's own on
// each platform (X11's cursor font, Win32's IDC_ ones, NSCursor, CSS's names).
// helder.ui's nodes take it too (Style.cursor, ui's Cursor), with Auto.
enum abstract Cursor(String) {
	// (a node's: its parent's; a window shows Default for it)
	var Auto = "auto";
	var Default = "default";
	// a link or a button: a hand
	var Pointer = "pointer";
	// text: an I-beam
	var Text = "text";
	var Crosshair = "crosshair";
	var Move = "move";
	var NotAllowed = "not-allowed";
	// resizing left and right, up and down
	var ResizeEW = "ew-resize";
	var ResizeNS = "ns-resize";
	// something that can be dragged, and being dragged: an open and a closed hand
	var Grab = "grab";
	var Grabbing = "grabbing";

	// (the back ends' tables: Default 0 to Grabbing 9, Auto Default's)
	@:noCompletion public function index():Int
		return switch (cast this : Cursor) {
			case Pointer: 1;
			case Text: 2;
			case Crosshair: 3;
			case Move: 4;
			case NotAllowed: 5;
			case ResizeEW: 6;
			case ResizeNS: 7;
			case Grab: 8;
			case Grabbing: 9;
			case _: 0;
		}

	@:noCompletion @:from static macro function ofString(e:haxe.macro.Expr.ExprOf<String>):haxe.macro.Expr
		return helder.os.Literal.of(e);
}
