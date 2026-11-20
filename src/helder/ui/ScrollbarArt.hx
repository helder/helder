package helder.ui;

// A platform's own scrollbars, drawn into the tree (Ui.scrollbarArt, with a
// ScrollbarLook of the platform's: macOS's, helder.ui.draw.MacScrollbarArt):
// their sizes, and their track and thumb drawn where the Ui places them. The
// Ui keeps their state (where the thumb is, its fading, its drag).
interface ScrollbarArt {
	// [the always-shown track's thickness, the thumb's thickness, the thumb's
	// inset from the box's edge] (points), overlay or always shown
	function metrics(overlay:Bool):Array<Float>;
	// the track (null: none, overlay's) and the thumb ([x, y, width,
	// height], window points), the thumb active (pressed, or the pointer
	// over its track) or not, at alpha
	function paint(canvas:Canvas, vertical:Bool, overlay:Bool, dark:Bool, scale:Float, track:Null<Array<Float>>, thumb:Array<Float>, pressed:Bool,
		alpha:Float):Void;
}
