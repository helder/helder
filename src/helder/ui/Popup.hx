package helder.ui;

// A layer above the tree (Ui.open: a child of Ui.overlay): drawn after the
// tree and over it, hit first, not clipped by the tree's overflow; the
// later opened on top. Anchored to a node of the tree (anchor), it is
// placed by placement (Below: under it, their left edges lined up; Above;
// Right: beside it, their tops lined up; Left), flipped to the other side
// when it does not fit and kept inside the window; Center centres it in
// the window; Point puts its top left at (atX, atY) in the window, flipped
// left or up where it would not fit (a context menu); TopLeft, TopRight,
// BottomLeft and BottomRight put it in that corner of the window, gap from
// its edges (notifications); Manual leaves it to its style (left, top). A modal one
// covers the window (its own style: a backdrop; its content centred, as
// Ui.open makes it) and keeps the keyboard focus inside: Tab cycles in
// it, the tree under it takes no pointer events. onDismiss: asked to close
// by a click outside it (not on its anchor; unless dismissOnOutside is
// false, as an alert dialog) or by Escape; Ui.close closes it and gives the
// focus back to where it was. An anchored one follows its anchor, placed
// again every layout (a window resized, the anchor scrolled). A menu
// (DrawnMenu's) is dismissed as the platforms' menus are instead: by a
// window's resize, and by a press outside it that goes no further (not
// delivered beneath, its release neither).
class Popup extends Node {
	public var anchor:Null<Node>;
	public var placement:Placement = Below;
	// the space between the anchor and the popup
	public var gap = 4.0;
	// Point's place, in window pixels
	public var atX = 0.0;
	public var atY = 0.0;
	public var modal = false;
	public var onDismiss:Null<Void->Void>;
	public var dismissOnOutside = true;
	public var menu = false;
	// the focus when it opened (given back when it closes)
	@:allow(helder.ui.Ui) @:allow(helder.ui.Popups) var returnFocus:Null<Node>;

	public function new(?tag:String) {
		super(tag == null ? "popup" : tag);
		style.position = Absolute;
	}
}
