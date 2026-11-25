package helder.os;

enum abstract EventKind(String) {
	var None = "none";
	// the window's close button: the window stays open until close()
	var Close = "close";
	var Resize = "resize";
	var KeyDown = "key-down";
	var KeyUp = "key-up";
	var MouseMove = "mouse-move";
	var MouseDown = "mouse-down";
	var MouseUp = "mouse-up";
	// a character typed (after KeyDown: with Shift, the layout and dead keys
	// applied), one code point each (an input method's commit: at once); not
	// with Control, Alt (Option) or the Command key held, nor for the keys
	// without a character
	var TextInput = "text-input";
	// the system lost the window's pixels (X11's Expose, Win32's WM_PAINT):
	// draw a frame again, even with nothing changed
	var Redraw = "redraw";
	// an input method's composition (the text not committed yet, shown where
	// it is typed): text, the caret in it (x, UTF-16); empty: it ended
	// (committed: TextInput follows; or cancelled). In the browser, on
	// macOS, Windows (TSF), Wayland (text-input-v3) and Android, while
	// Window.startTextInput is on
	var TextEditing = "text-editing";
	// the wheel or a trackpad: deltaX, deltaY in pixels (as a browser's wheel
	// event: positive scrolls toward the right and the bottom), at the
	// pointer (x, y); a wheel's notch is 40 pixels, a trackpad's motion
	// exact
	var Scroll = "scroll";
	// the window's scale changed (Window.scale: another display's DPI);
	// a Resize follows if its size in pixels changed too
	var ScaleChange = "scale-change";
	// Android: the system took the window (the app went to the background):
	// its Surface is lost (Surface.lost) and nothing is drawn until Resume;
	// iOS: the app went to the background (the Surface stays), no frames
	var Suspend = "suspend";
	// Android: a new window for the Surface (Surface.reattach), drawn to
	// again; iOS: back in the foreground
	var Resume = "resume";
	// a pointer (Event.pointer: the mouse, a finger, a pen; helder.os.Pointers)
	// went down, moved, went up, or was cancelled: the system took it (a
	// call, a system gesture, the browser panning the page), an ending that
	// must not tap and lets go of what it held. The mouse's after its
	// MouseDown, MouseMove and MouseUp (its first button down, its last up,
	// and every move: hovering too)
	var PointerDown = "pointer-down";
	var PointerMove = "pointer-move";
	var PointerUp = "pointer-up";
	var PointerCancel = "pointer-cancel";
	// files dragged onto the window and dropped there: Event.files, their
	// paths, at x, y (pixels from the top left). Windows' WM_DROPFILES,
	// macOS's dragging destination (file URLs), X11's XDND (text/uri-list);
	// not in the browser, on Android or iOS yet
	var Drop = "drop";
	// an input method's edit of the text around where text is typed
	// (Window.textContext's): x...y of it (UTF-16 indices) replaced by
	// text, the caret after it (Windows' TSF, Wayland's
	// delete_surrounding_text); an insertion at the caret comes as TextInput
	var TextReplace = "text-replace";
	// an input method's selection of that text: x...y (UTF-16; Android's
	// InputConnection.setSelection, a cursor moved by the keyboard)
	var TextSelect = "text-select";

	// (the web's events give them by index, in this order)
	@:noCompletion public static final ALL:Array<EventKind> = [None, Close, Resize, KeyDown, KeyUp, MouseMove, MouseDown, MouseUp, TextInput, Redraw, TextEditing, Scroll, ScaleChange, Suspend, Resume, PointerDown, PointerMove, PointerUp, PointerCancel, Drop, TextReplace, TextSelect];

	@:noCompletion @:from static macro function ofString(e:haxe.macro.Expr.ExprOf<String>):haxe.macro.Expr
		return helder.os.Literal.of(e);
}
