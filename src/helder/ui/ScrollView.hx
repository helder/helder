package helder.ui;

// A scroller as a platform's own scroll view drives it (Ui.nativeScroll):
// its padding box on screen (window points, its ancestors' scrolling
// applied), its content's size (the box and how far it scrolls on each
// axis) and its offsets from its start (0 to how far it scrolls, right to
// left too). Ui.scrollViews lists them, in paint order.
@:allow(helder.ui)
class ScrollView {
	public final node:Node;
	public var x(default, null) = 0.0;
	public var y(default, null) = 0.0;
	public var width(default, null) = 0.0;
	public var height(default, null) = 0.0;
	public var contentWidth(default, null) = 0.0;
	public var contentHeight(default, null) = 0.0;
	public var offsetX(default, null) = 0.0;
	public var offsetY(default, null) = 0.0;
	// the axes it scrolls on (overflow Scroll and overflowing)
	public var scrollsX(default, null) = false;
	public var scrollsY(default, null) = false;
	// its scrollbars shown (scrollbar-width not none)
	public var bars(default, null) = true;
	// inside a popup (over the tree)
	public var layer(default, null) = false;
	// under a popup: the tree's while one is open (a platform's view then takes no input)
	public var covered(default, null) = false;
	// the nearest scroller listed around it (null: none)
	public var parent(default, null):Null<ScrollView> = null;
	// (a number of its own, for a platform's side)
	public final id:Int = ++ids;

	static var ids = 0;
	// (the last Ui.scrollViews that listed it)
	var pass = 0;

	function new(node:Node)
		this.node = node;
}
