package helder.ui;

import helder.os.Mods;
import helder.ui.access.Role;
import helder.view.graph.Graph;

// A VirtualScroll over rows of fixed-size cells (UiFlow.VirtualGrid's): as
// many columns of at least cellWidth as fit, widened to fill the row, each
// grid row one of the scroller's. Items are indices into the source (keyOf,
// count); a reflow keeps the first item in view where it was, a refresh
// remakes only the rows whose keys changed. The selection and the focus
// are held by key.
@:allow(helder.ui.view)
class GridScroll extends VirtualScroll {
	@:typescript public final selection:Selection;
	@:typescript public var columns(default, null) = 1;
	public final cellWidth:Float;
	public final cellHeight:Float;
	public final gap:Float;
	public final padding:Float;
	// select mode (a phone's Select): a press toggles its item, a drag sideways selects a run
	@:typescript public var selectMode(get, set):Bool;
	// a cell's node filled for item index (what the source keeps returned), a cell let go
	public var onMakeCell:Null<(Int, Node)->Dynamic>;
	public var onDropCell:Null<(Node, Dynamic)->Void>;

	final keyOf:Int->String;
	final itemCount:Void->Int;
	final input:SelectionInput;
	var pitch = 0.0;
	var innerWidth = -1.0;
	var ready = false;
	var pendingIndex = -1;
	var pendingAlign = "auto";
	var pendingFocus = false;
	var selectionOff:Null<Void->Void>;
	// (the first item before a reflow: it can land partway across its new row)
	var firstItem = 0;
	var anchoredAt = -1.0;
	var drag:Null<GridMarquee>;
	final marquee = new Node("marquee");

	public function new(keyOf:Int->String, count:Void->Int, cellWidth:Float, cellHeight:Float, gap = 4.0, padding = 12.0,
			?selection:Selection, ?tag:String) {
		super(tag ?? "virtual-grid", cellHeight + gap);
		this.keyOf = keyOf;
		itemCount = count;
		this.cellWidth = cellWidth;
		this.cellHeight = cellHeight;
		this.gap = gap;
		this.padding = padding;
		this.selection = selection ?? new Selection(keyOf, count);
		insetTop = insetBottom = padding;
		fixedHeight = cellHeight + gap;
		keep = 0;
		overscan = 0;
		focusableRows = false;
		focusable = true;
		rowRole = Role.Row;
		semantics.role = Role.Table;
		semantics.multiselectable = true;
		style.height = 0;
		style.flexGrow = 1;
		style.minHeight = 0;
		style.minWidth = 0;
		marquee.slot = "grid-marquee";
		marquee.style.position = Absolute;
		marquee.style.pointerEvents = None;
		marquee.semantics = {hidden: true};

		onMakeRow = makeCells;
		onDropRow = (row, data) -> {
			var g:GridRow = data;
			if (onDropCell != null)
				for (j in 0...g.cells.length)
					onDropCell(row.children[j], g.cells[j]);
		};

		input = new SelectionInput(this, this.selection, count, itemAt, nodeAt, moveIndex);
		input.onEmptyClick = this.selection.clear;
		var down = onPointerDown, motion = onPointerMove, cancel = onPointerCancel, key = onKeyDown;
		onPointerDown = e -> {
			down(e);
			if (e.defaultPrevented || e.button != 1 || !e.isPrimary || itemAt(e.target) >= 0) return;
			finishMarquee();
			drag = new GridMarquee(e, scrollY, e.mods & Mods.SHIFT != 0 || SelectionInput.secondary(e.mods));
			if (ui != null && e.target != this) {
				@:privateAccess ui.setPressed(e.target, false);
				@:privateAccess ui.setPressed(this, true);
			}
			capture();
		};
		onPointerMove = e -> {
			motion(e);
			moveMarquee(e);
		};
		onPointerUp = e -> {
			if (e.button != 1 || drag == null || e.pointerId != drag.pointer) return;
			moveMarquee(e);
			finishMarquee();
		};
		onPointerCancel = e -> {
			cancel(e);
			if (drag != null && e.pointerId == drag.pointer) finishMarquee();
		};
		onLostPointerCapture = e -> if (drag != null && e.pointerId == drag.pointer) finishMarquee();
		onKeyDown = e -> {
			if (!e.defaultPrevented && e.key == Key.ESCAPE) finishMarquee();
			key(e);
		};
	}

	inline function get_selectMode():Bool
		return input.selectMode;

	inline function set_selectMode(v:Bool):Bool
		return input.selectMode = v;

	// the source's items changed: rows added or taken off the end, the rows
	// made whose keys changed made again, update given the others' cells
	// (item index, what the source keeps) to write their items
	public function refresh(?update:(Int, Dynamic)->Void) {
		if (!ready) return;
		var restore = focusWithin();
		var n = Std.int(Math.ceil(itemCount() / columns));
		if (n < count) splice(n, count - n, 0) else if (n > count) splice(count, 0, n - count);
		for (r in rows().copy()) {
			var g:GridRow = r.data, start = r.index * columns;
			var same = g.keys.length == Std.int(Math.min(columns, itemCount() - start));
			for (j in 0...g.keys.length)
				if (same && keyOf(start + j) != g.keys[j]) same = false;
			if (!same) splice(r.index, 1, 1) else if (update != null)
				for (j in 0...g.cells.length)
					update(start + j, g.cells[j]);
		}
		if (restore && !focusWithin()) refocus();
		if (ui != null) ui.requestFrame();
	}

	// (the row's geometry and the wrapper of each of its cells)
	function makeCells(row:Int, node:Node):GridRow {
		var start = row * columns;
		var end = Std.int(Math.min(start + columns, itemCount()));
		node.style.flexDirection = Row;
		node.style.alignItems = Start;
		node.style.padding = new Edges(0, padding, 0, padding);
		node.style.columnGap = gap;
		var g = new GridRow();
		for (i in start...end) {
			var cell = new Node("cell");
			cell.slot = "grid-cell";
			cell.style.width = pitch - gap;
			cell.style.height = cellHeight;
			cell.style.flexShrink = 0;
			cell.style.minWidth = 0;
			cell.focusable = true;
			cell.tabIndex = -1;
			cell.semantics = {role: Role.Cell, posInSet: i + 1, setSize: itemCount()};
			node.append(cell);
			var k = keyOf(i);
			SelectionInput.decorate(cell, selection, k);
			g.keys.push(k);
			g.cells.push(onMakeCell == null ? null : onMakeCell(i, cell));
		}
		return g;
	}

	function itemAt(target:Node):Int {
		var row = rowOf(target);
		if (row == null || row.node == target) return -1;
		var cell = target;
		while (cell.parent != row.node)
			cell = cell.parent;
		return row.index * columns + row.node.indexOf(cell);
	}

	function nodeAt(i:Int):Null<Node> {
		var row = rowAt(Std.int(i / columns));
		return row == null ? null : row.node.children[i % columns];
	}

	// scrolls to item index ("start", "center", "end"; "auto": as little as shows it)
	@:typescript override public function scrollToIndex(index:Int, align = "auto") {
		if (!ready) {
			pendingIndex = index < 0 ? 0 : index;
			pendingAlign = align;
			pendingFocus = false;
			return;
		}
		if (itemCount() > 0) super.scrollToIndex(Std.int(clampIndex(index) / columns), align);
	}

	// focuses item index, scrolled into view, the focus ring shown
	@:typescript override public function focusIndex(index:Int) {
		scrollToIndex(index);
		if (!ready) {
			pendingFocus = true;
			return;
		}
		if (itemCount() == 0) return;
		index = clampIndex(index);
		selection.moveFocus(index);
		if (ui != null) {
			ui.focusVisible = true;
			ui.setFocus(nodeAt(index) ?? this, false);
		}
	}

	function clampIndex(i:Int):Int
		return Std.int(Math.max(0, Math.min(itemCount() - 1, i)));

	function moveIndex(i:Int, key:Int):Null<Int> {
		var page = Std.int(Math.max(1, Math.floor(viewHeight() / fixedHeight))) * columns;
		return switch key {
			case Key.LEFT: i < 0 ? 0 : i - 1;
			case Key.RIGHT: i < 0 ? 0 : i + 1;
			case Key.UP: i < 0 ? 0 : i - columns;
			case Key.DOWN: i < 0 ? 0 : i + columns;
			case Key.HOME: 0;
			case Key.END: itemCount() - 1;
			case Key.PAGE_UP: i < 0 ? 0 : i - page;
			case Key.PAGE_DOWN: i < 0 ? 0 : i + page;
			case _: null;
		}
	}

	override function settle():Bool {
		var w = Math.max(0, width - style.borderEdges.horizontal - padding * 2);
		var changed = false;
		var cols = Std.int(Math.max(1, Math.floor((w + gap) / (cellWidth + gap))));
		pitch = (w + gap) / cols;
		if (!ready || cols != columns) {
			reflow(cols);
			changed = true;
		} else if (w != innerWidth) {
			for (row in rows())
				for (cell in row.node.children)
					cell.style.width = pitch - gap;
			changed = true;
		}
		innerWidth = w;
		if (super.settle()) changed = true;
		if (drag != null && drag.started && drag.scroll != scrollY) {
			updateMarquee(drag);
			changed = true;
		}
		cellTabStops();
		return changed;
	}

	function reflow(cols:Int) {
		var from = firstVisible();
		var delta = from < 0 ? -insetTop : scrollY - rowOffset(from);
		// (the same scroll as the last reflow left: its first item, not the row's)
		if (scrollY != anchoredAt || from < 0) firstItem = from < 0 ? 0 : from * columns;
		var restore = focusWithin();
		finishMarquee();
		firstItem = clampIndex(firstItem);
		columns = cols;
		ready = true;
		var y = insetTop + Std.int(firstItem / columns) * fixedHeight + delta;
		resetWindow(Std.int(Math.ceil(itemCount() / columns)), y);
		anchoredAt = scrollY;
		if (pendingIndex >= 0) {
			var i = pendingIndex;
			pendingIndex = -1;
			if (pendingFocus) focusIndex(i) else scrollToIndex(i, pendingAlign);
		} else if (restore) refocus();
	}

	// (the focus back on the focused item's cell if shown, else the grid)
	function refocus() {
		if (ui == null) return;
		var i = selection.focusIndex(), row = i < 0 ? -1 : Std.int(i / columns);
		ui.setFocus(row >= first && row < end ? nodeAt(i) ?? this : this, false);
	}

	// (one Tab stop: the focused key's cell if made and shown, else the first in view)
	function cellTabStops() {
		var stop:Null<Node> = null;
		var row = rowAt(firstVisible());
		if (row != null) stop = row.node.children[0];
		for (r in rows())
			if (r.index >= first && r.index < end) {
				var g:GridRow = r.data;
				for (j in 0...g.keys.length)
					if (selection.focus != null && g.keys[j] == selection.focus) stop = r.node.children[j];
			}
		tabIndex = stop == null ? 0 : -1;
		for (r in rows())
			for (cell in r.node.children)
				cell.tabIndex = cell == stop ? 0 : -1;
	}

	function moveMarquee(e:Event) {
		var d = drag;
		if (d == null || e.pointerId != d.pointer) return;
		d.x = e.localX;
		d.y = e.localY;
		if (!d.started) {
			if (!SelectionInput.dragged(d.x, d.y, d.fromX, d.fromY)) return;
			d.started = true;
			if (d.additive) d.base = selection.retainedKeys();
			append(marquee);
			Clock.addFor(this, t -> autoScroll(d, t));
		}
		updateMarquee(d);
	}

	function finishMarquee() {
		if (drag == null) return;
		drag = null;
		if (marquee.parent == this) remove(marquee);
	}

	// (within 32 of the top or bottom the view scrolls, faster further out)
	function autoScroll(d:GridMarquee, time:Float):Bool {
		if (drag != d || ui == null) return false;
		var elapsed = d.time < 0 ? 0 : Math.min(time - d.time, 0.05);
		d.time = time;
		var edge = Math.min(32, height / 2);
		var outside = d.y < edge ? d.y - edge : Math.max(0, d.y - (height - edge));
		if (outside != 0)
			scrollY = Math.max(0, Math.min(extent() - viewHeight(), scrollY + Math.max(-64, Math.min(64, outside)) * 18 * elapsed));
		return true;
	}

	// (the rectangle in the content, the cells it crosses counted, not looked for: rows not made too)
	function updateMarquee(d:GridMarquee) {
		var x = Math.max(0, Math.min(width, d.x));
		d.scroll = scrollY;
		var y = Math.max(0, Math.min(viewHeight(), d.y)) + scrollY;
		var left = Math.min(x, d.fromX), right = Math.max(x, d.fromX);
		var top = Math.min(y, d.contentY), bottom = Math.max(y, d.contentY);
		marquee.style.left = left - style.borderEdges.left;
		marquee.style.top = top - style.borderEdges.top;
		marquee.style.width = right - left;
		marquee.style.height = bottom - top;

		var keys = d.base.copy();
		if (pitch > gap && fixedHeight > 0) {
			var x0 = left - padding - style.borderEdges.left, x1 = right - padding - style.borderEdges.left;
			var y0 = top - padding - style.borderEdges.top, y1 = bottom - padding - style.borderEdges.top;
			// (start after the cells ending before the rectangle, stop at the cells starting after it)
			var c0 = Std.int(Math.max(0, Math.floor((x0 + gap) / pitch)));
			var c1 = Std.int(Math.min(columns, Math.ceil(x1 / pitch)));
			var r0 = Std.int(Math.max(0, Math.floor((y0 + gap) / fixedHeight)));
			var r1 = Std.int(Math.min(count, Math.ceil(y1 / fixedHeight)));
			var n = itemCount();
			for (r in r0...r1)
				for (c in c0...c1) {
					var i = r * columns + c;
					if (i < n) keys.push(keyOf(i));
				}
		}
		selection.setKeys(keys);
	}

	override function attach(u:Null<Ui>) {
		if (ui == u) return;
		finishMarquee();
		if (selectionOff != null) {
			selectionOff();
			selectionOff = null;
		}
		super.attach(u);
		if (u != null) Graph.root(off -> {
			selectionOff = off;
			Graph.renderEffect(() -> selection.version(), _ -> {
				for (r in rows()) {
					var g:GridRow = r.data;
					for (j in 0...g.keys.length)
						SelectionInput.decorate(r.node.children[j], selection, g.keys[j]);
				}
				cellTabStops();
				u.requestFrame();
			});
		});
	}
}

// (a grid row made: its cells' keys and what the source keeps with each)
private class GridRow {
	public final keys:Array<String> = [];
	public final cells:Array<Dynamic> = [];

	public function new() {}
}

// (a marquee's pointer, its origin in the content and its last position in the view)
private class GridMarquee {
	public final pointer:Int;
	public final fromX:Float;
	public final fromY:Float;
	public final contentY:Float;
	public final additive:Bool;
	public var x:Float;
	public var y:Float;
	public var started = false;
	public var time = -1.0;
	public var scroll = 0.0;
	public var base:Array<String> = [];

	public function new(e:Event, scroll:Float, additive:Bool) {
		pointer = e.pointerId;
		x = fromX = e.localX;
		y = fromY = e.localY;
		contentY = y + scroll;
		this.additive = additive;
	}
}
