package helder.view;

// An error about an element markup wrote (an attribute it has no setter
// for, a value it can't take), thrown where the element is built: where in
// the file it was written when the build knows (dev and headless builds:
// Source), so that a preview host can say it beside the message
class MarkupError extends haxe.Exception {
	public final at:Null<Source>;

	public function new(message:String, ?at:Source) {
		super(message);
		this.at = at;
	}
}
