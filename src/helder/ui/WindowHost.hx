package helder.ui;

import helder.os.Rect;
import helder.os.DragOperation;

// The window a Ui is drawn in, for what draws the window's own buttons
// (WindowControls) in an inset title bar (UiWindow's; null: none, a story's
// screen, a test's Ui)
interface WindowHost {
	// "system": the system's own buttons over the content (macOS's), placed
	// by the app; "windows" or "linux": the app draws them; "none": not
	// inset (the system's title bar), the browser, a phone
	function controls():String;
	// the system's buttons' box (points; null: none)
	function systemControls():Null<Rect>;
	// the system's buttons' top left moved to x, y (points)
	function placeControls(x:Float, y:Float):Void;
	function minimize():Void;
	function maximized():Bool;
	function maximize(on:Bool):Void;
	// a system drag of files from the press (Window.dragFiles)
	function dragFiles(paths:Array<String>, image:Null<helder.image.Image>, offsetX:Float, offsetY:Float, allowed:Array<DragOperation>,
		done:DragOperation->Void):Bool;
	function close():Void;
}
