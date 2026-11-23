package helder.ui.draw;

import helder.ui.Node;

// A subtree painted into a display list of its own (Ui.paint), kept from
// frame to frame while nothing it paints changes: a scroller's content,
// below its clip and above its scroll translation, so that a scroll only
// moves where it is drawn; a node whose transform or opacity moves, so
// that only they change; the window's tree, the root, holding the others.
// A scroller's is recorded over what is seen and a viewport each way,
// recorded again once a scroll goes past that. On the GPU a layer that
// holds no other and draws nothing anew each frame is drawn from tiles of
// its own (Renderer.layerTiles), kept while it is unchanged.
class Layer {
	// its node (null: the root's), and whether it is that scroller's content
	public final node:Null<Node>;
	public final scroll:Bool;
	public final list = new DisplayList();
	// (the layer whose list holds it)
	@:allow(helder.ui) var parent:Null<Layer> = null;
	// (what it paints changed; recorded again each frame: what it paints asks for frames, or moves on its own)
	@:allow(helder.ui) var dirty = true;
	@:allow(helder.ui) var volatile = false;
	// (what it was recorded over, in its coordinates; the window's state then: Ui.paintKey)
	@:allow(helder.ui) var x0 = 0.0;
	@:allow(helder.ui) var y0 = 0.0;
	@:allow(helder.ui) var x1 = 0.0;
	@:allow(helder.ui) var y1 = 0.0;
	@:allow(helder.ui) var key = -1;
	// (the paint it was last recorded in)
	@:allow(helder.ui) var recordedAt = -1;
	// (under visibility hidden where it was recorded, and in its parent's list now)
	@:allow(helder.ui) var hidden = false;
	@:allow(helder.ui) var hiddenIn = false;
	// (bumped as what it shows changes: recorded again, a layer it holds moved; its tiles' then)
	@:allow(helder.ui) var stamp = 0;
	// (bumped only as what it paints changes, not as it is recorded over more: tiles drawn before stand)
	@:allow(helder.ui) var content = 0;
	// (its sticky nodes' scrollers and their offsets as recorded: recorded again when they scroll)
	@:allow(helder.ui) final sticky:Array<Node> = [];
	@:allow(helder.ui) final stuck:Array<Float> = [];
	// (the paint it last moved in: a scroll, a transform, an opacity; its offsets then)
	@:allow(helder.ui) var movedAt = -1000;
	@:allow(helder.ui) var lastX = 0.0;
	@:allow(helder.ui) var lastY = 0.0;
	// (it moved in the last few paints: its tiles drawn where they fall, not drawn again)
	@:allow(helder.ui) var moving = false;
	// (a scroller's background under its content, opaque, where nothing
	// else is (no image, no inset shadow; 0: not so): its tiles drawn over it)
	@:allow(helder.ui) var backdrop = 0;
	// (what an animated node's layer paints, before its transform: its tiles')
	@:allow(helder.ui) var bx0 = 0.0;
	@:allow(helder.ui) var by0 = 0.0;
	@:allow(helder.ui) var bx1 = 0.0;
	@:allow(helder.ui) var by1 = 0.0;
	// (the record it was last recorded in: Ui.ticks then, what its nodes' entries are of)
	@:allow(helder.ui) var tick = -1;
	// (where it was last drawn, for a window kept between frames (Ui.paint's
	// damage): its matrix to the window, its opacity, the window's pixels it
	// covered; a scroller's scrollbars as drawn then)
	@:allow(helder.ui) final drawn:Array<Float> = [];
	@:allow(helder.ui) var bars:Null<DisplayList> = null;

	public function new(node:Null<Node>, scroll:Bool) {
		this.node = node;
		this.scroll = scroll;
	}

	// whether it covers x0, y0, x1, y1 as recorded
	@:allow(helder.ui) inline function covers(x0:Float, y0:Float, x1:Float, y1:Float):Bool
		return x0 >= this.x0 && y0 >= this.y0 && x1 <= this.x1 && y1 <= this.y1;

	// (what it shows changed: its tiles', its parents' too)
	@:allow(helder.ui) function bump() {
		var l = this;
		while (l != null) {
			l.stamp++;
			l = l.parent;
		}
	}

	// whether it can be drawn from tiles: it holds no layer, draws nothing anew each frame
	@:allow(helder.ui) inline function tiled():Bool
		return !volatile && list.layers == 0 && list.live == 0 && list.length > 0;
}
