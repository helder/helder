package helder.ui;

enum abstract EventType(String) {
	var PointerDown = "pointer-down";
	var PointerUp = "pointer-up";
	var PointerMove = "pointer-move";
	var PointerEnter = "pointer-enter";
	var PointerLeave = "pointer-leave";
	var Click = "click";
	var Wheel = "wheel";
	var KeyDown = "key-down";
	var KeyUp = "key-up";
	var TextInput = "text-input";
	var Composition = "composition";
	var Focus = "focus";
	var Blur = "blur";
	// drag and drop (Node.dragData): the source's start and end, a target's
	// over (preventDefault accepts the drop), leave and drop
	var DragStart = "drag-start";
	var DragOver = "drag-over";
	var DragLeave = "drag-leave";
	var Drop = "drop";
	var DragEnd = "drag-end";
	// the focus came into a node or its subtree, or left it: as Focus and
	// Blur, but bubbling (the DOM's focusin, focusout)
	var FocusIn = "focus-in";
	var FocusOut = "focus-out";
	// a text field's text changed by its user (text: its text now), as the DOM's input
	var Input = "input";
	// a pointer's press taken (Node.onPointerCancel), a capture lost (Node.onLostPointerCapture)
	var PointerCancel = "pointer-cancel";
	var LostPointerCapture = "lost-pointer-capture";
	// its laid-out size changed, or it was first laid out (Node.onResize:
	// target's width and height, after the layout; not bubbling)
	var Resize = "resize";
	// a text field's Enter (its keyboard's Enter key: Done, Next, Go...;
	// text: its text), as a form's submit
	var Submit = "submit";

	@:noCompletion @:from static macro function ofString(e:haxe.macro.Expr.ExprOf<String>):haxe.macro.Expr
		return helder.os.Literal.of(e);
}
