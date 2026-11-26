package helder.ui;

// What a node asks of its glass group (GlassGroup, made by GlassGroup.of):
// Node names only this, so that a program of nodes without glass (a 3D
// scene's overlay, a static Linux build) links none of glass's drawing
interface GlassGrouping {
	var spacing(default, set):Float;
	function attach(u:Null<Ui>):Void;
	function attached(u:Null<Ui>):Void;
	function sync():Void;
	function paint(canvas:Canvas):Void;
	function dispose():Void;
}
