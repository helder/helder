package helder.ui;

#if (target.name == "hxmc")
import hxmc.unsafe.Ptr;
#else
// (a build of no system's layers: Eval's, the tests')
private typedef Ptr = Dynamic;
#end

// A system layer of a node's own between what helder draws:
// where the system composites the window's layers (macOS and iOS:
// helder.ui.draw.CaLayers), placed at the node's box in its paint order,
// clipped by the scrollers around it (rounded ones too), under what is
// drawn over it, moved with its scroller and its transform in each frame's
// transaction. A layer (a CALayer: a video's, one drawn by the node itself)
// goes in the layer tree; a view (an NSView, a UIView: a native field, a
// web view) is a host view of its platform's, its view inside it at the
// node's box, so that its focus, input and accessibility stay the
// system's. Elsewhere, and while the system's layers are off, it is not
// placed: the node's to place or draw (Node.systemLayer)
@:hxmc.unsafe(gc)
class LayerSlot {
	// the CALayer, or the host view
	public final handle:Ptr;
	// a host view (its view in it: inner), not a layer
	public final view:Bool;
	public var inner:Ptr;
	// at the node's content box (else its padding box)
	public var content = true;
	// shown (else hidden where it would be)
	public var shown = true;

	public function new(handle:Ptr, view = false) {
		this.handle = handle;
		this.view = view;
		inner = #if (target.name == "hxmc") Ptr.nil() #else null #end;
	}
}
