package helder.ui.draw;

import helder.ui.Canvas;
import helder.ui.Node;

// Where a display list is replayed (DisplayList.replay): what can be seen,
// a rectangle in the coordinates of what is drawn there, and the
// translation motion and scrolling put it at (ptx, pty), as Ui's paint had
// them where it recorded the list. The list's cull entries change them as
// that paint did, in the same order and by the same sums, so that a list
// recorded over more than is seen (a scroller's content, a viewport each
// way) gives a canvas exactly the calls a direct paint gives it, and marks
// drawn (Node.drawnAt) the nodes that paint would have. A list's layers and
// what is painted live (scrollbars, matched elements flying) are its host's.
class Walk {
	public var x0 = 0.0;
	public var y0 = 0.0;
	public var x1 = 0.0;
	public var y1 = 0.0;
	public var ptx = 0.0;
	public var pty = 0.0;
	// the paint this is (Node.drawnAt), whether nodes are marked in it (one
	// walk a frame marks, a tile's does not), and whether it draws (one
	// walk a frame does: the first walk under motion does not)
	public var frame = 0;
	public var mark = false;
	public var draw = true;
	public var host:Null<WalkHost> = null;
	// (the rectangles saved, 4 each)
	final saved:Array<Float> = [];

	public function new() {}

	public function set(x0:Float, y0:Float, x1:Float, y1:Float) {
		this.x0 = x0;
		this.y0 = y0;
		this.x1 = x1;
		this.y1 = y1;
	}

	// (everything seen: under a transform, as the paint culls nothing there)
	public inline function all()
		set(-1e9, -1e9, 1e9, 1e9);

	public inline function save() {
		saved.push(x0);
		saved.push(y0);
		saved.push(x1);
		saved.push(y1);
	}

	public inline function restore() {
		var n = saved.length - 4;
		set(saved[n], saved[n + 1], saved[n + 2], saved[n + 3]);
		saved.resize(n);
	}

	// how many rectangles are saved (a walk's start, given back at its end)
	public inline function depth():Int
		return saved.length;

	public inline function unwind(depth:Int)
		saved.resize(depth);

	// (moved by dx, dy: what is seen, back by as much)
	public inline function shift(dx:Float, dy:Float) {
		x0 -= dx;
		x1 -= dx;
		y0 -= dy;
		y1 -= dy;
		ptx += dx;
		pty += dy;
	}

	public inline function clip(x0:Float, y0:Float, x1:Float, y1:Float) {
		this.x0 = Math.max(this.x0, x0);
		this.y0 = Math.max(this.y0, y0);
		this.x1 = Math.min(this.x1, x1);
		this.y1 = Math.min(this.y1, y1);
	}

	// whether a node's ink, widened (Ui's paint: the bounds it tests), is out of sight
	public inline function culls(ax1:Float, ax0:Float, ay1:Float, ay0:Float):Bool
		return ax1 <= x0 || ax0 >= x1 || ay1 <= y0 || ay0 >= y1;
}

// What a display list's walk leaves to the Ui that recorded it
interface WalkHost {
	// a layer the list holds, drawn where it is now (its offsets, its transform)
	function layer(l:Layer, c:Canvas, w:Walk):Void;
	// a scroller's scrollbars (nw, nh: its size as drawn)
	function bars(n:Node, nw:Float, nh:Float, c:Canvas, w:Walk):Void;
	// a node first reached: what its first paint sets off (Style.drawn's)
	function first(n:Node, entering:Bool):Void;
	// a matched element flying, met at x, y; the flights met, drawn over everything
	function flight(n:Node, x:Float, y:Float):Void;
	function flights(c:Canvas, w:Walk):Void;
}
